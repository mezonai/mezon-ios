import UIKit
import QuartzCore
import SwiftProtobuf

struct ChannelListState: Equatable {
    var categories: [ChannelCategory]
    var allChannels: [Mezon_Api_ChannelDescription] = []
    var selectedChannelId: Int64?
    var isLoading: Bool
    var errorMessage: String?
    var voiceUsersByChannel: [Int64: [String]] = [:]

    static let empty = ChannelListState(
        categories: [], allChannels: [], selectedChannelId: nil,
        isLoading: false, errorMessage: nil)

    static func == (lhs: ChannelListState, rhs: ChannelListState) -> Bool {
        guard lhs.isLoading == rhs.isLoading
            && lhs.selectedChannelId == rhs.selectedChannelId
            && lhs.errorMessage == rhs.errorMessage
            && lhs.categories.count == rhs.categories.count
            && lhs.allChannels.count == rhs.allChannels.count
            && lhs.voiceUsersByChannel == rhs.voiceUsersByChannel
            && zip(lhs.categories, rhs.categories).allSatisfy({
                $0.id == $1.id && $0.isCollapsed == $1.isCollapsed
                    && $0.channels.count == $1.channels.count
                    && ($0.favoriteFlatChannels?.count ?? 0) == ($1.favoriteFlatChannels?.count ?? 0)
            })
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

    var orderedThreadChildren: [Int64: [Mezon_Api_ChannelDescription]] = [:]

    var favoriteFlatChannels: [Mezon_Api_ChannelDescription]? = nil


    static let favoritesCategoryId: Int64 = Int64.min
}

enum ChannelListRow {
    case channel(Mezon_Api_ChannelDescription, isInFavoriteSection: Bool)
    case thread(Mezon_Api_ChannelDescription, isLast: Bool, isInFavoriteSection: Bool)
    case voiceMembersCollapsed(Mezon_Api_ChannelDescription, userIds: [String])
    case voiceMemberExpanded(Mezon_Api_ChannelDescription, userId: String)

    var channelDesc: Mezon_Api_ChannelDescription {
        switch self {
        case .channel(let ch, _): return ch
        case .thread(let ch, _, _): return ch
        case .voiceMembersCollapsed(let ch, _): return ch
        case .voiceMemberExpanded(let ch, _): return ch
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
        case .voice: return "Chat/SpeakerIcon"
        case .thread: return "Channel/ChevronRight"
        case .streaming: return "Channel/channelStream"
        case .app: return "Channel/channelApp"
        case .forum: return "Channel/channel"
        default: return "Channel/channel"
        }
    }

    var isSystemImage: Bool { true }
}


private func localizedFavoriteChannelsCategoryTitle() -> String {
    NSLocalizedString("favorite_channel_section", tableName: nil, bundle: .main, value: "Favorite channels", comment: "Channel list section header")
}


private func prioritizeChannels(_ channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
    channels.sorted { a, b in
        let aTop = a.parentID == 0
        let bTop = b.parentID == 0
        if aTop && !bTop { return true }
        if !aTop && bTop { return false }
        if aTop && bTop {
            return String(a.channelID) < String(b.channelID)
        }
        return String(a.parentID) < String(b.parentID)
    }
}


private func sortChannelsForCategory(_ channels: [Mezon_Api_ChannelDescription], categoryId: Int64) -> [Mezon_Api_ChannelDescription] {
    var sortedChannels: [Mezon_Api_ChannelDescription] = []
    let numOfChannel: Int = channels.count
    let threadStart: Int = channels.firstIndex(where: { $0.parentID != 0 }) ?? numOfChannel
    var indexThread: Int = threadStart
    let numOfParent: Int = threadStart
    var i = 0
    while i < numOfParent {
        let channel = channels[i]
        if channel.categoryID == categoryId {
            sortedChannels.append(channel)
            while indexThread < numOfChannel {
                let thread = channels[indexThread]
                let parentIdStr = String(thread.parentID)
                if thread.parentID == channel.channelID {
                    sortedChannels.append(thread)
                    indexThread += 1
                } else if String(channel.channelID) < parentIdStr {
                    indexThread -= 1
                    break
                } else {
                    indexThread += 1
                }
            }
        }
        i += 1
    }
    return sortedChannels
}


private func inferredCategoryDescs(from channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_CategoryDesc] {
    var seen = Set<Int64>()
    var result: [Mezon_Api_CategoryDesc] = []
    for ch in channels where ch.parentID == 0 {
        let id = ch.categoryID
        guard !seen.contains(id) else { continue }
        seen.insert(id)
        var c = Mezon_Api_CategoryDesc()
        c.categoryID = id
        c.categoryName = ch.categoryName
        c.clanID = ch.clanID
        result.append(c)
    }
    return result
}

private func splitParentsAndOrderedThreads(from flatSorted: [Mezon_Api_ChannelDescription])
    -> (parents: [Mezon_Api_ChannelDescription], threadsByParent: [Int64: [Mezon_Api_ChannelDescription]])
{
    var parents: [Mezon_Api_ChannelDescription] = []
    var threadsByParent: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    var i = 0
    while i < flatSorted.count {
        let ch = flatSorted[i]
        parents.append(ch)
        i += 1
        var threads: [Mezon_Api_ChannelDescription] = []
        while i < flatSorted.count, flatSorted[i].parentID == ch.channelID {
            threads.append(flatSorted[i])
            i += 1
        }
        if !threads.isEmpty {
            threadsByParent[ch.channelID] = threads
        }
    }
    return (parents, threadsByParent)
}


private func buildChannelCategories(
    _ channels: [Mezon_Api_ChannelDescription],
    categoryDescs: [Mezon_Api_CategoryDesc],
    favoriteChannelIds: Set<Int64>,
    collapsedIds: Set<Int64>? = nil
) -> [ChannelCategory] {
    let prioritized = prioritizeChannels(channels)
    let useCategories: [Mezon_Api_CategoryDesc] = {
        guard !categoryDescs.isEmpty else { return inferredCategoryDescs(from: channels) }
        var result = categoryDescs
        let knownIds = Set(categoryDescs.map(\.categoryID))
        for inferred in inferredCategoryDescs(from: channels) where !knownIds.contains(inferred.categoryID) {
            result.append(inferred)
        }
        return result
    }()

    var favorFlat: [Mezon_Api_ChannelDescription] = []
    for cat in useCategories {
        let flatSorted = sortChannelsForCategory(prioritized, categoryId: cat.categoryID)
        for ch in flatSorted where favoriteChannelIds.contains(ch.channelID) {
            favorFlat.append(ch)
        }
    }

    var out: [ChannelCategory] = []
    if !favoriteChannelIds.isEmpty {
        let favCat = ChannelCategory(
            id: ChannelCategory.favoritesCategoryId,
            name: localizedFavoriteChannelsCategoryTitle(),
            isCollapsed: collapsedIds?.contains(ChannelCategory.favoritesCategoryId) ?? false,
            channels: [],
            orderedThreadChildren: [:],
            favoriteFlatChannels: favorFlat
        )
        out.append(favCat)
    }

    for cat in useCategories {
        let flatSorted = sortChannelsForCategory(prioritized, categoryId: cat.categoryID)
        let (parents, threadsMap) = splitParentsAndOrderedThreads(from: flatSorted)
        let collapsed = collapsedIds?.contains(cat.categoryID) ?? false
        out.append(ChannelCategory(
            id: cat.categoryID,
            name: cat.categoryName,
            isCollapsed: collapsed,
            channels: parents,
            orderedThreadChildren: threadsMap,
            favoriteFlatChannels: nil
        ))
    }
    return out
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
    if let flat = category.favoriteFlatChannels {
        var rows: [ChannelListRow] = []
        for ch in flat {
            if ch.parentID == 0 {
                rows.append(.channel(ch, isInFavoriteSection: true))
            } else {
                rows.append(.thread(ch, isLast: true, isInFavoriteSection: true))
            }
        }
        return rows
    }
    var rows: [ChannelListRow] = []
    for ch in category.channels {
        rows.append(.channel(ch, isInFavoriteSection: false))
        let threads: [Mezon_Api_ChannelDescription]
        if let o = category.orderedThreadChildren[ch.channelID], !o.isEmpty {
            threads = o
        } else if let t = threadLookup[ch.channelID] {
            threads = t
        } else {
            threads = []
        }
        for (i, thread) in threads.enumerated() {
            rows.append(.thread(thread, isLast: i == 0, isInFavoriteSection: false))
        }
    }
    return rows
}

private enum FetchResult {
    case success([Mezon_Api_ChannelDescription], [Mezon_Api_CategoryDesc], Set<Int64>)
    case failure(String)
}

final class ChannelListViewController: ViewController {

    private let context: AccountContext
    private let initialSessionEpoch: Int
    private var isCurrentSessionAlive: Bool { context.isStillCurrentSession(epoch: initialSessionEpoch) }
    private let fetchDisposable = MetaDisposable()
    private let dataDisposable = MetaDisposable()
    private var processedBadgeKeys = Set<String>()

    private func indexOfChannelInAllChannels(_ channelId: Int64) -> Int? {
        allChannels.firstIndex { $0.channelID == channelId }
    }

    private func parentChannelIdForThreadBadge(topicId: Int64, messageChannelId: Int64) -> Int64 {
        guard topicId != 0 else { return messageChannelId }
        if let row = allChannels.first(where: { $0.channelID == topicId }), row.parentID != 0 {
            return row.parentID
        }
        if messageChannelId != 0, messageChannelId != topicId {
            return messageChannelId
        }
        return messageChannelId
    }

