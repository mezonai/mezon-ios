import Foundation
import SwiftProtobuf

public struct NotificationRecord: PostboxCoding, Identifiable, Equatable {

    public let id: Int64

    public let subject: String

    public let content: String

    public let code: Int32

    public let senderID: Int64

    public let createTimeSeconds: UInt32

    public let persistent: Bool

    public let clanID: Int64

    public let channelID: Int64

    public let channelType: Int32

    public let avatarURL: String

    public let topicID: Int64

    public let category: Int32

    public let messageID: Int64

    public init(
        id: Int64,
        subject: String,
        content: String,
        code: Int32,
        senderID: Int64,
        createTimeSeconds: UInt32,
        persistent: Bool,
        clanID: Int64,
        channelID: Int64,
        channelType: Int32,
        avatarURL: String,
        topicID: Int64,
        category: Int32,
        messageID: Int64 = 0
    ) {
        self.id = id
        self.subject = subject
        self.content = content
        self.code = code
        self.senderID = senderID
        self.createTimeSeconds = createTimeSeconds
        self.persistent = persistent
        self.clanID = clanID
        self.channelID = channelID
        self.channelType = channelType
        self.avatarURL = avatarURL
        self.topicID = topicID
        self.category = category
        self.messageID = messageID
    }
}

extension NotificationRecord {

    public var previewText: String {
        Self.extractDisplayText(from: content)
    }

    init(from apiModel: Mezon_Api_Notification) {
        self.id = apiModel.id
        self.subject = apiModel.subject
        self.code = apiModel.code
        self.senderID = apiModel.senderID
        self.createTimeSeconds = apiModel.createTimeSeconds
        self.persistent = apiModel.persistent
        self.topicID = apiModel.topicID
        self.category = apiModel.category

        if apiModel.channelType != 0 {
            self.channelType = apiModel.channelType
        } else if apiModel.hasChannel {
            self.channelType = apiModel.channel.type
        } else {
            self.channelType = 0
        }

        let decoded = NotificationRecord.decodeContent(from: apiModel.content)
        self.content = decoded.text
        self.avatarURL = apiModel.avatarURL.isEmpty ? decoded.avatar : apiModel.avatarURL
        self.messageID = decoded.messageID
        self.clanID = Self.mergeID(decoded: decoded.clanID, direct: apiModel.clanID, nested: apiModel.hasChannel ? apiModel.channel.clanID : 0)
        self.channelID = Self.mergeID(decoded: decoded.channelID, direct: apiModel.channelID, nested: apiModel.hasChannel ? apiModel.channel.channelID : 0)
    }

    private typealias DecodedContent = (text: String, avatar: String, messageID: Int64, clanID: Int64, channelID: Int64)

    private static func mergeID(decoded: Int64, direct: Int64, nested: Int64) -> Int64 {
        if decoded != 0 { return decoded }
        if direct != 0 { return direct }
        return nested
    }

