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
            onCreateGroupTapped: { [weak self] in
                self?.openNewGroupDMComposer()
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelDescriptionDidUpdate(_:)), name: .mezonChannelDescriptionDidUpdate, object: nil)
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

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        let notifyClanId = Self.int64UserInfo(notification.userInfo?["clanId"]) ?? 0
        guard notifyClanId == 0 else { return }
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]) else { return }

        if (notification.userInfo?["removed"] as? Bool) == true {
            let oldCount = directMessages.count
            directMessages.removeAll { $0.channelID == channelId }
            guard oldCount != directMessages.count else { return }
            directMessagesPipe.putNext(directMessages)
            setIsEmpty(directMessages.isEmpty)
            needsReloadPipe.putNext(())
            persistDmChannelListToPostbox()
            return
        }

        guard let updated = context.account.postbox.getDMChannelDescription(channelId: channelId),
              let index = directMessages.firstIndex(where: { $0.channelID == channelId })
        else {
            return
        }
        directMessages[index] = Self.mergeDmApiRowPreservingCachedPreview(updated, cached: directMessages[index])
        directMessagesPipe.putNext(directMessages)
        needsReloadPipe.putNext(())
        persistDmChannelListToPostbox()
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
        var incoming = lastSentHeader(from: m)
        if list[idx].hasLastSentMessage {
            let existing = list[idx].lastSentMessage
            if incoming.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !existing.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                incoming.content = existing.content
            }
            if incoming.id == 0 { incoming.id = existing.id }
            if incoming.timestampSeconds == 0 { incoming.timestampSeconds = existing.timestampSeconds }
            if incoming.senderID == 0 { incoming.senderID = existing.senderID }
        }
        list[idx].lastSentMessage = incoming
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

    private func openNewGroupDMComposer() {
        let vc = NewGroupDMViewController(context: context) { [weak self] channel in
            self?.upsertCreatedDirectMessageChannel(channel)
        }
        if let navigationController = navigationController as? NavigationController {
            navigationController.pushViewController(vc, animated: true)
        } else {
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    private func upsertCreatedDirectMessageChannel(_ channel: Mezon_Api_ChannelDescription) {
        var next = directMessages
        if let idx = next.firstIndex(where: { $0.channelID == channel.channelID }) {
            next[idx] = Self.mergeDmApiRowPreservingCachedPreview(channel, cached: next[idx])
        } else {
            next.insert(channel, at: 0)
        }
        let sorted = Self.sortDmChannels(next)
        setDirectMessages(sorted)
        setIsEmpty(sorted.isEmpty)
        persistDmChannelListToPostbox()
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

    private static func mergeDmApiRowsPreservingCachedPreview(
        _ rows: [Mezon_Api_ChannelDescription],
        cached cachedRows: [Mezon_Api_ChannelDescription]
    ) -> [Mezon_Api_ChannelDescription] {
        guard !rows.isEmpty, !cachedRows.isEmpty else { return rows }
        var cachedByChannelId: [Int64: Mezon_Api_ChannelDescription] = [:]
        for row in cachedRows {
            cachedByChannelId[row.channelID] = row
        }
        return rows.map { row in
            guard let cached = cachedByChannelId[row.channelID] else { return row }
            return mergeDmApiRowPreservingCachedPreview(row, cached: cached)
        }
    }

    private static func mergeDmApiRowPreservingCachedPreview(
        _ row: Mezon_Api_ChannelDescription,
        cached: Mezon_Api_ChannelDescription
    ) -> Mezon_Api_ChannelDescription {
        var merged = row

        if !merged.hasLastSentMessage, cached.hasLastSentMessage {
            merged.lastSentMessage = cached.lastSentMessage
        } else if merged.hasLastSentMessage, cached.hasLastSentMessage {
            let incoming = merged.lastSentMessage
            let existing = cached.lastSentMessage
            let incomingBlank = incoming.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let existingHasPreview = !existing.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let existingLooksNewer =
                existing.id > incoming.id
                || (existing.id == incoming.id && existing.timestampSeconds > incoming.timestampSeconds)

            var next = incoming
            if existingLooksNewer, existingHasPreview {
                next = existing
            } else if incomingBlank, existingHasPreview {
                next.content = existing.content
                if next.senderID == 0 { next.senderID = existing.senderID }
                if next.id == 0 { next.id = existing.id }
            }
            next.id = max(next.id, existing.id)
            next.timestampSeconds = max(next.timestampSeconds, existing.timestampSeconds)
            if next.senderID == 0 { next.senderID = existing.senderID }
            merged.lastSentMessage = next
        }

        if !merged.hasLastSeenMessage, cached.hasLastSeenMessage {
            merged.lastSeenMessage = cached.lastSeenMessage
        } else if merged.hasLastSeenMessage, cached.hasLastSeenMessage {
            var next = merged.lastSeenMessage
            let existing = cached.lastSeenMessage
            next.id = max(next.id, existing.id)
            next.timestampSeconds = max(next.timestampSeconds, existing.timestampSeconds)
            if next.senderID == 0 { next.senderID = existing.senderID }
            if next.content.isEmpty { next.content = existing.content }
            merged.lastSeenMessage = next
        }

        let rowSignalsReadState =
            row.countMessUnread != 0
            || row.hasLastSeenMessage
            || row.hasLastSentMessage
            || row.lastSeenMessage.timestampSeconds != 0
            || row.lastSentMessage.timestampSeconds != 0
        if merged.countMessUnread == 0, !rowSignalsReadState {
            merged.countMessUnread = cached.countMessUnread
        }

        return merged
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

    private func listDirectAndGroupMessageChannels(token: String) async throws -> [Mezon_Api_ChannelDescription] {
        var channels = try await context.account.network.listDirectMessageChannels(token: token)
        do {
            let groupChannels = try await context.account.network.listGroupMessageChannels(token: token)
            var existingIds = Set(channels.map(\.channelID))
            for channel in groupChannels where !existingIds.contains(channel.channelID) {
                channels.append(channel)
                existingIds.insert(channel.channelID)
            }
        } catch {
        }
        return channels
    }

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
                let cachedRows = self.directMessages
                var channels = try await self.listDirectAndGroupMessageChannels(token: token)
                channels = Self.mergeDmApiRowsPreservingCachedPreview(channels, cached: cachedRows)
                do {
                    let badgeResponse = try await self.context.account.network.listChannelBadgeCount(
                        clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(
                        into: &channels, badgeRows: badgeResponse.channeldesc)
                    channels = Self.mergeDmApiRowsPreservingCachedPreview(channels, cached: cachedRows)
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
                let cachedRows = self.directMessages
                var channels = try await self.listDirectAndGroupMessageChannels(token: token)
                channels = Self.mergeDmApiRowsPreservingCachedPreview(channels, cached: cachedRows)
                do {
                    let badgeResponse = try await self.context.account.network.listChannelBadgeCount(
                        clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(
                        into: &channels, badgeRows: badgeResponse.channeldesc)
                    channels = Self.mergeDmApiRowsPreservingCachedPreview(channels, cached: cachedRows)
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

private struct NewGroupDMFriendGroup {
    let character: String
    let friends: [Mezon_Api_Friend]
}

private let newGroupDMActionColor = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 1.0)

final class NewGroupDMViewController: ViewController, UITableViewDataSource, UITableViewDelegate {

    private static let maximumMembers = 20

    private let context: AccountContext
    private let onChannelCreated: (Mezon_Api_ChannelDescription) -> Void
    private let existingGroupChannel: Mezon_Api_ChannelDescription?
    private var excludedMemberIds: Set<Int64>
    private var existingMemberCountOverride: Int?

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let createButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private let contentView = UIView()
    private let searchContainerView = UIView()
    private let searchIconView = UIImageView()
    private let searchTextField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var allFriends: [Mezon_Api_Friend] = []
    private var filteredFriends: [Mezon_Api_Friend] = []
    private var groups: [NewGroupDMFriendGroup] = []
    private var selectedFriendIds: Set<Int64> = []
    private var searchText = ""
    private var isCreating = false
    private var refreshTask: Task<Void, Never>?
    private var existingMembersRefreshTask: Task<Void, Never>?
    private var friendsUpdatedDisposable: Disposable?

    init(context: AccountContext, onChannelCreated: @escaping (Mezon_Api_ChannelDescription) -> Void) {
        self.context = context
        self.onChannelCreated = onChannelCreated
        self.existingGroupChannel = nil
        self.excludedMemberIds = []
        self.existingMemberCountOverride = nil
        super.init(navigationBarPresentationData: nil)
    }

    init(
        context: AccountContext,
        existingGroupChannel: Mezon_Api_ChannelDescription,
        existingMemberIds: Set<Int64>? = nil,
        existingMemberCount: Int? = nil,
        onMembersAdded: @escaping (Mezon_Api_ChannelDescription) -> Void
    ) {
        self.context = context
        self.onChannelCreated = onMembersAdded
        self.existingGroupChannel = existingGroupChannel
        var excludedIds = Set(existingGroupChannel.userIds)
        if let existingMemberIds, !existingMemberIds.isEmpty {
            excludedIds.formUnion(existingMemberIds)
        }
        if let currentUserId = context.currentUser.flatMap({ Int64($0.id) }) {
            excludedIds.insert(currentUserId)
        }
        self.excludedMemberIds = excludedIds
        if let existingMemberCount {
            self.existingMemberCountOverride = existingMemberCount
        } else if let existingMemberIds, !existingMemberIds.isEmpty {
            self.existingMemberCountOverride = existingMemberIds.count
        } else if existingGroupChannel.memberCount > 0 {
            self.existingMemberCountOverride = Int(existingGroupChannel.memberCount)
        } else {
            self.existingMemberCountOverride = nil
        }
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTask?.cancel()
        existingMembersRefreshTask?.cancel()
        friendsUpdatedDisposable?.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        setupLayout()
        applyTheme()
        syncFriendsFromStore()
        refreshExistingGroupMembersIfNeeded()

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChanged), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChanged), name: LanguageManager.didChangeNotification, object: nil)

        friendsUpdatedDisposable = (context.engine.friendsData.friendsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.syncFriendsFromStore()
            })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFriends()
    }

    private func setupViews() {
        view.addSubview(headerView)
        view.addSubview(contentView)
        headerView.addSubview(backButton)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 2.sh
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.tag = 901
        headerView.addSubview(titleStack)

        headerView.addSubview(createButton)
        headerView.addSubview(activityIndicator)

        contentView.addSubview(searchContainerView)
        contentView.addSubview(tableView)

        searchContainerView.addSubview(searchIconView)
        searchContainerView.addSubview(searchTextField)

        backButton.setImage(
            UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf, weight: .semibold)),
            for: .normal
        )
        backButton.contentHorizontalAlignment = .left
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 1

        createButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .medium)
        createButton.contentHorizontalAlignment = .right
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)

        activityIndicator.hidesWhenStopped = true

        searchContainerView.layer.cornerRadius = 20.sh
        searchContainerView.clipsToBounds = true

        searchIconView.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.sf))
        searchIconView.contentMode = .scaleAspectFit

        searchTextField.font = .systemFont(ofSize: 14.sf)
        searchTextField.returnKeyType = .search
        searchTextField.autocorrectionType = .no
        searchTextField.autocapitalizationType = .none
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        tableView.register(NewGroupDMFriendCell.self, forCellReuseIdentifier: NewGroupDMFriendCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 60.sh
        tableView.estimatedRowHeight = 60.sh
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        emptyLabel.font = .systemFont(ofSize: 14.sf)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
    }

    private func setupLayout() {
        [headerView, contentView, backButton, createButton, activityIndicator, searchContainerView, searchIconView, searchTextField, tableView]
            .forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        let titleStack = headerView.viewWithTag(901)!
        let sideWidth: CGFloat = 78.sw
        let headerHeight: CGFloat = 58.sh

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 18.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: sideWidth),
            backButton.heightAnchor.constraint(equalToConstant: 44.sh),

            createButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -18.sw),
            createButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            createButton.widthAnchor.constraint(equalToConstant: sideWidth),
            createButton.heightAnchor.constraint(equalToConstant: 44.sh),

            activityIndicator.centerXAnchor.constraint(equalTo: createButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),

            titleStack.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4.sw),
            titleStack.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -4.sw),
            titleStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            contentView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            searchContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14.sh),
            searchContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18.sw),
            searchContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18.sw),
            searchContainerView.heightAnchor.constraint(equalToConstant: 40.sh),

            searchIconView.leadingAnchor.constraint(equalTo: searchContainerView.leadingAnchor, constant: 12.sw),
            searchIconView.centerYAnchor.constraint(equalTo: searchContainerView.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 18.swh),
            searchIconView.heightAnchor.constraint(equalToConstant: 18.swh),

            searchTextField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 8.sw),
            searchTextField.trailingAnchor.constraint(equalTo: searchContainerView.trailingAnchor, constant: -12.sw),
            searchTextField.topAnchor.constraint(equalTo: searchContainerView.topAnchor),
            searchTextField.bottomAnchor.constraint(equalTo: searchContainerView.bottomAnchor),

            tableView.topAnchor.constraint(equalTo: searchContainerView.bottomAnchor, constant: 10.sh),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func handleThemeChanged() {
        applyTheme()
    }

    @objc private func handleLanguageChanged() {
        applyLocalizedText()
    }

    private func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        headerView.backgroundColor = t.primary
        contentView.backgroundColor = t.primary
        searchContainerView.backgroundColor = t.secondary
        tableView.backgroundColor = t.primary

        backButton.tintColor = t.text
        titleLabel.textColor = t.text
        subtitleLabel.textColor = t.textDisabled
        createButton.setTitleColor(newGroupDMActionColor, for: .normal)
        createButton.setTitleColor(t.textDisabled, for: .disabled)
        activityIndicator.color = newGroupDMActionColor
        searchIconView.tintColor = t.text
        searchTextField.textColor = t.textStrong
        searchTextField.tintColor = t.textStrong
        emptyLabel.textColor = t.textDisabled

        applyLocalizedText()
        tableView.reloadData()
    }

    private func applyLocalizedText() {
        if existingGroupChannel != nil {
            titleLabel.text = L(L10n.ChannelDetail.addMembers)
            createButton.setTitle(L(L10n.ChannelPermission.bsAdd), for: .normal)
        } else {
            titleLabel.text = L(L10n.DirectMessage.newGroup)
            createButton.setTitle(L(L10n.DirectMessage.create), for: .normal)
        }
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.DirectMessage.searchFriends),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        updateMemberCount()
        updateEmptyState()
    }

    private func updateMemberCount() {
        let baseCount = baseMemberCount()
        subtitleLabel.text = L(
            L10n.DirectMessage.memberCount,
            baseCount + selectedFriendIds.count,
            Self.maximumMembers
        )
    }

    private func updateCreateButtonState() {
        createButton.isEnabled = !selectedFriendIds.isEmpty && !isCreating
        createButton.isHidden = isCreating
        if isCreating {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func updateEmptyState() {
        let hasQuery = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.text = hasQuery ? L(L10n.FriendList.noResults) : L(L10n.DirectMessage.noFriends)
        tableView.backgroundView = groups.isEmpty ? emptyLabel : nil
    }

    private func syncFriendsFromStore() {
        allFriends = context.engine.friendsData.allFriends()
            .filter { $0.state == EStateFriend.friend.rawValue && $0.hasUser && $0.user.id != 0 }
            .filter { !self.excludedMemberIds.contains($0.user.id) }
            .sorted { lhs, rhs in
                displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
            }
        applyFilter()
    }

    private func refreshFriends() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            await self.context.engine.friendsData.refreshFromNetwork(token: token)
        }
    }

    private func refreshExistingGroupMembersIfNeeded() {
        guard let existingGroup = existingGroupChannel else { return }
        existingMembersRefreshTask?.cancel()
        existingMembersRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            do {
                let response = try await self.context.account.network.listChannelUsersUC(
                    channelId: existingGroup.channelID,
                    limit: 500,
                    token: token
                )
                var ids = Set(response.userIds)
                guard !ids.isEmpty else { return }
                if let currentUserId = self.context.currentUser.flatMap({ Int64($0.id) }) {
                    ids.insert(currentUserId)
                }
                self.excludedMemberIds.formUnion(ids)
                self.existingMemberCountOverride = ids.count
                self.selectedFriendIds.subtract(self.excludedMemberIds)
                self.trimSelectionToMemberLimit()
                let labels = existingGroup.dmMemberLabelsForChannelList()
                self.context.account.postbox.write { tx in
                    tx.applyAllUsersAddChannelResponse(
                        response,
                        channelId: existingGroup.channelID,
                        dmMemberLabelByUserId: labels
                    )
                }
                self.syncFriendsFromStore()
                self.updateMemberCount()
                self.updateCreateButtonState()
            } catch {
            }
        }
    }

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredFriends = allFriends
        } else {
            let normalized = normalizeString(query)
            filteredFriends = allFriends.filter { friend in
                normalizeString(friend.user.username).contains(normalized)
                    || normalizeString(friend.user.displayName).contains(normalized)
            }
        }
        groups = groupByAlphabet(filteredFriends)
        updateEmptyState()
        tableView.reloadData()
    }

    private func groupByAlphabet(_ friends: [Mezon_Api_Friend]) -> [NewGroupDMFriendGroup] {
        var dict: [String: [Mezon_Api_Friend]] = [:]
        for friend in friends {
            let name = displayName(for: friend).trimmingCharacters(in: .whitespacesAndNewlines)
            let key: String
            if let first = name.first, first.isLetter {
                key = String(first).uppercased()
            } else {
                key = "#"
            }
            dict[key, default: []].append(friend)
        }
        return dict.map { NewGroupDMFriendGroup(character: $0.key, friends: $0.value) }
            .sorted { $0.character < $1.character }
    }

    private func normalizeString(_ str: String) -> String {
        str.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayName(for friend: Mezon_Api_Friend) -> String {
        let display = friend.user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let username = friend.user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? L(L10n.Common.detail) : username
    }

    private func baseMemberCount() -> Int {
        if let existing = existingGroupChannel {
            if let existingMemberCountOverride {
                return existingMemberCountOverride
            }
            if existing.memberCount > 0 {
                return Int(existing.memberCount)
            }
            var ids = Set(existing.userIds)
            if let currentUserId = context.currentUser.flatMap({ Int64($0.id) }) {
                ids.insert(currentUserId)
            }
            return max(ids.count, 1)
        }
        return 1
    }

    private func canSelectAdditionalFriend() -> Bool {
        baseMemberCount() + selectedFriendIds.count < Self.maximumMembers
    }

    private func trimSelectionToMemberLimit() {
        let remainingSlots = max(0, Self.maximumMembers - baseMemberCount())
        guard selectedFriendIds.count > remainingSlots else { return }
        selectedFriendIds = Set(selectedFriendIds.sorted().prefix(remainingSlots))
    }

    private func toggleSelection(for friend: Mezon_Api_Friend) {
        let userId = friend.user.id
        if selectedFriendIds.contains(userId) {
            selectedFriendIds.remove(userId)
        } else {
            guard canSelectAdditionalFriend() else {
                Toast.info(L(L10n.DirectMessage.memberLimitReached))
                return
            }
            selectedFriendIds.insert(userId)
        }
        updateMemberCount()
        updateCreateButtonState()
        tableView.reloadData()
    }

    @objc private func searchTextChanged() {
        searchText = searchTextField.text ?? ""
        applyFilter()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func createTapped() {
        guard !selectedFriendIds.isEmpty, !isCreating else { return }
        let selectedIds = Array(selectedFriendIds)
        guard baseMemberCount() + selectedIds.count <= Self.maximumMembers else {
            Toast.info(L(L10n.DirectMessage.memberLimitReached))
            return
        }
        isCreating = true
        updateCreateButtonState()

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isCreating = false
                self.updateCreateButtonState()
            }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.DirectMessage.createFailed))
                return
            }

            if let existingGroup = self.existingGroupChannel {
                do {
                    try await self.context.account.network.addChannelUsers(
                        channelId: existingGroup.channelID, userIds: selectedIds, token: token)
                    var updated = existingGroup
                    var merged = updated.userIds
                    for id in selectedIds where !merged.contains(id) { merged.append(id) }
                    updated.userIds = merged
                    updated.memberCount = Int32(min(Self.maximumMembers, self.baseMemberCount() + selectedIds.count))
                    if let members = try? await self.context.account.network.listChannelUsersUC(
                        channelId: existingGroup.channelID, limit: 500, token: token
                    ) {
                        let labels = updated.dmMemberLabelsForChannelList()
                        self.context.account.postbox.write { tx in
                            tx.applyAllUsersAddChannelResponse(
                                members,
                                channelId: existingGroup.channelID,
                                dmMemberLabelByUserId: labels
                            )
                        }
                    }
                    self.onChannelCreated(updated)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    Toast.error(error.localizedDescription.isEmpty ? L(L10n.DirectMessage.createFailed) : error.localizedDescription)
                }
                return
            }

            do {
                let channel: Mezon_Api_ChannelDescription
                if selectedIds.count == 1, let userId = selectedIds.first {
                    if let existing = await self.existingOneToOneDirectMessage(userId: userId, token: token) {
                        channel = existing
                    } else {
                        channel = try await self.context.account.network.createDirectMessage(userId: userId, token: token)
                    }
                } else {
                    channel = try await self.context.account.network.createGroupDirectMessage(userIds: selectedIds, token: token)
                }

                let decorated = self.decoratedChannel(channel, selectedIds: selectedIds)
                self.openCreatedChannel(decorated, showCreatedToast: selectedIds.count > 1)
            } catch {
                Toast.error(error.localizedDescription.isEmpty ? L(L10n.DirectMessage.createFailed) : error.localizedDescription)
            }
        }
    }

    private func existingOneToOneDirectMessage(userId: Int64, token: String) async -> Mezon_Api_ChannelDescription? {
        guard let channels = try? await context.account.network.listDirectMessageChannels(token: token) else {
            return nil
        }
        return channels.first { channel in
            channel.type == MezonConstants.ChannelType.dm.rawValue
                && channel.userIds.count == 1
                && channel.userIds.contains(userId)
        }
    }

    private func decoratedChannel(_ channel: Mezon_Api_ChannelDescription, selectedIds: [Int64]) -> Mezon_Api_ChannelDescription {
        var result = channel
        if result.clanID != 0 {
            result.clanID = 0
        }
        if result.type == 0 {
            result.type = selectedIds.count > 1
                ? MezonConstants.ChannelType.group.rawValue
                : MezonConstants.ChannelType.dm.rawValue
        }
        if result.userIds.isEmpty {
            result.userIds = selectedIds
        }

        let selectedFriends = selectedIds.compactMap { id in
            allFriends.first(where: { $0.user.id == id })?.user
        }
        var displayNames = selectedFriends.map { user in
            let display = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return display.isEmpty ? user.username : display
        }.filter { !$0.isEmpty }
        var usernames = selectedFriends.map(\.username).filter { !$0.isEmpty }
        var avatars = selectedFriends.map(\.avatarURL).filter { !$0.isEmpty }

        if let current = context.currentUser {
            let currentDisplay = current.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            displayNames.append(currentDisplay.isEmpty ? current.username : currentDisplay)
            if !current.username.isEmpty {
                usernames.append(current.username)
            }
            if let avatar = current.avatarURL?.absoluteString, !avatar.isEmpty {
                avatars.append(avatar)
            }
        }

        if result.displayNames.isEmpty {
            result.displayNames = displayNames
        }
        if result.usernames.isEmpty {
            result.usernames = usernames
        }
        if result.avatars.isEmpty {
            result.avatars = avatars
        }
        if result.type == MezonConstants.ChannelType.group.rawValue,
           result.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.channelLabel = displayNames.joined(separator: ", ")
        }
        return result
    }

    private func openCreatedChannel(_ channel: Mezon_Api_ChannelDescription, showCreatedToast: Bool) {
        onChannelCreated(channel)
        if showCreatedToast {
            Toast.success(L(L10n.DirectMessage.groupCreated))
        }

        let chatVC = ChatViewController(clanId: 0, channel: channel, context: context, parentName: nil)
        guard let navigationController else { return }
        if let navigationController = navigationController as? NavigationController {
            navigationController.replaceTopController(chatVC, animated: true)
        } else {
            var stack = navigationController.viewControllers
            if !stack.isEmpty {
                stack.removeLast()
            }
            stack.append(chatVC)
            navigationController.setViewControllers(stack, animated: true)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < groups.count else { return 0 }
        return groups[section].friends.count
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        26.sh
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < groups.count else { return nil }
        let view = UIView()
        view.backgroundColor = UIColor.theme.primary

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = groups[section].character
        label.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        label.textColor = UIColor.theme.textDisabled
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20.sw),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4.sh)
        ])
        return view
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: NewGroupDMFriendCell.reuseId, for: indexPath) as! NewGroupDMFriendCell
        let friend = groups[indexPath.section].friends[indexPath.row]
        let selected = selectedFriendIds.contains(friend.user.id)
        let disabled = !selected && !canSelectAdditionalFriend()
        cell.configure(friend: friend, selected: selected, disabled: disabled)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < groups.count, indexPath.row < groups[indexPath.section].friends.count else { return }
        toggleSelection(for: groups[indexPath.section].friends[indexPath.row])
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchTextField.resignFirstResponder()
    }
}

