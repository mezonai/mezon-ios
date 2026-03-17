import Foundation

enum PostboxViewKey: Hashable {
    case clanList
    case channelList(clanId: Int64)
    case messageHistory(channelId: String)
    case preferences(String)
    case notificationList(Int64, Int32)
    case topicList(Int64)
}

protocol PostboxView {}

struct PreferencesView: PostboxView {
    let key: String
    let data: Data?
}

final class CombinedView {
    let views: [PostboxViewKey: PostboxView]
    init(views: [PostboxViewKey: PostboxView]) { self.views = views }
}
