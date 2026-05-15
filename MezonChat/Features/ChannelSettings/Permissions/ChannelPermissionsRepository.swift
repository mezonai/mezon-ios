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

    func clanOwnerId(clanId: Int64) -> String? {
        context.engine.account.postbox.read { tx in
            tx.getClan(id: clanId)?.ownerId
        }
    }

    func allPermissions() -> [Mezon_Api_Permission] {
        context.engine.clanData.getAllPermissions()?.permissions ?? []
    }

    func myMaxPermissionRoleId(clanId: Int64) -> Int64 {
        guard let uid = context.currentUser?.id, let userId = Int64(uid) else { return 0 }
        let allRoles = roles(clanId: clanId)
        var max: Int32 = 0
        var maxRoleId: Int64 = 0
        for role in allRoles {
            let belongs = role.roleUserList.roleUsers.contains(where: { $0.id == userId })
            guard belongs else { continue }
            if role.maxLevelPermission > max {
                max = role.maxLevelPermission
                maxRoleId = role.id
            }
        }
        return maxRoleId
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
        roles(clanId: clanId).filter { $0.roleChannelActive == 1 && !isEveryone($0) }
    }

    // MARK: - Mutations

    func changeChannelPrivate(
        clanId: Int64,
        channelId: Int64,
        makePrivate: Bool
    ) async throws {
        guard let token = await context.getToken() else { return }
        let uid: Int64 = (context.currentUser?.id).flatMap(Int64.init) ?? 0
        try await context.engine.account.network.changeChannelPrivate(
            clanId: clanId,
            channelId: channelId,
            channelPrivate: makePrivate ? 1 : 0,
            userIds: uid != 0 ? [uid] : [],
            roleIds: [],
            token: token
        )
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
        mutateLocalRoleChannelActive(clanId: clanId, roleId: roleId, active: 0)
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
            mutateLocalRoleChannelActive(clanId: clanId, roleId: roleId, active: 1)
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
        permissionUpdates: [(permissionId: Int64, slug: String, status: PermissionStatus)]
    ) async throws {
        guard let token = await context.getToken() else { return }
        let maxPermissionRoleId = myMaxPermissionRoleId(clanId: clanId)
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
            maxPermissionId: maxPermissionRoleId,
            permissions: protoUpdates,
            token: token
        )
    }

    // MARK: - Local cache mutation

    private func mutateLocalRoleChannelActive(clanId: Int64, roleId: Int64, active: Int32) {
        var container = context.engine.clanData.getClanRoles(clanId: clanId) ?? Mezon_Api_RoleListEventResponse()
        guard let idx = container.roles.roles.firstIndex(where: { $0.id == roleId }) else { return }
        var role = container.roles.roles[idx]
        role.roleChannelActive = active
        container.roles.roles[idx] = role
        if let data = try? container.serializedData() {
            context.engine.account.postbox.setPreferenceDataSync(
                key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
        }
        context.rolePermissions.invalidateRolesCache()
        context.engine.clanData.clanRolesUpdated.putNext(clanId)
    }
}
