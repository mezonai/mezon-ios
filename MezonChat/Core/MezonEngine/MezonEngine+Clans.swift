import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Clans {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func listClanDescs(token: String) async throws -> [Mezon_Api_ClanDesc] {
            try await network.listClanDescs(token: token)
        }

        func clanListView() -> Signal<ClanListView, NoError> {
            postbox.clanListView()
        }
    }
}
