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
    let code: Int32

    let senderDisplayName: String
    let senderAvatarURL: String?

    let sendingState: SendingState

    let attachmentsJSON: Data
    let reactionsJSON: Data
    let referencesData: Data
    let mentionsJSON: Data

    init(
        id: String,
        channelId: String,
        clanId: String?,
        senderId: String,
        content: Data,
        createdAt: Date,
        editedAt: Date? = nil,
        isDeleted: Bool = false,
        code: Int32 = 0,
        senderDisplayName: String = "",
        senderAvatarURL: String? = nil,
        sendingState: SendingState = .sent,
        attachmentsJSON: Data = Data(),
        reactionsJSON: Data = Data(),
        referencesData: Data = Data(),
        mentionsJSON: Data = Data()
    ) {
        self.id                = id
        self.channelId         = channelId
        self.clanId            = clanId
        self.senderId          = senderId
        self.content           = content
        self.createdAt         = createdAt
        self.editedAt          = editedAt
        self.isDeleted         = isDeleted
        self.code              = code
        self.senderDisplayName = senderDisplayName
        self.senderAvatarURL   = senderAvatarURL
        self.sendingState      = sendingState
        self.attachmentsJSON   = attachmentsJSON
        self.reactionsJSON     = reactionsJSON
        self.referencesData    = referencesData
        self.mentionsJSON      = mentionsJSON
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
        let channelId = api.topicID != 0 ? "topic-\(api.topicID)" : "\(api.channelID)"
        self.init(
            id:                "\(api.messageID)",
            channelId:         channelId,
            clanId:            "\(api.clanID)",
            senderId:          "\(api.senderID)",
            content:           contentData,
            createdAt:         createdAt,
            code:              api.code,
            senderDisplayName: displayName,
            senderAvatarURL:   avatarURL,
            sendingState:      .sent,
            attachmentsJSON:   api.attachments,
            reactionsJSON:     api.reactions,
            referencesData:    api.references,
            mentionsJSON:      api.mentions
        )
    }

    static func pending(
        localId: String,
        text: String,
        channelId: String,
        clanId: Int64,
        sender: User,
        displayName: String? = nil,
        avatarURL: String? = nil,
        referencesData: Data = Data(),
        mentionsData: Data = Data()
    ) -> MessageRecord {
        let contentData = (try? JSONSerialization.data(withJSONObject: ["t": text])) ?? Data()
        let resolvedName = displayName ?? sender.displayName
        let resolvedAvatar = avatarURL ?? sender.avatarURL?.absoluteString
        return MessageRecord(
            id:                localId,
            channelId:         channelId,
            clanId:            clanId == 0 ? nil : "\(clanId)",
            senderId:          sender.id,
            content:           contentData,
            createdAt:         Date(),
            senderDisplayName: resolvedName,
            senderAvatarURL:   resolvedAvatar,
            sendingState:      .pending,
            referencesData:    referencesData,
            mentionsJSON:      mentionsData
        )
    }
}
