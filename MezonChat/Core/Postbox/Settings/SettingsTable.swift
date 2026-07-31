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

    func removeKeys(withPrefix prefix: String) {
        beforeCommit()
        let keys = db.query("SELECT key FROM settings") { stmt -> String in
            sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        }.filter { $0.hasPrefix(prefix) }
        if !keys.isEmpty {
            db.beginTransaction()
            for key in keys {
                db.run("DELETE FROM settings WHERE key = ?") {
                    sqlite3_bind_text($0, 1, key, -1, sqliteTransient)
                }
            }
            db.commitTransaction()
        }
        for key in cachedValues.keys where key.hasPrefix(prefix) {
            cachedValues.removeValue(forKey: key)
        }
        for key in pendingWrites.keys where key.hasPrefix(prefix) {
            pendingWrites.removeValue(forKey: key)
        }
    }

    override func clearMemoryCache() { cachedValues.removeAll() }
}
