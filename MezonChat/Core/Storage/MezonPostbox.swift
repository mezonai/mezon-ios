import Foundation
import SQLite3
import SwiftProtobuf

final class MezonPostbox {

    static let shared = MezonPostbox()

    private let queue = DispatchQueue(label: "mezon.postbox", qos: .userInitiated)
    private var db: OpaquePointer?
    private let basePath: String

    private static var basePath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mezon-data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private init(basePath: String = MezonPostbox.basePath) {
        self.basePath = basePath
        openDatabase()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func openDatabase() {
        let dbPath = (basePath as NSString).appendingPathComponent("postbox.db")
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            AppLogger.app.error("[Postbox] Failed to open SQLite at \(dbPath)")
            return
        }
        execute("PRAGMA journal_mode=WAL")
        execute("""
            CREATE TABLE IF NOT EXISTS kv (
                key TEXT PRIMARY KEY,
                value BLOB NOT NULL
            )
            """)
    }

    private func execute(_ sql: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            AppLogger.app.error("[Postbox] SQL error: \(sql)")
            return
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { return }
    }

    func set(key: String, value: Data) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            value.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count), nil)
            }
            sqlite3_step(stmt)
        }
    }

    func remove(key: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "DELETE FROM kv WHERE key = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    func get(key: String) -> Data? {
        queue.sync {
            guard let db = self.db else { return nil }
            let sql = "SELECT value FROM kv WHERE key = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let ptr = sqlite3_column_blob(stmt, 0)
            let len = Int(sqlite3_column_bytes(stmt, 0))
            guard let ptr, len > 0 else { return nil }
            return Data(bytes: ptr, count: len)
        }
    }

    private static let keyAccount = "account"
    private static let keyClans = "clans"
    private static let keySelectedClanId = "selectedClanId"
    private static func keyChannels(clanId: Int64) -> String { "channels_\(clanId)" }
    private static func keySelectedChannel(clanId: Int64) -> String { "selectedChannel_\(clanId)" }
    private static func keyNotifications(clanId: Int64, category: Int32) -> String {
        "notifications_\(clanId)_\(category)"
    }

    func saveAccount(_ account: Mezon_Api_Account) {
        if let data = try? account.serializedData() {
            set(key: Self.keyAccount, value: data)
        }
    }

    func loadAccount() -> Mezon_Api_Account? {
        guard let data = get(key: Self.keyAccount),
              let account = try? Mezon_Api_Account(serializedData: data) else { return nil }
        return account
    }

    func saveClans(_ clans: [Mezon_Api_ClanDesc], selectedClanId: Int64?) {
        set(key: Self.keyClans, value: encodeProtoArray(clans))
        if let id = selectedClanId {
            var idLE = id.littleEndian
            set(key: Self.keySelectedClanId, value: withUnsafeBytes(of: &idLE) { Data($0) })
        } else {
            remove(key: Self.keySelectedClanId)
        }
    }

    func loadClans() -> ([Mezon_Api_ClanDesc], selectedClanId: Int64?) {
        guard let data = get(key: Self.keyClans) else { return ([], nil) }
        let clans = decodeProtoArray(data, type: Mezon_Api_ClanDesc.self)
        var selId: Int64?
        if let selData = get(key: Self.keySelectedClanId), selData.count >= 8 {
            selId = selData.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
        }
        return (clans, selId)
    }

    func saveChannels(_ channels: [Mezon_Api_ChannelDescription], clanId: Int64, selectedChannelId: Int64?) {
        set(key: Self.keyChannels(clanId: clanId), value: encodeProtoArray(channels))
        if let id = selectedChannelId {
            var idLE = id.littleEndian
            set(key: Self.keySelectedChannel(clanId: clanId), value: withUnsafeBytes(of: &idLE) { Data($0) })
        } else {
            remove(key: Self.keySelectedChannel(clanId: clanId))
        }
    }

    func loadChannels(clanId: Int64) -> ([Mezon_Api_ChannelDescription], selectedChannelId: Int64?) {
        let key = Self.keyChannels(clanId: clanId)
        guard let data = get(key: key) else { return ([], nil) }
        let channels = decodeProtoArray(data, type: Mezon_Api_ChannelDescription.self)
        var selId: Int64?
        if let selData = get(key: Self.keySelectedChannel(clanId: clanId)), selData.count >= 8 {
            selId = selData.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
        }
        return (channels, selId)
    }

    func saveNotifications(
        _ notifications: [Mezon_Api_Notification], clanId: Int64, category: Int32
    ) {
        set(
            key: Self.keyNotifications(clanId: clanId, category: category),
            value: encodeProtoArray(notifications))
    }

    func loadNotifications(clanId: Int64, category: Int32) -> [Mezon_Api_Notification] {
        let key = Self.keyNotifications(clanId: clanId, category: category)
        guard let data = get(key: key) else { return [] }
        return decodeProtoArray(data, type: Mezon_Api_Notification.self)
    }

    func loadChannelClanIds() -> [Int64] {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql = "SELECT key FROM kv WHERE key LIKE 'channels_%'"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var ids: [Int64] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let key = String(cString: c)
                    if let suffix = key.split(separator: "_").last, let id = Int64(suffix) {
                        ids.append(id)
                    }
                }
            }
            return ids
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "DELETE FROM kv"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            sqlite3_step(stmt)
        }
    }

    private func encodeProtoArray<M: SwiftProtobuf.Message>(_ items: [M]) -> Data {
        var result = Data()
        var count = UInt32(items.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for item in items {
            if let d = try? item.serializedData() {
                var len = UInt32(d.count)
                result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                result.append(d)
            }
        }
        return result
    }

    private func decodeProtoArray<M: SwiftProtobuf.Message>(_ data: Data, type: M.Type) -> [M] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [M] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset+4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            let chunk = data.subdata(in: offset..<(offset + Int(len)))
            if let m = try? M(serializedData: chunk) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }
}
