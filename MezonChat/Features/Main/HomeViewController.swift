import UIKit
import AsyncDisplayKit
import UserNotifications

final class HomeViewController: BaseViewController {

    let clanListVC: ClanListViewController
    let channelListVC: ChannelListViewController
    private let context: AccountContext
    private lazy var discoverEmptyOverlayVC: DiscoverClanEmptyStateViewController = {
        DiscoverClanEmptyStateViewController(context: context)
    }()

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
        embedDiscoverOverlay()
        bindClanSelection()
        bindChannelSelection()
        bindSearchTapped()
        bindLogoTap()
        bindDismissDiscoverOnClanSelect()
        bindClanJoinCreate()
        bindDiscoverEmptyOverlay()
        applyInitialClanSelection()
        DispatchQueue.main.async { [weak self] in
            self?.applyInitialClanSelection()
        }

        self.scrollToTopWithTabBar = { [weak self] in
            guard let self else { return }
            if self.clanListVC.discoverEmptyOverlayShouldShow {
                self.focusDiscoverWhenNoClansFromTab()
            } else {
                self.scrollToTop?()
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleHomeThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: Notification.Name("MezonMentionReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppBadgeCount), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAlignHomeAfterCrossClanVoice(_:)), name: .mezonAlignHomeAfterCrossClanVoice, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAlignChannelListAfterSearchJump(_:)), name: .mezonAlignChannelListAfterSearchJump, object: nil)

        bindBadgeCountUpdates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        discoverEmptyOverlayVC.hostNavigationController = navigationController
        syncMainColumnZOrder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let tab = parent as? TabBarController, tab.selectedIndex == 0 {
            presentDiscoverWhenNoClansIfNeeded()
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard parent is TabBarController else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.parent is TabBarController else { return }
            self.syncMainColumnZOrder()
            self.resyncNestedSidebarAndChannelDisplayNodes()
        }
    }

    private func syncMainColumnZOrder() {
        if discoverEmptyOverlayVC.view.isHidden {
            view.bringSubviewToFront(channelListVC.view)
        } else {
            view.bringSubviewToFront(discoverEmptyOverlayVC.view)
        }
    }

    private func focusDiscoverWhenNoClansFromTab() {
        guard clanListVC.discoverEmptyOverlayShouldShow else { return }
        discoverEmptyOverlayVC.reloadDiscoverList()
        discoverEmptyOverlayVC.view.isHidden = false
        view.bringSubviewToFront(discoverEmptyOverlayVC.view)
        clanListVC.focusDiscoverInSidebar()
        syncMainColumnZOrder()
    }

    private func presentDiscoverWhenNoClansIfNeeded() {
        guard clanListVC.discoverEmptyOverlayShouldShow else { return }
        discoverEmptyOverlayVC.view.isHidden = false
        view.bringSubviewToFront(discoverEmptyOverlayVC.view)
        clanListVC.focusDiscoverInSidebar()
        syncMainColumnZOrder()
    }

    private func resyncNestedSidebarAndChannelDisplayNodes() {
        clanListVC.displayNode.recursivelyEnsureDisplaySynchronously(true)
        channelListVC.displayNode.recursivelyEnsureDisplaySynchronously(true)
    }

    @objc private func handleHomeThemeChange() {
        view.backgroundColor = UIColor.theme.primary
    }

    private static func int64FromAlignUserInfo(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    func focusClansTabAndSelectVoiceChannelOnly(_ channelId: Int64) {
        if let tab = parent as? TabBarController {
            tab.selectedIndex = 0
        }
        guard channelId != 0 else { return }
        channelListVC.selectWithoutNavigation(channelId: channelId)
    }

    func alignHomeForCrossClanVoice(clanId: Int64, voiceChannelId: Int64) {
        guard clanId != 0 else { return }
        if let tab = parent as? TabBarController {
            tab.selectedIndex = 0
        }
        if let clan = clanListVC.clans.first(where: { $0.clanID == clanId }) {
            clanListVC.select(clan: clan)
            if voiceChannelId != 0 {
                channelListVC.selectWithoutNavigation(channelId: voiceChannelId)
            }
            return
        }
        context.currentClanId = clanId
        clanListVC.loadClans()
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<50 {
                if self.context.account.socket.isConnected { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if self.context.account.socket.isConnected {
                self.context.account.socket.joinClanChat(clanId: clanId)
            }
            guard let token = await self.context.getToken() else { return }
            self.context.engine.clanData.fetchAllClanData(clanId: clanId, token: token)
            self.channelListVC.configure(
                clanId: clanId,
                clanName: "",
                logoURL: nil,
                bannerURL: nil,
                memberCount: 0,
                isCommunity: false
            )
            if voiceChannelId != 0 {
                self.channelListVC.selectWithoutNavigation(channelId: voiceChannelId)
            }
        }
    }

    @objc private func handleAlignHomeAfterCrossClanVoice(_ notification: Notification) {
        guard let clanId = Self.int64FromAlignUserInfo(notification.userInfo?["clanId"]), clanId != 0 else { return }
        let channelId = Self.int64FromAlignUserInfo(notification.userInfo?["channelId"]) ?? 0
        alignHomeForCrossClanVoice(clanId: clanId, voiceChannelId: channelId)
    }

    @objc private func handleAlignChannelListAfterSearchJump(_ notification: Notification) {
        guard let clanId = Self.int64FromAlignUserInfo(notification.userInfo?["clanId"]), clanId != 0 else { return }
        let channelId = Self.int64FromAlignUserInfo(notification.userInfo?["channelId"]) ?? 0
        guard channelId != 0 else { return }
        alignHomeForCrossClanVoice(clanId: clanId, voiceChannelId: channelId)
    }

    private func channelSidebarMemberCount(clanId: Int64) -> Int {
        context.engine.clanData.getClanUsers(clanId: clanId)?.clanUsers.count ?? 0
    }

    private func applyInitialClanSelection() {
        guard let id = clanListVC.selectedClanId, id != 0 else { return }
        context.currentClanId = id
        let clan = clanListVC.clans.first(where: { $0.clanID == id })
        let memberCount = channelSidebarMemberCount(clanId: id)
        channelListVC.configure(clanId: id, clanName: clan?.clanName ?? "", logoURL: clan?.logo, bannerURL: clan?.banner, memberCount: memberCount, isCommunity: clan?.isCommunity ?? false)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let clanOriginLayout = layout.withUpdatedSize(CGSize(width: clanSidebarWidth, height: layout.size.height))
        let si = layout.safeInsets
        let clanLayout = clanOriginLayout.withUpdatedSafeInsets(
            UIEdgeInsets(top: si.top, left: 0, bottom: si.bottom, right: 0))
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
            clanListVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            clanListVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clanListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            clanListVC.view.widthAnchor.constraint(equalToConstant: clanSidebarWidth),

            channelListVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            channelListVC.view.leadingAnchor.constraint(equalTo: clanListVC.view.trailingAnchor),
            channelListVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func embedDiscoverOverlay() {
        let vc = discoverEmptyOverlayVC
        vc.hostNavigationController = navigationController
        vc.onUserJoinedClan = { [weak self] in
            self?.clanListVC.loadClans()
        }
        addChild(vc)
        view.addSubview(vc.view)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: clanListVC.view.trailingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        vc.didMove(toParent: self)
        vc.view.isHidden = true
    }

    private func bindDiscoverEmptyOverlay() {
        discoverEmptyOverlayVC.view.isHidden = !clanListVC.discoverEmptyOverlayShouldShow
        disposables.add(
            (clanListVC.showDiscoverEmptyOverlaySignal |> deliverOnMainQueue)
                .start(next: { [weak self] show in
                    guard let self else { return }
                    self.discoverEmptyOverlayVC.view.isHidden = !show
                    if show {
                        self.view.bringSubviewToFront(self.discoverEmptyOverlayVC.view)
                        self.clanListVC.focusDiscoverInSidebar()
                    } else {
                        self.view.bringSubviewToFront(self.channelListVC.view)
                    }
                })
        )
    }

    private func dismissDiscoverOverlayIfPresent() {
        guard !discoverEmptyOverlayVC.view.isHidden else { return }
        discoverEmptyOverlayVC.view.isHidden = true
        view.bringSubviewToFront(channelListVC.view)
    }

    private func bindDismissDiscoverOnClanSelect() {
        clanListVC.onClanSelected = { [weak self] in
            self?.dismissDiscoverOverlayIfPresent()
        }
    }

    private func bindLogoTap() {
        clanListVC.onLogoTapped = { [weak self] in
            guard let self else { return }
            self.dismissDiscoverOverlayIfPresent()
            let rootController = self.navigationController as? MezonRootController
            if let tabBar = self.parent as? TabBarController {
                tabBar.selectedIndex = 1
            }
            rootController?.directMessagesController?.fetchDirectMessages()
        }
    }

    private func bindClanJoinCreate() {
        clanListVC.onJoinClanTapped = { [weak self] in
            guard let self else { return }
            self.discoverEmptyOverlayVC.reloadDiscoverList()
            self.discoverEmptyOverlayVC.view.isHidden = false
            self.view.bringSubviewToFront(self.discoverEmptyOverlayVC.view)
        }
        clanListVC.onCreateClanTapped = { [weak self] in
            guard let self else { return }
            let vc = CreateClanEntryViewController(context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    private func presentModalSheet(_ vc: UIViewController) {
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = vc.sheetPresentationController {
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
                sheet.detents = [.medium()]
                sheet.prefersEdgeAttachedInCompactHeight = true
            }
        }
        present(vc, animated: true)
    }

    private func bindClanSelection() {
        disposables.add(
            (clanListVC.selectedClanIdSignal |> deliverOnMainQueue)
                .start(next: { [weak self] clanId in
                    guard let self else { return }
                    guard let clanId, clanId != 0 else {
                        self.context.currentClanId = 0
                        self.channelListVC.configure(clanId: 0, clanName: "", logoURL: nil, bannerURL: nil, memberCount: 0, isCommunity: false)
                        return
                    }
                    self.context.currentClanId = clanId
                    let clan = self.clanListVC.clans.first(where: { $0.clanID == clanId })
                    let memberCount = self.channelSidebarMemberCount(clanId: clanId)
                    self.channelListVC.configure(clanId: clanId, clanName: clan?.clanName ?? "", logoURL: clan?.logo, bannerURL: clan?.banner, memberCount: memberCount, isCommunity: clan?.isCommunity ?? false)
                })
        )
        disposables.add(
            (context.engine.clanData.clanUsersUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] clanId in
                    guard let self else { return }
                    guard clanId != 0, clanId == self.context.currentClanId, clanId == self.channelListVC.clanId else { return }
                    let memberCount = self.channelSidebarMemberCount(clanId: clanId)
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
                    if let nav = self.navigationController as? NavigationController {
                        nav.pushViewController(
                            chatVC, animated: true,
                            stackPushAnimationDuration: NavigationController.channelListToChatPushAnimationDuration)
                    } else {
                        self.navigationController?.pushViewController(chatVC, animated: true)
                    }
                })
        )
    }

    func openChannelForOnboarding(_ channel: Mezon_Api_ChannelDescription) {
        guard channel.channelID != 0 else { return }
        channelListVC.selectWithoutNavigation(channelId: channel.channelID)

        guard let nav = navigationController else { return }

        if let existing = nav.viewControllers
            .compactMap({ $0 as? ChatViewController })
            .first(where: { $0.channel.channelID == channel.channelID }) {
            nav.popToViewController(existing, animated: true)
            return
        }

        var parentName: String?
        if channel.parentID != 0 {
            parentName = channelListVC.allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: channelListVC.clanId,
            channel: channel,
            context: context,
            parentName: parentName
        )
        var stack = nav.viewControllers
        stack.removeAll { $0 is ChatViewController }
        stack.append(chatVC)
        if let mezonNav = nav as? NavigationController {
            mezonNav.setViewControllers(stack, animated: true)
        } else {
            nav.setViewControllers(stack, animated: true)
        }
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
