import Foundation

extension MezonEngine.EngineData.Item {

    struct NotificationList: PostboxViewDataItem {
        typealias Result = [NotificationRecord]

        let clanId: Int64
        let category: Int32

        init(clanId: Int64, category: Int32) {
            self.clanId = clanId
            self.category = category
        }

        var key: PostboxViewKey {
            return .notificationList(clanId, category)
        }

        func extract(view: PostboxView) -> [NotificationRecord] {
            guard let view = view as? NotificationListView else { return [] }
            return view.notifications
        }
    }
}
