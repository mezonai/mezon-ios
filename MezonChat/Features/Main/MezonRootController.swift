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
        let homeTab = UITabBarItem(
            title: L(L10n.Tab.clans),
            image: clansImg,
            selectedImage: clansSel
        )
        homeTab.mezonTabBarFaceAssetName = "TabBar/ClansIconFace"
        homeVC.tabBarItem = homeTab

        let (messagesImg, messagesSel) = Self.tabBarImage(name: "TabBar/MessagesIcon", systemFallback: "bubble.left.and.bubble.right", systemFallbackSelected: "bubble.left.and.bubble.right.fill")
        let directMessagesVC = DirectMessagesViewController(context: context)
        let messagesTab = UITabBarItem(
            title: L(L10n.Tab.messages),
            image: messagesImg,
            selectedImage: messagesSel
        )
        messagesTab.mezonTabBarFaceAssetName = "TabBar/MessagesIconFace"
        directMessagesVC.tabBarItem = messagesTab

        let (notifImg, notifSel) = Self.tabBarImage(
            name: "TabBar/NotificationIcon", systemFallback: "bell",
            systemFallbackSelected: "bell.fill")
        let notificationsVC = NotificationsViewController(context: context)
        let notifTab = UITabBarItem(
            title: L(L10n.Tab.notifications),
            image: notifImg,
            selectedImage: notifSel
        )
        notifTab.mezonTabBarFaceAssetName = "TabBar/NotificationIconFace"
        notificationsVC.tabBarItem = notifTab

        let (profileImg, profileSel) = Self.tabBarImage(name: "TabBar/ProfileIcon", systemFallback: "person.crop.circle", systemFallbackSelected: "person.crop.circle.fill")
        let profileVC = ProfileViewController(context: context)
        let profileTab = UITabBarItem(
            title: L(L10n.Tab.profile),
            image: profileImg,
            selectedImage: profileSel
        )
        profileTab.mezonTabBarFaceAssetName = "TabBar/ProfileIconFace"
        profileVC.tabBarItem = profileTab

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleSharedContent(_:)), name: .mezonDidReceiveSharedContent, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(handleIncomingPeerCall(_:)), name: .mezonIncomingPeerCall, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(evaluateMandatoryUsernamePendingIfNeeded), name: .mezonAccountCurrentUserDidChange, object: nil)

        bootstrapGlobalFriendState()
        processPendingNavigation()
        checkPendingSharedContentOnLaunch()

        DispatchQueue.main.async { [weak self] in
            self?.evaluateMandatoryUsernamePendingIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.evaluateMandatoryUsernamePendingIfNeeded()
        }
    }

    @objc private func evaluateMandatoryUsernamePendingIfNeeded() {
        guard context.isLoggedIn else { return }
        guard let session = context.session else { return }
        guard MandatoryUsernamePendingStore.isPending else { return }
        guard !mandatoryUsernameModalAlreadyVisible() else { return }

        let stub = OTPContext(reqId: "", target: "", type: .sms)
        let updateVC = UpdateUsernameViewController(pendingSession: session, context: context, otpContext: stub)
        pushViewController(updateVC, animated: true)
    }

    private func mandatoryUsernameModalAlreadyVisible() -> Bool {
        viewControllers.contains(where: { $0 is UpdateUsernameViewController })
    }

    private func bootstrapGlobalFriendState() {
        context.engine.friendsData.start(tokenProvider: { [weak self] in
            guard let self else { return nil }
            return await self.context.getToken()
        })
        directMessagesController?.prefetchInitialDataOnAppLaunch()
    }

    private func processPendingNavigation() {
        guard var pending = AppDelegate.pendingNavigation else { return }
        AppDelegate.pendingNavigation = nil
        if pending["navigationInstanceId"] == nil {
            pending["navigationInstanceId"] = UUID().uuidString
        }

        if let clanIdStr = pending["clanId"] as? String, let clanId = Int64(clanIdStr), clanId != 0 {
            let isDM = pending["isDM"] as? Bool ?? false
            if !isDM {
                context.currentClanId = clanId
            }
        }

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
            if let sid = pending["navigationInstanceId"] as? String,
               sid == AppDelegate.lastHandledNavigationInstanceId {
                return
            }
            NotificationCenter.default.post(name: .mezonNavigateToChannel, object: nil, userInfo: pending)
        }
    }


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
        AppDelegate.recordNavigationInstanceHandled(userInfo: notification.userInfo)
        let clanIdStr = notification.userInfo?["clanId"] as? String
        let isDM = notification.userInfo?["isDM"] as? Bool ?? false
        let title = notification.userInfo?["title"] as? String

        AppDelegate.pendingNavigation = nil

        if isDM {
            navigateToDM(channelIdStr: channelIdStr, title: title)
        } else {
            navigateToChannel(channelIdStr: channelIdStr, clanIdStr: clanIdStr, pushTitle: title)
        }
    }

    private func bringChatForChannelToFrontIfOnStack(channelIdInt: Int64, clanIdStr: String?) -> Bool {
        guard let existing = viewControllers.compactMap({ $0 as? ChatViewController }).first(where: { $0.channel.channelID == channelIdInt }) else {
            return false
        }
        rootTabController?.selectedIndex = 0
        popToViewController(existing, animated: true)
        existing.handleBroughtForwardFromNotificationDeepLink()
        guard let homeVC = homeController else { return true }
        let notificationClanId = clanIdStr.flatMap { Int64($0) }
        let resolvedClanId: Int64 = {
            if existing.clanId != 0 { return existing.clanId }
            if let n = notificationClanId, n != 0 { return n }
            return homeVC.channelListVC.clanId
        }()
        switchClanIfNeeded(homeVC: homeVC, toClanId: resolvedClanId)
        homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
        return true
    }

    private func popToTabBarController() {
        if let tabBarVC = viewControllers.first(where: { $0 is TabBarController }) {
            popToViewController(tabBarVC, animated: false)
        }
    }

    @objc private func handleIncomingPeerCall(_ notification: Notification) {
        guard let payload = IncomingPeerCallPayload(userInfo: notification.userInfo) else {
            return
        }
        let myId: Int64? = {
            if let s = context.currentUser?.id, let v = Int64(s) { return v }
            if let s = SessionStore.load()?.userId, let v = Int64(s) { return v }
            return nil
        }()
        guard let myId else {
            return
        }
        guard payload.receiverId == myId || payload.receiverId == 0 else {
            return
        }
        switch peerCallIncomingPresentHost() {
        case .noHost:
            stashIncomingPeerCallAndScheduleFlush(notification.userInfo ?? [:])
            return
        case .alreadyShowing:
            WebRTCCallManager.shared.clearPendingIncomingPeerCallPresentation()
            return
        case .ready(let top):
            let skipRing = (notification.userInfo?["mezonSkipIncomingRingingUI"] as? Bool) == true
            let display = IncomingPeerCallPayloadParser.callerDisplay(for: payload, skipDecompressOffer: skipRing)
            let vc = PeerCallViewController(
                context: context,
                incoming: payload,
                remoteDisplayName: display.name,
                remoteAvatarURL: display.avatar,
                skipIncomingRingingUI: skipRing
            )
            top.present(vc, animated: !skipRing)
            WebRTCCallManager.shared.clearPendingIncomingPeerCallPresentation()
        }
    }

    func flushPendingIncomingPeerCallIfNeeded() {
        guard WebRTCCallManager.shared.peekPendingIncomingPeerCallPresentation() != nil else { return }
        switch peerCallIncomingPresentHost() {
        case .noHost:
            return
        case .alreadyShowing, .ready:
            break
        }
        guard let info = WebRTCCallManager.shared.peekPendingIncomingPeerCallPresentation() else { return }
        handleIncomingPeerCall(Notification(name: .mezonIncomingPeerCall, object: nil, userInfo: info))
    }

    private enum PeerCallIncomingPresentHost {
        case noHost
        case alreadyShowing
        case ready(UIViewController)
    }

    private func stashIncomingPeerCallAndScheduleFlush(_ userInfo: [AnyHashable: Any]) {
        WebRTCCallManager.shared.stashIncomingPeerCallPresentation(userInfo)
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingIncomingPeerCallIfNeeded()
        }
        for delay in [0.05, 0.2, 0.6] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flushPendingIncomingPeerCallIfNeeded()
            }
        }
    }

    private func peerCallApplicationModalRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
            .filter { [.foregroundActive, .foregroundInactive].contains($0.activationState) }
        for scene in scenes {
            if let w = scene.windows.first(where: { $0.isKeyWindow }),
               let r = w.rootViewController,
               !(r is SplashViewController) {
                return r
            }
        }
        for scene in scenes {
            let ordered = scene.windows.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
            for w in ordered {
                guard !w.isHidden, w.alpha > 0 else { continue }
                guard w.windowLevel == .normal, let r = w.rootViewController else { continue }
                if r is SplashViewController { continue }
                return r
            }
        }
        if isViewLoaded, let w = view.window, let r = w.rootViewController, !(r is SplashViewController) {
            return r
        }
        return nil
    }

    private func peerCallIncomingPresentHost() -> PeerCallIncomingPresentHost {
        guard let root = peerCallApplicationModalRootViewController() else {
            return .noHost
        }
        var top = root
        while let presented = top.presentedViewController {
            if presented is PeerCallViewController { return .alreadyShowing }
            top = presented
        }
        return .ready(top)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        flushPendingIncomingPeerCallIfNeeded()
    }

    private func navigateToDM(channelIdStr: String, title: String?) {
        guard let channelIdInt = Int64(channelIdStr) else { return }
        rootTabController?.selectedIndex = 1

        if let existingChat = viewControllers.compactMap({ $0 as? ChatViewController }).first(where: {
            $0.clanId == 0 && $0.channel.channelID == channelIdInt
        }) {
            popToViewController(existingChat, animated: true)
            existingChat.handleBroughtForwardFromNotificationDeepLink()
            Task { @MainActor [weak self] in
                guard let self, let token = await self.context.getToken() else { return }
                _ = try? await self.context.account.network.listDirectMessageChannels(token: token)
                self.directMessagesController?.fetchDirectMessages()
            }
            return
        }

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
            minimal.type = MezonConstants.ChannelType.dm.rawValue
            return minimal
        }()

        pushViewController(
            ChatViewController(clanId: 0, channel: resolvedChannel, context: context, fallbackChannelLabel: title),
            animated: false
        )

        Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            do {
                _ = try await self.context.account.network.listDirectMessageChannels(token: token)
                self.directMessagesController?.fetchDirectMessages()
            } catch {
            }
        }
    }

    private func resolvedClanIdForOpenChat(
        notificationClanId: Int64?,
        channel: Mezon_Api_ChannelDescription,
        fallbackClanId: Int64
    ) -> Int64 {
        if channel.type == MezonConstants.ChannelType.dm.rawValue {
            return 0
        }
        if channel.type == MezonConstants.ChannelType.group.rawValue && channel.clanID == 0 {
            return 0
        }
        if channel.clanID != 0 {
            if let n = notificationClanId, n != 0, n != channel.clanID {
            }
            return channel.clanID
        }
        if let n = notificationClanId, n != 0 { return n }
        return fallbackClanId
    }

    private func navigateToChannel(channelIdStr: String, clanIdStr: String?, pushTitle: String? = nil) {
        guard let channelIdInt = Int64(channelIdStr) else { return }
        if bringChatForChannelToFrontIfOnStack(channelIdInt: channelIdInt, clanIdStr: clanIdStr) { return }

        rootTabController?.selectedIndex = 0

        popToTabBarController()

        guard let homeVC = homeController else { return }

        let notificationClanId: Int64? = clanIdStr.flatMap { Int64($0) }

        if let (cachedClanId, cachedChannel) = context.account.postbox.getChannelDescription(channelId: channelIdInt) {
            let resolvedClanId = resolvedClanIdForOpenChat(
                notificationClanId: notificationClanId,
                channel: cachedChannel,
                fallbackClanId: cachedClanId
            )
            switchClanIfNeeded(homeVC: homeVC, toClanId: resolvedClanId)
            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var parentName: String?
            if cachedChannel.parentID != 0 {
                parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == cachedChannel.parentID })?.channelLabel
            }
            let chatVC = ChatViewController(
                clanId: resolvedClanId, channel: cachedChannel, context: context, parentName: parentName,
                fallbackChannelLabel: pushTitle
            )
            pushViewController(chatVC, animated: false)
            fetchClanChannelsInBackground(clanId: resolvedClanId, selectChannelId: channelIdInt)
            return
        }

        if let ch = context.engine.clanData.getAllChannelsByUser()?.channeldesc.first(where: { $0.channelID == channelIdInt }) {
            let resolvedClanId = resolvedClanIdForOpenChat(
                notificationClanId: notificationClanId,
                channel: ch,
                fallbackClanId: ch.clanID != 0
                    ? ch.clanID
                    : (context.currentClanId != 0 ? context.currentClanId : homeVC.channelListVC.clanId)
            )
            switchClanIfNeeded(homeVC: homeVC, toClanId: resolvedClanId)
            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var parentName: String?
            if ch.parentID != 0 {
                parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == ch.parentID })?.channelLabel
            }
            let chatVC = ChatViewController(
                clanId: resolvedClanId, channel: ch, context: context, parentName: parentName,
                fallbackChannelLabel: pushTitle
            )
            pushViewController(chatVC, animated: false)
            fetchClanChannelsInBackground(clanId: resolvedClanId, selectChannelId: channelIdInt)
            return
        }

        if let ch = homeVC.channelListVC.allChannels.first(where: { $0.channelID == channelIdInt }) {
            let resolvedClanId = resolvedClanIdForOpenChat(
                notificationClanId: notificationClanId,
                channel: ch,
                fallbackClanId: homeVC.channelListVC.clanId
            )
            switchClanIfNeeded(homeVC: homeVC, toClanId: resolvedClanId)
            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var parentName: String?
            if ch.parentID != 0 {
                parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == ch.parentID })?.channelLabel
            }
            let chatVC = ChatViewController(
                clanId: resolvedClanId, channel: ch, context: context, parentName: parentName,
                fallbackChannelLabel: pushTitle
            )
            pushViewController(chatVC, animated: false)
            return
        }

        let listClanId = homeVC.channelListVC.clanId
        let fallbackWhenNoPushClan: Int64 = context.currentClanId != 0 ? context.currentClanId : listClanId
        let targetClanId: Int64 = notificationClanId ?? fallbackWhenNoPushClan

        if let notificationClanId, notificationClanId != homeVC.clanListVC.selectedClanId,
           let clan = homeVC.clanListVC.clans.first(where: { $0.clanID == notificationClanId }) {
            homeVC.clanListVC.select(clan: clan)
            homeVC.channelListVC.configure(clanId: notificationClanId, clanName: clan.clanName, logoURL: clan.logo, bannerURL: clan.banner)

            if bringChatForChannelToFrontIfOnStack(channelIdInt: channelIdInt, clanIdStr: clanIdStr) { return }

            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var minimal = Mezon_Api_ChannelDescription()
            minimal.channelID = channelIdInt
            minimal.clanID = notificationClanId
            let chatVC = ChatViewController(
                clanId: notificationClanId, channel: minimal, context: context, fallbackChannelLabel: pushTitle
            )
            pushViewController(chatVC, animated: false)

            let loaded = homeVC.channelListVC.channelsLoadedSignal
                |> filter { $0 }
                |> take(1)
                |> timeout(5.0, queue: Queue.mainQueue(), alternate: .single(true))
                |> deliverOnMainQueue

            navigationDisposable.set(loaded.start(next: { [weak self] _ in
                guard let self, let homeVC = self.homeController else { return }
                if self.bringChatForChannelToFrontIfOnStack(channelIdInt: channelIdInt, clanIdStr: clanIdStr) { return }
                guard let top = self.topViewController as? ChatViewController else { return }
                guard top.channel.channelID == channelIdInt else { return }
                if let ch = homeVC.channelListVC.allChannels.first(where: { $0.channelID == channelIdInt }) {
                    var parentName: String?
                    if ch.parentID != 0 {
                        parentName = homeVC.channelListVC.allChannels.first(where: { $0.channelID == ch.parentID })?.channelLabel
                    }
                    top.applyMergedChannelDescriptionFromChannelListLoadIfNeeded(ch, parentChannelName: parentName)
                } else {
                    top.applyMergedChannelDescriptionFromChannelListLoadIfNeeded(nil)
                }
            }))
            return
        } else {
            switchClanIfNeeded(homeVC: homeVC, toClanId: targetClanId)
            homeVC.channelListVC.selectWithoutNavigation(channelId: channelIdInt)
            var minimal = Mezon_Api_ChannelDescription()
            minimal.channelID = channelIdInt
            minimal.clanID = targetClanId
            let chatVC = ChatViewController(
                clanId: targetClanId, channel: minimal, context: self.context, fallbackChannelLabel: pushTitle
            )
            pushViewController(chatVC, animated: false)
            fetchClanChannelsInBackground(clanId: targetClanId, selectChannelId: channelIdInt)
        }
    }

    private func switchClanIfNeeded(homeVC: HomeViewController, toClanId: Int64) {
        guard toClanId != 0, toClanId != homeVC.clanListVC.selectedClanId else { return }
        if let clan = homeVC.clanListVC.clans.first(where: { $0.clanID == toClanId }) {
            homeVC.clanListVC.select(clan: clan)
            homeVC.channelListVC.configure(clanId: toClanId, clanName: clan.clanName, logoURL: clan.logo, bannerURL: clan.banner)
        } else {

            context.currentClanId = toClanId

            Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<50 {
                    if self.context.account.socket.isConnected { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if self.context.account.socket.isConnected {
                    self.context.account.socket.joinClanChat(clanId: toClanId)
                }
                guard let token = await self.context.getToken() else { return }
                self.context.engine.clanData.fetchAllClanData(clanId: toClanId, token: token)
            }
        }
    }

    private func fetchClanChannelsInBackground(clanId: Int64, selectChannelId: Int64? = nil) {
        guard clanId != 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            do {
                let channels = try await self.context.account.network.listChannelDescs(clanId: clanId, token: token)
                let hadCache = (self.context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId))?.isEmpty == false)
                if channels.isEmpty && hadCache {
                    if let homeVC = self.homeController, homeVC.channelListVC.clanId == clanId,
                       let selectChannelId {
                        homeVC.channelListVC.selectWithoutNavigation(channelId: selectChannelId)
                    }
                    return
                }
                self.context.account.postbox.setPreferenceDataSync(
                    key: PreferencesKeys.channelList(clanId: clanId),
                    value: self.encodeChannelList(channels)
                )
                if let homeVC = self.homeController, homeVC.channelListVC.clanId == clanId {
                    homeVC.channelListVC.updateChannels(channels)
                    if let selectChannelId {
                        homeVC.channelListVC.selectWithoutNavigation(channelId: selectChannelId)
                    }
                }
            } catch {
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


    @objc private func handleSharedContent(_ notification: Notification) {
        let type = notification.userInfo?["type"] as? String ?? "unknown"
        presentSharingUI(type: type)
    }

    private func checkPendingSharedContentOnLaunch() {
        guard SharingManager.shared.hasPendingSharedContent() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            guard SharingManager.shared.hasPendingSharedContent() else { return }
            self.presentSharingUI(type: "unknown")
        }
    }

    private func presentSharingUI(type: String) {
        guard let content = SharingManager.shared.loadSharedContent(type: type) else {
            return
        }

        if let presented = self.view.window?.rootViewController?.presentedViewController,
           presented is SharingViewController {
            presented.dismiss(animated: false)
        }

        let sharingVC = SharingViewController(context: context, sharedContent: content)
        if let windowRoot = self.view.window?.rootViewController {
            var topVC = windowRoot
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(sharingVC, animated: true)
        }
    }

    deinit {
        navigationDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

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
                badgeBackgroundColor: UIColor.mezonUnreadBadge,
                badgeStrokeColor: .clear,
                badgeTextColor: .white
            ),
            emptyAreaColor: UIColor.theme.primary
        )
    }
}
