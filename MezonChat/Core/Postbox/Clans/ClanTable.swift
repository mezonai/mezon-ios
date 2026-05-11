import Foundation

final class ClanTable: Table {

    private var cached: [Int64: ClanRecord] = [:]
    private var pendingWrites: Set<Int64> = []
    private var pendingDeletes: Set<Int64> = []

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS clans (
                id       INTEGER PRIMARY KEY,
                name     TEXT    NOT NULL,
                icon     TEXT,
                owner_id TEXT,
                data     BLOB    NOT NULL
            )
        """)
    }

    func getAllClans() -> [ClanRecord] {
        if !cached.isEmpty { return Array(cached.values) }
        let rows = db.query(
            "SELECT data FROM clans ORDER BY id"
        ) { stmt -> ClanRecord? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let data = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
            return ClanRecord.postboxDecode(from: data)
        }
        let records = rows.compactMap { $0 }
        for r in records { cached[r.id] = r }
        return records
    }

    func getClan(id: Int64) -> ClanRecord? {
        if let c = cached[id] { return c }
        _ = getAllClans()
        return cached[id]
    }

    func setClans(_ clans: [ClanRecord]) {
        for c in clans {
            cached[c.id] = c
            pendingWrites.insert(c.id)
        }
    }

    func replaceAllClans(_ clans: [ClanRecord]) {
        _ = getAllClans()
        let newIds = Set(clans.map { $0.id })
        let staleIds = cached.keys.filter { !newIds.contains($0) }
        for id in staleIds {
            cached.removeValue(forKey: id)
            pendingWrites.remove(id)
            pendingDeletes.insert(id)
        }
        for c in clans {
            cached[c.id] = c
            pendingDeletes.remove(c.id)
            pendingWrites.insert(c.id)
        }
    }

    func deleteClan(id: Int64) {
        cached.removeValue(forKey: id)
        pendingDeletes.insert(id)
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty || !pendingDeletes.isEmpty else { return }
        db.beginTransaction()
        for id in pendingDeletes {
            db.run("DELETE FROM clans WHERE id = ?") { sqlite3_bind_int64($0, 1, id) }
        }
        for id in pendingWrites {
            guard let record = cached[id], let data = record.postboxEncode() else { continue }
            db.run("INSERT OR REPLACE INTO clans(id, name, icon, owner_id, data) VALUES(?,?,?,?,?)") { s in
                sqlite3_bind_int64(s, 1, record.id)
                sqlite3_bind_text(s, 2, record.name, -1, nil)
                if let icon = record.icon { sqlite3_bind_text(s, 3, icon, -1, nil) }
                else { sqlite3_bind_null(s, 3) }
                if let owner = record.ownerId { sqlite3_bind_text(s, 4, owner, -1, nil) }
                else { sqlite3_bind_null(s, 4) }
                data.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, 5, buf.baseAddress, Int32(buf.count), nil)
                }
            }
        }
        db.commitTransaction()
        pendingWrites.removeAll()
        pendingDeletes.removeAll()
    }

    override func clearMemoryCache() { cached.removeAll() }
}
