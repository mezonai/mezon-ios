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
            let cn = api.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cn.isEmpty { return cn }
            let dn = api.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dn.isEmpty { return dn }
            let un = api.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !un.isEmpty { return un }
            return "\(api.senderID)"
        }()
        let avatarURL: String? = {
            let ca = api.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ca.isEmpty { return ca }
            let av = api.avatar.trimmingCharacters(in: .whitespacesAndNewlines)
            if !av.isEmpty { return av }
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
        mentionsData: Data = Data(),
        contentData: Data? = nil
    ) -> MessageRecord {
        let contentDataResolved = contentData
            ?? ((try? JSONSerialization.data(withJSONObject: ["t": text])) ?? Data())
        let resolvedName: String = {
            if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return d }
            let sdn = sender.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sdn.isEmpty { return sdn }
            let sun = sender.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sun.isEmpty { return sun }
            return sender.id
        }()
        let resolvedAvatar: String? = {
            if let a = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { return a }
            return sender.avatarURL?.absoluteString
        }()
        return MessageRecord(
            id:                localId,
            channelId:         channelId,
            clanId:            clanId == 0 ? nil : "\(clanId)",
            senderId:          sender.id,
            content:           contentDataResolved,
            createdAt:         Date(),
            senderDisplayName: resolvedName,
            senderAvatarURL:   resolvedAvatar,
            sendingState:      .pending,
            referencesData:    referencesData,
            mentionsJSON:      mentionsData
        )
    }
}
