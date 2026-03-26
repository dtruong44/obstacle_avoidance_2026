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
        // Grab the depth map we temporarily saved in session(_:didUpdate:)
        guard let depthMap = self.currentDepthMap else { return }
        
        // Find the most confident bounding box to focus on
        guard let largestBox = self.boundingBoxes.max(by: { $0.score < $1.score }) else { return }
        
        // Lock the depth map in memory so we can safely read its pixels
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) } // Unlocks automatically when the function finishes
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Convert the 2D screen coordinates of the box into the depth map's resolution
        let depthMinX = Int((largestBox.rect.minX / screenRect.width) * CGFloat(width))
        let depthMaxX = Int((largestBox.rect.maxX / screenRect.width) * CGFloat(width))
        let depthMinY = Int((largestBox.rect.minY / screenRect.height) * CGFloat(height))
        let depthMaxY = Int((largestBox.rect.maxY / screenRect.height) * CGFloat(height))
        
        // Clamp values to prevent crashing if the bounding box goes slightly off-screen
        let clampedMinX = max(depthMinX, 0)
        let clampedMaxX = min(depthMaxX, Int(width) - 1)
        let clampedMinY = max(depthMinY, 0)
        let clampedMaxY = min(depthMaxY, Int(height) - 1)
        
        // Read the actual memory addresses to get the depth values
        let baseAddress = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float16>.self)
        var depthSamples = [Float16]()
        
        // Loop through every pixel inside the bounding box and grab its depth in meters
        for yVal in clampedMinY...clampedMaxY {
            for xVal in clampedMinX...clampedMaxX {
                let depthIndex = yVal * Int(width) + xVal
                depthSamples.append(baseAddress[depthIndex])
            }
        }
        
        // Use your existing median function to filter out noise
        let medianDepth = self.findMedian(distances: depthSamples)
        
        // Ignore crazy outliers (closer than 0.2m or further than 8.0m)
        guard medianDepth > 0.2 && medianDepth < 8.0 else { return }
        
        // 4. Update the UI and Threat logic (Must be on the Main Thread!)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update your published state variables
            self.objectDistance = medianDepth
            self.stress = self.updateDepth(medianDepth)
            self.objectName = largestBox.name
            self.corridorPosition = largestBox.direction
            self.vert = largestBox.vert
            
            // Feed it into your DecisionBlock threat assessment
            let objectDetected = DetectedObject(objName: self.objectName,
                                                distance: self.objectDistance,
                                                corridorPosition: self.corridorPosition,
                                                vert: self.vert)
            
            let block = DecisionBlock(detectedObject: objectDetected)
            let objectThreatLevel = block.computeThreatLevel(for: objectDetected)
            
            let processedObject = ProcessedObject(objName: self.objectName,
                                                  distance: self.objectDistance,
                                                  corridorPosition: self.corridorPosition,
                                                  vert: self.vert,
                                                  threatLevel: objectThreatLevel)
            
            block.processDetectedObjects(processed: processedObject)
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
                let decodedBoxes = YOLODecoder.decodeOutput(multiArray: multiArray, confidenceThreshold: 0.5)
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
}
extension FrameHandler: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Retrieve the synchronized depth data
        guard let syncedDepthData = synchronizedDataCollection
                .synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection
                .synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData
        else { return }
        // Process the video frame for yolo
        if let cgImage = imageFromSampleBuffer(sampleBuffer: syncedVideoData.sampleBuffer) {
            DispatchQueue.main.async { [unowned self] in
                self.frame = cgImage
            }
        }
        let depthMap = syncedDepthData.depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let width = Float(CVPixelBufferGetWidth(depthMap))
        let height = CVPixelBufferGetHeight(depthMap)
        // Lock the pixel address so we are not moving around too much
        //            ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height)
        // Process all detections from the current frame instead of only the highest-confidence one.
        let boxes = self.boundingBoxes
        guard !boxes.isEmpty else {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            return
        }

        // Get the baseadress of pixel and turn it into a Float16 so it is readable.
        let baseAddress = unsafeBitCast(
            CVPixelBufferGetBaseAddress(depthMap),
            to: UnsafeMutablePointer<Float16>.self
        )
