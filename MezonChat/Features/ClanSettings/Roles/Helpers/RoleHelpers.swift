import Foundation
import UIKit

enum RoleColors {
    static let palette: [String] = [
        "#1abc9c", "#2ecc71", "#3498db", "#9b59b6", "#e91e63",
        "#f1c40f", "#e67e22", "#e74c3c", "#95a5a6", "#607d8b",
        "#11806a", "#1f8b4c", "#206694", "#71368a", "#ad1457",
        "#c27c0e", "#e84300", "#992d22", "#979c9f", "#546e7a"
    ]

    static func uiColor(forRole role: Mezon_Api_Role) -> UIColor {
        if let color = UIColor(hexString: role.color), !role.color.isEmpty {
            return color
        }
        return UIColor(hexString: RolePermissionConstants.defaultRoleColor) ?? .systemGray
    }
}

enum RolePermissionLocalization {

    static func title(forSlug slug: String, fallback: String) -> String {
        let key = "clanRoles.permissionTitle.\(slug)"
        let translated = L(key)
        return translated != key ? translated : fallback
    }

    static func description(forSlug slug: String) -> String {
        let key = "clanRoles.permissionDescription.\(slug)"
        let translated = L(key)
        if translated != key { return translated }
        return L(L10n.ClanRoles.permissionNotAvailable)
    }

    static func isDisabledFor(
        permission: Mezon_Api_Permission,
        role: Mezon_Api_Role?,
        isClanOwner: Bool,
        hasAdministrator: Bool,
        hasManageClan: Bool,
        canEdit: Bool
    ) -> Bool {
        let slug = permission.slug
        switch slug {
        case EPermission.administrator.rawValue:
            return !isClanOwner || !canEdit
        case EPermission.manageClan.rawValue:
            return (!isClanOwner && !hasAdministrator) || !canEdit
        case EOverriddenPermission.sendMessage.rawValue:
            if let role, role.slug == "everyone-\(role.clanID)" {
                return true
            }
            return !canEdit
        default:
            return !canEdit
        }
    }
}

enum RoleMemberDisplay {

    static func displayName(_ member: ClanMemberRecord) -> String {
        if !member.clanNick.isEmpty { return member.clanNick }
        if !member.displayName.isEmpty { return member.displayName }
        return member.username
    }

    static func avatarURL(_ member: ClanMemberRecord) -> String? {
        if !member.clanAvatar.isEmpty { return member.clanAvatar }
        if !member.userAvatarURL.isEmpty { return member.userAvatarURL }
        return nil
    }

    static func displayName(_ user: Mezon_Api_RoleUserList.RoleUser) -> String {
        if !user.displayName.isEmpty { return user.displayName }
        return user.username
    }

    static func matches(_ member: ClanMemberRecord, query: String) -> Bool {
        let q = normalize(query)
        if q.isEmpty { return true }
        return normalize(member.displayName).contains(q)
            || normalize(member.username).contains(q)
            || normalize(member.clanNick).contains(q)
    }

    static func initials(_ name: String) -> String {
        let words = name
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
        let chars = words.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.joined()
    }

    private static func normalize(_ str: String) -> String {
        str.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}

enum RoleColorString {

    static func hex(_ role: Mezon_Api_Role) -> String {
        role.color.isEmpty ? RolePermissionConstants.defaultRoleColor : role.color
    }
}
