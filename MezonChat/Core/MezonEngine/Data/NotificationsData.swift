import Foundation

extension MezonEngine.EngineData.Item {

    struct NotificationList: PostboxViewDataItem {
        typealias Result = [Notifications]

        let clanId: Int64
        let category: Int32

        init(clanId: Int64, category: Int32) {
            self.clanId = clanId
            self.category = category
        }

        var key: PostboxViewKey {
            return .notificationList(clanId: clanId, category: category)
        }

        func extract(view: PostboxView) -> [Notifications] {
            guard let view = view as? NotificationListView else { return [] }
            return view.notifications
        }
    }
}
