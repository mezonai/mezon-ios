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
        return trimmed
    }

    private static func extractText(fromJSONObject obj: [String: Any]) -> String? {
        if let t = obj["t"] as? String, !t.isEmpty {
            return t
        }
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
            return (
                text, channelMessage.avatar, channelMessage.messageID, channelMessage.clanID,
                channelMessage.channelID
            )
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
        let clanID = parseInt64(obj["clan_id"]) ?? parseInt64(obj["clanId"]) ?? 0
        let channelID = parseInt64(obj["channel_id"]) ?? parseInt64(obj["channelId"]) ?? 0
        return (text, avatar, messageID, clanID, channelID)
    }
}
