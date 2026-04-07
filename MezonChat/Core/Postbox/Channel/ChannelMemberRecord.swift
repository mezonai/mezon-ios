import Foundation
import SwiftProtobuf

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
    let isOnline: Bool
    let displayName: String
    let username: String

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
        self.isOnline = false
        self.displayName = ""
        self.username = ""
    }

    init(from clanUser: Mezon_Api_ClanUserList.ClanUser) {
        self.id = 0
        self.userId = clanUser.user.id
        self.roleIds = clanUser.roleID
        self.threadId = 0
        self.clanNick = clanUser.clanNick
        self.clanAvatar = clanUser.clanAvatar
        self.clanId = clanUser.clanID
        self.isBanned = false
        self.expiredBanTime = 0
        self.isOnline = clanUser.user.online
        self.displayName = clanUser.user.displayName
        self.username = clanUser.user.username
    }

    init?(fromDict dict: [String: Any]) {
        guard let userId = dict["userId"] as? Int64 else { return nil }
        self.id = dict["id"] as? Int64 ?? 0
        self.userId = userId
        self.roleIds = dict["roleIds"] as? [Int64] ?? []
        self.threadId = dict["threadId"] as? Int64 ?? 0
        self.clanNick = dict["clanNick"] as? String ?? ""
        self.clanAvatar = dict["clanAvatar"] as? String ?? ""
        self.clanId = dict["clanId"] as? Int64 ?? 0
        self.isBanned = dict["isBanned"] as? Bool ?? false
        self.expiredBanTime = dict["expiredBanTime"] as? Int32 ?? 0
        self.isOnline = dict["isOnline"] as? Bool ?? false
        self.displayName = dict["displayName"] as? String ?? ""
        self.username = dict["username"] as? String ?? ""
    }

    func toDict() -> [String: Any] {
        return [
            "id": id,
            "userId": userId,
            "roleIds": roleIds,
            "threadId": threadId,
            "clanNick": clanNick,
            "clanAvatar": clanAvatar,
            "clanId": clanId,
            "isBanned": isBanned,
            "expiredBanTime": expiredBanTime,
            "isOnline": isOnline,
            "displayName": displayName,
            "username": username
        ]
    }

    init(id: Int64, userId: Int64, roleIds: [Int64], threadId: Int64, clanNick: String, clanAvatar: String, clanId: Int64, isBanned: Bool, expiredBanTime: Int32, isOnline: Bool = false, displayName: String = "", username: String = "") {
        self.id = id
        self.userId = userId
        self.roleIds = roleIds
        self.threadId = threadId
        self.clanNick = clanNick
        self.clanAvatar = clanAvatar
        self.clanId = clanId
        self.isBanned = isBanned
        self.expiredBanTime = expiredBanTime
        self.isOnline = isOnline
        self.displayName = displayName
        self.username = username
    }
}
