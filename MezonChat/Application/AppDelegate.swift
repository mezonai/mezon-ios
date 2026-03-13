import UIKit

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
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

    @objc private func handleWillEnterForeground() { accountContext?.recoverFromForeground() }
    @objc private func handleDidBecomeActive() { accountContext?.recoverFromForeground() }

    deinit { disposables.dispose() }
}
