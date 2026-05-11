import Foundation
import SwiftProtobuf

@MainActor
final class RolePermissionService {

    struct UserHighestRole {
        let roleId: Int64
        let color: String
        let icon: String
        let maxLevelPermission: Int32
    }

    struct ChannelOverriddenPermissions {
        var manageThread: Bool
        var sendMessage: Bool
        var deleteMessage: Bool

        static let empty = ChannelOverriddenPermissions(
            manageThread: false, sendMessage: false, deleteMessage: false
        )
    }

    private let engine: MezonEngine
    private let userIdProvider: () -> String?
    private let currentClanIdProvider: () -> Int64
    private let tokenProvider: () async -> String?

    private struct ClanRolesCache {
        let clanId: Int64
        let userIdToHighestRole: [Int64: UserHighestRole]
        let allRolesById: [Int64: Mezon_Api_Role]
    }

    private var cachedClanRoles: ClanRolesCache?

    private var channelPermissionsCache: [Int64: ChannelOverriddenPermissions] = [:]
    private var pendingChannelPermissionFetch: Set<Int64> = []

    private var rolesSubscriptionDisposable: Disposable?
    private var socketDisposable: Disposable?

    init(
        engine: MezonEngine,
        userIdProvider: @escaping () -> String?,
        currentClanIdProvider: @escaping () -> Int64,
        tokenProvider: @escaping () async -> String?
    ) {
        self.engine = engine
        self.userIdProvider = userIdProvider
        self.currentClanIdProvider = currentClanIdProvider
        self.tokenProvider = tokenProvider
    }

    func start() {
        rolesSubscriptionDisposable?.dispose()
        rolesSubscriptionDisposable = (engine.clanData.clanRolesUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.invalidateRolesCache()
        })

