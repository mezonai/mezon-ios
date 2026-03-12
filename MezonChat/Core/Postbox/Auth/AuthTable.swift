import Foundation

final class AuthTable: Table {

    private var cachedSession: AuthRecord?
    private var pendingWrite: AuthRecord??

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS auth_sessions (
                user_id       TEXT PRIMARY KEY,
                token         TEXT NOT NULL,
                refresh_token TEXT,
                expires_at    REAL,
                created_at    REAL NOT NULL,
                session_data  BLOB
            )
        """)
    }

    func getCurrentSession() -> AuthRecord? {
        if let cached = cachedSession { return cached }
        let rows = db.query(
            "SELECT user_id, token, refresh_token, expires_at, created_at, session_data FROM auth_sessions LIMIT 1"
        ) { stmt -> AuthRecord? in
            guard let userIdPtr = sqlite3_column_text(stmt, 0),
                  let tokenPtr  = sqlite3_column_text(stmt, 1) else { return nil }

            let userId  = String(cString: userIdPtr)
            let token   = String(cString: tokenPtr)
            let refresh = (sqlite3_column_type(stmt, 2) != SQLITE_NULL)
                ? String(cString: sqlite3_column_text(stmt, 2))
                : nil

            let expiresAt: Date? = (sqlite3_column_type(stmt, 3) != SQLITE_NULL)
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                : nil
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

            var sessionData: Data?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL,
               let ptr = sqlite3_column_blob(stmt, 5) {
                sessionData = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 5)))
            }

            return AuthRecord(
                userId: userId, token: token, refreshToken: refresh,
                expiresAt: expiresAt, createdAt: createdAt, sessionData: sessionData
            )
        }
        cachedSession = rows.compactMap { $0 }.first
        return cachedSession
    }

    func setSession(_ record: AuthRecord?) {
        cachedSession = record
        pendingWrite = .some(record)
    }

    override func beforeCommit() {
        guard let pending = pendingWrite else { return }
        defer { pendingWrite = nil }

        db.beginTransaction()
        db.rawExecute("DELETE FROM auth_sessions")
        if let record = pending {
            db.run("""
                INSERT INTO auth_sessions(user_id, token, refresh_token, expires_at, created_at, session_data)
                VALUES(?, ?, ?, ?, ?, ?)
            """) { s in
                sqlite3_bind_text(s, 1, record.userId, -1, nil)
                sqlite3_bind_text(s, 2, record.token,  -1, nil)
                if let rt = record.refreshToken {
                    sqlite3_bind_text(s, 3, rt, -1, nil)
                } else {
                    sqlite3_bind_null(s, 3)
                }
                if let exp = record.expiresAt {
                    sqlite3_bind_double(s, 4, exp.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(s, 4)
                }
                sqlite3_bind_double(s, 5, record.createdAt.timeIntervalSince1970)
                if let data = record.sessionData {
                    data.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 6, buf.baseAddress, Int32(buf.count), nil)
                    }
                } else {
                    sqlite3_bind_null(s, 6)
                }
            }
        }
        db.commitTransaction()
    }

    override func clearMemoryCache() {
        cachedSession = nil
    }
}