    private func recordTimestampSentinelForMention(
        clanId: Int64, channelIds: [Int64], ts: UInt32?
    ) {
        guard let ts, ts != 0, clanId != 0 else { return }
        for w in -2...2 {
            let t = Int64(ts) + Int64(w)
            for c in channelIds where c != 0 {
                processedBadgeKeys.insert("ts:\(clanId)_\(c)_\(t)")
            }
        }
    }

    private func hasRecentMentionSentinel(
        clanId: Int64, channelId: Int64, ts: UInt32?
    ) -> Bool {
        guard let ts, ts != 0, clanId != 0 else { return false }
        for w in -2...2 {
            let t = Int64(ts) + Int64(w)
            if processedBadgeKeys.contains("ts:\(clanId)_\(channelId)_\(t)") { return true }
        }
        return false
    }

    @discardableResult
    private func applyMentionEventUnreadIfNeeded(
        clanId: Int64,
        messageId: Int64,
        parentChannelId: Int64,
        threadChannelId: Int64?,
        ts: UInt32? = nil
    ) -> Bool {
        guard clanId != 0, messageId != 0, parentChannelId != 0 else { return false }
        let ekey = "m:\(clanId)_\(messageId)"
        if processedBadgeKeys.contains(ekey) { return false }
        processedBadgeKeys.insert(ekey)
        recordTimestampSentinelForMention(
            clanId: clanId,
            channelIds: [parentChannelId, threadChannelId ?? 0],
            ts: ts
        )
        if processedBadgeKeys.count > 1500 { processedBadgeKeys.removeAll() }
        var didChange = false
        if let ip = indexOfChannelInAllChannels(parentChannelId) {
            allChannels[ip].countMessUnread += 1
            didChange = true
        }
        if let t = threadChannelId, t != 0, t != parentChannelId, let it = indexOfChannelInAllChannels(t) {
            allChannels[it].countMessUnread += 1
            didChange = true
        }
        return didChange
    }

