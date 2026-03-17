import Foundation
import SwiftProtobuf

struct Notification: PostboxCoding, Identifiable, Equatable {
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
