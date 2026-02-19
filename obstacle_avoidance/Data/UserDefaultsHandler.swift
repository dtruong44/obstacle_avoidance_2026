import Foundation

class UserDefaultsHandler {

    static let shared = UserDefaultsHandler()
    private let defaults = UserDefaults.standard

    // Measurement Type, User Height, Haptic, Location Share


    func setMeasurementType(type: String) {
        defaults.set(type, forKey: "measurement_type")
    }

    func setUserHeight(height: Double) {
        defaults.set(height, forKey: "user_height")
    }

    func setHapticFeedback(enabled: Bool) {
        defaults.set(enabled, forKey: "haptic_feedback")
    }

    func setLocationSharing(enabled: Bool) {
        defaults.set(enabled, forKey: "location_sharing")
    }

    func getMeasurementType(type: String) {
        return defaults.object(forKey: "measurement_type") as? String ?? "Feet"
    }

    func getUserHeight(height: Double) {
        return defaults.object(forKey: "user_height") as? Double ?? 60.0
    }

    func getHapticFeedback(enabled: Bool) {
        return defaults.object(forKey: "haptic_feedback") as? Bool ?? false
    }

    func getLocationSharing(enabled: Bool) {
        return defaults.object(forKey: "location_sharing") as? Bool ?? false
    }
}