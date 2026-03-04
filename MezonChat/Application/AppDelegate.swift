import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MezonEnvironment.current = .dev

        let env = MezonEnvironment.current
        print("""
        ┌─────────────────────────────────────────
        │  Environment : \(env == .dev ? "DEV 🟡" : "PROD 🟢")
        │  Auth (GW)   : \(env.authBaseURL)
        │  Proto API   : \(env.protoBaseURL)
        │  WebSocket   : \(env.wsHost)\(env.wsPort.map { ":\($0)" } ?? "")
        │  Server key  : \(env.serverKey)
        └─────────────────────────────────────────
        """)
        return true
    }


    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
