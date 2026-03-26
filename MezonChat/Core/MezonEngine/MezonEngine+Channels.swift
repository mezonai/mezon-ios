import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Channels {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func listChannelDescs(clanId: Int64, token: String) async throws -> [Mezon_Api_ChannelDescription] {
            try await network.listChannelDescs(clanId: clanId, token: token)
        }

        func listDirectMessageChannels(token: String) async throws -> [Mezon_Api_ChannelDescription] {
            try await network.listDirectMessageChannels(token: token)
        }

        func channelListView(clanId: Int64) -> Signal<ChannelListView, NoError> {
            postbox.channelListView(clanId: clanId)
        }

        func updateChannelDescription(clanId: Int64, channelId: Int64, name: String?, topic: String?, categoryId: Int64?, token: String) async throws {
            let result = try await network.updateChannelDesc(
                clanId: clanId,
                channelId: channelId,
                channelLabel: name,
                topic: topic,
                categoryId: categoryId,
                token: token
            )
            
            self.postbox.write { tx in
                tx.updateChannelDescription(clanId: clanId, channelId: channelId, name: name, topic: topic)
            }
        }
    }
}
