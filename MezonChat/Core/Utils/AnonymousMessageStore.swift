import Foundation

enum AnonymousMessageStore {

    private static func storageKey(clanId: Int64) -> String {
        "MezonChat.anonymousMessage.clan.\(clanId)"
    }

    static func isEnabled(clanId: Int64) -> Bool {
        guard clanId != 0 else { return false }
        return UserDefaults.standard.bool(forKey: storageKey(clanId: clanId))
    }

    static func setEnabled(_ value: Bool, clanId: Int64) {
        guard clanId != 0 else { return }
        UserDefaults.standard.set(value, forKey: storageKey(clanId: clanId))
    }

    @discardableResult
    static func toggle(clanId: Int64) -> Bool {
        let next = !isEnabled(clanId: clanId)
        setEnabled(next, clanId: clanId)
        return next
    }
}
