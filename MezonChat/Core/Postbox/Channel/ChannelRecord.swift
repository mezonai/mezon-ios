import Foundation
import SwiftProtobuf

struct ChannelRecord: PostboxCoding, Equatable {

    let id: Int64
    let clanId: Int64

    let label: String
    let type: Int32

    let categoryId: Int64
    let categoryName: String
    let parentId: Int64

    let position: Int32

    var permissions: [PermissionRecord]
    var members: [ChannelMemberRecord]
    var isBanned: Bool
    var expiredBanTime: Int32

    init(proto: Mezon_Api_ChannelDescription) {
        self.id           = proto.channelID
        self.clanId       = proto.clanID
        self.label        = proto.channelLabel
        self.type         = Int32(proto.type)
        self.categoryId   = proto.categoryID
        self.categoryName = proto.categoryName
        self.parentId     = proto.parentID
        self.position     = 0
        self.permissions  = []
        self.members      = []
        self.isBanned     = false
        self.expiredBanTime = 0
    }

    var isTopLevel: Bool { parentId == 0 }

    static func empty(channelId: Int64) -> ChannelRecord {
        ChannelRecord(id: channelId, clanId: 0, label: "", type: 0,
                      categoryId: 0, categoryName: "", parentId: 0, position: 0)
    }

    init(id: Int64, clanId: Int64, label: String, type: Int32,
         categoryId: Int64, categoryName: String, parentId: Int64, position: Int32) {
        self.id = id
        self.clanId = clanId
        self.label = label
        self.type = type
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.parentId = parentId
        self.position = position
        self.permissions = []
        self.members = []
        self.isBanned = false
        self.expiredBanTime = 0
    }
}

struct PermissionRecord: PostboxCoding, Equatable {
    let id: Int64
    let title: String
    let slug: String
    let active: Int32
    let scope: Int32
    let level: Int32

    init(from proto: Mezon_Api_Permission) {
        self.id = proto.id
        self.title = proto.title
        self.slug = proto.slug
        self.active = proto.active
        self.scope = proto.scope
        self.level = proto.level
    }

    init(id: Int64, title: String, slug: String, active: Int32, scope: Int32, level: Int32) {
        self.id = id
        self.title = title
        self.slug = slug
        self.active = active
        self.scope = scope
        self.level = level
    }
}

struct ChannelMemberRecord: PostboxCoding, Equatable {
    let id: Int64
    let userId: Int64
    let roleIds: [Int64]
    let threadId: Int64
    let clanNick: String
    let clanAvatar: String
    let clanId: Int64
    let isBanned: Bool
    let expiredBanTime: Int32

    init(from proto: Mezon_Api_ChannelUserList.ChannelUser) {
        self.id = proto.id
        self.userId = proto.userID
        self.roleIds = proto.roleID
        self.threadId = proto.threadID
        self.clanNick = proto.clanNick
        self.clanAvatar = proto.clanAvatar
        self.clanId = proto.clanID
        self.isBanned = proto.isBanned
        self.expiredBanTime = proto.expiredBanTime
    }

    init(id: Int64, userId: Int64, roleIds: [Int64], threadId: Int64, clanNick: String, clanAvatar: String, clanId: Int64, isBanned: Bool, expiredBanTime: Int32) {
        self.id = id
        self.userId = userId
        self.roleIds = roleIds
        self.threadId = threadId
        self.clanNick = clanNick
        self.clanAvatar = clanAvatar
        self.clanId = clanId
        self.isBanned = isBanned
        self.expiredBanTime = expiredBanTime
    }
}
