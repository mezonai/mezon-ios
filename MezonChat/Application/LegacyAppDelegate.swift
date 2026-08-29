import UIKit

/// Application delegate used on iOS 12, where `UIWindowSceneDelegate` is unavailable.
/// It drives the same window/context/root-controller stack as `AppDelegate`.
final class LegacyAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    private var nativeWindow: (UIWindow & WindowHost)?
    private var mainWindow: Window1?
    private var sharedContext: SharedAccountContextImpl?
    private var accountContext: AccountContextImpl?
    private var rootController: MezonRootController?
    private var hasStartedAuthFlow = false
    private let disposables = DisposableSet()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        MezonEnvironment.current = .dev
        SessionStore.prepareInstallationScopedKeychainIfNeeded()

        let (nativeWindow, hostView) = nativeWindowHostView()
        self.nativeWindow = nativeWindow
        self.window = nativeWindow
        hostView.containerView.backgroundColor = UIColor.theme.primary
        nativeWindow.makeKeyAndVisible()

        NetworkMonitor.shared.start()
        NetworkBannerView.install(on: nativeWindow)

        let mainWindow = Window1(hostView: hostView, statusBarHost: nil)
        self.mainWindow = mainWindow
        mainWindow.viewController = SplashViewController()

        let sharedContext = SharedAccountContextImpl(mainWindow: mainWindow)
        self.sharedContext = sharedContext

        let context: AccountContextImpl
        if let savedSession = SessionStore.load() {
            let user = User(
                id: savedSession.userId ?? UUID().uuidString,
                username: savedSession.username ?? "me",
                displayName: savedSession.username ?? "Me",
                avatarURL: nil, status: .online, bio: nil
            )
            context = sharedContext.createAccountContext(
                session: savedSession, user: user, onReady: { _ in })
            self.accountContext = context
            context.clearAllPersistedSelectedChannelPreferences()
            hasStartedAuthFlow = true
            startAuthFlow(context: context)
        } else {
            context = sharedContext.createUnauthorizedContext(onReady: { [weak self] ready in
                guard let self, !self.hasStartedAuthFlow else { return }
                self.hasStartedAuthFlow = true
                self.startAuthFlow(context: ready)
            })
            self.accountContext = context
            context.clearAllPersistedSelectedChannelPreferences()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.hasStartedAuthFlow else { return }
            self.hasStartedAuthFlow = true
            if let ctx = self.accountContext {
                self.startAuthFlow(context: ctx)
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)

        return true
    }

    private func startAuthFlow(context: AccountContext) {
        guard let sharedContext, let mainWindow else { return }

        var lastLoggedIn: Bool? = context.isLoggedIn
        showRoot(isLoggedIn: context.isLoggedIn, context: context,
                 sharedContext: sharedContext, mainWindow: mainWindow)

        disposables.add(
            (context.isLoggedInSignal |> deliverOnMainQueue)
                .start(next: { [weak self] isLoggedIn in
                    guard let self, let sharedContext = self.sharedContext,
                          let mainWindow = self.mainWindow else { return }
                    if !isLoggedIn {
                        lastLoggedIn = false
                        self.showRoot(isLoggedIn: false, context: context,
                                      sharedContext: sharedContext, mainWindow: mainWindow)
                        return
                    }
                    if lastLoggedIn == true { return }
                    lastLoggedIn = true
                    self.showRoot(isLoggedIn: true, context: context,
                                  sharedContext: sharedContext, mainWindow: mainWindow)
                })
        )
    }

    private func showRoot(
        isLoggedIn: Bool,
        context: AccountContext,
        sharedContext: SharedAccountContext,
        mainWindow: Window1
    ) {
        if isLoggedIn {
            let rootController = sharedContext.makeMezonRootController(context: context)
            rootController.addRootControllers()
            self.rootController = rootController
            mainWindow.viewController = rootController
        } else {
            self.rootController = nil
            mainWindow.viewController = sharedContext.makeLoginController(context: context)
        }
        DispatchQueue.main.async {
            ThemeManager.shared.applyStatusBarStyle()
        }
    }

    @objc private func handleWillEnterForeground() {
        MezonSocket.shared.noteWillEnterForeground()
        accountContext?.recoverFromForeground()
    }

    @objc private func handleDidEnterBackground() {
        MezonSocket.shared.noteEnteredBackground()
    }
}
