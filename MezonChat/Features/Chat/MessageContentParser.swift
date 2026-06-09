import Foundation
import SwiftProtobuf


enum EmbedComponentType: Int {
    case button = 1
    case select = 2
    case input = 3
    case datepicker = 4
    case radio = 5
    case animation = 6
    case grid = 7
}

enum EmbedButtonStyle: Int {
    case primary = 1
    case secondary = 2
    case success = 3
    case danger = 4
    case link = 5
}

struct ParsedSelectOption: Equatable {
    let label: String
    let value: String
}

struct ParsedRadioOption: Equatable {
    let label: String
    let value: String
    let name: String?
}

struct ParsedEmbedInputComponent: Equatable {
    let type: EmbedComponentType
    let id: String
    let placeholder: String?
    let inputType: String?
    let isTextarea: Bool
    let defaultValue: String?
    let selectOptions: [ParsedSelectOption]?
    let minOptions: Int?
    let maxOptions: Int?
    let selectedValue: ParsedSelectOption?
    let radioOptions: [ParsedRadioOption]?
    let dateValue: String?
}

struct ParsedEmbedButton: Equatable {
    let id: String
    let label: String
    let style: EmbedButtonStyle
    let url: String?
    let disabled: Bool
}

struct ParsedEmbedActionRow: Equatable {
    let buttons: [ParsedEmbedButton]
}

struct ParsedEmbedField: Equatable {
    let name: String
    let value: String
    let inline: Bool
    let inputComponent: ParsedEmbedInputComponent?
}

struct ParsedEmbed: Equatable {
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
    let actionRows: [ParsedEmbedActionRow]
}

struct ParsedOgpPreview: Equatable {
    let title: String
    let description: String
    let imageURL: String
    let url: String
}

struct ParsedContent {
    let text: String
    let tokens: [ContentToken]
    let embeds: [ParsedEmbed]
    let ogpPreviews: [ParsedOgpPreview]

    static let empty = ParsedContent(text: "", tokens: [], embeds: [], ogpPreviews: [])

    var isPlainText: Bool { tokens.isEmpty && embeds.isEmpty && ogpPreviews.isEmpty }

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

