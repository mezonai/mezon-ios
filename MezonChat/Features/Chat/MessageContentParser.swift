import Foundation
import SwiftProtobuf

struct ParsedEmbedField: Equatable {
    let name: String
    let value: String
}

struct ParsedEmbed {
    let color: String?
    let title: String?
    let url: String?
    let description: String?
    let fields: [ParsedEmbedField]
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
        let emojiTokens = tokens.filter {
            if case .emoji = $0.kind { return true }
            return false
        }
        guard emojiTokens.count == tokens.count else { return false }
        let len = text.utf16.count
        var gaps: [String] = []
        var cursor = 0
        for token in emojiTokens.sorted(by: { $0.start < $1.start }) {
            guard token.start >= 0, token.end <= len, token.start < token.end else { return false }
            if cursor < token.start {
                gaps.append(text.mezon_utf16Substring(from: cursor, to: token.start))
            }
            cursor = max(cursor, token.end)
        }
        if cursor < len {
            gaps.append(text.mezon_utf16Substring(from: cursor, to: len))
        }
        return gaps.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum ContentTokenKind: Equatable {
    case emoji(emojiId: String)
    case mention(userId: String?, roleId: String?, username: String?)
    case hashtag(channelId: String?, clanId: String?, channelLabel: String?, channelType: Int32?, channelPrivate: Int32?, ageRestricted: Int32?)
    case mezonChannelLink(isVoiceLinkMarkdown: Bool, channelId: String, clanId: String)
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
                guard token.start >= 0, token.end <= text.utf16.count else { return false }
                let i = String.Index(utf16Offset: token.start, in: text)
                guard i < text.endIndex else { return false }
                return text[i] == "@"
            }
            tokens.append(contentsOf: validMentions)
        }

        if let hg = json["hg"] as? [[String: Any]] {
            tokens.append(contentsOf: parseHashtags(hg))
        }

        if let mk = json["mk"] as? [[String: Any]] {
            tokens.append(contentsOf: parseMarkdowns(mk, text: text))
        }

        tokens.sort { $0.start < $1.start }

        let maxLen = text.utf16.count
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

    private static func int32Value(_ v: Any?) -> Int32? {
        guard let i = intValue(v) else { return nil }
        return Int32(i)
    }

    private static func parseHashtags(_ items: [[String: Any]]) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]) else { return nil }
            let channelId = stringValue(item["channelId"]) ?? stringValue(item["channelid"])
            let clanId = stringValue(item["clanId"])
            let channelLabel = stringValue(item["channelLabel"]) ?? stringValue(item["channelIabel"])
            let channelType = int32Value(item["channelType"]) ?? int32Value(item["type"])
            let channelPrivate = int32Value(item["channelPrivate"]) ?? 0
            let ageRestricted = int32Value(item["ageRestricted"]) ?? 0
            return ContentToken(
                start: s, end: e,
                kind: .hashtag(
                    channelId: channelId, clanId: clanId, channelLabel: channelLabel,
                    channelType: channelType, channelPrivate: channelPrivate, ageRestricted: ageRestricted
                )
            )
        }
    }

    private static func parseMarkdowns(_ items: [[String: Any]], text: String) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]),
                  s >= 0, e <= text.utf16.count, s < e else { return nil }
            let type = item["type"] as? String ?? ""
            let slice = text.mezon_utf16Substring(from: s, to: e)
            let mkChannelId = normalizedMkId(item["channelId"]) ?? normalizedMkId(item["channelid"])
            let mkClanId = normalizedMkId(item["clanId"]) ?? ""

            switch type {
            case "c":
                return ContentToken(start: s, end: e, kind: .inlineCode)
            case "s":
                return ContentToken(start: s, end: e, kind: .strikethrough)
            case "t", "pre":
                return ContentToken(start: s, end: e, kind: .codeBlock)
            case "b":
                return ContentToken(start: s, end: e, kind: .bold)
            case "lk_yt", "lk_fb", "lk_tt":
                return ContentToken(start: s, end: e, kind: .link)
            case "vk":
                if isMezonChatChannelPageURL(slice),
                   let pair = resolveMezonChannelIds(slice: slice, mkChannelId: mkChannelId, mkClanId: mkClanId) {
                    return ContentToken(
                        start: s, end: e,
                        kind: .mezonChannelLink(isVoiceLinkMarkdown: true, channelId: pair.channelId, clanId: pair.clanId))
                }
                return ContentToken(start: s, end: e, kind: .link)
            case "lk", "lk_ogp":
                if isMezonChatChannelPageURL(slice),
                   let pair = resolveMezonChannelIds(slice: slice, mkChannelId: mkChannelId, mkClanId: mkClanId) {
                    return ContentToken(
                        start: s, end: e,
                        kind: .mezonChannelLink(isVoiceLinkMarkdown: false, channelId: pair.channelId, clanId: pair.clanId))
                }
                return ContentToken(start: s, end: e, kind: .link)
            default:
                return ContentToken(start: s, end: e, kind: .bold)
            }
        }
    }

    private static func isMezonChatChannelPageURL(_ slice: String) -> Bool {
        let lower = slice.lowercased()
        guard lower.contains("/chat/clans/"), lower.contains("/channels/") else { return false }
        guard !lower.contains("/canvas/") else { return false }
        return true
    }

    private static func resolveMezonChannelIds(slice: String, mkChannelId: String?, mkClanId: String) -> (channelId: String, clanId: String)? {
        if let c = mkChannelId, !c.isEmpty {
            return (c, mkClanId)
        }
        return extractClanAndChannelIdsFromMezonChatURL(slice)
    }

    private static func extractClanAndChannelIdsFromMezonChatURL(_ url: String) -> (channelId: String, clanId: String)? {
        guard let clanRe = try? NSRegularExpression(pattern: #"/clans/(\d+)/"#, options: []),
              let chanRe = try? NSRegularExpression(pattern: #"/channels/(\d+)"#, options: []) else { return nil }
        let ns = url as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let cm = clanRe.firstMatch(in: url, options: [], range: full),
              cm.numberOfRanges >= 2,
              let chm = chanRe.firstMatch(in: url, options: [], range: full),
              chm.numberOfRanges >= 2 else { return nil }
        let clan = ns.substring(with: cm.range(at: 1))
        let chan = ns.substring(with: chm.range(at: 1))
        guard !clan.isEmpty, !chan.isEmpty else { return nil }
        return (chan, clan)
    }

    private static func intValue(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func normalizedMkId(_ v: Any?) -> String? {
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != "0" else { return nil }
            return t
        }
        if let i = v as? Int, i != 0 { return "\(i)" }
        if let d = v as? Double, d != 0 { return String(Int(d)) }
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

            let fields: [ParsedEmbedField] = (item["fields"] as? [[String: Any]])?.compactMap { f in
                let name = ((f["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let valueRaw = f["value"] as? String else { return nil }
                let value = valueRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                return ParsedEmbedField(name: name, value: value)
            } ?? []

            let hasContent = title != nil || description != nil || !fields.isEmpty || imageURL != nil || thumbnailURL != nil || authorName != nil
            guard hasContent else { return nil }

            return ParsedEmbed(
                color: color, title: title, url: url, description: description, fields: fields,
                imageURL: imageURL, imageWidth: imageWidth, imageHeight: imageHeight,
                thumbnailURL: thumbnailURL, footerText: footerText, footerIconURL: footerIconURL,
                authorName: authorName, authorIconURL: authorIconURL, timestamp: timestamp
            )
        }
    }
}
