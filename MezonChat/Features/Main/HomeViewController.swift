import UIKit
import AsyncDisplayKit

final class HomeViewController: BaseViewController {

    private let clanListVC: ClanListViewController
    private let channelListVC: ChannelListViewController
    private let context: AccountContext

    private let clanSidebarWidth: CGFloat = Constants.Layout.clanSidebarWidth

    init(context: AccountContext) {
        self.context = context
        self.clanListVC = ClanListViewController(context: context)
        self.channelListVC = ChannelListViewController(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        embedChildren()
        bindClanSelection()
        bindChannelSelection()
        bindLogoTap()
        applyInitialClanSelection()

        NotificationCenter.default.addObserver(self, selector: #selector(handleNavigateToChannel(_:)), name: .mezonNavigateToChannel, object: nil)

        processPendingNavigation()
    }

    private func processPendingNavigation() {
        guard let pending = AppDelegate.pendingNavigation else { return }
        AppDelegate.pendingNavigation = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard self != nil else { return }
            NotificationCenter.default.post(name: .mezonNavigateToChannel, object: nil, userInfo: pending)
        }
    }

    /// On launch: if we have a cached selected clan, configure channel list and fetch channels.
    private func applyInitialClanSelection() {
        guard let id = clanListVC.selectedClanId,
              let clan = clanListVC.clans.first(where: { $0.clanID == id }) else { return }
        context.currentClanId = id
        channelListVC.configure(clanId: id, clanName: clan.clanName)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let clanLayout = layout.withUpdatedSize(CGSize(width: clanSidebarWidth, height: layout.size.height))
        clanListVC.containerLayoutUpdated(clanLayout, transition: transition)

        let channelWidth = max(0, layout.size.width - clanSidebarWidth)
        let channelLayout = layout.withUpdatedSize(CGSize(width: channelWidth, height: layout.size.height))
        channelListVC.containerLayoutUpdated(channelLayout, transition: transition)
    }

    private func embedChildren() {
        addChild(clanListVC)
        view.addSubview(clanListVC.view)
        clanListVC.view.translatesAutoresizingMaskIntoConstraints = false
        clanListVC.didMove(toParent: self)

        addChild(channelListVC)
        view.addSubview(channelListVC.view)
        channelListVC.view.translatesAutoresizingMaskIntoConstraints = false
        channelListVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            clanListVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            clanListVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clanListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            clanListVC.view.widthAnchor.constraint(equalToConstant: clanSidebarWidth),

            channelListVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            channelListVC.view.leadingAnchor.constraint(equalTo: clanListVC.view.trailingAnchor),
            channelListVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindLogoTap() {
        clanListVC.onLogoTapped = { [weak self] in
            guard let self else { return }
            if let tabBar = self.parent as? TabBarController {
                tabBar.selectedIndex = 1
            }
        }
    }

    private func bindClanSelection() {
        disposables.add(
            (clanListVC.selectedClanIdSignal |> deliverOnMainQueue)
                .start(next: { [weak self] clanId in
                    guard let clanId, let self else { return }
                    let name = self.clanListVC.clans.first(where: { $0.clanID == clanId })?.clanName ?? ""
                    self.channelListVC.configure(clanId: clanId, clanName: name)
                })
        )
    }

    private func bindChannelSelection() {
        disposables.add(
            (channelListVC.selectedChannelSignal |> deliverOnMainQueue)
                .start(next: { [weak self] channel in
                    guard let channel, let self else { return }
                    let chatVC = ChatViewController(clanId: self.channelListVC.clanId, channel: channel, context: self.context)
                    self.navigationController?.pushViewController(chatVC, animated: true)
                })
        )
    }

    @objc private func handleNavigateToChannel(_ notification: Notification) {
        guard let channelIdStr = notification.userInfo?["channelId"] as? String else { return }
        let clanIdStr = notification.userInfo?["clanId"] as? String
        let isDM = notification.userInfo?["isDM"] as? Bool ?? false
        let title = notification.userInfo?["title"] as? String

        if isDM {
            navigateToDM(channelIdStr: channelIdStr, title: title, retryCount: 0)
        } else {
            navigateToChannel(channelIdStr: channelIdStr, clanIdStr: clanIdStr, retryCount: 0)
        }
    }

    private func navigateToDM(channelIdStr: String, title: String?, retryCount: Int) {
        let maxRetries = 5
        guard let channelIdInt = Int64(channelIdStr) else { return }

        guard let rootController = navigationController as? MezonRootController else {
            if retryCount < maxRetries {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.navigateToDM(channelIdStr: channelIdStr, title: title, retryCount: retryCount + 1)
                }
            }
            return
        }

        if let tabBarVC = rootController.viewControllers.first(where: { $0 is TabBarController }) {
            rootController.popToViewController(tabBarVC, animated: false)
        }

        let dmVC = rootController.directMessagesController
        if let found = dmVC?.directMessages.first(where: { $0.channelID == channelIdInt }) {
            let chatVC = ChatViewController(clanId: 0, channel: found, context: context)
            rootController.pushViewController(chatVC, animated: false)
            return
        }

        guard let token = context.session?.token else {
            if retryCount < maxRetries {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.navigateToDM(channelIdStr: channelIdStr, title: title, retryCount: retryCount + 1)
                }
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                if let dmVC = rootController.directMessagesController {
                    await dmVC.fetchDirectMessages()
                }
                if let ch = channels.first(where: { $0.channelID == channelIdInt }) {
                    let chatVC = ChatViewController(clanId: 0, channel: ch, context: self.context)
                    rootController.pushViewController(chatVC, animated: false)
                } else if retryCount < maxRetries {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.navigateToDM(channelIdStr: channelIdStr, title: title, retryCount: retryCount + 1)
                    }
                }
            } catch {
                AppLogger.network.error("[FCM] Failed to fetch DM channels: \(error)")
                if retryCount < maxRetries {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.navigateToDM(channelIdStr: channelIdStr, title: title, retryCount: retryCount + 1)
                    }
                }
            }
        }
    }

    private func navigateToChannel(channelIdStr: String, clanIdStr: String?, retryCount: Int) {
        let maxRetries = 5

        if let tabBar = self.parent as? TabBarController {
            tabBar.selectedIndex = 0
        }

        if let nav = navigationController {
            if let tabBarVC = nav.viewControllers.first(where: { $0 is TabBarController }) {
                nav.popToViewController(tabBarVC, animated: false)
            } else {
                nav.popToRootViewController(animated: false)
            }
        }

        guard let channelIdInt = Int64(channelIdStr) else { return }

        if let ch = channelListVC.allChannels.first(where: { $0.channelID == channelIdInt }) {
            channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            let chatVC = ChatViewController(clanId: channelListVC.clanId, channel: ch, context: context)
            navigationController?.pushViewController(chatVC, animated: false)
            return
        }

        if let clanIdStr,
           let clanIdInt = Int64(clanIdStr),
           let clan = clanListVC.clans.first(where: { $0.clanID == clanIdInt }),
           clanIdInt != clanListVC.selectedClanId {
            clanListVC.select(clan: clan)
            channelListVC.configure(clanId: clanIdInt, clanName: clan.clanName)
        }

        if retryCount < maxRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.navigateToChannel(channelIdStr: channelIdStr, clanIdStr: clanIdStr, retryCount: retryCount + 1)
            }
        }
    }

    deinit { disposables.dispose() }
}
