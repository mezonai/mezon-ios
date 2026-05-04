import Foundation
import SwiftProtobuf

struct ClanMemberRecord: PostboxCoding, Equatable {
    let userId: Int64
    let roleIds: [Int64]
    let clanNick: String
    let clanAvatar: String
    let userAvatarURL: String
    let clanId: Int64
    let isOnline: Bool
    let displayName: String
    let username: String

    init(from clanUser: Mezon_Api_ClanUserList.ClanUser) {
        self.userId = clanUser.user.id
        self.roleIds = clanUser.roleID
        self.clanNick = clanUser.clanNick
        self.clanAvatar = clanUser.clanAvatar
        self.userAvatarURL = clanUser.user.avatarURL
        self.clanId = clanUser.clanID
        self.isOnline = clanUser.user.online
        self.displayName = clanUser.user.displayName
        self.username = clanUser.user.username
    }

    init(
        userId: Int64, roleIds: [Int64], clanNick: String, clanAvatar: String, userAvatarURL: String = "",
        clanId: Int64, isOnline: Bool = false, displayName: String = "", username: String = ""
    ) {
        self.userId = userId
        self.roleIds = roleIds
        self.clanNick = clanNick
        self.clanAvatar = clanAvatar
        self.userAvatarURL = userAvatarURL
        self.clanId = clanId
        self.isOnline = isOnline
        self.displayName = displayName
        self.username = username
    }

    static func postboxDecode(from data: Data) -> ClanMemberRecord? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let userId = dict["userId"] as? Int64 else { return nil }
        return ClanMemberRecord(
            userId: userId,
            roleIds: dict["roleIds"] as? [Int64] ?? [],
            clanNick: dict["clanNick"] as? String ?? "",
            clanAvatar: dict["clanAvatar"] as? String ?? "",
            userAvatarURL: dict["userAvatarURL"] as? String ?? "",
            clanId: dict["clanId"] as? Int64 ?? 0,
            isOnline: dict["isOnline"] as? Bool ?? false,
            displayName: dict["displayName"] as? String ?? "",
            username: dict["username"] as? String ?? ""
        )
    }

    func postboxEncode() -> Data? {
        let dict: [String: Any] = [
            "userId": userId,
            "roleIds": roleIds,
            "clanNick": clanNick,
            "clanAvatar": clanAvatar,
            "userAvatarURL": userAvatarURL,
            "clanId": clanId,
            "isOnline": isOnline,
            "displayName": displayName,
            "username": username
        ]
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    func toClanUserListClanUser() -> Mezon_Api_ClanUserList.ClanUser {
        var u = Mezon_Api_User()
        u.id = userId
        u.online = isOnline
        u.displayName = displayName
        u.username = username
        u.avatarURL = userAvatarURL
        var c = Mezon_Api_ClanUserList.ClanUser()
        c.user = u
        c.roleID = roleIds
        c.clanNick = clanNick
        c.clanAvatar = clanAvatar
        c.clanID = clanId
        return c
    }

    func resolvedAvatarURL(fallbackProfileAvatar: String?) -> String? {
        if !clanAvatar.isEmpty { return clanAvatar }
        if !userAvatarURL.isEmpty { return userAvatarURL }
        if let p = fallbackProfileAvatar, !p.isEmpty { return p }
        return nil
    }
}
