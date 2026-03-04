import UIKit

final class MainCoordinator: BaseCoordinator {

    let tabBarController = UITabBarController()
    private let context: AppContext

    private var clansNav: UINavigationController?
    private var messagesNav: UINavigationController?
    private var notificationsNav: UINavigationController?
    private var profileNav: UINavigationController?

    init(context: AppContext) {
        self.context = context
    }

    override func start() {
        clansNav         = makeClansTab()
        messagesNav      = makeTab(icon: "bubble.left.and.bubble.right", tag: 1)
        notificationsNav = makeTab(icon: "bell",                          tag: 2)
        profileNav       = makeTab(icon: "person.crop.circle",            tag: 3)

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
        let clanVM    = ClanListViewModel(context: context)
        let channelVM = ChannelListViewModel(context: context)
        let homeVC    = HomeViewController(clanVM: clanVM, channelVM: channelVM)

        let nav = UINavigationController(rootViewController: homeVC)
        nav.navigationBar.prefersLargeTitles = false
        nav.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: "house"), tag: 0)
        nav.navigationBar.isHidden = true
        return nav
    }

    private func makeTab(icon: String, tag: Int) -> UINavigationController {
        let vc = UIViewController()
        vc.view.backgroundColor = .mezonBackground
        let nav = UINavigationController(rootViewController: vc)
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
