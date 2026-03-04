import Foundation
import Combine

struct ChannelCategory {
    let id: Int64
    let name: String
    var isCollapsed: Bool = false
    var channels: [Mezon_Api_ChannelDescription]
}

enum ChannelType: Int32 {
    case text      = 1
    case voice     = 2
    case thread    = 3
    case streaming = 9
    case app       = 5
    case forum     = 10
    case unknown   = 0

    var icon: String {
        switch self {
        case .text:      return "#"
        case .voice:     return "speaker.wave.2.fill"
        case .thread:    return "arrow.turn.down.right"
        case .streaming: return "video.fill"
        case .app:       return "app.fill"
        case .forum:     return "text.bubble.fill"
        default:         return "#"
        }
    }

    var isSystemImage: Bool { self != .text }
}

@MainActor
final class ChannelListViewModel: BaseViewModel {

    @Published private(set) var categories: [ChannelCategory] = []
    @Published var selectedChannelId: Int64?

    private(set) var clanId: Int64 = 0
    private(set) var clanName: String = ""
    private let context: AppContext

    init(context: AppContext) {
        self.context = context
        super.init()
    }

    func load(clanId: Int64, clanName: String) {
        self.clanId = clanId
        self.clanName = clanName
        Task { await fetchChannels() }
    }

    func fetchChannels() async {
        guard clanId != 0 else { return }
        guard let token = context.session?.token else {
            print("[ChannelListViewModel] no session token")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let descs = try await MezonHTTPClient.shared.listChannelDescs(clanId: clanId, token: token)
            categories = groupByCategory(descs)
        } catch {
            errorMessage = error.localizedDescription
            print("[ChannelListViewModel] fetchChannels error: \(error)")
        }
    }

    func toggleCollapse(categoryId: Int64) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        categories[idx].isCollapsed.toggle()
    }

    func select(channel: Mezon_Api_ChannelDescription) {
        selectedChannelId = channel.channelID
    }

    private func groupByCategory(_ channels: [Mezon_Api_ChannelDescription]) -> [ChannelCategory] {
        let topLevel = channels.filter { $0.parentID == 0 }

        var map: [(Int64, String, [Mezon_Api_ChannelDescription])] = []
        var seenIds: [Int64] = []

        for ch in topLevel {
            let catId = ch.categoryID
            if let existingIdx = seenIds.firstIndex(of: catId) {
                map[existingIdx].2.append(ch)
            } else {
                seenIds.append(catId)
                map.append((catId, ch.categoryName, [ch]))
            }
        }

        return map.map { (id, name, chList) in
            ChannelCategory(id: id, name: name, isCollapsed: false, channels: chList)
        }
    }
}
