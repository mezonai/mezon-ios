import Foundation

final class MessageTable: Table {

    private var cache: [String: [MessageRecord]] = [:]
    private var pendingWrites:  Set<String> = []
    private var pendingDeletes: Set<String> = []

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS messages (
                id                   TEXT PRIMARY KEY,
                channel_id           TEXT NOT NULL,
                clan_id              TEXT,
                sender_id            TEXT NOT NULL,
                content              BLOB NOT NULL,
                created_at           REAL NOT NULL,
                edited_at            REAL,
                is_deleted           INTEGER NOT NULL DEFAULT 0,
                sender_display_name  TEXT NOT NULL DEFAULT '',
                sender_avatar_url    TEXT,
                sending_state        INTEGER NOT NULL DEFAULT 1,
                attachments_json     BLOB,
                reactions_json       BLOB
            )
        """)
        db.rawExecute(
            "CREATE INDEX IF NOT EXISTS idx_messages_channel ON messages(channel_id, created_at DESC)"
        )

        db.rawExecute("ALTER TABLE messages ADD COLUMN sender_display_name TEXT NOT NULL DEFAULT ''")
        db.rawExecute("ALTER TABLE messages ADD COLUMN sender_avatar_url TEXT")
        db.rawExecute("ALTER TABLE messages ADD COLUMN sending_state INTEGER NOT NULL DEFAULT 1")
        db.rawExecute("ALTER TABLE messages ADD COLUMN attachments_json BLOB")
        db.rawExecute("ALTER TABLE messages ADD COLUMN reactions_json BLOB")
    }

    func getMessages(channelId: String, limit: Int = 50) -> [MessageRecord] {
        if let cached = cache[channelId] { return cached }

        let rows = db.query(
            """
            SELECT id, channel_id, clan_id, sender_id, content, created_at, edited_at,
                   is_deleted, sender_display_name, sender_avatar_url, sending_state,
                   attachments_json, reactions_json
            FROM messages
            WHERE channel_id = ? AND is_deleted = 0
            ORDER BY created_at ASC
            LIMIT ?
            """,
            { s in
                sqlite3_bind_text(s, 1, channelId, -1, nil)
                sqlite3_bind_int(s, 2, Int32(limit))
            }
        ) { stmt -> MessageRecord? in
            guard let idPtr  = sqlite3_column_text(stmt, 0),
                  let chPtr  = sqlite3_column_text(stmt, 1),
                  let snPtr  = sqlite3_column_text(stmt, 3),
                  let blobPtr = sqlite3_column_blob(stmt, 4) else { return nil }

            let id        = String(cString: idPtr)
            let chId      = String(cString: chPtr)
            let clanId    = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 2)) : nil
            let senderId  = String(cString: snPtr)
            let content   = Data(bytes: blobPtr, count: Int(sqlite3_column_bytes(stmt, 4)))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let editedAt: Date? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)) : nil
            let isDeleted = sqlite3_column_int(stmt, 7) != 0
            let displayName = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
            let avatarURL   = sqlite3_column_type(stmt, 9) != SQLITE_NULL
                ? sqlite3_column_text(stmt, 9).map { String(cString: $0) } : nil
            let stateRaw  = sqlite3_column_int(stmt, 10)
            let sendingState = SendingState(rawValue: stateRaw) ?? .sent

            let attachmentsJSON: Data
            if sqlite3_column_type(stmt, 11) != SQLITE_NULL, let ptr = sqlite3_column_blob(stmt, 11) {
                attachmentsJSON = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 11)))
            } else { attachmentsJSON = Data() }

            let reactionsJSON: Data
            if sqlite3_column_type(stmt, 12) != SQLITE_NULL, let ptr = sqlite3_column_blob(stmt, 12) {
                reactionsJSON = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 12)))
            } else { reactionsJSON = Data() }

            return MessageRecord(
                id: id, channelId: chId, clanId: clanId, senderId: senderId,
                content: content, createdAt: createdAt, editedAt: editedAt,
                isDeleted: isDeleted, senderDisplayName: displayName,
                senderAvatarURL: avatarURL, sendingState: sendingState,
                attachmentsJSON: attachmentsJSON, reactionsJSON: reactionsJSON
            )
        }

        let result = rows.compactMap { $0 }
        cache[channelId] = result
        return result
    }

    func addMessages(_ messages: [MessageRecord]) {
        for msg in messages {
            var current = cache[msg.channelId] ?? []
            if let idx = current.firstIndex(where: { $0.id == msg.id }) {
                current[idx] = msg
            } else {
                current.append(msg)
            }
            current.sort { $0.createdAt < $1.createdAt }
            cache[msg.channelId] = current
            pendingWrites.insert(msg.channelId)
        }
    }

    func deleteMessage(id: String) {
        pendingDeletes.insert(id)
        for key in cache.keys {
            cache[key]?.removeAll { $0.id == id }
        }
    }

    func markMessageFailed(id: String) {
        for channelId in cache.keys {
            if let idx = cache[channelId]?.firstIndex(where: { $0.id == id }) {
                let old = cache[channelId]![idx]
                cache[channelId]![idx] = MessageRecord(
                    id: old.id, channelId: old.channelId, clanId: old.clanId,
                    senderId: old.senderId, content: old.content,
                    createdAt: old.createdAt, editedAt: old.editedAt,
                    isDeleted: old.isDeleted, senderDisplayName: old.senderDisplayName,
                    senderAvatarURL: old.senderAvatarURL, sendingState: .failed,
                    attachmentsJSON: old.attachmentsJSON, reactionsJSON: old.reactionsJSON
                )
                pendingWrites.insert(channelId)
                db.run("UPDATE messages SET sending_state = 2 WHERE id = ?") {
                    sqlite3_bind_text($0, 1, id, -1, nil)
                }
            }
        }
    }

    func replaceMessage(pendingId: String, with record: MessageRecord) {
        for channelId in cache.keys {
            cache[channelId]?.removeAll { $0.id == pendingId }
        }
        db.run("DELETE FROM messages WHERE id = ?") {
            sqlite3_bind_text($0, 1, pendingId, -1, nil)
        }
        addMessages([record])
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty || !pendingDeletes.isEmpty else { return }
        db.beginTransaction()

        for msgId in pendingDeletes {
            db.run("UPDATE messages SET is_deleted = 1 WHERE id = ?") {
                sqlite3_bind_text($0, 1, msgId, -1, nil)
            }
        }
        pendingDeletes.removeAll()

        for channelId in pendingWrites {
            guard let messages = cache[channelId] else { continue }
            for record in messages {
                db.run("""
                    INSERT OR REPLACE INTO messages(
                        id, channel_id, clan_id, sender_id, content,
                        created_at, edited_at, is_deleted,
                        sender_display_name, sender_avatar_url, sending_state,
                        attachments_json, reactions_json
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                """) { s in
                    sqlite3_bind_text(s, 1, record.id,        -1, nil)
                    sqlite3_bind_text(s, 2, record.channelId, -1, nil)
                    if let cid = record.clanId { sqlite3_bind_text(s, 3, cid, -1, nil) }
                    else { sqlite3_bind_null(s, 3) }
                    sqlite3_bind_text(s, 4, record.senderId, -1, nil)
                    record.content.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 5, buf.baseAddress, Int32(buf.count), nil)
                    }
                    sqlite3_bind_double(s, 6, record.createdAt.timeIntervalSince1970)
                    if let ea = record.editedAt { sqlite3_bind_double(s, 7, ea.timeIntervalSince1970) }
                    else { sqlite3_bind_null(s, 7) }
                    sqlite3_bind_int(s, 8, record.isDeleted ? 1 : 0)
                    sqlite3_bind_text(s, 9, record.senderDisplayName, -1, nil)
                    if let url = record.senderAvatarURL { sqlite3_bind_text(s, 10, url, -1, nil) }
                    else { sqlite3_bind_null(s, 10) }
                    sqlite3_bind_int(s, 11, record.sendingState.rawValue)
                    if !record.attachmentsJSON.isEmpty {
                        record.attachmentsJSON.withUnsafeBytes { buf in
                            sqlite3_bind_blob(s, 12, buf.baseAddress, Int32(buf.count), nil)
                        }
                    } else { sqlite3_bind_null(s, 12) }
                    if !record.reactionsJSON.isEmpty {
                        record.reactionsJSON.withUnsafeBytes { buf in
                            sqlite3_bind_blob(s, 13, buf.baseAddress, Int32(buf.count), nil)
                        }
                    } else { sqlite3_bind_null(s, 13) }
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
