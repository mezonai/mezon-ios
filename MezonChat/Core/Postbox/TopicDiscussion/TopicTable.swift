import Foundation
import SwiftProtobuf

public final class TopicTable: Table {

    private var cache: [Int64: [TopicRecord]] = [:]
    private(set) var updatedClanIds = Set<Int64>()

    public override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS topics (
                id                   INTEGER PRIMARY KEY,
                channel_id           INTEGER NOT NULL,
                clan_id              INTEGER NOT NULL,
                creator_id           INTEGER NOT NULL,
                content              TEXT NOT NULL,
                update_time_seconds  INTEGER NOT NULL,
                last_sent_message    TEXT NOT NULL,
                last_sender_id       INTEGER NOT NULL DEFAULT 0
            )
        """)
        db.rawExecute(
            "CREATE INDEX IF NOT EXISTS idx_topics_clan ON topics(clan_id, update_time_seconds DESC)"
        )
        addColumnIfNeeded("topics", column: "last_sender_id", definition: "INTEGER NOT NULL DEFAULT 0")
    }

    public override func beforeCommit() {
        updatedClanIds.removeAll()
    }

    public override func clearMemoryCache() {
        cache.removeAll()
    }

    func getTopics(clanId: Int64, limit: Int = 50) -> [TopicRecord] {
        if let cached = cache[clanId] { return cached }

        let rows = db.query(
            """
            SELECT id, channel_id, clan_id, creator_id, content, update_time_seconds, last_sent_message, last_sender_id
            FROM topics
            WHERE clan_id = ?
            ORDER BY update_time_seconds DESC
            LIMIT ?
            """,
            { s in
                sqlite3_bind_int64(s, 1, clanId)
                sqlite3_bind_int(s, 2, Int32(limit))
            }
        ) { stmt -> TopicRecord? in
            TopicRecord(
                id: sqlite3_column_int64(stmt, 0),
                channelID: sqlite3_column_int64(stmt, 1),
                clanID: sqlite3_column_int64(stmt, 2),
                creatorID: sqlite3_column_int64(stmt, 3),
                lastSenderID: sqlite3_column_int64(stmt, 7),
                content: String(cString: sqlite3_column_text(stmt, 4)),
                updateTimeSeconds: UInt32(sqlite3_column_int64(stmt, 5)),
                lastSentMessageContent: String(cString: sqlite3_column_text(stmt, 6))
            )
        }
        let result = rows.compactMap { $0 }
        cache[clanId] = result
        return result
    }

    func updateTopics(_ topics: [TopicRecord], clanId: Int64) {
        db.run("DELETE FROM topics WHERE clan_id = ?") { s in
            sqlite3_bind_int64(s, 1, clanId)
        }
        for t in topics {
            db.run(
                """
                INSERT INTO topics (id, channel_id, clan_id, creator_id, content, update_time_seconds, last_sent_message, last_sender_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                { s in
                    sqlite3_bind_int64(s, 1, t.id)
                    sqlite3_bind_int64(s, 2, t.channelID)
                    sqlite3_bind_int64(s, 3, t.clanID)
                    sqlite3_bind_int64(s, 4, t.creatorID)
                    sqlite3_bind_text(s, 5, (t.content as NSString).utf8String, -1, sqliteTransient)
                    sqlite3_bind_int64(s, 6, Int64(t.updateTimeSeconds))
                    sqlite3_bind_text(s, 7, (t.lastSentMessageContent as NSString).utf8String, -1, sqliteTransient)
                    sqlite3_bind_int64(s, 8, t.lastSenderID)
                }
            )
        }
        cache[clanId] = topics
        updatedClanIds.insert(clanId)
    }
}
