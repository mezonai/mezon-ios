import Foundation

struct User: Identifiable, Equatable, Codable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    var status: OnlineStatus
    var bio: String?
    var email: String?
    var phoneNumber: String?
    var isBot: Bool

    init(
        id: String,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        status: OnlineStatus = .offline,
        bio: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        isBot: Bool = false
    ) {
        self.id          = id
        self.username    = username
        self.displayName = displayName
        self.avatarURL   = avatarURL
        self.status      = status
        self.bio         = bio
        self.email       = email
        self.phoneNumber = phoneNumber
        self.isBot       = isBot
    }

    enum OnlineStatus: String, Codable, Equatable {
        case online
        case idle
        case doNotDisturb = "dnd"
        case offline
    }
}
