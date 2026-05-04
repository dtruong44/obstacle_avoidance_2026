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
}

struct ProcessedObject {
    let objName: String
    let distance: Float16
    let corridorPosition: String
    let vert: String
    let threatLevel: Float16
    let severityBand: AudioSeverityBand
}

class DecisionBlock {
    var detectedObject: DetectedObject
    private static var riskFrameCountByKey: [String: Int] = [:]

    // Initializer
    init(detectedObject: DetectedObject) {
        self.detectedObject = detectedObject
    }

    // Does the mathmatics to create a threat heuristic for the objects
    func computeThreatLevel(for object: DetectedObject) -> Float16 {
        let objectID = ThreatLevelConfigV3.objectName[object.objName] ?? 1
        let objThreat = ThreatLevelConfigV3.objectWeights[objectID] ?? 1
        let directionWeight = ThreatLevelConfigV3.corridorPosition[object.corridorPosition] ?? 1
        //This inverts distance so the closer something is the more dangerous it is.
        let distanceClamped = max(0.1, Float16(object.distance))
        let inverseDistance = 1.0 / distanceClamped
        if object.corridorPosition == "outside" || object.distance >= 3{
            return(0.0)
        } else {
            var threat = Float16(objThreat) * Float16(directionWeight) * inverseDistance
            if(detectedObject.vert == "upper third" && distanceClamped < 1.75){
                threat *= 2
            }
            return Float16(threat)
        }
    }

    private func computeSeverityBand(for threat: Float16) -> AudioSeverityBand {
        if threat >= AudioPolicyConfig.criticalThreatThreshold {
            return .critical
        }
        if threat >= AudioPolicyConfig.highThreatThreshold {
            return .high
        }
        if threat >= AudioPolicyConfig.minimumThreatToSpeak {
            return .normal
        }
        return .low
    }

    private func passesHysteresis(threat: Float16) -> Bool {
        let key = AudioQueue.makeDedupKey(
            name: detectedObject.objName,
            direction: detectedObject.corridorPosition,
            vertical: detectedObject.vert
        )

        if threat < AudioPolicyConfig.minimumThreatToSpeak {
            Self.riskFrameCountByKey[key] = 0
            return false
        }

        let previous = Self.riskFrameCountByKey[key] ?? 0
        let current = previous + 1
        Self.riskFrameCountByKey[key] = current

        if threat >= AudioPolicyConfig.highThreatThreshold {
            return true
        }
        return current >= AudioPolicyConfig.minRiskyFramesForNormal
    }

    // Given the provided information about the object, computes the threat level to create a processedObject
    func processDetectedObjects() {
        let threat = computeThreatLevel(for: detectedObject)
        let severityBand = computeSeverityBand(for: threat)

        let processed = ProcessedObject(
            objName: detectedObject.objName,
            distance: detectedObject.distance,
            corridorPosition: detectedObject.corridorPosition,
            vert: detectedObject.vert,
            threatLevel: threat,
            severityBand: severityBand
            )

        // Passes each instance of a detected object into the Queue
        if passesHysteresis(threat: processed.threatLevel) {
            AudioQueue.addToHeap(processed)
        } else{
            return
        }
    }
}
