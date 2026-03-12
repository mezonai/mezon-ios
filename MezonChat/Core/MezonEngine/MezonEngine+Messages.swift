import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Messages {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func listChannelMessages(
            clanId: Int64,
            channelId: Int64,
            messageId: Int64,
            direction: Int32,
            limit: Int32,
            topicId: Int64,
            token: String
        ) async throws -> Mezon_Api_ChannelMessageList {
            try await network.listChannelMessages(
                clanId: clanId, channelId: channelId,
                messageId: messageId, direction: direction,
                limit: limit, topicId: topicId, token: token
            )
        }

        func sendChannelMessage(
            clanId: Int64, channelId: Int64, mode: Int32,
            isPublic: Bool, content: String,
            mentions: [Mezon_Api_MessageMention],
            attachments: [Mezon_Api_MessageAttachment],
            references: [Mezon_Api_MessageRef],
            anonymous: Bool, mentionEveryone: Bool,
            avatar: String, topicId: Int64, token: String
        ) async throws -> Mezon_Realtime_ChannelMessageAck {
            try await network.sendChannelMessage(
                clanId: clanId, channelId: channelId,
                mode: mode, isPublic: isPublic, content: content,
                mentions: mentions, attachments: attachments, references: references,
                anonymous: anonymous, mentionEveryone: mentionEveryone,
                avatar: avatar, topicId: topicId, token: token
            )
        }

        func messageHistoryView(channelId: String) -> Signal<MessageHistoryView, NoError> {
            postbox.messageHistoryView(channelId: channelId)
        }
    }
}
