import Foundation
import SwiftProtobuf

public struct TopicRecord: PostboxCoding, Identifiable, Equatable {
    public let id: Int64
    public let channelID: Int64
    public let clanID: Int64
    public let messageID: Int64
    public let creatorID: Int64
    public let lastSenderID: Int64
    public let senderAvatarURL: String
    public let senderDisplayName: String
    public let content: String
    public let updateTimeSeconds: UInt32
    public let lastSentMessageContent: String
    public let rootMessageCode: Int32
    public let rootHasAttachment: Bool

    init(from proto: Mezon_Api_SdTopic) {
        self.id = proto.id
        self.channelID = proto.channelID
        self.clanID = proto.clanID
        self.messageID = proto.messageID
        self.creatorID = proto.creatorID
        let replySender = proto.hasLastSentMessage ? proto.lastSentMessage.senderID : 0
        self.lastSenderID = replySender != 0 ? replySender : proto.creatorID
        self.senderAvatarURL = ""
        self.senderDisplayName = ""
        self.content = proto.content
        self.updateTimeSeconds = proto.createTimeSeconds
        self.lastSentMessageContent = proto.hasLastSentMessage ? proto.lastSentMessage.content : ""
        self.rootMessageCode = 0
        self.rootHasAttachment = false
    }

    public init(
        id: Int64,
        channelID: Int64,
        clanID: Int64,
        messageID: Int64 = 0,
        creatorID: Int64,
        lastSenderID: Int64 = 0,
        senderAvatarURL: String = "",
        senderDisplayName: String = "",
        content: String,
        updateTimeSeconds: UInt32,
        lastSentMessageContent: String,
        rootMessageCode: Int32 = 0,
        rootHasAttachment: Bool = false
    ) {
        self.id = id
        self.channelID = channelID
        self.clanID = clanID
        self.messageID = messageID
        self.creatorID = creatorID
        self.lastSenderID = lastSenderID != 0 ? lastSenderID : creatorID
        self.senderAvatarURL = senderAvatarURL
        self.senderDisplayName = senderDisplayName
        self.content = content
        self.updateTimeSeconds = updateTimeSeconds
        self.lastSentMessageContent = lastSentMessageContent
        self.rootMessageCode = rootMessageCode
        self.rootHasAttachment = rootHasAttachment
    }
}
