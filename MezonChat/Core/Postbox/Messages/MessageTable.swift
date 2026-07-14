import Foundation

final class MessageTable: Table {

    private static let topicMessageCode: Int32 = 9

    private struct TopicMetaValue {
        var rpl: Int
        var lsnt: Int64
        var authoritative: Bool
    }

    private var cache: [String: [MessageRecord]] = [:]
    private var pendingWrites:  Set<String> = []
    private var pendingDeletes: Set<String> = []
    private var topicMeta: [Int64: TopicMetaValue] = [:]

    override func createTable() {
        db.rawExecute("""
            CREATE TABLE IF NOT EXISTS messages (
                id                   TEXT NOT NULL,
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
                reactions_json       BLOB,
                references_data      BLOB,
                mentions_json        BLOB,
                code                 INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(id, channel_id)
            )
        """)

        addColumnIfNeeded("messages", column: "sender_display_name", definition: "TEXT NOT NULL DEFAULT ''")
        addColumnIfNeeded("messages", column: "sender_avatar_url", definition: "TEXT")
        addColumnIfNeeded("messages", column: "sending_state", definition: "INTEGER NOT NULL DEFAULT 1")
        addColumnIfNeeded("messages", column: "attachments_json", definition: "BLOB")
        addColumnIfNeeded("messages", column: "reactions_json", definition: "BLOB")
        addColumnIfNeeded("messages", column: "references_data", definition: "BLOB")
        addColumnIfNeeded("messages", column: "mentions_json", definition: "BLOB")
        addColumnIfNeeded("messages", column: "code", definition: "INTEGER NOT NULL DEFAULT 0")
        migrateMessagesPrimaryKeyIfNeeded()
        db.rawExecute(
            "CREATE INDEX IF NOT EXISTS idx_messages_channel ON messages(channel_id, created_at DESC)"
        )
    }

    private func migrateMessagesPrimaryKeyIfNeeded() {
        let columns: [(name: String, pk: Int32)] = db.query("PRAGMA table_info('messages')") { stmt in
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let pk = sqlite3_column_int(stmt, 5)
            return (name, pk)
        }
        let idPk = columns.first(where: { $0.name == "id" })?.pk ?? 0
        let channelPk = columns.first(where: { $0.name == "channel_id" })?.pk ?? 0
        guard idPk == 1, channelPk == 0 else { return }

        db.beginTransaction()
        db.rawExecute("DROP INDEX IF EXISTS idx_messages_channel")
        guard db.rawExecute("ALTER TABLE messages RENAME TO messages_legacy_id_pk") else {
            db.rollback()
            return
        }
        guard db.rawExecute("""
            CREATE TABLE messages (
                id                   TEXT NOT NULL,
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
                reactions_json       BLOB,
                references_data      BLOB,
                mentions_json        BLOB,
                code                 INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(id, channel_id)
            )
        """) else {
            db.rawExecute("ALTER TABLE messages_legacy_id_pk RENAME TO messages")
            db.rollback()
            return
        }
        db.rawExecute("""
            INSERT OR REPLACE INTO messages(
                id, channel_id, clan_id, sender_id, content,
                created_at, edited_at, is_deleted,
                sender_display_name, sender_avatar_url, sending_state,
                attachments_json, reactions_json, references_data, mentions_json, code
            )
            SELECT
                id, channel_id, clan_id, sender_id, content,
                created_at, edited_at, is_deleted,
                sender_display_name, sender_avatar_url, sending_state,
                attachments_json, reactions_json, references_data, mentions_json, code
            FROM messages_legacy_id_pk
        """)
        db.rawExecute("DROP TABLE messages_legacy_id_pk")
        db.commitTransaction()
    }

