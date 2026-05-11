import Foundation

enum EPermission: String, CaseIterable {
    case clanOwner       = "clan-owner"
    case administrator   = "administrator"
    case viewChannel     = "view-channel"
    case manageChannel   = "manage-channel"
    case manageClan      = "manage-clan"
}

enum EOverriddenPermission: String, CaseIterable {
    case manageThread    = "manage-thread"
    case sendMessage     = "send-message"
    case deleteMessage   = "delete-message"
}

enum RolePermissionConstants {
    static let defaultRoleColor = "#99aab5"
    static let defaultMessageCreatorNameDisplayColor = "#17ac86"
}
