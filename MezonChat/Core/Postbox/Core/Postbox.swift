import Foundation

final class Postbox {

    static let shared = Postbox()

    private let authDb: SqliteDatabase
    private let messagesDb: SqliteDatabase
    private let clansDb: SqliteDatabase
    private let profileDb: SqliteDatabase
    private let settingsDb: SqliteDatabase

    private let queue = Queue(name: "mezon.postbox", qos: .userInitiated)

    let authTable: AuthTable
    let messageTable: MessageTable
    let channelTable: ChannelTable
    let clanTable: ClanTable
    let profileTable: ProfileTable
    let settingsTable: SettingsTable

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

        authDb     = SqliteDatabase(path: dbPath("auth.db"),     encryptionKey: authKey)
        messagesDb = SqliteDatabase(path: dbPath("messages.db"), encryptionKey: messagesKey)
        clansDb    = SqliteDatabase(path: dbPath("clans.db"))
        profileDb  = SqliteDatabase(path: dbPath("profile.db"))
        settingsDb = SqliteDatabase(path: dbPath("settings.db"))

        authTable     = AuthTable(db: authDb)
        messageTable  = MessageTable(db: messagesDb)
        channelTable  = ChannelTable(db: clansDb)
        clanTable     = ClanTable(db: clansDb)
        profileTable  = ProfileTable(db: profileDb)
        settingsTable = SettingsTable(db: settingsDb)
    }

    func write(_ block: @escaping (PostboxTransaction) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let tx = PostboxTransaction(
                channelTable: channelTable,
                clanTable: clanTable,
                messageTable: messageTable,
                authTable: authTable,
                profileTable: profileTable,
                settingsTable: settingsTable
            )
            block(tx)
            channelTable.beforeCommit()
            clanTable.beforeCommit()
            messageTable.beforeCommit()
            authTable.beforeCommit()
            profileTable.beforeCommit()
            settingsTable.beforeCommit()
            viewTracker.replay(transaction: tx)
        }
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
                settingsTable: settingsTable
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

    func clearAll() {
        queue.async { [self] in
            authDb.rawExecute("DELETE FROM auth_sessions")
            messagesDb.rawExecute("DELETE FROM messages")
            clansDb.rawExecute("DELETE FROM channels")
            clansDb.rawExecute("DELETE FROM clans")
            profileDb.rawExecute("DELETE FROM profile")
            settingsDb.rawExecute("DELETE FROM settings")
            authTable.clearMemoryCache()
            messageTable.clearMemoryCache()
            channelTable.clearMemoryCache()
            clanTable.clearMemoryCache()
            profileTable.clearMemoryCache()
            settingsTable.clearMemoryCache()
        }
    }
}
