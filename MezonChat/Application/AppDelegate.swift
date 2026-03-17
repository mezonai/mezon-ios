import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate {

    var window: UIWindow?
    private var nativeWindow: (UIWindow & WindowHost)?
    private var mainWindow: Window1?

    private var sharedContext: SharedAccountContextImpl?
    private var accountContext: AccountContextImpl?
    private var rootController: MezonRootController?

    private let disposables = DisposableSet()
    private var hasStartedAuthFlow = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MezonEnvironment.current = .prod

        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error {
                AppLogger.network.error("[FCM] Notification auth error: \(error)")
            }
            AppLogger.network.info("[FCM] Notification permission granted: \(granted)")
        }
        application.registerForRemoteNotifications()

        Messaging.messaging().delegate = self

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = AppDelegate.self
        return config
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let (nativeWindow, hostView) = nativeWindowHostView(windowScene: windowScene)
        self.nativeWindow = nativeWindow
        self.window = nativeWindow
        hostView.containerView.backgroundColor = UIColor.theme.primary
        nativeWindow.makeKeyAndVisible()

        let statusBarHost = SceneStatusBarHost(scene: windowScene)
        let mainWindow = Window1(hostView: hostView, statusBarHost: statusBarHost)
        self.mainWindow = mainWindow

        mainWindow.viewController = SplashViewController()

        let sharedContext = SharedAccountContextImpl(mainWindow: mainWindow)
        self.sharedContext = sharedContext

        let savedSession = SessionStore.load()

        let context = sharedContext.createUnauthorizedContext(onReady: { [weak self] context in
            guard let self, !self.hasStartedAuthFlow else { return }
            self.hasStartedAuthFlow = true
            self.startAuthFlow(context: context)
        })
        self.accountContext = context

        if let savedSession {
            context.login(
                user: User(
                    id: savedSession.userId ?? UUID().uuidString,
                    username: savedSession.username ?? "me",
                    displayName: savedSession.username ?? "Me",
                    avatarURL: nil, status: .online, bio: nil
                ),
                session: savedSession
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.hasStartedAuthFlow else { return }
            self.hasStartedAuthFlow = true
            if let ctx = self.accountContext {
                self.startAuthFlow(context: ctx)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    private func startAuthFlow(context: AccountContext) {
        guard let sharedContext, let mainWindow else { return }

        var lastLoggedIn: Bool? = context.isLoggedIn
        showRoot(isLoggedIn: context.isLoggedIn, context: context, sharedContext: sharedContext, mainWindow: mainWindow)

        disposables.add(
            (context.isLoggedInSignal |> deliverOnMainQueue)
                .start(next: { [weak self] isLoggedIn in
                    guard let self, let sharedContext = self.sharedContext, let mainWindow = self.mainWindow else { return }
                    guard isLoggedIn != lastLoggedIn else { return }
                    lastLoggedIn = isLoggedIn
                    self.showRoot(isLoggedIn: isLoggedIn, context: context, sharedContext: sharedContext, mainWindow: mainWindow)
                })
        )
    }

    private func showRoot(isLoggedIn: Bool, context: AccountContext, sharedContext: SharedAccountContext, mainWindow: Window1) {
        if isLoggedIn {
            let rootController = sharedContext.makeMezonRootController(context: context)
            rootController.addRootControllers()
            self.rootController = rootController
            mainWindow.viewController = rootController
        } else {
            self.rootController = nil
            mainWindow.viewController = sharedContext.makeLoginController(context: context)
        }
    }


    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        AppLogger.network.info("[FCM] APNs token registered")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.network.error("[FCM] APNs registration failed: \(error)")
    }

    @objc private func handleWillEnterForeground() {
        accountContext?.recoverFromForeground()
        UIApplication.shared.applicationIconBadgeNumber = 0
        UserDefaults(suiteName: "group.mezon.mobile")?.set(0, forKey: "badgeCount")
    }

    deinit { disposables.dispose() }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        AppLogger.network.info("[FCM] Notification tapped: \(userInfo)")
        completionHandler()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        print("[FCM] Token: \(fcmToken)")
        AppLogger.network.info("[FCM] Token received: \(fcmToken.prefix(20))...")

        Task { @MainActor in
            guard let context = self.accountContext, let session = context.session else { return }
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            do {
                _ = try await context.account.network.registFcmDeviceToken(
                    fcmToken: fcmToken, deviceId: deviceId, platform: "ios", authToken: session.token
                )
                AppLogger.network.info("[FCM] Token registered with server")
            } catch {
                AppLogger.network.error("[FCM] Token registration failed: \(error)")
            }
        }
    }
}
