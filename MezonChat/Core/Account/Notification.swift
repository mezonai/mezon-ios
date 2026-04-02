import Foundation
import SwiftProtobuf

struct MezonNotification: PostboxCoding, Identifiable, Equatable {

    let id: Int64

    let subject: String

    let content: String

    let code: Int32

    let senderID: Int64

    let createTimeSeconds: UInt32

    let persistent: Bool

    let clanID: Int64

    let channelID: Int64

    let channelType: Int32

    let avatarURL: String

    let topicID: Int64

    let category: Int32
}
