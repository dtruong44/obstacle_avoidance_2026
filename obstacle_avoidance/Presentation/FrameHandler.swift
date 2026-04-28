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
        // 1. Grab the depth map we temporarily saved
        guard let depthMap = self.currentDepthMap else { return }
        guard !self.boundingBoxes.isEmpty else { return }
        
        // 2. Lock the depth map in memory so we can safely read its pixels
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let baseAddress = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float16>.self)
        
        // Variables to track our winning "Highest Threat" object
        var highestThreatScore: Float = -1.0
        var mostDangerousBox: BoundingBox? = nil
        var mostDangerousDepth: Float16 = 0.0
        
        // 3. 🚨 THE O(n) LOOP: Evaluate EVERY box on the screen
        for box in self.boundingBoxes {
            
            // Convert the 2D screen coordinates into depth map resolution
            let depthMinX = Int((box.rect.minX / screenRect.width) * CGFloat(width))
            let depthMaxX = Int((box.rect.maxX / screenRect.width) * CGFloat(width))
            let depthMinY = Int((box.rect.minY / screenRect.height) * CGFloat(height))
            let depthMaxY = Int((box.rect.maxY / screenRect.height) * CGFloat(height))
            
            // Clamp values to prevent crashing
            let clampedMinX = max(depthMinX, 0)
            let clampedMaxX = min(depthMaxX, Int(width) - 1)
            let clampedMinY = max(depthMinY, 0)
            let clampedMaxY = min(depthMaxY, Int(height) - 1)
            
            var depthSamples = [Float16]()
            
            // Grab the depth pixels for THIS specific box
            for yVal in clampedMinY...clampedMaxY {
                for xVal in clampedMinX...clampedMaxX {
                    let depthIndex = yVal * Int(width) + xVal
                    depthSamples.append(baseAddress[depthIndex])
                }
            }
            
            let medianDepth = self.findMedian(distances: depthSamples)
            
            // Ignore crazy outliers (closer than 0.2m or further than 8.0m)
            guard medianDepth > 0.2 && medianDepth < 8.0 else { continue }
            
            // ---------------------------------------------------------
            // CALCULATE THE THREAT SCORE FOR THIS BOX
            // ---------------------------------------------------------
            let depthFloat = Float(medianDepth)
            let proximityFactor = max(0, 1.0 - (depthFloat / self.maxDepth))
            
            // Centeredness: box.rect.midX / screenRect.width gives 0.0 to 1.0
            let distanceFromCenter = abs(Float(box.rect.midX / screenRect.width) - 0.5)
            let centerednessFactor = max(0, 1.0 - (distanceFromCenter * 2.0))
            
            // Weights: 70% Distance, 30% Center Position
            let weightDistance: Float = 0.7
            let weightCenter: Float = 0.3
            let currentThreat = (proximityFactor * weightDistance) + (centerednessFactor * weightCenter)
            
            // Is this the most dangerous thing we've seen so far?
            if currentThreat > highestThreatScore {
                highestThreatScore = currentThreat
                mostDangerousBox = box
                mostDangerousDepth = medianDepth
            }
        }
        
        // 4. Ensure we actually found a valid dangerous box
        guard let winningBox = mostDangerousBox else { return }
        
        // ---------------------------------------------------------
        // 🚨 THE LOW-PASS FILTER (EMA) - Applied ONLY to the winner!
        // ---------------------------------------------------------
        let objectIdentifier = winningBox.name
        let alpha: Float16 = 0.3 // 30% new data, 70% historical
        let previousSmoothed = self.smoothedDistances[objectIdentifier] ?? mostDangerousDepth
        let smoothedDepth = (alpha * mostDangerousDepth) + ((1.0 - alpha) * previousSmoothed)
        
        // Save it for the next frame
        self.smoothedDistances[objectIdentifier] = smoothedDepth

        // 5. Update the UI and Threat logic (Main Thread!)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 👉 Publish the single winning box so the UI can draw it
            self.targetedBox = winningBox
            
            // Update state variables with smoothed data
            self.objectDistance = smoothedDepth
            self.stress = self.updateDepth(smoothedDepth)
            self.objectName = winningBox.name
            self.corridorPosition = winningBox.direction
            self.vert = winningBox.vert
            
            // Feed into DecisionBlock
            let objectDetected = DetectedObject(objName: self.objectName,
                                                distance: self.objectDistance,
                                                corridorPosition: self.corridorPosition,
                                                vert: self.vert)
            
            let block = DecisionBlock(detectedObject: objectDetected)
            block.processDetectedObjects()
        }
    }
    
    //New function, replaces commented one above - Bilal.
    func findMedian(distances: [Float16]) -> Float16 {
        let filtered = distances.filter { $0 > 0 && !$0.isNaN }
        guard filtered.count > 0 else { return 0 }
        
        let sorted = filtered.sorted()
        let count = sorted.count
        
        if count % 2 == 1 {
            return sorted[count / 2]
        } else {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
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