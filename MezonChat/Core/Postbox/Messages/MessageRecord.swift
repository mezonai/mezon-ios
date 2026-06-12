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
    var editedAt: Date?
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

    init(from api: Mezon_Api_ChannelMessage, customId: String? = nil) {
        let contentData = api.content.data(using: .utf8) ?? Data()
        let parsedPoll = PollData.parse(from: contentData)
        let isPoll = api.code == 18 || parsedPoll != nil
        
        let createdAt   = Date(timeIntervalSince1970: TimeInterval(api.createTimeSeconds))
        let isClanContext = api.clanID != 0
        let displayName: String = {
            if isClanContext {
                let cn = api.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cn.isEmpty { return cn }
            }
            let dn = api.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dn.isEmpty { return dn }
            let un = api.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !un.isEmpty { return un }
            return "\(api.senderID)"
        }()
        let avatarURL: String? = {
            if isClanContext {
                let ca = api.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ca.isEmpty { return ca }
            }
            let av = api.avatar.trimmingCharacters(in: .whitespacesAndNewlines)
            if !av.isEmpty { return av }
            return nil
        }()
        let channelId = api.topicID != 0 ? "topic-\(api.topicID)" : "\(api.channelID)"
        let editedAt: Date? = {
            if isPoll { return nil }
            if api.hideEditted { return nil }
            return api.updateTimeSeconds > api.createTimeSeconds
                ? Date(timeIntervalSince1970: TimeInterval(api.updateTimeSeconds))
                : nil
        }()
        self.init(
            id:                customId ?? "\(api.messageID)",
            channelId:         channelId,
            clanId:            "\(api.clanID)",
            senderId:          "\(api.senderID)",
            content:           contentData,
            createdAt:         createdAt,
            editedAt:          editedAt,
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

    static func fromApi(_ api: Mezon_Api_ChannelMessage, merging previous: MessageRecord?, customId: String? = nil) -> MessageRecord {
        var fresh = MessageRecord(from: api, customId: customId)
        guard let prev = previous, prev.id == fresh.id else { return fresh }
        if prev.senderId != fresh.senderId { return fresh }
        let mergedContent = PresignFinishContent.mergePresignFinishContent(local: prev.content, server: fresh.content)
        if mergedContent != fresh.content {
            fresh = MessageRecord(
                id: fresh.id,
                channelId: fresh.channelId,
                clanId: fresh.clanId,
                senderId: fresh.senderId,
                content: mergedContent,
                createdAt: fresh.createdAt,
                editedAt: fresh.editedAt,
                isDeleted: fresh.isDeleted,
                code: fresh.code,
                senderDisplayName: fresh.senderDisplayName,
                senderAvatarURL: fresh.senderAvatarURL,
                sendingState: fresh.sendingState,
                attachmentsJSON: mergedAttachmentsJSON(fresh: fresh, previous: prev),
                reactionsJSON: fresh.reactionsJSON,
                referencesData: fresh.referencesData,
                mentionsJSON: fresh.mentionsJSON
            )
        }
        if PresignFinishContent.hasPresignFinishField(in: fresh.content) {
            fresh.editedAt = nil
        }
        let bodyTextUnchanged = prev.content == fresh.content
            && prev.mentionsJSON == fresh.mentionsJSON
            && prev.referencesData == fresh.referencesData
        if bodyTextUnchanged {
            fresh.editedAt = prev.editedAt
        }
        let sameBodyForMerge = prev.content == fresh.content
            && prev.attachmentsJSON == fresh.attachmentsJSON
            && prev.referencesData == fresh.referencesData
            && prev.mentionsJSON == fresh.mentionsJSON
            && prev.code == fresh.code
        if !sameBodyForMerge {
            let mergedDisplayName = preferredDisplayName(api: api, fresh: fresh, previous: prev)
            let mergedAvatarURL: String? = fresh.senderAvatarURL ?? prev.senderAvatarURL
            return MessageRecord(
                id: fresh.id,
                channelId: fresh.channelId,
                clanId: fresh.clanId,
                senderId: fresh.senderId,
                content: fresh.content,
                createdAt: prev.createdAt,
                editedAt: fresh.editedAt,
                isDeleted: fresh.isDeleted,
                code: prev.code,
                senderDisplayName: mergedDisplayName,
                senderAvatarURL: mergedAvatarURL,
                sendingState: fresh.sendingState,
                attachmentsJSON: mergedAttachmentsJSON(fresh: fresh, previous: prev),
                reactionsJSON: mergedReactionsJSON(fresh: fresh, previous: prev),
                referencesData: fresh.referencesData,
                mentionsJSON: fresh.mentionsJSON
            )
        }
        let isClanContext = api.clanID != 0
        if isClanContext {
            let nick = api.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
            let clanAv = api.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nick.isEmpty || !clanAv.isEmpty {
                return recordByMergingReactions(fresh: fresh, previous: prev)
            }
        }
        let dn = api.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let un = api.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let av = api.avatar.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dn.isEmpty || !un.isEmpty || !av.isEmpty {
            return recordByMergingReactions(fresh: fresh, previous: prev)
        }

        let prevIsPoll = prev.code == 18 || PollData.parse(from: prev.content) != nil
        let freshIsPoll = fresh.code == 18 || PollData.parse(from: fresh.content) != nil
        let isLogicallyPoll = prevIsPoll || freshIsPoll

        var effectiveContent = fresh.content
        if isLogicallyPoll && !freshIsPoll {
            effectiveContent = prev.content
        } else if fresh.content.isEmpty {
            effectiveContent = prev.content
        }

        let effectiveEditedAt: Date? = isLogicallyPoll ? nil : fresh.editedAt

        let finalDisplayName = preferredDisplayName(api: api, fresh: fresh, previous: prev)
        return MessageRecord(
            id: fresh.id,
            channelId: fresh.channelId,
            clanId: fresh.clanId,
            senderId: fresh.senderId,
            content: effectiveContent,
            createdAt: fresh.createdAt,
            editedAt: effectiveEditedAt,
            isDeleted: fresh.isDeleted,
            code: fresh.code,
            senderDisplayName: finalDisplayName,
            senderAvatarURL: fresh.senderAvatarURL ?? prev.senderAvatarURL,
            sendingState: fresh.sendingState,
            attachmentsJSON: mergedAttachmentsJSON(fresh: fresh, previous: prev),
            reactionsJSON: mergedReactionsJSON(fresh: fresh, previous: prev),
            referencesData: fresh.referencesData,
            mentionsJSON: fresh.mentionsJSON
        )
    }

    private static func preferredDisplayName(
        api: Mezon_Api_ChannelMessage, fresh: MessageRecord, previous: MessageRecord
    ) -> String {
        let isClanContext = api.clanID != 0
        let hasAuthoritativeName: Bool = {
            if isClanContext, !api.clanNick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return !api.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }()
        if hasAuthoritativeName, !fresh.senderDisplayName.isEmpty {
            return fresh.senderDisplayName
        }
        let prevName = previous.senderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prevName.isEmpty, prevName != "\(api.senderID)" {
            return previous.senderDisplayName
        }
        return fresh.senderDisplayName
    }

    private static func mergedReactionsJSON(fresh: MessageRecord, previous: MessageRecord) -> Data {
        fresh.reactionsJSON.isEmpty ? previous.reactionsJSON : fresh.reactionsJSON
    }

    private static func mergedAttachmentsJSON(incoming: Data, previous: Data) -> Data {
        incoming.isEmpty ? previous : incoming
    }

    private static func mergedAttachmentsJSON(fresh: MessageRecord, previous: MessageRecord) -> Data {
        mergedAttachmentsJSON(incoming: fresh.attachmentsJSON, previous: previous.attachmentsJSON)
    }

    static func mergingIncomingPreservingEmptyAttachments(
        incoming: MessageRecord,
        previous: MessageRecord
    ) -> MessageRecord {
        let attachmentsJSON = mergedAttachmentsJSON(incoming: incoming.attachmentsJSON, previous: previous.attachmentsJSON)
        let reactionsJSON = mergedReactionsJSON(fresh: incoming, previous: previous)
        guard attachmentsJSON != incoming.attachmentsJSON || reactionsJSON != incoming.reactionsJSON else { return incoming }
        return MessageRecord(
            id: incoming.id,
            channelId: incoming.channelId,
            clanId: incoming.clanId,
            senderId: incoming.senderId,
            content: incoming.content,
            createdAt: incoming.createdAt,
            editedAt: incoming.editedAt,
            isDeleted: incoming.isDeleted,
            code: incoming.code,
            senderDisplayName: incoming.senderDisplayName,
            senderAvatarURL: incoming.senderAvatarURL,
            sendingState: incoming.sendingState,
            attachmentsJSON: attachmentsJSON,
            reactionsJSON: reactionsJSON,
            referencesData: incoming.referencesData,
            mentionsJSON: incoming.mentionsJSON
        )
    }

    private static func recordByMergingReactions(fresh: MessageRecord, previous: MessageRecord) -> MessageRecord {
        let reactionsJSON = mergedReactionsJSON(fresh: fresh, previous: previous)
        let attachmentsJSON = mergedAttachmentsJSON(fresh: fresh, previous: previous)
        guard reactionsJSON != fresh.reactionsJSON || attachmentsJSON != fresh.attachmentsJSON else { return fresh }
        return MessageRecord(
            id: fresh.id,
            channelId: fresh.channelId,
            clanId: fresh.clanId,
            senderId: fresh.senderId,
            content: fresh.content,
            createdAt: fresh.createdAt,
            editedAt: fresh.editedAt,
            isDeleted: fresh.isDeleted,
            code: fresh.code,
            senderDisplayName: fresh.senderDisplayName,
            senderAvatarURL: fresh.senderAvatarURL,
            sendingState: fresh.sendingState,
            attachmentsJSON: attachmentsJSON,
            reactionsJSON: reactionsJSON,
            referencesData: fresh.referencesData,
            mentionsJSON: fresh.mentionsJSON
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

    static func compareAscending(id aId: String, createdAt aDate: Date, id bId: String, createdAt bDate: Date) -> Bool {
        if aId == bId { return false }
        if let aNum = numericMessageId(aId), let bNum = numericMessageId(bId) {
            return aNum < bNum
        }
        if aDate != bDate {
            return aDate < bDate
        }
        let aPending = aId.hasPrefix("pending-")
        let bPending = bId.hasPrefix("pending-")
        if aPending != bPending {
            return aPending
        }
        return aId < bId
    }

    static func isOrderedAscending(_ a: MessageRecord, _ b: MessageRecord) -> Bool {
        compareAscending(id: a.id, createdAt: a.createdAt, id: b.id, createdAt: b.createdAt)
    }

    private static func numericMessageId(_ id: String) -> UInt64? {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return UInt64(id)
    }
}
