import UIKit

final class ThemeManager {

    static let shared = ThemeManager()

    static let didChangeNotification = Notification.Name("AppThemeDidChange")

    private static let userDefaultsKey = "mezon.mobile.selectedTheme"

    private(set) var current: AppTheme

    var attributes: ThemeAttributes { current.attributes }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? ""
        current = AppTheme(rawValue: stored) ?? .system
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSystemAppearanceChange),
            name: Notification.Name("SystemAppearanceDidChange"), object: nil)
    }

    @objc private func handleSystemAppearanceChange() {
        if current == .system {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: current)
        }
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
                    let finalStyle = isAuthFlow(rootVC) ? .darkContent : style
                    (rootVC as? StatusBarStyleUpdatable)?.updatePreferredStatusBarStyle(finalStyle)
                    rootVC.setNeedsStatusBarAppearanceUpdate()
                }
            }
        }
    }

    private func isAuthFlow(_ controller: UIViewController) -> Bool {
        if controller is AuthScreenStatusBarStyle {
            return true
        }

        if let window = controller.view.window as? WindowHost {
            var found = false
            window.forEachController { c in
                if c is AuthScreenStatusBarStyle {
                    found = true
                }
            }
            if found { return true }
        }

        if let nav = controller as? UINavigationController {
            if let top = nav.topViewController, isAuthFlow(top) {
                return true
            }
        }
        for child in controller.children {
            if isAuthFlow(child) {
                return true
            }
        }
        return false
    }
}

protocol StatusBarStyleUpdatable {
    func updatePreferredStatusBarStyle(_ style: UIStatusBarStyle)
}
