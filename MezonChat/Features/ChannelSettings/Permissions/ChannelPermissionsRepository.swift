import Foundation
import SwiftProtobuf

@MainActor
final class ChannelPermissionsRepository {

    enum PermissionStatus: Int {
        case none = 0
        case allow = 1
        case deny = 2

        var apiType: Int32 {
            switch self {
            case .none: return 0
            case .allow: return 1
            case .deny: return 2
            }
        }
    }

    private let context: AccountContext

    init(context: AccountContext) {
        self.context = context
    }

    // MARK: - Reads (cached)

    func clanMembers(clanId: Int64) -> [ClanMemberRecord] {
        context.engine.account.postbox.read { $0.getClanMembers(clanId: clanId) }
    }

    func roles(clanId: Int64) -> [Mezon_Api_Role] {
        guard let response = context.engine.clanData.getClanRoles(clanId: clanId) else { return [] }
        let active = response.roles.roles.filter { $0.active != 0 }
        return active.sorted { lhs, rhs in
            if lhs.orderRole != rhs.orderRole { return lhs.orderRole < rhs.orderRole }
            return lhs.id < rhs.id
        }
    }

    func isEveryone(_ role: Mezon_Api_Role) -> Bool {
        role.slug == "everyone-\(role.clanID)"
    }

    func roleIsInChannel(_ role: Mezon_Api_Role, channelId: Int64) -> Bool {
        role.channelIds.contains(channelId)
    }

    func clanOwnerId(clanId: Int64) -> String? {
        context.engine.account.postbox.read { tx in
            tx.getClan(id: clanId)?.ownerId
        }
    }

    func allPermissions() -> [Mezon_Api_Permission] {
        context.engine.clanData.getAllPermissions()?.permissions ?? []
    }

    func channelOverridePermissionRows() -> [Mezon_Api_Permission] {
        let ch = allPermissions().filter { $0.scope == 2 }
        if !ch.isEmpty { return ch }
        return allPermissions()
    }

    func myMaxPermissionRoleId(clanId: Int64) -> Int64 {
        resolveMyMaxPermissionRoleId(clanId: clanId).roleId
    }

    private func resolveMyMaxPermissionRoleId(clanId: Int64) -> (userId: Int64, roleId: Int64, trace: String) {
        guard let uid = context.currentUser?.id, let userId = Int64(uid) else {
            return (0, 0, "no_current_user_id")
        }
        let allRoles = roles(clanId: clanId)
        guard !allRoles.isEmpty else {
            return (userId, 0, "no_roles_cached clanId=\(clanId)")
        }
        let roleById = Dictionary(uniqueKeysWithValues: allRoles.map { ($0.id, $0) })

        func bestRoleId(from roleIds: [Int64]) -> Int64 {
            var bestId: Int64 = 0
            var bestLevel: Int32 = Int32.min
            for rid in roleIds {
                guard let r = roleById[rid] else { continue }
                if r.maxLevelPermission > bestLevel {
                    bestLevel = r.maxLevelPermission
                    bestId = rid
                }
            }
            return bestId
        }

        let memberIds = clanMembers(clanId: clanId).first(where: { $0.userId == userId })?.roleIds ?? []
        let fromMemberRoles = bestRoleId(from: memberIds)
        if fromMemberRoles != 0 {
            return (
                userId, fromMemberRoles,
                "memberRoleIds ids=\(memberIds) resolved=\(fromMemberRoles)"
            )
        }

        var maxLevel: Int32 = Int32.min
        var maxRoleId: Int64 = 0
        for role in allRoles {
            guard role.roleUserList.roleUsers.contains(where: { $0.id == userId }) else { continue }
            if role.maxLevelPermission > maxLevel {
                maxLevel = role.maxLevelPermission
                maxRoleId = role.id
            }
        }
        if maxRoleId != 0 {
            return (userId, maxRoleId, "roleUserList resolved=\(maxRoleId)")
        }

        let userListCache = context.engine.clanData.getUserPermissions(clanId: clanId)
        let apiUserRoleIds = userListCache?.roles.map(\.id) ?? []
        let fromApiRoles = bestRoleId(from: apiUserRoleIds)
        if fromApiRoles != 0 {
            return (
                userId, fromApiRoles,
                "apiUserRoles ids=\(apiUserRoleIds) listMaxLevel=\(userListCache?.maxLevelPermission ?? 0) resolved=\(fromApiRoles)"
            )
        }

        if let userList = userListCache, userList.maxLevelPermission > 0 {
            let level = userList.maxLevelPermission
            let candidates = allRoles.filter { $0.maxLevelPermission == level }
            if let chosen = candidates.min(by: {
                if $0.orderRole != $1.orderRole { return $0.orderRole < $1.orderRole }
                return $0.id < $1.id
            }) {
                return (
                    userId, chosen.id,
                    "aggregateLevelMatch level=\(level) candidateCount=\(candidates.count) resolved=\(chosen.id)"
                )
            }
        }

        return (
            userId, 0,
            "unresolved memberIds=\(memberIds) apiRoleIds=\(apiUserRoleIds) userListMax=\(userListCache?.maxLevelPermission ?? -1)"
        )
    }

