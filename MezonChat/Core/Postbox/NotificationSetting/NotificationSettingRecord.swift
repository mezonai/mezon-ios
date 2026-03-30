import Foundation

enum NotificationSettingScope: Int32, PostboxCoding {
    case channel  = 0
    case category = 1
    case clan     = 2
}

struct NotificationSettingRecord: PostboxCoding, Equatable {
    let id: Int64
    let entityId: Int64
    let scope: NotificationSettingScope
    let notificationSettingType: Int32
    let timeMuteSeconds: UInt32
    let active: Int32

    init(id: Int64, entityId: Int64, scope: NotificationSettingScope,
         notificationSettingType: Int32, timeMuteSeconds: UInt32, active: Int32) {
        self.id = id
        self.entityId = entityId
        self.scope = scope
        self.notificationSettingType = notificationSettingType
        self.timeMuteSeconds = timeMuteSeconds
        self.active = active
    }

    init(from proto: Mezon_Api_NotificationUserChannel) {
        self.id = proto.id
        self.entityId = proto.channelID
        self.scope = .channel
        self.notificationSettingType = proto.notificationSettingType
        self.timeMuteSeconds = UInt32(bitPattern: proto.timeMuteSeconds)
        self.active = proto.active
    }
}
