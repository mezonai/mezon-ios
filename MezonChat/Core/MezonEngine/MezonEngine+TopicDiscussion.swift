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
                tx.updateTopics(mapped, clanId: clanId)
            }
        }
    }
}
