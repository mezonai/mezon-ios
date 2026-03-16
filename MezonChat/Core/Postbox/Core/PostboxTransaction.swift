import Foundation

final class PostboxTransaction {

    let channelTable:              ChannelTable
    let clanTable:                 ClanTable
    let messageTable:              MessageTable
    let authTable:                 AuthTable
    let profileTable:              ProfileTable
    let settingsTable:             SettingsTable
    let notificationSettingTable:  NotificationSettingTable
    let notificationTable:         NotificationTable

    private(set) var updatedChannelClanIds:     Set<Int64>   = []
    private(set) var updatedClans:              Bool         = false
    private(set) var updatedMessageChannelIds:  Set<String>  = []
    private(set) var updatedChannelMetaIds:     Set<Int64>   = []
    private(set) var updatedNotificationSettingIds: Set<Int64> = []
    private(set) var updatedNotificationKeys:   Set<String>  = []

    init(
        channelTable: ChannelTable,
        clanTable: ClanTable,
        messageTable: MessageTable,
        authTable: AuthTable,
        profileTable: ProfileTable,
        settingsTable: SettingsTable,
        notificationSettingTable: NotificationSettingTable,
        notificationTable: NotificationTable
    ) {
        self.channelTable              = channelTable
        self.clanTable                 = clanTable
        self.messageTable              = messageTable
        self.authTable                 = authTable
        self.profileTable              = profileTable
        self.settingsTable             = settingsTable
        self.notificationSettingTable  = notificationSettingTable
        self.notificationTable         = notificationTable
    }

    func getChannels(clanId: Int64) -> [ChannelRecord] {
        channelTable.getChannels(clanId: clanId)
    }

    func updateChannels(_ channels: [ChannelRecord], clanId: Int64) {
        channelTable.setChannels(channels, clanId: clanId)
        updatedChannelClanIds.insert(clanId)
    }

    func deleteChannels(clanId: Int64) {
        channelTable.deleteChannels(clanId: clanId)
        updatedChannelClanIds.insert(clanId)
    }

    func getClans() -> [ClanRecord]        { clanTable.getAllClans() }
    func getClan(id: Int64) -> ClanRecord? { clanTable.getClan(id: id) }

    func updateClans(_ clans: [ClanRecord]) {
        clanTable.setClans(clans)
        updatedClans = true
    }

    func deleteClan(id: Int64) {
        clanTable.deleteClan(id: id)
        updatedClans = true
    }

    func getMessages(channelId: String, limit: Int = 50) -> [MessageRecord] {
        messageTable.getMessages(channelId: channelId, limit: limit)
    }

    func addMessages(_ messages: [MessageRecord]) {
        messageTable.addMessages(messages)
        for m in messages { updatedMessageChannelIds.insert(m.channelId) }
    }

    func deleteMessage(id: String) {
        messageTable.deleteMessage(id: id)
    }

    func markMessageFailed(id: String) {
        messageTable.markMessageFailed(id: id)
    }

    func replaceMessage(pendingId: String, with record: MessageRecord) {
        messageTable.replaceMessage(pendingId: pendingId, with: record)
        updatedMessageChannelIds.insert(record.channelId)
    }

    func updateNotifications(_ notifications: [Notifications], clanId: Int64, category: Int32) {
        notificationTable.replaceNotifications(notifications, clanId: clanId, category: category)
        updatedNotificationKeys.insert("\(clanId)_\(category)")
    }

    func appendNotifications(_ notifications: [Notifications], clanId: Int64, category: Int32) {
        notificationTable.appendNotifications(notifications, clanId: clanId, category: category)
        updatedNotificationKeys.insert("\(clanId)_\(category)")
    }

    func getCurrentSession() -> AuthRecord? { authTable.getCurrentSession() }
    func setSession(_ record: AuthRecord?)  { authTable.setSession(record) }

    func getProfile(userId: String) -> ProfileRecord?  { profileTable.getProfile(userId: userId) }
    func updateProfile(_ record: ProfileRecord)         { profileTable.setProfile(record) }

    func getSetting(key: String) -> Data?                        { settingsTable.get(key: key) }
    func getSetting<T: PostboxCoding>(key: String, type: T.Type) -> T? { settingsTable.get(key: key, type: type) }
    func setSetting(key: String, value: Data?)                   { settingsTable.set(key: key, value: value) }
    func setSetting<T: PostboxCoding>(key: String, value: T?)    { settingsTable.set(key: key, value: value) }

    // MARK: - Channel Meta

    func getChannelMeta(channelId: Int64) -> ChannelRecord? {
        channelTable.getChannelMeta(channelId: channelId)
    }

    // MARK: - Notification Settings

    func getNotificationSetting(entityId: Int64) -> NotificationSettingRecord? {
        notificationSettingTable.get(entityId: entityId)
    }

    func updateNotificationSetting(_ record: NotificationSettingRecord) {
        notificationSettingTable.set(record)
        updatedNotificationSettingIds.insert(record.entityId)
    }

    func updateChannelPermissions(_ permissions: [PermissionRecord], channelId: Int64) {
        channelTable.updatePermissions(permissions, channelId: channelId)
        updatedChannelMetaIds.insert(channelId)
    }

    func updateChannelMembers(_ members: [ChannelMemberRecord], channelId: Int64) {
        channelTable.updateMembers(members, channelId: channelId)
        updatedChannelMetaIds.insert(channelId)
    }

    func updateBanStatus(isBanned: Bool, expiredBanTime: Int32, channelId: Int64) {
        channelTable.updateBanStatus(isBanned: isBanned, expiredBanTime: expiredBanTime, channelId: channelId)
        updatedChannelMetaIds.insert(channelId)
    }

    var isEmpty: Bool {
        updatedChannelClanIds.isEmpty && !updatedClans && updatedMessageChannelIds.isEmpty && updatedChannelMetaIds.isEmpty && updatedNotificationSettingIds.isEmpty && updatedNotificationKeys.isEmpty
    }
}
