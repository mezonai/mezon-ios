import Foundation

final class Postbox {

    static let shared = Postbox()

    private let authDb: SqliteDatabase
    private let messagesDb: SqliteDatabase
    private let clansDb: SqliteDatabase
    private let profileDb: SqliteDatabase
    private let settingsDb: SqliteDatabase
    private let notificationsDb: SqliteDatabase

    private let queue = Queue(name: "mezon.postbox", qos: .userInitiated)

    let authTable: AuthTable
    let messageTable: MessageTable
    let channelTable: ChannelTable
    let clanTable: ClanTable
    let profileTable: ProfileTable
    let settingsTable: SettingsTable
    let notificationSettingTable: NotificationSettingTable
    let notificationTable: NotificationTable
    let topicTable: TopicTable
    let clanMemberTable: ClanMemberTable

    private let viewTracker = ViewTracker()

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mezon-postbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func dbPath(_ name: String) -> String {
            dir.appendingPathComponent(name).path
        }

        let keychain    = KeychainHelper.shared
        let authKey     = keychain.databaseKey(for: "auth")
        let messagesKey = keychain.databaseKey(for: "messages")

        authDb     = authKey.map { SqliteDatabase(path: dbPath("auth.db"), encryptionKey: $0) }
            ?? SqliteDatabase.unopened()
        messagesDb = messagesKey.map { SqliteDatabase(path: dbPath("messages.db"), encryptionKey: $0) }
            ?? SqliteDatabase.unopened()
        clansDb    = SqliteDatabase(path: dbPath("clans.db"))
        profileDb  = SqliteDatabase(path: dbPath("profile.db"))
        settingsDb = SqliteDatabase(path: dbPath("settings.db"))
        notificationsDb = SqliteDatabase(path: dbPath("notifications.db"))

