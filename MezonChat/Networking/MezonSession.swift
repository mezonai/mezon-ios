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
    let tcpURL: String?

    let userId: String?
    let username: String?
    let idToken: String?
    let isRemember: Bool?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }

    static let unresolvedExpiryFallbackSeconds: TimeInterval = 300

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
        case tcpURL          = "tcp_url"
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
        tcpURL       = try c.decodeIfPresent(String.self, forKey: CodingKeys.tcpURL)
        userId       = try c.decodeIfPresent(String.self, forKey: CodingKeys.userId)
        username     = try c.decodeIfPresent(String.self, forKey: CodingKeys.username)
        idToken      = try c.decodeIfPresent(String.self, forKey: CodingKeys.idToken)
        isRemember   = try c.decodeIfPresent(Bool.self, forKey: CodingKeys.isRemember)

        if let ts = try? c.decode(Int64.self, forKey: CodingKeys.expiresAt) {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(ts))
        } else if let ts = try? c.decode(Double.self, forKey: CodingKeys.expiresAt) {
            expiresAt = Date(timeIntervalSince1970: ts)
        } else {
            expiresAt = Date().addingTimeInterval(Self.unresolvedExpiryFallbackSeconds)
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
        try c.encodeIfPresent(tcpURL, forKey: .tcpURL)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(idToken, forKey: .idToken)
        try c.encodeIfPresent(isRemember, forKey: .isRemember)
    }

    static func fromProto(_ proto: Mezon_Api_Session) -> MezonSession {
        let expiresAt = accessTokenExpiryFromJWT(proto.token) ?? Date().addingTimeInterval(unresolvedExpiryFallbackSeconds)
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
            isRemember: proto.isRemember,
            tcpURL: nil
        )
    }

    static func accessTokenExpiryFromJWT(_ token: String) -> Date? {
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
        isRemember: Bool?,
        tcpURL: String? = nil
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
        self.tcpURL = tcpURL
    }

    func withIdToken(_ newIdToken: String?) -> MezonSession {
        MezonSession(
            token: token,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            created: created,
            apiURL: apiURL,
            wsURL: wsURL,
            userId: userId,
            username: username,
            idToken: newIdToken,
            isRemember: isRemember,
            tcpURL: tcpURL
        )
    }

    func mergedPreservingLocalCredentials(from previous: MezonSession) -> MezonSession {
        var mergedIdToken = idToken
        if mergedIdToken?.isEmpty != false, let p = previous.idToken, !p.isEmpty {
            mergedIdToken = p
        }
        var mergedTcpURL = tcpURL
        if mergedTcpURL?.isEmpty != false, let p = previous.tcpURL, !p.isEmpty {
            mergedTcpURL = p
        }
        return MezonSession(
            token: token,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            created: created,
            apiURL: apiURL,
            wsURL: wsURL,
            userId: userId,
            username: username,
            idToken: mergedIdToken,
            isRemember: isRemember,
            tcpURL: mergedTcpURL
        )
    }

    func mergedWithUsernameResponse(_ proto: Mezon_Api_Session, chosenUsername: String) -> MezonSession {
        let partial = MezonSession.fromProto(proto)
        return MezonSession(
            token: partial.token.isEmpty ? token : partial.token,
            refreshToken: partial.refreshToken.isEmpty ? refreshToken : partial.refreshToken,
            expiresAt: partial.expiresAt,
            created: false,
            apiURL: partial.apiURL ?? apiURL,
            wsURL: partial.wsURL ?? wsURL,
            userId: partial.userId ?? userId,
            username: chosenUsername,
            idToken: partial.idToken ?? idToken,
            isRemember: partial.isRemember ?? isRemember,
            tcpURL: partial.tcpURL ?? tcpURL
        )
    }

    func applyingRefreshEvent(_ proto: Mezon_Api_Session) -> MezonSession {
        let newToken = proto.token.isEmpty ? token : proto.token
        let newExpiry = proto.token.isEmpty
            ? expiresAt
            : (MezonSession.accessTokenExpiryFromJWT(proto.token)
                ?? Date().addingTimeInterval(MezonSession.unresolvedExpiryFallbackSeconds))
        return MezonSession(
            token: newToken,
            refreshToken: proto.refreshToken.isEmpty ? refreshToken : proto.refreshToken,
            expiresAt: newExpiry,
            created: created,
            apiURL: apiURL,
            wsURL: wsURL,
            userId: userId,
            username: username,
            idToken: idToken,
            isRemember: isRemember,
            tcpURL: tcpURL
        )
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
    private static let idTokenBackupAccount = "mezon.session.id_token_backup"
    private static let installationIdAccount = "mezon.installation_instance"
    private static let installationIdUserDefaultsKey = "mezon.installation_instance.ud"
    private static let configKey = "mezon.config"

    static func prepareInstallationScopedKeychainIfNeeded() {
        let ud = UserDefaults.standard
        let udInst = ud.string(forKey: installationIdUserDefaultsKey)
        let kcInst = loadInstallationIdFromKeychain()

        if udInst == nil, kcInst == nil {
            if load() != nil {
                let newId = UUID().uuidString
                ud.set(newId, forKey: installationIdUserDefaultsKey)
                saveInstallationIdToKeychain(newId)
                return
            }
            clearOrphanKeychainAfterReinstall()
            let newId = UUID().uuidString
            ud.set(newId, forKey: installationIdUserDefaultsKey)
            saveInstallationIdToKeychain(newId)
            return
        }

        if udInst == nil, kcInst != nil {
            clearOrphanKeychainAfterReinstall()
            let newId = UUID().uuidString
            ud.set(newId, forKey: installationIdUserDefaultsKey)
            saveInstallationIdToKeychain(newId)
            return
        }

        if let udInst, kcInst == nil {
            saveInstallationIdToKeychain(udInst)
            return
        }

        if let udInst, let kcInst, udInst != kcInst {
            clearOrphanKeychainAfterReinstall()
            let newId = UUID().uuidString
            ud.set(newId, forKey: installationIdUserDefaultsKey)
            saveInstallationIdToKeychain(newId)
            return
        }
    }

    private static func loadInstallationIdFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: installationIdAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty else { return nil }
        return s
    }

    private static func saveInstallationIdToKeychain(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        let del: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: installationIdAccount,
        ]
        SecItemDelete(del as CFDictionary)
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: installationIdAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func deleteInstallationIdFromKeychain() {
        let del: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: installationIdAccount,
        ]
        SecItemDelete(del as CFDictionary)
    }

    private static func clearOrphanKeychainAfterReinstall() {
        clear()
        deleteInstallationIdFromKeychain()
        KeychainHelper.shared.removeAllDatabaseEncryptionKeys()
        if #available(iOS 13.0, *) {
            MmnWalletStore.shared.clear()
        }
    }

    private struct IdTokenBackupPayload: Codable {
        let userId: String
        let idToken: String
    }

    private static func idTokenBackupQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: idTokenBackupAccount,
        ]
    }

    private static func loadIdTokenBackup() -> IdTokenBackupPayload? {
        var q = idTokenBackupQuery()
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let payload = try? JSONDecoder().decode(IdTokenBackupPayload.self, from: data)
        else { return nil }
        return payload
    }

    private static func persistIdTokenBackup(_ payload: IdTokenBackupPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        SecItemDelete(idTokenBackupQuery() as CFDictionary)
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: idTokenBackupAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func clearIdTokenBackup() {
        SecItemDelete(idTokenBackupQuery() as CFDictionary)
    }

    private static func syncIdTokenBackup(for session: MezonSession) {
        if let existing = loadIdTokenBackup(),
           let uid = session.userId,
           !uid.isEmpty,
           existing.userId != uid {
            clearIdTokenBackup()
        }
        if let id = session.idToken, !id.isEmpty,
           let uid = session.userId, !uid.isEmpty {
            persistIdTokenBackup(IdTokenBackupPayload(userId: uid, idToken: id))
        }
    }

    static func applyIdTokenFallback(_ session: MezonSession) -> MezonSession {
        if let id = session.idToken, !id.isEmpty { return session }
        guard let uid = session.userId, !uid.isEmpty,
              let backup = loadIdTokenBackup(),
              backup.userId == uid,
              !backup.idToken.isEmpty
        else { return session }
        return session.withIdToken(backup.idToken)
    }

    static func save(_ session: MezonSession) {
        let sessionToStore = applyIdTokenFallback(session)
        syncIdTokenBackup(for: sessionToStore)
        guard let data = try? JSONEncoder().encode(sessionToStore) else { return }
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

        if let apiURL = sessionToStore.apiURL, let wsURL = sessionToStore.wsURL {
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
           var session = try? JSONDecoder().decode(MezonSession.self, from: data) {
            session = applyIdTokenFallback(session)
            return session
        }
        if let data = UserDefaults.standard.data(forKey: "mezon.session"),
           var session = try? JSONDecoder().decode(MezonSession.self, from: data) {
            session = applyIdTokenFallback(session)
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
        clearIdTokenBackup()
        UserDefaults.standard.removeObject(forKey: "mezon.session")
        UserDefaults.standard.removeObject(forKey: configKey)
    }
}
