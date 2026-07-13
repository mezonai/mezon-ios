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
            let localEnriched = postbox.read { tx in
                mapped.map { Self.enrichSenderAvatar($0, tx: tx) }
            }
            let enriched = await enrichRootMessagesFromNetwork(
                localEnriched,
                token: token
            )
            postbox.write { tx in
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

        private func enrichRootMessagesFromNetwork(_ topics: [TopicRecord], token: String) async -> [TopicRecord] {
            var result: [TopicRecord] = []
            result.reserveCapacity(topics.count)
            for topic in topics {
                guard topic.messageID != 0 else {
                    result.append(topic)
                    continue
                }
                guard let root = await fetchRootMessage(for: topic, token: token) else {
                    result.append(topic)
                    continue
                }
                let content = topic.content.isEmpty ? root.content : topic.content
                let rootCode = topic.rootMessageCode != 0 ? topic.rootMessageCode : root.code
                let rootHasAttachment = topic.rootHasAttachment || !root.attachments.isEmpty
                if content == topic.content,
                   rootCode == topic.rootMessageCode,
                   rootHasAttachment == topic.rootHasAttachment {
                    result.append(topic)
                    continue
                }
                result.append(
                    TopicRecord(
                        id: topic.id,
                        channelID: topic.channelID,
                        clanID: topic.clanID,
                        messageID: topic.messageID,
                        creatorID: topic.creatorID,
                        lastSenderID: topic.lastSenderID,
                        senderAvatarURL: topic.senderAvatarURL,
                        senderDisplayName: topic.senderDisplayName,
                        content: content,
                        updateTimeSeconds: topic.updateTimeSeconds,
                        lastSentMessageContent: topic.lastSentMessageContent,
                        rootMessageCode: rootCode,
                        rootHasAttachment: rootHasAttachment
                    )
                )
            }
            return result
        }

        private func fetchRootMessage(for topic: TopicRecord, token: String) async -> Mezon_Api_ChannelMessage? {
            for direction in [Int32(2), Int32(3)] {
                if let response = try? await network.listChannelMessages(
                    clanId: topic.clanID,
                    channelId: topic.channelID,
                    messageId: topic.messageID,
                    direction: direction,
                    limit: 3,
                    token: token
                ),
                   let message = response.messages.first(where: { $0.messageID == topic.messageID }) {
                    return message
                }
            }
            return nil
        }

        private static func enrichSenderAvatar(_ topic: TopicRecord, tx: PostboxTransaction) -> TopicRecord {
            let senderId = topic.lastSenderID
            var avatar = topic.senderAvatarURL
            var displayName = topic.senderDisplayName
            let root: MessageRecord?
            if topic.messageID != 0 {
                root = tx.getMessageById("\(topic.messageID)", channelId: "\(topic.channelID)")
                    ?? tx.getMessageById("\(topic.messageID)")
            } else {
                root = nil
            }
            if senderId != 0, let profile = tx.getProfile(userId: String(senderId)) {
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
            let rootContent: String
            if topic.content.isEmpty, let rootText = root.flatMap({ String(data: $0.content, encoding: .utf8) }) {
                rootContent = rootText
            } else {
                rootContent = topic.content
            }
            let rootCode = topic.rootMessageCode != 0 ? topic.rootMessageCode : (root?.code ?? 0)
            let rootHasAttachment = topic.rootHasAttachment || !(root?.attachmentsJSON.isEmpty ?? true)
            guard avatar != topic.senderAvatarURL ||
                    displayName != topic.senderDisplayName ||
                    rootContent != topic.content ||
                    rootCode != topic.rootMessageCode ||
                    rootHasAttachment != topic.rootHasAttachment else {
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
                content: rootContent,
                updateTimeSeconds: topic.updateTimeSeconds,
                lastSentMessageContent: topic.lastSentMessageContent,
                rootMessageCode: rootCode,
                rootHasAttachment: rootHasAttachment
            )
        }
    }
}