    private func readMessageRow(_ stmt: OpaquePointer) -> MessageRecord? {
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

        let referencesData: Data
        if sqlite3_column_type(stmt, 13) != SQLITE_NULL, let ptr = sqlite3_column_blob(stmt, 13) {
            referencesData = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 13)))
        } else { referencesData = Data() }

        let mentionsJSON: Data
        if sqlite3_column_type(stmt, 14) != SQLITE_NULL, let ptr = sqlite3_column_blob(stmt, 14) {
            mentionsJSON = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 14)))
        } else { mentionsJSON = Data() }

        let code = sqlite3_column_int(stmt, 15)

        return MessageRecord(
            id: id, channelId: chId, clanId: clanId, senderId: senderId,
            content: content, createdAt: createdAt, editedAt: editedAt,
            isDeleted: isDeleted, code: code,
            senderDisplayName: displayName,
            senderAvatarURL: avatarURL, sendingState: sendingState,
            attachmentsJSON: attachmentsJSON, reactionsJSON: reactionsJSON,
            referencesData: referencesData, mentionsJSON: mentionsJSON
        )
    }

    func getMessageById(_ messageId: String, channelId: String? = nil) -> MessageRecord? {
        if let channelId {
            if let m = cache[channelId]?.first(where: { $0.id == messageId && !$0.isDeleted }) {
                return m
            }
            let rows = db.query(
                """
                SELECT id, channel_id, clan_id, sender_id, content, created_at, edited_at,
                       is_deleted, sender_display_name, sender_avatar_url, sending_state,
                       attachments_json, reactions_json, references_data, mentions_json, code
                FROM messages
                WHERE id = ? AND channel_id = ? AND is_deleted = 0
                LIMIT 1
                """,
                { s in
                    sqlite3_bind_text(s, 1, messageId, -1, sqliteTransient)
                    sqlite3_bind_text(s, 2, channelId, -1, sqliteTransient)
                }
            ) { stmt in self.readMessageRow(stmt) }
            return rows.compactMap { $0 }.first
        }
        for (_, msgs) in cache {
            if let m = msgs.first(where: { $0.id == messageId && !$0.isDeleted }) {
                return m
            }
        }
        let rows = db.query(
            """
            SELECT id, channel_id, clan_id, sender_id, content, created_at, edited_at,
                   is_deleted, sender_display_name, sender_avatar_url, sending_state,
                   attachments_json, reactions_json, references_data, mentions_json, code
            FROM messages
            WHERE id = ? AND is_deleted = 0
            LIMIT 1
            """,
            { s in sqlite3_bind_text(s, 1, messageId, -1, sqliteTransient) }
        ) { stmt in self.readMessageRow(stmt) }
        return rows.compactMap { $0 }.first
    }

    func getMessages(channelId: String, limit: Int = 50) -> [MessageRecord] {
        if let cached = cache[channelId] {
            let filtered = cached.filter { $0.channelId == channelId && !$0.isDeleted }
            if filtered.count != cached.count {
                cache[channelId] = filtered
            }
            return filtered
        }

        let rows = db.query(
            """
            SELECT id, channel_id, clan_id, sender_id, content, created_at, edited_at,
                   is_deleted, sender_display_name, sender_avatar_url, sending_state,
                   attachments_json, reactions_json, references_data, mentions_json, code
            FROM messages
            WHERE channel_id = ? AND is_deleted = 0
            ORDER BY created_at ASC
            LIMIT ?
            """,
            { s in
                sqlite3_bind_text(s, 1, channelId, -1, sqliteTransient)
                sqlite3_bind_int(s, 2, Int32(limit))
            }
        ) { stmt in self.readMessageRow(stmt) }

        let result = rows.compactMap { $0 }.filter { $0.channelId == channelId }
        cache[channelId] = result
        return result
    }

    func getRecentMessages(channelId: String, limit: Int = 50) -> [MessageRecord] {
        if let cached = cache[channelId] {
            return cached
                .filter { $0.channelId == channelId && !$0.isDeleted }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
                .map { $0 }
        }

        let rows = db.query(
            """
            SELECT id, channel_id, clan_id, sender_id, content, created_at, edited_at,
                   is_deleted, sender_display_name, sender_avatar_url, sending_state,
                   attachments_json, reactions_json, references_data, mentions_json, code
            FROM messages
            WHERE channel_id = ? AND is_deleted = 0
            ORDER BY created_at DESC
            LIMIT ?
            """,
            { s in
                sqlite3_bind_text(s, 1, channelId, -1, sqliteTransient)
                sqlite3_bind_int(s, 2, Int32(limit))
            }
        ) { stmt in self.readMessageRow(stmt) }

        return rows.compactMap { $0 }.filter { $0.channelId == channelId }
    }

    private func contentsEquivalent(_ a: Data, _ b: Data) -> Bool {
        let baseA = PresignFinishContent.contentBaseWithoutPresign(a)
        let baseB = PresignFinishContent.contentBaseWithoutPresign(b)
        if baseA == baseB { return true }
        if let objA = try? JSONSerialization.jsonObject(with: baseA) as? [String: Any],
           let objB = try? JSONSerialization.jsonObject(with: baseB) as? [String: Any] {
            return NSDictionary(dictionary: objA).isEqual(to: objB)
        }
        return false
    }

    private func serverEchoMatchesPending(server: MessageRecord, pending: MessageRecord) -> Bool {
        guard pending.id.hasPrefix("pending-"), pending.senderId == server.senderId else { return false }
        return contentsEquivalent(pending.content, server.content)
    }

    private var resendDuplicateGuards: [String: [Date]] = [:]
    private static let resendGuardWindow: TimeInterval = 300

    private func resendGuardKey(senderId: String, content: Data) -> String {
        let base = PresignFinishContent.contentBaseWithoutPresign(content)
        let normalized: String
        if let obj = try? JSONSerialization.jsonObject(with: base),
           let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            normalized = s
        } else {
            normalized = String(data: base, encoding: .utf8) ?? ""
        }
        return "\(senderId)\u{1}\(normalized)"
    }

    func registerResendDuplicateGuard(senderId: String, content: Data) {
        let key = resendGuardKey(senderId: senderId, content: content)
        let now = Date()
        var arr = (resendDuplicateGuards[key] ?? []).filter { now.timeIntervalSince($0) < Self.resendGuardWindow }
        arr.append(now)
        resendDuplicateGuards[key] = arr
    }

    private func consumeResendDuplicateGuard(senderId: String, content: Data) -> Bool {
        let key = resendGuardKey(senderId: senderId, content: content)
        let now = Date()
        var arr = (resendDuplicateGuards[key] ?? []).filter { now.timeIntervalSince($0) < Self.resendGuardWindow }
        guard !arr.isEmpty else {
            resendDuplicateGuards[key] = nil
            return false
        }
        arr.removeFirst()
        resendDuplicateGuards[key] = arr.isEmpty ? nil : arr
        return true
    }

    private func hasActiveResendDuplicateGuard(senderId: String, content: Data) -> Bool {
        let key = resendGuardKey(senderId: senderId, content: content)
        let now = Date()
        let arr = (resendDuplicateGuards[key] ?? []).filter { now.timeIntervalSince($0) < Self.resendGuardWindow }
        resendDuplicateGuards[key] = arr.isEmpty ? nil : arr
        return !arr.isEmpty
    }

    private func isResendDuplicate(_ msg: MessageRecord, in current: [MessageRecord]) -> Bool {
        guard !msg.id.hasPrefix("pending-") else { return false }
        let hasTwin = current.contains { other in
            !other.id.hasPrefix("pending-")
                && other.id != msg.id
                && other.senderId == msg.senderId
                && contentsEquivalent(other.content, msg.content)
        }
        guard hasTwin else { return false }
        return consumeResendDuplicateGuard(senderId: msg.senderId, content: msg.content)
    }

    func addMessages(_ messages: [MessageRecord]) {
        for incoming in messages {
            let msg = enrichTopicMeta(incoming)
            var current = cache[msg.channelId] ?? []

            if !msg.id.hasPrefix("pending-") {
                let existingIdx = current.firstIndex(where: { $0.id == msg.id })
                if let pidx = current.firstIndex(where: { serverEchoMatchesPending(server: msg, pending: $0) }) {
                    let pending = current[pidx]
                    let pid = pending.id
                    let echo = Self.mergePendingIdentityIntoServerEcho(pending: pending, server: msg)
                    if let existingIdx {
                        current[existingIdx] = MessageRecord.mergingIncomingPreservingEmptyAttachments(
                            incoming: echo,
                            previous: current[existingIdx]
                        )
                        current.remove(at: pidx)
                    } else {
                        current[pidx] = echo
                    }
                    pendingDeletes.insert(pid)
                } else if let existingIdx {
                    current[existingIdx] = MessageRecord.mergingIncomingPreservingEmptyAttachments(
                        incoming: msg,
                        previous: current[existingIdx]
                    )
                } else if isResendDuplicate(msg, in: current) {
                    continue
                } else {
                    current.append(msg)
                }
            } else if let idx = current.firstIndex(where: { $0.id == msg.id }) {
                current[idx] = msg
            } else {
                current.append(msg)
            }
            current.sort { MessageRecord.isOrderedAscending($0, $1) }
            cache[msg.channelId] = current
            pendingWrites.insert(msg.channelId)
        }
    }

    private static func mergePendingIdentityIntoServerEcho(pending: MessageRecord, server: MessageRecord) -> MessageRecord {
        let pendingName = pending.senderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverName = server.senderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let useName: String = {
            if pendingName.isEmpty { return server.senderDisplayName }
            if serverName.isEmpty { return pending.senderDisplayName }
            if serverName == pending.senderId { return pending.senderDisplayName }
            return pending.senderDisplayName
        }()
        let useAvatar: String? = {
            let pa = pending.senderAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !pa.isEmpty { return pending.senderAvatarURL }
            return server.senderAvatarURL
        }()
        let mergedContent = PresignFinishContent.mergePresignFinishContent(
            local: pending.content,
            server: server.content
        )
        let attachmentsJSON = !server.attachmentsJSON.isEmpty
            ? server.attachmentsJSON
            : pending.attachmentsJSON
        return MessageRecord(
            id: server.id,
            channelId: server.channelId,
            clanId: server.clanId,
            senderId: server.senderId,
            content: mergedContent,
            createdAt: server.createdAt,
            editedAt: server.editedAt,
            isDeleted: server.isDeleted,
            code: server.code,
            senderDisplayName: useName,
            senderAvatarURL: useAvatar,
            sendingState: .sent,
            attachmentsJSON: attachmentsJSON,
            reactionsJSON: server.reactionsJSON.isEmpty ? pending.reactionsJSON : server.reactionsJSON,
            referencesData: server.referencesData,
            mentionsJSON: server.mentionsJSON
        )
    }

    func replaceAllMessages(_ messages: [MessageRecord], channelId: String) {
        let belonging = messages.filter { $0.channelId == channelId }
        let existing = cache[channelId] ?? getMessages(channelId: channelId)
        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let mergedRaw = belonging.map { incoming -> MessageRecord in
            guard let previous = existingById[incoming.id] else { return incoming }
            return MessageRecord.mergingIncomingPreservingEmptyAttachments(
                incoming: incoming,
                previous: previous
            )
        }
        var mergedBelonging: [MessageRecord] = []
        var keptIds = Set<String>()
        for record in mergedRaw {
            guard !keptIds.contains(record.id) else { continue }
            let isTwin = !record.id.hasPrefix("pending-") && mergedBelonging.contains { kept in
                !kept.id.hasPrefix("pending-")
                    && kept.id != record.id
                    && kept.senderId == record.senderId
                    && contentsEquivalent(kept.content, record.content)
            }
            if isTwin, hasActiveResendDuplicateGuard(senderId: record.senderId, content: record.content) {
                continue
            }
            keptIds.insert(record.id)
            mergedBelonging.append(record)
        }
        let pendingsToKeep = existing.filter { record in
            guard record.id.hasPrefix("pending-"), keptIds.insert(record.id).inserted else { return false }
            return !mergedBelonging.contains(where: { serverEchoMatchesPending(server: $0, pending: record) })
        }
        cache[channelId] = (mergedBelonging + pendingsToKeep).sorted { MessageRecord.isOrderedAscending($0, $1) }
        pendingWrites.insert(channelId)
        db.run("DELETE FROM messages WHERE channel_id = ? AND id NOT LIKE 'pending-%'") {
            sqlite3_bind_text($0, 1, channelId, -1, sqliteTransient)
        }
    }

    func channelIdForMessage(id: String) -> String? {
        for (channelId, msgs) in cache {
            if msgs.contains(where: { $0.id == id }) { return channelId }
        }
        return nil
    }

    @discardableResult
    func deleteMessage(id: String) -> [String] {
        pendingDeletes.insert(id)
        var affectedChannelIds: [String] = []
        for key in cache.keys {
            guard cache[key]?.contains(where: { $0.id == id }) == true else { continue }
            cache[key]?.removeAll { $0.id == id }
            affectedChannelIds.append(key)
        }
        return affectedChannelIds
    }

    func updateMessageReactions(messageId: String, reaction: Mezon_Api_MessageReaction) -> [String] {
        let preferredChannelIds = Self.preferredReactionChannelIds(for: reaction)
        let cacheTargets: [String]
        if preferredChannelIds.isEmpty {
            cacheTargets = cache.keys
                .filter { channelId in
                    cache[channelId]?.contains(where: { $0.id == messageId && !$0.isDeleted }) == true
                }
                .sorted()
        } else {
            cacheTargets = preferredChannelIds.filter { channelId in
                cache[channelId]?.contains(where: { $0.id == messageId && !$0.isDeleted }) == true
            }
        }

        var updatedChannelIds = Set<String>()
        for channelId in cacheTargets {
            if updateCachedMessageReaction(messageId: messageId, channelId: channelId, reaction: reaction) {
                updatedChannelIds.insert(channelId)
            }
        }

        if updatedChannelIds.isEmpty {
            let fallbackCacheTargets = cache.keys
                .filter { channelId in
                    !cacheTargets.contains(channelId)
                        && cache[channelId]?.contains(where: { $0.id == messageId && !$0.isDeleted }) == true
                }
                .sorted()
            for channelId in fallbackCacheTargets {
                if updateCachedMessageReaction(messageId: messageId, channelId: channelId, reaction: reaction) {
                    updatedChannelIds.insert(channelId)
                }
            }
        }

        if updatedChannelIds.isEmpty, !preferredChannelIds.isEmpty {
            for channelId in preferredChannelIds {
                if updateStoredMessageReaction(messageId: messageId, channelId: channelId, reaction: reaction) {
                    updatedChannelIds.insert(channelId)
                }
            }
        }

        return Array(updatedChannelIds)
    }

    private func updateCachedMessageReaction(messageId: String, channelId: String, reaction: Mezon_Api_MessageReaction) -> Bool {
        guard let idx = cache[channelId]?.firstIndex(where: { $0.id == messageId && !$0.isDeleted }) else { return false }
        let old = cache[channelId]![idx]
        guard let updated = Self.recordByApplyingReaction(reaction, to: old) else { return false }
        cache[channelId]![idx] = updated
        pendingWrites.insert(channelId)
        return true
    }

    private func updateStoredMessageReaction(messageId: String, channelId: String, reaction: Mezon_Api_MessageReaction) -> Bool {
        guard let old = getMessageById(messageId, channelId: channelId),
              let updated = Self.recordByApplyingReaction(reaction, to: old) else { return false }
        updateStoredMessageReactions(updated)
        return true
    }

    private static func preferredReactionChannelIds(for reaction: Mezon_Api_MessageReaction) -> [String] {
        var ids: [String] = []
        if reaction.topicID != 0 {
            ids.append("topic-\(reaction.topicID)")
        }
        if reaction.channelID != 0 {
            let channelId = "\(reaction.channelID)"
            if !ids.contains(channelId) {
                ids.append(channelId)
            }
        }
        return ids
    }

    private static func recordByApplyingReaction(_ reaction: Mezon_Api_MessageReaction, to old: MessageRecord) -> MessageRecord? {
        var reactionsArray = reactionRows(from: old.reactionsJSON)

        let emojiIdForJson = reaction.emojiID != 0 ? "\(reaction.emojiID)" : ""
        let isAdding = !reaction.action
        var appendedCount: Int = {
            if isAdding { return 0 }
            let c = Int(reaction.count)
            return c > 0 ? c : 1
        }()

        var newEntry: [String: Any] = [
            "emoji_id": emojiIdForJson,
            "emoji": reaction.emoji,
            "action": isAdding,
            "count": appendedCount
        ]
        if reaction.senderID != 0 {
            newEntry["sender_id"] = "\(reaction.senderID)"
        }
        if !reaction.senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newEntry["sender_name"] = reaction.senderName
        }
        if reaction.id != 0 {
            newEntry["id"] = "\(reaction.id)"
        }
        if reaction.channelID != 0 {
            newEntry["channel_id"] = "\(reaction.channelID)"
        }
        if reaction.topicID != 0 {
            newEntry["topic_id"] = "\(reaction.topicID)"
        }

        var didChange = false
        if let key = reactionEmojiKeyJSON(newEntry) {
            let senderId = reactionSenderIdJSON(newEntry)
            if isAdding, reaction.count > 0 {
                didChange = upsertReactionTotalCountJSON(
                    items: &reactionsArray,
                    emojiKey: key,
                    emojiId: emojiIdForJson,
                    emoji: reaction.emoji,
                    totalCount: Int(reaction.count)
                ) || didChange
            }
            if !senderId.isEmpty {
                let activeCount = activeReactionCountJSON(items: reactionsArray, emojiKey: key, senderId: senderId)
                if isAdding, activeCount > 0, reaction.count > 0 {
                    guard didChange else { return nil }
                    guard let newData = try? JSONSerialization.data(withJSONObject: reactionsArray) else { return nil }
                    return replacingReactions(old, reactionsJSON: newData)
                }
                if !isAdding {
                    guard activeCount > 0 else { return nil }
                    if appendedCount > activeCount {
                        appendedCount = activeCount
                        newEntry["count"] = appendedCount
                    }
                }
                if isAdding {
                    if reaction.count == 0 || !didChange {
                        didChange = adjustReactionTotalCountJSON(
                            items: &reactionsArray,
                            emojiKey: key,
                            delta: 1
                        ) || didChange
                    }
                } else {
                    didChange = adjustReactionTotalCountJSON(
                        items: &reactionsArray,
                        emojiKey: key,
                        delta: -appendedCount
                    ) || didChange
                }
            } else {
                guard didChange else { return nil }
                guard let newData = try? JSONSerialization.data(withJSONObject: reactionsArray) else { return nil }
                return replacingReactions(old, reactionsJSON: newData)
            }
        } else {
            return nil
        }

        reactionsArray.append(newEntry)
        guard let newData = try? JSONSerialization.data(withJSONObject: reactionsArray) else { return nil }
        return replacingReactions(old, reactionsJSON: newData)
    }

    private static func upsertReactionTotalCountJSON(
        items: inout [[String: Any]],
        emojiKey: String,
        emojiId: String,
        emoji: String,
        totalCount: Int
    ) -> Bool {
        guard totalCount > 0 else { return false }
        if let index = items.firstIndex(where: { reactionEmojiKeyJSON($0) == emojiKey && isReactionTotalCountRowJSON($0) }) {
            let old = reactionTotalCountJSON(items[index]) ?? 0
            let normalizedTotal = max(old, totalCount)
            if old == normalizedTotal { return false }
            items[index]["count"] = normalizedTotal
            items[index]["count_is_total"] = true
            return true
        }
        var row: [String: Any] = [
            "emoji_id": emojiId,
            "emoji": emoji,
            "action": true,
            "count": totalCount,
            "count_is_total": true
        ]
        if emojiId.isEmpty {
            row.removeValue(forKey: "emoji_id")
        }
        items.append(row)
        return true
    }

    private static func adjustReactionTotalCountJSON(
        items: inout [[String: Any]],
        emojiKey: String,
        delta: Int
    ) -> Bool {
        guard delta != 0,
              let index = items.firstIndex(where: { reactionEmojiKeyJSON($0) == emojiKey && isReactionTotalCountRowJSON($0) }) else {
            return false
        }
        let old = reactionTotalCountJSON(items[index]) ?? 0
        let updated = max(0, old + delta)
        if updated == old { return false }
        items[index]["count"] = updated
        items[index]["count_is_total"] = true
        return true
    }

    private static func reactionRows(from data: Data) -> [[String: Any]] {
        if !data.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let arr = json as? [[String: Any]] {
                return arr
            }
            if let dict = json as? [String: Any], let arr = dict["reactions"] as? [[String: Any]] {
                return arr
            }
        }

        guard !data.isEmpty,
              let list = try? Mezon_Api_MessageReactionList(serializedBytes: data) else { return [] }
        return list.reactions.map { r in
            var row: [String: Any] = [
                "emoji_id": r.emojiID != 0 ? "\(r.emojiID)" : "",
                "emoji": r.emoji,
                "sender_name": r.senderName,
                "action": !r.action,
                "count": Int(r.count)
            ]
            if r.senderID != 0 {
                row["sender_id"] = "\(r.senderID)"
            }
            if r.id != 0 {
                row["id"] = "\(r.id)"
            }
            if r.channelID != 0 {
                row["channel_id"] = "\(r.channelID)"
            }
            if r.topicID != 0 {
                row["topic_id"] = "\(r.topicID)"
            }
            return row
        }
    }

    private static func reactionEventIdJSON(_ item: [String: Any]) -> String {
        for key in ["id", "reaction_id", "reactionId"] {
            if let s = item[key] as? String {
                let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty, v != "0" { return v }
            }
            if let n = item[key] as? Int, n != 0 { return "\(n)" }
            if let n = item[key] as? Int64, n != 0 { return "\(n)" }
            if let n = item[key] as? NSNumber, n.int64Value != 0 { return "\(n.int64Value)" }
        }
        return ""
    }

    private static func reactionEmojiKeyJSON(_ item: [String: Any]) -> String? {
        let emojiId = stringIdJSON(
            item,
            keys: ["emoji_id", "emojiId", "emojiID", "emojiid"]
        )
        let emoji = (item["emoji"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = emojiId.isEmpty ? emoji : emojiId
        return key.isEmpty ? nil : key
    }

    private static func reactionSenderIdJSON(_ item: [String: Any]) -> String {
        stringIdJSON(
            item,
            keys: ["sender_id", "senderId", "senderID", "user_id", "userId", "userID"]
        )
    }

    private static func stringIdJSON(_ item: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let s = item[key] as? String {
                let value = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, value != "0" { return value }
            }
            if let n = item[key] as? Int, n != 0 { return "\(n)" }
            if let n = item[key] as? Int32, n != 0 { return "\(n)" }
            if let n = item[key] as? Int64, n != 0 { return "\(n)" }
            if let n = item[key] as? NSNumber, n.int64Value != 0 { return "\(n.int64Value)" }
            if let n = item[key] as? Double, n != 0 { return "\(Int64(n))" }
        }
        return ""
    }

    private static func reactionRowCountJSON(_ item: [String: Any]) -> Int {
        if isReactionTotalCountRowJSON(item) { return 0 }
        return intValue(item["count"]) ?? 0
    }

    private static func reactionTotalCountJSON(_ item: [String: Any]) -> Int? {
        let explicitTotal = max(
            intValue(item["total_count"]) ?? 0,
            intValue(item["totalCount"]) ?? 0
        )
        if explicitTotal > 0 { return explicitTotal }
        if boolValue(item["count_is_total"], default: false)
            || boolValue(item["countIsTotal"], default: false)
        {
            return intValue(item["count"])
        }
        if reactionSenderIdJSON(item).isEmpty, let count = intValue(item["count"]), count > 0 {
            return count
        }
        return nil
    }

    private static func isReactionTotalCountRowJSON(_ item: [String: Any]) -> Bool {
        reactionTotalCountJSON(item) != nil
    }

    private static func boolValue(_ value: Any?, default defaultValue: Bool) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" || t == "1" { return true }
            if t == "false" || t == "0" { return false }
        }
        return defaultValue
    }

    private static func activeReactionCountJSON(items: [[String: Any]], emojiKey: String, senderId: String) -> Int {
        var count = 0
        for item in items {
            guard reactionEmojiKeyJSON(item) == emojiKey,
                  reactionSenderIdJSON(item) == senderId else { continue }
            let actionAdd = boolValue(item["action"], default: true)
            let rowCount = reactionRowCountJSON(item)
            if actionAdd {
                if rowCount > 0 {
                    count = rowCount
                } else {
                    count += 1
                }
            } else {
                count = max(0, count - (rowCount > 0 ? rowCount : 1))
            }
        }
        return count
    }

    private static func replacingReactions(_ record: MessageRecord, reactionsJSON: Data) -> MessageRecord {
        MessageRecord(
            id: record.id,
            channelId: record.channelId,
            clanId: record.clanId,
            senderId: record.senderId,
            content: record.content,
            createdAt: record.createdAt,
            editedAt: record.editedAt,
            isDeleted: record.isDeleted,
            code: record.code,
            senderDisplayName: record.senderDisplayName,
            senderAvatarURL: record.senderAvatarURL,
            sendingState: record.sendingState,
            attachmentsJSON: record.attachmentsJSON,
            reactionsJSON: reactionsJSON,
            referencesData: record.referencesData,
            mentionsJSON: record.mentionsJSON
        )
    }

    func updateMessageTopicMetadata(messageId: String, channelId: String, topicId: Int64, creatorId: Int64) -> String? {
        guard topicId != 0 else { return nil }
        if var records = cache[channelId],
           let index = records.firstIndex(where: { $0.id == messageId && !$0.isDeleted }) {
            let updated = Self.withTopicMetadata(
                records[index],
                topicId: topicId,
                creatorId: creatorId,
                replyCount: nil
            )
            records[index] = updated
            cache[channelId] = records
            pendingWrites.insert(channelId)
            return channelId
        }

        guard let existing = getMessageById(messageId, channelId: channelId) else { return nil }
        let updated = Self.withTopicMetadata(
            existing,
            topicId: topicId,
            creatorId: creatorId,
            replyCount: nil
        )
        updateStoredMessageContent(updated)
        return channelId
    }

    func updateTopicReplyCount(parentChannelId: String, topicId: Int64, delta: Int) -> [String] {
        guard topicId != 0, delta != 0 else { return [] }
        let existing = topicMeta[topicId]
        let baseRpl = existing?.rpl
            ?? currentTopicReplyCount(topicId: topicId, preferredChannelId: parentChannelId)
            ?? 0
        let baseLsnt = existing?.lsnt ?? 0
        topicMeta[topicId] = TopicMetaValue(
            rpl: max(0, baseRpl + delta),
            lsnt: baseLsnt,
            authoritative: existing?.authoritative ?? false
        )
        return applyTopicMeta(topicId: topicId, preferredChannelId: parentChannelId)
    }

    func setTopicReplyCount(topicId: Int64, replyCount: Int, lastSentTimestamp: Int64) -> [String] {
        guard topicId != 0 else { return [] }
        let lsnt = lastSentTimestamp != 0 ? lastSentTimestamp : (topicMeta[topicId]?.lsnt ?? 0)
        topicMeta[topicId] = TopicMetaValue(rpl: max(0, replyCount), lsnt: lsnt, authoritative: true)
        return applyTopicMeta(topicId: topicId, preferredChannelId: nil)
    }

    private func applyTopicMeta(topicId: Int64, preferredChannelId: String?) -> [String] {
        guard let meta = topicMeta[topicId] else { return [] }
        var changedChannels: [String] = []

        for channelId in Array(cache.keys) {
            guard let records = cache[channelId],
                  let index = records.firstIndex(where: {
                      !$0.isDeleted && Self.topicId(in: $0.content) == topicId
                  }) else { continue }
            var updated = records
            updated[index] = Self.withTopicMeta(records[index], replyCount: meta.rpl, lastSentTimestamp: meta.lsnt)
            cache[channelId] = updated
            pendingWrites.insert(channelId)
            changedChannels.append(channelId)
        }

        if changedChannels.isEmpty, let parentChannelId = preferredChannelId,
           let existing = findStoredTopicParentMessage(channelId: parentChannelId, topicId: topicId) {
            let updated = Self.withTopicMeta(existing, replyCount: meta.rpl, lastSentTimestamp: meta.lsnt)
            updateStoredMessageContent(updated)
            changedChannels.append(parentChannelId)
        }
        return changedChannels
    }

    private func currentTopicReplyCount(topicId: Int64, preferredChannelId: String) -> Int? {
        let orderedChannels = [preferredChannelId] + cache.keys.filter { $0 != preferredChannelId }
        for channelId in orderedChannels {
            if let records = cache[channelId],
               let record = records.first(where: { Self.topicId(in: $0.content) == topicId }) {
                return Self.intValue(Self.jsonContent(from: record.content)["rpl"]) ?? 0
            }
        }
        if let existing = findStoredTopicParentMessage(channelId: preferredChannelId, topicId: topicId) {
            return Self.intValue(Self.jsonContent(from: existing.content)["rpl"]) ?? 0
        }
        return nil
    }

    private func enrichTopicMeta(_ record: MessageRecord) -> MessageRecord {
        guard let tp = Self.topicId(in: record.content),
              let meta = topicMeta[tp], meta.authoritative else { return record }
        return Self.withTopicMeta(record, replyCount: meta.rpl, lastSentTimestamp: meta.lsnt)
    }

    func markMessageFailed(id: String) {
        updateSendingState(id: id, state: .failed)
    }

    func markMessagePending(id: String) {
        updateSendingState(id: id, state: .pending)
    }

    func markMessageSent(id: String) {
        updateSendingState(id: id, state: .sent)
    }

    private func updateSendingState(id: String, state: SendingState) {
        for channelId in cache.keys {
            if let idx = cache[channelId]?.firstIndex(where: { $0.id == id }) {
                let old = cache[channelId]![idx]
                cache[channelId]![idx] = MessageRecord(
                    id: old.id, channelId: old.channelId, clanId: old.clanId,
                    senderId: old.senderId, content: old.content,
                    createdAt: old.createdAt, editedAt: old.editedAt,
                    isDeleted: old.isDeleted, code: old.code,
                    senderDisplayName: old.senderDisplayName,
                    senderAvatarURL: old.senderAvatarURL, sendingState: state,
                    attachmentsJSON: old.attachmentsJSON, reactionsJSON: old.reactionsJSON,
                    referencesData: old.referencesData, mentionsJSON: old.mentionsJSON
                )
                pendingWrites.insert(channelId)
                db.run("UPDATE messages SET sending_state = ? WHERE id = ?") {
                    sqlite3_bind_int($0, 1, state.rawValue)
                    sqlite3_bind_text($0, 2, id, -1, sqliteTransient)
                }
            }
        }
    }

    func replaceMessage(pendingId: String, with record: MessageRecord) {
        for channelId in cache.keys {
            cache[channelId]?.removeAll { $0.id == pendingId }
        }
        db.run("DELETE FROM messages WHERE id = ?") {
            sqlite3_bind_text($0, 1, pendingId, -1, sqliteTransient)
        }
        addMessages([record])
    }

    private static func jsonContent(from data: Data) -> [String: Any] {
        if !data.isEmpty,
           let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any] {
            return dict
        }
        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ["t": text]
        }
        return [:]
    }

    private static func data(from json: [String: Any], fallback: Data) -> Data {
        (try? JSONSerialization.data(withJSONObject: json)) ?? fallback
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int32 { return Int(value) }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? UInt32 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func topicId(in data: Data) -> Int64? {
        let json = jsonContent(from: data)
        if let value = json["tp"] as? Int64, value != 0 { return value }
        if let value = json["tp"] as? Int, value != 0 { return Int64(value) }
        if let value = json["tp"] as? NSNumber, value.int64Value != 0 { return value.int64Value }
        if let value = json["tp"] as? Double, value != 0 { return Int64(value) }
        if let value = json["tp"] as? String,
           let id = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)),
           id != 0 {
            return id
        }
        return nil
    }

    private static func withTopicMetadata(
        _ record: MessageRecord,
        topicId: Int64,
        creatorId: Int64,
        replyCount: Int?
    ) -> MessageRecord {
        var json = jsonContent(from: record.content)
        json["tp"] = "\(topicId)"
        json["cid"] = "\(creatorId)"
        if let replyCount {
            json["rpl"] = max(0, replyCount)
        } else if json["rpl"] == nil {
            json["rpl"] = 0
        }

        return replacingTopicContent(
            record,
            content: data(from: json, fallback: record.content)
        )
    }

    private static func withTopicMeta(_ record: MessageRecord, replyCount: Int, lastSentTimestamp: Int64) -> MessageRecord {
        var json = jsonContent(from: record.content)
        json["rpl"] = max(0, replyCount)
        if lastSentTimestamp != 0 {
            json["lsnt"] = lastSentTimestamp
        }
        return replacingTopicContent(
            record,
            content: data(from: json, fallback: record.content)
        )
    }

    private static func replacingTopicContent(_ record: MessageRecord, content: Data) -> MessageRecord {
        MessageRecord(
            id: record.id,
            channelId: record.channelId,
            clanId: record.clanId,
            senderId: record.senderId,
            content: content,
            createdAt: record.createdAt,
            editedAt: record.editedAt,
            isDeleted: record.isDeleted,
            code: topicMessageCode,
            senderDisplayName: record.senderDisplayName,
            senderAvatarURL: record.senderAvatarURL,
            sendingState: record.sendingState,
            attachmentsJSON: record.attachmentsJSON,
            reactionsJSON: record.reactionsJSON,
            referencesData: record.referencesData,
            mentionsJSON: record.mentionsJSON
        )
    }

    private func findStoredTopicParentMessage(channelId: String, topicId: Int64) -> MessageRecord? {
        let rows = db.query(
            """
            SELECT id, channel_id, clan_id, sender_id, content, created_at, edited_at,
                   is_deleted, sender_display_name, sender_avatar_url, sending_state,
                   attachments_json, reactions_json, references_data, mentions_json, code
            FROM messages
            WHERE channel_id = ? AND is_deleted = 0
            ORDER BY created_at ASC
            """,
            { s in sqlite3_bind_text(s, 1, channelId, -1, sqliteTransient) }
        ) { stmt in self.readMessageRow(stmt) }
        return rows.compactMap { $0 }.first(where: { Self.topicId(in: $0.content) == topicId })
    }

    private func updateStoredMessageContent(_ record: MessageRecord) {
        db.run(
            """
            UPDATE messages
            SET content = ?, code = ?
            WHERE id = ? AND channel_id = ? AND is_deleted = 0
            """
        ) { s in
            record.content.withUnsafeBytes { buf in
                sqlite3_bind_blob(s, 1, buf.baseAddress, Int32(buf.count), sqliteTransient)
            }
            sqlite3_bind_int(s, 2, record.code)
            sqlite3_bind_text(s, 3, record.id, -1, sqliteTransient)
            sqlite3_bind_text(s, 4, record.channelId, -1, sqliteTransient)
        }
    }

    private func updateStoredMessageReactions(_ record: MessageRecord) {
        db.run(
            """
            UPDATE messages
            SET reactions_json = ?
            WHERE id = ? AND channel_id = ? AND is_deleted = 0
            """
        ) { s in
            if !record.reactionsJSON.isEmpty {
                record.reactionsJSON.withUnsafeBytes { buf in
                    sqlite3_bind_blob(s, 1, buf.baseAddress, Int32(buf.count), sqliteTransient)
                }
            } else {
                sqlite3_bind_null(s, 1)
            }
            sqlite3_bind_text(s, 2, record.id, -1, sqliteTransient)
            sqlite3_bind_text(s, 3, record.channelId, -1, sqliteTransient)
        }
    }

    override func beforeCommit() {
        guard !pendingWrites.isEmpty || !pendingDeletes.isEmpty else { return }
        db.beginTransaction()

        for msgId in pendingDeletes {
            db.run("UPDATE messages SET is_deleted = 1 WHERE id = ?") {
                sqlite3_bind_text($0, 1, msgId, -1, sqliteTransient)
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
                        attachments_json, reactions_json, references_data, mentions_json, code
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """) { s in
                    sqlite3_bind_text(s, 1, record.id,        -1, sqliteTransient)
                    sqlite3_bind_text(s, 2, record.channelId, -1, sqliteTransient)
                    if let cid = record.clanId { sqlite3_bind_text(s, 3, cid, -1, sqliteTransient) }
                    else { sqlite3_bind_null(s, 3) }
                    sqlite3_bind_text(s, 4, record.senderId, -1, sqliteTransient)
                    record.content.withUnsafeBytes { buf in
                        sqlite3_bind_blob(s, 5, buf.baseAddress, Int32(buf.count), sqliteTransient)
                    }
                    sqlite3_bind_double(s, 6, record.createdAt.timeIntervalSince1970)
                    if let ea = record.editedAt { sqlite3_bind_double(s, 7, ea.timeIntervalSince1970) }
                    else { sqlite3_bind_null(s, 7) }
                    sqlite3_bind_int(s, 8, record.isDeleted ? 1 : 0)
                    sqlite3_bind_text(s, 9, record.senderDisplayName, -1, sqliteTransient)
                    if let url = record.senderAvatarURL { sqlite3_bind_text(s, 10, url, -1, sqliteTransient) }
                    else { sqlite3_bind_null(s, 10) }
                    sqlite3_bind_int(s, 11, record.sendingState.rawValue)
                    if !record.attachmentsJSON.isEmpty {
                        record.attachmentsJSON.withUnsafeBytes { buf in
                            sqlite3_bind_blob(s, 12, buf.baseAddress, Int32(buf.count), sqliteTransient)
                        }
                    } else { sqlite3_bind_null(s, 12) }
                    if !record.reactionsJSON.isEmpty {
                        record.reactionsJSON.withUnsafeBytes { buf in
                            sqlite3_bind_blob(s, 13, buf.baseAddress, Int32(buf.count), sqliteTransient)
                        }
                    } else { sqlite3_bind_null(s, 13) }
                    if !record.referencesData.isEmpty {
                        record.referencesData.withUnsafeBytes { buf in
                            sqlite3_bind_blob(s, 14, buf.baseAddress, Int32(buf.count), sqliteTransient)
                        }
                    } else { sqlite3_bind_null(s, 14) }
                    if !record.mentionsJSON.isEmpty {
                        record.mentionsJSON.withUnsafeBytes { buf in
                            sqlite3_bind_blob(s, 15, buf.baseAddress, Int32(buf.count), sqliteTransient)
                        }
                    } else { sqlite3_bind_null(s, 15) }
                    sqlite3_bind_int(s, 16, record.code)
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
