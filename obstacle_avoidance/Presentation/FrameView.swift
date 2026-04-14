//
//  FrameView.swift
//  obstacleAvoidance
//
//  Swift file that is used to startup the phone camera for viewing the frames.
//  Triggers audible notification for largest bounding box in view.
//

import SwiftUI

struct FrameView: View {
    private let speechLockDuration: TimeInterval = 1.15

    @ObservedObject var frameHandler: FrameHandler
    @State private var timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    @State private var isSpeaking: Bool = false

//    var image: CGImage?
//    var boundingBoxes: [BoundingBox]
//    
    var body: some View {
        ZStack {
            // Overlay bounding boxes on the image
            // Notify user of object with the biggest bounding box
            if let biggestBox = frameHandler.targetedBox {
                ZStack {
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: biggestBox.rect.width, height: biggestBox.rect.height)
                        .position(x: biggestBox.rect.midX, y: biggestBox.rect.midY)
                }
            }
        }
        .onReceive(timer) { _ in
            guard !isSpeaking else { return }
            guard let audioOutput = AudioQueue.popHighestPriorityObject(threshold: AudioPolicyConfig.minimumThreatToSpeak) else {
                return
            }

            isSpeaking = true

            let message = "\(audioOutput.objName) \(audioOutput.corridorPosition) \(audioOutput.formattedDist)"
            DispatchQueue.main.async {
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }

            let dynamicLock = audioOutput.severityBand == .critical ? 0.8 : speechLockDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + dynamicLock) {
                isSpeaking = false
            }
        }
    }
}

struct FrameViewPreviews: PreviewProvider {
    static var previews: some View {
//        FrameView(image: nil, boundingBoxes: [], frameHandler: FrameHandler)
        FrameView(frameHandler: FrameHandler())
    }
}

//import SwiftUI
//
///// A single announced object (name + distance) for duplicate detection.
//private struct AnnouncedEntry {
//    let objectName: String
//    let distance: Float16
//}
//
///// Holds last-announcement state so it's visible immediately and persists across view updates.
//private final class AnnouncementState {
//    static let maxRecentCount = 5
//    var lastAnnounceTime: Date = .distantPast
//    var lastAnnouncedList: [AnnouncedEntry] = []
//
//    func addAnnounced(objectName: String, distance: Float16) {
//        // If we already have this object in the list, remove the old one first
//        lastAnnouncedList.removeAll(where: { $0.objectName == objectName })
//        
//        lastAnnouncedList.append(AnnouncedEntry(objectName: objectName, distance: distance))
//        if lastAnnouncedList.count > Self.maxRecentCount {
//            lastAnnouncedList.removeFirst()
//        }
//    }
//}
//
//private final class ObservableAnnouncementState: ObservableObject {
//    let state = AnnouncementState()
//}
//
//struct FrameView: View {
//
//    // Minimum seconds of silence between ANY announcement (prevents stuttering)
//    private let announceInterval: TimeInterval = 2.0
//
//    @StateObject private var announcementState = ObservableAnnouncementState()
//    
//    // Runs 10 times a second to save battery and CPU
//    @State private var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
//
//    var image: CGImage?
//    var boundingBoxes: [BoundingBox]
//
//    // This function should announce the distance of obstacle  ("10ft -> 6ft -> 3ft")
//    private func shouldSkipAnnouncement(objectName: String, distance: Float16) -> Bool {
//        let state = announcementState.state
//        let now = Date()
//        
//        // RULE 1: Give VoiceOver time to finish speaking.
//        if now.timeIntervalSince(state.lastAnnounceTime) < announceInterval {
//            return true // Skip.
//        }
//        
//        // RULE 2: Check if we have spoken about this exact object recently.
//        for entry in state.lastAnnouncedList {
//            if objectName == entry.objectName {
//                
//                // Calculate how much closer the object got
//                let distanceChange = entry.distance - distance
//                
//                // If the object got closer by 1.0 meter, we DO NOT skip. We speak!
//                if distanceChange >= 1.0 {
//                    return false
//                }
//                
//                // If the object is less than 1.0 meter away, and it has been 4 seconds, remind them!
//                if distance < 1.0 && now.timeIntervalSince(state.lastAnnounceTime) > 4.0 {
//                    return false
//                }
//                
//                // Otherwise, it is the same object and hasn't moved much. Skip it.
//                return true
//            }
//        }
//        
//        // RULE 3: It is a completely new object. Do not skip! Speak!
//        return false
//    }
//
//    var body: some View {
//        ZStack {
//            // Draw Bounding Box
//            if let biggestBox = boundingBoxes.max(by: { $0.rect.width < $1.rect.width }) {
//                ZStack {
//                    Rectangle()
//                        .stroke(Color.red, lineWidth: 2)
//                        .frame(width: biggestBox.rect.width, height: biggestBox.rect.height)
//                        .position(x: biggestBox.rect.midX, y: biggestBox.rect.midY)
//                }
//            }
//        }
//        .onReceive(timer) { _ in
//            
//            // THE SMART BOUNCER
//            while let audioOutput = AudioQueue.popHighestPriorityObject(threshold: 1) {
//                
//                // Check our Rules
//                if shouldSkipAnnouncement(objectName: audioOutput.objName, distance: audioOutput.distance) {
//                    continue // It failed the rules. Throw it away and check the next item.
//                }
//                
//                // IT PASSED THE RULES!
//                
//                // 1. Save it to our memory
//                let state = announcementState.state
//                state.lastAnnounceTime = Date()
//                state.addAnnounced(objectName: audioOutput.objName, distance: audioOutput.distance)
//
//                // 2. Format the text
//                let message = "\(audioOutput.objName) \(audioOutput.corridorPosition) \(audioOutput.formattedDist)"
//                
//                // 3. Clear the old garbage out of the queue
//                AudioQueue.clearQueue()
//                
//                // 4. Speak it out loud
//                if UIAccessibility.isVoiceOverRunning {
//                    UIAccessibility.post(notification: .announcement, argument: message)
//                }
//                
//                // 5. Stop checking the queue until the next timer tick
//                break
//            }
//        }
//    }
//}