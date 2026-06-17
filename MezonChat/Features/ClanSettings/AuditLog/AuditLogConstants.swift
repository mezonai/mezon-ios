import Foundation

enum AuditLogAction: String, CaseIterable {
    case allActionAudit = ""
    case updateClanActionAudit = "Update Clan"
    case createChannelActionAudit = "Create Channel"
    case updateChannelActionAudit = "Update Channel"
    case updateChannelPrivateActionAudit = "Update Channel Private"
    case deleteChanneActionAudit = "Delete Channe" 
    case createChannelPermissionActionAudit = "Create Channel Permission"
    case updateChannelPermissionActionAudit = "Update Channel Permission"
    case deleteChannelPermissionActionAudit = "Delete Channel Permission"
    case kickMemberActionAudit = "Kick Member"
    case pruneMemberActionAudit = "Prune Member"
    case banMemberActionAudit = "Ban Member"
    case unbanMemberActionAudit = "Unban Member"
    case updateMemberActionAudit = "Update Member"
    case updateRolesMemberActionAudit = "Update Roles Member"
    case moveMemberActionAudit = "Move Member"
    case disconnectMemberActionAudit = "Disconnect Member"
    case addBotActionAudit = "Add Bot"
    case createThreadActionAudit = "Create Thread"
    case updateThreadActionAudit = "Update Thread"
    case deleteThreadActionAudit = "Delete Thread"
    case createRoleActionAudit = "Create Role"
    case updateRoleActionAudit = "Update Role"
    case deleteRoleActionAudit = "Delete Role"
    case createWebhookActionAudit = "Create Webhook"
    case updateWebhookActionAudit = "Update Webhook"
    case deleteWebhookActionAudit = "Delete Webhook"
    case createEmojiActionAudit = "Create Emoji"
    case updateEmojiActionAudit = "Update Emoji"
    case deleteEmojiActionAudit = "Delete Emoji"
    case createStickerActionAudit = "Create Sticker"
    case updateStickerActionAudit = "Update Sticker"
    case deleteStickerActionAudit = "Delete Sticker"
    case createEventActionAudit = "Create Event"
    case updateEventActionAudit = "Update Event"
    case deleteEventActionAudit = "Delete Event"
    case createCanvasActionAudit = "Create Canvas"
    case updateCanvasActionAudit = "Update Canvas"
    case deleteCanvasActionAudit = "Delete Canvas"
    case createCategoryActionAudit = "Create Category"
    case updateCategoryActionAudit = "Update Category"
    case deleteCategoryActionAudit = "Delete Category"
    case addMemberChannelActionAudit = "Add Member Channel"
    case removeMemberChannelActionAudit = "Remove Member Channel"
    case addRoleChannelActionAudit = "Add Role Channel"
    case removeRoleChannelActionAudit = "Remove Role Channel"
    case addMemberThreadActionAudit = "Add Member Thread"
    case removeMemberThreadActionAudit = "Remove Member Thread"
    case addRoleThreadActionAudit = "Add Role Thread"
    case removeRoleThreadActionAudit = "Remove Role Thread"

    var isAddAction: Bool {
        switch self {
        case .addMemberChannelActionAudit, .addRoleChannelActionAudit:
            return true
        default:
            return false
        }
    }

    var isRemoveAction: Bool {
        switch self {
        case .removeMemberChannelActionAudit, .removeRoleChannelActionAudit:
            return true
        default:
            return false
        }
    }

    var isChannelAction: Bool {
        return isAddAction || isRemoveAction
    }
    
