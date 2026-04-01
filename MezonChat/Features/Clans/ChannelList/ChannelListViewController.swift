import UIKit
import SwiftProtobuf

struct ChannelListState: Equatable {
    var categories: [ChannelCategory]
    var allChannels: [Mezon_Api_ChannelDescription] = []
    var selectedChannelId: Int64?
    var isLoading: Bool
    var errorMessage: String?

    static let empty = ChannelListState(categories: [], allChannels: [], selectedChannelId: nil, isLoading: false, errorMessage: nil)

    static func == (lhs: ChannelListState, rhs: ChannelListState) -> Bool {
        guard lhs.isLoading == rhs.isLoading
            && lhs.selectedChannelId == rhs.selectedChannelId
            && lhs.errorMessage == rhs.errorMessage
            && lhs.categories.count == rhs.categories.count
            && lhs.allChannels.count == rhs.allChannels.count
            && zip(lhs.categories, rhs.categories).allSatisfy({ $0.id == $1.id && $0.isCollapsed == $1.isCollapsed && $0.channels.count == $1.channels.count })
        else { return false }
        return zip(lhs.allChannels, rhs.allChannels).allSatisfy {
            $0.channelID == $1.channelID
            && $0.countMessUnread == $1.countMessUnread
            && $0.lastSentMessage.timestampSeconds == $1.lastSentMessage.timestampSeconds
            && $0.lastSeenMessage.timestampSeconds == $1.lastSeenMessage.timestampSeconds
        }
    }
}

enum ChannelFetchError: Error {
    case noSession
    case network(Error)

    var localizedDescription: String {
        switch self {
        case .noSession: return "No active session. Please log in."
        case .network(let e): return e.localizedDescription
        }
    }
}

struct ChannelCategory {
    let id: Int64
    let name: String
    var isCollapsed: Bool = false
    var channels: [Mezon_Api_ChannelDescription]
}

enum ChannelListRow {
    case channel(Mezon_Api_ChannelDescription)
    case thread(Mezon_Api_ChannelDescription, isLast: Bool)

    var channelDesc: Mezon_Api_ChannelDescription {
        switch self {
        case .channel(let ch): return ch
        case .thread(let ch, _): return ch
        }
    }
}

enum ChannelType: Int32 {
    case text = 1
    case voice = 10
    case group = 3
    case thread = 4
    case streaming = 6
    case app = 8
    case forum = 11
    case unknown = 0

    var icon: String {
        switch self {
        case .text: return "Channel/channel"
        case .voice: return "Channel/channelVoice"
        case .thread: return "Channel/ChevronRight"
        case .streaming: return "Channel/channelStream"
        case .app: return "Channel/channelApp"
        case .forum: return "Channel/channel"
        default: return "Channel/channel"
        }
    }

    var isSystemImage: Bool { true }
}

private func buildChannelCategories(_ channels: [Mezon_Api_ChannelDescription], collapsedIds: Set<Int64>? = nil) -> [ChannelCategory] {
    let topLevel = channels.filter { $0.parentID == 0 }
    var order: [Int64] = []
    var lookup: [Int64: (String, [Mezon_Api_ChannelDescription])] = [:]
    for ch in topLevel {
        let catId = ch.categoryID
        if lookup[catId] == nil { order.append(catId); lookup[catId] = (ch.categoryName, []) }
        lookup[catId]!.1.append(ch)
    }
    return order.compactMap { id in
        guard let (name, list) = lookup[id] else { return nil }
        return ChannelCategory(id: id, name: name, isCollapsed: collapsedIds?.contains(id) ?? false, channels: list)
    }
}

func buildThreadLookup(_ allChannels: [Mezon_Api_ChannelDescription]) -> [Int64: [Mezon_Api_ChannelDescription]] {
    var lookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    for ch in allChannels where ch.parentID != 0 {
        lookup[ch.parentID, default: []].append(ch)
    }
    for key in lookup.keys {
        lookup[key]?.sort { $0.channelLabel < $1.channelLabel }
    }
    return lookup
}

func flattenCategoryToRows(_ category: ChannelCategory, allChannels: [Mezon_Api_ChannelDescription]) -> [ChannelListRow] {
    let lookup = buildThreadLookup(allChannels)
    return flattenCategoryToRows(category, threadLookup: lookup)
}

