import UIKit
import Combine

final class AppCoordinator: BaseCoordinator {

    private let window: UIWindow
    private let context: AppContext
    private var cancellables = Set<AnyCancellable>()

    init(window: UIWindow, context: AppContext) {
        self.window = window
        self.context = context
    }

    override func start() {
        showLoading()

        context.$isSessionReady
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startMain()
            }
            .store(in: &cancellables)
    }

    private func startMain() {
        context.$isLoggedIn
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] isLoggedIn in
                isLoggedIn ? self?.showMain() : self?.showAuth()
            }
            .store(in: &cancellables)
    }

    private func showLoading() {
        window.rootViewController = SplashViewController()
        window.makeKeyAndVisible()
    }

    private func showAuth() {
        childCoordinators.removeAll()
        let coordinator = AuthCoordinator(context: context)
        addChild(coordinator)
        let nav = coordinator.navigationController
        nav.modalPresentationStyle = .fullScreen
        window.rootViewController = nav
        coordinator.start()
        animateTransition()
    }

    private func showMain() {
        childCoordinators.removeAll()
        let coordinator = MainCoordinator(context: context)
        addChild(coordinator)
        window.rootViewController = coordinator.tabBarController
        coordinator.start()
        animateTransition()
    }

    private func animateTransition() {
        UIView.transition(
            with: window,
            duration: Constants.Animation.defaultDuration,
            options: .transitionCrossDissolve,
            animations: nil
        )
    }
}
