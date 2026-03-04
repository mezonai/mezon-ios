import UIKit

final class AuthCoordinator: BaseCoordinator {

    let navigationController = UINavigationController()
    private let context: AppContext

    init(context: AppContext) {
        self.context = context
    }

    override func start() {
        showLogin()
    }


    private func showLogin() {
        let vm = LoginViewModel(context: context)

        vm.onLoginSuccess = { [weak self] user, session in
            Task { @MainActor in self?.context.login(user: user, session: session) }
        }

        vm.onOTPRequired = { [weak self] otpContext in
            self?.showVerifyOTP(otpContext: otpContext)
        }

        let vc = LoginViewController(viewModel: vm)
        navigationController.setViewControllers([vc], animated: false)
    }

    private func showVerifyOTP(otpContext: OTPContext) {
        let vm = VerifyOTPViewModel(otpContext: otpContext)

        vm.onVerifySuccess = { [weak self] user, session in
            Task { @MainActor in self?.context.login(user: user, session: session) }
        }

        let vc = VerifyOTPViewController(viewModel: vm)
        navigationController.pushViewController(vc, animated: true)
    }
}
