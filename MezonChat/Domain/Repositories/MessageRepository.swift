import Foundation
import Combine

protocol MessageRepository {
    func fetchMessages(
        channelId: String,
        limit: Int,
        before: Date?
    ) -> AnyPublisher<[Message], Error>

    func sendMessage(
        channelId: String,
        content: Message.Content
    ) -> AnyPublisher<Message, Error>

    func editMessage(
        messageId: String,
        content: Message.Content
    ) -> AnyPublisher<Message, Error>

    func deleteMessage(messageId: String) -> AnyPublisher<Void, Error>

    func addReaction(
        messageId: String,
        emoji: String
    ) -> AnyPublisher<Message, Error>

    func messageStream(channelId: String) -> AnyPublisher<Message, Error>
}
