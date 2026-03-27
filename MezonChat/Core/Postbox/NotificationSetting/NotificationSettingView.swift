import Foundation

struct NotificationSettingView: PostboxView {
    let entityId: Int64
    let record: NotificationSettingRecord?
}

final class MutableNotificationSettingView: MutablePostboxView {

    let entityId: Int64
    private(set) var record: NotificationSettingRecord?

    init(entityId: Int64, initial: NotificationSettingRecord?) {
        self.entityId = entityId
        self.record = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedNotificationSettingIds.contains(entityId) else { return false }
        record = transaction.notificationSettingTable.get(entityId: entityId)
        return true
    }

    func immutableView() -> NotificationSettingView {
        NotificationSettingView(entityId: entityId, record: record)
    }
}
