import UIKit

// AppDelegate conforms to UIWindowSceneDelegate (iOS 13+), so it cannot be @main
// at a deployment target of 12.0; the delegate class is picked at runtime instead.
private let delegateClassName: String = {
    if #available(iOS 13.0, *) {
        return NSStringFromClass(AppDelegate.self)
    }
    return NSStringFromClass(LegacyAppDelegate.self)
}()

_ = UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    delegateClassName
)