    static func extractDisplayText(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.first == "{" || trimmed.first == "[" else { return trimmed }
        guard let data = trimmed.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return trimmed
        }
        if let extracted = extractText(fromJSONObject: obj), !extracted.isEmpty {
            return extracted
        }
        if obj["embed"] != nil || obj["embeds"] != nil {
            return ""
        }
        if obj["t"] is String || obj["text"] is String {
            return ""
        }
        return trimmed
    }

    private static func extractText(fromJSONObject obj: [String: Any]) -> String? {
        if let t = obj["t"] as? String {
            let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { return x }
        }
        if let t = obj["text"] as? String {
            let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { return x }
        }
        if let embedLine = extractEmbedSummary(from: obj["embed"]) { return embedLine }
        if let embedLine = extractEmbedSummary(from: obj["embeds"]) { return embedLine }
        guard let contentVal = obj["content"] else { return nil }
        if let nestedString = contentVal as? String {
            let out = extractDisplayText(from: nestedString)
            return out.isEmpty ? nil : out
        }
        if let inner = contentVal as? [String: Any] {
            return extractText(fromJSONObject: inner)
        }
        return nil
    }

    private static func extractEmbedSummary(from value: Any?) -> String? {
        let items: [[String: Any]]
        if let arr = value as? [[String: Any]] {
            items = arr
        } else if let one = value as? [String: Any] {
            items = [one]
        } else {
            return nil
        }
        guard let first = items.first else { return nil }
        var parts: [String] = []
        if let s = first["title"] as? String {
            let x = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { parts.append(x) }
        }
        if let s = first["description"] as? String {
            let x = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { parts.append(x) }
        }
        if let author = first["author"] as? [String: Any], let s = author["name"] as? String {
            let x = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { parts.append(x) }
        }
        if let footer = first["footer"] as? [String: Any], let s = footer["text"] as? String {
            let x = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { parts.append(x) }
        } else if let s = first["footer"] as? String {
            let x = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !x.isEmpty { parts.append(x) }
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: " ")
        if joined.count > 220 {
            return String(joined.prefix(220)) + "…"
        }
        return joined
    }

    private static func parseInt64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber {
            return n.int64Value
        }
        if let i = value as? Int64 {
            return i
        }
        if let i = value as? Int {
            return Int64(i)
        }
        if let s = value as? String {
            return Int64(s)
        }
        return nil
    }

    private static func decodeContent(from data: Data) -> DecodedContent {
        guard !data.isEmpty else { return ("", "", 0, 0, 0) }
        if let channelMessage = try? Mezon_Api_DirectFcmProto(serializedBytes: data) {
            let jsonString = channelMessage.content
            let text = extractDisplayText(from: jsonString)
            let base: DecodedContent = (
                text, channelMessage.avatar, channelMessage.messageID, channelMessage.clanID,
                channelMessage.channelID
            )
            var merged = base
            if !channelMessage.link.isEmpty {
                let linkIds = Self.parseRoutingIds(fromLink: channelMessage.link)
                merged = Self.mergeDecodedContent(
                    merged,
                    (merged.text, merged.avatar, merged.messageID, linkIds.clanID, linkIds.channelID)
                )
            }
            if !jsonString.isEmpty {
                let trimmedJson = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedJson.first == "{" {
                    merged = Self.mergeDecodedContent(merged, Self.decodeJsonPayload(jsonString))
                }
            }
            return merged
        }
        guard let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty else {
            return ("", "", 0, 0, 0)
        }
        let trimmed = utf8.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" {
            return decodeJsonPayload(utf8)
        }
        return (utf8, "", 0, 0, 0)
    }

    private static func mergeDecodedContent(_ a: DecodedContent, _ b: DecodedContent) -> DecodedContent {
        (
            a.text.isEmpty ? b.text : a.text,
            a.avatar.isEmpty ? b.avatar : a.avatar,
            a.messageID != 0 ? a.messageID : b.messageID,
            a.clanID != 0 ? a.clanID : b.clanID,
            a.channelID != 0 ? a.channelID : b.channelID
        )
    }

    private static func parseRoutingIds(fromLink link: String) -> (clanID: Int64, channelID: Int64) {
        var clanID: Int64 = 0
        var channelID: Int64 = 0
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return (0, 0) }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(of: "clans"), i + 1 < parts.count {
            clanID = Int64(parts[i + 1]) ?? 0
        }
        for seg in ["channels", "channel", "direct", "dm", "c"] {
            if let i = parts.firstIndex(of: seg), i + 1 < parts.count, channelID == 0 {
                channelID = Int64(parts[i + 1]) ?? 0
            }
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                let n = item.name.lowercased()
                guard let v = item.value, let id = Int64(v) else { continue }
                if channelID == 0, n.contains("channel") || n == "cid" || n == "c" { channelID = id }
                if clanID == 0, n.contains("clan") || n.contains("guild") { clanID = id }
            }
        }
        return (clanID, channelID)
    }

    private static func decodeJsonPayload(_ raw: String) -> DecodedContent {
        guard let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (extractDisplayText(from: raw), "", 0, 0, 0)
        }
        let text = extractText(fromJSONObject: obj) ?? extractDisplayText(from: raw)
        let avatar = (obj["avatar"] as? String) ?? ""
        let messageID =
            parseInt64(obj["message_id"]) ?? parseInt64(obj["messageId"]) ?? parseInt64(obj["messageID"])
            ?? 0
        var clanID =
            parseInt64(obj["clan_id"]) ?? parseInt64(obj["clanId"]) ?? parseInt64(obj["clanID"]) ?? 0
        var channelID =
            parseInt64(obj["channel_id"]) ?? parseInt64(obj["channelId"]) ?? parseInt64(obj["channelID"])
            ?? 0
        if channelID == 0 {
            channelID =
                parseInt64(obj["channel"]) ?? parseInt64(obj["cid"]) ?? parseInt64(obj["c"])
                ?? parseInt64(obj["message_channel_id"]) ?? parseInt64(obj["messageChannelId"])
                ?? parseInt64(obj["target_channel_id"]) ?? parseInt64(obj["targetChannelId"]) ?? 0
        }
        if let ch = obj["channel"] as? [String: Any] {
            if channelID == 0 {
                channelID =
                    parseInt64(ch["channel_id"]) ?? parseInt64(ch["channelId"])
                    ?? parseInt64(ch["channelID"]) ?? parseInt64(ch["id"]) ?? 0
            }
            if clanID == 0 {
                clanID =
                    parseInt64(ch["clan_id"]) ?? parseInt64(ch["clanId"]) ?? parseInt64(ch["clanID"])
                    ?? 0
            }
        } else if let chStr = obj["channel"] as? String {
            if channelID == 0 {
                channelID = Int64(chStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }
        if let link =
            (obj["link"] as? String) ?? (obj["deep_link"] as? String)
            ?? (obj["deepLink"] as? String),
            !link.isEmpty
        {
            let rid = parseRoutingIds(fromLink: link)
            if channelID == 0 { channelID = rid.channelID }
            if clanID == 0 { clanID = rid.clanID }
        }
        return (text, avatar, messageID, clanID, channelID)
    }
}
