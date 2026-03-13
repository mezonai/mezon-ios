import UIKit
import SwiftProtobuf

struct ChannelListState {
    var categories: [ChannelCategory]
    var allChannels: [Mezon_Api_ChannelDescription] = []
    var selectedChannelId: Int64?
    var isLoading: Bool
    var errorMessage: String?

    static let empty = ChannelListState(categories: [], allChannels: [], selectedChannelId: nil, isLoading: false, errorMessage: nil)
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
    case text = 1, voice = 2, group = 3, thread = 4, streaming = 9, app = 5, forum = 10, unknown = 0

    var icon: String {
        switch self {
        case .text: return "#"
        case .voice: return "speaker.wave.2.fill"
        case .thread: return "arrow.turn.down.right"
        case .streaming: return "video.fill"
        case .app: return "app.fill"
        case .forum: return "text.bubble.fill"
        default: return "#"
        }
    }

    var isSystemImage: Bool { self != .text }
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

func flattenCategoryToRows(_ category: ChannelCategory, allChannels: [Mezon_Api_ChannelDescription]) -> [ChannelListRow] {
    var rows: [ChannelListRow] = []
    for ch in category.channels {
        rows.append(.channel(ch))
        let threads = allChannels.filter { $0.parentID == ch.channelID }.sorted { $0.channelLabel < $1.channelLabel }
        for (i, thread) in threads.enumerated() {
            rows.append(.thread(thread, isLast: i == threads.count - 1))
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
            onToggleCollapse: { [weak self] id in self?.toggleCollapse(categoryId: id) }
        )
        displayNode = ChannelListContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        channelListNode.applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        channelListNode.updateLayout(layout: layout, transition: transition)
    }

    func configure(clanId: Int64, clanName: String) {
        channelListNode.configure(clanName: clanName)
        load(clanId: clanId, clanName: clanName)
    }

    func refresh() { fetchChannels() }

    @objc private func handleThemeChange() { channelListNode.applyTheme() }

    private func setCategories(_ v: [ChannelCategory]) { categories = v; categoriesPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setSelectedChannelId(_ v: Int64?) { selectedChannelId = v; selectedChannelIdPipe.putNext(v) }
    private func setSelectedChannel(_ v: Mezon_Api_ChannelDescription?) { selectedChannel = v; selectedChannelPipe.putNext(v) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v) }

    func load(clanId: Int64, clanName: String) {
        self.clanId = clanId
        self.clanName = clanName
        fetchChannels()
    }

    func fetchChannels() {
        guard clanId != 0 else { return }
        setIsLoading(true)
        setErrorMessage(nil)
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
                self.persistSelectedChannel()
                self.categoriesPipe.putNext(cats)
            case .failure(let msg):
                self.errorMessage = msg
                self.errorMessagePipe.putNext(msg)
            }
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

    private(set) var allChannels: [Mezon_Api_ChannelDescription] = []

    var currentState: ChannelListState {
        ChannelListState(categories: categories, allChannels: allChannels, selectedChannelId: selectedChannelId, isLoading: isLoading, errorMessage: errorMessage)
    }

    func stateSignal() -> Signal<ChannelListState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    private func channelListSignal(clanId: Int64) -> Signal<[Mezon_Api_ChannelDescription], ChannelFetchError> {
        let context = self.context
        return Signal { subscriber in
            let task = Task { @MainActor in
                guard let token = context.session?.token else { subscriber.putError(.noSession); return }
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
}
