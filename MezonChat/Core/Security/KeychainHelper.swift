import Foundation
import Security
import os.log

final class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    private let service = "mezon.postbox.dbkeys"
    private static let log = OSLog(subsystem: "mezon.security", category: "keychain")

    private static let maxKeychainRetries = 3

    private enum KeyLookup {
        case found(Data)
        case missing
        case unavailable(OSStatus)
    }

    func databaseKey(for identifier: String) -> Data? {
        let account = "db.\(identifier)"

        switch load(account: account) {
        case .found(let existing):
            return existing
        case .unavailable(let status):
            os_log(.error, log: Self.log,
                   "Keychain unreadable (status %d) for %{public}@; refusing to regenerate key",
                   status, identifier)
            return nil
        case .missing:
            break
        }

        var key = Data(count: 32)
        let result = key.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            os_log(.error, log: Self.log, "SecRandomCopyBytes failed with status %d", result)
            return nil
        }

        for attempt in 1...Self.maxKeychainRetries {
            if save(account: account, data: key) { return key }
            os_log(.error, log: Self.log, "Keychain save attempt %d/%d failed for %{public}@", attempt, Self.maxKeychainRetries, identifier)
            if attempt < Self.maxKeychainRetries {
                Thread.sleep(forTimeInterval: 0.1 * Double(attempt))
            }
        }

        if case .found(let reloaded) = load(account: account) { return reloaded }

        os_log(.error, log: Self.log,
               "Failed to persist database encryption key for %{public}@ after %d attempts",
               identifier, Self.maxKeychainRetries)
        return nil
    }

    @discardableResult
    private func save(account: String, data: Data) -> Bool {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            os_log(.error, log: Self.log, "SecItemAdd failed: %d for account %{public}@", status, account)
            return false
        }
        return true
    }

    private func load(account: String) -> KeyLookup {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, !data.isEmpty else { return .unavailable(status) }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable(status)
        }
    }

    func removeAllDatabaseEncryptionKeys() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
