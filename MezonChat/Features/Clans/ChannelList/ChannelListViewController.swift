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
        lhs.isLoading == rhs.isLoading
        && lhs.selectedChannelId == rhs.selectedChannelId
        && lhs.errorMessage == rhs.errorMessage
        && lhs.categories.count == rhs.categories.count
        && lhs.allChannels.count == rhs.allChannels.count
        && zip(lhs.categories, rhs.categories).allSatisfy { $0.id == $1.id && $0.isCollapsed == $1.isCollapsed && $0.channels.count == $1.channels.count }
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

private func buildChannelCategories(_ channels: [Mezon_Api_ChannelDescription]) -> [ChannelCategory] {
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
        return ChannelCategory(id: id, name: name, isCollapsed: false, channels: list)
    }
}

/// Pre-built thread lookup for O(1) access instead of O(n) filter per channel.
/// Call once per state change, reuse for all sections.
func buildThreadLookup(_ allChannels: [Mezon_Api_ChannelDescription]) -> [Int64: [Mezon_Api_ChannelDescription]] {
    var lookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    for ch in allChannels where ch.parentID != 0 {
        lookup[ch.parentID, default: []].append(ch)
    }
    // Sort each group once
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

    private let categoriesPipe = ValuePipe<[ChannelCategory]>()
    private let selectedChannelIdPipe = ValuePipe<Int64?>()
    private let selectedChannelPipe = ValuePipe<Mezon_Api_ChannelDescription?>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let needsReloadPipe = ValuePipe<Void>()

    private let channelsLoadedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var channelsLoadedSignal: Signal<Bool, NoError> { channelsLoadedPromise.get() }

    var selectedChannelSignal: Signal<Mezon_Api_ChannelDescription?, NoError> { selectedChannelPipe.signal() }

    private(set) var categories: [ChannelCategory] = []
    private(set) var selectedChannelId: Int64?
    private(set) var selectedChannel: Mezon_Api_ChannelDescription?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var clanId: Int64 = 0
    private(set) var clanName: String = ""

    private var channelListNode: ChannelListContainerNode { displayNode as! ChannelListContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = ChannelListInteraction(
            onSelectChannel: { [weak self] ch in self?.select(channel: ch) },
            onToggleCollapse: { [weak self] id in self?.toggleCollapse(categoryId: id) },
            onRefresh: { [weak self] in self?.fetchChannels() }
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
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        channelListNode.updateLayout(layout: layout, transition: transition)
    }

    func configure(clanId: Int64, clanName: String, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        channelListNode.configure(clanName: clanName, bannerURL: bannerURL, memberCount: memberCount, isCommunity: isCommunity)
        guard clanId != self.clanId else { return }
        restoreCachedChannelApps(clanId: clanId)
        load(clanId: clanId, clanName: clanName)
    }

    func updateMemberCount(_ count: Int) {
        channelListNode.updateMemberCount(count)
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

    /// Handle new incoming message — update lastSentMessage for unread highlight (NO badge increment)
    @objc private func handleNewMessageReceived(_ notification: Notification) {
        guard let channelId = notification.userInfo?["channelId"] as? Int64,
              let clanId = notification.userInfo?["clanId"] as? Int64 else { return }

        let senderId: String
        if let s = notification.userInfo?["senderId"] as? String { senderId = s }
        else if let n = notification.userInfo?["senderId"] as? Int64 { senderId = String(n) }
        else { return }

        let ts: UInt32
        if let t = notification.userInfo?["timestampSeconds"] as? UInt32 { ts = t }
        else if let t = notification.userInfo?["timestampSeconds"] as? Int { ts = UInt32(t) }
        else { ts = UInt32(Date().timeIntervalSince1970) }

        guard clanId == self.clanId, clanId != 0 else { return }
        guard senderId != context.currentUser?.id else { return }
        if let currentChannel = context.currentChannel, currentChannel.channelID == channelId { return }

        var updated = false
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
                var header = allChannels[i].lastSentMessage
                header.timestampSeconds = ts
                allChannels[i].lastSentMessage = header
                updated = true
            }
        }
        guard updated else { return }
        rebuildAndReload()
    }

    /// Handle mention/reply notification — increment countMessUnread badge
    @objc private func handleMentionReceived(_ notification: Notification) {
        guard let channelId = notification.userInfo?["channelId"] as? Int64,
              let clanId = notification.userInfo?["clanId"] as? Int64 else { return }
        guard clanId == self.clanId, clanId != 0 else { return }

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
                    let cats = buildChannelCategories(channels)
                    self.categories = cats
                    self.channelsLoadedPromise.set(true)
                    self.persistSelectedChannel()
                    self.categoriesPipe.putNext(cats)
                    self.fetchChannelApps()
                    self.context.account.postbox.setPreferenceData(
                        key: PreferencesKeys.channelList(clanId: clanId),
                        value: self.encodeChannelList(channels)
                    )
                case .failure(let msg):
                    self.errorMessage = msg
                    self.errorMessagePipe.putNext(msg)
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
    }

    func select(channel: Mezon_Api_ChannelDescription) {
        setSelectedChannelId(channel.channelID)
        setSelectedChannel(channel)
        self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId), value: encodeChannelId(channel.channelID))
    }

    func selectWithoutNavigation(channelId: Int64) {
        setSelectedChannelId(channelId)
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
        guard clanId != 0, let token = context.session?.token else { return }
        let clanId = self.clanId
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let apps = try await self.context.account.network.listChannelApps(clanId: clanId, token: token)
                self.channelListNode.updateChannelApps(apps)
                // Cache to postbox
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

    // MARK: - Channel List Cache

    @discardableResult
    private func restoreCachedChannels(clanId: Int64) -> Bool {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { return false }
        let channels = decodeChannelList(data)
        guard !channels.isEmpty else { return false }
        allChannels = channels
        let cats = buildChannelCategories(channels)
        categories = cats
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
}