        authTable     = AuthTable(db: authDb)
        messageTable  = MessageTable(db: messagesDb)
        channelTable  = ChannelTable(db: clansDb)
        clanTable     = ClanTable(db: clansDb)
        profileTable  = ProfileTable(db: profileDb)
        settingsTable = SettingsTable(db: settingsDb)
        notificationSettingTable = NotificationSettingTable(db: clansDb)
        notificationTable = NotificationTable(db: notificationsDb)
        topicTable = TopicTable(db: notificationsDb)
        clanMemberTable = ClanMemberTable(db: clansDb)
    }

    func write(_ block: @escaping (PostboxTransaction) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.runWriteTransaction(block)
        }
    }

    func writeSync(_ block: (PostboxTransaction) -> Void) {
        queue.sync { [weak self] in
            guard let self else { return }
            self.runWriteTransaction(block)
        }
    }

    private func runWriteTransaction(_ block: (PostboxTransaction) -> Void) {
        let tx = PostboxTransaction(
            channelTable: channelTable,
            clanTable: clanTable,
            messageTable: messageTable,
            authTable: authTable,
            profileTable: profileTable,
            settingsTable: settingsTable,
            notificationSettingTable: notificationSettingTable,
            notificationTable: notificationTable,
            topicTable: topicTable,
            clanMemberTable: clanMemberTable
        )
        block(tx)
        channelTable.beforeCommit()
        clanTable.beforeCommit()
        clanMemberTable.beforeCommit()
        messageTable.beforeCommit()
        authTable.beforeCommit()
        profileTable.beforeCommit()
        settingsTable.beforeCommit()
        notificationSettingTable.beforeCommit()
        notificationTable.beforeCommit()
        viewTracker.replay(transaction: tx)
    }

    @discardableResult
    func read<T>(_ block: (PostboxTransaction) -> T) -> T {
        var result: T!
        queue.sync { [self] in
            let tx = PostboxTransaction(
                channelTable: channelTable,
                clanTable: clanTable,
                messageTable: messageTable,
                authTable: authTable,
                profileTable: profileTable,
                settingsTable: settingsTable,
                notificationSettingTable: notificationSettingTable,
                notificationTable: notificationTable,
                topicTable: topicTable,
                clanMemberTable: clanMemberTable
            )
            result = block(tx)
        }
        return result
    }

    func channelListView(clanId: Int64) -> Signal<ChannelListView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableChannelListView, ValuePipe<ChannelListView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initialChannels = self.channelTable.getChannels(clanId: clanId)
                subscriber.putNext(ChannelListView(clanId: clanId, channels: initialChannels))
                let (index, signal) = self.viewTracker.addChannelListView(
                    clanId: clanId, initialChannels: initialChannels
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeChannelListView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func clanListView() -> Signal<ClanListView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableClanListView, ValuePipe<ClanListView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.clanTable.getAllClans()
                subscriber.putNext(ClanListView(clans: initial))
                let (index, signal) = self.viewTracker.addClanListView(initial: initial)
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeClanListView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func profileView(userId: String) -> Signal<ProfileView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableProfileView, ValuePipe<ProfileView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.profileTable.getProfile(userId: userId)
                subscriber.putNext(ProfileView(userId: userId, record: initial))
                let (index, signal) = self.viewTracker.addProfileView(userId: userId, initial: initial)
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeProfileView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func messageHistoryView(channelId: String) -> Signal<MessageHistoryView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableMessageHistoryView, ValuePipe<MessageHistoryView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.messageTable.getMessages(channelId: channelId)
                subscriber.putNext(MessageHistoryView(channelId: channelId, messages: initial))
                let (index, signal) = self.viewTracker.addMessageHistoryView(
                    channelId: channelId, initial: initial
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeMessageHistoryView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func channelMetaView(channelId: Int64) -> Signal<ChannelMetaView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableChannelMetaView, ValuePipe<ChannelMetaView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.channelTable.getChannelMeta(channelId: channelId)
                subscriber.putNext(ChannelMetaView(channelId: channelId, record: initial))
                let (index, signal) = self.viewTracker.addChannelMetaView(
                    channelId: channelId, initial: initial
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeChannelMetaView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }


    func clanMemberView(clanId: Int64) -> Signal<ClanMemberView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableClanMemberView, ValuePipe<ClanMemberView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.clanMemberTable.getMembers(clanId: clanId)
                subscriber.putNext(ClanMemberView(clanId: clanId, members: initial))
                let (index, signal) = self.viewTracker.addClanMemberView(
                    clanId: clanId, initial: initial
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeClanMemberView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func notificationListView(clanId: Int64, category: Int32) -> Signal<NotificationListView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableNotificationListView, ValuePipe<NotificationListView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.notificationTable.getNotificationRecord(clanId: clanId, category: category)
                subscriber.putNext(NotificationListView(clanId: clanId, category: category, notifications: initial))
                let (index, signal) = self.viewTracker.addNotificationListView(
                    clanId: clanId, category: category, initial: initial
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeNotificationListView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func topicListView(clanId: Int64) -> Signal<TopicListView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableTopicListView, ValuePipe<TopicListView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.topicTable.getTopics(clanId: clanId)
                subscriber.putNext(TopicListView(clanId: clanId, topics: initial))
                let (index, signal) = self.viewTracker.addTopicListView(
                    clanId: clanId, initial: initial
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeTopicListView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func notificationSettingView(entityId: Int64) -> Signal<NotificationSettingView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var viewIndex: Bag<(MutableNotificationSettingView, ValuePipe<NotificationSettingView>)>.Index?
            var innerDisposable: Disposable?
            self.queue.sync {
                let initial = self.notificationSettingTable.get(entityId: entityId)
                subscriber.putNext(NotificationSettingView(entityId: entityId, record: initial))
                let (index, signal) = self.viewTracker.addNotificationSettingView(
                    entityId: entityId, initial: initial
                )
                viewIndex = index
                innerDisposable = signal.start(next: { subscriber.putNext($0) })
            }
            return ActionDisposable { [weak self] in
                self?.queue.async {
                    if let idx = viewIndex { self?.viewTracker.removeNotificationSettingView(index: idx) }
                    innerDisposable?.dispose()
                }
            }
        }
    }

    func combinedView(keys: [PostboxViewKey]) -> Signal<CombinedView, NoError> {
        let signals: [Signal<(PostboxViewKey, PostboxView), NoError>] = keys.map { key in
            switch key {
            case .clanList:
                return clanListView() |> map { (key, $0 as PostboxView) }
            case .channelList(let clanId):
                return channelListView(clanId: clanId) |> map { (key, $0 as PostboxView) }
            case .messageHistory(let channelId):
                return messageHistoryView(channelId: channelId) |> map { (key, $0 as PostboxView) }
            case .preferences(let prefKey):
                return preferencesView(key: prefKey) |> map { (key, $0 as PostboxView) }
            case .notificationList(let clanId, let category):
                return notificationListView(clanId: clanId, category: category) |> map { (key, $0 as PostboxView) }
            case .topicList(let clanId):
                return topicListView(clanId: clanId) |> map { (key, $0 as PostboxView) }
            }
        }
        guard !signals.isEmpty else {
            return .single(CombinedView(views: [:]))
        }
        return combineLatest(signals)
            |> map { pairs in
                var views: [PostboxViewKey: PostboxView] = [:]
                for (key, view) in pairs { views[key] = view }
                return CombinedView(views: views)
            }
    }

    func preferencesView(key: String) -> Signal<PreferencesView, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            let data = self.getPreferenceData(key: key)
            subscriber.putNext(PreferencesView(key: key, data: data))
            return EmptyDisposable
        }
    }

    func setSetting<T: PostboxCoding>(key: String, value: T?) {
        queue.async { [self] in
            settingsTable.set(key: key, value: value)
            settingsTable.beforeCommit()
        }
    }

    func setSettingData(key: String, value: Data?) {
        queue.async { [self] in
            settingsTable.set(key: key, value: value)
            settingsTable.beforeCommit()
        }
    }

    func getSetting<T: PostboxCoding>(key: String, type: T.Type) -> T? {
        var result: T?
        queue.sync { [self] in result = settingsTable.get(key: key, type: type) }
        return result
    }

    func getSettingData(key: String) -> Data? {
        var result: Data?
        queue.sync { [self] in result = settingsTable.get(key: key) }
        return result
    }

    func setPreference<T: PostboxCoding>(key: String, value: T?) { setSetting(key: key, value: value) }
    func setPreferenceData(key: String, value: Data?)             { setSettingData(key: key, value: value) }
    func setPreferenceDataSync(key: String, value: Data?) {
        queue.sync { [self] in
            settingsTable.set(key: key, value: value)
            settingsTable.beforeCommit()
        }
    }
    func getPreference<T: PostboxCoding>(key: String, type: T.Type) -> T? { getSetting(key: key, type: type) }
    func getPreferenceData(key: String) -> Data?                  { getSettingData(key: key) }

    func allChannelClanIds() -> [Int64] {
        var result: [Int64] = []
        queue.sync { [self] in
            result = clansDb.query("SELECT DISTINCT clan_id FROM channels") { stmt in
                sqlite3_column_int64(stmt, 0)
            }
        }
        return result
    }

    func getChannelDescription(channelId: Int64) -> (clanId: Int64, channel: Mezon_Api_ChannelDescription)? {
        let clanRecords = read { tx in tx.getClans() }
        let clanIds = clanRecords.map(\.id)

        for clanId in clanIds {
            guard let data = getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { continue }
            let channels = decodeChannelList(data)
            if let ch = channels.first(where: { $0.channelID == channelId }) {
                return (clanId, ch)
            }
        }
        return nil
    }

    func getDMChannelDescription(channelId: Int64) -> Mezon_Api_ChannelDescription? {
        guard let data = getPreferenceData(key: PreferencesKeys.dmChannelList) else { return nil }
        let channels = decodeChannelList(data)
        return channels.first(where: { $0.channelID == channelId })
    }

    private func channelDescriptionFromClanChannelListPreference(clanId: Int64, channelId: Int64)
        -> Mezon_Api_ChannelDescription? {
        guard clanId != 0 else { return nil }
        guard let data = getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)),
            !data.isEmpty else { return nil }
        return decodeChannelList(data).first(where: { $0.channelID == channelId })
    }

    func resolvedChannelDescription(clanId: Int64, channelId: Int64) -> Mezon_Api_ChannelDescription? {
        if clanId == 0 {
            return getDMChannelDescription(channelId: channelId)
                ?? getChannelDescription(channelId: channelId)?.channel
        }
        let prefCh = channelDescriptionFromClanChannelListPreference(clanId: clanId, channelId: channelId)
            ?? getChannelDescription(channelId: channelId)?.channel
        guard let record = read({ tx in
            tx.getChannels(clanId: clanId).first(where: { $0.id == channelId })
        }) else {
            return prefCh
        }
        let sql = record.toProto()
        guard var merged = prefCh else { return sql }
        if sql.type != 0 && merged.type == 0 {
            merged.type = sql.type
        }
        if sql.categoryID != 0 && merged.categoryID == 0 {
            merged.categoryID = sql.categoryID
            merged.categoryName = sql.categoryName
        }
        return merged
    }

    func getCachedDMChannelList() -> [Mezon_Api_ChannelDescription] {
        guard let data = getPreferenceData(key: PreferencesKeys.dmChannelList) else { return [] }
        return decodeChannelList(data)
    }

    func getAllCachedClanChannelDescriptions() -> [Mezon_Api_ChannelDescription] {
        let clanIds = read { tx in tx.getClans() }.map(\.id)
        var result: [Mezon_Api_ChannelDescription] = []
        for clanId in clanIds where clanId != 0 {
            guard let data = getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)),
                !data.isEmpty else { continue }
            result.append(contentsOf: decodeChannelList(data))
        }
        return result
    }

    func updateCachedDMChannelDescription(_ channel: Mezon_Api_ChannelDescription) {
        var channels = getCachedDMChannelList()
        if let index = channels.firstIndex(where: { $0.channelID == channel.channelID }) {
            channels[index] = channel
        } else {
            channels.insert(channel, at: 0)
        }
        setPreferenceDataSync(key: PreferencesKeys.dmChannelList, value: encodeChannelList(channels))
        updateCachedAllChannelsByUser(channel)
    }

    func removeCachedDMChannelDescription(channelId: Int64) {
        var channels = getCachedDMChannelList()
        channels.removeAll { $0.channelID == channelId }
        setPreferenceDataSync(key: PreferencesKeys.dmChannelList, value: encodeChannelList(channels))
        removeCachedAllChannelsByUser(channelId: channelId)
    }

    private func decodeChannelList(_ data: Data) -> [Mezon_Api_ChannelDescription] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    private func encodeChannelList(_ channels: [Mezon_Api_ChannelDescription]) -> Data {
        var result = Data()
        var count = UInt32(channels.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for channel in channels {
            guard let data = try? channel.serializedData() else { continue }
            var length = UInt32(data.count)
            result.append(contentsOf: withUnsafeBytes(of: &length) { Array($0) })
            result.append(data)
        }
        return result
    }

    private func updateCachedAllChannelsByUser(_ channel: Mezon_Api_ChannelDescription) {
        guard let data = getPreferenceData(key: PreferencesKeys.allChannelsByUser),
              var list = try? Mezon_Api_ChannelDescList(serializedBytes: data)
        else {
            return
        }
        if let index = list.channeldesc.firstIndex(where: { $0.channelID == channel.channelID }) {
            list.channeldesc[index] = channel
        } else {
            list.channeldesc.append(channel)
        }
        setPreferenceDataSync(key: PreferencesKeys.allChannelsByUser, value: try? list.serializedData())
    }

    private func removeCachedAllChannelsByUser(channelId: Int64) {
        guard let data = getPreferenceData(key: PreferencesKeys.allChannelsByUser),
              var list = try? Mezon_Api_ChannelDescList(serializedBytes: data)
        else {
            return
        }
        list.channeldesc.removeAll { $0.channelID == channelId }
        setPreferenceDataSync(key: PreferencesKeys.allChannelsByUser, value: try? list.serializedData())
    }

    func clearAll() {
        queue.async { [self] in
            Self.runClearAllDatabases(
                authDb: authDb, messagesDb: messagesDb, clansDb: clansDb, profileDb: profileDb,
                settingsDb: settingsDb, notificationsDb: notificationsDb,
                authTable: authTable, messageTable: messageTable, channelTable: channelTable,
                clanTable: clanTable, profileTable: profileTable, settingsTable: settingsTable,
                notificationSettingTable: notificationSettingTable, notificationTable: notificationTable,
                topicTable: topicTable, clanMemberTable: clanMemberTable
            )
        }
    }

    func clearAllSync() {
        queue.sync { [self] in
            Self.runClearAllDatabases(
                authDb: authDb, messagesDb: messagesDb, clansDb: clansDb, profileDb: profileDb,
                settingsDb: settingsDb, notificationsDb: notificationsDb,
                authTable: authTable, messageTable: messageTable, channelTable: channelTable,
                clanTable: clanTable, profileTable: profileTable, settingsTable: settingsTable,
                notificationSettingTable: notificationSettingTable, notificationTable: notificationTable,
                topicTable: topicTable, clanMemberTable: clanMemberTable
            )
        }
    }

    private static func runClearAllDatabases(
        authDb: SqliteDatabase,
        messagesDb: SqliteDatabase,
        clansDb: SqliteDatabase,
        profileDb: SqliteDatabase,
        settingsDb: SqliteDatabase,
        notificationsDb: SqliteDatabase,
        authTable: AuthTable,
        messageTable: MessageTable,
        channelTable: ChannelTable,
        clanTable: ClanTable,
        profileTable: ProfileTable,
        settingsTable: SettingsTable,
        notificationSettingTable: NotificationSettingTable,
        notificationTable: NotificationTable,
        topicTable: TopicTable,
        clanMemberTable: ClanMemberTable
    ) {
        authDb.rawExecute("DELETE FROM auth_sessions")
        messagesDb.rawExecute("DELETE FROM messages")
        clansDb.rawExecute("DELETE FROM channels")
        clansDb.rawExecute("DELETE FROM clans")
        clansDb.rawExecute("DELETE FROM channel_meta")
        clansDb.rawExecute("DELETE FROM clan_members")
        clansDb.rawExecute("DELETE FROM notification_settings")
        profileDb.rawExecute("DELETE FROM profile")
        settingsDb.rawExecute("DELETE FROM settings")
        notificationsDb.rawExecute("DELETE FROM notifications")
        notificationsDb.rawExecute("DELETE FROM topics")
        authTable.clearMemoryCache()
        messageTable.clearMemoryCache()
        channelTable.clearMemoryCache()
        clanTable.clearMemoryCache()
        profileTable.clearMemoryCache()
        settingsTable.clearMemoryCache()
        notificationSettingTable.clearMemoryCache()
        notificationTable.clearMemoryCache()
        topicTable.clearMemoryCache()
        clanMemberTable.clearMemoryCache()
    }
}
