import Foundation

enum EventEditorAccess {
    @MainActor
    static func canEdit(_ event: Mezon_Api_EventManagement, context: AccountContext) -> Bool {
        let userId = Int64(context.currentUser?.id ?? context.account.id) ?? 0
        return (userId != 0 && userId == event.creatorID) ||
            context.rolePermissions.hasClanPermission(.clanOwner, clanId: event.clanID) ||
            context.rolePermissions.hasClanPermission(.manageClan, clanId: event.clanID) ||
            context.rolePermissions.hasClanPermission(.administrator, clanId: event.clanID)
    }

    @MainActor
    static func canEnd(_ event: Mezon_Api_EventManagement, context: AccountContext) -> Bool {
        EventDisplayHelper.resolvedStatus(for: event) == .ongoing &&
            context.rolePermissions.hasClanPermission(.clanOwner, clanId: event.clanID)
    }

    static func voiceChannels(_ channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
        channels.filter { $0.type == MezonConstants.ChannelType.mezonVoice.rawValue }
    }

    static func announcementChannels(_ channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
        channels.filter {
            $0.channelPrivate != 0 && ($0.type == MezonConstants.ChannelType.channel.rawValue || $0.type == MezonConstants.ChannelType.thread.rawValue)
        }
    }
}
