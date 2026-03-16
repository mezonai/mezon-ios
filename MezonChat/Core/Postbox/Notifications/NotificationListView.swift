import Foundation

struct NotificationListView: PostboxView {
    let clanId: Int64
    let category: Int32
    let notifications: [Notifications]
}

final class MutableNotificationListView: MutablePostboxView {

    let clanId: Int64
    let category: Int32
    private(set) var notifications: [Notifications]

    init(clanId: Int64, category: Int32, initial: [Notifications]) {
        self.clanId = clanId
        self.category = category
        self.notifications = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedNotificationKeys.contains("\(clanId)_\(category)") else { return false }
        notifications = transaction.notificationTable.getNotifications(clanId: clanId, category: category)
        return true
    }

    func immutableView() -> NotificationListView {
        NotificationListView(clanId: clanId, category: category, notifications: notifications)
    }
}
