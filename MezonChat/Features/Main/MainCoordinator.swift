import UIKit

final class MainCoordinator: BaseCoordinator {

    let tabBarController = UITabBarController()
    private let sharedContext: SharedAccountContext

    private var clansNav: UINavigationController?
    private var messagesNav: UINavigationController?
    private var notificationsNav: UINavigationController?
    private var profileNav: UINavigationController?

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
    }

    override func start() {
        clansNav         = makeClansTab()
        messagesNav      = makeMessagesTab()
        notificationsNav = makeTab(icon: "bell",                          tag: 2)
        profileNav       = makeProfileTab()

        tabBarController.viewControllers = [clansNav, messagesNav, notificationsNav, profileNav].compactMap { $0 }
        styleTabBar()
        applyLanguage()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: LanguageManager.didChangeNotification,
            object: nil
        )
    }


    private func makeClansTab() -> UINavigationController {
        let clanVM    = ClanListViewModel(sharedContext: sharedContext)
        let channelVM = ChannelListViewModel(sharedContext: sharedContext)
        let homeVC    = HomeViewController(clanVM: clanVM, channelVM: channelVM, sharedContext: sharedContext)

        let nav = UINavigationController(rootViewController: homeVC)
        nav.navigationBar.prefersLargeTitles = false
        nav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "house"), tag: 0)
        nav.navigationBar.isHidden = true
        return nav
    }

    private func makeMessagesTab() -> UINavigationController {
        let vm = MessagesViewModel(sharedContext: sharedContext)
        let vc = MessagesViewController(viewModel: vm, sharedContext: sharedContext)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.isHidden = true
        nav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "bubble.left.and.bubble.right"), tag: 1)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    private func makeProfileTab() -> UINavigationController {
        let vc = ProfileViewController(sharedContext: sharedContext)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.isHidden = true
        nav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "person.crop.circle"), tag: 3)
        return nav
    }

    private func makeTab(icon: String, tag: Int) -> UINavigationController {
        let vm  = NotificationsViewModel(sharedContext: sharedContext)
        let vc  = NotificationViewController(viewModel: vm, sharedContext: sharedContext)
        let nav = UINavigationController(rootViewController: vc)
        vc.view.backgroundColor = .mezonBackground
        nav.navigationBar.isHidden = true
        nav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: icon), tag: tag)
        return nav
    }


    @objc private func applyLanguage() {
        clansNav?.tabBarItem.title         = L(L10n.Tab.clans)
        messagesNav?.tabBarItem.title      = L(L10n.Tab.messages)
        notificationsNav?.tabBarItem.title = L(L10n.Tab.notifications)
        profileNav?.tabBarItem.title       = L(L10n.Tab.profile)
    }

    @objc private func handleLanguageChange() {
        applyLanguage()
    }


    private func styleTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBarController.tabBar.standardAppearance  = appearance
        tabBarController.tabBar.scrollEdgeAppearance = appearance
    }
}
