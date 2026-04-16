import Foundation
import Security
import os.log

final class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    private let service = "mezon.postbox.dbkeys"
    private static let log = OSLog(subsystem: "mezon.security", category: "keychain")

    func databaseKey(for identifier: String) -> Data {
        let account = "db.\(identifier)"
        if let existing = load(account: account) { return existing }

        var key = Data(count: 32)
        let result = key.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            fatalError("SecRandomCopyBytes failed with status \(result). Cannot generate database encryption key.")
        }
        guard save(account: account, data: key) else {
            fatalError("Failed to save database encryption key to Keychain for \(identifier).")
        }
        return key
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

    private func load(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
