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
        return defaults.string(forKey: "measurement_type") ?? "Feet"
    }

    func getUserHeight(height: Double) {
        let returnedHeight = defaults.double(forKey: "user_height")
        return returnedHeight ?? 60.0
    }

    func getHapticFeedback(enabled: Bool) {
        return defaults.bool(forKey: "haptic_feedback") ?? false
    }

    func getLocationSharing(enabled: Bool) {
        return defaults.bool(forKey: "location_sharing") ?? false
    }
}