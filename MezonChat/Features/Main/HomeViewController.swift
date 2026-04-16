import UIKit
import AsyncDisplayKit
import UserNotifications

final class HomeViewController: BaseViewController {

    let clanListVC: ClanListViewController
    let channelListVC: ChannelListViewController
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
        bindSearchTapped()
        bindLogoTap()
        applyInitialClanSelection()
        DispatchQueue.main.async { [weak self] in
            self?.applyInitialClanSelection()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleHomeThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: Notification.Name("MezonMentionReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: UIApplication.willEnterForegroundNotification, object: nil)

        bindBadgeCountUpdates()
    }

    @objc private func handleHomeThemeChange() {
        view.backgroundColor = UIColor.theme.primary
    }

    private func applyInitialClanSelection() {
        guard let id = clanListVC.selectedClanId,
              let clan = clanListVC.clans.first(where: { $0.clanID == id }) else { return }
        context.currentClanId = id
        let users = context.engine.clanData.getClanUsers(clanId: id)?.clanUsers ?? []
        let memberCount = users.count
        let onlineCount = users.filter { $0.user.online }.count
        channelListVC.configure(clanId: id, clanName: clan.clanName, logoURL: clan.logo, bannerURL: clan.banner, memberCount: memberCount, onlineCount: onlineCount, isCommunity: clan.isCommunity)
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

            channelListVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            channelListVC.view.leadingAnchor.constraint(equalTo: clanListVC.view.trailingAnchor),
            channelListVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func bindLogoTap() {
        clanListVC.onLogoTapped = { [weak self] in
            guard let self else { return }
            let rootController = self.navigationController as? MezonRootController
            if let tabBar = self.parent as? TabBarController {
                tabBar.selectedIndex = 1
            }
            rootController?.directMessagesController?.fetchDirectMessages()
        }
    }

    private func bindClanSelection() {
        disposables.add(
            (clanListVC.selectedClanIdSignal |> deliverOnMainQueue)
                .start(next: { [weak self] clanId in
                    guard let clanId, let self else { return }
                    let clan = self.clanListVC.clans.first(where: { $0.clanID == clanId })
                    let users = self.context.engine.clanData.getClanUsers(clanId: clanId)?.clanUsers ?? []
                    let memberCount = users.count
                    let onlineCount = users.filter { $0.user.online }.count
                    self.channelListVC.configure(clanId: clanId, clanName: clan?.clanName ?? "", logoURL: clan?.logo, bannerURL: clan?.banner, memberCount: memberCount, onlineCount: onlineCount, isCommunity: clan?.isCommunity ?? false)
                })
        )
        disposables.add(
            (context.engine.clanData.clanUsersUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] clanId in
                    guard let self, clanId == self.channelListVC.clanId else { return }
                    let memberCount = self.context.engine.clanData.getClanUsers(clanId: clanId)?.clanUsers.count ?? 0
                    self.channelListVC.updateMemberCount(memberCount)
                })
        )
    }

    private func bindChannelSelection() {
        disposables.add(
            (channelListVC.selectedChannelSignal |> deliverOnMainQueue)
                .start(next: { [weak self] channel in
                    guard let channel, let self else { return }
                    if channel.type == MezonConstants.ChannelType.mezonVoice.rawValue { return }
                    var parentName: String?
                    if channel.parentID != 0 {
                        parentName = self.channelListVC.allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
                    }
                    let chatVC = ChatViewController(clanId: self.channelListVC.clanId, channel: channel, context: self.context, parentName: parentName)
                    self.navigationController?.pushViewController(chatVC, animated: true)
                })
        )
    }

    private func bindSearchTapped() {
        disposables.add(
            (channelListVC.searchTappedSignal |> deliverOnMainQueue)
                .start(next: { [weak self] in
                    guard let self else { return }
                    let searchVC = SearchViewController(
                        clanId: self.channelListVC.clanId,
                        context: self.context,
                        channels: self.channelListVC.allChannels
                    )
                    self.navigationController?.pushViewController(searchVC, animated: true)
                })
        )
    }

    private func bindBadgeCountUpdates() {
        disposables.add(
            (context.engine.clanData.clanBadgeCountUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] _ in
                    self?.updateAppBadgeCount()
                })
        )
        disposables.add(
            (clanListVC.clansSignal |> deliverOnMainQueue)
                .start(next: { [weak self] _ in
                    self?.updateAppBadgeCount()
                })
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.updateAppBadgeCount()
        }
    }

    @objc private func updateAppBadgeCount() {
        let clanBadgeTotal = clanListVC.clans.reduce(Int(0)) { total, clan in
            let count = Int(clan.badgeCount)
            return total + (count > 0 ? count : 0)
        }

        let dmUnreadTotal = clanListVC.unreadDMs.reduce(Int(0)) { total, dm in
            total + Int(dm.countMessUnread)
        }

        let badgeCount = max(0, clanBadgeTotal + dmUnreadTotal)

        let shared = UserDefaults(suiteName: "group.mezon.mobile")
        shared?.set(badgeCount, forKey: "badgeCount")

        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(badgeCount)
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        disposables.dispose()
    }
}
