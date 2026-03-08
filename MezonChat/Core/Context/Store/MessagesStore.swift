import Foundation
import Combine
import SwiftProtobuf

@MainActor
final class MessagesStore: ObservableObject {

    static func key(clanId: Int64, channelId: Int64) -> String {
        "\(clanId)_\(channelId)"
    }

    @Published private(set) var messagesByChannel: [String: [Mezon_Api_ChannelMessage]] = [:]
    @Published private(set) var loadingChannels: Set<String> = []
    @Published private(set) var hasMoreOlderByChannel: [String: Bool] = [:]

    init() {}

    func setMessages(_ messages: [Mezon_Api_ChannelMessage], clanId: Int64, channelId: Int64) {
        let k = Self.key(clanId: clanId, channelId: channelId)
        messagesByChannel[k] = messages.sorted { $0.createTimeSeconds < $1.createTimeSeconds }
    }

    func appendMessages(_ messages: [Mezon_Api_ChannelMessage], clanId: Int64, channelId: Int64) {
        let k = Self.key(clanId: clanId, channelId: channelId)
        var current = messagesByChannel[k] ?? []
        print("appendMessages: \(messages) messages")
        for m in messages {
            if !current.contains(where: { "\($0.messageID)" == "\(m.messageID)" }) {
                current.append(m)
            }
        }
        current.sort { $0.createTimeSeconds < $1.createTimeSeconds }
        messagesByChannel[k] = current
        objectWillChange.send()
    }

    func messagesPublisher(clanId: Int64, channelId: Int64) -> AnyPublisher<[Mezon_Api_ChannelMessage], Never> {
        let k = Self.key(clanId: clanId, channelId: channelId)
        return $messagesByChannel
            .map { $0[k] ?? [] }
            .eraseToAnyPublisher()
    }

    func dmLastMessagesPublisher() -> AnyPublisher<[Int64: Mezon_Api_ChannelMessage], Never> {
        $messagesByChannel
            .map { dict in
                var result: [Int64: Mezon_Api_ChannelMessage] = [:]
                for (k, msgs) in dict where k.hasPrefix("0_") {
                    guard let channelId = Int64(k.dropFirst(2)),
                          let last = msgs.max(by: { $0.createTimeSeconds < $1.createTimeSeconds }) else { continue }
                    result[channelId] = last
                }
                return result
            }
            .eraseToAnyPublisher()
    }

    func setHasMoreOlder(_ hasMore: Bool, clanId: Int64, channelId: Int64) {
        let k = Self.key(clanId: clanId, channelId: channelId)
        hasMoreOlderByChannel[k] = hasMore
    }

    func setLoading(_ loading: Bool, clanId: Int64, channelId: Int64) {
        let k = Self.key(clanId: clanId, channelId: channelId)
        if loading {
            loadingChannels.insert(k)
        } else {
            loadingChannels.remove(k)
        }
    }

    func messages(clanId: Int64, channelId: Int64) -> [Mezon_Api_ChannelMessage] {
        messagesByChannel[Self.key(clanId: clanId, channelId: channelId)] ?? []
    }

    func hasMoreOlder(clanId: Int64, channelId: Int64) -> Bool {
        hasMoreOlderByChannel[Self.key(clanId: clanId, channelId: channelId)] ?? true
    }

    func clear() {
        messagesByChannel = [:]
        loadingChannels = []
        hasMoreOlderByChannel = [:]
    }
}
