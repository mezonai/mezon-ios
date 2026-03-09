import Foundation
import SwiftProtobuf

@MainActor
final class NotificationsStore: ObservableObject {
    @Published private(set) var notificationsCache: [String: [Notifications]] = [:]


    private func cacheKey(clanId: Int64, category: Int32) -> String {
        return "\(clanId)_\(category)"
    }

    func loadCachedNotifications(for clanId: Int64, categories: [Int32]) {
        for category in categories {
            let cachedApiModels = MezonPostbox.shared.loadNotifications(
                clanId: clanId, category: category)
            let domainModels = cachedApiModels.map { Notifications(from: $0) }
            notificationsCache[cacheKey(clanId: clanId, category: category)] = domainModels
        }
    }

    func saveFetchedNotifications(
        _ apiNotifications: [Mezon_Api_Notification], clanId: Int64, category: Int32
    ) {
        MezonPostbox.shared.saveNotifications(apiNotifications, clanId: clanId, category: category)

        let domainModels = apiNotifications.map { Notifications(from: $0) }
        notificationsCache[cacheKey(clanId: clanId, category: category)] = domainModels
    }

    func clear() {
        notificationsCache.removeAll()
    }
}
