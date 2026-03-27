import Foundation
import SwiftProtobuf

struct ParsedEmbed {
    let color: String?
    let title: String?
    let url: String?
    let description: String?
    let imageURL: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let thumbnailURL: String?
    let footerText: String?
    let footerIconURL: String?
    let authorName: String?
    let authorIconURL: String?
    let timestamp: String?
}

struct ParsedContent {
    let text: String
    let tokens: [ContentToken]
    let embeds: [ParsedEmbed]

    static let empty = ParsedContent(text: "", tokens: [], embeds: [])

    var isPlainText: Bool { tokens.isEmpty }

    var isOnlyEmoji: Bool {
        guard !tokens.isEmpty else { return false }
        let allEmoji = tokens.allSatisfy {
            if case .emoji = $0.kind { return true }
            return false
        }
        guard allEmoji else { return false }
        var remaining = text
        for token in tokens.sorted(by: { $0.start > $1.start }) {
            let s = remaining.index(remaining.startIndex, offsetBy: token.start, limitedBy: remaining.endIndex) ?? remaining.endIndex
            let e = remaining.index(remaining.startIndex, offsetBy: token.end, limitedBy: remaining.endIndex) ?? remaining.endIndex
            if s < e { remaining.removeSubrange(s..<e) }
        }
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ContentTokenKind {
    case emoji(emojiId: String)
    case mention(userId: String?, roleId: String?, username: String?)
    case hashtag(channelId: String?, clanId: String?, channelLabel: String?)
    case inlineCode
    case codeBlock
    case bold
    case strikethrough
    case link
}

struct ContentToken {
    let start: Int
    let end: Int
    let kind: ContentTokenKind
}

enum MessageContentParser {

    static func parse(data: Data, mentionsData: Data = Data()) -> ParsedContent {
        guard !data.isEmpty,
              let str = String(data: data, encoding: .utf8),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedContent(text: str, tokens: [], embeds: [])
        }
        let text = json["t"] as? String ?? json["text"] as? String ?? ""
        let embeds = parseEmbeds(json["embed"])
        if text.isEmpty && embeds.isEmpty { return ParsedContent(text: "", tokens: [], embeds: []) }
        guard !text.isEmpty else { return ParsedContent(text: "", tokens: [], embeds: embeds) }

        var tokens: [ContentToken] = []

        if let ej = json["ej"] as? [[String: Any]] {
            tokens.append(contentsOf: parseEmojis(ej))
        }

        if let mentions = json["mentions"] as? [[String: Any]] {
            tokens.append(contentsOf: parseMentions(mentions))
        } else if !mentionsData.isEmpty {
            let mentionTokens = parseMentionsFromProto(mentionsData)
            let validMentions = mentionTokens.filter { token in
                let idx = text.index(text.startIndex, offsetBy: token.start, limitedBy: text.endIndex)
                guard let i = idx, i < text.endIndex else { return false }
                return text[i] == "@"
            }
            tokens.append(contentsOf: validMentions)
        }

        if let hg = json["hg"] as? [[String: Any]] {
            tokens.append(contentsOf: parseHashtags(hg))
        }

        if let mk = json["mk"] as? [[String: Any]] {
            tokens.append(contentsOf: parseMarkdowns(mk))
        }

        tokens.sort { $0.start < $1.start }

        let maxLen = text.count
        tokens = tokens.filter { $0.start >= 0 && $0.end <= maxLen && $0.start < $0.end }

        return ParsedContent(text: text, tokens: tokens, embeds: embeds)
    }

    private static func parseEmojis(_ items: [[String: Any]]) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]),
                  let emojiId = stringValue(item["emojiid"]) else { return nil }
            return ContentToken(start: s, end: e, kind: .emoji(emojiId: emojiId))
        }
    }

    private static func parseMentions(_ items: [[String: Any]]) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]) else { return nil }
            let userId = stringValue(item["user_id"])
            let roleId = stringValue(item["role_id"])
            let username = stringValue(item["username"])
            return ContentToken(start: s, end: e, kind: .mention(userId: userId, roleId: roleId, username: username))
        }
    }

    private static func parseMentionsFromProto(_ data: Data) -> [ContentToken] {
        if let list = try? Mezon_Api_MessageMentionList(serializedBytes: data), !list.mentions.isEmpty {
            return list.mentions.compactMap { m -> ContentToken? in
                let s = Int(m.s)
                let e = Int(m.e)
                guard e > s else { return nil }
                guard m.userID != 0 || m.roleID != 0 else { return nil }
                let userId = m.userID != 0 ? "\(m.userID)" : nil
                let roleId = m.roleID != 0 ? "\(m.roleID)" : nil
                let username = m.username.isEmpty ? nil : m.username
                return ContentToken(start: s, end: e, kind: .mention(userId: userId, roleId: roleId, username: username))
            }
        }
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parseMentions(jsonArray)
        }
        return []
    }

    private static func parseHashtags(_ items: [[String: Any]]) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]) else { return nil }
            let channelId = stringValue(item["channelId"]) ?? stringValue(item["channelid"])
            let clanId = stringValue(item["clanId"])
            let channelLabel = stringValue(item["channelLabel"]) ?? stringValue(item["channelIabel"])
            return ContentToken(start: s, end: e, kind: .hashtag(channelId: channelId, clanId: clanId, channelLabel: channelLabel))
        }
    }

    private static func parseMarkdowns(_ items: [[String: Any]]) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]) else { return nil }
            let type = item["type"] as? String ?? ""
            let kind: ContentTokenKind
            switch type {
            case "c":           kind = .inlineCode
            case "s":           kind = .strikethrough
            case "t", "pre":    kind = .codeBlock
            case "b":           kind = .bold
            case "lk", "lk_yt", "lk_fb", "lk_tt", "vk", "lk_ogp":
                                kind = .link
            default:            kind = .bold
            }
            return ContentToken(start: s, end: e, kind: kind)
        }
    }

    private static func intValue(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func stringValue(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty, s != "0" else { return nil }
        return s
    }

    private static func parseEmbeds(_ value: Any?) -> [ParsedEmbed] {
        guard let arr = value as? [[String: Any]], !arr.isEmpty else { return [] }
        return arr.compactMap { item -> ParsedEmbed? in
            let title = item["title"] as? String
            let description = item["description"] as? String
            let url = item["url"] as? String
            let color = item["color"] as? String

            let imageURL = (item["image"] as? [String: Any])?["url"] as? String
            let imageWidth = intValue((item["image"] as? [String: Any])?["width"])
            let imageHeight = intValue((item["image"] as? [String: Any])?["height"])
            let thumbnailURL = (item["thumbnail"] as? [String: Any])?["url"] as? String

            let footer = item["footer"] as? [String: Any]
            let footerText = footer?["text"] as? String
            let footerIconURL = footer?["icon_url"] as? String

            let author = item["author"] as? [String: Any]
            let authorName = author?["name"] as? String
            let authorIconURL = author?["icon_url"] as? String

            let timestamp = item["timestamp"] as? String

            let hasContent = title != nil || description != nil || imageURL != nil || thumbnailURL != nil || authorName != nil
            guard hasContent else { return nil }

            return ParsedEmbed(
                color: color, title: title, url: url, description: description,
                imageURL: imageURL, imageWidth: imageWidth, imageHeight: imageHeight,
                thumbnailURL: thumbnailURL, footerText: footerText, footerIconURL: footerIconURL,
                authorName: authorName, authorIconURL: authorIconURL, timestamp: timestamp
            )
        }
    }
}
