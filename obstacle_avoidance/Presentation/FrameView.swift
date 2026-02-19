
//  FrameView.swift
//  obstacleAvoidance
//
//  Swift file that is used to startup the phone camera for viewing the frames.
//  Triggers audible notification for largest bounding box in view.
//

import SwiftUI

/// A single announced object (name + distance) for duplicate detection.
private struct AnnouncedEntry {
    let objectName: String
    let distance: Float16
}

/// Holds last-announcement state so it's visible immediately and persists across view updates.
/// Keeps the last 5 announced objects; won't repeat any of them until they drop off the list.
private final class AnnouncementState {
    static let maxRecentCount = 5
    var lastAnnounceTime: Date = .distantPast
    /// Last 5 announced objects (oldest at index 0). Never more than 5; when a 6th is added, the 1st is removed.
    var lastAnnouncedList: [AnnouncedEntry] = []

    func addAnnounced(objectName: String, distance: Float16) {
        lastAnnouncedList.append(AnnouncedEntry(objectName: objectName, distance: distance))
        if lastAnnouncedList.count > Self.maxRecentCount {
            lastAnnouncedList.removeFirst()
        }
    }
}

private final class ObservableAnnouncementState: ObservableObject {
    let state = AnnouncementState()
}

struct FrameView: View {

    // Minimum seconds between any two announcements (more silence, less overload)
    private let announceInterval: TimeInterval = 2.8
    // Consider distance "similar" if within this fraction of last announced (0.15 = 15%)
    private let distanceSimilarityTolerance: Float16 = 0.15
    // Delay after posting an announcement before allowing the next pop (VoiceOver is speaking)
    private let speakDelay: Double = 2.0

    @StateObject private var announcementState = ObservableAnnouncementState()
    @State private var timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    @State private var clearTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    @State private var isSpeaking: Bool = false

    var image: CGImage?
    var boundingBoxes: [BoundingBox]

    /// True if we should skip announcing (same object at similar distance, or too soon since last announcement).
    /// Skips if the object matches any of the last 5 announced objects (name + similar distance).
    private func shouldSkipAnnouncement(objectName: String, distance: Float16) -> Bool {
        let state = announcementState.state
        let now = Date()
        if now.timeIntervalSince(state.lastAnnounceTime) < announceInterval {
            return true
        }
        let epsilon: Float16 = 1e-6
        for entry in state.lastAnnouncedList {
            guard objectName == entry.objectName else { continue }
            let ref = max(entry.distance, epsilon)
            let relativeChange = abs(distance - entry.distance) / ref
            if relativeChange <= distanceSimilarityTolerance {
                return true  // Match found in recent list; skip to avoid repeating
            }
        }
        return false
    }

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }

            // Overlay bounding boxes on the image
            // Notify user of object with the biggest bounding box
            if let biggestBox = boundingBoxes.max(by: { $0.rect.width < $1.rect.width }) {
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
            guard let audioOutput = AudioQueue.popHighestPriorityObject(threshold: 1) else {
                return
            }
            isSpeaking = true  // Claim immediately so the next tick can't pop and announce the same object

            if shouldSkipAnnouncement(objectName: audioOutput.objName, distance: audioOutput.distance) {
                AudioQueue.clearQueue()
                isSpeaking = false
                return
            }

            // Update persistent state: add to last-5 list (oldest drops off when 6th is added)
            let state = announcementState.state
            state.lastAnnounceTime = Date()
            state.addAnnounced(objectName: audioOutput.objName, distance: audioOutput.distance)

            let message = "\(audioOutput.objName) \(audioOutput.corridorPosition) \(audioOutput.formattedDist)"
            AudioQueue.clearQueue()
            DispatchQueue.main.async {
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + speakDelay) {
                isSpeaking = false
            }
        }
        .onReceive(clearTimer) { _ in
            AudioQueue.clearQueue()
        }
    }
}



struct FrameViewPreviews: PreviewProvider {
    static var previews: some View {
        FrameView(image: nil, boundingBoxes: [])
    }
}
