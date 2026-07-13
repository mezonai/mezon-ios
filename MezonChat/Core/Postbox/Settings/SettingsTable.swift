import Foundation

final class SettingsTable: Table {

    private var cachedValues: [String: Data] = [:]
    private var pendingWrites: [String: Data?] = [:]

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS settings (
                key  TEXT PRIMARY KEY,
                data BLOB NOT NULL
            )
        """)
    }

    func get(key: String) -> Data? {
        if let cached = cachedValues[key] { return cached }
        let rows = db.query(
            "SELECT data FROM settings WHERE key = ?",
            { sqlite3_bind_text($0, 1, key, -1, sqliteTransient) }
        ) { stmt -> Data? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
        }
        let value = rows.compactMap { $0 }.first
        if let v = value { cachedValues[key] = v }
        return value
    }

    func get<T: PostboxCoding>(key: String, type: T.Type) -> T? {
        guard let data = get(key: key) else { return nil }
        return T.postboxDecode(from: data)
    }

    func set(key: String, value: Data?) {
        let normalized = (value?.isEmpty == true) ? nil : value
        if let v = normalized { cachedValues[key] = v }
        else { cachedValues.removeValue(forKey: key) }
        pendingWrites[key] = normalized
    }

    func set<T: PostboxCoding>(key: String, value: T?) {
        set(key: key, value: value?.postboxEncode())
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }
        db.beginTransaction()
        for (key, value) in pendingWrites {
            if let data = value {
                db.run("INSERT OR REPLACE INTO settings(key, data) VALUES(?, ?)") { s in
                    sqlite3_bind_text(s, 1, key, -1, sqliteTransient)
                    data.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 2, buf.baseAddress, Int32(buf.count), sqliteTransient)
                    }
                }
            } else {
                db.run("DELETE FROM settings WHERE key = ?") {
                    sqlite3_bind_text($0, 1, key, -1, sqliteTransient)
                }
            }
        }
        db.commitTransaction()
        pendingWrites.removeAll()
    }

    override func clearMemoryCache() { cachedValues.removeAll() }
}
