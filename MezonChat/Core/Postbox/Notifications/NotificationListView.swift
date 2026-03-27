import Foundation

struct NotificationListView: PostboxView {
    let clanId: Int64
    let category: Int32
    let notifications: [NotificationRecord]
}

final class MutableNotificationListView: MutablePostboxView {

    let clanId: Int64
    let category: Int32
    private(set) var notifications: [NotificationRecord]

    init(clanId: Int64, category: Int32, initial: [NotificationRecord]) {
        self.clanId = clanId
        self.category = category
        self.notifications = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedNotificationKeys.contains("\(clanId)_\(category)") else { return false }
        notifications = transaction.notificationTable.getNotificationRecord(clanId: clanId, category: category)
        return true
    }

    func immutableView() -> NotificationListView {
        NotificationListView(clanId: clanId, category: category, notifications: notifications)
    }
}
