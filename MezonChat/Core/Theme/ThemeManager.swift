import UIKit

final class ThemeManager {

    static let shared = ThemeManager()

    static let didChangeNotification = Notification.Name("AppThemeDidChange")

    private static let userDefaultsKey = "mezon.mobile.selectedTheme"

    private(set) var current: AppTheme

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
            self.applyStatusBarStyle()
        }
    }

    var preferredStatusBarStyle: UIStatusBarStyle {
        current == .light ? .darkContent : .lightContent
    }

    func applyStatusBarStyle() {
        let style = preferredStatusBarStyle
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                if let rootVC = window.rootViewController {
                    rootVC.setNeedsStatusBarAppearanceUpdate()
                }
            }
        }
        if let scene = scenes.first,
           let window = scene.windows.first,
           let rootVC = window.rootViewController as? UIViewController {
            (rootVC as? StatusBarStyleUpdatable)?.updatePreferredStatusBarStyle(style)
        }
    }
}

protocol StatusBarStyleUpdatable {
    func updatePreferredStatusBarStyle(_ style: UIStatusBarStyle)
}
