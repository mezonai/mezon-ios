import UIKit

private func isKeyboardWindow(window: NSObject) -> Bool {
    let typeName = NSStringFromClass(type(of: window))
    if #available(iOS 9.0, *) {
        if typeName.hasPrefix("UI") && typeName.hasSuffix("RemoteKeyboardWindow") {
            return true
        }
    } else {
        if typeName.hasPrefix("UI") && typeName.hasSuffix("TextEffectsWindow") {
            return true
        }
    }
    return false
}

private func isKeyboardView(view: NSObject) -> Bool {
    let typeName = NSStringFromClass(type(of: view))
    if typeName.hasPrefix("UI") && typeName.hasSuffix("InputSetHostView") {
        return true
    }
    return false
}

private func isKeyboardViewContainer(view: NSObject) -> Bool {
    let typeName = NSStringFromClass(type(of: view))
    if typeName.hasPrefix("UI") && typeName.hasSuffix("InputSetContainerView") {
        return true
    }
    return false
}

@available(iOS 13.0, *)
public final class SceneStatusBarHost: StatusBarHost {
    private weak var scene: UIWindowScene?

    public init(scene: UIWindowScene?) {
        self.scene = scene
    }

    public var isApplicationInForeground: Bool {
        guard let scene = scene else { return false }
        switch scene.activationState {
        case .unattached:
            return false
        case .foregroundActive, .foregroundInactive:
            return true
        case .background:
            return false
        @unknown default:
            return false
        }
    }

    public var statusBarFrame: CGRect {
        guard let scene = scene else { return .zero }
        return scene.statusBarManager?.statusBarFrame ?? .zero
    }

    public var keyboardWindow: UIWindow? {
        if #available(iOS 16.0, *) {
            return UIApplication.shared.internalGetKeyboard()
        }
        for window in UIApplication.shared.windows {
            if isKeyboardWindow(window: window) {
                return window
            }
        }
        return nil
    }

    public var keyboardView: UIView? {
        guard let keyboardWindow = keyboardWindow else { return nil }
        for view in keyboardWindow.subviews {
            if isKeyboardViewContainer(view: view) {
                for subview in view.subviews {
                    if isKeyboardView(view: subview) {
                        return subview
                    }
                }
            }
        }
        return nil
    }
}
