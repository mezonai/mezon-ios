import UIKit
import AsyncDisplayKit

final class MezonRootController: NavigationController {
    private let context: AccountContext
    private static let tabBarBundle = Bundle.main

    private(set) var rootTabController: TabBarController?
    private(set) var homeController: HomeViewController?
    private(set) var directMessagesController: DirectMessagesViewController?
    private(set) var profileController: ProfileViewController?

    init(context: AccountContext) {
        self.context = context
        super.init(mode: .single, theme: Self.makeNavTheme())
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    private static func tabBarImage(name: String, systemFallback: String, systemFallbackSelected: String? = nil) -> (image: UIImage?, selectedImage: UIImage?) {
        let custom = UIImage(named: name, in: tabBarBundle, compatibleWith: nil)
        let selected = UIImage(named: name, in: tabBarBundle, compatibleWith: nil)
        if custom != nil {
            return (custom, selected ?? custom)
        }
        return (
            UIImage(systemName: systemFallback),
            UIImage(systemName: systemFallbackSelected ?? systemFallback.replacingOccurrences(of: ".fill", with: "") + ".fill")
        )
    }

    func addRootControllers() {
        let tabBarController = TabBarControllerImpl(navigationBarPresentationData: nil)
        tabBarController.navigationPresentation = .master

        let (clansImg, clansSel) = Self.tabBarImage(name: "TabBar/ClansIcon", systemFallback: "square.grid.2x2", systemFallbackSelected: "square.grid.2x2.fill")
        let homeVC = HomeViewController(context: context)
        homeVC.tabBarItem = UITabBarItem(
            title: L(L10n.Tab.clans),
            image: clansImg,
            selectedImage: clansSel
        )

        let (messagesImg, messagesSel) = Self.tabBarImage(name: "TabBar/MessagesIcon", systemFallback: "bubble.left.and.bubble.right", systemFallbackSelected: "bubble.left.and.bubble.right.fill")
        let directMessagesVC = DirectMessagesViewController(context: context)
        directMessagesVC.tabBarItem = UITabBarItem(
            title: L(L10n.Tab.messages),
            image: messagesImg,
            selectedImage: messagesSel
        )

        let (notifImg, notifSel) = Self.tabBarImage(name: "TabBar/NotificationIcon", systemFallback: "bell", systemFallbackSelected: "bell.fill")
        let notificationsVC = PlaceholderViewController(title: L(L10n.Tab.notifications))
        notificationsVC.tabBarItem = UITabBarItem(
            title: L(L10n.Tab.notifications),
            image: notifImg,
            selectedImage: notifSel
        )

        let (profileImg, profileSel) = Self.tabBarImage(name: "TabBar/ProfileIcon", systemFallback: "person.crop.circle", systemFallbackSelected: "person.crop.circle.fill")
        let profileVC = ProfileViewController(context: context)
        profileVC.tabBarItem = UITabBarItem(
            title: L(L10n.Tab.profile),
            image: profileImg,
            selectedImage: profileSel
        )

        let controllers: [ViewController] = [homeVC, directMessagesVC, notificationsVC, profileVC]
        tabBarController.setControllers(controllers, selectedIndex: 0)

        self.homeController = homeVC
        self.directMessagesController = directMessagesVC
        self.profileController = profileVC
        self.rootTabController = tabBarController

        pushViewController(tabBarController, animated: false)

        Task { await directMessagesVC.fetchDirectMessages() }
    }

    static func makeNavTheme() -> NavigationControllerTheme {
        NavigationControllerTheme(
            statusBar: .black,
            navigationBar: NavigationBarTheme(
                overallDarkAppearance: false,
                buttonColor: UIColor.theme.textStrong,
                disabledButtonColor: UIColor.theme.textDisabled,
                primaryTextColor: UIColor.theme.textStrong,
                backgroundColor: UIColor.theme.secondary,
                enableBackgroundBlur: false,
                separatorColor: UIColor.theme.border,
                badgeBackgroundColor: .systemRed,
                badgeStrokeColor: .clear,
                badgeTextColor: .white
            ),
            emptyAreaColor: UIColor.theme.primary
        )
    }
}