    // MARK: - Channel members / roles fetching

    func fetchChannelMembers(clanId: Int64, channelId: Int64, channelType: Int32) async -> [Int64] {
        guard let token = await context.getToken() else { return [] }
        do {
            let response = try await context.engine.account.network.listChannelUsersUC(
                channelId: channelId,
                token: token)
            return response.userIds
        } catch {
            return []
        }
    }

    func channelRoles(clanId: Int64, channelId: Int64) -> [Mezon_Api_Role] {
        roles(clanId: clanId).filter { roleIsInChannel($0, channelId: channelId) && !isEveryone($0) }
    }

    // MARK: - Mutations

    func changeChannelPrivate(
        clanId: Int64,
        channelId: Int64,
        makePrivate: Bool
    ) async throws {
        guard let token = await context.getToken() else {
            throw NSError(domain: "session", code: -1)
        }
        let uid: Int64 = (context.currentUser?.id).flatMap(Int64.init) ?? 0
        // UpdateChannelPrivate uses an action flag: 0 makes private, 1 publishes.
        try await context.engine.account.network.changeChannelPrivate(
            clanId: clanId,
            channelId: channelId,
            channelPrivate: makePrivate ? 0 : 1,
            userIds: uid != 0 ? [uid] : [],
            roleIds: [],
            token: token
        )
        if makePrivate {
            clearLocalRoleChannels(clanId: clanId, channelId: channelId)
        }
        context.engine.clanData.updateChannelPrivateLocally(
            clanId: clanId, channelId: channelId, isPrivate: makePrivate
        )
    }

    func removeChannelUser(channelId: Int64, userId: Int64) async throws {
        guard let token = await context.getToken() else { return }
        try await context.engine.account.network.removeChannelUsers(
            channelId: channelId,
            userIds: [userId],
            token: token
        )
    }

    func removeChannelRole(channelId: Int64, clanId: Int64, roleId: Int64) async throws {
        guard let token = await context.getToken() else { return }
        try await context.engine.account.network.deleteRoleChannelDesc(
            roleId: roleId,
            clanId: clanId,
            channelId: channelId,
            token: token
        )
        removeLocalRoleChannel(clanId: clanId, roleId: roleId, channelId: channelId)
    }

    func addChannelMembers(channelId: Int64, userIds: [Int64]) async throws {
        guard !userIds.isEmpty, let token = await context.getToken() else { return }
        try await context.engine.account.network.addChannelUsers(
            channelId: channelId,
            userIds: userIds,
            token: token
        )
    }

