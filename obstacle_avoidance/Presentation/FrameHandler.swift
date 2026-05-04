// Obstacle Avoidance App
// FrameHandler.swift
//  Swift file that is used to setup the camera/frame capture. This is what will likely be modified for CoreML implementation.
import SwiftUI
import AVFoundation
import Foundation
import CoreImage
import Vision
import RealityKit
import UIKit
import ARKit
 
class FrameHandler: NSObject, ObservableObject, ARSessionDelegate {
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
    }
    @Published var targetedBox: BoundingBox? = nil
    @Published var frame: CGImage?
    @Published var boundingBoxes: [BoundingBox] = []
    @Published var objectDistance: Float16 = 0.0
    @Published var corridorGeometry: CorridorGeometry? = nil // represents the area created by the corridor
    // Initializing variables related to capturing image.
    public var permissionGranted = true
    //    public let captureSession = AVCaptureSession()
    public let arSession = ARSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var currentDepthMap: CVPixelBuffer? = nil
    private let context = CIContext()
    private var requests = [VNRequest]() // To hold detection requests
    // Tracks the smoothed sitance for each object name to apply the low pass filter
    private var smoothedDistances: [String: Float16] = [:]
    public var detectionLayer: CALayer! = nil
    public let preferredWidthResolution = 1920
    private var sessionConfigured = false
    public var isProcessingFrame = false
    public var boxCoordinates: [CGRect] = []
    public var boxCenter = CGPoint(x: 0, y: 0)
    public var objectName: String = ""
    public var detectionTimestamps: [TimeInterval] = []
    public var objectCoordinates: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    public var confidence: Float = 0.0
    public var corridorPosition: String = ""
    public var vert: String = ""
    private var recentDetections: [DetectionOutput] = []
    public var maxDepth: Float = 12.0
    @Published var stress: CGFloat = 0.0
    var screenRect: CGRect!
    override init() {
        super.init()
        self.checkPermission()
        // Initialize screenRect here before setting up the capture session and detector
        self.screenRect = UIScreen.main.bounds
        
    }
    func stopCamera() {
        arSession.pause()
    }
    
    func startCamera() {
        // Start ARKit session
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth){
            config.frameSemantics.insert(.sceneDepth)
            arSession.delegate = self
            arSession.delegateQueue = sessionQueue
            arSession.run(config)
        }
        setupDetector()
        sessionConfigured = true
    }
    
    func setupDetector() {
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3Tiny", withExtension: "mlmodelc") else {
            print("Error: Model file not found")
            return
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel,
                                                    completionHandler: self.detectionDidComplete)
            self.requests = [objectRecognition]
        } catch let error {
            print("Error loading Core ML model: \(error)")
        }
    }
    func detectionDidComplete(request: VNRequest, error: Error?) {
        // Always unlock the pipeline when we are done so the camera doesn't freeze
        defer { self.isProcessingFrame = false }
        
        guard let results = request.results else { return }
        
        // Process the 2D bounding boxes (Your existing logic)
        self.extractDetections(results)
        
        // Calculate the 3D distance using the depth map we saved earlier
        self.calculateDistanceAndThreat()
    }
    
    func calculateDistanceAndThreat() {
        guard let depthMap = self.currentDepthMap else { return }
        guard !self.boundingBoxes.isEmpty else { return }

        // Lock depth buffer
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let format = CVPixelBufferGetPixelFormatType(depthMap)

        // Select the correct pointer type as we have to extract correct number of bits
        let baseFloat32: UnsafeMutablePointer<Float>?
        let baseFloat16: UnsafeMutablePointer<Float16>?

        switch format {
        case kCVPixelFormatType_DepthFloat32,
             kCVPixelFormatType_DisparityFloat32:
            baseFloat32 = CVPixelBufferGetBaseAddress(depthMap)?
                .assumingMemoryBound(to: Float.self)
            baseFloat16 = nil

        case kCVPixelFormatType_DepthFloat16,
             kCVPixelFormatType_DisparityFloat16:
            baseFloat16 = CVPixelBufferGetBaseAddress(depthMap)?
                .assumingMemoryBound(to: Float16.self)
            baseFloat32 = nil

        default:
            print("Unsupported depth format:", format)
            return
        }

        func readDepthMeters(_ index: Int) -> Float {
            let raw: Float

            if let f32 = baseFloat32 {
                raw = f32[index]
            } else if let f16 = baseFloat16 {
                raw = Float(f16[index])
            } else {
                return .nan
            }

            // Convert disparity → meters
            if format == kCVPixelFormatType_DisparityFloat16 ||
               format == kCVPixelFormatType_DisparityFloat32 {
                return raw > 0 ? 1.0 / raw : .nan
            }

            // Already meters
            return raw
        }

        // Find the median distance as distribution of depth samples are skewed
        func median(_ values: [Float]) -> Float {
            guard !values.isEmpty else { return .nan }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0
                ? (sorted[mid - 1] + sorted[mid]) / 2
                : sorted[mid]
        }

        // Calculate the threat based on the depth samples
        var highestThreat: Float = -1
        var mostDangerousBox: BoundingBox?
        var mostDangerousDepth: Float = 0

        for box in self.boundingBoxes {

            // Convert UI rect to depth map coordinates
            let minX = Int((box.rect.minX / screenRect.width) * CGFloat(width))
            let maxX = Int((box.rect.maxX / screenRect.width) * CGFloat(width))
            let minY = Int((box.rect.minY / screenRect.height) * CGFloat(height))
            let maxY = Int((box.rect.maxY / screenRect.height) * CGFloat(height))

            let x0 = max(minX, 0)
            let x1 = min(maxX, width - 1)
            let y0 = max(minY, 0)
            let y1 = min(maxY, height - 1)

            var samples = [Float]()
            samples.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))

            for y in y0...y1 {
                for x in x0...x1 {
                    let idx = y * width + x
                    let d = readDepthMeters(idx)
                    if d.isFinite { samples.append(d) }
                }
            }

            let depth = median(samples)

            // Ignore invalid or extreme values
            guard depth > 0.2 && depth < 8.0 else { continue }

            // Threat score
            let proximity = max(0, 1.0 - (depth / self.maxDepth))
            let distFromCenter = abs(Float(box.rect.midX / screenRect.width) - 0.5)
            let centered = max(0, 1.0 - distFromCenter * 2.0)

            let threat = proximity * 0.7 + centered * 0.3

            if threat > highestThreat {
                highestThreat = threat
                mostDangerousBox = box
                mostDangerousDepth = depth
            }
        }

        guard let winningBox = mostDangerousBox else { return }

        // LOW-PASS FILTER
        let id = winningBox.name
        let alpha: Float = 0.3
        let prev = Float(self.smoothedDistances[id] ?? Float16(mostDangerousDepth))
        let smoothed = alpha * mostDangerousDepth + (1 - alpha) * prev

        self.smoothedDistances[id] = Float16(smoothed)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.targetedBox = winningBox
            self.objectDistance = Float16(smoothed)
            self.stress = self.updateDepth(Float16(smoothed))
            self.objectName = winningBox.name
            self.corridorPosition = winningBox.direction
            self.vert = winningBox.vert

            let obj = DetectedObject(
                objName: self.objectName,
                distance: self.objectDistance,
                corridorPosition: self.corridorPosition,
                vert: self.vert
            )

            DecisionBlock(detectedObject: obj).processDetectedObjects()
        }
    }

    
    func updateDepth(_ z: Float16) -> CGFloat {
        let d = Float(z)                 // convert once
        let maxD = Float(maxDepth)       // ensure same type
        
        let normalized = max(0, min(1, (1 - (d / maxD))))
        return CGFloat(normalized)
    }
    
    private func createBoundingBoxes(from observation: VNRecognizedObjectObservation, screenRect: CGRect) -> [BoundingBox] {
        var boxes: [BoundingBox] = []
        for label in observation.labels {
            // If the AI is less than 60% sure, throw it in the trash.
            guard label.confidence > 0.30 else { continue }
            
            let labelIdentifier = label.identifier
            let confidence = label.confidence
            let objectBounds = VNImageRectForNormalizedRect(
                observation.boundingBox,
                Int(screenRect.size.width),
                Int(screenRect.size.height)
            )
            let transformedBounds = CGRect(
                x: objectBounds.minX,
                y: screenRect.size.height - objectBounds.maxY,
                width: objectBounds.maxX - objectBounds.minX,
                height: objectBounds.maxY - objectBounds.minY
            )
            if let corridor = self.corridorGeometry{
                let objectPos = CorridorUtils.determinePosition(transformedBounds, corridor: corridor)
                let centerXPercentage = (transformedBounds.midX / screenRect.width) * 100
                let centerYPercentage = (transformedBounds.midY / screenRect.height) * 100
                let direction = DetectionUtils.calculateDirection(centerXPercentage)
                let verticalLocation = DetectionUtils.verticalCorridor(centerYPercentage)
                let box = BoundingBox(
                    classIndex: 0,
                    score: confidence,
                    rect: transformedBounds,
                    name: labelIdentifier,
                    direction: objectPos,
                    vert: verticalLocation
                )
                boxes.append(box)
                
            }
            
        }
        return boxes
    }
    
    /**handleRawModelOutout takes the raw tensors returned by the YOLOV8 model and puts them in a suitable format
     for our NMSHandler function.
     **/
    func handleRawModelOutput(from results: [VNObservation]){
        for result in results{
            
            if let observation = result as? VNCoreMLFeatureValueObservation,
               let multiArray = observation.featureValue.multiArrayValue{
                print("name???: ",observation.featureName)
                let decodedBoxes = YOLODecoder.decodeOutput(multiArray: multiArray, confidenceThreshold: 0.25)
                let filteredIndices = nonMaxSuppressionMultiClass(
                    numClasses: YOLODecoder.labels.count,
                    boundingBoxes: decodedBoxes,
                    scoreThreshold: 0.5,
                    iouThreshold: 0.4,
                    maxPerClass: 5,
                    maxTotal: 20
                )
                let filteredBoxes = filteredIndices.map { decodedBoxes[$0] }
                self.boundingBoxes = filteredBoxes
            }
        }
    }
    
    
    func extractDetections(_ results: [VNObservation]) {
        // Ensure screenRect is initialized
        guard let screenRect = self.screenRect else {
            print("Error: screenRect is nil")
            return
        }
        // Initialize detectionLayer if needed
        if detectionLayer == nil {
            detectionLayer = CALayer()
            updateLayers() // Ensure detectionLayer frame is updated
        }
        // Set up producer consumer for this part and set up unique ids for bounding boxes for tracking
        DispatchQueue.main.async { [weak self] in
            self?.detectionLayer?.sublayers = nil
            // Create an array to store BoundingBox objects
            var boundingBoxResults: [BoundingBox] = []
            // Iterate through all results
            for result in results {
                // Check if the result is a recognized object observation
                if let observation = result as? VNRecognizedObjectObservation {
                    let boxes = self?.createBoundingBoxes(from: observation, screenRect: screenRect)
                    if let boxes = boxes {
                        boundingBoxResults.append(contentsOf: boxes)
                    }
                }
            }
            // Call the NMS function
            self?.boundingBoxes = []
            let filteredResults = NMSHandler.performNMS(on: boundingBoxResults)
            self?.boundingBoxes = filteredResults
        }
    }
    private func calculateAngle(centerX: CGFloat) -> Int { // RDA
        let centerPercentage = (centerX / self.screenRect.width) * 100 // RDA
        return Int(centerPercentage * 360 / 100) // Simplified calculation for the angle // RDA
    }
    
    func updateLayers() {
        detectionLayer?.frame = CGRect(
            x: 0,
            y: 0,
            width: screenRect.size.width,
            height: screenRect.size.height
        )
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        let pixelBuffer = frame.capturedImage

        guard let depthMap = frame.sceneDepth?.depthMap else {
            isProcessingFrame = false
            return
        }

        self.currentDepthMap = depthMap

        sessionQueue.async {
            let requestHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )

            do {
                try requestHandler.perform(self.requests)
            } catch {
                print("Vision failed: \(error)")
                DispatchQueue.main.async {
                    self.isProcessingFrame = false
                }
            }
        }
    }
  
    
    func drawBoundingBox(_ bounds: CGRect) -> CALayer {
        let boxLayer = CALayer()
        if bounds.isEmpty {
            print("Error: Invalid bounds in drawBoundingBox")
            return boxLayer  // Return an empty layer
        }
        return boxLayer // Need to finish
    }
    // Function that checks to ensure that the user has agreed to allow the use of the camera.
    // Unavoidable as this is integral to Apple infrastructure
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has already given permission in the past.
            self.permissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                }
            }
        case .denied, .restricted:
            // The user explicitly said "No" or has parental controls blocking the camera.
            self.permissionGranted = false
            
        default:
            self.permissionGranted = false
        }
    }
    
    // Everything below is me trying to figure out the display of bounding boxes on the screen
    struct CameraPreview: UIViewRepresentable {
        var session: ARSession
        
        func makeUIView(context: Context) -> ARView {
            // Create an ARKit View
            let arView = ARView(frame: .zero)
            
            // Tell the view to use our already-running ARSession
            arView.session = session
            
            return arView
        }
        
        func updateUIView(_ uiView: ARView, context: Context) {}
    }
    
    struct BoundingBoxLayer: UIViewRepresentable {
        var layer: CALayer?
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            return view
        }
        func updateUIView(_ uiView: UIView, context: Context) {
            guard let layer = layer else { return }
            // Remove any existing sublayers
            uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            // Scale the layer to match the size of the preview
            let scale = UIScreen.main.scale
            layer.frame = CGRect(
                x: 0,
                y: 0,
                width: uiView.bounds.width * scale,
                height: uiView.bounds.height * scale
            )
            uiView.layer.addSublayer(layer)  // Add the layer to the view's layer
        }
    }
    struct DetectionOutput{
        let objcetName: String
        let distance: Float16
        let corridorPosition: String
        let id: Int
        let vert: String
    }
}
