import Foundation

final class ChannelTable: Table {

    private var cachedRows: [Int64: [ChannelRecord]] = [:]
    private var pendingWrites: Set<Int64> = []

    private var metaCache: [Int64: ChannelRecord] = [:]
    private var pendingMetaWrites: Set<Int64> = []

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS channels (
                id      INTEGER NOT NULL,
                clan_id INTEGER NOT NULL,
                data    BLOB    NOT NULL,
                PRIMARY KEY (id, clan_id)
            )
        """)
        db.rawExecute(
            "CREATE INDEX IF NOT EXISTS idx_channels_clan ON channels(clan_id)"
        )
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS channel_meta (
                channel_id INTEGER PRIMARY KEY,
                data       BLOB NOT NULL
            )
        """)
    }


    func getChannels(clanId: Int64) -> [ChannelRecord] {
        if let cached = cachedRows[clanId] { return cached }

        let rows = db.query(
            "SELECT data FROM channels WHERE clan_id = ? ORDER BY id",
            { sqlite3_bind_int64($0, 1, clanId) }
        ) { stmt -> ChannelRecord? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: ptr, count: len)
            return ChannelRecord.postboxDecode(from: data)
        }.compactMap { $0 }

        cachedRows[clanId] = rows
        return rows
    }

    func setChannels(_ channels: [ChannelRecord], clanId: Int64) {
        cachedRows[clanId] = channels
        pendingWrites.insert(clanId)
    }

    func updateSingleChannelRecord(_ record: ChannelRecord) {
        if var channels = cachedRows[record.clanId] {
            if let index = channels.firstIndex(where: { $0.id == record.id }) {
                channels[index] = record
                cachedRows[record.clanId] = channels
            }
        }

        guard let data = record.postboxEncode() else { return }
        db.run("UPDATE channels SET data = ? WHERE id = ? AND clan_id = ?") { s in
            data.withUnsafeBytes { buf in
                sqlite3_bind_blob(s, 1, buf.baseAddress, Int32(buf.count), nil)
            }
            sqlite3_bind_int64(s, 2, record.id)
            sqlite3_bind_int64(s, 3, record.clanId)
        }
        cachedRows.removeValue(forKey: record.clanId)

        metaCache[record.id] = record
    }

    func deleteChannels(clanId: Int64) {
        cachedRows[clanId] = []
        pendingWrites.insert(clanId)
    }

    func getChannelMeta(channelId: Int64) -> ChannelRecord? {
        if let cached = metaCache[channelId] { return cached }

        let rows = db.query(
            "SELECT data FROM channel_meta WHERE channel_id = ?",
            { sqlite3_bind_int64($0, 1, channelId) }
        ) { stmt -> ChannelRecord? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: ptr, count: len)
            return ChannelRecord.postboxDecode(from: data)
        }

        let record = rows.compactMap { $0 }.first
        if let record { metaCache[channelId] = record }
        return record
    }

    private func setChannelMeta(_ record: ChannelRecord) {
        metaCache[record.id] = record
        pendingMetaWrites.insert(record.id)
    }

    private func currentMeta(channelId: Int64) -> ChannelRecord {
        if let existing = getChannelMeta(channelId: channelId) { return existing }
        for (_, channels) in cachedRows {
            if let ch = channels.first(where: { $0.id == channelId }) { return ch }
        }
        return .empty(channelId: channelId)
    }

    func updatePermissions(_ permissions: [PermissionRecord], channelId: Int64) {
        var record = currentMeta(channelId: channelId)
        record.permissions = permissions
        setChannelMeta(record)
    }

    func updateMembers(_ members: [ChannelMemberRecord], channelId: Int64) {
        var record = currentMeta(channelId: channelId)
        record.members = ChannelMemberRecord.deduplicatedByUserId(members)
        setChannelMeta(record)
    }

    func updateBanStatus(isBanned: Bool, expiredBanTime: Int32, channelId: Int64) {
        var record = currentMeta(channelId: channelId)
        record.isBanned = isBanned
        record.expiredBanTime = expiredBanTime
        setChannelMeta(record)
    }


    override func beforeCommit() {
        let hasChannelWrites = !pendingWrites.isEmpty
        let hasMetaWrites = !pendingMetaWrites.isEmpty
        guard hasChannelWrites || hasMetaWrites else { return }

        db.beginTransaction()

        for clanId in pendingWrites {
            db.run("DELETE FROM channels WHERE clan_id = ?") {
                sqlite3_bind_int64($0, 1, clanId)
            }
            for record in cachedRows[clanId] ?? [] {
                guard let data = record.postboxEncode() else { continue }
                db.run("INSERT INTO channels(id, clan_id, data) VALUES(?, ?, ?)") { s in
                    sqlite3_bind_int64(s, 1, record.id)
                    sqlite3_bind_int64(s, 2, record.clanId)
                    data.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 3, buf.baseAddress, Int32(buf.count), nil)
                    }
                }
            }
        }
        pendingWrites.removeAll()

        for channelId in pendingMetaWrites {
            guard let record = metaCache[channelId], let data = record.postboxEncode() else { continue }
            db.run("INSERT OR REPLACE INTO channel_meta(channel_id, data) VALUES(?, ?)") { s in
                sqlite3_bind_int64(s, 1, channelId)
                data.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, 2, buf.baseAddress, Int32(buf.count), nil)
                }
            }
        }
        pendingMetaWrites.removeAll()

        db.commitTransaction()
    }

    override func clearMemoryCache() {
        cachedRows.removeAll()
        metaCache.removeAll()
    }
}
