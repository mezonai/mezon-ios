import UIKit
import AsyncDisplayKit

final class MezonRootController: NavigationController {
    private let context: AccountContext

    private(set) var rootTabController: TabBarController?
    private(set) var homeController: HomeViewController?
    private(set) var messagesController: MessagesViewController?
    private(set) var profileController: ProfileViewController?

    init(context: AccountContext) {
        self.context = context
        super.init(mode: .single, theme: Self.makeNavTheme())
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    func addRootControllers() {
        let tabBarController = TabBarControllerImpl(navigationBarPresentationData: nil)
        tabBarController.navigationPresentation = .master

        let homeVC = HomeViewController(context: context)
        homeVC.tabBarItem = UITabBarItem(
            title: "Clans",
            image: UIImage(systemName: "square.grid.2x2"),
            selectedImage: UIImage(systemName: "square.grid.2x2.fill")
        )

        let messagesVC = MessagesViewController(context: context)
        messagesVC.tabBarItem = UITabBarItem(
            title: "Messages",
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        )

        let notificationsVC = PlaceholderViewController(title: "Notifications")
        notificationsVC.tabBarItem = UITabBarItem(
            title: "Notifications",
            image: UIImage(systemName: "bell"),
            selectedImage: UIImage(systemName: "bell.fill")
        )

        let profileVC = ProfileViewController(context: context)
        profileVC.tabBarItem = UITabBarItem(
            title: "Account",
            image: UIImage(systemName: "person.crop.circle"),
            selectedImage: UIImage(systemName: "person.crop.circle.fill")
        )

        let controllers: [ViewController] = [homeVC, messagesVC, notificationsVC, profileVC]
        tabBarController.setControllers(controllers, selectedIndex: 0)

        self.homeController = homeVC
        self.messagesController = messagesVC
        self.profileController = profileVC
        self.rootTabController = tabBarController

        pushViewController(tabBarController, animated: false)

        Task { await messagesVC.fetchDirectMessages() }
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
