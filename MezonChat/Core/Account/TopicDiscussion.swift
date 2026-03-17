import Foundation
import SwiftProtobuf

public struct Topic: PostboxCoding, Equatable {
    public let id: Int64
    public let channelID: Int64
    public let clanID: Int64
    public let creatorID: Int64
    public let content: String
    public let updateTimeSeconds: UInt32
    public let lastSentMessageContent: String

    init(from proto: Mezon_Api_SdTopic) {
        self.id = proto.id
        self.channelID = proto.channelID
        self.clanID = proto.clanID
        self.creatorID = proto.creatorID
        self.content = proto.content
        self.updateTimeSeconds = proto.updateTimeSeconds
        self.lastSentMessageContent = proto.hasLastSentMessage ? proto.lastSentMessage.content : ""
    }

    public init(
        id: Int64,
        channelID: Int64,
        clanID: Int64,
        creatorID: Int64,
        content: String,
        updateTimeSeconds: UInt32,
        lastSentMessageContent: String
    ) {
        self.id = id
        self.channelID = channelID
        self.clanID = clanID
        self.creatorID = creatorID
        self.content = content
        self.updateTimeSeconds = updateTimeSeconds
        self.lastSentMessageContent = lastSentMessageContent
    }
}
