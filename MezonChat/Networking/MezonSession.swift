import Foundation
import Security
import SwiftProtobuf

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

    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token        = try c.decode(String.self, forKey: CodingKeys.token)
        refreshToken = try c.decode(String.self, forKey: CodingKeys.refreshToken)
        created      = try c.decodeIfPresent(Bool.self, forKey: CodingKeys.created) ?? false
        apiURL       = try c.decodeIfPresent(String.self, forKey: CodingKeys.apiURL)
        wsURL        = try c.decodeIfPresent(String.self, forKey: CodingKeys.wsURL)
        userId       = try c.decodeIfPresent(String.self, forKey: CodingKeys.userId)
        username     = try c.decodeIfPresent(String.self, forKey: CodingKeys.username)
        idToken      = try c.decodeIfPresent(String.self, forKey: CodingKeys.idToken)
        isRemember   = try c.decodeIfPresent(Bool.self, forKey: CodingKeys.isRemember)

        if let ts = try? c.decode(Int64.self, forKey: CodingKeys.expiresAt) {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(ts))
        } else if let ts = try? c.decode(Double.self, forKey: CodingKeys.expiresAt) {
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

    static func fromProto(_ proto: Mezon_Api_Session) -> MezonSession {
        let expiresAt = accessTokenExpiryFromJWT(proto.token) ?? Date().addingTimeInterval(3600)
        return MezonSession(
            token: proto.token,
            refreshToken: proto.refreshToken,
            expiresAt: expiresAt,
            created: proto.created,
            apiURL: proto.apiURL.isEmpty ? nil : proto.apiURL,
            wsURL: proto.wsURL.isEmpty ? nil : proto.wsURL,
            userId: proto.userID != 0 ? String(proto.userID) : nil,
            username: nil,
            idToken: proto.idToken.isEmpty ? nil : proto.idToken,
            isRemember: proto.isRemember
        )
    }

    private static func accessTokenExpiryFromJWT(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = (4 - payload.count % 4) % 4
        if pad > 0 { payload += String(repeating: "=", count: pad) }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let exp = obj["exp"] as? Double {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = obj["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        if let exp = obj["exp"] as? Int64 {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    private init(
        token: String,
        refreshToken: String,
        expiresAt: Date,
        created: Bool,
        apiURL: String?,
        wsURL: String?,
        userId: String?,
        username: String?,
        idToken: String?,
        isRemember: Bool?
    ) {
        self.token = token
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.created = created
        self.apiURL = apiURL
        self.wsURL = wsURL
        self.userId = userId
        self.username = username
        self.idToken = idToken
        self.isRemember = isRemember
    }
}

struct OTPRequestResponse: Decodable {
    let reqId: String?

    enum CodingKeys: String, CodingKey {
        case reqId = "req_id"
    }
}

enum SessionStore {
    private static let service = "mezon.session.store"
    private static let sessionAccount = "mezon.session"
    private static let configKey = "mezon.config"

    static func save(_ session: MezonSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionAccount,
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        if let apiURL = session.apiURL, let wsURL = session.wsURL {
            let config: [String: String] = ["api_url": apiURL, "ws_url": wsURL]
            UserDefaults.standard.set(config, forKey: configKey)
        }
    }

    static func load() -> MezonSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let session = try? JSONDecoder().decode(MezonSession.self, from: data) {
            return session
        }
        if let data = UserDefaults.standard.data(forKey: "mezon.session"),
           let session = try? JSONDecoder().decode(MezonSession.self, from: data) {
            save(session)
            UserDefaults.standard.removeObject(forKey: "mezon.session")
            return session
        }
        return nil
    }

    static func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: sessionAccount,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "mezon.session")
        UserDefaults.standard.removeObject(forKey: configKey)
    }
}
