import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Notifications {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func listNotifications(
            clanId: Int64, category: Int32, notificationId: Int64 = 0, token: String
        ) async throws {
            let apiNotifications = try await network.listNotifications(
                clanID: clanId,
                category: category,
                token: token,
                notificationID: notificationId
            )

            let mappedNotifications = apiNotifications.map { NotificationRecord(from: $0) }

            postbox.write { tx in
                if notificationId > 0 {
                    tx.appendNotifications(mappedNotifications, clanId: clanId, category: category)
                } else {
                    tx.updateNotifications(mappedNotifications, clanId: clanId, category: category)
                }
            }
        }
    }
}
