import Foundation
import SwiftProtobuf

final class RolesRepository {

    private let context: AccountContext

    init(context: AccountContext) {
        self.context = context
    }

    // MARK: - Reads

    func roles(clanId: Int64) -> [Mezon_Api_Role] {
        guard clanId != 0 else { return [] }
        guard let response = context.engine.clanData.getClanRoles(clanId: clanId) else { return [] }
        let active = response.roles.roles.filter { $0.active != 0 }
        let indexed = active.enumerated().map { (idx: $0.offset, role: $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.role.orderRole != rhs.role.orderRole {
                return lhs.role.orderRole < rhs.role.orderRole
            }
            return lhs.idx < rhs.idx
        }
        return sorted.map { $0.role }
    }

    func role(roleId: Int64, clanId: Int64) -> Mezon_Api_Role? {
        roles(clanId: clanId).first { $0.id == roleId }
    }

    func everyoneRole(clanId: Int64) -> Mezon_Api_Role? {
        let slug = "everyone-\(clanId)"
        return roles(clanId: clanId).first { $0.slug == slug }
    }

    func isEveryone(role: Mezon_Api_Role) -> Bool {
        role.slug == "everyone-\(role.clanID)"
    }

    func allPermissions() -> [Mezon_Api_Permission] {
        context.engine.clanData.getAllPermissions()?.permissions ?? []
    }

    func clanMembers(clanId: Int64) -> [ClanMemberRecord] {
        context.engine.account.postbox.read { $0.getClanMembers(clanId: clanId) }
    }

    // MARK: - Mutations

    @available(iOS 13.0, *)
    @MainActor
    func refresh(clanId: Int64) async {
        guard clanId != 0 else { return }
        guard let token = await context.getToken() else { return }
        do {
            let response = try await context.engine.account.network.listRoles(clanId: clanId, token: token)
            if let data = try? response.serializedData() {
                context.engine.account.postbox.setPreferenceData(
                    key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
            }
            context.rolePermissions.invalidateRolesCache()
            context.engine.clanData.clanRolesUpdated.putNext(clanId)
        } catch {}
    }

    @discardableResult
    @available(iOS 13.0, *)
    func createRole(
        clanId: Int64,
        title: String,
        color: String,
        roleIcon: String,
        addUserIds: [Int64],
        activePermissionIds: [Int64]
    ) async throws -> Mezon_Api_Role {
        guard let token = await context.getToken() else {
            throw RolesRepositoryError.notAuthenticated
        }
        var req = Mezon_Api_CreateRoleRequest()
        req.title = title
        req.color = color
        req.roleIcon = roleIcon
        req.clanID = clanId
        req.addUserIds = addUserIds
        req.activePermissionIds = activePermissionIds
        req.allowMention = 0
        req.displayOnline = 0
        req.maxPermissionID = 0

        let role = try await context.engine.account.network.createRole(request: req, token: token)
        applyCreated(role: role, clanId: clanId)
        await refresh(clanId: clanId)
        return role
    }

    @available(iOS 13.0, *)
    func updateRole(
        roleId: Int64,
        clanId: Int64,
        title: String?,
        color: String?,
        roleIcon: String?,
        addUserIds: [Int64],
        activePermissionIds: [Int64],
        removeUserIds: [Int64],
        removePermissionIds: [Int64]
    ) async throws {
        guard let token = await context.getToken() else {
            throw RolesRepositoryError.notAuthenticated
        }
        var req = Mezon_Api_UpdateRoleRequest()
        req.roleID = roleId
        req.clanID = clanId
        if let title { req.title = SwiftProtobuf.Google_Protobuf_StringValue.with { $0.value = title } }
        if let color { req.color = SwiftProtobuf.Google_Protobuf_StringValue.with { $0.value = color } }
        if let roleIcon { req.roleIcon = SwiftProtobuf.Google_Protobuf_StringValue.with { $0.value = roleIcon } }
        req.addUserIds = addUserIds
        req.activePermissionIds = activePermissionIds
        req.removeUserIds = removeUserIds
        req.removePermissionIds = removePermissionIds
        req.allowMention = 0
        req.displayOnline = 0
        req.maxPermissionID = 0

        try await context.engine.account.network.updateRole(request: req, token: token)

        applyUpdated(
            roleId: roleId, clanId: clanId,
            title: title, color: color, roleIcon: roleIcon,
            addUserIds: addUserIds, activePermissionIds: activePermissionIds,
            removeUserIds: removeUserIds, removePermissionIds: removePermissionIds
        )
        mutateStoredClanMemberRoleIds(
            roleId: roleId,
            clanId: clanId,
            addUserIds: addUserIds,
            removeUserIds: removeUserIds
        )
    }

    @available(iOS 13.0, *)
    @MainActor
    func fetchRoleMembers(roleId: Int64, clanId: Int64) async {
        guard roleId != 0, let token = await context.getToken() else { return }
        do {
            let response = try await context.engine.account.network.listRoleUsers(
                roleId: roleId, token: token)
            applyFetchedRoleUsers(roleId: roleId, clanId: clanId, users: response.roleUsers)
        } catch {}
    }

    private func applyFetchedRoleUsers(
        roleId: Int64, clanId: Int64, users: [Mezon_Api_RoleUserList.RoleUser]
    ) {
        let previousUserIds =
            role(roleId: roleId, clanId: clanId)?.roleUserList.roleUsers.map(\.id) ?? []
        mutateStoredRoles(clanId: clanId) { container in
            guard let idx = container.roles.roles.firstIndex(where: { $0.id == roleId }) else { return }
            var role = container.roles.roles[idx]
            role.roleUserList.roleUsers = users
            container.roles.roles[idx] = role
        }
        let newUserIds = Set(users.map(\.id))
        let oldUserIds = Set(previousUserIds)
        mutateStoredClanMemberRoleIds(
            roleId: roleId,
            clanId: clanId,
            addUserIds: Array(newUserIds.subtracting(oldUserIds)),
            removeUserIds: Array(oldUserIds.subtracting(newUserIds))
        )
    }

    @available(iOS 13.0, *)
    @MainActor
    func deleteRole(roleId: Int64, clanId: Int64) async throws {
        guard let token = await context.getToken() else {
            throw RolesRepositoryError.notAuthenticated
        }
        try await context.engine.account.network.deleteRole(
            roleId: roleId, clanId: clanId, token: token)
        applyDeleted(roleId: roleId, clanId: clanId)
    }

    // MARK: - Local cache merge

    private func applyCreated(role: Mezon_Api_Role, clanId: Int64) {
        mutateStoredRoles(clanId: clanId) { container in
            container.roles.roles.append(role)
        }
    }

    private func applyUpdated(
        roleId: Int64,
        clanId: Int64,
        title: String?,
        color: String?,
        roleIcon: String?,
        addUserIds: [Int64],
        activePermissionIds: [Int64],
        removeUserIds: [Int64],
        removePermissionIds: [Int64]
    ) {
        let permissionById = Dictionary(allPermissions().map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let memberLookup = Dictionary(clanMembers(clanId: clanId).map { ($0.userId, $0) }, uniquingKeysWith: { $1 })

        mutateStoredRoles(clanId: clanId) { container in
            guard let idx = container.roles.roles.firstIndex(where: { $0.id == roleId }) else { return }
            var role = container.roles.roles[idx]
            if let title { role.title = title }
            if let color { role.color = color }
            if let roleIcon { role.roleIcon = roleIcon }

            let removePerm = Set(removePermissionIds)
            var perms = role.permissionList.permissions.filter { !removePerm.contains($0.id) }
            let existingPermIds = Set(perms.map { $0.id })
            for id in activePermissionIds where !existingPermIds.contains(id) {
                if var p = permissionById[id] {
                    p.active = 1
                    perms.append(p)
                }
            }
            role.permissionList.permissions = perms

            let removeUser = Set(removeUserIds)
            var users = role.roleUserList.roleUsers.filter { !removeUser.contains($0.id) }
            let existingUserIds = Set(users.map { $0.id })
            for uid in addUserIds where !existingUserIds.contains(uid) {
                if let member = memberLookup[uid] {
                    var u = Mezon_Api_RoleUserList.RoleUser()
                    u.id = uid
                    u.username = member.username
                    u.displayName = member.displayName
                    u.avatarURL = member.clanAvatar.isEmpty ? member.userAvatarURL : member.clanAvatar
                    u.online = member.isOnline
                    users.append(u)
                }
            }
            role.roleUserList.roleUsers = users
            container.roles.roles[idx] = role
        }
    }

    private func applyDeleted(roleId: Int64, clanId: Int64) {
        mutateStoredRoles(clanId: clanId) { container in
            container.roles.roles.removeAll { $0.id == roleId }
        }
    }

    private func mutateStoredRoles(clanId: Int64, _ block: (inout Mezon_Api_RoleListEventResponse) -> Void) {
        var container = context.engine.clanData.getClanRoles(clanId: clanId) ?? Mezon_Api_RoleListEventResponse()
        block(&container)
        if let data = try? container.serializedData() {
            context.engine.account.postbox.setPreferenceDataSync(
                key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
        }
        context.rolePermissions.invalidateRolesCache()
        context.engine.clanData.clanRolesUpdated.putNext(clanId)
    }

    private func mutateStoredClanMemberRoleIds(
        roleId: Int64,
        clanId: Int64,
        addUserIds: [Int64],
        removeUserIds: [Int64]
    ) {
        guard !addUserIds.isEmpty || !removeUserIds.isEmpty else { return }
        let addSet = Set(addUserIds)
        let removeSet = Set(removeUserIds)
        var updatedMembers: [ClanMemberRecord] = []

        context.engine.account.postbox.writeSync { tx in
            let members = tx.getClanMembers(clanId: clanId)
            guard !members.isEmpty else { return }
            var changed = false
            updatedMembers = members.map { member in
                var roleIds = member.roleIds
                if removeSet.contains(member.userId) {
                    let filtered = roleIds.filter { $0 != roleId }
                    if filtered != roleIds {
                        roleIds = filtered
                        changed = true
                    }
                }
                if addSet.contains(member.userId), !roleIds.contains(roleId) {
                    roleIds.append(roleId)
                    changed = true
                }
                guard roleIds != member.roleIds else { return member }
                return ClanMemberRecord(
                    userId: member.userId,
                    roleIds: roleIds,
                    clanNick: member.clanNick,
                    clanAvatar: member.clanAvatar,
                    userAvatarURL: member.userAvatarURL,
                    clanId: member.clanId,
                    isOnline: member.isOnline,
                    displayName: member.displayName,
                    username: member.username
                )
            }
            if changed {
                tx.updateClanMembers(updatedMembers, clanId: clanId)
            } else {
                updatedMembers = []
            }
        }

        guard !updatedMembers.isEmpty else { return }
        var list = Mezon_Api_ClanUserList()
        list.clanID = clanId
        list.clanUsers = updatedMembers.map { $0.toClanUserListClanUser() }
        if let data = try? list.serializedData() {
            context.engine.account.postbox.setPreferenceDataSync(
                key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
        }
        context.engine.clanData.clanUsersUpdated.putNext(clanId)
    }

    // MARK: - Permission gates

    func userMaxPermissionLevel(clanId: Int64) -> Int32 {
        context.rolePermissions.userMaxPermissionLevel(clanId: clanId)
    }

    func isClanOwner(clanId: Int64) -> Bool {
        context.rolePermissions.isClanOwner(clanId: clanId)
    }

    func hasClanPermission(_ permission: EPermission, clanId: Int64) -> Bool {
        context.rolePermissions.hasClanPermission(permission, clanId: clanId)
    }

    func canManageRoles(clanId: Int64) -> Bool {
        context.rolePermissions.canManageRoles(clanId: clanId)
    }

    func canEditRole(_ role: Mezon_Api_Role, clanId: Int64) -> Bool {
        if isClanOwner(clanId: clanId) { return true }
        if !canManageRoles(clanId: clanId) { return false }
        let userLevel = userMaxPermissionLevel(clanId: clanId)
        return userLevel > role.maxLevelPermission
    }
}

enum RolesRepositoryError: Error {
    case notAuthenticated
}
