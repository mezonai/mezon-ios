import UIKit

struct DirectMessagesState {
    var directMessages: [Mezon_Api_ChannelDescription]
    var isEmpty: Bool
    var isLoading: Bool
    var errorMessage: String?
    var incomingFriendRequestCount: Int
    var messageActivityRows: [DmMessageActivityItem]

    static let empty = DirectMessagesState(
        directMessages: [], isEmpty: true, isLoading: false, errorMessage: nil,
        incomingFriendRequestCount: 0, messageActivityRows: [])
}

final class DirectMessagesViewController: ViewController {

    private let context: AccountContext

    private let directMessagesPipe = ValuePipe<[Mezon_Api_ChannelDescription]>()
    private let isEmptyPipe = ValuePipe<Bool>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var directMessages: [Mezon_Api_ChannelDescription] = []
    private(set) var isEmpty: Bool = true
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var incomingFriendRequestCount: Int = 0
    private var userActivities: [Mezon_Api_UserActivity] = []

    private var directMessagesNode: DirectMessagesContainerNode { displayNode as! DirectMessagesContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = DirectMessagesInteraction(
            onSelectDirectMessage: { [weak self] ch in
                guard let self else { return }
                let vc = ChatViewController(clanId: 0, channel: ch, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onAddFriendTapped: { [weak self] in
                guard let self else { return }
                let vc = FriendRequestViewController(context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onSearchTapped: { [weak self] in
                guard let self else { return }
                let vc = SearchViewController(clanId: self.resolvedClanIdForSearch(), context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onBackTapped: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onRefresh: { [weak self] in
                self?.refreshDirectMessages()
            },
            onSelectMessageActivity: { [weak self] item in
                self?.openDirectMessageFromActivity(item)
            }
        )
        displayNode = DirectMessagesContainerNode(signal: stateSignal(), interaction: interaction, context: context)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let layout = lastLayout {
            directMessagesNode.updateLayout(
                size: layout.size,
                safeTop: resolvedSafeTop(for: layout),
                bottomInset: layout.intrinsicInsets.bottom,
                transition: .immediate
            )
        }
        if isNodeLoaded {
            directMessagesNode.resetMessageActivityStripScroll(animated: false)
        }
        fetchDirectMessages()
        syncIncomingFriendRequestCount()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.secondary
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMarkedAsRead(_:)), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewMessageReceived(_:)), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSocketReconnectForDMBadges(_:)), name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDirectMessagesThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNetworkStatusChanged(_:)), name: NetworkMonitor.statusDidChangeNotification, object: nil)
        
        friendsUpdatedDisposable = (context.engine.friendsData.friendsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.syncIncomingFriendRequestCount()
                self?.needsReloadPipe.putNext(())
            })
        syncIncomingFriendRequestCount()
    }
    
    private var friendsUpdatedDisposable: Disposable?

    @objc private func handleNetworkStatusChanged(_ notification: Notification) {
        let connected = (notification.userInfo?["isConnected"] as? Bool) ?? NetworkMonitor.shared.isConnected
        guard connected else { return }
        fetchDirectMessages()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        friendsUpdatedDisposable?.dispose()
    }

    @objc private func handleDirectMessagesThemeChange() {
        guard isNodeLoaded else { return }
        view.backgroundColor = UIColor.theme.secondary
        directMessagesNode.applyTheme()
    }

    @objc private func handleSocketReconnectForDMBadges(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool, connected else { return }
        lastFetchDirectMessagesAt = nil
        fetchDirectMessages()
        Task { @MainActor in
            await self.applyDmListChannelBadgeCount()
        }
    }

