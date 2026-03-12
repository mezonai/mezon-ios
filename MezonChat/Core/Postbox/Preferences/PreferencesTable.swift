import Foundation

final class PreferencesTable: Table {

    private var cachedValues: [String: Data] = [:]
    private var pendingWrites: [String: Data?] = [:]

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS preferences (
                key  TEXT PRIMARY KEY,
                data BLOB NOT NULL
            )
        """)
    }

    func get(key: String) -> Data? {
        if let cached = cachedValues[key] { return cached }
        let rows = db.query(
            "SELECT data FROM preferences WHERE key = ?",
            { sqlite3_bind_text($0, 1, key, -1, nil) }
        ) { stmt -> Data? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            return Data(bytes: ptr, count: len)
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
        if let v = value {
            cachedValues[key] = v
        } else {
            cachedValues.removeValue(forKey: key)
        }
        pendingWrites[key] = value
    }

    func set<T: PostboxCoding>(key: String, value: T?) {
        set(key: key, value: value?.postboxEncode())
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }
        db.beginTransaction()
        for (key, value) in pendingWrites {
            if let data = value {
                db.run("INSERT OR REPLACE INTO preferences(key, data) VALUES(?, ?)") { s in
                    sqlite3_bind_text(s, 1, key, -1, nil)
                    data.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 2, buf.baseAddress, Int32(buf.count), nil)
                    }
                }
            } else {
                db.run("DELETE FROM preferences WHERE key = ?") {
                    sqlite3_bind_text($0, 1, key, -1, nil)
                }
            }
        }
        db.commitTransaction()
        pendingWrites.removeAll()
    }

    override func clearMemoryCache() {
        cachedValues.removeAll()
    }
}

enum PreferencesKeys {
    static let account    = "account"
    static let clans      = "clans"
    static let selectedClanId = "selectedClanId"
    static func selectedChannelId(clanId: Int64) -> String { "selectedChannel_\(clanId)" }
}
