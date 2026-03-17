import Foundation
import SwiftProtobuf

struct ParsedContent {
    let text: String
    let tokens: [ContentToken]

    static let empty = ParsedContent(text: "", tokens: [])

    var isPlainText: Bool { tokens.isEmpty }
}

enum ContentTokenKind {
    case emoji(emojiId: String)
    case mention(userId: String?, roleId: String?, username: String?)
    case hashtag(channelId: String?, clanId: String?, channelLabel: String?)
    case inlineCode
    case codeBlock
    case bold
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
            return ParsedContent(text: str, tokens: [])
        }
        let text = json["t"] as? String ?? json["text"] as? String ?? ""
        guard !text.isEmpty else { return ParsedContent(text: "", tokens: []) }

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

        return ParsedContent(text: text, tokens: tokens)
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
            case "s", "c":      kind = .inlineCode
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
}