    func addChannelRoles(channelId: Int64, clanId: Int64, roleIds: [Int64]) async throws {
        guard !roleIds.isEmpty, let token = await context.getToken() else { return }
        try await context.engine.account.network.addRoleChannelDesc(
            channelId: channelId,
            roleIds: roleIds,
            token: token
        )
        for roleId in roleIds {
            addLocalRoleChannel(clanId: clanId, roleId: roleId, channelId: channelId)
        }
    }

    // MARK: - Advanced permissions

    func fetchPermissionOverrides(channelId: Int64, roleId: Int64, userId: Int64) async -> [Mezon_Api_PermissionRoleChannel] {
        guard let token = await context.getToken() else { return [] }
        do {
            let response = try await context.engine.account.network.getPermissionByRoleIdChannelId(
                roleId: roleId,
                channelId: channelId,
                userId: userId,
                token: token
            )
            return response.permissionRoleChannel
        } catch {
            return []
        }
    }

    func setPermissionOverrides(
        clanId: Int64,
        channelId: Int64,
        roleId: Int64,
        userId: Int64,
        roleLabel: String = "",
        permissionUpdates: [(permissionId: Int64, slug: String, status: PermissionStatus)]
    ) async throws {
        guard let token = await context.getToken() else {
            throw NSError(domain: "session", code: -1)
        }
        let maxPermissionRoleId = myMaxPermissionRoleId(clanId: clanId)
        let maxPermissionIdSent: Int64 = userId != 0 ? 0 : maxPermissionRoleId
        let protoUpdates: [Mezon_Api_PermissionUpdate] = permissionUpdates.map { (id, slug, status) in
            var p = Mezon_Api_PermissionUpdate()
            p.permissionID = id
            p.slug = slug
            p.type = status.apiType
            return p
        }
        try await context.engine.account.network.setRoleChannelPermission(
            roleId: roleId,
            channelId: channelId,
            userId: userId,
            maxPermissionId: maxPermissionIdSent,
            permissions: protoUpdates,
            roleLabel: roleLabel,
            token: token
        )
    }

    // MARK: - Local cache mutation

    private func addLocalRoleChannel(clanId: Int64, roleId: Int64, channelId: Int64) {
        var container = context.engine.clanData.getClanRoles(clanId: clanId) ?? Mezon_Api_RoleListEventResponse()
        guard let idx = container.roles.roles.firstIndex(where: { $0.id == roleId }) else { return }
        var role = container.roles.roles[idx]
        if !role.channelIds.contains(channelId) {
            role.channelIds.append(channelId)
        }
        container.roles.roles[idx] = role
        persistLocalRoles(container, clanId: clanId)
    }

    private func removeLocalRoleChannel(clanId: Int64, roleId: Int64, channelId: Int64) {
        var container = context.engine.clanData.getClanRoles(clanId: clanId) ?? Mezon_Api_RoleListEventResponse()
        guard let idx = container.roles.roles.firstIndex(where: { $0.id == roleId }) else { return }
        var role = container.roles.roles[idx]
        role.channelIds.removeAll { $0 == channelId }
        container.roles.roles[idx] = role
        persistLocalRoles(container, clanId: clanId)
    }

    private func clearLocalRoleChannels(clanId: Int64, channelId: Int64) {
        var container = context.engine.clanData.getClanRoles(clanId: clanId) ?? Mezon_Api_RoleListEventResponse()
        var changed = false
        for idx in container.roles.roles.indices {
            let before = container.roles.roles[idx].channelIds.count
            container.roles.roles[idx].channelIds.removeAll { $0 == channelId }
            if container.roles.roles[idx].channelIds.count != before {
                changed = true
            }
        }
        guard changed else { return }
        persistLocalRoles(container, clanId: clanId)
    }

    private func persistLocalRoles(_ container: Mezon_Api_RoleListEventResponse, clanId: Int64) {
        if let data = try? container.serializedData() {
            context.engine.account.postbox.setPreferenceDataSync(
                key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
        }
        context.rolePermissions.invalidateRolesCache()
        context.engine.clanData.clanRolesUpdated.putNext(clanId)
    }
}
