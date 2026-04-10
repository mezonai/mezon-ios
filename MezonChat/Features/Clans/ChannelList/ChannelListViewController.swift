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

    static let empty = ChannelListState(categories: [], allChannels: [], selectedChannelId: nil, isLoading: false, errorMessage: nil)

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
    let useCategories = categoryDescs.isEmpty ? inferredCategoryDescs(from: channels) : categoryDescs

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
    private let fetchDisposable = MetaDisposable()
    private let dataDisposable = MetaDisposable()
    private var processedBadgeKeys = Set<String>()

    deinit {
        fetchDisposable.dispose()
        dataDisposable.dispose()
        NotificationCenter.default.removeObserver(self, name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("MezonJoinedClanChatForBadges"), object: nil)
        NotificationCenter.default.removeObserver(self, name: .mezonVoicePresenceChanged, object: nil)
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
            onSearchTapped: { [weak self] in self?.searchTappedPipe.putNext(()) },
            onQRTapped: { [weak self] in
                guard let self else { return }
                let vc = QRScannerViewController(context: self.context)
                self.enclosingNavigationController?.pushViewController(vc, animated: true)
            }
        )
        let container = ChannelListContainerNode(signal: stateSignal(), interaction: interaction)
        container.voiceMemberResolver = { [weak self] uid in
            self?.resolveVoiceMember(uid)
        }
        displayNode = container
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoicePresenceChanged(_:)), name: .mezonVoicePresenceChanged, object: nil)
    }

    @objc private func handleVoicePresenceChanged(_ notification: Notification) {
        guard let n = notification.userInfo?["clanId"] as? NSNumber else { return }
        guard n.int64Value == clanId, clanId != 0 else { return }
        needsReloadPipe.putNext(())
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

    @MainActor
    private func applyChannelBadgeCounts(clanId: Int64) async {
        guard clanId != 0 else { return }
        guard let token = await context.getToken() else { return }
        do {
            let rows = try await context.account.network.listChannelBadgeCount(clanId: clanId, token: token)
                .channeldesc
            guard !rows.isEmpty else { return }
            var updated = allChannels
            ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &updated, badgeRows: rows)
            guard !channelListRowsVisuallyEqual(allChannels, updated) else { return }
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
        restoreCachedChannelApps(clanId: clanId)
        channelListNode.configure(clanName: clanName, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, onlineCount: onlineCount, isCommunity: isCommunity)
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
                    break
                default:
                    break
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
        self.enclosingNavigationController?.pushViewController(vc, animated: true)
    }

    func refresh() { fetchChannels() }

    func fetchChannels() {
        guard clanId != 0 else { return }
        isLoading = true
        errorMessage = nil

        needsReloadPipe.putNext(())
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
        if ActiveChannelTracker.currentChannelId == channelId { return }

        let topicId: Int64 = {
            if let t = notification.userInfo?["topicId"] as? Int64 { return t }
            if let t = notification.userInfo?["topicId"] as? Int { return Int64(t) }
            return 0
        }()

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
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v) }

    func load(clanId: Int64, clanName: String) {
        self.clanId = clanId
        self.clanName = clanName
        channelsLoadedPromise.set(false)
        errorMessage = nil
        channelListCategoryDescs = []
        channelListFavoriteIds = []
        allChannels = []
        categories = []

        let hadCache = restoreCachedChannels(clanId: clanId)
        isLoading = !hadCache
        if !hadCache {
            needsReloadPipe.putNext(())
        }

        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
    }

    private func fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: Bool = false) {
        guard clanId != 0 else {
            isLoading = false
            needsReloadPipe.putNext(())
            return
        }
        let clanId = self.clanId

        let signal = channelListSignal(clanId: clanId)
            |> map { payload -> FetchResult in .success(payload.channels, payload.categoryDescs, payload.favoriteChannelIds) }
            |> `catch` { (error: ChannelFetchError) -> Signal<FetchResult, NoError> in .single(.failure(error.localizedDescription)) }
            |> deliverOnMainQueue

        let allowEmptyApps = allowEmptyChannelAppsOverwrite
        fetchDisposable.set(signal.start(next: { [weak self] result in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let channels, let categoryDescs, let favoriteIds):
                    self.channelListCategoryDescs = categoryDescs
                    self.channelListFavoriteIds = favoriteIds
                    self.allChannels = channels
                    let storedCollapsed = self.loadCollapsedCategoryIds()
                    let built = buildChannelCategories(
                        channels,
                        categoryDescs: categoryDescs,
                        favoriteChannelIds: favoriteIds,
                        collapsedIds: storedCollapsed
                    )
                    let cats = self.applyBuiltCategoriesPreservingCollapse(built)
                    self.categories = cats
                    self.channelsLoadedPromise.set(true)
                    self.persistSelectedChannel()
                    self.categoriesPipe.putNext(cats)
                    self.fetchChannelApps(allowEmptyOverwrite: allowEmptyApps)
                    self.context.account.postbox.setPreferenceData(
                        key: PreferencesKeys.channelList(clanId: clanId),
                        value: self.encodeChannelList(channels)
                    )
                    self.context.account.postbox.setPreferenceData(
                        key: PreferencesKeys.channelListMeta(clanId: clanId),
                        value: self.encodeChannelListMeta(categoryDescs: categoryDescs, favoriteIds: favoriteIds)
                    )
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
        needsReloadPipe.putNext(())
    }

    private func handleChannelTap(_ channel: Mezon_Api_ChannelDescription) {
        if channel.type == MezonConstants.ChannelType.mezonVoice.rawValue {
            presentJoinVoiceSheet(for: channel)
            return
        }
        select(channel: channel)
    }

    private func resolveVoiceMember(_ uid: String) -> VoiceMemberDisplay? {
        guard let uidInt = Int64(uid) else { return nil }

        let member = context.account.postbox.read {
            $0.getClanMembers(clanId: self.clanId)
        }.first(where: { $0.userId == uidInt })

        let name: String
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
        } else if let profile = context.account.postbox.read({ $0.getProfile(userId: uid) }) {
            name = profile.displayName ?? profile.username
        } else {
            return nil
        }

        let avatar: String?
        if let m = member {
            if !m.clanAvatar.isEmpty {
                avatar = m.clanAvatar
            } else {
                avatar = context.account.postbox.read({ $0.getProfile(userId: uid) })?.avatarUrl
            }
        } else {
            avatar = context.account.postbox.read({ $0.getProfile(userId: uid) })?.avatarUrl
        }

        return VoiceMemberDisplay(name: name, avatarURL: avatar)
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
        nav.pushViewController(chatVC, animated: true)
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
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.selectedChannelId(clanId: clanId),
            value: encodeChannelId(channelId)
        )

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
            categories: categories,
            allChannels: allChannels,
            selectedChannelId: selectedChannelId,
            isLoading: isLoading,
            errorMessage: errorMessage,
            voiceUsersByChannel: voiceMap
        )
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
            let task = Task { @MainActor in
                guard let token = await context.getToken() else { subscriber.putError(.noSession); return }
                do {
                    async let channelsTask = context.account.network.listChannelDescs(clanId: clanId, token: token)
                    async let categoriesTask = Self.listCategoryDescsOrEmpty(network: context.account.network, clanId: clanId, token: token)
                    async let favoritesTask = Self.listFavoriteChannelIdsOrEmpty(network: context.account.network, clanId: clanId, token: token)
                    let channels = try await channelsTask
                    let categoryDescs = await categoriesTask
                    let favoriteIds = Set(await favoritesTask)
                    var mergedChannels = channels
                    do {
                        let rows = try await context.account.network.listChannelBadgeCount(clanId: clanId, token: token)
                            .channeldesc
                        if !rows.isEmpty {
                            ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &mergedChannels, badgeRows: rows)
                        }
                    } catch {
                        AppLogger.network.debug("[ChannelList] ListChannelBadgeCount (batched with list): \(error)")
                    }
                    subscriber.putNext(ChannelListFetchPayload(
                        channels: mergedChannels,
                        categoryDescs: categoryDescs,
                        favoriteChannelIds: favoriteIds
                    ))
                    subscriber.putCompletion()
                } catch { subscriber.putError(.network(error)) }
            }
            return ActionDisposable { task.cancel() }
        }
    }

    private static func listCategoryDescsOrEmpty(network: MezonHTTPClient, clanId: Int64, token: String) async -> [Mezon_Api_CategoryDesc] {
        do {
            return try await network.listCategoryDescs(clanId: clanId, token: token)
        } catch {
            AppLogger.network.debug("[ChannelList] ListCategoryDescs: \(error)")
            return []
        }
    }

    private static func listFavoriteChannelIdsOrEmpty(network: MezonHTTPClient, clanId: Int64, token: String) async -> [Int64] {
        do {
            return try await network.listFavoriteChannelIds(clanId: clanId, token: token)
        } catch {
            AppLogger.network.debug("[ChannelList] GetListFavoriteChannel: \(error)")
            return []
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

    private func fetchChannelApps(allowEmptyOverwrite: Bool = false) {
        guard clanId != 0 else { return }
        let clanId = self.clanId
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            do {
                let apps = try await self.context.account.network.listChannelApps(clanId: clanId, token: token)
                guard self.clanId == clanId else { return }
                let key = PreferencesKeys.channelApps(clanId: clanId)
                if apps.isEmpty, !allowEmptyOverwrite {
                    if self.channelListNode.hasDisplayedChannelApps { return }
                    if let data = self.context.account.postbox.getPreferenceData(key: key),
                       !self.decodeChannelApps(data).isEmpty {
                        return
                    }
                }
                self.channelListNode.updateChannelApps(apps)
                let encoded = self.encodeChannelApps(apps)
                if self.context.account.postbox.getPreferenceData(key: key) != encoded {
                    self.context.account.postbox.setPreferenceData(key: key, value: encoded)
                }
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
        if let metaData = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListMeta(clanId: clanId)),
           let meta = decodeChannelListMeta(metaData)
        {
            channelListCategoryDescs = meta.categoryDescs
            channelListFavoriteIds = meta.favoriteIds
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
        persistSelectedChannel()
        needsReloadPipe.putNext(())
        return true
    }

    private struct ChannelListCachedMeta {
        var categoryDescs: [Mezon_Api_CategoryDesc]
        var favoriteIds: Set<Int64>
    }

    private func encodeChannelListMeta(categoryDescs: [Mezon_Api_CategoryDesc], favoriteIds: Set<Int64>) -> Data {
        var d = Data()
        var version: UInt32 = 1
        d.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })
        let favSorted = favoriteIds.sorted()
        var favCount = UInt32(favSorted.count)
        d.append(contentsOf: withUnsafeBytes(of: &favCount) { Array($0) })
        for id in favSorted {
            var le = id.littleEndian
            d.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }
        var catCount = UInt32(categoryDescs.count)
        d.append(contentsOf: withUnsafeBytes(of: &catCount) { Array($0) })
        for c in categoryDescs {
            guard let sd = try? c.serializedData() else { continue }
            var len = UInt32(sd.count)
            d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
            d.append(sd)
        }
        return d
    }

    private func decodeChannelListMeta(_ data: Data) -> ChannelListCachedMeta? {
        guard data.count >= 4 else { return nil }
        var offset = 0
        let version = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard version == 1 else { return nil }
        offset = 4
        guard offset + 4 <= data.count else { return nil }
        let favCount = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
        offset += 4
        var favs = Set<Int64>()
        for _ in 0..<favCount {
            guard offset + 8 <= data.count else { return nil }
            let id = data.subdata(in: offset..<(offset + 8)).withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
            favs.insert(id)
            offset += 8
        }
        guard offset + 4 <= data.count else { return ChannelListCachedMeta(categoryDescs: [], favoriteIds: favs) }
        let catCount = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
        offset += 4
        var cats: [Mezon_Api_CategoryDesc] = []
        for _ in 0..<catCount {
            guard offset + 4 <= data.count else { break }
            let len = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) })
            offset += 4
            guard offset + len <= data.count else { break }
            if let m = try? Mezon_Api_CategoryDesc(serializedBytes: data.subdata(in: offset..<(offset + len))) {
                cats.append(m)
            }
            offset += len
        }
        return ChannelListCachedMeta(categoryDescs: cats, favoriteIds: favs)
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
