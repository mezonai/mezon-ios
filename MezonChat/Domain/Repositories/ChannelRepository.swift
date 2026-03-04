import Foundation
import Combine

protocol ChannelRepository {
    func fetchDirectMessages() -> AnyPublisher<[Channel], Error>
    func fetchClanChannels(clanId: String) -> AnyPublisher<[Channel], Error>
    func fetchChannel(id: String) -> AnyPublisher<Channel, Error>
    func createDirectMessage(userId: String) -> AnyPublisher<Channel, Error>
    func markAsRead(channelId: String) -> AnyPublisher<Void, Error>
}
