import Foundation
import Security

struct MmnPersistedZkProofs: Codable, Sendable {
    let proof: String
    let publicInput: String
}

struct MmnPersistedEphemeralKey: Codable, Sendable {
    let publicKeyBase58: String
    let seedBase64: String
}

private struct MmnWalletPersistedPayload: Codable {
    let userId: String
    let zkProofs: MmnPersistedZkProofs?
    let ephemeralKey: MmnPersistedEphemeralKey?
}

final class MmnWalletStore: @unchecked Sendable {
    static let shared = MmnWalletStore()

    private let queue = DispatchQueue(label: "mezon.mmn.walletstore", attributes: .concurrent)
    private var _userId: String?
    private var _zkProofs: MmnPersistedZkProofs?
    private var _ephemeralKey: MmnPersistedEphemeralKey?

    private static let service = "mezon.mmn.wallet.store"
    private static let account = "mezon.mmn.wallet"

    private init() {}

    var boundUserId: String? {
        queue.sync { _userId }
    }

    var zkProofs: MmnPersistedZkProofs? {
        queue.sync { _zkProofs }
    }

    var ephemeralKey: MmnPersistedEphemeralKey? {
        queue.sync { _ephemeralKey }
    }

    func ephemeralKeyPair() -> MmnEphemeralKeyPair? {
        guard let ek = ephemeralKey, let seed = Data(base64Encoded: ek.seedBase64) else { return nil }
        return try? MmnEphemeralKeyPair.fromSeed(seed)
    }

    func bind(userId: String) {
        guard !userId.isEmpty else { return }
        queue.sync(flags: .barrier) {
            if _userId == userId, _zkProofs != nil || _ephemeralKey != nil { return }
            _userId = userId
            let payload = Self.loadPersisted()
            if let payload, payload.userId == userId {
                _zkProofs = payload.zkProofs
                _ephemeralKey = payload.ephemeralKey
            } else {
                _zkProofs = nil
                _ephemeralKey = nil
                if let p = payload, p.userId != userId {
                    Self.persist(nil)
                }
            }
        }
    }

    func setZkProofs(_ zk: MmnPersistedZkProofs, ephemeralKey: MmnPersistedEphemeralKey, userId: String) {
        guard !userId.isEmpty else { return }
        queue.sync(flags: .barrier) {
            _userId = userId
            _zkProofs = zk
            _ephemeralKey = ephemeralKey
            Self.persist(MmnWalletPersistedPayload(userId: userId, zkProofs: zk, ephemeralKey: ephemeralKey))
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            _userId = nil
            _zkProofs = nil
            _ephemeralKey = nil
            Self.persist(nil)
        }
    }

    private static func keychainQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    private static func loadPersisted() -> MmnWalletPersistedPayload? {
        var q = keychainQuery()
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let payload = try? JSONDecoder().decode(MmnWalletPersistedPayload.self, from: data)
        else { return nil }
        return payload
    }

    private static func persist(_ payload: MmnWalletPersistedPayload?) {
        SecItemDelete(keychainQuery() as CFDictionary)
        guard let payload, let data = try? JSONEncoder().encode(payload) else { return }
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
