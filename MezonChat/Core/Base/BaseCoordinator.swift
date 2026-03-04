import UIKit

@MainActor
protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get set }
    func start()
}

@MainActor
class BaseCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []

    var onFinish: (() -> Void)?

    func start() {}

    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }

    func removeChild(_ coordinator: Coordinator) {
        childCoordinators = childCoordinators.filter { $0 !== coordinator }
    }
}
