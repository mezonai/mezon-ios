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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleThemeDidChange() {
        let newTheme = Self.makeNavTheme()
        self.updateTheme(newTheme)
        ThemeManager.shared.applyStatusBarStyle()
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleNavigateToFriendRequests(_:)), name: .mezonNavigateToFriendRequests, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleQRSelectClanRoot(_:)), name: .mezonQRSelectClan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleQRNavigateToDM(_:)), name: .mezonQRNavigateToDM, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSharedContent(_:)), name: .mezonDidReceiveSharedContent, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeepLink), name: .mezonHandleDeepLink, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(handleIncomingPeerCall(_:)), name: .mezonIncomingPeerCall, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(evaluateMandatoryUsernamePendingIfNeeded), name: .mezonAccountCurrentUserDidChange, object: nil)

        bootstrapGlobalFriendState()
        processPendingNavigation()
        processPendingFriendRequestNavigation()
        processPendingDeepLink()
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
            await self.awaitSessionReadyBounded()
            if let sid = pending["navigationInstanceId"] as? String,
               sid == AppDelegate.lastHandledNavigationInstanceId {
                return
            }
            NotificationCenter.default.post(name: .mezonNavigateToChannel, object: nil, userInfo: pending)
        }
    }

    private func processPendingFriendRequestNavigation() {
        guard var pending = AppDelegate.pendingFriendRequestNavigation else { return }
        AppDelegate.pendingFriendRequestNavigation = nil
        if pending["navigationInstanceId"] == nil {
            pending["navigationInstanceId"] = UUID().uuidString
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.awaitSessionReadyBounded()
            if let sid = pending["navigationInstanceId"] as? String,
               sid == AppDelegate.lastHandledFriendRequestNavigationInstanceId {
                return
            }
            NotificationCenter.default.post(name: .mezonNavigateToFriendRequests, object: nil, userInfo: pending)
        }
    }


    @objc private func handleQRSelectClanRoot(_ notification: Notification) {
        rootTabController?.selectedIndex = 0
        popToTabBarController()
    }

    @objc private func handleQRNavigateToDM(_ notification: Notification) {
        guard let channelIdStr = notification.userInfo?["channelId"] as? String else { return }
        navigateToDM(channelIdStr: channelIdStr)
    }

    @objc private func handleNavigateToChannel(_ notification: Notification) {
        guard let channelIdStr = notification.userInfo?["channelId"] as? String else { return }
        AppDelegate.recordNavigationInstanceHandled(userInfo: notification.userInfo)
        let clanIdStr = notification.userInfo?["clanId"] as? String
        let isDM = notification.userInfo?["isDM"] as? Bool ?? false

        AppDelegate.pendingNavigation = nil

        handoffActiveVoiceRoomToPiPBeforeNavigation()

        if !isDM, let clanId = clanIdStr.flatMap({ Int64($0) }), clanId != 0 {
            context.currentClanId = clanId
        }

        context.account.socket.ensureFreshConnection()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.awaitSessionReadyBounded()
            if isDM {
                self.navigateToDM(channelIdStr: channelIdStr)
            } else {
                self.navigateToChannel(channelIdStr: channelIdStr, clanIdStr: clanIdStr)
            }
        }
    }

    @objc private func handleNavigateToFriendRequests(_ notification: Notification) {
        AppDelegate.recordFriendRequestNavigationInstanceHandled(userInfo: notification.userInfo)
        AppDelegate.pendingFriendRequestNavigation = nil

        handoffActiveVoiceRoomToPiPBeforeNavigation()
        context.account.socket.ensureFreshConnection()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.awaitSessionReadyBounded()
            self.navigateToFriendRequests()
        }
    }

    private func navigateToFriendRequests() {
        rootTabController?.selectedIndex = 1

        if let existing = viewControllers.compactMap({ $0 as? FriendRequestViewController }).first {
            popToViewController(existing, animated: true)
            refreshFriendRequestsForNotificationTap()
            return
        }

        popToTabBarController()
        let vc = FriendRequestViewController(context: context)
        pushViewController(vc, animated: false)
        refreshFriendRequestsForNotificationTap()
    }

    private func refreshFriendRequestsForNotificationTap() {
        Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            await self.context.engine.friendsData.refreshFromNetwork(token: token, force: true)
        }
    }

    private func handoffActiveVoiceRoomToPiPBeforeNavigation() {
        guard let voiceRoom = viewControllers.compactMap({ $0 as? VoiceChannelRoomViewController }).first else { return }
        voiceRoom.handoffToPiPForExternalNavigation()
    }

    private func awaitSessionReadyBounded(timeoutNanoseconds: UInt64 = 5_000_000_000) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                await self?.context.waitForSessionReady()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            _ = await group.next()
            group.cancelAll()
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
        if WebRTCCallManager.shared.discardStaleIncomingPeerPayloadIfNeeded(payload) {
            return
        }
        switch peerCallIncomingPresentHost() {
        case .noHost:
            stashIncomingPeerCallAndScheduleFlush(notification.userInfo ?? [:])
            return
        case .alreadyShowing:
            WebRTCCallManager.shared.clearPendingIncomingPeerCallPresentation()
            return
        case .ready:
            let skipRing = (notification.userInfo?["mezonSkipIncomingRingingUI"] as? Bool) == true
            let display = IncomingPeerCallPayloadParser.callerDisplay(for: payload, skipDecompressOffer: skipRing)
            let vc = PeerCallViewController(
                context: context,
                incoming: payload,
                remoteDisplayName: display.name,
                remoteAvatarURL: display.avatar,
                skipIncomingRingingUI: skipRing
            )
            pushPeerCallOnSelf(vc, animated: !skipRing)
            WebRTCCallManager.shared.clearPendingIncomingPeerCallPresentation()
        }
    }

    private func pushPeerCallOnSelf(_ vc: PeerCallViewController, animated: Bool) {
        let push: () -> Void = { [weak self] in
            self?.pushViewController(vc, animated: animated)
        }
        if presentedViewController != nil {
            dismiss(animated: false, completion: push)
        } else {
            push()
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
        if viewControllers.contains(where: { $0 is PeerCallViewController }) {
            return .alreadyShowing
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

    private func navigateToDM(channelIdStr: String) {
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

        let dmChatVC = ChatViewController(clanId: 0, channel: resolvedChannel, context: context)
        dmChatVC.prepareForNotificationNavigation()
        pushViewController(dmChatVC, animated: false)

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

    private func isKnownDirectMessageChannel(channelId: Int64) -> Bool {
        if let found = directMessagesController?.directMessages.first(where: { $0.channelID == channelId }) {
            return found.type == MezonConstants.ChannelType.dm.rawValue
                || found.type == MezonConstants.ChannelType.group.rawValue
                || found.clanID == 0
        }
        if let cached = context.account.postbox.getDMChannelDescription(channelId: channelId) {
            return cached.type == MezonConstants.ChannelType.dm.rawValue
                || cached.type == MezonConstants.ChannelType.group.rawValue
                || cached.clanID == 0
        }
        return false
    }

    private func navigateToChannel(channelIdStr: String, clanIdStr: String?) {
        guard let channelIdInt = Int64(channelIdStr) else { return }
        let notificationClanId: Int64? = clanIdStr.flatMap { Int64($0) }

        if notificationClanId == 0 || (notificationClanId == nil && isKnownDirectMessageChannel(channelId: channelIdInt)) {
            navigateToDM(channelIdStr: channelIdStr)
            return
        }

        if bringChatForChannelToFrontIfOnStack(channelIdInt: channelIdInt, clanIdStr: clanIdStr) { return }

        rootTabController?.selectedIndex = 0

        popToTabBarController()

        guard let homeVC = homeController else { return }

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
                clanId: resolvedClanId, channel: cachedChannel, context: context, parentName: parentName
            )
            chatVC.prepareForNotificationNavigation()
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
                clanId: resolvedClanId, channel: ch, context: context, parentName: parentName
            )
            chatVC.prepareForNotificationNavigation()
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
                clanId: resolvedClanId, channel: ch, context: context, parentName: parentName
            )
            chatVC.prepareForNotificationNavigation()
            pushViewController(chatVC, animated: false)
            return
        }

        if notificationClanId == nil {
            navigateToDM(channelIdStr: channelIdStr)
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
                clanId: notificationClanId, channel: minimal, context: context
            )
            chatVC.prepareForNotificationNavigation()
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
                clanId: targetClanId, channel: minimal, context: self.context
            )
            chatVC.prepareForNotificationNavigation()
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
            homeVC.channelListVC.configure(
                clanId: toClanId,
                clanName: "",
                logoURL: nil,
                bannerURL: nil,
                memberCount: 0,
                isCommunity: false
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: self.context, clanId: toClanId, force: true)
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
            guard let self else { return }
            let startEpoch = self.context.sessionEpoch
            guard let token = await self.context.getToken() else { return }
            let network = self.context.account.network
            do {
                async let channelsTask = network.listChannelDescs(clanId: clanId, token: token)
                async let categoriesTask = network.listCategoryDescs(clanId: clanId, token: token)
                async let favoritesTask = network.listFavoriteChannelIds(clanId: clanId, token: token)
                let categoryDescs = (try? await categoriesTask) ?? []
                let favoriteIds = Set((try? await favoritesTask) ?? [])
                let channels = try await channelsTask
                guard self.context.isStillCurrentSession(epoch: startEpoch) else { return }
                if channels.isEmpty {
                    if let homeVC = self.homeController, homeVC.channelListVC.clanId == clanId {
                        if let selectChannelId {
                            homeVC.channelListVC.selectWithoutNavigation(channelId: selectChannelId)
                        }
                        if homeVC.channelListVC.allChannels.isEmpty {
                            homeVC.channelListVC.fetchChannels()
                        }
                    }
                    return
                }
                self.context.account.postbox.setPreferenceDataSync(
                    key: PreferencesKeys.channelList(clanId: clanId),
                    value: self.encodeChannelList(channels)
                )
                if let homeVC = self.homeController, homeVC.channelListVC.clanId == clanId {
                    homeVC.channelListVC.ingestNotificationChannelData(
                        channels: channels,
                        categoryDescs: categoryDescs,
                        favoriteIds: favoriteIds,
                        selectChannelId: selectChannelId
                    )
                }
            } catch {
                if let homeVC = self.homeController, homeVC.channelListVC.clanId == clanId,
                   homeVC.channelListVC.allChannels.isEmpty {
                    homeVC.channelListVC.fetchChannels()
                }
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

        let sharingVC = SharingViewController(context: context, sharedContent: content)
        guard let windowRoot = view.window?.rootViewController else { return }

        dismissShareSheetStack(from: windowRoot) { [weak self] anchor in
            guard let self else { return }
            self.presentSharingViewController(sharingVC, on: anchor)
        }
    }

    private func isEphemeralShareSheet(_ viewController: UIViewController) -> Bool {
        if viewController is UIActivityViewController { return true }
        let className = NSStringFromClass(type(of: viewController))
        return className.contains("SLComposeViewController")
            || className.contains("SLRemoteComposeViewController")
    }

    private func resolvedSharePresentationAnchor(from root: UIViewController) -> UIViewController {
        var anchor = root
        while let presented = anchor.presentedViewController {
            guard presented.viewIfLoaded?.window != nil else { break }
            if isEphemeralShareSheet(presented) {
                return anchor
            }
            anchor = presented
        }
        return anchor
    }

    private func dismissShareSheetStack(
        from root: UIViewController,
        completion: @escaping (UIViewController) -> Void
    ) {
        var activityVC: UIActivityViewController?
        var anchor = root
        while let presented = anchor.presentedViewController {
            if let activity = presented as? UIActivityViewController {
                activityVC = activity
            }
            guard presented.viewIfLoaded?.window != nil else { break }
            anchor = presented
        }

        if let activityVC {
            activityVC.dismiss(animated: false) {
                completion(self.resolvedSharePresentationAnchor(from: root))
            }
            return
        }

        let ephemeral = anchor.presentedViewController
        if let ephemeral, isEphemeralShareSheet(ephemeral) {
            ephemeral.dismiss(animated: false) {
                completion(self.resolvedSharePresentationAnchor(from: root))
            }
            return
        }

        completion(resolvedSharePresentationAnchor(from: root))
    }

    private func presentSharingViewController(
        _ sharingVC: SharingViewController,
        on anchor: UIViewController
    ) {
        guard anchor.viewIfLoaded?.window != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak sharingVC] in
                guard let self, let sharingVC else { return }
                guard let windowRoot = self.view.window?.rootViewController else { return }
                let retryAnchor = self.resolvedSharePresentationAnchor(from: windowRoot)
                guard retryAnchor.viewIfLoaded?.window != nil else { return }
                self.presentSharingViewController(sharingVC, on: retryAnchor)
            }
            return
        }

        if let presented = anchor.presentedViewController {
            if presented is SharingViewController {
                presented.dismiss(animated: false) {
                    anchor.present(sharingVC, animated: true)
                }
                return
            }
            if isEphemeralShareSheet(presented) {
                presented.dismiss(animated: false) {
                    anchor.present(sharingVC, animated: true)
                }
                return
            }
        }

        anchor.present(sharingVC, animated: true)
    }

    // MARK: - Deep links

    private func processPendingDeepLink() {
        guard let route = DeepLinkRouter.consumePending() else { return }
        scheduleDeepLink(route)
    }

    @objc private func handleDeepLink() {
        guard let route = DeepLinkRouter.consumePending() else { return }
        scheduleDeepLink(route)
    }

    private func scheduleDeepLink(_ route: DeepLinkRoute) {
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
            self.performDeepLink(route)
        }
    }

    private func performDeepLink(_ route: DeepLinkRoute) {
        switch route {
        case let .channelApp(channelId, clanId, _, _):
            handleDeepLinkChannelApp(channelId: channelId, clanId: clanId)
        case let .invite(code):
            handleDeepLinkInvite(code: code)
        case let .chat(username, data):
            handleDeepLinkChat(username: username, data: data)
        case let .botInstall(appId):
            handleDeepLinkBotInstall(appId: appId)
        case let .login(loginId):
            handleDeepLinkLogin(loginId: loginId)
        }
    }

    private func handleDeepLinkBotInstall(appId: String) {
        guard let appIdInt = Int64(appId) else { return }
        let clans = homeController?.clanListVC.clans ?? []
        let vc = InstallClanViewController(context: context, appId: appIdInt, clans: clans)
        presentDeepLinkOverlay(vc)
    }

    private func handleDeepLinkLogin(loginId: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var token = self.context.session?.token ?? ""
            if token.isEmpty {
                token = await self.context.getToken() ?? ""
            }
            guard !token.isEmpty else {
                Toast.info("Please log in to Mezon first")
                return
            }
            let sessionToken = token
            let theme = self.context.sharedContext.currentPresentationTheme.attributes
            let node = QRLoginConfirmNode(theme: theme)
            let overlay = DeepLinkNodeOverlayController(node: node)
            node.onCancel = { [weak overlay] in
                overlay?.dismissOverlay()
            }
            node.onStartTalking = { [weak overlay] in
                overlay?.dismissOverlay()
            }
            node.onLogin = { [weak self, weak node, weak overlay] in
                guard let self else { return }
                Task { @MainActor in
                    do {
                        _ = try await self.context.engine.auth.confirmLogin(loginId: loginId, token: sessionToken)
                        node?.setSuccess(true)
                    } catch {
                        overlay?.dismissOverlay()
                        Toast.error(error.localizedDescription)
                    }
                }
            }
            self.presentDeepLinkOverlay(overlay)
        }
    }

    private func presentDeepLinkOverlay(_ controller: UIViewController) {
        let presenter: UIViewController
        if let root = view.window?.rootViewController {
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            presenter = top
        } else {
            presenter = self
        }
        guard presenter.presentedViewController == nil,
              !presenter.isBeingPresented,
              !presenter.isBeingDismissed else { return }
        if presenter is InstallClanViewController || presenter is DeepLinkNodeOverlayController { return }
        presenter.present(controller, animated: true)
    }

    private func handleDeepLinkChannelApp(channelId: String, clanId: String?) {
        guard let channelIdInt = Int64(channelId) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error("Session unavailable")
                return
            }
            let clanIdInt = clanId.flatMap { Int64($0) } ?? self.context.currentClanId
            guard clanIdInt != 0 else {
                Toast.error("App unavailable")
                return
            }
            do {
                let apps = try await self.context.account.network.listChannelApps(clanId: clanIdInt, token: token)
                guard let app = apps.first(where: { $0.channelID == channelIdInt }) else {
                    Toast.error("App unavailable")
                    return
                }
                let webAppData = try await self.context.account.network.generateChannelAppHash(appId: app.appID, token: token)
                guard !webAppData.isEmpty, let url = app.channelAppWebPageURL(webAppData: webAppData) else {
                    Toast.error("App unavailable")
                    return
                }
                let title = app.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                let vc = ChannelAppWebViewController(pageURL: url, appTitle: title.isEmpty ? "App" : title)
                self.presentOverlay(controller: vc, inGlobal: true)
                DispatchQueue.main.async { [weak self] in
                    self?.requestLayout(transition: .immediate)
                }
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleDeepLinkInvite(code: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var token = self.context.session?.token ?? ""
            if token.isEmpty {
                token = await self.context.getToken() ?? ""
            }
            do {
                let inviteInfo = try await self.context.engine.clanData.getInviteInfo(code: code, token: token)
                let theme = self.context.sharedContext.currentPresentationTheme.attributes
                let node = QRClanInviteNode(theme: theme, inviteInfo: inviteInfo)
                let overlay = DeepLinkNodeOverlayController(node: node)
                node.onCancel = { [weak overlay] in
                    overlay?.dismissOverlay()
                }
                node.onJoin = { [weak self, weak node, weak overlay] in
                    guard let self else { return }
                    node?.setJoining(true)
                    Task { @MainActor in
                        let clanId = await ClanInviteJoiner.join(context: self.context, code: code, clanId: inviteInfo.clan_id.flatMap(Int64.init))
                        guard let clanId else {
                            overlay?.dismissOverlay()
                            return
                        }
                        overlay?.dismissOverlay {
                            self.rootTabController?.selectedIndex = 0
                            self.popToTabBarController()
                            NotificationCenter.default.post(
                                name: .mezonQRSelectClan,
                                object: nil,
                                userInfo: ["clanId": "\(clanId)"]
                            )
                        }
                    }
                }
                self.presentDeepLinkOverlay(overlay)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleDeepLinkChat(username: String, data: String?) {
        guard let data, let profile = DeepLinkRouter.decodeProfileData(data) else {
            return
        }
        let theme = context.sharedContext.currentPresentationTheme.attributes
        let node = QRUserProfileNode(profile: profile, theme: theme)
        let overlay = DeepLinkNodeOverlayController(node: node)
        node.onClose = { [weak overlay] in
            overlay?.dismissOverlay()
        }
        node.onMessage = { [weak self, weak overlay] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    guard let userId = Int64(profile.id) else { return }
                    let token = await self.context.getToken() ?? ""
                    let channel = try await self.context.account.network.createDirectMessage(userId: userId, token: token)
                    overlay?.dismissOverlay {
                        NotificationCenter.default.post(
                            name: .mezonQRNavigateToDM,
                            object: nil,
                            userInfo: ["channelId": "\(channel.channelID)", "title": profile.name]
                        )
                    }
                } catch {
                    Toast.error(error.localizedDescription)
                }
            }
        }
        presentDeepLinkOverlay(overlay)
    }

    deinit {
        navigationDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    static func makeNavTheme(theme: AppTheme? = nil) -> NavigationControllerTheme {
        let actualTheme = theme ?? ThemeManager.shared.current
        let isDark = actualTheme.usesLightStatusBarContent
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
