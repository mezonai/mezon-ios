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
        CallKitManager.shared.configure()
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoIPTokenDidUpdate), name: .mezonVoIPTokenDidUpdate, object: nil)
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MezonSocket.shared.reconnectFromForeground()
            }
        }

        DispatchQueue.main.async {
            FirebaseApp.configure()
            UNUserNotificationCenter.current().delegate = self
            Messaging.messaging().delegate = self
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVoIPMinimalCallChromeActivated),
            name: .mezonVoIPMinimalCallChromeActivated,
            object: nil
        )

        SessionStore.prepareInstallationScopedKeychainIfNeeded()

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        clearPersistedSelectedChannelForCurrentClanOnExit()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        clearPersistedSelectedChannelForCurrentClanOnExit()
    }

    private func clearPersistedSelectedChannelForCurrentClanOnExit() {
        guard let ctx = accountContext else { return }
        let id = ctx.currentClanId
        guard id != 0 else { return }
        ctx.clearPersistedSelectedChannelPreference(forClanId: id)
    }

    @objc private func handleVoIPTokenDidUpdate() {
        registerFcmDeviceWithBackendIfPossible()
    }

    private func registerFcmDeviceWithBackendIfPossible() {
        Task { @MainActor in
            guard !VoIPMinimalCallBootstrap.isMinimalChromeActive else { return }
            guard let context = self.accountContext else { return }
            context.registerFCMDeviceTokenIfNeededExternally()
        }
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

        VoIPMinimalCallBootstrap.reconcileAfterAppColdStartIfNoActiveVoIPCall()


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
            VoIPAnswerAccountBridge.context = context
            self.startAuthFlow(context: context)
        } else {
            VoIPAnswerAccountBridge.context = nil
            context = sharedContext.createUnauthorizedContext(onReady: onReady)
            self.accountContext = context
        }
        if !VoIPMinimalCallBootstrap.isMinimalChromeActive {
            registerFcmDeviceWithBackendIfPossible()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.hasStartedAuthFlow else { return }
            self.hasStartedAuthFlow = true
            if let ctx = self.accountContext {
                self.startAuthFlow(context: ctx)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        if let notificationResponse = connectionOptions.notificationResponse {
            let userInfo = notificationResponse.notification.request.content.userInfo
            let (channelId, clanId, isDM) = Self.parseFCMPayload(userInfo)
            if !isDM, let clanId, let clanIdInt = Int64(clanId), clanIdInt != 0 {
                accountContext?.currentClanId = clanIdInt
            }
            Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM)
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
            if VoIPMinimalCallBootstrap.isMinimalChromeActive {
                self.rootController = nil
                mainWindow.viewController = VoIPMinimalShellViewController(context: context)
            } else {
                let rootController = sharedContext.makeMezonRootController(context: context)
                rootController.addRootControllers()
                self.rootController = rootController
                mainWindow.viewController = rootController
                requestNotificationPermission()
                registerFcmDeviceWithBackendIfPossible()
            }
        } else {
            VoIPAnswerAccountBridge.context = nil
            self.rootController = nil
            mainWindow.viewController = sharedContext.makeLoginController(context: context)
            installMandatoryUsernameStackIfNeeded(context: context, mainWindow: mainWindow)
        }
        DispatchQueue.main.async {
            ThemeManager.shared.applyStatusBarStyle()
        }
        if !VoIPMinimalCallBootstrap.isMinimalChromeActive {
            AppUpdateGate.scheduleVersionCheckIfNeeded(mainWindow: mainWindow)
        }
    }

    @objc private func handleVoIPMinimalCallChromeActivated() {
        swapToVoIPMinimalShellIfNeeded()
    }

    private func swapToVoIPMinimalShellIfNeeded() {
        guard VoIPMinimalCallBootstrap.isMinimalChromeActive else { return }
        guard let ctx = accountContext, ctx.isLoggedIn else { return }
        guard let mainWindow else { return }
        guard !(mainWindow.viewController is VoIPMinimalShellViewController) else { return }
        rootController = nil
        mainWindow.viewController = VoIPMinimalShellViewController(context: ctx)
        DispatchQueue.main.async {
            ThemeManager.shared.applyStatusBarStyle()
        }
    }

    private func installMandatoryUsernameStackIfNeeded(context: AccountContext, mainWindow: Window1) {
        guard let session = context.session else { return }
        guard MandatoryUsernamePendingStore.isPending else { return }
        guard let nav = mainWindow.viewController as? NavigationController else { return }
        let loginVC = LoginViewController(context: context)
        let stub = OTPContext(reqId: "", target: "", type: .sms)
        let updateVC = UpdateUsernameViewController(pendingSession: session, context: context, otpContext: stub)
        nav.setViewControllers([loginVC, updateVC], animated: false)
    }

    private func requestNotificationPermission() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, error in
            if error != nil {
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
        if let shell = mainWindow?.viewController as? VoIPMinimalShellViewController {
            shell.flushPendingIncomingPeerCallIfNeeded()
        }
        rootController?.flushPendingIncomingPeerCallIfNeeded()
        checkPendingSharedContent()
    }

    @objc private func handleDidBecomeActive() {
        if !VoIPMinimalCallBootstrap.isMinimalChromeActive {
            VoIPMinimalCallBootstrap.clearExitAfterPeerCallFlagOnly()
        }
        if let shell = mainWindow?.viewController as? VoIPMinimalShellViewController {
            shell.flushPendingIncomingPeerCallIfNeeded()
        }
        rootController?.flushPendingIncomingPeerCallIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if let shell = self?.mainWindow?.viewController as? VoIPMinimalShellViewController {
                shell.flushPendingIncomingPeerCallIfNeeded()
            }
            self?.rootController?.flushPendingIncomingPeerCallIfNeeded()
        }
        accountContext?.recoverFromForeground()
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

    private static func pushPayloadString(_ userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        let dataDict = userInfo["data"] as? [String: Any]
        for key in keys {
            if let v = stringFromPushValue(userInfo[key]) { return v }
            if let dataDict, let v = stringFromPushValue(dataDict[key]) { return v }
        }
        return nil
    }

    private static func parseFCMPayload(_ userInfo: [AnyHashable: Any]) -> (channelId: String?, clanId: String?, isDM: Bool) {
        let channelId = pushPayloadString(userInfo, keys: [
            "channel", "channel_id", "channelId", "channelID",
            "message_channel_id", "messageChannelId", "target_channel_id", "targetChannelId",
        ])

        var clanId: String?
        var isDM = false

        if let link = pushPayloadString(userInfo, keys: ["link"]) {
            isDM = link.lowercased().contains("direct")
            if let url = URL(string: link) {
                let parts = url.pathComponents
                if let i = parts.firstIndex(of: "clans"), i + 1 < parts.count {
                    clanId = parts[i + 1]
                }
            }
        }

        if clanId == nil {
            clanId = pushPayloadString(userInfo, keys: ["clan_id", "clanId", "clan", "guild_id", "guildId"])
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

        Task { @MainActor in
            let suppressPeerCallToast = WebRTCCallManager.shared.isPeerCallDetailScreenActive
            guard !isViewingChannel, !suppressPeerCallToast else { return }
            Toast.notification(title: title, message: body) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !isDM, let clanId, let clanIdInt = Int64(clanId), clanIdInt != 0 {
                        self.accountContext?.currentClanId = clanIdInt
                    }
                    Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM)
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

        if !isDM, let clanId, let clanIdInt = Int64(clanId), clanIdInt != 0 {
            accountContext?.currentClanId = clanIdInt
        }

        Self.navigateToChannel(channelId: channelId, clanId: clanId, isDM: isDM)

        completionHandler()
    }

    static var pendingNavigation: [String: Any]?
    static var lastHandledNavigationInstanceId: String?

    static func navigateToChannel(channelId: String?, clanId: String?, isDM: Bool = false) {
        guard let channelId, !channelId.isEmpty else { return }
        var info: [String: Any] = [
            "channelId": channelId,
            "isDM": isDM,
            "navigationInstanceId": UUID().uuidString,
        ]
        if let clanId, !clanId.isEmpty { info["clanId"] = clanId }
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
    static let mezonAlignChannelListAfterSearchJump = Notification.Name("MezonAlignChannelListAfterSearchJump")
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard fcmToken != nil else { return }
        registerFcmDeviceWithBackendIfPossible()
    }
}
