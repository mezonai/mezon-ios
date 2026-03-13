import Foundation

struct Message: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let channelId: String
    let clanId: String?
    let senderId: String
    var content: Content
    let createdAt: Date
    var editedAt: Date?
    var isDeleted: Bool
    var reactions: [Reaction]
    var replyToId: String?
    var mentionedUserIds: [String]
    var isPinned: Bool

    enum Content: Equatable, Hashable, Codable {
        case text(String)
        case image(URL, width: Int, height: Int)
        case video(URL, thumbnailURL: URL?)
        case file(URL, filename: String, size: Int64)
        case sticker(String)
        case system(String)
    }

    struct Reaction: Equatable, Hashable, Codable {
        let emoji: String
        var userIds: [String]

        mutating func toggle(userId: String) {
            if let idx = userIds.firstIndex(of: userId) {
                userIds.remove(at: idx)
            } else {
                userIds.append(userId)
            }
        }
    }
}

extension Message {
    var textContent: String? {
        if case .text(let text) = content { return text }
        return nil
    }

    var isSystemMessage: Bool {
        if case .system = content { return true }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}