//        let centerX = Float(CGFloat(width) * (boxCenter.x / screenRect.width))
//        let centerY = Float(CGFloat(height) * (boxCenter.y / screenRect.height))
//        let windowSize = 100
//        //Max and min ensure that when the bounty box is far left or far right of screen we do not get nevative value or values taht exceed the width
//        let leftX = max(centerX - Float(windowSize), 0)
//        let rightX = min(centerX + Float(windowSize), width - 1)
//        let bottomY = max(centerY - Float(windowSize), 0)
//        let topY = min(centerY + Float(windowSize), width - 1)
////        var totalDepth: Float16 = 0
//        var count = 0
//        var depthSamples = [Float16]()
//        //For each X and Y value find the depth and add it to a list to find the median value
//        for yVal in Int(bottomY)...Int(topY) {
//            for xVal in Int(leftX)...Int(rightX){
//                depthSamples.append(baseAddress[yVal * Int(width) + xVal])
////                totalDepth += baseAddress[y * Int(width) + x]
//                count += 1
//            }
//        }
        // Pre-compute median depths for each bounding box
        var perBoxDetections: [(box: BoundingBox, medianDepth: Float16)] = []
        var closestDepthForStress: Float16 = 0
        var minDistanceForStress: Float = .greatestFiniteMagnitude

        for box in boxes {
            //  Compute bounding box corners in screen coordinates
            let boxMinX = box.rect.minX
            let boxMaxX = box.rect.maxX
            let boxMinY = box.rect.minY
            let boxMaxY = box.rect.maxY

            // Convert from screen coordinates to depth-map coordinates
            let depthMinX = Int((boxMinX / screenRect.width) * CGFloat(width))
            let depthMaxX = Int((boxMaxX / screenRect.width) * CGFloat(width))
            let depthMinY = Int((boxMinY / screenRect.height) * CGFloat(height))
            let depthMaxY = Int((boxMaxY / screenRect.height) * CGFloat(height))

            // Clamp the values so they never go outside the depth buffer array
            let clampedMinX = max(depthMinX, 0)
            let clampedMaxX = min(depthMaxX, Int(width) - 1)
            let clampedMinY = max(depthMinY, 0)
            let clampedMaxY = min(depthMaxY, Int(height) - 1)

            var depthSamples = [Float16]()
            for yVal in clampedMinY...clampedMaxY {
                for xVal in clampedMinX...clampedMaxX {
                    let depthIndex = yVal * Int(width) + xVal
                    depthSamples.append(baseAddress[depthIndex])
                }
            }

            let medianDepth = self.findMedian(distances: depthSamples)

            // Remove outliers for this box.
            guard medianDepth > 0.2 && medianDepth < 8.0 else {
                continue
            }

            perBoxDetections.append((box: box, medianDepth: medianDepth))

            let distanceFloat = Float(medianDepth)
            if distanceFloat < minDistanceForStress {
                minDistanceForStress = distanceFloat
                closestDepthForStress = medianDepth
            }
        }

        // If none of the boxes produced a valid median depth, bail out.
        guard !perBoxDetections.isEmpty else {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            return
        }

        // Use the closest valid detection to drive the stress indicator.
        stress = self.updateDepth(closestDepthForStress)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        DispatchQueue.main.async {
            // For each detection with a valid median depth, compute and enqueue its threat.
            for (box, medianDepth) in perBoxDetections {
                self.boxCenter = CGPoint(x: box.rect.midX, y: box.rect.midY)
                self.objectName = box.name
                self.objectCoordinates = box.rect
                self.confidence = box.score
                self.corridorPosition = box.direction
                self.objectIDD = box.classIndex
                self.vert = box.vert
                self.objectDistance = medianDepth

                let objectDetected = DetectedObject(
                    objName: self.objectName,
                    distance: self.objectDistance,
                    corridorPosition: self.corridorPosition,
                    vert: self.vert,
                    confidence: self.confidence
                )
                let block = DecisionBlock(detectedObject: objectDetected)
                let objectThreatLevel = block.computeThreatLevel(for: objectDetected)
                let processedObject = ProcessedObject(
                    objName: self.objectName,
                    distance: self.objectDistance,
                    corridorPosition: self.corridorPosition,
                    vert: self.vert,
                    threatLevel: objectThreatLevel
                )
                block.processDetectedObjects(processed: processedObject)
            }

            //let audioOutput = AudioQueue.popHighestPriorityObject(threshold: 1)
//            if audioOutput?.threatLevel ?? 0 > 1{
//                content.append("Object name: \(audioOutput!.objName),")
//                content.append("Object direction: \(audioOutput!.corridorPosition),")
//                content.append("Object Verticality: \(audioOutput!.vert),")
//                content.append("Object distance: \(audioOutput!.distance),")
//                content.append("Threat level: \(audioOutput!.threatLevel),")
//                content.append("Distance as a Float: \(Float(audioOutput!.distance)),\n")

//                //print(content)
//            }
        }
    }
    
    func updateDepth(_ z: Float16) -> CGFloat {
        let d = Float(z)                 // convert once
        let maxD = Float(maxDepth)       // ensure same type

        let normalized = max(0, min(1, (1 - (d / maxD))))
        return CGFloat(normalized)
    }

  /*
    func findMedian(distances: [Float16]) -> Float16
    {
        let count = distances.count
        guard count > 0 else { return 0 }
        if count % 2 == 1 {
            return distances[count / 2] // Odd number of elements: return the middle one.
        } else {
            // Even number of elements: average the two middle ones.
            let lower = distances[count / 2 - 1]
            let upper = distances[count / 2]
            return (lower + upper) / 2
        }
    }
    */
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