        socketDisposable?.dispose()
        socketDisposable = (MezonSocket.shared.events()
            |> deliverOnMainQueue).start(next: { [weak self] event in
            guard let self else { return }
            switch event {
            case .roleEvent, .roleAssign:
                self.invalidateRolesCache()
                self.refreshRolesIfNeeded()
            case .permissionSet(let m):
                if m.channelID != 0 {
                    self.invalidateChannelPermissions(channelId: m.channelID)
                }
            case .permissionChanged(let m):
                if m.channelID != 0 {
                    self.invalidateChannelPermissions(channelId: m.channelID)
                }
            default:
                break
            }
        })
    }

    func stop() {
        rolesSubscriptionDisposable?.dispose()
        rolesSubscriptionDisposable = nil
        socketDisposable?.dispose()
        socketDisposable = nil
    }

    func invalidateRolesCache() {
        cachedClanRoles = nil
        NotificationCenter.default.post(name: .mezonRolesDidChange, object: nil)
    }

    func invalidateChannelPermissions(channelId: Int64? = nil) {
        if let channelId {
            channelPermissionsCache.removeValue(forKey: channelId)
        } else {
            channelPermissionsCache.removeAll()
        }
        NotificationCenter.default.post(
            name: .mezonChannelOverriddenPermissionsDidChange,
            object: nil,
            userInfo: channelId.map { ["channelId": $0] } ?? [:]
        )
    }

    private func refreshRolesIfNeeded() {
        let clanId = currentClanIdProvider()
        guard clanId != 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.tokenProvider() else { return }
            do {
                let response = try await self.engine.account.network.listRoles(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    self.engine.account.postbox.setPreferenceData(
                        key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
                }
                self.invalidateRolesCache()
                self.engine.clanData.clanRolesUpdated.putNext(clanId)
            } catch {}
        }
    }

    private func ensureClanRolesCache(for clanId: Int64) -> ClanRolesCache? {
        guard clanId != 0 else { return nil }
        if let cache = cachedClanRoles, cache.clanId == clanId { return cache }
        guard let response = engine.clanData.getClanRoles(clanId: clanId) else {
            cachedClanRoles = nil
            return nil
        }

        let rolesWithIndex = response.roles.roles
            .filter { $0.active != 0 }
            .enumerated()
            .map { (idx, role) in (idx: idx, role: role) }

        let sortedRoles = rolesWithIndex.sorted { lhs, rhs in
            if lhs.role.orderRole != rhs.role.orderRole {
                return lhs.role.orderRole < rhs.role.orderRole
            }
            return lhs.idx < rhs.idx
        }.map { $0.role }

        var userMap: [Int64: UserHighestRole] = [:]
        var allRolesById: [Int64: Mezon_Api_Role] = [:]
        for role in sortedRoles {
            allRolesById[role.id] = role
            let rawColor = role.color
            let normalizedColor = Self.normalizeHexColor(rawColor)
            let entry = UserHighestRole(
                roleId: role.id,
                color: normalizedColor ?? RolePermissionConstants.defaultRoleColor,
                icon: role.roleIcon,
                maxLevelPermission: role.maxLevelPermission
            )
            for user in role.roleUserList.roleUsers {
                guard user.id != 0 else { continue }
                if let existing = userMap[user.id] {
                    let existingIsDefault = existing.color == RolePermissionConstants.defaultRoleColor
                    let newIsCustom = entry.color != RolePermissionConstants.defaultRoleColor
                    var nextColor = existing.color
                    var nextIcon = existing.icon
                    if existingIsDefault && newIsCustom {
                        nextColor = entry.color
                    }
                    if existing.icon.isEmpty && !entry.icon.isEmpty {
                        nextIcon = entry.icon
                    }
                    if nextColor != existing.color || nextIcon != existing.icon {
                        userMap[user.id] = UserHighestRole(
                            roleId: existing.roleId,
                            color: nextColor,
                            icon: nextIcon,
                            maxLevelPermission: existing.maxLevelPermission
                        )
                    }
                } else {
                    userMap[user.id] = entry
                }
            }
        }
        let cache = ClanRolesCache(
            clanId: clanId,
            userIdToHighestRole: userMap,
            allRolesById: allRolesById
        )
        cachedClanRoles = cache
        return cache
    }

    private static func normalizeHexColor(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard withoutHash.count == 3 || withoutHash.count == 6 || withoutHash.count == 8 else {
            return nil
        }
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard withoutHash.unicodeScalars.allSatisfy({ hexCharSet.contains($0) }) else {
            return nil
        }
        if withoutHash.count == 3 {
            let chars = Array(withoutHash)
            let expanded = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
            return "#" + expanded
        }
        return "#" + withoutHash
    }

    func highestRoleColor(forUserId userId: String, clanId: Int64) -> UIColor? {
        guard let uid = Int64(userId) else { return nil }
        guard let cache = ensureClanRolesCache(for: clanId) else { return nil }
        guard let entry = cache.userIdToHighestRole[uid] else { return nil }
        return UIColor(hexString: entry.color)
    }

    func highestRoleColorHex(forUserId userId: String, clanId: Int64) -> String? {
        guard let uid = Int64(userId) else { return nil }
        guard let cache = ensureClanRolesCache(for: clanId) else { return nil }
        return cache.userIdToHighestRole[uid]?.color
    }

    func highestRoleIconURL(forUserId userId: String, clanId: Int64) -> String? {
        guard let uid = Int64(userId) else { return nil }
        guard let cache = ensureClanRolesCache(for: clanId) else { return nil }
        guard let entry = cache.userIdToHighestRole[uid] else { return nil }
        let icon = entry.icon
        return icon.isEmpty ? nil : icon
    }

    var defaultMessageCreatorNameDisplayColor: UIColor {
        UIColor(hexString: RolePermissionConstants.defaultMessageCreatorNameDisplayColor)
            ?? UIColor.theme.text
    }

    func messageSenderNameColor(
        senderId: String,
        clanId: Int64,
        isClanChannel: Bool,
        fallback: UIColor
    ) -> UIColor {
        if isClanChannel {
            if let color = highestRoleColor(forUserId: senderId, clanId: clanId) {
                return color
            }
            if let defaultColor = UIColor(hexString: RolePermissionConstants.defaultRoleColor) {
                return defaultColor
            }
            return fallback
        }
        return defaultMessageCreatorNameDisplayColor
    }

    func messageSenderRoleIconURL(
        senderId: String,
        clanId: Int64,
        isClanChannel: Bool
    ) -> String? {
        guard isClanChannel else { return nil }
        return highestRoleIconURL(forUserId: senderId, clanId: clanId)
    }

    func userMaxPermissionLevel(clanId: Int64) -> Int32 {
        guard clanId != 0 else { return 0 }
        guard let roleList = engine.clanData.getUserPermissions(clanId: clanId) else { return 0 }
        return roleList.maxLevelPermission
    }

    func isClanOwner(clanId: Int64) -> Bool {
        guard clanId != 0 else { return false }
        guard let userId = userIdProvider(), !userId.isEmpty else { return false }
        let owner = engine.account.postbox.read { tx -> String? in
            tx.getClan(id: clanId)?.ownerId
        }
        guard let owner, !owner.isEmpty else { return false }
        return owner == userId
    }

    private func slugForLookup(_ slug: String) -> String {
        slug.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    private func defaultPermissionLevel(slug: String) -> Int32? {
        let needle = slugForLookup(slug)
        guard let allPerms = engine.clanData.getAllPermissions() else { return nil }
        return allPerms.permissions.first(where: {
            slugForLookup($0.slug) == needle
        })?.level
    }

    func hasClanPermission(_ permission: EPermission, clanId: Int64) -> Bool {
        if permission == .clanOwner {
            return isClanOwner(clanId: clanId)
        }
        if isClanOwner(clanId: clanId) { return true }
        guard let level = defaultPermissionLevel(slug: permission.rawValue) else { return false }
        return level <= userMaxPermissionLevel(clanId: clanId)
    }

    func hasOverriddenPermission(_ permission: EOverriddenPermission, clanId: Int64, channelId: Int64) -> Bool {
        guard channelId != 0 else { return false }
        if isClanOwner(clanId: clanId) { return true }
        if let cached = channelPermissionsCache[channelId] {
            switch permission {
            case .manageThread:  return cached.manageThread
            case .sendMessage:   return cached.sendMessage
            case .deleteMessage: return cached.deleteMessage
            }
        }
        return false
    }

    func ensureChannelPermissions(clanId: Int64, channelId: Int64, force: Bool = false) {
        guard clanId != 0, channelId != 0 else { return }
        if !force && channelPermissionsCache[channelId] != nil { return }
        if pendingChannelPermissionFetch.contains(channelId) { return }
        pendingChannelPermissionFetch.insert(channelId)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingChannelPermissionFetch.remove(channelId) }
            guard let token = await self.tokenProvider() else { return }
            do {
                let response = try await self.engine.account.network.listUserPermissionInChannel(
                    clanId: clanId, channelId: channelId, token: token)
                let perms = response.permissions.permissions
                self.applyChannelPermissions(channelId: channelId, permissions: perms)

                let records = perms.map { PermissionRecord(from: $0) }
                self.engine.account.postbox.write { tx in
                    tx.updateChannelPermissions(records, channelId: channelId)
                }
            } catch {}
        }
    }

    func applyChannelPermissions(channelId: Int64, permissions: [Mezon_Api_Permission]) {
        var result = ChannelOverriddenPermissions.empty
        for perm in permissions {
            let slug = slugForLookup(perm.slug)
            let active = perm.active != 0
            switch slug {
            case EOverriddenPermission.manageThread.rawValue:  result.manageThread = active
            case EOverriddenPermission.sendMessage.rawValue:   result.sendMessage = active
            case EOverriddenPermission.deleteMessage.rawValue: result.deleteMessage = active
            default: break
            }
        }
        channelPermissionsCache[channelId] = result
        NotificationCenter.default.post(
            name: .mezonChannelOverriddenPermissionsDidChange,
            object: nil,
            userInfo: ["channelId": channelId]
        )
    }

    func channelOverriddenPermissions(channelId: Int64) -> ChannelOverriddenPermissions? {
        channelPermissionsCache[channelId]
    }

    func canSendMessage(clanId: Int64, channelId: Int64) -> Bool {
        if clanId == 0 { return true }
        if isClanOwner(clanId: clanId) { return true }
        if hasClanPermission(.administrator, clanId: clanId) { return true }
        if hasOverriddenPermission(.sendMessage, clanId: clanId, channelId: channelId) { return true }
        return hasClanPermission(.manageChannel, clanId: clanId)
    }

    func canDeleteMessage(clanId: Int64, channelId: Int64) -> Bool {
        if clanId == 0 { return false }
        if isClanOwner(clanId: clanId) { return true }
        if hasClanPermission(.administrator, clanId: clanId) { return true }
        if hasOverriddenPermission(.deleteMessage, clanId: clanId, channelId: channelId) { return true }
        return hasClanPermission(.manageChannel, clanId: clanId)
    }

    func canManageThread(clanId: Int64, channelId: Int64) -> Bool {
        if clanId == 0 { return false }
        if isClanOwner(clanId: clanId) { return true }
        if hasClanPermission(.administrator, clanId: clanId) { return true }
        if hasOverriddenPermission(.manageThread, clanId: clanId, channelId: channelId) { return true }
        return hasClanPermission(.manageChannel, clanId: clanId)
    }

    func canManageChannel(clanId: Int64) -> Bool {
        return hasClanPermission(.manageChannel, clanId: clanId)
    }

    func canManageClan(clanId: Int64) -> Bool {
        return hasClanPermission(.manageClan, clanId: clanId)
    }
}

extension Notification.Name {
    static let mezonRolesDidChange = Notification.Name("mezon.roles.didChange")
    static let mezonChannelOverriddenPermissionsDidChange = Notification.Name("mezon.channelPermissions.didChange")
}