    deinit {
        fetchDisposable.dispose()
        dataDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
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
    private var showEmptyCategoriesEnabled: Bool = false
    private(set) var selectedChannelId: Int64?
    private(set) var selectedChannel: Mezon_Api_ChannelDescription?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var clanId: Int64 = 0
    private(set) var clanName: String = ""
    private(set) var clanLogoURL: String = ""

    private var pendingSkeletonRevealItem: DispatchWorkItem?
    private let skeletonRevealDelay: TimeInterval = 0.4

    private var channelListCategoryDescs: [Mezon_Api_CategoryDesc] = []

    private var channelListFavoriteIds: Set<Int64> = []

    private var channelListNode: ChannelListContainerNode { displayNode as! ChannelListContainerNode }

    private var enclosingNavigationController: NavigationController? {
        var current: UIViewController? = self
        while let node = current {
            if let nav = node as? NavigationController {
                return nav
            }
            if let nav = node.navigationController as? NavigationController {
                return nav
            }
            current = node.parent
        }
        return nil
    }

    init(context: AccountContext) {
        self.context = context
        self.initialSessionEpoch = context.sessionEpoch
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = ChannelListInteraction(
            onSelectChannel: { [weak self] ch in self?.handleChannelTap(ch) },
            onLongPressChannel: { [weak self] ch in self?.presentChannelActionSheet(ch) },
            onToggleCollapse: { [weak self] id in self?.toggleCollapse(categoryId: id) },
            onRefresh: { [weak self] in self?.fetchChannels() },
            onPresentSettings: { [weak self] in self?.presentSettings() },
            onInviteClan: { [weak self] in self?.presentInviteClanSheet() },
            onSearchTapped: { [weak self] in self?.searchTappedPipe.putNext(()) },
            onQRTapped: { [weak self] in
                guard let self else { return }
                let vc = QRScannerViewController(context: self.context)
                self.enclosingNavigationController?.pushViewController(vc, animated: true)
            },
            onSelectChannelApp: { [weak self] app in self?.openChannelApp(app) },
            onClearCurrentChannelSelection: { [weak self] in self?.clearCurrentChannelSelection() },
            isShowEmptyCategoriesEnabled: { [weak self] in self?.showEmptyCategoriesEnabled ?? false },
            onToggleShowEmptyCategories: { [weak self] value in self?.setShowEmptyCategories(value) }
        )
        let initialClan = effectiveClanIdForChannelAppsHydration()
        let initialApps = initialClan != 0 ? channelAppsRawFromCache(clanId: initialClan) : []
        let container = ChannelListContainerNode(
            signal: stateSignal(),
            interaction: interaction,
            initialChannelApps: initialApps
        )
        container.voiceMemberResolver = { [weak self] uid in
            self?.resolveVoiceMember(uid)
        }
        displayNode = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        channelListNode.applyTheme()
        hydrateChannelAppsFromCacheForEffectiveClan()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMarkedAsRead(_:)), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewMessageReceived(_:)), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMentionReceived(_:)), name: Notification.Name("MezonMentionReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSocketStatusForChannelBadges(_:)), name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleJoinedClanForChannelBadges(_:)), name: Notification.Name("MezonJoinedClanChatForBadges"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoicePresenceChanged(_:)), name: .mezonVoicePresenceChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNetworkStatusChanged(_:)), name: NetworkMonitor.statusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserChannelAddedFromSocket(_:)), name: .mezonUserChannelAddedFromSocket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelDescriptionDidUpdate(_:)), name: .mezonChannelDescriptionDidUpdate, object: nil)
    }

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64 else { return }
        guard gid == clanId, clanId != 0 else { return }
        if let p = readChannelCachePayloadIfAvailable(clanId: clanId) {
            applyChannelCachePayload(channels: p.channels, meta: p.meta)
            needsReloadPipe.putNext(())
        }
    }

    private func effectiveClanIdForChannelAppsHydration() -> Int64 {
        if clanId != 0 { return clanId }
        return persistedSelectedClanId()
    }

    private func channelAppsRawFromCache(clanId: Int64) -> [Mezon_Api_ChannelAppResponse] {
        guard clanId != 0 else { return [] }
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else { return [] }
        let apps = decodeChannelApps(data)
        if apps.isEmpty { return [] }
        guard cachedChannelAppsMatchClan(apps, clanId: clanId) else { return [] }
        return apps
    }

    private func hydrateChannelAppsFromCacheForEffectiveClan() {
        let id = effectiveClanIdForChannelAppsHydration()
        guard id != 0 else { return }
        restoreCachedChannelApps(clanId: id)
    }

    private func persistedSelectedClanId() -> Int64 {
        let udValue = UserDefaults.standard.integer(forKey: "mezon_selectedClanId")
        if udValue != 0 { return Int64(udValue) }
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedClanId), data.count >= 8 {
            return data.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
        }
        return 0
    }

    @objc private func handleUserChannelAddedFromSocket(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64 else { return }
        guard gid == clanId, clanId != 0 else { return }
        if let p = readChannelCachePayloadIfAvailable(clanId: clanId) {
            applyChannelCachePayload(channels: p.channels, meta: p.meta)
        } else if NetworkMonitor.shared.isConnected {
            fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
        }
        syncSelectedChannelFromStoredPreferences()
        needsReloadPipe.putNext(())
    }

    @objc private func handleVoicePresenceChanged(_ notification: Notification) {
        guard let n = notification.userInfo?["clanId"] as? NSNumber else { return }
        guard n.int64Value == clanId, clanId != 0 else { return }
        needsReloadPipe.putNext(())
    }

    @objc private func handleNetworkStatusChanged(_ notification: Notification) {
        let connected = (notification.userInfo?["isConnected"] as? Bool) ?? NetworkMonitor.shared.isConnected
        guard connected, clanId != 0 else { return }
        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
    }

    @objc private func handleJoinedClanForChannelBadges(_ notification: Notification) {
        guard let joinedClan = notification.userInfo?["clanId"] as? Int64 else { return }
        guard joinedClan == clanId, joinedClan != 0 else { return }
        Task { @MainActor in
            await self.applyChannelBadgeCounts(clanId: joinedClan)
        }
    }

    @objc private func handleSocketStatusForChannelBadges(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool, connected else { return }
        guard clanId != 0 else { return }

        lastChannelFetchAtByClanId.removeValue(forKey: clanId)
        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
    }


    private func channelListRowsVisuallyEqual(_ a: [Mezon_Api_ChannelDescription], _ b: [Mezon_Api_ChannelDescription]) -> Bool {
        guard a.count == b.count else { return false }
        let byId = Dictionary(uniqueKeysWithValues: b.map { ($0.channelID, $0) })
        for ch in a {
            guard let o = byId[ch.channelID] else { return false }
            if ch.countMessUnread != o.countMessUnread { return false }
            if ch.channelLabel != o.channelLabel { return false }
            if ch.type != o.type { return false }
            if ch.channelPrivate != o.channelPrivate { return false }
            if ch.ageRestricted != o.ageRestricted { return false }
            if ch.lastSeenMessage.timestampSeconds != o.lastSeenMessage.timestampSeconds { return false }
            if ch.lastSentMessage.timestampSeconds != o.lastSentMessage.timestampSeconds { return false }
            if ch.hasLastSentMessage != o.hasLastSentMessage { return false }
            let uA = ch.countMessUnread > 0
                || (ch.hasLastSentMessage && ch.lastSeenMessage.timestampSeconds < ch.lastSentMessage.timestampSeconds)
            let uB = o.countMessUnread > 0
                || (o.hasLastSentMessage && o.lastSeenMessage.timestampSeconds < o.lastSentMessage.timestampSeconds)
            if uA != uB { return false }
        }
        return true
    }

    private var inflightBadgeCountTask: [Int64: Task<[Mezon_Api_ChannelDescription], Never>] = [:]
    private var lastBadgeCountFetchAtByClanId: [Int64: Date] = [:]
    private let badgeCountFetchCooldown: TimeInterval = 5.0

    @MainActor
    private func fetchMergedChannelsWithBadgeCounts(base: [Mezon_Api_ChannelDescription], clanId: Int64) async -> [Mezon_Api_ChannelDescription] {
        guard clanId != 0 else { return base }
        guard clanId == self.clanId else { return base }

        if let inflight = inflightBadgeCountTask[clanId] {
            let rows = await inflight.value
            guard isCurrentSessionAlive else { return base }
            guard clanId == self.clanId else { return base }
            guard !rows.isEmpty else { return base }
            var merged = base
            ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &merged, badgeRows: rows)
            return merged
        }

        if let last = lastBadgeCountFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < badgeCountFetchCooldown {
            return base
        }

        let token = await context.getTokenPreferringCachedSkipSessionReadyWait()
        guard clanId == self.clanId else { return base }
        guard let token else { return base }

        let task: Task<[Mezon_Api_ChannelDescription], Never> = Task.detached(priority: .utility) {
            do {
                return try await MezonHTTPClient.shared.listChannelBadgeCount(clanId: clanId, token: token).channeldesc
            } catch {
                return []
            }
        }
        inflightBadgeCountTask[clanId] = task
        let rows = await task.value
        inflightBadgeCountTask[clanId] = nil
        lastBadgeCountFetchAtByClanId[clanId] = Date()

        guard isCurrentSessionAlive else { return base }
        guard clanId == self.clanId else { return base }
        guard !rows.isEmpty else { return base }
        var merged = base
        ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &merged, badgeRows: rows)
        return merged
    }

    @MainActor
    private func applyChannelBadgeCounts(clanId: Int64) async {
        guard clanId != 0 else { return }
        guard clanId == self.clanId else { return }
        let updated = await fetchMergedChannelsWithBadgeCounts(base: allChannels, clanId: clanId)
        guard isCurrentSessionAlive else { return }
        if channelListRowsVisuallyEqual(allChannels, updated) {
            let total = updated.reduce(Int32(0)) { $0 + $1.countMessUnread }
            NotificationCenter.default.post(
                name: Notification.Name("MezonClanChannelUnreadDerived"),
                object: nil,
                userInfo: ["clanId": clanId, "totalUnread": total]
            )
            return
        }
        allChannels = updated
        let storedCollapsed = loadCollapsedCategoryIds()
        let built = buildChannelCategories(
            updated,
            categoryDescs: channelListCategoryDescs,
            favoriteChannelIds: channelListFavoriteIds,
            collapsedIds: storedCollapsed
        )
        let cats = applyBuiltCategoriesPreservingCollapse(built)
        categories = cats
        categoriesPipe.putNext(cats)
        persistFullChannelListCache(
            clanId: clanId,
            channels: updated,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds,
            categories: cats
        )
        needsReloadPipe.putNext(())
        postClanSidebarUnreadDerivedFromCurrentChannels()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        channelListNode.updateLayout(layout: layout, transition: transition)
    }

    func configure(clanId: Int64, clanName: String, logoURL: String? = nil, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        self.clanLogoURL = logoURL ?? ""
        guard clanId != self.clanId else {
            channelListNode.configure(clanName: clanName, clanId: clanId, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, isCommunity: isCommunity)
            if clanId != 0 && !channelListNode.hasDisplayedChannelApps {
                hydrateChannelAppsFromCacheForEffectiveClan()
            }
            return
        }
        let previousClanId = self.clanId
        if previousClanId != 0 {
            context.clearPersistedSelectedChannelPreference(forClanId: previousClanId)
        }
        setSelectedChannelId(nil)
        setSelectedChannel(nil)
        channelListNode.clearChannelApps()
        if clanId != 0 {
            restoreCachedChannelApps(clanId: clanId)
        }
        channelListNode.markClanSwitching()
        channelListNode.configure(clanName: clanName, clanId: clanId, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, isCommunity: isCommunity)
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
        self.enclosingNavigationController?.pushViewController(vc, animated: true)
    }

    private func presentInviteClanSheet() {
        guard clanId != 0 else { return }
        let vc = ClanInviteSheetViewController(context: context, clanId: clanId)
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = vc.sheetPresentationController {
                sheet.prefersGrabberVisible = true
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
        }
        present(vc, animated: true)
    }

    private func presentChannelActionSheet(_ channel: Mezon_Api_ChannelDescription) {
        let (isMuted, welcomeChannelId): (Bool, Int64?) = context.account.postbox.read { tx in
            let muted: Bool = {
                guard let record = tx.getNotificationSetting(entityId: channel.channelID) else { return false }
                return record.timeMuteSeconds != 0
            }()
            let welcome: Int64? = {
                guard let data = tx.getClan(id: self.clanId)?.data, !data.isEmpty,
                      let desc = try? Mezon_Api_ClanDesc(serializedBytes: data) else { return nil }
                return desc.welcomeChannelID
            }()
            return (muted, welcome)
        }
        let isFavorite = self.channelListFavoriteIds.contains(channel.channelID)
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let isGeneralChannel: Bool = {
            guard let welcomeChannelId else { return false }
            return channel.channelID == welcomeChannelId
        }()

        let canManage: Bool
        if isThread {
            let currentUserId = Int64(self.context.account.id) ?? 0
            let isCreator = channel.creatorID == currentUserId
            let isOwner = self.context.rolePermissions.isClanOwner(clanId: self.clanId)
            let isAdmin = self.context.rolePermissions.hasClanPermission(.administrator, clanId: self.clanId)
            let canManageThread = self.context.rolePermissions.canManageThread(clanId: self.clanId, channelId: channel.channelID)
            
            canManage = (isCreator && canManageThread) || isAdmin || isOwner
        } else {
            canManage = self.context.rolePermissions.canManageChannel(clanId: self.clanId)
        }

        let actionSheet = ChannelActionSheetController(
            channelId: channel.channelID,
            channelName: channel.channelLabel,
            clanName: clanName,
            clanAvatarURL: clanLogoURL,
            isFavorite: isFavorite,
            isMuted: isMuted,
            isThread: isThread,
            channelType: channel.type,
            canManageChannel: canManage,
            isGeneralChannel: isGeneralChannel,
            onAction: { [weak self] action in
                guard let self else { return }
                switch action {
                case .markAsRead:
                    self.handleMarkAsRead(channel)
                case .markFavorite:
                    self.handleMarkFavorite(channel)
                case .unmarkFavorite:
                    self.handleUnmarkFavorite(channel)
                case .copyLink:
                    let link = "https://mezon.ai/chat/clans/\(channel.clanID)/channels/\(channel.channelID)"
                    UIPasteboard.general.string = link
                    Toast.success(L(L10n.MessageAction.copied))
                case .mute:
                    self.presentMuteDurationSheet(channel)
                case .unmute:
                    self.handleMuteChannel(channel, mute: false)
                case .notificationSettings:
                    self.presentNotificationSettings(channel)
                case .threads:
                    let vc = ThreadListViewController(
                        context: self.context,
                        clanId: channel.clanID,
                        parentChannelId: channel.channelID,
                        parentCategoryId: channel.categoryID,
                        parentChannelLabel: channel.channelLabel,
                        composerParentChannel: channel
                    )
                    self.enclosingNavigationController?.pushViewController(vc, animated: true)
                case .editChannel:
                    self.presentChannelSettings(channel)
                case .deleteChannel:
                    self.presentDeleteChannelConfirm(channel)
                case .leaveThread:
                    self.presentLeaveThreadConfirm(channel)
                }
            }
        )
        if let window = self.view.window as? WindowHost {
            window.present(actionSheet, on: .root, blockInteraction: false, completion: {})
        }
        
        fetchNotificationSettingForBottomsheet(channelId: channel.channelID)
    }
    
    private func fetchNotificationSettingForBottomsheet(channelId: Int64) {
        Task { @MainActor in
            let startEpoch = context.sessionEpoch
            guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            do {
                let noti = try await MezonHTTPClient.shared.getNotificationChannel(channelId: channelId, token: token)
                guard context.isStillCurrentSession(epoch: startEpoch) else { return }
                let record = NotificationSettingRecord(id: 0, entityId: channelId, scope: .channel, notificationSettingType: noti.notificationSettingType, timeMuteSeconds: UInt32(bitPattern: noti.timeMuteSeconds), active: noti.active)
                context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }

                NotificationCenter.default.post(
                    name: .mezonNotificationSettingDidUpdate,
                    object: nil,
                    userInfo: ["channelId": channelId, "record": record]
                )
            } catch {
            }
        }
    }

    private func handleMarkAsRead(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.markAsRead(channelId: channel.channelID, clanId: channel.clanID, categoryId: channel.categoryID, token: token)
                NotificationCenter.default.post(
                    name: Notification.Name("MezonChannelMarkedAsRead"),
                    object: nil,
                    userInfo: ["channelId": channel.channelID, "clanId": channel.clanID]
                )
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleMarkFavorite(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let _ = try await MezonHTTPClient.shared.addFavoriteChannel(channelId: channel.channelID, clanId: channel.clanID, token: token)
                channelListFavoriteIds.insert(channel.channelID)
                
                let built = buildChannelCategories(
                    allChannels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: loadCollapsedCategoryIds()
                )
                let cats = applyBuiltCategoriesPreservingCollapse(built)
                categories = cats
                categoriesPipe.putNext(cats)
                persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: cats)
                needsReloadPipe.putNext(())
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleUnmarkFavorite(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.removeFavoriteChannel(channelId: channel.channelID, clanId: channel.clanID, token: token)
                channelListFavoriteIds.remove(channel.channelID)
                
                let built = buildChannelCategories(
                    allChannels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: loadCollapsedCategoryIds()
                )
                let cats = applyBuiltCategoriesPreservingCollapse(built)
                categories = cats
                categoriesPipe.putNext(cats)
                persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: cats)
                needsReloadPipe.putNext(())
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func presentMuteDurationSheet(_ channel: Mezon_Api_ChannelDescription) {
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let vc = MuteDurationViewController(
            channelName: channel.channelLabel,
            channelId: channel.channelID,
            clanId: channel.clanID,
            context: self.context,
            isThread: isThread
        ) { [weak self] duration in
            self?.handleMuteChannel(channel, muteTimeSeconds: duration.seconds)
        }
        self.enclosingNavigationController?.pushViewController(vc)
    }

    private func handleMuteChannel(_ channel: Mezon_Api_ChannelDescription, mute: Bool) {
        handleMuteChannel(channel, muteTimeSeconds: 0)
    }

    private func handleMuteChannel(_ channel: Mezon_Api_ChannelDescription, muteTimeSeconds: Int32) {
        ChannelMuteHelper.setMuteChannel(
            context: context,
            channelId: channel.channelID,
            clanId: channel.clanID,
            muteTimeSeconds: muteTimeSeconds
        )
    }

    private func presentNotificationSettings(_ channel: Mezon_Api_ChannelDescription) {
        let currentTypeInt = context.account.postbox.read { tx in
            tx.getNotificationSetting(entityId: channel.channelID)?.notificationSettingType
        }
        let currentType: ChannelNotificationType
        if let typeInt = currentTypeInt, let type = ChannelNotificationType(rawValue: typeInt) {
            currentType = type
        } else {
            currentType = .useDefault
        }
        
        let sheet = NotificationSettingsSheetController(
            channelId: channel.channelID,
            clanId: channel.clanID,
            context: context,
            currentType: currentType,
            defaultLabel: L(L10n.NotificationSettings.allMessages)
        )
        if let window = self.view.window as? WindowHost {
            window.present(sheet, on: .root, blockInteraction: false, completion: {})
            sheet.animateIn()
        }
    }

    private func presentDeleteChannelConfirm(_ channel: Mezon_Api_ChannelDescription) {
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let title = isThread ? L(L10n.ChannelAction.deleteThread) : L(L10n.Channel.delete)
        let message = isThread ? L(L10n.Channel.deleteThreadConfirm) : L(L10n.Channel.deleteConfirm)

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] _ in
            self?.handleDeleteChannel(channel)
        }))
        if let rootVC = self.view.window?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            topVC.present(alert, animated: true)
        }
    }

    private func presentLeaveThreadConfirm(_ channel: Mezon_Api_ChannelDescription) {
        let title = L(L10n.ChannelAction.leaveThread)
        let message = L(L10n.ChannelAction.leaveThreadConfirm)

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] _ in
            self?.handleLeaveThread(channel)
        }))
        if let rootVC = self.view.window?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            topVC.present(alert, animated: true)
        }
    }

    private func handleDeleteChannel(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.deleteChannelDesc(channelId: channel.channelID, clanId: channel.clanID, token: token)
                allChannels.removeAll { $0.channelID == channel.channelID }
                
                let built = buildChannelCategories(
                    allChannels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: loadCollapsedCategoryIds()
                )
                let cats = applyBuiltCategoriesPreservingCollapse(built)
                categories = cats
                categoriesPipe.putNext(cats)
                persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: cats)
                needsReloadPipe.putNext(())
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleLeaveThread(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.leaveThread(clanId: channel.clanID, channelId: channel.channelID, token: token)
                allChannels.removeAll { $0.channelID == channel.channelID }
                
                let built = buildChannelCategories(
                    allChannels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: loadCollapsedCategoryIds()
                )
                let cats = applyBuiltCategoriesPreservingCollapse(built)
                categories = cats
                categoriesPipe.putNext(cats)
                persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: cats)
                needsReloadPipe.putNext(())
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func presentChannelSettings(_ channel: Mezon_Api_ChannelDescription) {
        let vc = ChannelSettingsViewController(
            context: context,
            clanId: channel.clanID,
            channelId: channel.channelID,
            categoryId: channel.categoryID,
            categoryName: channel.categoryName,
            channelType: channel.type,
            channelPrivate: channel.channelPrivate == 1,
            channelName: channel.channelLabel,
            channelTopic: channel.topic
        )
        self.enclosingNavigationController?.pushViewController(vc, animated: true)
    }

    func refresh() { fetchChannels() }

    func fetchChannels() {
        guard clanId != 0 else { return }
        isLoading = true
        errorMessage = nil

        needsReloadPipe.putNext(())
        lastChannelFetchAtByClanId.removeValue(forKey: clanId)
        lastBadgeCountFetchAtByClanId.removeValue(forKey: clanId)
        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: true)
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

        let apiMessage: Mezon_Api_ChannelMessage? = (notification.userInfo?["serializedChannelMessage"] as? Data).flatMap { try? Mezon_Api_ChannelMessage(serializedBytes: $0) }
        var topicId = Self.int64UserInfo(notification.userInfo?["topicId"]) ?? 0
        if let m = apiMessage, topicId == 0, m.topicID != 0 { topicId = m.topicID }
        if topicId != 0 {
            if ActiveChannelTracker.currentChannelId == topicId { return }
        } else {
            if ActiveChannelTracker.currentChannelId == channelId { return }
        }

        var updated = false
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
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

        if let apiMessage {
            let currentUserId = context.currentUser?.id
            let roleIds = ClanListViewController.getCurrentUserRoleIds(context: context)
            let isMentioned = ClanListViewController.checkMessageMentionsUser(
                apiMessage,
                currentUserId: currentUserId,
                currentUserRoleIds: roleIds
            )
            if isMentioned, apiMessage.messageID != 0 {
                if topicId != 0 {
                    let parentId = parentChannelIdForThreadBadge(topicId: topicId, messageChannelId: channelId)
                    if applyMentionEventUnreadIfNeeded(
                        clanId: clanId, messageId: apiMessage.messageID, parentChannelId: parentId, threadChannelId: topicId, ts: ts
                    ) { updated = true }
                } else {
                    if applyMentionEventUnreadIfNeeded(
                        clanId: clanId, messageId: apiMessage.messageID, parentChannelId: channelId, threadChannelId: nil, ts: ts
                    ) { updated = true }
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
        if notification.userInfo?["isParentOfTopic"] as? Bool == true { return }
        let messageId = notification.userInfo?["messageId"] as? String ?? ""
        let ts = notification.userInfo?["timestampSeconds"]
        let tsU32: UInt32? = {
            if let t = ts as? UInt32 { return t }
            if let t = ts as? Int { return UInt32(t) }
            if let t = ts as? NSNumber { return t.uint32Value }
            return nil
        }()
        if !messageId.isEmpty, messageId != "0", let mid = Int64(messageId), mid != 0 {
            if processedBadgeKeys.contains("m:\(clanId)_\(mid)") { return }
            var updated = false
            let topicFromNoti = Self.int64UserInfo(notification.userInfo?["topicId"]) ?? 0
            if topicFromNoti != 0 {
                let parentId = parentChannelIdForThreadBadge(
                    topicId: topicFromNoti, messageChannelId: channelId
                )
                if applyMentionEventUnreadIfNeeded(
                    clanId: clanId, messageId: mid, parentChannelId: parentId, threadChannelId: topicFromNoti, ts: tsU32
                ) { updated = true }
            } else {
                if applyMentionEventUnreadIfNeeded(
                    clanId: clanId, messageId: mid, parentChannelId: channelId, threadChannelId: nil, ts: tsU32
                ) { updated = true }
            }
            if updated { rebuildAndReload() }
            return
        }
        if hasRecentMentionSentinel(clanId: clanId, channelId: channelId, ts: tsU32) { return }
        let dedupKey: String
        if !messageId.isEmpty, messageId != "0" {
            dedupKey = "\(channelId)_\(messageId)"
        } else {
            dedupKey = "\(channelId)_\(ts ?? 0)"
        }
        guard !processedBadgeKeys.contains(dedupKey) else { return }
        processedBadgeKeys.insert(dedupKey)
        if processedBadgeKeys.count > 1500 { processedBadgeKeys.removeAll() }
        if let i = indexOfChannelInAllChannels(channelId) {
            allChannels[i].countMessUnread += 1
            rebuildAndReload()
        }
    }

    private func applyBuiltCategoriesPreservingCollapse(_ built: [ChannelCategory]) -> [ChannelCategory] {
        built.map { cat in
            if let existing = categories.first(where: { $0.id == cat.id }) {
                return ChannelCategory(
                    id: cat.id,
                    name: cat.name,
                    isCollapsed: existing.isCollapsed,
                    channels: cat.channels,
                    orderedThreadChildren: cat.orderedThreadChildren,
                    favoriteFlatChannels: cat.favoriteFlatChannels
                )
            }
            return cat
        }
    }

    private func rebuildAndReload() {
        let storedCollapsed = loadCollapsedCategoryIds()
        let built = buildChannelCategories(
            allChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteChannelIds: channelListFavoriteIds,
            collapsedIds: storedCollapsed
        )
        let cats = applyBuiltCategoriesPreservingCollapse(built)
        categories = cats
        categoriesPipe.putNext(cats)
        needsReloadPipe.putNext(())
        postClanSidebarUnreadDerivedFromCurrentChannels()
    }

    private func postClanSidebarUnreadDerivedFromCurrentChannels() {
        guard clanId != 0 else { return }
        guard !allChannels.isEmpty else { return }
        let total = allChannels.reduce(Int32(0)) { $0 + $1.countMessUnread }
        NotificationCenter.default.post(
            name: Notification.Name("MezonClanChannelUnreadDerived"),
            object: nil,
            userInfo: ["clanId": clanId, "totalUnread": total]
        )
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
        rebuildAndReload()
    }

    private func setCategories(_ v: [ChannelCategory]) { categories = v; categoriesPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setSelectedChannelId(_ v: Int64?) { selectedChannelId = v; selectedChannelIdPipe.putNext(v) }
    private func setSelectedChannel(_ v: Mezon_Api_ChannelDescription?) { selectedChannel = v; selectedChannelPipe.putNext(v) }
    private func setIsLoading(_ v: Bool) {
        if !v { cancelDeferredSkeletonReveal() }
        isLoading = v
        isLoadingPipe.putNext(v)
        needsReloadPipe.putNext(())
    }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v) }

    private func scheduleDeferredSkeletonRevealIfStillEmpty() {
        let pendingClanId = clanId
        cancelDeferredSkeletonReveal()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.clanId == pendingClanId, self.clanId != 0 else { return }
            guard self.categories.isEmpty else { return }
            guard NetworkMonitor.shared.isConnected else { return }
            self.isLoading = true
            self.isLoadingPipe.putNext(true)
            self.needsReloadPipe.putNext(())
        }
        pendingSkeletonRevealItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + skeletonRevealDelay, execute: item)
    }

    private func cancelDeferredSkeletonReveal() {
        pendingSkeletonRevealItem?.cancel()
        pendingSkeletonRevealItem = nil
    }

    private func clearCurrentChannelSelection() {
        guard selectedChannelId != nil || selectedChannel != nil else { return }
        setSelectedChannelId(nil)
        setSelectedChannel(nil)
        if clanId != 0 {
            context.clearPersistedSelectedChannelPreference(forClanId: clanId)
        }
        needsReloadPipe.putNext(())
    }

    func load(clanId: Int64, clanName: String) {
        fetchDisposable.set(nil)
        self.clanId = clanId
        self.clanName = clanName
        self.showEmptyCategoriesEnabled = loadShowEmptyCategoriesPreference(clanId: clanId)
        channelsLoadedPromise.set(false)
        errorMessage = nil

        restoreSelectionFromPostboxForCurrentClanOnly()

        let pendingCache: (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?)? =
            clanId != 0 ? readChannelCachePayloadIfAvailable(clanId: clanId) : nil

        if clanId != 0, let cache = pendingCache {
            allChannels = cache.channels
            if let meta = cache.meta {
                channelListCategoryDescs = meta.categoryDescs
                channelListFavoriteIds = meta.favoriteIds
            } else {
                channelListCategoryDescs = []
                channelListFavoriteIds = []
            }
            if let blob = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListCategories(clanId: clanId)),
               let snap = decodeCategoriesSnapshot(blob),
               categoriesSnapshotConsistentWithChannels(snap, authoritative: cache.channels) {
                categories = mergeChannelProtosIntoCategoriesSnapshot(snap, authoritative: cache.channels)
                channelsLoadedPromise.set(true)
                categoriesPipe.putNext(categories)
                syncSelectedChannelFromStoredPreferences()
                refreshChannelAppsLabelsFromChannelList()
            } else {
                let storedCollapsed = loadCollapsedCategoryIds()
                let built = buildChannelCategories(
                    cache.channels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: storedCollapsed
                )
                categories = applyBuiltCategoriesPreservingCollapse(built)
                channelsLoadedPromise.set(true)
                categoriesPipe.putNext(categories)
                syncSelectedChannelFromStoredPreferences()
                refreshChannelAppsLabelsFromChannelList()
            }
        } else {
            channelListCategoryDescs = []
            channelListFavoriteIds = []
            allChannels = []
            categories = []
        }
        restoreCachedChannelApps(clanId: clanId)
        if clanId == 0 || !NetworkMonitor.shared.isConnected {
            channelListNode.setChannelAppsLoadingIndicator(false)
        }
        isLoading = false
        if pendingCache == nil && clanId != 0 && NetworkMonitor.shared.isConnected {
            scheduleDeferredSkeletonRevealIfStillEmpty()
        } else {
            cancelDeferredSkeletonReveal()
        }
        needsReloadPipe.putNext(())
        if clanId != 0, !allChannels.isEmpty {
            postClanSidebarUnreadDerivedFromCurrentChannels()
        }

        if NetworkMonitor.shared.isConnected {
            fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
        }
    }

    private var inflightChannelFetchClanId: Int64 = 0
    private var lastChannelFetchAtByClanId: [Int64: Date] = [:]
    private let channelFetchCooldown: TimeInterval = 5.0

    private func fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: Bool = false) {
        guard clanId != 0 else {
            cancelDeferredSkeletonReveal()
            isLoading = false
            channelListNode.setChannelAppsLoadingIndicator(false)
            needsReloadPipe.putNext(())
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            cancelDeferredSkeletonReveal()
            isLoading = false
            isLoadingPipe.putNext(false)
            channelListNode.setChannelAppsLoadingIndicator(false)
            needsReloadPipe.putNext(())
            return
        }
        let clanId = self.clanId
        if inflightChannelFetchClanId == clanId { return }
        if let last = lastChannelFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < channelFetchCooldown {
            cancelDeferredSkeletonReveal()
            isLoading = false
            isLoadingPipe.putNext(false)
            channelListNode.setChannelAppsLoadingIndicator(false)
            needsReloadPipe.putNext(())
            return
        }
        inflightChannelFetchClanId = clanId
        lastChannelFetchAtByClanId[clanId] = Date()

        let signal = channelListSignal(clanId: clanId)
            |> map { payload -> FetchResult in .success(payload.channels, payload.categoryDescs, payload.favoriteChannelIds) }
            |> `catch` { (error: ChannelFetchError) -> Signal<FetchResult, NoError> in .single(.failure(error.localizedDescription)) }
            |> deliverOnMainQueue

        let allowEmptyApps = allowEmptyChannelAppsOverwrite
        let hadCachedChannels = !self.allChannels.isEmpty
        fetchDisposable.set(signal.start(next: { [weak self] result in
                guard let self else { return }
                guard self.isCurrentSessionAlive else {
                    self.clearInflightChannelFetchIfMatches(clanId: clanId)
                    return
                }
                guard self.clanId == clanId else {
                    self.clearInflightChannelFetchIfMatches(clanId: clanId)
                    return
                }
                self.cancelDeferredSkeletonReveal()
                self.isLoading = false
                switch result {
                case .success(let channels, let categoryDescs, let favoriteIds):
                    if channels.isEmpty && hadCachedChannels {
                        self.channelsLoadedPromise.set(true)
                        self.channelListNode.endRefreshing()
                        self.isLoadingPipe.putNext(false)
                        self.fetchChannelApps(allowEmptyOverwrite: allowEmptyApps)
                        self.needsReloadPipe.putNext(())
                        Task { @MainActor [weak self] in
                            await self?.applyChannelBadgeCounts(clanId: clanId)
                        }
                        self.clearInflightChannelFetchIfMatches(clanId: clanId)
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.isCurrentSessionAlive else {
                            self.clearInflightChannelFetchIfMatches(clanId: clanId)
                            return
                        }
                        guard self.clanId == clanId else {
                            self.clearInflightChannelFetchIfMatches(clanId: clanId)
                            return
                        }
                        let merged = await self.fetchMergedChannelsWithBadgeCounts(base: channels, clanId: clanId)
                        self.channelListCategoryDescs = categoryDescs
                        self.channelListFavoriteIds = favoriteIds
                        self.allChannels = merged
                        let storedCollapsed = self.loadCollapsedCategoryIds()
                        let built = buildChannelCategories(
                            merged,
                            categoryDescs: categoryDescs,
                            favoriteChannelIds: favoriteIds,
                            collapsedIds: storedCollapsed
                        )
                        let cats = self.applyBuiltCategoriesPreservingCollapse(built)
                        self.categories = cats
                        self.channelsLoadedPromise.set(true)
                        self.syncSelectedChannelFromStoredPreferences()
                        self.categoriesPipe.putNext(cats)
                        self.fetchChannelApps(allowEmptyOverwrite: allowEmptyApps)
                        self.persistFullChannelListCache(
                            clanId: clanId,
                            channels: merged,
                            categoryDescs: categoryDescs,
                            favoriteIds: favoriteIds,
                            categories: cats
                        )
                        self.channelListNode.endRefreshing()
                        self.isLoadingPipe.putNext(false)
                        self.needsReloadPipe.putNext(())
                        self.postClanSidebarUnreadDerivedFromCurrentChannels()
                        self.clearInflightChannelFetchIfMatches(clanId: clanId)
                    }
                    return
                case .failure(let msg):
                    self.errorMessage = msg
                    self.errorMessagePipe.putNext(msg)
                    self.channelListNode.setChannelAppsLoadingIndicator(false)
                    if !self.allChannels.isEmpty {
                        self.channelsLoadedPromise.set(true)
                    }
                }
                self.channelListNode.endRefreshing()
                self.isLoadingPipe.putNext(false)
                self.needsReloadPipe.putNext(())
                self.clearInflightChannelFetchIfMatches(clanId: clanId)
            }))
    }

    private func clearInflightChannelFetchIfMatches(clanId: Int64) {
        if inflightChannelFetchClanId == clanId {
            inflightChannelFetchClanId = 0
        }
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
        if isCurrentSessionAlive {
            self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId), value: encodeChannelId(channel.channelID))
        }
        needsReloadPipe.putNext(())
    }

    private func handleChannelTap(_ channel: Mezon_Api_ChannelDescription) {
        if channel.type == MezonConstants.ChannelType.mezonVoice.rawValue {
            presentJoinVoiceSheet(for: channel)
            return
        }
        select(channel: channel)
    }

    private func presentationWindowHostForChannelApp() -> WindowHost? {
        if let w = window { return w }
        if let nav = navigationController as? NavigationController, let cw = nav.currentWindow {
            return cw
        }
        return view.windowHost
    }

    private func navigationControllerForChannelAppGlobalOverlay() -> NavigationController? {
        if let nav = navigationController as? NavigationController { return nav }
        if let root = view.window?.rootViewController {
            return root.mezon_findDeepestNavigationController()
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for w in scene.windows where !w.isHidden {
            if let nav = w.rootViewController?.mezon_findDeepestNavigationController() { return nav }
        }
        return nil
    }

    private func openChannelApp(_ app: Mezon_Api_ChannelAppResponse) {
        guard app.appID != 0, !app.appURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Toast.error("App unavailable")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error("Session unavailable")
                return
            }
            do {
                let webAppData = try await self.context.account.network.generateChannelAppHash(appId: app.appID, token: token)
                guard !webAppData.isEmpty else {
                    Toast.error("App unavailable")
                    return
                }
                guard let url = app.channelAppWebPageURL(webAppData: webAppData) else {
                    Toast.error("App unavailable")
                    return
                }
                let title = app.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                let vc = ChannelAppWebViewController(
                    pageURL: url,
                    appTitle: title.isEmpty ? "App" : title)
                let navForOverlay = self.navigationControllerForChannelAppGlobalOverlay()
                if let nav = navForOverlay {
                    nav.presentOverlay(controller: vc, inGlobal: true)
                } else if let host = self.presentationWindowHostForChannelApp() {
                    host.presentInGlobalOverlay(vc)
                } else {
                    Toast.error("App unavailable")
                    return
                }
                DispatchQueue.main.async {
                    navForOverlay?.requestLayout(transition: .immediate)
                }
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func resolveVoiceMember(_ uid: String) -> VoiceMemberDisplay? {
        guard let uidInt = Int64(uid) else { return nil }

        let profile = context.account.postbox.read { $0.getProfile(userId: uid) }

        let member = context.account.postbox.read {
            $0.getClanMembers(clanId: self.clanId)
        }.first(where: { $0.userId == uidInt })

        let name: String
        let username: String
        if let m = member {
            if !m.clanNick.isEmpty {
                name = m.clanNick
            } else if !m.displayName.isEmpty {
                name = m.displayName
            } else if !m.username.isEmpty {
                name = m.username
            } else {
                return nil
            }
            username = m.username
        } else if let profile {
            name = (profile.displayName?.isEmpty == false ? profile.displayName : nil) ?? profile.username
            username = profile.username
        } else {
            return nil
        }

        let avatar: String?
        if let m = member {
            avatar = m.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl)
        } else {
            avatar = profile?.avatarUrl.flatMap { $0.isEmpty ? nil : $0 }
        }

        return VoiceMemberDisplay(name: name, username: username, avatarURL: avatar)
    }

    private func presentJoinVoiceSheet(for channel: Mezon_Api_ChannelDescription) {
        let title = channel.channelLabel.isEmpty
            ? NSLocalizedString("voiceChannel.defaultName", tableName: nil, bundle: .main, value: "Voice", comment: "")
            : channel.channelLabel

        var voiceUserIds: [String] = []
        let sources: [Mezon_Api_VoiceChannelUserList?] = [
            context.engine.clanData.getVoiceUsers(clanId: clanId),
            context.engine.clanData.getStreamUsers(clanId: clanId),
        ]
        for list in sources.compactMap({ $0 }) {
            for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !voiceUserIds.contains(uid) {
                    voiceUserIds.append(uid)
                }
            }
        }
        let resolvedMembers = voiceUserIds.compactMap { resolveVoiceMember($0) }

        let sheet = JoinVoiceChannelSheetViewController(
            channelTitle: title,
            chatUnreadCount: Int(channel.countMessUnread),
            members: resolvedMembers,
            onChat: { [weak self] in self?.pushChatViewController(for: channel) },
            onJoinVoice: { [weak self] in self?.pushVoiceChannelRoom(for: channel) },
            onInvite: {}
        )
        sheet.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            sheet.sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = JoinVoiceChannelSheetViewController.preferredSheetHeight(
                    safeAreaBottomInset: bottomInset, hasMembers: !resolvedMembers.isEmpty)
                let detentId = JoinVoiceChannelSheetViewController.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { context in
                    min(targetHeight, context.maximumDetentValue)
                }
                sheet.sheetPresentationController?.detents = [contentDetent]
                sheet.sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheet.sheetPresentationController?.detents = [.medium(), .large()]
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        present(sheet, animated: true)
        CATransaction.commit()
    }

    private func pushChatViewController(for channel: Mezon_Api_ChannelDescription) {
        select(channel: channel)
        guard let nav = enclosingNavigationController else { return }
        var parentName: String?
        if channel.parentID != 0 {
            parentName = allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: clanId, channel: channel, context: context, parentName: parentName)
        nav.pushViewController(
            chatVC, animated: true,
            stackPushAnimationDuration: NavigationController.channelListToChatPushAnimationDuration)
    }

    private func pushVoiceChannelRoom(for channel: Mezon_Api_ChannelDescription) {
        select(channel: channel)
        guard let nav = enclosingNavigationController else { return }

        let pip = VoiceChannelPiPOverlay.shared
        if pip.isActive {
            if pip.channel?.channelID == channel.channelID {
                let vc = VoiceChannelRoomViewController(
                    context: context, channel: channel,
                    parentChannelName: parentChannelName(for: channel),
                    voiceChannelCrossClanExitAlignClanId: pip.crossClanVoiceExitAlignClanId,
                    existingPiPOverlay: pip)
                nav.pushViewController(vc, animated: true)
                return
            } else {
                pip.dismiss()
            }
        }

        let vc = VoiceChannelRoomViewController(
            context: context, channel: channel,
            parentChannelName: parentChannelName(for: channel))
        nav.pushViewController(vc, animated: true)
    }

    private func parentChannelName(for channel: Mezon_Api_ChannelDescription) -> String? {
        guard channel.parentID != 0 else { return nil }
        return allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
    }

    func selectWithoutNavigation(channelId: Int64) {
        setSelectedChannelId(channelId)
        if let ch = allChannels.first(where: { $0.channelID == channelId }) {
            selectedChannel = ch
        }
        if isCurrentSessionAlive {
            context.account.postbox.setPreferenceData(
                key: PreferencesKeys.selectedChannelId(clanId: clanId),
                value: encodeChannelId(channelId)
            )
        }

        needsReloadPipe.putNext(())
    }

    func updateChannels(_ channels: [Mezon_Api_ChannelDescription]) {
        allChannels = channels
        let storedCollapsed = loadCollapsedCategoryIds()
        let built = buildChannelCategories(
            channels,
            categoryDescs: channelListCategoryDescs,
            favoriteChannelIds: channelListFavoriteIds,
            collapsedIds: storedCollapsed
        )
        let cats = applyBuiltCategoriesPreservingCollapse(built)
        categories = cats
        channelsLoadedPromise.set(true)
        categoriesPipe.putNext(cats)
        needsReloadPipe.putNext(())
        postClanSidebarUnreadDerivedFromCurrentChannels()
    }

    private(set) var allChannels: [Mezon_Api_ChannelDescription] = []

    var currentState: ChannelListState {
        var voiceMap: [Int64: [String]] = [:]
        let sources: [Mezon_Api_VoiceChannelUserList?] = [
            context.engine.clanData.getVoiceUsers(clanId: clanId),
            context.engine.clanData.getStreamUsers(clanId: clanId),
        ]
        for list in sources.compactMap({ $0 }) {
            for vu in list.voiceChannelUsers {
                let filtered = vu.userIds.filter { !$0.isEmpty && Int64($0) != nil }
                if !filtered.isEmpty {
                    var existing = voiceMap[vu.channelID] ?? []
                    for uid in filtered where !existing.contains(uid) {
                        existing.append(uid)
                    }
                    voiceMap[vu.channelID] = existing
                }
            }
        }
        return ChannelListState(
            categories: displayedCategories,
            allChannels: allChannels,
            selectedChannelId: selectedChannelId,
            isLoading: isLoading,
            errorMessage: errorMessage,
            voiceUsersByChannel: voiceMap
        )
    }

    private var displayedCategories: [ChannelCategory] {
        guard !showEmptyCategoriesEnabled else { return categories }
        return categories.filter { cat in
            if let fav = cat.favoriteFlatChannels { return !fav.isEmpty }
            return !cat.channels.isEmpty
        }
    }

    private func setShowEmptyCategories(_ value: Bool) {
        guard clanId != 0 else { return }
        guard value != showEmptyCategoriesEnabled else { return }
        showEmptyCategoriesEnabled = value
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.showEmptyCategories(clanId: clanId),
            value: Data([UInt8(value ? 1 : 0)])
        )
        needsReloadPipe.putNext(())
    }

    private func loadShowEmptyCategoriesPreference(clanId: Int64) -> Bool {
        guard clanId != 0,
              let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.showEmptyCategories(clanId: clanId)),
              let first = data.first else { return false }
        return first != 0
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

                guard newState != lastEmitted else { return }
                lastEmitted = newState
                subscriber.putNext(newState)
            })
        }
    }

    private struct ChannelListFetchPayload {
        let channels: [Mezon_Api_ChannelDescription]
        let categoryDescs: [Mezon_Api_CategoryDesc]
        let favoriteChannelIds: Set<Int64>
    }

    private func channelListSignal(clanId: Int64) -> Signal<ChannelListFetchPayload, ChannelFetchError> {
        let context = self.context
        return Signal { subscriber in
            let task = Task {
                let startEpoch = await MainActor.run { context.sessionEpoch }
                let token = await Task { @MainActor in
                    await context.getTokenPreferringCachedSkipSessionReadyWait()
                }.value
                guard let token else {
                    await MainActor.run {
                        guard context.isStillCurrentSession(epoch: startEpoch) else {
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putError(.noSession)
                    }
                    return
                }
                let network = MezonHTTPClient.shared
                do {
                    async let channelsTask = network.listChannelDescs(clanId: clanId, token: token)
                    async let categoriesTask = Self.listCategoryDescsOrEmpty(network: network, clanId: clanId, token: token)
                    async let favoritesTask = Self.listFavoriteChannelIdsOrEmpty(network: network, clanId: clanId, token: token)
                    let channels = try await channelsTask
                    let categoryDescs = await categoriesTask
                    let favoriteIds = Set(await favoritesTask)
                    let payload = ChannelListFetchPayload(
                        channels: channels,
                        categoryDescs: categoryDescs,
                        favoriteChannelIds: favoriteIds
                    )
                    await MainActor.run {
                        guard context.isStillCurrentSession(epoch: startEpoch) else {
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putNext(payload)
                        subscriber.putCompletion()
                    }
                } catch {
                    await MainActor.run {
                        guard context.isStillCurrentSession(epoch: startEpoch) else {
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putError(.network(error))
                    }
                }
            }
            return ActionDisposable { task.cancel() }
        }
    }

    nonisolated private static func listCategoryDescsOrEmpty(network: MezonHTTPClient, clanId: Int64, token: String) async -> [Mezon_Api_CategoryDesc] {
        do {
            return try await network.listCategoryDescs(clanId: clanId, token: token)
        } catch {
            return []
        }
    }

    nonisolated private static func listFavoriteChannelIdsOrEmpty(network: MezonHTTPClient, clanId: Int64, token: String) async -> [Int64] {
        do {
            return try await network.listFavoriteChannelIds(clanId: clanId, token: token)
        } catch {
            return []
        }
    }

    private func restoreSelectionFromPostboxForCurrentClanOnly() {
        guard clanId != 0 else {
            setSelectedChannelId(nil)
            setSelectedChannel(nil)
            return
        }
        setSelectedChannel(nil)
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId)), data.count >= 8 {
            let id = data.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
            setSelectedChannelId(id)
        } else {
            setSelectedChannelId(nil)
        }
    }

    private func reconcileSelectionWithLoadedChannels() {
        guard !allChannels.isEmpty else { return }
        guard let sid = selectedChannelId, sid != 0 else { return }
        if !allChannels.contains(where: { $0.channelID == sid }) {
            setSelectedChannelId(nil)
            setSelectedChannel(nil)
        }
    }

    private func syncSelectedChannelFromStoredPreferences() {
        restoreSelectionFromPostboxForCurrentClanOnly()
        reconcileSelectionWithLoadedChannels()
    }

    private func encodeChannelId(_ id: Int64) -> Data {
        var le = id.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    private func cachedChannelAppsMatchClan(_ apps: [Mezon_Api_ChannelAppResponse], clanId: Int64) -> Bool {
        for a in apps where a.clanID != 0 && a.clanID != clanId {
            return false
        }
        return true
    }

    private func fetchChannelApps(allowEmptyOverwrite _: Bool = false) {
        guard clanId != 0 else { return }
        let clanId = self.clanId
        Task { @MainActor [weak self] in
            defer {
                if let self, self.clanId == clanId {
                    self.channelListNode.setChannelAppsLoadingIndicator(false)
                }
            }
            guard let self else { return }
            let startEpoch = self.context.sessionEpoch
            guard let token = await self.resolveAuthTokenPreferringUnexpiredSessionStore() else { return }
            guard self.context.isStillCurrentSession(epoch: startEpoch) else { return }
            guard self.clanId == clanId else { return }

            let key = PreferencesKeys.channelApps(clanId: clanId)
            let cachedData = self.context.account.postbox.getPreferenceData(key: key)

            do {
                let apps = try await Task.detached(priority: .utility) {
                    try await MezonHTTPClient.shared.listChannelApps(clanId: clanId, token: token)
                }.value
                guard self.context.isStillCurrentSession(epoch: startEpoch) else { return }
                guard self.clanId == clanId else { return }
                let hasNonEmptyCache: Bool = {
                    guard let cachedData, !cachedData.isEmpty else { return false }
                    return !self.decodeChannelApps(cachedData).isEmpty
                }()
                if apps.isEmpty && hasNonEmptyCache {
                    return
                }
                self.channelListNode.updateChannelApps(apps)
                let encoded = self.encodeChannelApps(apps)
                if cachedData != encoded {
                    self.context.account.postbox.setPreferenceDataSync(key: key, value: encoded)
                }
            } catch {
            }
        }
    }

    private func restoreCachedChannelApps(clanId: Int64) {
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else {
            if !channelListNode.hasDisplayedChannelApps {
                channelListNode.updateChannelApps([])
            }
            return
        }
        let apps = decodeChannelApps(data)
        if apps.isEmpty {
            if !channelListNode.hasDisplayedChannelApps {
                channelListNode.updateChannelApps([])
            }
            return
        }
        guard cachedChannelAppsMatchClan(apps, clanId: clanId) else {
            channelListNode.updateChannelApps([])
            return
        }
        channelListNode.updateChannelApps(apps)
    }

    private func refreshChannelAppsLabelsFromChannelList() {
        guard clanId != 0 else { return }
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else { return }
        let apps = decodeChannelApps(data)
        if apps.isEmpty { return }
        channelListNode.updateChannelApps(apps)
    }

    private func encodeChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) -> Data {
        var r = Mezon_Api_ListChannelAppsResponse()
        r.channelApps = apps
        return (try? r.serializedData()) ?? Data()
    }

    private func decodeChannelApps(_ data: Data) -> [Mezon_Api_ChannelAppResponse] {
        if data.isEmpty { return [] }
        do {
            return try Mezon_Api_ListChannelAppsResponse(serializedBytes: data).channelApps
        } catch {
            return decodeChannelAppsLegacy(data)
        }
    }

    private func decodeChannelAppsLegacy(_ data: Data) -> [Mezon_Api_ChannelAppResponse] {
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

    private func persistFavoriteChannelIds(_ ids: Set<Int64>, clanId: Int64) {
        guard isCurrentSessionAlive else { return }
        var resp = Mezon_Api_ListFavoriteChannelResponse()
        resp.channelIds = Array(ids)
        if let data = try? resp.serializedData() {
            context.account.postbox.setPreferenceDataSync(key: PreferencesKeys.favoriteChannelIds(clanId: clanId), value: data)
        }
    }

    private func resolvedFavoriteChannelIds(clanId: Int64, meta: ChannelListCachedMeta?) -> Set<Int64> {
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.favoriteChannelIds(clanId: clanId)),
           let r = try? Mezon_Api_ListFavoriteChannelResponse(serializedBytes: data) {
            return Set(r.channelIds)
        }
        return meta?.favoriteIds ?? []
    }

    private func cachedChannelsMatchClan(_ channels: [Mezon_Api_ChannelDescription], clanId: Int64) -> Bool {
        for ch in channels where ch.clanID != 0 && ch.clanID != clanId {
            return false
        }
        return true
    }

    private func readChannelCachePayloadIfAvailable(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?)? {
        if let strict = readValidatedChannelCache(clanId: clanId) { return strict }
        return readChannelCacheLenient(clanId: clanId)
    }

    private func readValidatedChannelCache(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?)? {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { return nil }
        let channels = decodeChannelList(data)
        guard !channels.isEmpty, cachedChannelsMatchClan(channels, clanId: clanId) else { return nil }
        return channelListMetaAndChannels(channels: channels, clanId: clanId)
    }

    private func readChannelCacheLenient(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?)? {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { return nil }
        let raw = decodeChannelList(data)
        guard !raw.isEmpty else { return nil }
        let channels = raw.filter { $0.clanID == 0 || $0.clanID == clanId }
        guard !channels.isEmpty else { return nil }
        return channelListMetaAndChannels(channels: channels, clanId: clanId)
    }

    private func channelListMetaAndChannels(
        channels: [Mezon_Api_ChannelDescription],
        clanId: Int64
    ) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?) {
        let metaFromBlob: ChannelListCachedMeta?
        if let metaData = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListMeta(clanId: clanId)),
           let m = ChannelListMetaCodec.decode(metaData) {
            metaFromBlob = m
        } else {
            metaFromBlob = nil
        }
        let favIds = resolvedFavoriteChannelIds(clanId: clanId, meta: metaFromBlob)
        let merged = ChannelListCachedMeta(
            categoryDescs: metaFromBlob?.categoryDescs ?? [],
            favoriteIds: favIds
        )
        return (channels, merged)
    }

    private func resolveAuthTokenPreferringUnexpiredSessionStore() async -> String? {
        await context.getTokenPreferringCachedSkipSessionReadyWait()
    }

    private func applyChannelCachePayload(channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?) {
        allChannels = channels
        if let meta {
            channelListCategoryDescs = meta.categoryDescs
            channelListFavoriteIds = meta.favoriteIds
        } else {
            channelListCategoryDescs = []
            channelListFavoriteIds = []
        }
        let storedCollapsed = loadCollapsedCategoryIds()
        let built = buildChannelCategories(
            channels,
            categoryDescs: channelListCategoryDescs,
            favoriteChannelIds: channelListFavoriteIds,
            collapsedIds: storedCollapsed
        )
        categories = applyBuiltCategoriesPreservingCollapse(built)
        channelsLoadedPromise.set(true)
        categoriesPipe.putNext(categories)
        syncSelectedChannelFromStoredPreferences()
        refreshChannelAppsLabelsFromChannelList()
        postClanSidebarUnreadDerivedFromCurrentChannels()
    }



    private func persistFullChannelListCache(
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>,
        categories: [ChannelCategory]
    ) {
        guard isCurrentSessionAlive else { return }
        guard clanId != 0 else { return }
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelList(clanId: clanId),
            value: encodeChannelList(channels)
        )
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelListMeta(clanId: clanId),
            value: ChannelListMetaCodec.encode(categoryDescs: categoryDescs, favoriteIds: favoriteIds)
        )
        persistFavoriteChannelIds(favoriteIds, clanId: clanId)
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelListCategories(clanId: clanId),
            value: encodeCategoriesSnapshot(categories)
        )
    }

    private func encodeCategoriesSnapshot(_ cats: [ChannelCategory]) -> Data {
        var d = Data()
        var ver: UInt32 = 1
        d.append(contentsOf: withUnsafeBytes(of: &ver) { Array($0) })
        var n = UInt32(cats.count)
        d.append(contentsOf: withUnsafeBytes(of: &n) { Array($0) })
        for cat in cats {
            var idLe = cat.id.littleEndian
            d.append(contentsOf: withUnsafeBytes(of: &idLe) { Array($0) })
            d.append(cat.isCollapsed ? 1 : 0)
            let nameD = Data(cat.name.utf8)
            var nl = UInt32(nameD.count)
            d.append(contentsOf: withUnsafeBytes(of: &nl) { Array($0) })
            d.append(nameD)
            let fav = cat.favoriteFlatChannels
            var favCount = UInt32(fav?.count ?? 0)
            d.append(contentsOf: withUnsafeBytes(of: &favCount) { Array($0) })
            if let fav {
                for ch in fav {
                    guard let sd = try? ch.serializedData() else { continue }
                    var len = UInt32(sd.count)
                    d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                    d.append(sd)
                }
            }
            var pCount = UInt32(cat.channels.count)
            d.append(contentsOf: withUnsafeBytes(of: &pCount) { Array($0) })
            for ch in cat.channels {
                guard let sd = try? ch.serializedData() else { continue }
                var len = UInt32(sd.count)
                d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                d.append(sd)
            }
            let keys = cat.orderedThreadChildren.keys.sorted()
            var mapCount = UInt32(keys.count)
            d.append(contentsOf: withUnsafeBytes(of: &mapCount) { Array($0) })
            for pk in keys {
                guard let threads = cat.orderedThreadChildren[pk] else { continue }
                var pkLe = pk.littleEndian
                d.append(contentsOf: withUnsafeBytes(of: &pkLe) { Array($0) })
                var tc = UInt32(threads.count)
                d.append(contentsOf: withUnsafeBytes(of: &tc) { Array($0) })
                for t in threads {
                    guard let sd = try? t.serializedData() else { continue }
                    var len = UInt32(sd.count)
                    d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                    d.append(sd)
                }
            }
        }
        return d
    }

    private func decodeCategoriesSnapshot(_ data: Data) -> [ChannelCategory]? {
        guard data.count >= 8 else { return nil }
        var o = 0
        let ver = data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        o += 4
        guard ver == 1 else { return nil }
        let count = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
        o += 4
        guard count >= 0, count < 512 else { return nil }
        var out: [ChannelCategory] = []
        for _ in 0..<count {
            guard o + 9 <= data.count else { return nil }
            let id = data.subdata(in: o..<(o + 8)).withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
            o += 8
            let collapsed = data[o] != 0
            o += 1
            guard o + 4 <= data.count else { return nil }
            let nl = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
            o += 4
            guard o + nl <= data.count else { return nil }
            let name = String(data: data.subdata(in: o..<(o + nl)), encoding: .utf8) ?? ""
            o += nl
            guard o + 4 <= data.count else { return nil }
            let favc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
            o += 4
            var favFlat: [Mezon_Api_ChannelDescription]? = nil
            if favc > 0 {
                var fa: [Mezon_Api_ChannelDescription] = []
                for _ in 0..<favc {
                    guard o + 4 <= data.count else { return nil }
                    let len = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
                    o += 4
                    guard o + len <= data.count, len > 0 else { return nil }
                    if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: o..<(o + len))) {
                        fa.append(ch)
                    }
                    o += len
                }
                favFlat = fa
            }
            guard o + 4 <= data.count else { return nil }
            let pc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
            o += 4
            var parents: [Mezon_Api_ChannelDescription] = []
            for _ in 0..<pc {
                guard o + 4 <= data.count else { return nil }
                let len = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
                o += 4
                guard o + len <= data.count, len > 0 else { return nil }
                if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: o..<(o + len))) {
                    parents.append(ch)
                }
                o += len
            }
            guard o + 4 <= data.count else { return nil }
            let mc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
            o += 4
            var threadsMap: [Int64: [Mezon_Api_ChannelDescription]] = [:]
            for _ in 0..<mc {
                guard o + 8 <= data.count else { return nil }
                let pk = data.subdata(in: o..<(o + 8)).withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
                o += 8
                guard o + 4 <= data.count else { return nil }
                let tc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
                o += 4
                var tarr: [Mezon_Api_ChannelDescription] = []
                for _ in 0..<tc {
                    guard o + 4 <= data.count else { return nil }
                    let len = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
                    o += 4
                    guard o + len <= data.count, len > 0 else { return nil }
                    if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: o..<(o + len))) {
                        tarr.append(ch)
                    }
                    o += len
                }
                threadsMap[pk] = tarr
            }
            out.append(ChannelCategory(
                id: id,
                name: name,
                isCollapsed: collapsed,
                channels: parents,
                orderedThreadChildren: threadsMap,
                favoriteFlatChannels: favFlat
            ))
        }
        guard o == data.count else { return nil }
        return out
    }

    private func categoriesSnapshotConsistentWithChannels(
        _ cats: [ChannelCategory],
        authoritative: [Mezon_Api_ChannelDescription]
    ) -> Bool {
        let allowed = Set(authoritative.map(\.channelID))
        var presentTopLevel = Set<Int64>()
        for cat in cats {
            if let fav = cat.favoriteFlatChannels {
                for ch in fav where !allowed.contains(ch.channelID) { return false }
            }
            for ch in cat.channels {
                if !allowed.contains(ch.channelID) { return false }
                presentTopLevel.insert(ch.channelID)
            }
            for (_, arr) in cat.orderedThreadChildren {
                for ch in arr where !allowed.contains(ch.channelID) { return false }
            }
        }
        let requiredTopLevel = Set(authoritative.filter { $0.parentID == 0 }.map(\.channelID))
        return requiredTopLevel.isSubset(of: presentTopLevel)
    }

    private func mergeChannelProtosIntoCategoriesSnapshot(
        _ cats: [ChannelCategory],
        authoritative: [Mezon_Api_ChannelDescription]
    ) -> [ChannelCategory] {
        let byId = Dictionary(uniqueKeysWithValues: authoritative.map { ($0.channelID, $0) })
        func mergeOne(_ ch: Mezon_Api_ChannelDescription) -> Mezon_Api_ChannelDescription {
            byId[ch.channelID] ?? ch
        }
        return cats.map { cat in
            let mergedFav = cat.favoriteFlatChannels?.map(mergeOne)
            let mergedParents = cat.channels.map(mergeOne)
            var newThreads: [Int64: [Mezon_Api_ChannelDescription]] = [:]
            for (k, arr) in cat.orderedThreadChildren {
                newThreads[k] = arr.map(mergeOne)
            }
            return ChannelCategory(
                id: cat.id,
                name: cat.name,
                isCollapsed: cat.isCollapsed,
                channels: mergedParents,
                orderedThreadChildren: newThreads,
                favoriteFlatChannels: mergedFav
            )
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
        guard isCurrentSessionAlive else { return }
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

private extension UIViewController {
    func mezon_findDeepestNavigationController() -> NavigationController? {
        if let nav = self as? NavigationController {
            if let tab = nav.topViewController as? TabBarController,
               let current = tab.currentController {
                return current.mezon_findDeepestNavigationController() ?? nav
            }
            return nav
        }
        if let tab = self as? TabBarController, let current = tab.currentController {
            return current.mezon_findDeepestNavigationController()
        }
        if let tab = self as? UITabBarController, let sel = tab.selectedViewController {
            return sel.mezon_findDeepestNavigationController()
        }
        if let presented = presentedViewController {
            if let nav = presented.mezon_findDeepestNavigationController() { return nav }
        }
        for child in children {
            if let nav = child.mezon_findDeepestNavigationController() { return nav }
        }
        return nil
    }
}
