import Foundation

final class NotificationTable: Table {

    private var cache: [String: [NotificationRecord]] = [:]
    private var pendingWrites: Set<String> = []


    private func cacheKey(clanId: Int64, category: Int32) -> String {
        return "\(clanId)_\(category)"
    }

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS notifications (
                id                   INTEGER PRIMARY KEY,
                subject              TEXT NOT NULL,
                content              TEXT NOT NULL,
                code                 INTEGER NOT NULL,
                sender_id            INTEGER NOT NULL,
                create_time_seconds  INTEGER NOT NULL,
                persistent           INTEGER NOT NULL DEFAULT 0,
                clan_id              INTEGER NOT NULL,
                channel_id           INTEGER NOT NULL,
                channel_type         INTEGER NOT NULL,
                avatar_url           TEXT NOT NULL,
                topic_id             INTEGER NOT NULL,
                category             INTEGER NOT NULL,
                message_id           INTEGER NOT NULL DEFAULT 0
            )
        """)
        db.rawExecute(
            "CREATE INDEX IF NOT EXISTS idx_notifications_clan_category ON notifications(clan_id, category, create_time_seconds DESC)"
        )
        addColumnIfNeeded("notifications", column: "message_id", definition: "INTEGER NOT NULL DEFAULT 0")
    }

    func getNotificationRecord(clanId: Int64, category: Int32, limit: Int = 50) -> [NotificationRecord] {
        let key = cacheKey(clanId: clanId, category: category)
        if let cached = cache[key] { return cached }

        let rows = db.query(
            """
            SELECT id, subject, content, code, sender_id, create_time_seconds,
                   persistent, clan_id, channel_id, channel_type, avatar_url, topic_id, category, message_id
            FROM notifications
            WHERE clan_id = ? AND category = ?
            ORDER BY create_time_seconds DESC
            LIMIT ?
            """,
            { s in
                sqlite3_bind_int64(s, 1, clanId)
                sqlite3_bind_int(s, 2, category)
                sqlite3_bind_int(s, 3, Int32(limit))
            }
        ) { stmt -> NotificationRecord? in
            let id = sqlite3_column_int64(stmt, 0)
            let subject = String(cString: sqlite3_column_text(stmt, 1))
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let code = sqlite3_column_int(stmt, 3)
            let senderId = sqlite3_column_int64(stmt, 4)
            let createTime = UInt32(sqlite3_column_int64(stmt, 5))
            let persistent = sqlite3_column_int(stmt, 6) != 0
            let rClanId = sqlite3_column_int64(stmt, 7)
            let channelId = sqlite3_column_int64(stmt, 8)
            let channelType = sqlite3_column_int(stmt, 9)
            let avatarUrl = String(cString: sqlite3_column_text(stmt, 10))
            let topicId = sqlite3_column_int64(stmt, 11)
            let rCategory = sqlite3_column_int(stmt, 12)
            let messageId = sqlite3_column_int64(stmt, 13)

            return NotificationRecord(
                id: id, subject: subject, content: content, code: code,
                senderID: senderId, createTimeSeconds: createTime,
                persistent: persistent, clanID: rClanId, channelID: channelId,
                channelType: channelType, avatarURL: avatarUrl, topicID: topicId,
                category: rCategory, messageID: messageId
            )
        }

        let result = rows.compactMap { $0 }
        cache[key] = result
        return result
    }

    func replaceNotificationRecord(_ notifications: [NotificationRecord], clanId: Int64, category: Int32) {
        let key = cacheKey(clanId: clanId, category: category)
        cache[key] = notifications.sorted { $0.createTimeSeconds > $1.createTimeSeconds }
        pendingWrites.insert(key)
    }

    func appendNotificationRecord(_ notifications: [NotificationRecord], clanId: Int64, category: Int32) {
        let key = cacheKey(clanId: clanId, category: category)
        var existing = cache[key] ?? []

        var seen = Set(existing.map { $0.id })
        for n in notifications {
            if !seen.contains(n.id) {
                existing.append(n)
                seen.insert(n.id)
            }
        }
        cache[key] = existing.sorted { $0.createTimeSeconds > $1.createTimeSeconds }
        pendingWrites.insert(key)
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty else { return }
        db.beginTransaction()

        for key in pendingWrites {

            let parts = key.components(separatedBy: "_")
            guard parts.count == 2,
                  let clanId = Int64(parts[0]),
                  let category = Int32(parts[1]),
                  let list = cache[key] else { continue }


            db.run("DELETE FROM notifications WHERE clan_id = ? AND category = ?") { s in
                sqlite3_bind_int64(s, 1, clanId)
                sqlite3_bind_int(s, 2, category)
            }

            for item in list {
                db.run("""
                    INSERT INTO notifications(
                        id, subject, content, code, sender_id, create_time_seconds,
                        persistent, clan_id, channel_id, channel_type, avatar_url, topic_id, category, message_id
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """) { s in
                    sqlite3_bind_int64(s, 1, item.id)
                    sqlite3_bind_text(s, 2, (item.subject as NSString).utf8String, -1, sqliteTransient)
                    sqlite3_bind_text(s, 3, (item.content as NSString).utf8String, -1, sqliteTransient)
                    sqlite3_bind_int(s, 4, item.code)
                    sqlite3_bind_int64(s, 5, item.senderID)
                    sqlite3_bind_int64(s, 6, Int64(item.createTimeSeconds))
                    sqlite3_bind_int(s, 7, item.persistent ? 1 : 0)
                    sqlite3_bind_int64(s, 8, item.clanID)
                    sqlite3_bind_int64(s, 9, item.channelID)
                    sqlite3_bind_int(s, 10, item.channelType)
                    sqlite3_bind_text(s, 11, (item.avatarURL as NSString).utf8String, -1, sqliteTransient)
                    sqlite3_bind_int64(s, 12, item.topicID)
                    sqlite3_bind_int(s, 13, item.category)
                    sqlite3_bind_int64(s, 14, item.messageID)
                }
            }
        }
        db.commitTransaction()
        pendingWrites.removeAll()
    }

    override func clearMemoryCache() {
        cache.removeAll()
    }
}
