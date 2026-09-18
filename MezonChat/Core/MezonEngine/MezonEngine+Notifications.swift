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
            let friends = engine.friendsData.allFriends()

            postbox.write { tx in
                let enriched = mappedNotifications.map { record in
                    let friendAvatar =
                        friends.first(where: { $0.user.id == record.senderID })?.user.avatarURL
                        ?? ""
                    return record.enrichedSenderAvatar(
                        transaction: tx, fallbackAvatarURL: friendAvatar)
                }
                if notificationId > 0 {
                    tx.appendNotifications(enriched, clanId: clanId, category: category)
                } else {
                    tx.updateNotifications(enriched, clanId: clanId, category: category)
                }
            }
        }

        func deleteNotifications(
            ids: [Int64], clanId: Int64, category: Int32, token: String
        ) async throws {
            try await network.deleteNotifications(ids: ids, category: category, token: token)
            postbox.write { tx in
                tx.removeNotifications(ids: ids, clanId: clanId, category: category)
            }
        }
    }
}
