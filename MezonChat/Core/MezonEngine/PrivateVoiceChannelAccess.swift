import Foundation

enum PrivateVoiceChannelAccess {
    static func afterPrivacyUpdate(
        userId: Int64, creatorId: Int64, memberIds: [Int64], roleIds: [Int64],
        selfRoleIds: [Int64]?, isOwnerOrAdmin: Bool, permissionsLoaded: Bool
    ) -> Bool? {
        guard userId != 0 else { return nil }
        if isOwnerOrAdmin || userId == creatorId || memberIds.contains(userId) { return true }
        if selfRoleIds?.contains(where: { roleIds.contains($0) }) == true { return true }
        guard permissionsLoaded, roleIds.isEmpty || selfRoleIds != nil else { return nil }
        return false
    }

    static func targetsUser(_ userId: Int64, ids: [Int64]) -> Bool {
        userId != 0 && ids.contains(userId)
    }
}

struct VoiceChannelAccessState {
    private var clanRevisions: [Int64: UInt64] = [:]
    private(set) var revokedChannelIds = Set<Int64>()

    func revision(clanId: Int64) -> UInt64 { clanRevisions[clanId, default: 0] }
    func mergingVoiceChannels<Channel>(
        incoming: [Channel], cached: [Channel], since snapshot: VoiceChannelAccessState,
        id: (Channel) -> Int64, clanId: (Channel) -> Int64, isVoice: (Channel) -> Bool
    ) -> [Channel] {
        func changed(_ channel: Channel) -> Bool {
            revision(clanId: clanId(channel)) != snapshot.revision(clanId: clanId(channel))
        }
        var result = incoming.filter { !isVoice($0) || (!changed($0) && !revokedChannelIds.contains(id($0))) }
        let incomingIds = Set(result.map(id))
        result += cached.filter {
            isVoice($0) && changed($0) && !revokedChannelIds.contains(id($0)) && !incomingIds.contains(id($0))
        }
        return result
    }

    mutating func invalidate(clanId: Int64) {
        clanRevisions[clanId, default: 0] &+= 1
    }

    mutating func revoke(clanId: Int64, channelId: Int64) {
        invalidate(clanId: clanId)
        revokedChannelIds.insert(channelId)
    }

    mutating func grant(clanId: Int64, channelId: Int64) {
        invalidate(clanId: clanId)
        revokedChannelIds.remove(channelId)
    }

    mutating func accept(channelIds: [Int64], clanId: Int64, revision: UInt64) -> Bool {
        guard revision == self.revision(clanId: clanId) else { return false }
        revokedChannelIds.subtract(channelIds)
        return true
    }
}