    static func parseLocalCodeBlocks(text: String) -> ParsedContent {
        var tokens: [ContentToken] = []
        let pattern = "(?s)```(.*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in results {
                tokens.append(ContentToken(start: match.range.location, end: NSMaxRange(match.range), kind: .codeBlock))
            }
        }
        return ParsedContent(text: text, tokens: tokens, embeds: [], ogpPreviews: [])
    }

    static func parse(data: Data, mentionsData: Data = Data()) -> ParsedContent {
        guard !data.isEmpty,
              let str = String(data: data, encoding: .utf8),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedContent(text: str, tokens: [], embeds: [], ogpPreviews: [])
        }
        let text = json["t"] as? String ?? json["text"] as? String ?? ""
        let embeds = parseEmbeds(json["embed"], topLevelComponents: json["components"])
        let markdownItems = json["mk"] as? [[String: Any]] ?? []
        let ogpPreviews = parseOgpPreviews(markdownItems, text: text)
        if let embed = json["embed"] {
        }
        if text.isEmpty && embeds.isEmpty && ogpPreviews.isEmpty {
            return ParsedContent(text: "", tokens: [], embeds: [], ogpPreviews: [])
        }
        guard !text.isEmpty else {
            return ParsedContent(text: "", tokens: [], embeds: embeds, ogpPreviews: ogpPreviews)
        }

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

        tokens.append(contentsOf: parseMarkdowns(markdownItems, text: text))

        tokens.sort { $0.start < $1.start }

        let maxLen = text.utf16.count
        tokens = tokens.filter { $0.start >= 0 && $0.end <= maxLen && $0.start < $0.end }

        return ParsedContent(text: text, tokens: tokens, embeds: embeds, ogpPreviews: ogpPreviews)
    }

    private static func parseEmojis(_ items: [[String: Any]]) -> [ContentToken] {
        items.compactMap { item in
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]),
                  let emojiId = emojiIdFromEjItem(item) else { return nil }
            return ContentToken(start: s, end: e, kind: .emoji(emojiId: emojiId))
        }
    }

    private static func emojiIdFromEjItem(_ item: [String: Any]) -> String? {
        if let s = item["emojiid"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != "0" else { return nil }
            return t
        }
        if let s = item["emojiId"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != "0" else { return nil }
            return t
        }
        if let n = item["emojiid"] as? Int, n != 0 { return "\(n)" }
        if let n = item["emojiId"] as? Int, n != 0 { return "\(n)" }
        if let n = item["emojiid"] as? Int64, n != 0 { return "\(n)" }
        if let n = item["emojiId"] as? Int64, n != 0 { return "\(n)" }
        if let n = item["emojiid"] as? Double, n != 0 { return String(Int(n)) }
        if let n = item["emojiId"] as? Double, n != 0 { return String(Int(n)) }
        return nil
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
            let type = item["type"] as? String ?? ""
            if type == "lk_ogp" { return nil }
            guard let s = intValue(item["s"]),
                  let e = intValue(item["e"]),
                  s >= 0, e <= text.utf16.count, s < e else { return nil }
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
            case "lk":
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

    private static func parseOgpPreviews(_ items: [[String: Any]], text: String) -> [ParsedOgpPreview] {
        items.compactMap { item in
            guard (item["type"] as? String) == "lk_ogp" else { return nil }
            let title = stringValue(item["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = stringValue(item["description"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let image = stringValue(item["image"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty, !description.isEmpty, !image.isEmpty else { return nil }

            let url = stringValue(item["url"])?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ogpURLFromText(text, index: intValue(item["index"]))
            guard let url, !url.isEmpty, !isGoogleMapLink(url) else { return nil }
            return ParsedOgpPreview(title: title, description: description, imageURL: image, url: url)
        }
    }

    private static func ogpURLFromText(_ text: String, index: Int?) -> String? {
        guard let index, index >= 0 else { return nil }
        let ns = text as NSString
        guard index < ns.length else { return nil }
        var end = index
        let stop: Set<unichar> = [0x20, 0x0A, 0x0D, 0x09]
        while end < ns.length, !stop.contains(ns.character(at: end)) {
            end += 1
        }
        var cleanEnd = end
        let trailing: Set<unichar> = [0x2C, 0x2E, 0x21, 0x3F, 0x3B, 0x3A]
        while cleanEnd > index, trailing.contains(ns.character(at: cleanEnd - 1)) {
            cleanEnd -= 1
        }
        guard cleanEnd > index else { return nil }
        return ns.substring(with: NSRange(location: index, length: cleanEnd - index))
    }

    private static func isGoogleMapLink(_ link: String) -> Bool {
        let lower = link.lowercased()
        guard let components = URLComponents(string: lower), let host = components.host else {
            return false
        }
        if host == "maps.app.goo.gl" { return true }
        if host == "goo.gl", components.path.hasPrefix("/maps") { return true }
        if host.hasSuffix("google.com"), components.path.hasPrefix("/maps") { return true }
        return lower.contains("google.com/maps")
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

    private static func parseEmbeds(_ value: Any?, topLevelComponents: Any? = nil) -> [ParsedEmbed] {
        let topActionRows = parseActionRows(topLevelComponents)
        guard let arr = value as? [[String: Any]], !arr.isEmpty else {
            if !topActionRows.isEmpty {
                return [ParsedEmbed(
                    color: nil, title: nil, url: nil, description: nil, fields: [],
                    imageURL: nil, imageWidth: nil, imageHeight: nil,
                    thumbnailURL: nil, footerText: nil, footerIconURL: nil,
                    authorName: nil, authorIconURL: nil, timestamp: nil,
                    actionRows: topActionRows
                )]
            }
            return []
        }
        return arr.enumerated().compactMap { (idx, item) -> ParsedEmbed? in
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
                let valueRaw = (f["value"] as? String) ?? ""
                let value = valueRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let inline = (f["inline"] as? Bool) ?? false
                let inputComponent = parseFieldInputComponent(f["inputs"] ?? f["input"])
                if value.isEmpty && inputComponent == nil { return nil }
                return ParsedEmbedField(name: name, value: value, inline: inline, inputComponent: inputComponent)
            } ?? []

            let actionRows = idx == 0 ? topActionRows : []

            let hasContent = title != nil || description != nil || !fields.isEmpty || imageURL != nil || thumbnailURL != nil || authorName != nil || !actionRows.isEmpty
            guard hasContent else { return nil }

            return ParsedEmbed(
                color: color, title: title, url: url, description: description, fields: fields,
                imageURL: imageURL, imageWidth: imageWidth, imageHeight: imageHeight,
                thumbnailURL: thumbnailURL, footerText: footerText, footerIconURL: footerIconURL,
                authorName: authorName, authorIconURL: authorIconURL, timestamp: timestamp,
                actionRows: actionRows
            )
        }
    }


    private static func parseFieldInputComponent(_ value: Any?) -> ParsedEmbedInputComponent? {
        var dict: [String: Any]? = nil
        if let d = value as? [String: Any] {
            dict = d
        } else if let arr = value as? [[String: Any]], let first = arr.first {
            dict = first
        } else if let str = value as? String, let data = str.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = parsed
        }
        guard let dict = dict else { return nil }

        guard let typeRaw = intValue(dict["type"]),
              let type = EmbedComponentType(rawValue: typeRaw) else { return nil }
        let id = (dict["id"] as? String) ?? ""

        switch type {
        case .input:
            let comp = dict["component"] as? [String: Any]
            return ParsedEmbedInputComponent(
                type: .input, id: id,
                placeholder: comp?["placeholder"] as? String,
                inputType: comp?["type"] as? String,
                isTextarea: (comp?["textarea"] as? Bool) ?? false,
                defaultValue: stringifyValue(comp?["defaultValue"]),
                selectOptions: nil, minOptions: nil, maxOptions: nil, selectedValue: nil,
                radioOptions: nil, dateValue: nil
            )

        case .select:
            let comp = dict["component"] as? [String: Any]
            let optionsArray = (comp?["options"] as? [[String: Any]]) ?? (dict["options"] as? [[String: Any]]) ?? (dict["component"] as? [[String: Any]])
            let opts = optionsArray?.compactMap { opt -> ParsedSelectOption? in
                guard let label = stringifyValue(opt["label"] ?? opt["value"]) else { return nil }
                guard let value = stringifyValue(opt["value"]) else { return nil }
                return ParsedSelectOption(label: label, value: value)
            }
            let selValDict = (comp?["valueSelected"] as? [String: Any]) ?? (dict["valueSelected"] as? [String: Any]) ?? (dict["value"] as? [String: Any])
            var selVal: ParsedSelectOption? = nil
            if let sv = selValDict {
                if let label = stringifyValue(sv["label"] ?? sv["value"]), let value = stringifyValue(sv["value"]) {
                    selVal = ParsedSelectOption(label: label, value: value)
                }
            } else if let valStr = stringifyValue(dict["value"] ?? comp?["value"] ?? dict["defaultValue"] ?? comp?["defaultValue"]) {
                if let match = opts?.first(where: { $0.value == valStr }) {
                    selVal = match
                } else {
                    selVal = ParsedSelectOption(label: valStr, value: valStr)
                }
            }
            return ParsedEmbedInputComponent(
                type: .select, id: id,
                placeholder: (comp?["placeholder"] as? String) ?? (dict["placeholder"] as? String),
                inputType: nil, isTextarea: false, defaultValue: nil,
                selectOptions: opts, minOptions: intValue(comp?["min_options"] ?? dict["min_options"]),
                maxOptions: intValue(comp?["max_options"] ?? dict["max_options"]), selectedValue: selVal,
                radioOptions: nil, dateValue: nil
            )

        case .datepicker:
            let comp = dict["component"] as? [String: Any]
            let dateVal = stringifyValue(comp?["value"])
            return ParsedEmbedInputComponent(
                type: .datepicker, id: id,
                placeholder: nil, inputType: nil, isTextarea: false, defaultValue: nil,
                selectOptions: nil, minOptions: nil, maxOptions: nil, selectedValue: nil,
                radioOptions: nil, dateValue: dateVal
            )

        case .radio:
            let compArr = dict["component"] as? [[String: Any]]
            let options = compArr?.compactMap { opt -> ParsedRadioOption? in
                guard let label = stringifyValue(opt["label"] ?? opt["value"]), let value = stringifyValue(opt["value"]) else { return nil }
                return ParsedRadioOption(label: label, value: value, name: opt["name"] as? String)
            }
            let maxOpt = intValue(dict["max_options"])
            let selectedOrDefault = stringifyValue(dict["valueSelected"] ?? dict["value"] ?? dict["defaultValue"])
            return ParsedEmbedInputComponent(
                type: .radio, id: id,
                placeholder: nil, inputType: nil, isTextarea: false, defaultValue: selectedOrDefault,
                selectOptions: nil, minOptions: nil, maxOptions: maxOpt, selectedValue: nil,
                radioOptions: options, dateValue: nil
            )

        default:
            return nil
        }
    }

    private static func stringifyValue(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? Int { return "\(n)" }
        if let d = v as? Double { return "\(d)" }
        return nil
    }


    private static func parseActionRows(_ value: Any?) -> [ParsedEmbedActionRow] {
        guard let arr = value as? [[String: Any]], !arr.isEmpty else { return [] }
        return arr.compactMap { row -> ParsedEmbedActionRow? in
            guard let components = row["components"] as? [[String: Any]], !components.isEmpty else { return nil }
            let buttons = components.compactMap { comp -> ParsedEmbedButton? in
                guard let typeRaw = intValue(comp["type"]),
                      typeRaw == EmbedComponentType.button.rawValue else { return nil }
                let id = (comp["id"] as? String) ?? ""
                guard let buttonDict = comp["component"] as? [String: Any] else { return nil }
                let label = (buttonDict["label"] as? String) ?? ""
                let styleRaw = intValue(buttonDict["style"]) ?? EmbedButtonStyle.primary.rawValue
                let style = EmbedButtonStyle(rawValue: styleRaw) ?? .primary
                let url = buttonDict["url"] as? String
                let disabled = (buttonDict["disable"] as? Bool) ?? false
                return ParsedEmbedButton(id: id, label: label, style: style, url: url, disabled: disabled)
            }
            guard !buttons.isEmpty else { return nil }
            return ParsedEmbedActionRow(buttons: buttons)
        }
    }
}

enum PresignFinishContent {
    static let fieldKey = "presign_finish"

    static func parseKeys(from contentData: Data) -> [String]? {
        guard !contentData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              json[fieldKey] != nil else { return nil }
        return json[fieldKey] as? [String] ?? []
    }

    static func presignKey(from cdnURL: String) -> String {
        let trimmed = cdnURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let noQuery = trimmed.split(separator: "?", maxSplits: 1).first.map(String.init) ?? trimmed
        let last = (noQuery as NSString).lastPathComponent
        guard !last.isEmpty else { return "" }
        let withoutExt = (last as NSString).deletingPathExtension
        return withoutExt.isEmpty ? last : withoutExt
    }

    static func isAttachmentReady(url: String, presignFinish: [String]?) -> Bool {
        guard let presignFinish else { return true }
        let key = presignKey(from: url)
        guard !key.isEmpty else { return false }
        return presignFinish.contains(key)
    }

    static func injectPresignFinish(into contentData: Data, keys: [String]) -> Data {
        var json: [String: Any] = [:]
        if !contentData.isEmpty,
           let existing = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
            json = existing
        }
        json[fieldKey] = keys
        return (try? JSONSerialization.data(withJSONObject: json)) ?? contentData
    }

    static func injectEmptyPresignFinish(into contentData: Data) -> Data {
        injectPresignFinish(into: contentData, keys: [])
    }

    static func presignFinishOnlyContent(keys: [String]) -> Data {
        injectPresignFinish(into: Data(), keys: keys)
    }

    static func presignFinishOnlyString(keys: [String]) -> String {
        String(data: presignFinishOnlyContent(keys: keys), encoding: .utf8) ?? "{\"presign_finish\":[]}"
    }

    static func isPresignOnlyPayload(_ contentData: Data) -> Bool {
        guard !contentData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              json[fieldKey] != nil else { return false }
        return json.keys.allSatisfy { $0 == fieldKey }
    }

    static func hasPresignFinishField(in contentData: Data) -> Bool {
        guard !contentData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else { return false }
        return json[fieldKey] != nil
    }

    static func contentBaseWithoutPresign(_ contentData: Data) -> Data {
        guard !contentData.isEmpty,
              var json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            return contentData
        }
        json.removeValue(forKey: fieldKey)
        return (try? JSONSerialization.data(withJSONObject: json)) ?? contentData
    }

    static func mergePresignFinishContent(local: Data, server: Data) -> Data {
        let localKeys = parseKeys(from: local) ?? []
        let serverKeys = parseKeys(from: server) ?? []
        if localKeys.isEmpty && serverKeys.isEmpty {
            return server.isEmpty ? local : server
        }
        let mergedKeys: [String]
        if serverKeys.count >= localKeys.count {
            mergedKeys = serverKeys
        } else {
            var keys = localKeys
            for key in serverKeys where !keys.contains(key) {
                keys.append(key)
            }
            mergedKeys = keys
        }
        let base: Data
        if isPresignOnlyPayload(server), !local.isEmpty {
            base = contentBaseWithoutPresign(local)
        } else if !server.isEmpty {
            base = contentBaseWithoutPresign(server)
        } else {
            base = contentBaseWithoutPresign(local)
        }
        return injectPresignFinish(into: base, keys: mergedKeys)
    }

    static func isPresignFinishOnlyChange(newContent: Data, oldContent: Data) -> Bool {
        guard !newContent.isEmpty, !oldContent.isEmpty,
              let newJson = try? JSONSerialization.jsonObject(with: newContent) as? [String: Any],
              let oldJson = try? JSONSerialization.jsonObject(with: oldContent) as? [String: Any],
              newJson[fieldKey] != nil else { return false }
        var newCopy = newJson
        var oldCopy = oldJson
        newCopy.removeValue(forKey: fieldKey)
        oldCopy.removeValue(forKey: fieldKey)
        return NSDictionary(dictionary: newCopy).isEqual(to: oldCopy)
    }
}
