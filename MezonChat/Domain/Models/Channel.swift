import Foundation

struct Channel: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var name: String
    var description: String?
    let type: ChannelType
    let clanId: String?         // nil for DMs
    var memberIds: [String]
    var lastMessage: Message?
    var unreadCount: Int
    var isArchived: Bool

    enum ChannelType: String, Codable, Equatable {
        case text           // text channel inside a clan
        case voice          // voice channel
        case directMessage  // 1-to-1 DM
        case groupDM        // group DM (no clan)
        case announcement   // read-only broadcast channel
    }
}

extension Channel {
    var isDirect: Bool {
        type == .directMessage || type == .groupDM
    }

    var displayName: String {
        isDirect ? name : "#\(name)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }
}