    @MainActor
    private func applyDmListChannelBadgeCount() async {
        guard !directMessages.isEmpty else { return }
        guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
        do {
            let badgeResponse = try await context.account.network.listChannelBadgeCount(clanId: 0, token: token)
            let rows = badgeResponse.channeldesc
            guard !rows.isEmpty else { return }
            var updated = directMessages
            ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &updated, badgeRows: rows)
            updated.sort { ch1, ch2 in
                let t1 = ch1.hasLastSentMessage ? ch1.lastSentMessage.timestampSeconds : 0
                let t2 = ch2.hasLastSentMessage ? ch2.lastSentMessage.timestampSeconds : 0
                return t1 > t2
            }
            setDirectMessages(updated)
            persistDmChannelListToPostbox()
        } catch {
        }
    }

    private static func int64UserInfo(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }


    @objc private func handleNewMessageReceived(_ notification: Notification) {
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]),
              let clanId = Self.int64UserInfo(notification.userInfo?["clanId"]) else { return }
        guard clanId == 0 else { return }

        let wsMessage: Mezon_Api_ChannelMessage? = {
            guard let data = notification.userInfo?["serializedChannelMessage"] as? Data else { return nil }
            return try? Mezon_Api_ChannelMessage(serializedBytes: data)
        }()

        var needsReload = false

        if let m = wsMessage {
            let isMutation = m.code == 1 || m.code == 2
            let isDmOrGroup =
                m.mode == MezonConstants.ChannelStreamMode.dm.rawValue
                || m.mode == MezonConstants.ChannelStreamMode.group.rawValue
            if isDmOrGroup, !isMutation, Self.applyUpdateDmLastSentMessage(m, to: &directMessages) {
                needsReload = true
            }
        }

        let senderId: String? = {
            if let m = wsMessage { return String(m.senderID) }
            let v = notification.userInfo?["senderId"]
            if let s = v as? String { return s }
            if let n = v as? Int64 { return String(n) }
            if let n = v as? Int { return String(n) }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }()
        let ts: UInt32 = {
            if let m = wsMessage, m.createTimeSeconds > 0 { return m.createTimeSeconds }
            if let t = notification.userInfo?["timestampSeconds"] as? UInt32 { return t }
            if let t = notification.userInfo?["timestampSeconds"] as? Int { return UInt32(t) }
            return UInt32(Date().timeIntervalSince1970)
        }()

        if let senderId, senderId != context.currentUser?.id,
           (notification.userInfo?["incrementDmBadge"] as? Bool) == true {
            for i in 0..<directMessages.count where directMessages[i].channelID == channelId {
                directMessages[i].countMessUnread += 1
                if wsMessage == nil {
                    var header = directMessages[i].lastSentMessage
                    header.timestampSeconds = ts
                    directMessages[i].lastSentMessage = header
                }
                needsReload = true
            }
        }

        guard needsReload else { return }
        directMessages.sort { ch1, ch2 in
            let t1 = ch1.hasLastSentMessage ? ch1.lastSentMessage.timestampSeconds : 0
            let t2 = ch2.hasLastSentMessage ? ch2.lastSentMessage.timestampSeconds : 0
            return t1 > t2
        }
        directMessagesPipe.putNext(directMessages)
        needsReloadPipe.putNext(())
        persistDmChannelListToPostbox()
    }


    private static func lastSentHeader(from m: Mezon_Api_ChannelMessage) -> Mezon_Api_ChannelMessageHeader {
        var h = Mezon_Api_ChannelMessageHeader()
        h.id = m.messageID
        h.timestampSeconds = m.createTimeSeconds
        h.senderID = m.senderID
        h.content = m.content
        return h
    }

    @discardableResult
    private static func applyUpdateDmLastSentMessage(_ m: Mezon_Api_ChannelMessage, to list: inout [Mezon_Api_ChannelDescription]) -> Bool {
        let cid = m.channelID
        guard let idx = list.firstIndex(where: { $0.channelID == cid }) else { return false }
        list[idx].lastSentMessage = lastSentHeader(from: m)
        return true
    }

    private func persistDmChannelListToPostbox() {
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.dmChannelList,
            value: encodeDMChannelList(directMessages)
        )
    }

    private static func int32UserInfo(_ value: Any?) -> Int32? {
        if let v = value as? Int32 { return v }
        if let v = value as? Int { return Int32(v) }
        if let v = value as? NSNumber { return v.int32Value }
        if let v = value as? String { return Int32(v) }
        return nil
    }

    @objc private func handleChannelMarkedAsRead(_ notification: Notification) {
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]) else { return }

        let modeOpt = Self.int32UserInfo(notification.userInfo?["mode"])
        let clanId = Self.int64UserInfo(notification.userInfo?["clanId"]) ?? 0
        let modeMatchesDmOrGroup = modeOpt.map {
            $0 == MezonConstants.ChannelStreamMode.dm.rawValue
                || $0 == MezonConstants.ChannelStreamMode.group.rawValue
        } ?? false
        let inDmList = directMessages.contains(where: { $0.channelID == channelId })
        let clanless = clanId == 0
        guard inDmList || (clanless && (modeMatchesDmOrGroup || modeOpt == nil)) else { return }

        let now = notification.userInfo?["timestampSeconds"] as? UInt32 ?? UInt32(Date().timeIntervalSince1970)
        var updated = false
        for i in 0..<directMessages.count {
            if directMessages[i].channelID == channelId {
                directMessages[i].countMessUnread = 0
                directMessages[i].lastSeenMessage.timestampSeconds = now
                updated = true
            }
        }
        if updated {
            directMessagesPipe.putNext(directMessages)
            needsReloadPipe.putNext(())
            persistDmChannelListToPostbox()
        }
    }

    private var lastLayout: ContainerViewLayout?

    private static let cachedSelectedClanUserDefaultsKey = "mezon_selectedClanId"

    private func resolvedClanIdForSearch() -> Int64 {
        let cur = context.currentClanId
        if cur != 0 { return cur }
        let ud = UserDefaults.standard.integer(forKey: Self.cachedSelectedClanUserDefaultsKey)
        if ud != 0 { return Int64(ud) }
        if let selData = context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedClanId), selData.count >= 8 {
            let id = selData.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
            if id != 0 { return id }
        }
        return 0
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout

        directMessagesNode.updateLayout(
            size: layout.size,
            safeTop: resolvedSafeTop(for: layout),
            bottomInset: layout.intrinsicInsets.bottom,
            transition: transition
        )
    }

    private func resolvedSafeTop(for layout: ContainerViewLayout) -> CGFloat {
        let viewSafeTop = isViewLoaded ? view.safeAreaInsets.top : 0
        return max(layout.safeInsets.top, layout.statusBarHeight ?? 0, viewSafeTop)
    }

    private func setDirectMessages(_ v: [Mezon_Api_ChannelDescription]) {
        directMessages = v
        directMessagesPipe.putNext(v)
        needsReloadPipe.putNext(())
    }

    private func setIsEmpty(_ v: Bool) { isEmpty = v; isEmptyPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v); needsReloadPipe.putNext(()) }

    private func setIncomingFriendRequestCount(_ v: Int) {
        let changed = incomingFriendRequestCount != v
        incomingFriendRequestCount = v
        if changed {
            needsReloadPipe.putNext(())
        }
    }

    private var prefetchFriendListTask: Task<Void, Never>?

    func prefetchInitialDataOnAppLaunch() {
        prefetchFriendListTask?.cancel()
        prefetchFriendListTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            self.fetchDirectMessages()
            await self.context.engine.friendsData.refreshFromNetwork(token: token)
        }
    }
    
    private func syncIncomingFriendRequestCount() {
        setIncomingFriendRequestCount(context.engine.friendsData.incomingFriendRequestCount())
    }

    private static func sortDmChannels(_ channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
        channels.sorted { ch1, ch2 in
            let t1 = ch1.hasLastSentMessage ? ch1.lastSentMessage.timestampSeconds : 0
            let t2 = ch2.hasLastSentMessage ? ch2.lastSentMessage.timestampSeconds : 0
            return t1 > t2
        }
    }

    private var fetchUserActivitiesTask: Task<Void, Never>?
    private var lastFetchUserActivitiesAt: Date?
    private let fetchUserActivitiesCooldown: TimeInterval = 2.0

    private func fetchUserActivities(token: String) async {
        if let existing = fetchUserActivitiesTask {
            _ = await existing.value
            return
        }
        if let last = lastFetchUserActivitiesAt, Date().timeIntervalSince(last) < fetchUserActivitiesCooldown {
            return
        }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.fetchUserActivitiesTask = nil
                self.lastFetchUserActivitiesAt = Date()
            }
            do {
                let res = try await self.context.account.network.listUserActivity(token: token)
                self.userActivities = res.activities
                self.needsReloadPipe.putNext(())
            } catch {
                self.userActivities = []
                self.needsReloadPipe.putNext(())
            }
        }
        fetchUserActivitiesTask = task
        _ = await task.value
    }

    private func openDirectMessageFromActivity(_ item: DmMessageActivityItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            let targetUserId = item.userId
            let dmChannels = try? await self.context.account.network.listDirectMessageChannels(token: token)
            if let existing = dmChannels?.first(where: { ch in
                ch.type == MezonConstants.ChannelType.dm.rawValue
                    && ch.userIds.count == 1
                    && ch.userIds.contains(targetUserId)
            }) {
                let chatVC = ChatViewController(clanId: 0, channel: existing, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
                return
            }
            do {
                let channel = try await self.context.account.network.createDirectMessage(
                    userId: targetUserId,
                    token: token
                )
                var next = self.directMessages
                if !next.contains(where: { $0.channelID == channel.channelID }) {
                    next.insert(channel, at: 0)
                    self.setDirectMessages(Self.sortDmChannels(next))
                    self.persistDmChannelListToPostbox()
                }
                let chatVC = ChatViewController(clanId: 0, channel: channel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private static func buildMessageActivityRows(
        activities: [Mezon_Api_UserActivity],
        friends: [Mezon_Api_Friend],
        directMessages: [Mezon_Api_ChannelDescription],
        myUserId: Int64,
        postboxAvatarURL: (Int64) -> String?
    ) -> [DmMessageActivityItem] {
        var profileById: [Int64: (displayName: String, username: String, avatar: String)] = [:]
        for f in friends {
            guard f.hasUser, f.user.id != 0 else { continue }
            guard f.state != EStateFriend.block.rawValue else { continue }
            let u = f.user
            let disp = u.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = disp.isEmpty ? u.username : disp
            profileById[u.id] = (displayName: name, username: u.username, avatar: u.avatarURL)
        }
        for ch in directMessages {
            guard ch.type == MezonConstants.ChannelType.dm.rawValue, ch.userIds.count == 1 else { continue }
            let uid = ch.userIds[0]
            let label = ch.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let dispName = ch.displayNames.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let un = ch.usernames.first ?? ""
            let av = ch.avatars.first ?? ""
            let avTrim = av.trimmingCharacters(in: .whitespacesAndNewlines)
            let display: String
            if !label.isEmpty {
                display = label
            } else if !dispName.isEmpty {
                display = dispName
            } else {
                display = un
            }
            if var existing = profileById[uid] {
                if existing.avatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !avTrim.isEmpty {
                    existing.avatar = av
                    profileById[uid] = existing
                }
                continue
            }
            profileById[uid] = (displayName: display, username: un, avatar: av)
        }
        for uid in profileById.keys {
            guard var p = profileById[uid] else { continue }
            if p.avatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let pb = postboxAvatarURL(uid)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pb.isEmpty
            {
                p.avatar = pb
                profileById[uid] = p
            }
        }
        var actByUser: [Int64: Mezon_Api_UserActivity] = [:]
        for a in activities {
            actByUser[a.userID] = a
        }
        var rows: [DmMessageActivityItem] = []
        for (uid, prof) in profileById where uid != myUserId {
            guard let act = actByUser[uid] else { continue }
            let desc = act.activityDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let actName = act.activityName.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle: String
            if !desc.isEmpty, !actName.isEmpty {
                subtitle = "\(actName) - \(desc)"
            } else if !actName.isEmpty {
                subtitle = actName
            } else {
                subtitle = desc
            }
            let trimmedSub = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSub.isEmpty else { continue }
            rows.append(DmMessageActivityItem(
                userId: uid,
                displayName: prof.displayName,
                username: prof.username,
                avatarURL: prof.avatar,
                activitySubtitle: trimmedSub
            ))
        }
        rows.sort {
            $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
        }
        return rows
    }

    private func applyDmListFromCache() {
        let cached = context.account.postbox.getCachedDMChannelList()
        guard !cached.isEmpty else { return }
        let sorted = Self.sortDmChannels(cached)
        setDirectMessages(sorted)
        setIsEmpty(sorted.isEmpty)
        setErrorMessage(nil)
    }

    private var fetchDirectMessagesTask: Task<Void, Never>?
    private var lastFetchDirectMessagesAt: Date?
    private let fetchDirectMessagesCooldown: TimeInterval = 2.0

    func fetchDirectMessages() {
        if fetchDirectMessagesTask != nil { return }
        if let last = lastFetchDirectMessagesAt, Date().timeIntervalSince(last) < fetchDirectMessagesCooldown {
            applyDmListFromCache()
            return
        }
        applyDmListFromCache()
        if !NetworkMonitor.shared.isConnected {
            setIsLoading(false)
            return
        }
        if directMessages.isEmpty {
            setIsLoading(true)
        }
        setErrorMessage(nil)

        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.setIsLoading(false)
                self.fetchDirectMessagesTask = nil
                self.lastFetchDirectMessagesAt = Date()
            }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            await self.fetchUserActivities(token: token)
            do {
                var channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                do {
                    let badgeResponse = try await self.context.account.network.listChannelBadgeCount(
                        clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(
                        into: &channels, badgeRows: badgeResponse.channeldesc)
                } catch {
                }
                let sorted = Self.sortDmChannels(channels)
                self.setDirectMessages(sorted)
                self.setIsEmpty(sorted.isEmpty)
                self.persistDmChannelListToPostbox()
                self.setErrorMessage(nil)
            } catch {
                self.applyDmListFromCache()
                if self.directMessages.isEmpty {
                    self.setErrorMessage(error.localizedDescription)
                }
            }
        }
        fetchDirectMessagesTask = task
    }

    private func refreshDirectMessages() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.directMessagesNode.endRefreshing() }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else {
                self.applyDmListFromCache()
                return
            }
            do {
                var channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                do {
                    let badgeResponse = try await self.context.account.network.listChannelBadgeCount(
                        clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(
                        into: &channels, badgeRows: badgeResponse.channeldesc)
                } catch {
                }
                let sorted = Self.sortDmChannels(channels)
                self.setDirectMessages(sorted)
                self.setIsEmpty(sorted.isEmpty)
                self.persistDmChannelListToPostbox()
            } catch {
                self.applyDmListFromCache()
            }
            await self.fetchUserActivities(token: token)
        }
    }

    private func encodeDMChannelList(_ channels: [Mezon_Api_ChannelDescription]) -> Data {
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

    var currentState: DirectMessagesState {
        let rows = Self.buildMessageActivityRows(
            activities: userActivities,
            friends: context.engine.friendsData.allFriends(),
            directMessages: directMessages,
            myUserId: Int64(context.currentUser?.id ?? "") ?? 0,
            postboxAvatarURL: { uid in
                context.account.postbox.read { $0.getProfile(userId: "\(uid)") }?.avatarUrl
            }
        )
        return DirectMessagesState(
            directMessages: directMessages,
            isEmpty: isEmpty,
            isLoading: isLoading,
            errorMessage: errorMessage,
            incomingFriendRequestCount: incomingFriendRequestCount,
            messageActivityRows: rows
        )
    }

    func stateSignal() -> Signal<DirectMessagesState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }
}
