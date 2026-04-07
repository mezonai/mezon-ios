import Foundation

final class ClanMemberTable: Table {

    private var cachedMembers: [Int64: [ClanMemberRecord]] = [:]
    private var pendingWrites: Set<Int64> = []

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS clan_members (
                clan_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                data    BLOB    NOT NULL,
                PRIMARY KEY (clan_id, user_id)
            )
        """)
    }

    func getMembers(clanId: Int64) -> [ClanMemberRecord] {
        if let cached = cachedMembers[clanId] { return cached }

        let rows = db.query(
            "SELECT data FROM clan_members WHERE clan_id = ?",
            { sqlite3_bind_int64($0, 1, clanId) }
        ) { stmt -> ClanMemberRecord? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: ptr, count: len)
            return ClanMemberRecord.postboxDecode(from: data)
        }.compactMap { $0 }

        cachedMembers[clanId] = rows
        return rows
    }

    func updateMembers(_ members: [ClanMemberRecord], clanId: Int64) {
        cachedMembers[clanId] = members
        pendingWrites.insert(clanId)
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }

        db.beginTransaction()
        for clanId in pendingWrites {
            db.run("DELETE FROM clan_members WHERE clan_id = ?") {
                sqlite3_bind_int64($0, 1, clanId)
            }
            for record in cachedMembers[clanId] ?? [] {
                guard let data = record.postboxEncode() else { continue }
                db.run("INSERT INTO clan_members(clan_id, user_id, data) VALUES(?, ?, ?)") { s in
                    sqlite3_bind_int64(s, 1, clanId)
                    sqlite3_bind_int64(s, 2, record.userId)
                    data.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 3, buf.baseAddress, Int32(buf.count), nil)
                    }
                }
            }
        }
        pendingWrites.removeAll()
        db.commitTransaction()
    }

    override func clearMemoryCache() {
        cachedMembers.removeAll()
    }
}
