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

    static func deduplicatedByUserId(_ members: [ChannelMemberRecord]) -> [ChannelMemberRecord] {
        var seen = Set<Int64>()
        var result: [ChannelMemberRecord] = []
        result.reserveCapacity(members.count)
        for member in members where member.userId != 0 {
            guard seen.insert(member.userId).inserted else { continue }
            result.append(member)
        }
        return result
    }

    static func mergingProfilesFromChannelUsers(
        _ users: [Mezon_Api_ChannelUserList.ChannelUser],
        postbox: Postbox
    ) -> [ChannelMemberRecord] {
        let records = postbox.read { tx in
            users.map { u in
                let profile = tx.getProfile(userId: String(u.userID))
                return ChannelMemberRecord(
                    id: u.id,
                    userId: u.userID,
                    roleIds: u.roleID,
                    threadId: u.threadID,
                    clanNick: u.clanNick,
                    clanAvatar: u.clanAvatar,
                    clanId: u.clanID,
                    isBanned: u.isBanned,
                    expiredBanTime: u.expiredBanTime,
                    isOnline: profile?.isOnline ?? false,
                    displayName: profile?.displayName ?? "",
                    username: profile?.username ?? ""
                )
            }
        }
        return deduplicatedByUserId(records)
    }
}

extension PostboxTransaction {
    func applyAllUsersAddChannelResponse(
        _ res: Mezon_Api_AllUsersAddChannelResponse,
        channelId: Int64,
        dmMemberLabelByUserId: [Int64: String]
    ) {
        let userIds = res.userIds
        guard !userIds.isEmpty else { return }
        var members: [ChannelMemberRecord] = []
        for (i, uid) in userIds.enumerated() {
            let displayName = i < res.displayNames.count ? res.displayNames[i] : ""
            let username = i < res.usernames.count ? res.usernames[i] : ""
            let avatar = i < res.avatars.count ? res.avatars[i] : ""
            let isOnline = i < res.onlines.count ? res.onlines[i] : false
            let uidStr = String(uid)
            let existing = getProfile(userId: uidStr)
            let profileDisplayName = displayName.isEmpty ? existing?.displayName : displayName
            let profileUsername = username.isEmpty ? (existing?.username ?? "") : username
            let profileAvatar: String? = avatar.isEmpty ? existing?.avatarUrl : avatar
            updateProfile(ProfileRecord(
                userId: uidStr,
                username: profileUsername,
                displayName: profileDisplayName,
                avatarUrl: profileAvatar,
                status: existing?.status ?? 0,
                isOnline: isOnline
            ))
            let resolvedDisplayName = profileDisplayName ?? ""
            let resolvedUsername = profileUsername
            let label = dmMemberLabelByUserId[uid]
            let finalDisplayName = resolvedDisplayName.isEmpty
                ? (label ?? resolvedUsername) : resolvedDisplayName
            let finalUsername = resolvedUsername.isEmpty
                ? (label ?? "") : resolvedUsername
            members.append(ChannelMemberRecord(
                id: uid, userId: uid, roleIds: [],
                threadId: 0, clanNick: "",
                clanAvatar: avatar, clanId: 0,
                isBanned: false, expiredBanTime: 0,
                isOnline: isOnline,
                displayName: finalDisplayName,
                username: finalUsername
            ))
        }
        updateChannelMembers(members, channelId: channelId)
    }
}

extension Mezon_Api_ChannelDescription {
    func dmMemberLabelsForChannelList() -> [Int64: String] {
        let dm = MezonConstants.ChannelType.dm.rawValue
        let group = MezonConstants.ChannelType.group.rawValue
        guard type == dm || type == group else { return [:] }

        var result: [Int64: String] = [:]
        let ids = userIds
        let displayNames = self.displayNames
        let usernames = self.usernames
        for i in ids.indices {
            let id = ids[i]
            let dn = i < displayNames.count ? displayNames[i] : ""
            let un = i < usernames.count ? usernames[i] : ""
            let label = !dn.isEmpty ? dn : un
            if !label.isEmpty {
                result[id] = label
            }
        }
        return result
    }
}
