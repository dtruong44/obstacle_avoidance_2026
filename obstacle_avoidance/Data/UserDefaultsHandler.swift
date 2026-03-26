import Foundation

class UserDefaultsHandler {

    static let shared = UserDefaultsHandler()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let measurementType = "measurement_type"
        static let userHeight = "user_height"
        static let hapticFeedback = "haptic_feedback"
        static let locationSharing = "location_sharing"
    }

    func setMeasurementType(type: String) {
        defaults.set(type, forKey: Keys.measurementType)
    }

    func setUserHeight(height: Double) {
        defaults.set(height, forKey: Keys.userHeight)
    }

    func setHapticFeedback(enabled: Bool) {
        defaults.set(enabled, forKey: Keys.hapticFeedback)
    }

    func setLocationSharing(enabled: Bool) {
        defaults.set(enabled, forKey: Keys.locationSharing)
    }

    func getMeasurementType() -> String {
        return defaults.string(forKey: Keys.measurementType) ?? "Feet"
    }

    func getUserHeight() -> Double {
        let returnedHeight = defaults.double(forKey: Keys.userHeight)
        return returnedHeight == 0 ? 60.0 : returnedHeight
    }

    func getHapticFeedback() -> Bool {
        return defaults.bool(forKey: Keys.hapticFeedback)
    }

    func getLocationSharing() -> Bool {
        return defaults.bool(forKey: Keys.locationSharing)
    }
}