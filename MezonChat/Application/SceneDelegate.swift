import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        let sharedDataStore = SharedDataStore()
        let appContext = AppContext(sharedDataStore: sharedDataStore)
        MezonSocket.shared.messagesStore = sharedDataStore.messagesStore
        let sharedContext = SharedAccountContext(appContext: appContext, sharedDataStore: sharedDataStore)
        let coordinator = AppCoordinator(window: window, sharedContext: sharedContext)
        appCoordinator = coordinator
        coordinator.start()

        window.makeKeyAndVisible()
    }
}
