import Foundation

final class ProfileTable: Table {

    private var cached: [String: ProfileRecord] = [:]
    private var pendingWrites: Set<String> = []

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS profile (
                user_id      TEXT PRIMARY KEY,
                username     TEXT NOT NULL,
                display_name TEXT,
                avatar_url   TEXT,
                status       INTEGER NOT NULL DEFAULT 0,
                data         BLOB    NOT NULL
            )
        """)
    }

    func getProfile(userId: String) -> ProfileRecord? {
        if let c = cached[userId] { return c }
        let rows = db.query(
            "SELECT user_id, username, display_name, avatar_url, status, data FROM profile WHERE user_id = ?",
            { sqlite3_bind_text($0, 1, userId, -1, nil) }
        ) { stmt -> ProfileRecord? in
            guard let uidPtr  = sqlite3_column_text(stmt, 0),
                  let unPtr   = sqlite3_column_text(stmt, 1),
                  let blobPtr = sqlite3_column_blob(stmt, 5) else { return nil }

            let uid     = String(cString: uidPtr)
            let uname   = String(cString: unPtr)
            let dispName = (sqlite3_column_type(stmt, 2) != SQLITE_NULL)
                ? String(cString: sqlite3_column_text(stmt, 2)) : nil
            let avatarUrl = (sqlite3_column_type(stmt, 3) != SQLITE_NULL)
                ? String(cString: sqlite3_column_text(stmt, 3)) : nil
            let status  = sqlite3_column_int(stmt, 4)
            let data    = Data(bytes: blobPtr, count: Int(sqlite3_column_bytes(stmt, 5)))

            return ProfileRecord(
                userId: uid, username: uname, displayName: dispName,
                avatarUrl: avatarUrl, status: status, data: data
            )
        }
        let result = rows.compactMap { $0 }.first
        if let r = result { cached[userId] = r }
        return result
    }

    func setProfile(_ record: ProfileRecord) {
        cached[record.userId] = record
        pendingWrites.insert(record.userId)
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }
        db.beginTransaction()
        for userId in pendingWrites {
            guard let record = cached[userId], let data = record.data.isEmpty ? Data("{}".utf8) as Data? : record.data as Data? else { continue }
            db.run("""
                INSERT OR REPLACE INTO profile(user_id, username, display_name, avatar_url, status, data)
                VALUES(?, ?, ?, ?, ?, ?)
            """) { s in
                sqlite3_bind_text(s, 1, record.userId, -1, nil)
                sqlite3_bind_text(s, 2, record.username, -1, nil)
                if let d = record.displayName { sqlite3_bind_text(s, 3, d, -1, nil) }
                else { sqlite3_bind_null(s, 3) }
                if let a = record.avatarUrl { sqlite3_bind_text(s, 4, a, -1, nil) }
                else { sqlite3_bind_null(s, 4) }
                sqlite3_bind_int(s, 5, record.status)
                data.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, 6, buf.baseAddress, Int32(buf.count), nil)
                }
            }
        }
        db.commitTransaction()
        pendingWrites.removeAll()
    }

    override func clearMemoryCache() { cached.removeAll() }
}
