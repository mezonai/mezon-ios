import Foundation

enum MandatoryUsernamePendingStore {
    private static let key = "mezon.mandatoryUsernamePending"

    static var isPending: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setPending() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func clearPending() {
        UserDefaults.standard.set(false, forKey: key)
    }
}
