/* 
An object class to store the audio queue information sent from the DecisionBlock to the UI.

Current Author: Darien Aranda
Previous Author: Scott Schnieders
Last modfiied: 2/28/2025
 */
import Foundation

struct AudioQueueVertex: Comparable {
    let threatLevel: Float16
    let objName: String // Name of the obstacle
    let corridorPosition: String // Angle of the obstacle in left/right/center.
    let vert: String // Vertical postionality of an object
    let distance: Float16 // Distance calculated from the person holding phone to the obstacle (in feet).
    let severityBand: AudioSeverityBand
    let dedupKey: String
    let createdAt: Date
    let expiresAt: Date

    static func < (lhs: AudioQueueVertex, rhs: AudioQueueVertex) -> Bool {
        if lhs.severityBand != rhs.severityBand {
            return lhs.severityBand > rhs.severityBand
        }
        if lhs.threatLevel != rhs.threatLevel {
            return lhs.threatLevel > rhs.threatLevel
        }
        return lhs.createdAt < rhs.createdAt
    }
}

extension AudioQueueVertex{
    func roundingDistance(distance: Double) -> Double{
        let decimalVal = distance - floor(distance)
        if  decimalVal > 0.7{
            return ceil(distance)
        }
        else{
            return floor(distance)
        }
    }
    
    var formattedDist: String{
        let unitPref = UserDefaults.standard.string(forKey: "measurementType") ?? "feet"
        if unitPref == "meters"{
            var meters = Double(self.distance)
            if meters > 1{
                meters = roundingDistance(distance: meters)
            }
            return String(format: "%.0f meters", meters)
        } else {
            var feet = Double(self.distance) * 3.28084
            if feet > 1{
                feet = roundingDistance(distance: feet)
            }
            return String(format: "%.0f feet", feet)
        }
    }
}

class AudioQueue {
    public static var queue: [AudioQueueVertex] = []
    private static var lastGlobalAnnouncementAt: Date = .distantPast
    private static var lastAnnouncementByKey: [String: Date] = [:]

    static func makeDedupKey(name: String, direction: String, vertical: String) -> String {
        "\(name.lowercased())|\(direction.lowercased())|\(vertical.lowercased())"
    }

    static func addToHeap(_ processedObject: ProcessedObject) {
        let now = Date()
        pruneExpired(referenceTime: now)
        guard processedObject.threatLevel >= AudioPolicyConfig.minimumThreatToSpeak else { return }

        let dedupKey = makeDedupKey(
            name: processedObject.objName,
            direction: processedObject.corridorPosition,
            vertical: processedObject.vert
        )
        let newVertex = AudioQueueVertex(
            threatLevel: processedObject.threatLevel,
            objName: processedObject.objName,
            corridorPosition: processedObject.corridorPosition,
            vert: processedObject.vert,
            distance: processedObject.distance,
            severityBand: processedObject.severityBand,
            dedupKey: dedupKey,
            createdAt: now,
            expiresAt: now.addingTimeInterval(AudioPolicyConfig.entryTTL)
        )

        if let existingIndex = queue.firstIndex(where: { $0.dedupKey == dedupKey }) {
            let existing = queue[existingIndex]
            if shouldReplace(existing: existing, with: newVertex) {
                queue[existingIndex] = newVertex
            }
        } else {
            queue.append(newVertex)
        }

        trimQueueIfNeeded()
    }

    static func clearQueue(){
        queue.removeAll()
    }

    static func popHighestPriorityObject(threshold: Float16) -> AudioQueueVertex? {
            let now = Date()
            pruneExpired(referenceTime: now)
            guard !queue.isEmpty else { return nil }

            queue.sort()

            for (index, candidate) in queue.enumerated() {
                guard candidate.threatLevel >= threshold else { continue }
                guard canSpeak(candidate: candidate, now: now) else { continue }

                let selected = queue.remove(at: index)
                rememberAnnouncement(selected, now: now)
                return selected
            }

            return nil
        }

    private static func shouldReplace(existing: AudioQueueVertex, with incoming: AudioQueueVertex) -> Bool {
        if incoming.severityBand > existing.severityBand { return true }
        if incoming.threatLevel > existing.threatLevel + 0.05 { return true }

        let gotCloserEnough = existing.distance - incoming.distance >= AudioPolicyConfig.distanceDeltaForReplacement
        return gotCloserEnough
    }

    private static func canSpeak(candidate: AudioQueueVertex, now: Date) -> Bool {
        if candidate.severityBand == .critical {
            let lastAt = lastAnnouncementByKey[candidate.dedupKey] ?? .distantPast
            return now.timeIntervalSince(lastAt) >= AudioPolicyConfig.criticalCooldown
        }

        guard now.timeIntervalSince(lastGlobalAnnouncementAt) >= AudioPolicyConfig.globalCooldown else {
            return false
        }

        let lastAt = lastAnnouncementByKey[candidate.dedupKey] ?? .distantPast
        return now.timeIntervalSince(lastAt) >= AudioPolicyConfig.perKeyCooldown
    }

    private static func rememberAnnouncement(_ candidate: AudioQueueVertex, now: Date) {
        lastGlobalAnnouncementAt = now
        lastAnnouncementByKey[candidate.dedupKey] = now
    }

    private static func pruneExpired(referenceTime now: Date = Date()) {
        queue.removeAll(where: { $0.expiresAt <= now })
    }

    private static func trimQueueIfNeeded() {
        guard queue.count > AudioPolicyConfig.maxPendingItems else { return }
        queue.sort()
        queue = Array(queue.prefix(AudioPolicyConfig.maxPendingItems))
    }
}