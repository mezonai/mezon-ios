import Foundation
import SwiftProtobuf

public struct NotificationRecord: PostboxCoding, Identifiable, Equatable {
    /// ID of the Notification.
    public let id: Int64
    /// Subject of the notification.
    public let subject: String
    /// Decoded text content of the notification.
    public let content: String
    /// Category code for this notification.
    public let code: Int32
    /// ID of the sender, if a user. Otherwise 'null'.
    public let senderID: Int64
    /// The UNIX time when the notification was created.
    public let createTimeSeconds: UInt32
    /// True if this notification was persisted to the database.
    public let persistent: Bool
    /// ID of clan
    public let clanID: Int64
    /// ID of channel
    public let channelID: Int64
    /// mode of
    public let channelType: Int32

    public let avatarURL: String
    /// topic ID
    public let topicID: Int64
    /// category (1: mentions, 2: messages, 3: for you).
    public let category: Int32
    /// ID of the message that triggered this notification.
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
    init(from apiModel: Mezon_Api_Notification) {
        self.id = apiModel.id
        self.subject = apiModel.subject
        self.code = apiModel.code
        self.senderID = apiModel.senderID
        self.createTimeSeconds = apiModel.createTimeSeconds
        self.persistent = apiModel.persistent
        self.channelType = apiModel.channelType
        self.topicID = apiModel.topicID
        self.category = apiModel.category

        let decoded = NotificationRecord.decodeContent(from: apiModel.content)
        self.content = decoded.text
        self.avatarURL = apiModel.avatarURL.isEmpty ? decoded.avatar : apiModel.avatarURL
        self.messageID = decoded.messageID
        self.clanID = decoded.clanID
        self.channelID = decoded.channelID
    }

    private typealias DecodedContent = (text: String, avatar: String, messageID: Int64, clanID: Int64, channelID: Int64)

    //Decode content in notification
    private static func decodeContent(from data: Data) -> DecodedContent {
        guard !data.isEmpty else { return ("", "", 0, 0, 0) }
        if let channelMessage = try? Mezon_Api_DirectFcmProto(serializedBytes: data) {
            let jsonString = channelMessage.content
            let text: String
            if let jsonData = jsonString.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let t = json["t"] as? String
            {
                text = t
            } else {
                text = jsonString
            }
            return (text, channelMessage.avatar, channelMessage.messageID, channelMessage.clanID, channelMessage.channelID)
        }
        return (String(data: data, encoding: .utf8) ?? "", "", 0, 0, 0)
    }
}
