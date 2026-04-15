import Foundation
import SwiftProtobuf

struct ProfileRecord: PostboxCoding, Equatable {

    let userId: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let status: Int32
    let isOnline: Bool
    let data: Data

    init(
        userId: String,
        username: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        status: Int32 = 0,
        isOnline: Bool = false,
        data: Data = Data()
    ) {
        self.userId      = userId
        self.username    = username
        self.displayName = displayName
        self.avatarUrl   = avatarUrl
        self.status      = status
        self.isOnline    = isOnline
        self.data        = data
    }

    init(from proto: Mezon_Api_User) {
        self.userId      = "\(proto.id)"
        self.username    = proto.username
        self.displayName = proto.displayName
        self.avatarUrl   = proto.avatarURL
        self.status      = ProfileRecord.mapStatus(proto.status)
        self.isOnline    = proto.online
        self.data        = Data()
    }

    init(from proto: Mezon_Api_ChannelUserList.ChannelUser) {
        self.userId      = "\(proto.userID)"
        self.username    = proto.clanNick
        self.displayName = proto.clanNick
        self.avatarUrl   = proto.clanAvatar
        self.status      = 0
        self.isOnline    = false
        self.data        = Data()
    }

    init(from clanUser: Mezon_Api_ClanUserList.ClanUser) {
        self.userId      = "\(clanUser.user.id)"
        self.username    = clanUser.user.username
        self.displayName = clanUser.clanNick.isEmpty ? clanUser.user.displayName : clanUser.clanNick
        self.avatarUrl   = clanUser.clanAvatar.isEmpty ? clanUser.user.avatarURL : clanUser.clanAvatar
        self.status      = ProfileRecord.mapStatus(clanUser.user.status)
        self.isOnline    = clanUser.user.online
        self.data        = Data()
    }
    static func mapStatus(_ status: String) -> Int32 {
        switch status.lowercased() {
        case "online": return 1
        case "idle": return 2
        case "do not disturb", "dnd": return 3
        case "invisible": return 4
        default: return 0
        }
    }
}
