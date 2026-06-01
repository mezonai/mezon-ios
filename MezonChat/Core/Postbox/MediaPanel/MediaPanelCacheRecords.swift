import Foundation
import SwiftProtobuf

extension Notification.Name {
    static let mezonStickerListDidUpdate = Notification.Name("MezonStickerListDidUpdate")
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
