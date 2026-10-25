import Foundation

enum AnonymousMessageStore {

    static func clanPreventsAnonymous(clanId: Int64, lookupClan: () -> ClanRecord?) -> Bool {
        guard clanId != 0 else { return true }
        return lookupClan()?.preventsAnonymousMessages ?? false
    }

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

    static func applyClanPolicy(preventAnonymous: Bool, clanId: Int64) {
        if preventAnonymous && isEnabled(clanId: clanId) {
            setEnabled(false, clanId: clanId)
        }
    }

    @discardableResult
    static func toggle(clanId: Int64) -> Bool {
        let next = !isEnabled(clanId: clanId)
        setEnabled(next, clanId: clanId)
        return next
    }

    static func removeAllClanToggles() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("MezonChat.anonymousMessage.clan.")
        }
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
