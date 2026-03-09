import Foundation
import SwiftProtobuf

struct Notifications: Codable, Identifiable {
    /// ID of the Notification.
    let id: Int64
    /// Subject of the notification.
    let subject: String
    /// Decoded text content of the notification.
    let content: String
    /// Category code for this notification.
    let code: Int32
    /// ID of the sender, if a user. Otherwise 'null'.
    let senderID: Int64
    /// The UNIX time when the notification was created.
    let createTimeSeconds: UInt32
    /// True if this notification was persisted to the database.
    let persistent: Bool
    /// ID of clan
    let clanID: Int64
    /// ID of channel
    let channelID: Int64
    /// mode of
    let channelType: Int32

    let avatarURL: String
    /// topic ID
    let topicID: Int64
    /// category (1: mentions, 2: messages, 3: for you).
    let category: Int32
}

extension Notifications {
    init(from apiModel: Mezon_Api_Notification) {
        self.id = apiModel.id
        self.subject = apiModel.subject
        self.code = apiModel.code
        self.senderID = apiModel.senderID
        self.createTimeSeconds = apiModel.createTimeSeconds
        self.persistent = apiModel.persistent
        self.clanID = apiModel.clanID
        self.channelID = apiModel.channelID
        self.channelType = apiModel.channelType
        self.topicID = apiModel.topicID
        self.category = apiModel.category

        let decoded = Notifications.decodeContent(from: apiModel.content)
        self.content = decoded.text
        self.avatarURL = apiModel.avatarURL.isEmpty ? decoded.avatar : apiModel.avatarURL
    }

    private typealias DecodedContent = (text: String, avatar: String)

    //Decode content in notification
    private static func decodeContent(from data: Data) -> DecodedContent {
        guard !data.isEmpty else { return ("", "") }
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
            return (text, channelMessage.avatar)
        }
        return (String(data: data, encoding: .utf8) ?? "", "")
    }
}
