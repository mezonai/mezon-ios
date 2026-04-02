import UIKit
import AsyncDisplayKit

final class MezonRootController: NavigationController {
    private let context: AccountContext
    private static let tabBarBundle = Bundle.main
    private let navigationDisposable = MetaDisposable()

    private(set) var rootTabController: TabBarController?
    private(set) var homeController: HomeViewController?
    private(set) var directMessagesController: DirectMessagesViewController?
    private(set) var notificationsController: NotificationsViewController?
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

        let (notifImg, notifSel) = Self.tabBarImage(
            name: "TabBar/NotificationIcon", systemFallback: "bell",
            systemFallbackSelected: "bell.fill")
        let notificationsVC = NotificationsViewController(context: context)
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
        self.notificationsController = notificationsVC
        self.profileController = profileVC
        self.rootTabController = tabBarController

        pushViewController(tabBarController, animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(handleNavigateToChannel(_:)), name: .mezonNavigateToChannel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleQRSelectClanRoot(_:)), name: .mezonQRSelectClan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleQRNavigateToDM(_:)), name: .mezonQRNavigateToDM, object: nil)

        processPendingNavigation()
    }

    private func processPendingNavigation() {
        guard let pending = AppDelegate.pendingNavigation else { return }
        AppDelegate.pendingNavigation = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    await self.context.waitForSessionReady()
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
                _ = await group.next()
                group.cancelAll()
            }
            NotificationCenter.default.post(name: .mezonNavigateToChannel, object: nil, userInfo: pending)
        }
    }

    // MARK: - Notification Navigation

    @objc private func handleQRSelectClanRoot(_ notification: Notification) {
        rootTabController?.selectedIndex = 0
        popToTabBarController()
    }

    @objc private func handleQRNavigateToDM(_ notification: Notification) {
        guard let channelIdStr = notification.userInfo?["channelId"] as? String else { return }
        let title = notification.userInfo?["title"] as? String
        navigateToDM(channelIdStr: channelIdStr, title: title)
    }

    @objc private func handleNavigateToChannel(_ notification: Notification) {
        guard let channelIdStr = notification.userInfo?["channelId"] as? String else { return }
        let clanIdStr = notification.userInfo?["clanId"] as? String
        let isDM = notification.userInfo?["isDM"] as? Bool ?? false
        let title = notification.userInfo?["title"] as? String

        if isDM {
            navigateToDM(channelIdStr: channelIdStr, title: title)
        } else {
            navigateToChannel(channelIdStr: channelIdStr, clanIdStr: clanIdStr)
        }
    }

    private func isChatAlreadyVisible(channelId: Int64) -> Bool {
        guard let topVC = topViewController as? ChatViewController else { return false }
        return topVC.channel.channelID == channelId
    }

    private func popToTabBarController() {
        if let tabBarVC = viewControllers.first(where: { $0 is TabBarController }) {
            popToViewController(tabBarVC, animated: false)
        }
    }

    private func navigateToDM(channelIdStr: String, title: String?) {
        guard let channelIdInt = Int64(channelIdStr) else { return }
        if isChatAlreadyVisible(channelId: channelIdInt) { return }

        popToTabBarController()

        let resolvedChannel: Mezon_Api_ChannelDescription = {
            if let found = directMessagesController?.directMessages.first(where: { $0.channelID == channelIdInt }) {
                return found
            }
            if let cached = context.account.postbox.getDMChannelDescription(channelId: channelIdInt) {
                return cached
            }
            var minimal = Mezon_Api_ChannelDescription()
            minimal.channelID = channelIdInt
            minimal.type = MezonConstants.ChannelType.group.rawValue
            return minimal
        }()

        pushViewController(ChatViewController(clanId: 0, channel: resolvedChannel, context: context), animated: false)

        Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            do {
                _ = try await self.context.account.network.listDirectMessageChannels(token: token)
                self.directMessagesController?.fetchDirectMessages()
            } catch {
                AppLogger.network.error("[FCM] Failed to fetch DM channels in background: \(error)")
            }
        }
    }

    private func navigateToChannel(channelIdStr: String, clanIdStr: String?) {
        guard let channelIdInt = Int64(channelIdStr) else { return }
        if isChatAlreadyVisible(channelId: channelIdInt) { return }

        rootTabController?.selectedIndex = 0

        popToTabBarController()

        guard let homeVC = homeController else { return }

        let notificationClanId: Int64? = clanIdStr.flatMap { Int64($0) }

        if let (cachedClanId, cachedChannel) = context.account.postbox.getChannelDescription(channelId: channelIdInt) {
            switchClanIfNeeded(homeVC: homeVC, toClanId: cachedClanId)
            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var parentName: String?
            if cachedChannel.parentID != 0 {
                parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == cachedChannel.parentID })?.channelLabel
            }
            let chatVC = ChatViewController(clanId: cachedClanId, channel: cachedChannel, context: context, parentName: parentName)
            pushViewController(chatVC, animated: false)
            fetchClanChannelsInBackground(clanId: cachedClanId)
            return
        }

        if let ch = homeVC.channelListVC.allChannels.first(where: { $0.channelID == channelIdInt }) {
            let resolvedClanId = notificationClanId ?? (ch.clanID != 0 ? ch.clanID : homeVC.channelListVC.clanId)
            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var parentName: String?
            if ch.parentID != 0 {
                parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == ch.parentID })?.channelLabel
            }
            let chatVC = ChatViewController(clanId: resolvedClanId, channel: ch, context: context, parentName: parentName)
            pushViewController(chatVC, animated: false)
            return
        }

        let targetClanId: Int64 = notificationClanId ?? homeVC.channelListVC.clanId

        if let notificationClanId, notificationClanId != homeVC.clanListVC.selectedClanId,
           let clan = homeVC.clanListVC.clans.first(where: { $0.clanID == notificationClanId }) {
            homeVC.clanListVC.select(clan: clan)
            homeVC.channelListVC.configure(clanId: notificationClanId, clanName: clan.clanName, logoURL: clan.logo, bannerURL: clan.banner)

            let loaded = homeVC.channelListVC.channelsLoadedSignal
                |> filter { $0 }
                |> take(1)
                |> timeout(5.0, queue: Queue.mainQueue(), alternate: .single(true))
                |> deliverOnMainQueue

            navigationDisposable.set(loaded.start(next: { [weak self] _ in
                guard let self, let homeVC = self.homeController else { return }
                if self.isChatAlreadyVisible(channelId: channelIdInt) { return }

                if let ch = homeVC.channelListVC.allChannels.first(where: { $0.channelID == channelIdInt }) {
                    homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
                    var parentName: String?
                    if ch.parentID != 0 {
                        parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == ch.parentID })?.channelLabel
                    }
                    let chatVC = ChatViewController(clanId: targetClanId, channel: ch, context: self.context, parentName: parentName)
                    self.pushViewController(chatVC, animated: false)
                } else {
                    var minimal = Mezon_Api_ChannelDescription()
                    minimal.channelID = channelIdInt
                    minimal.clanID = targetClanId
                    let chatVC = ChatViewController(clanId: targetClanId, channel: minimal, context: self.context)
                    self.pushViewController(chatVC, animated: false)
                }
            }))
        } else {
            var minimal = Mezon_Api_ChannelDescription()
            minimal.channelID = channelIdInt
            minimal.clanID = targetClanId
            let chatVC = ChatViewController(clanId: targetClanId, channel: minimal, context: self.context)
            pushViewController(chatVC, animated: false)
            fetchClanChannelsInBackground(clanId: targetClanId)
        }
    }

    private func switchClanIfNeeded(homeVC: HomeViewController, toClanId: Int64) {
        guard toClanId != homeVC.clanListVC.selectedClanId,
              let clan = homeVC.clanListVC.clans.first(where: { $0.clanID == toClanId }) else { return }
        homeVC.clanListVC.select(clan: clan)
        homeVC.channelListVC.configure(clanId: toClanId, clanName: clan.clanName, logoURL: clan.logo, bannerURL: clan.banner)
    }

    private func fetchClanChannelsInBackground(clanId: Int64) {
        guard clanId != 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            do {
                let channels = try await self.context.account.network.listChannelDescs(clanId: clanId, token: token)
                self.context.account.postbox.setPreferenceData(
                    key: PreferencesKeys.channelList(clanId: clanId),
                    value: self.encodeChannelList(channels)
                )
                if let homeVC = self.homeController, homeVC.channelListVC.clanId == clanId {
                    homeVC.channelListVC.updateChannels(channels)
                }
            } catch {
                AppLogger.network.error("[FCM] fetchClanChannels background failed: \(error)")
            }
        }
    }

    private func encodeChannelList(_ channels: [Mezon_Api_ChannelDescription]) -> Data {
        var result = Data()
        var count = UInt32(channels.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for ch in channels {
            if let d = try? ch.serializedData() {
                var len = UInt32(d.count)
                result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                result.append(d)
            }
        }
        return result
    }

    deinit { navigationDisposable.dispose() }

    static func makeNavTheme(theme: AppTheme? = nil) -> NavigationControllerTheme {
        let actualTheme = theme ?? ThemeManager.shared.current
        let isDark = actualTheme == .dark || (actualTheme == .system && UITraitCollection.current.userInterfaceStyle == .dark)
        return NavigationControllerTheme(
            statusBar: isDark ? .white : .black,
            navigationBar: NavigationBarTheme(
                overallDarkAppearance: isDark,
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
