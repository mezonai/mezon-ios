import UIKit
import Combine

final class ThemeManager: ObservableObject {

    static let shared = ThemeManager()

    static let didChangeNotification = Notification.Name("AppThemeDidChange")

    private static let userDefaultsKey = "mezon.mobile.selectedTheme"

    @Published private(set) var current: AppTheme

    var attributes: ThemeAttributes { current.attributes }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? ""
        current = AppTheme(rawValue: stored) ?? .purpleHaze
    }

    func set(_ theme: AppTheme) {
        guard theme != current else { return }
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.userDefaultsKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: theme)
        }
    }
}
