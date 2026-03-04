import Foundation

struct MezonSession: Codable {
    let token: String
    let refreshToken: String
    let expiresAt: Date
    let created: Bool

    let apiURL: String?
    let wsURL: String?

    let userId: String?
    let username: String?
    let idToken: String?
    let isRemember: Bool?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }

    var wsHostname: String? {
        guard let wsURL, let url = URL(string: wsURL) else { return nil }
        return url.host
    }

    var apiHostname: String? {
        guard let apiURL, let url = URL(string: apiURL) else { return nil }
        return url.host
    }

    enum CodingKeys: String, CodingKey {
        case token
        case refreshToken    = "refresh_token"
        case expiresAt       = "expires_at"
        case created
        case apiURL          = "api_url"
        case wsURL           = "ws_url"
        case userId          = "user_id"
        case username
        case idToken         = "id_token"
        case isRemember      = "is_remember"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token        = try c.decode(String.self, forKey: .token)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        created      = try c.decodeIfPresent(Bool.self, forKey: .created) ?? false
        apiURL       = try c.decodeIfPresent(String.self, forKey: .apiURL)
        wsURL        = try c.decodeIfPresent(String.self, forKey: .wsURL)
        userId       = try c.decodeIfPresent(String.self, forKey: .userId)
        username     = try c.decodeIfPresent(String.self, forKey: .username)
        idToken      = try c.decodeIfPresent(String.self, forKey: .idToken)
        isRemember   = try c.decodeIfPresent(Bool.self, forKey: .isRemember)

        if let ts = try? c.decode(Int64.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(ts))
        } else if let ts = try? c.decode(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: ts)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(refreshToken, forKey: .refreshToken)
        try c.encode(created, forKey: .created)
        try c.encode(Int64(expiresAt.timeIntervalSince1970), forKey: .expiresAt)
        try c.encodeIfPresent(apiURL, forKey: .apiURL)
        try c.encodeIfPresent(wsURL, forKey: .wsURL)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(idToken, forKey: .idToken)
        try c.encodeIfPresent(isRemember, forKey: .isRemember)
    }
}

struct OTPRequestResponse: Decodable {
    let reqId: String?

    enum CodingKeys: String, CodingKey {
        case reqId = "req_id"
    }
}

enum SessionStore {
    private static let sessionKey = "mezon.session"
    private static let configKey  = "mezon.config"

    static func save(_ session: MezonSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
        if let apiURL = session.apiURL, let wsURL = session.wsURL {
            let config: [String: String] = ["api_url": apiURL, "ws_url": wsURL]
            UserDefaults.standard.set(config, forKey: configKey)
        }
    }

    static func load() -> MezonSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(MezonSession.self, from: data)
        else { return nil }
        return session
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: configKey)
    }
}