func flattenCategoryToRows(_ category: ChannelCategory, threadLookup: [Int64: [Mezon_Api_ChannelDescription]]) -> [ChannelListRow] {
    var rows: [ChannelListRow] = []
    for ch in category.channels {
        rows.append(.channel(ch))
        if let threads = threadLookup[ch.channelID] {
            for (i, thread) in threads.enumerated() {
                rows.append(.thread(thread, isLast: i == 0))
            }
        }
    }
    return rows
}

private enum FetchResult {
    case success([Mezon_Api_ChannelDescription])
    case failure(String)
}

final class ChannelListViewController: ViewController {

    private let context: AccountContext
    private let fetchDisposable = MetaDisposable()
    private let dataDisposable = MetaDisposable()
    private var processedBadgeKeys = Set<String>()

    deinit {
        fetchDisposable.dispose()
        dataDisposable.dispose()
        NotificationCenter.default.removeObserver(self, name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("MezonJoinedClanChatForBadges"), object: nil)
    }

    private let categoriesPipe = ValuePipe<[ChannelCategory]>()
    private let selectedChannelIdPipe = ValuePipe<Int64?>()
    private let selectedChannelPipe = ValuePipe<Mezon_Api_ChannelDescription?>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let needsReloadPipe = ValuePipe<Void>()

    private let channelsLoadedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var channelsLoadedSignal: Signal<Bool, NoError> { channelsLoadedPromise.get() }

    var selectedChannelSignal: Signal<Mezon_Api_ChannelDescription?, NoError> { selectedChannelPipe.signal() }

    private let searchTappedPipe = ValuePipe<Void>()
    var searchTappedSignal: Signal<Void, NoError> { searchTappedPipe.signal() }

    private(set) var categories: [ChannelCategory] = []
    private(set) var selectedChannelId: Int64?
    private(set) var selectedChannel: Mezon_Api_ChannelDescription?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var clanId: Int64 = 0
    private(set) var clanName: String = ""
    private(set) var clanLogoURL: String = ""

