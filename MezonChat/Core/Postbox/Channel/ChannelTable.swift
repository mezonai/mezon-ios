import Foundation

final class ChannelTable: Table {

    private var cachedRows: [Int64: [ChannelRecord]] = [:]
    private var pendingWrites: Set<Int64> = []

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

    func deleteChannels(clanId: Int64) {
        cachedRows[clanId] = []
        pendingWrites.insert(clanId)
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }

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
        db.commitTransaction()
        pendingWrites.removeAll()
    }

    override func clearMemoryCache() {
        cachedRows.removeAll()
    }
}
