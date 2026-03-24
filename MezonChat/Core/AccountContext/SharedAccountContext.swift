import Foundation
import UIKit

@MainActor
protocol SharedAccountContext: AnyObject {
    var mainWindow: Window1? { get }
    var basePath: String { get }

    var currentPresentationTheme: AppTheme { get }

    var activeAccountContext: Signal<AccountContext?, NoError> { get }

    func makeMezonRootController(context: AccountContext) -> MezonRootController
    func makeLoginController(context: AccountContext) -> NavigationController
}

@MainActor
final class SharedAccountContextImpl: SharedAccountContext {
    let mainWindow: Window1?
    let basePath: String

    var currentPresentationTheme: AppTheme { ThemeManager.shared.current }

    private let activeAccountContextPipe = ValuePipe<AccountContext?>()
    var activeAccountContext: Signal<AccountContext?, NoError> { activeAccountContextPipe.signal() }

    private var _accountContext: AccountContextImpl?

    init(mainWindow: Window1?, basePath: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "") {
        self.mainWindow = mainWindow
        self.basePath = basePath
    }

    func createAccountContext(
        session: MezonSession,
        user: User?,
        onReady: @escaping @MainActor (AccountContextImpl) -> Void
    ) -> AccountContextImpl {
        let account = Account(id: session.userId ?? UUID().uuidString)
        let context = AccountContextImpl(
            sharedContext: self,
            account: account,
            session: session,
            user: user,
            onReady: onReady
        )
        _accountContext = context
        activeAccountContextPipe.putNext(context)
        return context
    }

    func createUnauthorizedContext(
        onReady: @escaping @MainActor (AccountContextImpl) -> Void
    ) -> AccountContextImpl {
        let account = Account(id: "unauthorized")
        let context = AccountContextImpl(
            sharedContext: self,
            account: account,
            session: nil,
            user: nil,
            onReady: onReady
        )
        _accountContext = context
        activeAccountContextPipe.putNext(context)
        return context
    }

    func clearAccountContext() {
        _accountContext = nil
        activeAccountContextPipe.putNext(nil)
    }

    func makeMezonRootController(context: AccountContext) -> MezonRootController {
        MezonRootController(context: context)
    }

    func makeLoginController(context: AccountContext) -> NavigationController {
        let nav = NavigationController(mode: .single, theme: MezonRootController.makeNavTheme())
        nav.setViewControllers([WelcomeController(context: context)], animated: false)
        return nav
    }
}