    private var channelListNode: ChannelListContainerNode { displayNode as! ChannelListContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = ChannelListInteraction(
            onSelectChannel: { [weak self] ch in self?.select(channel: ch) },
            onLongPressChannel: { [weak self] ch in self?.presentChannelActionSheet(ch) },
            onToggleCollapse: { [weak self] id in self?.toggleCollapse(categoryId: id) },
            onRefresh: { [weak self] in self?.fetchChannels() },
            onPresentSettings: { [weak self] in self?.presentSettings() },
            onSearchTapped: { [weak self] in self?.searchTappedPipe.putNext(()) },
            onQRTapped: { [weak self] in
                guard let self else { return }
                let vc = QRScannerViewController(context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        displayNode = ChannelListContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        channelListNode.applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMarkedAsRead(_:)), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewMessageReceived(_:)), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMentionReceived(_:)), name: Notification.Name("MezonMentionReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSocketStatusForChannelBadges(_:)), name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleJoinedClanForChannelBadges(_:)), name: Notification.Name("MezonJoinedClanChatForBadges"), object: nil)
    }

    @objc private func handleJoinedClanForChannelBadges(_ notification: Notification) {
        guard let joinedClan = notification.userInfo?["clanId"] as? Int64 else { return }
        guard joinedClan == clanId, joinedClan != 0 else { return }
        Task { @MainActor in
            await self.applyChannelBadgeCountsFromSocket(clanId: joinedClan)
        }
    }

    @objc private func handleSocketStatusForChannelBadges(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool, connected else { return }
        guard clanId != 0 else { return }
        Task { @MainActor in
            await self.applyChannelBadgeCountsFromSocket(clanId: self.clanId)
        }
    }

    /// RN `listChannelBadgeCount` — socket-only authoritative unread per channel.
    @MainActor
    private func applyChannelBadgeCountsFromSocket(clanId: Int64) async {
        guard clanId != 0 else { return }
        guard context.account.socket.isConnected else { return }
        do {
            let rows = try await context.account.socket.fetchListChannelBadgeCount(clanId: clanId)
            guard !rows.isEmpty else { return }
            var updated = allChannels
            ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &updated, badgeRows: rows)
            allChannels = updated
            let storedCollapsed = loadCollapsedCategoryIds()
            let cats = buildChannelCategories(updated, collapsedIds: storedCollapsed)
            categories = cats
            categoriesPipe.putNext(cats)
            context.account.postbox.setPreferenceData(
                key: PreferencesKeys.channelList(clanId: clanId),
                value: encodeChannelList(updated)
            )
            needsReloadPipe.putNext(())
        } catch {
            AppLogger.network.debug("[ChannelList] ListChannelBadgeCount: \(error)")
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        channelListNode.updateLayout(layout: layout, transition: transition)
    }

    func configure(clanId: Int64, clanName: String, logoURL: String? = nil, bannerURL: String? = nil, memberCount: Int = 0, onlineCount: Int = 0, isCommunity: Bool = false) {
        self.clanLogoURL = logoURL ?? ""
        guard clanId != self.clanId else {
            channelListNode.configure(clanName: clanName, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, onlineCount: onlineCount, isCommunity: isCommunity)
            return
        }
        channelListNode.markClanSwitching()
        channelListNode.configure(clanName: clanName, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, onlineCount: onlineCount, isCommunity: isCommunity)
        restoreCachedChannelApps(clanId: clanId)
        load(clanId: clanId, clanName: clanName)
    }

    func updateMemberCount(_ count: Int) {
        channelListNode.updateMemberCount(count)
    }

    private func presentSettings() {
        let vc = ClanSettingsViewController(
            context: context,
            clanId: clanId,
            clanName: clanName,
            avatarURL: clanLogoURL
        )
        self.navigationController?.pushViewController(vc, animated: true)
    }

    private func presentChannelActionSheet(_ channel: Mezon_Api_ChannelDescription) {
        let actionSheet = ChannelActionSheetController(
            channelName: channel.channelLabel,
            clanName: clanName,
            clanAvatarURL: clanLogoURL,
            onAction: { [weak self] action in
                guard let self else { return }
                switch action {
                case .editChannel:
                    self.presentChannelSettings(channel)
                case .deleteChannel:
                    print("Delete channel: \(channel.channelID)")
                default:
                    print("Handle action: \(action)")
                }
            }
        )
        if let window = self.view.window as? WindowHost {
            window.present(actionSheet, on: .root, blockInteraction: false, completion: {})
            actionSheet.animateIn()
        }
    }

    private func presentChannelSettings(_ channel: Mezon_Api_ChannelDescription) {
        let vc = ChannelSettingsViewController(
            context: context,
            clanId: channel.clanID,
            channelId: channel.channelID,
            categoryId: channel.categoryID,
            channelName: channel.channelLabel,
            channelTopic: channel.topic
        )
        self.navigationController?.pushViewController(vc, animated: true)
    }

    func refresh() { fetchChannels() }

    func fetchChannels() {
        guard clanId != 0 else { return }
        isLoading = true
        errorMessage = nil
        // Single emission instead of separate setIsLoading + setErrorMessage
        needsReloadPipe.putNext(())
        fetchChannelsWithoutLoadingSignal()
    }

    @objc private func handleThemeChange() { channelListNode.applyTheme() }

    private static func int64UserInfo(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    @objc private func handleNewMessageReceived(_ notification: Notification) {
        let rawChannelId = notification.userInfo?["channelId"]
        let rawClanId = notification.userInfo?["clanId"]

        guard let channelId = Self.int64UserInfo(rawChannelId),
              let clanId = Self.int64UserInfo(rawClanId) else { return }

        let senderId: String? = {
            let v = notification.userInfo?["senderId"]
            if let s = v as? String { return s }
            if let n = v as? Int64 { return String(n) }
            if let n = v as? Int { return String(n) }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }()
        guard let senderId else { return }

        let ts: UInt32
        if let t = notification.userInfo?["timestampSeconds"] as? UInt32 { ts = t }
        else if let t = notification.userInfo?["timestampSeconds"] as? Int { ts = UInt32(t) }
        else { ts = UInt32(Date().timeIntervalSince1970) }

        guard clanId == self.clanId, clanId != 0 else { return }
        guard senderId != context.currentUser?.id else { return }
        if ActiveChannelTracker.currentChannelId == channelId { return }

        let topicId: Int64 = {
            if let t = notification.userInfo?["topicId"] as? Int64 { return t }
            if let t = notification.userInfo?["topicId"] as? Int { return Int64(t) }
            return 0
        }()

        let mode: Int32 = {
            if let m = notification.userInfo?["mode"] as? Int32 { return m }
            if let m = notification.userInfo?["mode"] as? Int { return Int32(m) }
            return 0
        }()
        let isThreadMode = mode == MezonConstants.ChannelStreamMode.thread.rawValue

        var updated = false
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
                let oldTs = allChannels[i].lastSentMessage.timestampSeconds
                let lastSeenTs = allChannels[i].lastSeenMessage.timestampSeconds
                var header = allChannels[i].lastSentMessage
                header.timestampSeconds = ts
                allChannels[i].lastSentMessage = header
                updated = true
            }
        }

        if topicId != 0 {
            for i in 0..<allChannels.count {
                if allChannels[i].channelID == topicId {
                    var header = allChannels[i].lastSentMessage
                    header.timestampSeconds = ts
                    allChannels[i].lastSentMessage = header
                    updated = true
                }
            }
        }

        if let serializedData = notification.userInfo?["serializedChannelMessage"] as? Data,
           let apiMessage = try? Mezon_Api_ChannelMessage(serializedBytes: serializedData) {
            let currentUserId = context.currentUser?.id
            let roleIds = ClanListViewController.getCurrentUserRoleIds(context: context)
            let isMentioned = ClanListViewController.checkMessageMentionsUser(
                apiMessage,
                currentUserId: currentUserId,
                currentUserRoleIds: roleIds
            )
            if isMentioned {
                let isTopicMessage = topicId != 0
                if isTopicMessage {
                    let topicDedupKey = "\(topicId)_\(apiMessage.messageID)"
                    if !processedBadgeKeys.contains(topicDedupKey) {
                        processedBadgeKeys.insert(topicDedupKey)
                        if processedBadgeKeys.count > 500 { processedBadgeKeys.removeAll() }
                        for i in 0..<allChannels.count {
                            if allChannels[i].channelID == topicId {
                                allChannels[i].countMessUnread += 1
                                updated = true
                            }
                        }
                    }
                    let parentDedupKey = "\(channelId)_\(apiMessage.messageID)"
                    if !processedBadgeKeys.contains(parentDedupKey) {
                        processedBadgeKeys.insert(parentDedupKey)
                        for i in 0..<allChannels.count {
                            if allChannels[i].channelID == channelId {
                                allChannels[i].countMessUnread += 1
                                updated = true
                            }
                        }
                    }
                } else {
                    let dedupKey = "\(channelId)_\(apiMessage.messageID)"
                    if !processedBadgeKeys.contains(dedupKey) {
                        processedBadgeKeys.insert(dedupKey)
                        if processedBadgeKeys.count > 500 { processedBadgeKeys.removeAll() }
                        for i in 0..<allChannels.count {
                            if allChannels[i].channelID == channelId {
                                allChannels[i].countMessUnread += 1
                                updated = true
                            }
                        }
                    }
                }
            }
        }

        guard updated else { return }
        rebuildAndReload()
    }