    var localizedString: String {
        switch self {
        case .allActionAudit: return L(L10n.AuditLog.allActions)
        case .updateClanActionAudit: return L(L10n.AuditLog.updateClan)
        case .createChannelActionAudit: return L(L10n.AuditLog.createChannel)
        case .updateChannelActionAudit: return L(L10n.AuditLog.updateChannel)
        case .updateChannelPrivateActionAudit: return L(L10n.AuditLog.updateChannelPrivate)
        case .deleteChanneActionAudit: return L(L10n.AuditLog.deleteChannel)
        case .createChannelPermissionActionAudit: return L(L10n.AuditLog.createChannelPermission)
        case .updateChannelPermissionActionAudit: return L(L10n.AuditLog.updateChannelPermission)
        case .deleteChannelPermissionActionAudit: return L(L10n.AuditLog.deleteChannelPermission)
        case .kickMemberActionAudit: return L(L10n.AuditLog.kickMember)
        case .pruneMemberActionAudit: return L(L10n.AuditLog.pruneMember)
        case .banMemberActionAudit: return L(L10n.AuditLog.banMember)
        case .unbanMemberActionAudit: return L(L10n.AuditLog.unbanMember)
        case .updateMemberActionAudit: return L(L10n.AuditLog.updateMember)
        case .updateRolesMemberActionAudit: return L(L10n.AuditLog.updateRolesMember)
        case .moveMemberActionAudit: return L(L10n.AuditLog.moveMember)
        case .disconnectMemberActionAudit: return L(L10n.AuditLog.disconnectMember)
        case .addBotActionAudit: return L(L10n.AuditLog.addBot)
        case .createThreadActionAudit: return L(L10n.AuditLog.createThread)
        case .updateThreadActionAudit: return L(L10n.AuditLog.updateThread)
        case .deleteThreadActionAudit: return L(L10n.AuditLog.deleteThread)
        case .createRoleActionAudit: return L(L10n.AuditLog.createRole)
        case .updateRoleActionAudit: return L(L10n.AuditLog.updateRole)
        case .deleteRoleActionAudit: return L(L10n.AuditLog.deleteRole)
        case .createWebhookActionAudit: return L(L10n.AuditLog.createWebhook)
        case .updateWebhookActionAudit: return L(L10n.AuditLog.updateWebhook)
        case .deleteWebhookActionAudit: return L(L10n.AuditLog.deleteWebhook)
        case .createEmojiActionAudit: return L(L10n.AuditLog.createEmoji)
        case .updateEmojiActionAudit: return L(L10n.AuditLog.updateEmoji)
        case .deleteEmojiActionAudit: return L(L10n.AuditLog.deleteEmoji)
        case .createStickerActionAudit: return L(L10n.AuditLog.createSticker)
        case .updateStickerActionAudit: return L(L10n.AuditLog.updateSticker)
        case .deleteStickerActionAudit: return L(L10n.AuditLog.deleteSticker)
        case .createEventActionAudit: return L(L10n.AuditLog.createEvent)
        case .updateEventActionAudit: return L(L10n.AuditLog.updateEvent)
        case .deleteEventActionAudit: return L(L10n.AuditLog.deleteEvent)
        case .createCanvasActionAudit: return L(L10n.AuditLog.createCanvas)
        case .updateCanvasActionAudit: return L(L10n.AuditLog.updateCanvas)
        case .deleteCanvasActionAudit: return L(L10n.AuditLog.deleteCanvas)
        case .createCategoryActionAudit: return L(L10n.AuditLog.createCategory)
        case .updateCategoryActionAudit: return L(L10n.AuditLog.updateCategory)
        case .deleteCategoryActionAudit: return L(L10n.AuditLog.deleteCategory)
        case .addMemberChannelActionAudit: return L(L10n.AuditLog.addMemberChannel)
        case .removeMemberChannelActionAudit: return L(L10n.AuditLog.removeMemberChannel)
        case .addRoleChannelActionAudit: return L(L10n.AuditLog.addRoleChannel)
        case .removeRoleChannelActionAudit: return L(L10n.AuditLog.removeRoleChannel)
        case .addMemberThreadActionAudit: return L(L10n.AuditLog.addMemberThread)
        case .removeMemberThreadActionAudit: return L(L10n.AuditLog.removeMemberThread)
        case .addRoleThreadActionAudit: return L(L10n.AuditLog.addRoleThread)
        case .removeRoleThreadActionAudit: return L(L10n.AuditLog.removeRoleThread)
        default: return rawValue.replacingOccurrences(of: "_ACTION_AUDIT", with: "").lowercased()
        }
    }
}
