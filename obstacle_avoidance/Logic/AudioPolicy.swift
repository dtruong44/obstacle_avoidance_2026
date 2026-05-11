import Foundation

enum AudioSeverityBand: Int, Comparable, Codable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    static func < (lhs: AudioSeverityBand, rhs: AudioSeverityBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AudioPolicyConfig {
    // Queue hygiene
    static let maxPendingItems = 8
    static let entryTTL: TimeInterval = 1.6

    // Speech pacing
    static let globalCooldown: TimeInterval = 1.4
    static let perKeyCooldown: TimeInterval = 2.8
    static let criticalCooldown: TimeInterval = 0.9

    // Threat gates
    static let minimumThreatToSpeak: Float16 = 1.0
    static let highThreatThreshold: Float16 = 1.5
    static let criticalThreatThreshold: Float16 = 2.4
    static let distanceDeltaForReplacement: Float16 = 0.4

    // Hysteresis
    static let minRiskyFramesForNormal = 2
    static let minRiskyFramesForLow = 3

    static func informationFrequencyMultiplier() -> Double {
        let stored = UserDefaults.standard.double(forKey: "informationFrequencyMultiplier")
        let multiplier = stored == 0 ? 1.0 : stored
        return min(max(multiplier, 0.5), 2.0)
    }

    static func scaledInterval(_ base: TimeInterval) -> TimeInterval {
        let multiplier = informationFrequencyMultiplier()
        return base / multiplier
    }
}