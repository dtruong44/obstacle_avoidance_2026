/* 
An object class that takes the data surrounding an obstacle and determines 
if it should be announced to the user.

Data in:
    Object Name
    Distance
    Direction

Returns: ProcessedObject which is the detectedObject with a computed threat levelt o be passed to AudioQueue

Inital Author: Scott Schnieders
Current Author: Darien Aranda
Last modfiied: 3/26/2025
 */

import SwiftUI
import Foundation

// Create a struct holding parameters that pass through logic
struct DetectedObject {
    let objName: String
    let distance: Float16
    let corridorPosition: String
    let vert: String
    let confidence: Float
}

struct ProcessedObject {
    let objName: String
    let distance: Float16
    let corridorPosition: String
    let vert: String
    let threatLevel: Float16
}

#if DEBUG
extension DecisionBlock {
    // Helper to quickly log threat scores for synthetic test cases.
    static func debugThreat(for object: DetectedObject) -> Float16 {
        let block = DecisionBlock(detectedObject: object)
        let score = block.computeThreatLevel(for: object)
        print("Debug threat for \(object.objName) at \(object.distance)m (\(object.corridorPosition), \(object.vert), conf=\(object.confidence)): \(score)")
        return score
    }
}
#endif

class DecisionBlock {
    var detectedObject: DetectedObject
    var processed: ProcessedObject!

    // Simple in-memory temporal smoother for threat scores
    private static var threatHistory: [String: Float16] = [:]

    private static func smoothedThreat(forKey key: String, newValue: Float16) -> Float16 {
        // Exponential moving average with bias towards recent values
        let alpha: Float16 = 0.6
        if let previous = threatHistory[key] {
            let smoothed = alpha * newValue + (1 - alpha) * previous
            threatHistory[key] = smoothed
            return smoothed
        } else {
            threatHistory[key] = newValue
            return newValue
        }
    }

    // Initializer
    init(detectedObject: DetectedObject) {
        self.detectedObject = detectedObject
    }

    // Does the mathematics to create a threat heuristic for the objects
    func computeThreatLevel(for object: DetectedObject) -> Float16 {
        let objectID = ThreatLevelConfigV3.objectName[object.objName] ?? 1
        let objThreat = ThreatLevelConfigV3.objectWeights[objectID] ?? 1
        let directionWeight = ThreatLevelConfigV3.corridorPosition[object.corridorPosition] ?? 1
        // Distance shaping tuned for sidewalk use
        let rawDistance = max(0.2, Float(object.distance))
        let maxRange: Float = 8.0

        // Ignore very distant or clearly outside-corridor objects
        if object.corridorPosition == "Outside" || rawDistance >= maxRange {
            return 0.0
        }

        // Distance weight: closer objects get disproportionately higher weight
        let distanceExponent: Float = 1.3
        let distanceWeight = 1.0 / pow(rawDistance, distanceExponent)

        // Vertical weighting: lower > middle > upper for sidewalk collision risk
        let vertWeight: Float
        switch object.vert {
        case "lower third":
            vertWeight = 1.2
        case "middle third":
            vertWeight = 1.0
        case "upper third":
            vertWeight = 0.7
        default:
            vertWeight = 1.0
        }

        // Confidence weighting from YOLO
        let clampedConfidence = max(0.1, min(1.0, object.confidence))
        let confidenceGamma: Float = 1.3
        let confidenceWeight = pow(clampedConfidence, confidenceGamma)

        var threatFloat =
            Float(objThreat) *
            Float(directionWeight) *
            distanceWeight *
            vertWeight *
            confidenceWeight

        // Extra boost for close overhead hazards
        if object.vert == "upper third" && rawDistance < 1.75 {
            threatFloat *= 1.3
        }

        let rawThreat = Float16(threatFloat)

        // Temporal smoothing key: object type + lateral position + coarse distance bucket
        let distanceBucket = Int(rawDistance.rounded())
        let key = "\(object.objName)_\(object.corridorPosition)_\(distanceBucket)"
        return DecisionBlock.smoothedThreat(forKey: key, newValue: rawThreat)
    }

    // Given the provided information about the object, computes the threat level to create a processedObject
    func processDetectedObjects(processed: ProcessedObject) {
        let processed = ProcessedObject(
            objName: detectedObject.objName,
            distance: detectedObject.distance,
            corridorPosition: detectedObject.corridorPosition,
            vert: detectedObject.vert,
            threatLevel: computeThreatLevel(for: detectedObject)
            )

        // Passes each instance of a detected object into the Queue
        if processed.threatLevel != 0{
            AudioQueue.addToHeap(processed)
        } else{
            return
        }
    }
}
