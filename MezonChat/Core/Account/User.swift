import Foundation

struct User: Identifiable, Equatable, Codable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    var accountLogoURL: String?
    var status: OnlineStatus
    var customStatus: String?
    var customStatusTimeReset: Int32?
    var customStatusNoClear: Bool?
    var bio: String?
    var email: String?
    var phoneNumber: String?
    var isBot: Bool
    let createTimeSeconds: UInt32

    init(
        id: String,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        accountLogoURL: String? = nil,
        status: OnlineStatus = .offline,
        customStatus: String? = nil,
        customStatusTimeReset: Int32? = nil,
        customStatusNoClear: Bool? = nil,
        bio: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        isBot: Bool = false,
        createTimeSeconds: UInt32 = 0
    ) {
        self.id          = id
        self.username    = username
        self.displayName = displayName
        self.avatarURL   = avatarURL
        self.accountLogoURL = accountLogoURL
        self.status       = status
        self.customStatus = customStatus
        self.customStatusTimeReset = customStatusTimeReset
        self.customStatusNoClear = customStatusNoClear
        self.bio          = bio
        self.email       = email
        self.phoneNumber = phoneNumber
        self.isBot       = isBot
        self.createTimeSeconds = createTimeSeconds
    }

    enum OnlineStatus: String, Codable, Equatable {
        case online
        case idle
        case doNotDisturb = "dnd"
        case invisible
        case offline
    }

    static func knownPresenceStatus(fromApiString raw: String) -> OnlineStatus? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        switch lower {
        case "online": return .online
        case "idle", "away": return .idle
        case "dnd", "do not disturb", "do_not_disturb", "donotdisturb": return .doNotDisturb
        case "invisible": return .invisible
        case "offline": return .offline
        default: return nil
        }
    }

    static func presenceStatus(fromApiString raw: String, onlineFallback: Bool) -> OnlineStatus {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return onlineFallback ? .online : .offline }
        if let known = knownPresenceStatus(fromApiString: raw) { return known }
        return onlineFallback ? .online : .offline
    }

    static func customStatusDurationRowValue(timeReset: Int32, noClear: Bool) -> Int {
        if noClear { return 0 }
        switch timeReset {
        case 240: return 240
        case 60: return 60
        case 30: return 30
        case 0: return 0
        default: return -1
        }
    }
}

extension User.OnlineStatus {
    var apiPresenceString: String {
        switch self {
        case .online:       return "Online"
        case .idle:         return "Idle"
        case .doNotDisturb: return "Do Not Disturb"
        case .invisible:    return "Invisible"
        case .offline:      return "Offline"
        }
    }
}
