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

        DispatchQueue.main.async {
            FirebaseApp.configure()
            UNUserNotificationCenter.current().delegate = self
            Messaging.messaging().delegate = self
        }

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

        NetworkMonitor.shared.start()
        NetworkBannerView.install(on: nativeWindow)
        // SocketStatusBannerView.install(on: nativeWindow)

        let statusBarHost = SceneStatusBarHost(scene: windowScene)
        let mainWindow = Window1(hostView: hostView, statusBarHost: statusBarHost)
        self.mainWindow = mainWindow

        mainWindow.viewController = SplashViewController()

        let sharedContext = SharedAccountContextImpl(mainWindow: mainWindow)
        self.sharedContext = sharedContext

        let savedSession = SessionStore.load()

        let onReady: @MainActor (AccountContextImpl) -> Void = { [weak self] context in
            guard let self, !self.hasStartedAuthFlow else { return }
            self.hasStartedAuthFlow = true
            self.startAuthFlow(context: context)
        }

        let context: AccountContextImpl
        if let savedSession {
            let user = User(
                id: savedSession.userId ?? UUID().uuidString,
                username: savedSession.username ?? "me",
                displayName: savedSession.username ?? "Me",
                avatarURL: nil, status: .online, bio: nil
            )
            context = sharedContext.createAccountContext(session: savedSession, user: user, onReady: { _ in })
            self.accountContext = context
            self.hasStartedAuthFlow = true
            self.startAuthFlow(context: context)
        } else {
            context = sharedContext.createUnauthorizedContext(onReady: onReady)
            self.accountContext = context
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.hasStartedAuthFlow else { return }
            self.hasStartedAuthFlow = true
            if let ctx = self.accountContext {
                self.startAuthFlow(context: ctx)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        if let notificationResponse = connectionOptions.notificationResponse {
            let userInfo = notificationResponse.notification.request.content.userInfo
            let title = notificationResponse.notification.request.content.title
            AppLogger.network.info("[FCM] Cold launch from notification: \(userInfo)")
            let (channelId, clanId, isDM) = Self.parseFCMPayload(userInfo)
            Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM, title: title)
        }
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
            requestNotificationPermission()
        } else {
            self.rootController = nil
            mainWindow.viewController = sharedContext.makeLoginController(context: context)
        }
        DispatchQueue.main.async {
            ThemeManager.shared.applyStatusBarStyle()
        }
    }

    private func requestNotificationPermission() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error {
                AppLogger.network.error("[FCM] Notification auth error: \(error)")
            }
            AppLogger.network.info("[FCM] Notification permission granted: \(granted)")
        }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
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
    }

    deinit { disposables.dispose() }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    private static func parseFCMPayload(_ userInfo: [AnyHashable: Any]) -> (channelId: String?, clanId: String?, isDM: Bool) {
        let channelId: String? = {
            if let s = userInfo["channel"] as? String { return s }
            if let n = userInfo["channel"] { return "\(n)" }
            if let s = userInfo["channel_id"] as? String { return s }
            if let n = userInfo["channel_id"] { return "\(n)" }
            return nil
        }()
        
        var clanId: String?
        var isDM = false
        if let link = userInfo["link"] as? String {
            isDM = link.contains("direct/")
            if let url = URL(string: link) {
                let parts = url.pathComponents
                if let clansIdx = parts.firstIndex(of: "clans"), clansIdx + 1 < parts.count {
                    clanId = parts[clansIdx + 1]
                }
            }
        }
        
        if clanId == nil || clanId == "0" {
            if let s = userInfo["clan_id"] as? String, !s.isEmpty, s != "0" { clanId = s }
            else if let n = userInfo["clan_id"] { let s = "\(n)"; if s != "0" && !s.isEmpty { clanId = s } }
            if clanId == nil || clanId == "0" {
                if let s = userInfo["clanId"] as? String { clanId = s }
                else if let n = userInfo["clanId"] { clanId = "\(n)" }
            }
        }
        
        return (channelId, clanId, isDM)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let title = notification.request.content.title
        let body = notification.request.content.body

        let (channelId, clanId, isDM) = Self.parseFCMPayload(userInfo)

        // Skip toast if user is already viewing this channel
        let isViewingChannel: Bool = {
            guard let chId = channelId, let chIdInt = Int64(chId) else { return false }
            return ActiveChannelTracker.currentChannelId == chIdInt
        }()

        if !isViewingChannel {
            Toast.notification(title: title, message: body) {
                DispatchQueue.main.async {
                    Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM, title: title)
                }
            }
        }

        completionHandler([.badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let (channelId, clanId, isDM) = Self.parseFCMPayload(userInfo)
        let title = response.notification.request.content.title

        Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM, title: title)

        completionHandler()
    }

    static var pendingNavigation: [String: Any]?

    static func navigateToChannel(channelId: String?, clanId: String?, isDM: Bool = false, title: String? = nil) {
        guard let channelId, !channelId.isEmpty else { return }
        var info: [String: Any] = ["channelId": channelId, "isDM": isDM]
        if let clanId, !clanId.isEmpty { info["clanId"] = clanId }
        if let title, !title.isEmpty { info["title"] = title }
        pendingNavigation = info
        NotificationCenter.default.post(name: .mezonNavigateToChannel, object: nil, userInfo: info)
    }
}

extension Notification.Name {
    static let mezonNavigateToChannel = Notification.Name("MezonNavigateToChannel")
    static let mezonSocketStatusChanged = Notification.Name("MezonSocketStatusChanged")
    static let mezonMessageTypingReceived = Notification.Name("MezonMessageTypingReceived")
    static let mezonQRSelectClan = Notification.Name("MezonQRSelectClan")
    static let mezonQRNavigateToDM = Notification.Name("MezonQRNavigateToDM")
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        print("[FCM] Token: \(fcmToken)")
        AppLogger.network.info("[FCM] Token received: \(fcmToken.prefix(20))...")

        Task { @MainActor in
            guard let context = self.accountContext else { return }
            guard let token = await context.getToken() else { return }
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            do {
                _ = try await context.account.network.registFcmDeviceToken(
                    fcmToken: fcmToken, deviceId: deviceId, platform: "ios", authToken: token
                )
                AppLogger.network.info("[FCM] Token registered with server")
            } catch {
                AppLogger.network.error("[FCM] Token registration failed: \(error)")
            }
        }
    }
}
