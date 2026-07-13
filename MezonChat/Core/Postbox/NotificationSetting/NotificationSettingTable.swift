import Foundation

final class NotificationSettingTable: Table {

    private var cache: [Int64: NotificationSettingRecord] = [:]
    private var pendingWrites: Set<Int64> = []

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS notification_settings (
                entity_id INTEGER PRIMARY KEY,
                data      BLOB NOT NULL
            )
        """)
    }

    func get(entityId: Int64) -> NotificationSettingRecord? {
        if let cached = cache[entityId] { return cached }

        let rows = db.query(
            "SELECT data FROM notification_settings WHERE entity_id = ?",
            { sqlite3_bind_int64($0, 1, entityId) }
        ) { stmt -> NotificationSettingRecord? in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return nil }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: ptr, count: len)
            return NotificationSettingRecord.postboxDecode(from: data)
        }

        let record = rows.compactMap { $0 }.first
        if let record { cache[entityId] = record }
        return record
    }

    func set(_ record: NotificationSettingRecord) {
        cache[record.entityId] = record
        pendingWrites.insert(record.entityId)
    }

    func delete(entityId: Int64) {
        cache.removeValue(forKey: entityId)
        pendingWrites.insert(entityId)
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }
        db.beginTransaction()
        for entityId in pendingWrites {
            if let record = cache[entityId], let data = record.postboxEncode() {
                db.run("INSERT OR REPLACE INTO notification_settings(entity_id, data) VALUES(?, ?)") { s in
                    sqlite3_bind_int64(s, 1, entityId)
                    data.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 2, buf.baseAddress, Int32(buf.count), sqliteTransient)
                    }
                }
            } else {
                db.run("DELETE FROM notification_settings WHERE entity_id = ?") {
                    sqlite3_bind_int64($0, 1, entityId)
                }
            }
        }
        pendingWrites.removeAll()
        db.commitTransaction()
    }

    override func clearMemoryCache() {
        cache.removeAll()
    }
}
