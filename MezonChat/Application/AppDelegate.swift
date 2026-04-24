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
            let (channelId, clanId, isDM) = Self.parseFCMPayload(userInfo)
            if !isDM, let clanId, let clanIdInt = Int64(clanId), clanIdInt != 0 {
                accountContext?.currentClanId = clanIdInt
            }
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
                    if !isLoggedIn {
                        lastLoggedIn = false
                        self.showRoot(isLoggedIn: false, context: context, sharedContext: sharedContext, mainWindow: mainWindow)
                        return
                    }
                    if lastLoggedIn == true { return }
                    lastLoggedIn = true
                    self.showRoot(isLoggedIn: true, context: context, sharedContext: sharedContext, mainWindow: mainWindow)
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
        AppUpdateGate.scheduleVersionCheckIfNeeded(mainWindow: mainWindow)
    }

    private func requestNotificationPermission() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error {
            }
        }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }


    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }

    @objc private func handleWillEnterForeground() {
        accountContext?.recoverFromForeground()
        checkPendingSharedContent()
    }

    private func checkPendingSharedContent() {
        if SharingManager.shared.hasPendingSharedContent() {
            NotificationCenter.default.post(
                name: .mezonDidReceiveSharedContent,
                object: nil,
                userInfo: ["type": "unknown"]
            )
        }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            handleShareURL(context.url)
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        handleShareURL(url)
        return url.scheme == "mezon.mobile.sharing"
    }

    private func handleShareURL(_ url: URL) {
        guard url.scheme == "mezon.mobile.sharing" else { return }

        let type: String
        if let fragment = url.fragment {
            type = fragment
        } else {
            type = "text"
        }


        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: .mezonDidReceiveSharedContent,
                object: nil,
                userInfo: ["type": type]
            )
        }
    }

    deinit { disposables.dispose() }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    private static func stringFromPushValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String, !s.isEmpty { return s }
        let s = "\(value)"
        return s.isEmpty ? nil : s
    }

    private static func parseFCMPayload(_ userInfo: [AnyHashable: Any]) -> (channelId: String?, clanId: String?, isDM: Bool) {
        let channelId = stringFromPushValue(userInfo["channel"])
            ?? stringFromPushValue(userInfo["channel_id"])

        var clanId: String?
        var isDM = false

        if let link = stringFromPushValue(userInfo["link"]) {
            isDM = link.lowercased().contains("direct")
            if let url = URL(string: link) {
                let parts = url.pathComponents
                if let i = parts.firstIndex(of: "clans"), i + 1 < parts.count {
                    clanId = parts[i + 1]
                }
            }
        }

        if clanId == nil {
            clanId = stringFromPushValue(userInfo["clan_id"])
                ?? stringFromPushValue(userInfo["clanId"])
        }

        if let c = clanId, let v = Int64(c), v == 0 {
            isDM = true
        }

        if isDM {
            clanId = "0"
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

        if !isDM, let clanId, let clanIdInt = Int64(clanId), clanIdInt != 0 {
            accountContext?.currentClanId = clanIdInt
        }

        Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM, title: title)

        completionHandler()
    }

    static var pendingNavigation: [String: Any]?
    static var lastHandledNavigationInstanceId: String?

    static func navigateToChannel(channelId: String?, clanId: String?, isDM: Bool = false, title: String? = nil) {
        guard let channelId, !channelId.isEmpty else { return }
        var info: [String: Any] = [
            "channelId": channelId,
            "isDM": isDM,
            "navigationInstanceId": UUID().uuidString,
        ]
        if let clanId, !clanId.isEmpty { info["clanId"] = clanId }
        if let title, !title.isEmpty { info["title"] = title }
        pendingNavigation = info
        NotificationCenter.default.post(name: .mezonNavigateToChannel, object: nil, userInfo: info)
        let instanceId = info["navigationInstanceId"] as? String
        DispatchQueue.main.async {
            guard let instanceId,
                  (pendingNavigation?["navigationInstanceId"] as? String) == instanceId else { return }
            pendingNavigation = nil
        }
    }

    static func recordNavigationInstanceHandled(userInfo: [AnyHashable: Any]?) {
        if let sid = userInfo?["navigationInstanceId"] as? String {
            lastHandledNavigationInstanceId = sid
        }
    }
}

extension Notification.Name {
    static let mezonNavigateToChannel = Notification.Name("MezonNavigateToChannel")
    static let mezonSocketStatusChanged = Notification.Name("MezonSocketStatusChanged")
    static let mezonMessageTypingReceived = Notification.Name("MezonMessageTypingReceived")
    static let mezonQRSelectClan = Notification.Name("MezonQRSelectClan")
    static let mezonQRNavigateToDM = Notification.Name("MezonQRNavigateToDM")
    static let mezonDidReceiveSharedContent = Notification.Name("MezonDidReceiveSharedContent")
    static let mezonVoicePresenceChanged = Notification.Name("MezonVoicePresenceChanged")
    static let mezonAlignHomeAfterCrossClanVoice = Notification.Name("MezonAlignHomeAfterCrossClanVoice")
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }

        Task { @MainActor in
            guard let context = self.accountContext else { return }
            guard let token = await context.getToken() else { return }
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            let voipToken = CallKitManager.shared.voipToken ?? ""
            do {
                _ = try await context.account.network.registFcmDeviceToken(
                    fcmToken: fcmToken, deviceId: deviceId, platform: "ios", voipToken: voipToken, authToken: token
                )
            } catch {
            }
        }
    }
}
