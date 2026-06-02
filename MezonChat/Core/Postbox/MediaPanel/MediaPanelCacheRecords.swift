import Foundation
import SwiftProtobuf

extension Notification.Name {
    static let mezonStickerListDidUpdate = Notification.Name("mezon.stickerList.didUpdate")
    static let mezonEmojiListDidUpdate = Notification.Name("mezon.emojiList.didUpdate")
}

enum MediaPanelRealtimeAction: Int32 {
    case created = 1
    case update = 2
    case delete = 3
}

enum MediaPanelPostboxKeys {
    static let emojiListByUser = "mediaPanel.emojiList.byUser"
    static let stickerListByUser = "mediaPanel.stickerList.byUser"

    static func emojiList(clanId: Int64) -> String { "mediaPanel.emojiList.\(clanId)" }
    static func stickerList(clanId: Int64) -> String { "mediaPanel.stickerList.\(clanId)" }
    static let gifCategoriesJson = "mediaPanel.gif.categories.json"
    static let gifFeaturedJson = "mediaPanel.gif.featured.json"
}

struct CachedClanEmojiRecord: Codable, PostboxCoding, Equatable {
    var id: Int64
    var src: String
    var shortname: String
    var category: String
    var creatorID: Int64
    var clanID: Int64
    var logo: String
    var clanName: String
    var isForSale: Bool
}

struct MediaPanelEmojiListCache: PostboxCoding, Equatable {
    var fetchedAt: TimeInterval
    var emojis: [CachedClanEmojiRecord]
}

enum StickerMediaType: Int32 {
    case sticker = 0
    case audio   = 1
}

struct CachedClanStickerRecord: Codable, PostboxCoding, Equatable {
    var id: Int64
    var source: String
    var shortname: String
    var category: String
    var creatorID: Int64
    var createTimeSeconds: UInt32
    var clanID: Int64
    var logo: String
    var clanName: String
    var mediaType: Int32
    var isForSale: Bool
}

struct MediaPanelStickerListCache: PostboxCoding, Equatable {
    var fetchedAt: TimeInterval
    var stickers: [CachedClanStickerRecord]
}

struct MediaPanelTenorJsonCache: PostboxCoding, Equatable {
    var fetchedAt: TimeInterval
    var jsonData: Data
}

extension Mezon_Api_ClanEmoji {
    func toCachedRecord() -> CachedClanEmojiRecord {
        CachedClanEmojiRecord(
            id: id,
            src: src,
            shortname: shortname,
            category: category,
            creatorID: creatorID,
            clanID: clanID,
            logo: logo,
            clanName: clanName,
            isForSale: isForSale
        )
    }
}

extension Mezon_Api_ClanSticker {
    func toCachedRecord() -> CachedClanStickerRecord {
        CachedClanStickerRecord(
            id: id,
            source: source,
            shortname: shortname,
            category: category,
            creatorID: creatorID,
            createTimeSeconds: createTimeSeconds,
            clanID: clanID,
            logo: logo,
            clanName: clanName,
            mediaType: mediaType,
            isForSale: isForSale
        )
    }
}

extension CachedClanEmojiRecord {
    var displayImageURLString: String {
        let src = self.src.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty, URL(string: src)?.scheme != nil { return src }
        if src.hasPrefix("//") { return "https:\(src)" }
        if !src.isEmpty {
            let base = MezonConfig.baseImgURL
            return src.hasPrefix("/") ? "\(base)\(src)" : "\(base)/\(src)"
        }
        return "\(MezonConfig.baseImgURL)/emojis/\(id).webp"
    }

    static func innerName(from shortname: String) -> String {
        var s = shortname.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(":") { s.removeFirst() }
        if s.hasSuffix(":") { s.removeLast() }
        return s
    }

    static func wrappedShortname(_ inner: String) -> String {
        ":\(inner):"
    }
}

extension CachedClanStickerRecord {
    var displayImageURLString: String {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty, URL(string: src)?.scheme != nil { return src }
        if src.hasPrefix("//") { return "https:\(src)" }
        if !src.isEmpty {
            let base = MezonConfig.baseImgURL
            return src.hasPrefix("/") ? "\(base)\(src)" : "\(base)/\(src)"
        }
        return "\(MezonConfig.baseImgURL)/stickers/\(id).webp"
    }
}

extension ClanMemberRecord {
    var resolvedDisplayName: String {
        if !clanNick.isEmpty { return clanNick }
        if !displayName.isEmpty { return displayName }
        return username
    }
}

extension Array where Element == CachedClanEmojiRecord {
    func deduplicatedByEmojiId() -> [CachedClanEmojiRecord] {
        var byId: [Int64: CachedClanEmojiRecord] = [:]
        var order: [Int64] = []
        for emoji in self where emoji.id != 0 {
            if byId[emoji.id] == nil {
                order.append(emoji.id)
            }
            let existing = byId[emoji.id]
            let existingHasSrc = !(existing?.src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let incomingHasSrc = !emoji.src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if existing == nil || (incomingHasSrc && !existingHasSrc) {
                byId[emoji.id] = emoji
            }
        }
        return order.compactMap { byId[$0] }
    }
}
