import Foundation
import SwiftProtobuf

extension MezonEngine {
    @MainActor
    final class TopicService {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func listTopics(clanId: Int64, token: String) async throws {
            let apiTopics = try await network.listSdTopics(clanID: clanId, token: token)
            let mapped = apiTopics.map { TopicRecord(from: $0) }
            postbox.write { tx in
                let enriched = mapped.map { Self.enrichSenderAvatar($0, tx: tx) }
                tx.updateTopics(enriched, clanId: clanId)
            }
        }

        func createTopic(clanId: Int64, channelId: Int64, messageId: Int64, token: String) async throws -> Mezon_Api_SdTopic {
            let apiTopic = try await network.createSdTopic(
                clanID: clanId,
                channelID: channelId,
                messageID: messageId,
                token: token
            )
            let topic = TopicRecord(from: apiTopic)
            postbox.write { tx in
                let enriched = Self.enrichSenderAvatar(topic, tx: tx)
                var topics = tx.topicTable.getTopics(clanId: clanId)
                topics.removeAll { $0.id == enriched.id }
                topics.insert(enriched, at: 0)
                tx.updateTopics(topics, clanId: clanId)
            }
            return apiTopic
        }

        private static func enrichSenderAvatar(_ topic: TopicRecord, tx: PostboxTransaction) -> TopicRecord {
            let senderId = topic.lastSenderID
            guard senderId != 0 else { return topic }
            var avatar = topic.senderAvatarURL
            var displayName = topic.senderDisplayName
            if let profile = tx.getProfile(userId: String(senderId)) {
                if avatar.isEmpty, let url = profile.avatarUrl, !url.isEmpty {
                    avatar = url
                }
                if displayName.isEmpty {
                    if let dn = profile.displayName, !dn.isEmpty {
                        displayName = dn
                    } else if !profile.username.isEmpty {
                        displayName = profile.username
                    }
                }
            }
            guard avatar != topic.senderAvatarURL || displayName != topic.senderDisplayName else {
                return topic
            }
            return TopicRecord(
                id: topic.id,
                channelID: topic.channelID,
                clanID: topic.clanID,
                messageID: topic.messageID,
                creatorID: topic.creatorID,
                lastSenderID: topic.lastSenderID,
                senderAvatarURL: avatar,
                senderDisplayName: displayName,
                content: topic.content,
                updateTimeSeconds: topic.updateTimeSeconds,
                lastSentMessageContent: topic.lastSentMessageContent,
                rootMessageCode: topic.rootMessageCode,
                rootHasAttachment: topic.rootHasAttachment
            )
        }
    }
}
