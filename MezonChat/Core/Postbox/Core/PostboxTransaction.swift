import Foundation
import SwiftProtobuf

final class PostboxTransaction {

    let channelTable:              ChannelTable
    let clanTable:                 ClanTable
    let messageTable:              MessageTable
    let authTable:                 AuthTable
    let profileTable:              ProfileTable
    let settingsTable:             SettingsTable
    let notificationSettingTable:  NotificationSettingTable
    let notificationTable:         NotificationTable
    let topicTable:                TopicTable
    let clanMemberTable:           ClanMemberTable

    private(set) var updatedChannelClanIds:     Set<Int64>   = []
    private(set) var updatedClans:              Bool         = false
    private(set) var updatedMessageChannelIds:  Set<String>  = []
    private(set) var updatedChannelMetaIds:     Set<Int64>   = []
    private(set) var updatedNotificationSettingIds: Set<Int64> = []
    private(set) var updatedNotificationKeys:   Set<String>  = []
    private(set) var updatedTopicClanIds:       Set<Int64>   = []
    private(set) var updatedClanMemberIds:      Set<Int64>   = []
    private(set) var updatedProfileUserIds:     Set<String>  = []

    init(
        channelTable: ChannelTable,
        clanTable: ClanTable,
        messageTable: MessageTable,
        authTable: AuthTable,
        profileTable: ProfileTable,
        settingsTable: SettingsTable,
        notificationSettingTable: NotificationSettingTable,
        notificationTable: NotificationTable,
        topicTable: TopicTable,
        clanMemberTable: ClanMemberTable
    ) {
        self.channelTable              = channelTable
        self.clanTable                 = clanTable
        self.messageTable              = messageTable
        self.authTable                 = authTable
        self.profileTable              = profileTable
        self.settingsTable             = settingsTable
        self.notificationSettingTable  = notificationSettingTable
        self.notificationTable         = notificationTable
        self.topicTable                = topicTable
        self.clanMemberTable           = clanMemberTable
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

    func replaceAllMessages(_ messages: [MessageRecord], channelId: String) {
        messageTable.replaceAllMessages(messages, channelId: channelId)
        updatedMessageChannelIds.insert(channelId)
    }

    func deleteMessage(id: String) {
        let channelId = messageTable.channelIdForMessage(id: id)
        messageTable.deleteMessage(id: id)
        if let channelId { updatedMessageChannelIds.insert(channelId) }
    }

    func updateMessageReactions(messageId: String, reaction: Mezon_Api_MessageReaction) {
        if let ch = messageTable.updateMessageReactions(messageId: messageId, reaction: reaction) {
            updatedMessageChannelIds.insert(ch)
        }
    }

    func markMessageFailed(id: String) {
        let channelId = messageTable.channelIdForMessage(id: id)
        messageTable.markMessageFailed(id: id)
        if let channelId { updatedMessageChannelIds.insert(channelId) }
    }

    func markMessageSent(id: String) {
        let channelId = messageTable.channelIdForMessage(id: id)
        messageTable.markMessageSent(id: id)
        if let channelId { updatedMessageChannelIds.insert(channelId) }
    }

    func replaceMessage(pendingId: String, with record: MessageRecord) {
        messageTable.replaceMessage(pendingId: pendingId, with: record)
        updatedMessageChannelIds.insert(record.channelId)
    }

    func updateNotifications(_ notifications: [NotificationRecord], clanId: Int64, category: Int32) {
        notificationTable.replaceNotificationRecord(notifications, clanId: clanId, category: category)
        updatedNotificationKeys.insert("\(clanId)_\(category)")
    }

    func appendNotifications(_ notifications: [NotificationRecord], clanId: Int64, category: Int32) {
        notificationTable.appendNotificationRecord(notifications, clanId: clanId, category: category)
        updatedNotificationKeys.insert("\(clanId)_\(category)")
    }

    func updateTopics(_ topics: [TopicRecord], clanId: Int64) {
        topicTable.updateTopics(topics, clanId: clanId)
        updatedTopicClanIds.insert(clanId)
    }

    func getCurrentSession() -> AuthRecord? { authTable.getCurrentSession() }
    func setSession(_ record: AuthRecord?)  { authTable.setSession(record) }

    func getProfile(userId: String) -> ProfileRecord?  { profileTable.getProfile(userId: userId) }
    func updateProfile(_ record: ProfileRecord) {
        profileTable.setProfile(record)
        updatedProfileUserIds.insert(record.userId)
    }

    func getSetting(key: String) -> Data?                        { settingsTable.get(key: key) }
    func getSetting<T: PostboxCoding>(key: String, type: T.Type) -> T? { settingsTable.get(key: key, type: type) }
    func setSetting(key: String, value: Data?)                   { settingsTable.set(key: key, value: value) }
    func setSetting<T: PostboxCoding>(key: String, value: T?)    { settingsTable.set(key: key, value: value) }

    func getChannelMeta(channelId: Int64) -> ChannelRecord? {
        channelTable.getChannelMeta(channelId: channelId)
    }

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

    func updateClanMembers(_ members: [ClanMemberRecord], clanId: Int64) {
        clanMemberTable.updateMembers(members, clanId: clanId)
        updatedClanMemberIds.insert(clanId)
    }

    func getClanMembers(clanId: Int64) -> [ClanMemberRecord] {
        clanMemberTable.getMembers(clanId: clanId)
    }

    func updateChannelDescription(clanId: Int64, channelId: Int64, name: String?, topic: String?) {
        let channels = channelTable.getChannels(clanId: clanId)
        if let index = channels.firstIndex(where: { $0.id == channelId }) {
            let existing = channels[index]
            let updated = existing.updating(label: name, topic: topic)
            channelTable.updateSingleChannelRecord(updated)
            updatedChannelClanIds.insert(clanId)
        }
    }

    var isEmpty: Bool {
        updatedChannelClanIds.isEmpty && !updatedClans && updatedMessageChannelIds.isEmpty && updatedChannelMetaIds.isEmpty && updatedNotificationSettingIds.isEmpty && updatedNotificationKeys.isEmpty && updatedTopicClanIds.isEmpty && updatedClanMemberIds.isEmpty && updatedProfileUserIds.isEmpty
    }
}
