import Foundation
import SwiftProtobuf

enum SendingState: Int32, Codable {
    case pending = 0
    case sent    = 1
    case failed  = 2
}

struct MessageRecord: PostboxCoding, Equatable {

    let id: String
    let channelId: String
    let clanId: String?

    let senderId: String
    let content: Data
    let createdAt: Date
    let editedAt: Date?
    let isDeleted: Bool

    let senderDisplayName: String
    let senderAvatarURL: String?

    let sendingState: SendingState

    init(
        id: String,
        channelId: String,
        clanId: String?,
        senderId: String,
        content: Data,
        createdAt: Date,
        editedAt: Date? = nil,
        isDeleted: Bool = false,
        senderDisplayName: String = "",
        senderAvatarURL: String? = nil,
        sendingState: SendingState = .sent
    ) {
        self.id                = id
        self.channelId         = channelId
        self.clanId            = clanId
        self.senderId          = senderId
        self.content           = content
        self.createdAt         = createdAt
        self.editedAt          = editedAt
        self.isDeleted         = isDeleted
        self.senderDisplayName = senderDisplayName
        self.senderAvatarURL   = senderAvatarURL
        self.sendingState      = sendingState
    }
}

extension MessageRecord {

    init(from api: Mezon_Api_ChannelMessage) {
        let contentData = api.content.data(using: .utf8) ?? Data()
        let createdAt   = Date(timeIntervalSince1970: TimeInterval(api.createTimeSeconds))
        let displayName: String = {
            if !api.clanNick.isEmpty    { return api.clanNick }
            if !api.displayName.isEmpty { return api.displayName }
            if !api.username.isEmpty    { return api.username }
            return "\(api.senderID)"
        }()
        let avatarURL: String? = {
            if !api.clanAvatar.isEmpty { return api.clanAvatar }
            if !api.avatar.isEmpty     { return api.avatar }
            return nil
        }()
        self.init(
            id:                "\(api.messageID)",
            channelId:         "\(api.channelID)",
            clanId:            "\(api.clanID)",
            senderId:          "\(api.senderID)",
            content:           contentData,
            createdAt:         createdAt,
            senderDisplayName: displayName,
            senderAvatarURL:   avatarURL,
            sendingState:      .sent
        )
    }

    static func pending(
        localId: String,
        text: String,
        channelId: String,
        clanId: Int64,
        sender: User
    ) -> MessageRecord {
        let contentData = (try? JSONSerialization.data(withJSONObject: ["t": text])) ?? Data()
        return MessageRecord(
            id:                localId,
            channelId:         channelId,
            clanId:            clanId == 0 ? nil : "\(clanId)",
            senderId:          sender.id,
            content:           contentData,
            createdAt:         Date(),
            senderDisplayName: sender.displayName,
            senderAvatarURL:   sender.avatarURL?.absoluteString,
            sendingState:      .pending
        )
    }
}
