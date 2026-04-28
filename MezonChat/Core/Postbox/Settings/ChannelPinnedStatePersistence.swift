import Foundation

struct ChannelPinnedStateSnapshot: Codable, Equatable, PostboxCoding {
    var pinnedMessageIds: [String]
    var pinServerIdByMessageId: [String: Int64]
}

enum ChannelPinnedStatePersistence {
    private static func storageKey(accountId: String, clanId: Int64, channelId: Int64) -> String {
        "channelPins_\(accountId)_\(clanId)_\(channelId)"
    }

    static func load(postbox: Postbox, accountId: String, clanId: Int64, channelId: Int64) -> ChannelPinnedStateSnapshot? {
        guard !accountId.isEmpty, channelId != 0 else { return nil }
        return postbox.getSetting(
            key: storageKey(accountId: accountId, clanId: clanId, channelId: channelId),
            type: ChannelPinnedStateSnapshot.self
        )
    }

    static func save(
        postbox: Postbox,
        accountId: String,
        clanId: Int64,
        channelId: Int64,
        pinnedMessageIds: Set<String>,
        pinServerIdByMessageId: [String: Int64]
    ) {
        guard !accountId.isEmpty, channelId != 0 else { return }
        let key = storageKey(accountId: accountId, clanId: clanId, channelId: channelId)
        if pinnedMessageIds.isEmpty && pinServerIdByMessageId.isEmpty {
            postbox.setSetting(key: key, value: nil as ChannelPinnedStateSnapshot?)
            return
        }
        let snap = ChannelPinnedStateSnapshot(
            pinnedMessageIds: pinnedMessageIds.sorted(),
            pinServerIdByMessageId: pinServerIdByMessageId
        )
        postbox.setSetting(key: key, value: snap)
    }

    static func applyPinMessage(postbox: Postbox, accountId: String, clanId: Int64, channelId: Int64, messageId: Int64) {
        guard !accountId.isEmpty, channelId != 0, messageId != 0 else { return }
        let key = storageKey(accountId: accountId, clanId: clanId, channelId: channelId)
        var snap =
            postbox.getSetting(key: key, type: ChannelPinnedStateSnapshot.self)
            ?? ChannelPinnedStateSnapshot(pinnedMessageIds: [], pinServerIdByMessageId: [:])
        var ids = Set(snap.pinnedMessageIds)
        ids.insert("\(messageId)")
        snap.pinnedMessageIds = ids.sorted()
        postbox.setSetting(key: key, value: snap)
    }

    static func applyUnpinMessage(postbox: Postbox, accountId: String, clanId: Int64, channelId: Int64, messageId: Int64) {
        guard !accountId.isEmpty, channelId != 0, messageId != 0 else { return }
        let key = storageKey(accountId: accountId, clanId: clanId, channelId: channelId)
        let mid = "\(messageId)"
        let existing = postbox.getSetting(key: key, type: ChannelPinnedStateSnapshot.self)
        var snap =
            existing
            ?? ChannelPinnedStateSnapshot(pinnedMessageIds: [], pinServerIdByMessageId: [:])
        var ids = Set(snap.pinnedMessageIds)
        ids.remove(mid)
        snap.pinnedMessageIds = ids.sorted()
        snap.pinServerIdByMessageId.removeValue(forKey: mid)
        if snap.pinnedMessageIds.isEmpty && snap.pinServerIdByMessageId.isEmpty {
            postbox.setSetting(key: key, value: nil as ChannelPinnedStateSnapshot?)
        } else {
            postbox.setSetting(key: key, value: snap)
        }
    }
}