private final class NewGroupDMFriendCell: UITableViewCell {

    static let reuseId = "NewGroupDMFriendCell"

    private let avatarView = TextAvatarView(username: "", size: 40.swh, fontSize: 16.sf)
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let checkImageView = UIImageView()

    private var imageTask: URLSessionDataTask?
    private var representedAvatarURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        representedAvatarURL = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarView.showPlaceholder()
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.theme.secondary
        container.layer.cornerRadius = 10.sf
        container.clipsToBounds = true
        contentView.addSubview(container)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        checkImageView.translatesAutoresizingMaskIntoConstraints = false

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 20.swh
        avatarImageView.isHidden = true

        nameLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        nameLabel.numberOfLines = 1
        usernameLabel.font = .systemFont(ofSize: 12.sf)
        usernameLabel.numberOfLines = 1

        checkImageView.contentMode = .scaleAspectFit

        container.addSubview(avatarView)
        avatarView.addSubview(avatarImageView)
        container.addSubview(nameLabel)
        container.addSubview(usernameLabel)
        container.addSubview(checkImageView)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3.sh),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3.sh),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18.sw),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18.sw),

            avatarView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12.sw),
            avatarView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 40.swh),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            checkImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14.sw),
            checkImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            checkImageView.widthAnchor.constraint(equalToConstant: 22.swh),
            checkImageView.heightAnchor.constraint(equalToConstant: 22.swh),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.trailingAnchor.constraint(equalTo: checkImageView.leadingAnchor, constant: -12.sw),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 9.sh),

            usernameLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            usernameLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh)
        ])
    }

    func configure(friend: Mezon_Api_Friend, selected: Bool, disabled: Bool) {
        let t = UIColor.theme
        contentView.alpha = disabled ? 0.45 : 1.0
        contentView.subviews.first?.backgroundColor = t.secondary

        let user = friend.user
        let display = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = display.isEmpty ? username : display
        nameLabel.text = name.isEmpty ? L(L10n.Common.detail) : name
        nameLabel.textColor = t.textStrong
        usernameLabel.text = username.isEmpty ? "" : "@\(username)"
        usernameLabel.textColor = t.textDisabled
        avatarView.configure(username: username.isEmpty ? name : username, fontSize: 16.sf)

        let symbol = selected ? "checkmark.circle.fill" : "circle"
        checkImageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21.sf, weight: .semibold))
        checkImageView.tintColor = selected ? newGroupDMActionColor : t.textDisabled

        loadAvatarIfNeeded(user.avatarURL)
    }

    private func loadAvatarIfNeeded(_ rawURL: String) {
        imageTask?.cancel()
        imageTask = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true

        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            avatarView.showPlaceholder()
            return
        }

        let proxied = ImgproxyURL.avatarProxyURL(from: trimmed, width: 100, height: 100)
        representedAvatarURL = proxied
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            avatarImageView.image = cached
            avatarImageView.isHidden = false
            avatarView.showImageMode()
            return
        }

        avatarView.showSkeleton()
        imageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self, self.representedAvatarURL == proxied else { return }
            if let image {
                self.avatarImageView.image = image
                self.avatarImageView.isHidden = false
                self.avatarView.showImageMode()
            } else {
                self.avatarImageView.image = nil
                self.avatarImageView.isHidden = true
                self.avatarView.showPlaceholder()
            }
        }
    }
}