    @objc private func handleMentionReceived(_ notification: Notification) {
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]),
              let clanId = Self.int64UserInfo(notification.userInfo?["clanId"]) else { return }
        guard clanId == self.clanId, clanId != 0 else { return }
        let messageId = notification.userInfo?["messageId"] as? String ?? ""
        let ts = notification.userInfo?["timestampSeconds"]
        let dedupKey: String
        if !messageId.isEmpty, messageId != "0" {
            dedupKey = "\(channelId)_\(messageId)"
        } else {
            dedupKey = "\(channelId)_\(ts ?? 0)"
        }
        guard !processedBadgeKeys.contains(dedupKey) else { return }
        processedBadgeKeys.insert(dedupKey)
        if processedBadgeKeys.count > 500 { processedBadgeKeys.removeAll() }

        var updated = false
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
                allChannels[i].countMessUnread += 1
                updated = true
            }
        }
        guard updated else { return }
        rebuildAndReload()
    }

    private func rebuildAndReload() {
        let cats = buildChannelCategories(allChannels).map { cat -> ChannelCategory in
            if let existing = self.categories.first(where: { $0.id == cat.id }) {
                return ChannelCategory(id: cat.id, name: cat.name, isCollapsed: existing.isCollapsed, channels: cat.channels)
            }
            return cat
        }
        self.categories = cats
        categoriesPipe.putNext(cats)
        needsReloadPipe.putNext(())
    }

    @objc private func handleChannelMarkedAsRead(_ notification: Notification) {
        guard let channelId = notification.userInfo?["channelId"] as? Int64 else { return }
        let now = UInt32(Date().timeIntervalSince1970)
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
                allChannels[i].countMessUnread = 0
                allChannels[i].lastSeenMessage.timestampSeconds = now
            }
        }
        let cats = buildChannelCategories(allChannels).map { cat -> ChannelCategory in
            if let existing = self.categories.first(where: { $0.id == cat.id }) {
                return ChannelCategory(id: cat.id, name: cat.name, isCollapsed: existing.isCollapsed, channels: cat.channels)
            }
            return cat
        }
        self.categories = cats
        categoriesPipe.putNext(cats)
        needsReloadPipe.putNext(())
    }

    private func setCategories(_ v: [ChannelCategory]) { categories = v; categoriesPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setSelectedChannelId(_ v: Int64?) { selectedChannelId = v; selectedChannelIdPipe.putNext(v) }
    private func setSelectedChannel(_ v: Mezon_Api_ChannelDescription?) { selectedChannel = v; selectedChannelPipe.putNext(v) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v) }

    func load(clanId: Int64, clanName: String) {
        self.clanId = clanId
        self.clanName = clanName
        channelsLoadedPromise.set(false)
        errorMessage = nil

        let hadCache = restoreCachedChannels(clanId: clanId)
        // Only show loading state if we have no cached data to display
        isLoading = !hadCache
        if !hadCache {
            needsReloadPipe.putNext(())
        }
        fetchChannelsWithoutLoadingSignal()
    }

    private func fetchChannelsWithoutLoadingSignal() {
        guard clanId != 0 else { return }
        let clanId = self.clanId

        let signal = channelListSignal(clanId: clanId)
            |> map { channels -> FetchResult in .success(channels) }
            |> `catch` { (error: ChannelFetchError) -> Signal<FetchResult, NoError> in .single(.failure(error.localizedDescription)) }
            |> deliverOnMainQueue

        fetchDisposable.set(signal.start(next: { [weak self] result in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let channels):
                    self.allChannels = channels
                    let storedCollapsed = self.loadCollapsedCategoryIds()
                    let cats = buildChannelCategories(channels, collapsedIds: storedCollapsed)
                    self.categories = cats
                self.channelsLoadedPromise.set(true)
                self.persistSelectedChannel()
                    self.categoriesPipe.putNext(cats)
                self.fetchChannelApps()
                    self.context.account.postbox.setPreferenceData(
                        key: PreferencesKeys.channelList(clanId: clanId),
                        value: self.encodeChannelList(channels)
                    )
                    Task { @MainActor in
                        await self.applyChannelBadgeCountsFromSocket(clanId: clanId)
                    }
                case .failure(let msg):
                    self.errorMessage = msg
                    self.errorMessagePipe.putNext(msg)
                    if !self.allChannels.isEmpty {
                        self.channelsLoadedPromise.set(true)
                    }
                }
                self.channelListNode.endRefreshing()
                self.isLoadingPipe.putNext(false)
                self.needsReloadPipe.putNext(())
            }))
    }

    func toggleCollapse(categoryId: Int64) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        var updated = categories
        updated[idx].isCollapsed.toggle()
        setCategories(updated)
        persistCollapseState()
    }

    func select(channel: Mezon_Api_ChannelDescription) {
        setSelectedChannelId(channel.channelID)
        setSelectedChannel(channel)
        self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId), value: encodeChannelId(channel.channelID))
    }

    func selectWithoutNavigation(channelId: Int64) {
        setSelectedChannelId(channelId)
    }

    func updateChannels(_ channels: [Mezon_Api_ChannelDescription]) {
        allChannels = channels
        let storedCollapsed = loadCollapsedCategoryIds()
        let cats = buildChannelCategories(channels, collapsedIds: storedCollapsed)
        categories = cats
        channelsLoadedPromise.set(true)
        categoriesPipe.putNext(cats)
        needsReloadPipe.putNext(())
    }

    private(set) var allChannels: [Mezon_Api_ChannelDescription] = []

    var currentState: ChannelListState {
        ChannelListState(categories: categories, allChannels: allChannels, selectedChannelId: selectedChannelId, isLoading: isLoading, errorMessage: errorMessage)
    }

    func stateSignal() -> Signal<ChannelListState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var lastEmitted = self.currentState
            subscriber.putNext(lastEmitted)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { newState in
                // Skip duplicate emissions to avoid unnecessary UI reloads
                guard newState != lastEmitted else { return }
                lastEmitted = newState
                subscriber.putNext(newState)
            })
        }
    }

    private func channelListSignal(clanId: Int64) -> Signal<[Mezon_Api_ChannelDescription], ChannelFetchError> {
        let context = self.context
        return Signal { subscriber in
            let task = Task { @MainActor in
                guard let token = await context.getToken() else { subscriber.putError(.noSession); return }
                do {
                    let channels = try await context.account.network.listChannelDescs(clanId: clanId, token: token)
                    subscriber.putNext(channels)
                    subscriber.putCompletion()
                } catch { subscriber.putError(.network(error)) }
            }
            return ActionDisposable { task.cancel() }
        }
    }

    private func persistSelectedChannel() {
        if let data = self.context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId)), data.count >= 8 {
            setSelectedChannelId(data.withUnsafeBytes { $0.load(as: Int64.self).littleEndian })
        }
    }

    private func encodeChannelId(_ id: Int64) -> Data {
        var le = id.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    private func fetchChannelApps() {
        guard clanId != 0 else { return }
        let clanId = self.clanId
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            do {
                let apps = try await self.context.account.network.listChannelApps(clanId: clanId, token: token)
                self.channelListNode.updateChannelApps(apps)
                self.context.account.postbox.setPreferenceData(
                    key: PreferencesKeys.channelApps(clanId: clanId),
                    value: self.encodeChannelApps(apps)
                )
            } catch {
                AppLogger.network.error("Failed to fetch channel apps: \(error)")
            }
        }
    }

    private func restoreCachedChannelApps(clanId: Int64) {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelApps(clanId: clanId)) else { return }
        let apps = decodeChannelApps(data)
        if !apps.isEmpty {
            channelListNode.updateChannelApps(apps)
        }
    }

    private func encodeChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) -> Data {
        var result = Data()
        var count = UInt32(apps.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for app in apps {
            if let d = try? app.serializedData() {
                var len = UInt32(d.count)
                result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                result.append(d)
            }
        }
        return result
    }

    private func decodeChannelApps(_ data: Data) -> [Mezon_Api_ChannelAppResponse] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [Mezon_Api_ChannelAppResponse] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelAppResponse(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    @discardableResult
    private func restoreCachedChannels(clanId: Int64) -> Bool {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { return false }
        let channels = decodeChannelList(data)
        guard !channels.isEmpty else { return false }
        allChannels = channels
        let storedCollapsed = loadCollapsedCategoryIds()
        let cats = buildChannelCategories(channels, collapsedIds: storedCollapsed)
        categories = cats
        channelsLoadedPromise.set(true)
        categoriesPipe.putNext(cats)
        persistSelectedChannel()
        needsReloadPipe.putNext(())
        return true
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

    private func decodeChannelList(_ data: Data) -> [Mezon_Api_ChannelDescription] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    private func persistCollapseState() {
        let collapsed = Set(categories.filter(\.isCollapsed).map(\.id))
        let encoded = encodeCollapsedIds(collapsed)
        context.account.postbox.setPreferenceData(key: PreferencesKeys.collapsedCategories(clanId: clanId), value: encoded)
    }

    private func loadCollapsedCategoryIds() -> Set<Int64>? {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.collapsedCategories(clanId: clanId)) else { return nil }
        return decodeCollapsedIds(data)
    }

    private func encodeCollapsedIds(_ ids: Set<Int64>) -> Data {
        var result = Data()
        var count = UInt32(ids.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for id in ids {
            var le = id.littleEndian
            result.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }
        return result
    }

    private func decodeCollapsedIds(_ data: Data) -> Set<Int64> {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result = Set<Int64>()
        var offset = 4
        for _ in 0..<count {
            guard offset + 8 <= data.count else { break }
            let id = data.subdata(in: offset..<(offset + 8)).withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
            result.insert(id)
            offset += 8
        }
        return result
    }
}
