import Foundation
import os.log

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SqliteDatabase {

    private(set) var handle: OpaquePointer?
    private(set) var isValid = false
    private var path: String?
    private var isEncrypted = false
    private static let walSizeLimitBytes = 4 * 1024 * 1024
    private static let log = OSLog(subsystem: "mezon.postbox", category: "sqlite")

    private enum Readability {
        case readable
        case damaged(Int32)
        case temporarilyUnavailable(Int32)
    }

    private init() {}

    static func unopened() -> SqliteDatabase {
        SqliteDatabase()
    }

    init(path: String, encryptionKey: Data? = nil) {
        self.path = path
        self.isEncrypted = encryptionKey != nil
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard openConnection(path: path, flags: flags, encryptionKey: encryptionKey) else { return }

        switch readability() {
        case .readable:
            break

        case .temporarilyUnavailable(let code):
            os_log(.error, log: Self.log,
                   "database temporarily unreadable (sqlite %d); keeping file intact, will retry next launch: %{public}@",
                   code, path)
            closeHandle()
            return

        case .damaged(let code):
            os_log(.error, log: Self.log, "database corrupt or wrong key (sqlite %d), recreating: %{public}@", code, path)
            closeHandle()
            Self.removeDatabaseFiles(path: path)
            guard openConnection(path: path, flags: flags, encryptionKey: encryptionKey) else { return }
            guard case .readable = readability() else {
                os_log(.error, log: Self.log, "database recreate failed: %{public}@", path)
                closeHandle()
                return
            }
        }

        rawExecute("PRAGMA journal_mode=WAL")
        rawExecute("PRAGMA journal_size_limit=\(Self.walSizeLimitBytes)")
        rawExecute("PRAGMA synchronous=NORMAL")
        rawExecute("PRAGMA foreign_keys=ON")
        isValid = true
    }

    private func closeHandle() {
        if let h = handle {
            sqlite3_close(h)
            handle = nil
        }
    }

    private func readability() -> Readability {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(handle, "SELECT count(*) FROM sqlite_master", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            return .readable
        }
        let code = handle.map { sqlite3_errcode($0) } ?? SQLITE_ERROR
        switch code {
        case SQLITE_NOTADB, SQLITE_CORRUPT:
            return .damaged(code)
        default:
            return .temporarilyUnavailable(code)
        }
    }

    private func openConnection(path: String, flags: Int32, encryptionKey: Data?) -> Bool {
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            os_log(.error, log: Self.log, "sqlite3_open_v2 failed: %d for %{public}@", rc, path)
            handle = nil
            return false
        }
        if let key = encryptionKey {
            let keyRC = key.withUnsafeBytes { ptr in
                sqlite3_key(handle, ptr.baseAddress, Int32(key.count))
            }
            guard keyRC == SQLITE_OK else {
                os_log(.error, log: Self.log, "sqlite3_key failed: %d for %{public}@", keyRC, path)
                sqlite3_close(handle)
                handle = nil
                return false
            }
        }
        sqlite3_busy_timeout(handle, 3000)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, "PRAGMA cipher_log_level = NONE", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return true
    }

    private static func removeDatabaseFiles(path: String) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: path + suffix)
        }
    }

    deinit {
        if let h = handle { sqlite3_close(h) }
    }

    @discardableResult
    func rawExecute(_ sql: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            logFailure("prepare", sql: sql)
            return false
        }
        let rc = sqlite3_step(stmt)
        let ok = rc == SQLITE_DONE || rc == SQLITE_OK || rc == SQLITE_ROW
        if !ok {
            logFailure("step(\(rc))", sql: sql)
        }
        return ok
    }

    func run(_ sql: String, _ bind: ((OpaquePointer) -> Void)? = nil) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let s = stmt else {
            logFailure("prepare", sql: sql)
            return
        }
        bind?(s)
        let rc = sqlite3_step(s)
        if rc != SQLITE_DONE && rc != SQLITE_OK && rc != SQLITE_ROW {
            logFailure("step(\(rc))", sql: sql)
        }
    }

    private func logFailure(_ stage: String, sql: String) {
        let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
        os_log(.error, log: Self.log, "sqlite %{public}@ failed: %{public}@ — %{public}@", stage, message, String(sql.prefix(120)))
    }

    func query<T>(_ sql: String,
                  _ bind: ((OpaquePointer) -> Void)? = nil,
                  decode: (OpaquePointer) -> T) -> [T] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let s = stmt else { return [] }
        bind?(s)
        var results: [T] = []
        while sqlite3_step(s) == SQLITE_ROW {
            results.append(decode(s))
        }
        return results
    }

    func checkedQuery<T>(_ sql: String,
                         _ bind: ((OpaquePointer) -> Void)? = nil,
                         decode: (OpaquePointer) -> T) -> [T]? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let s = stmt else {
            logFailure("prepare", sql: sql)
            return nil
        }
        bind?(s)
        var results: [T] = []
        var rc = sqlite3_step(s)
        while rc == SQLITE_ROW {
            results.append(decode(s))
            rc = sqlite3_step(s)
        }
        guard rc == SQLITE_DONE else {
            logFailure("step(\(rc))", sql: sql)
            return nil
        }
        return results
    }

    @discardableResult
    func replaceContents(_ populate: (SqliteDatabase) -> Bool) -> Bool {
        guard isValid, !isEncrypted, let path, handle != nil else { return false }
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let replacementPath = path + ".compact"
        Self.removeReplacementFiles(path: replacementPath)
        let replacement = SqliteDatabase()
        guard replacement.openConnection(path: replacementPath, flags: flags, encryptionKey: nil) else {
            Self.removeReplacementFiles(path: replacementPath)
            return false
        }
        let populated = populate(replacement)
        let replacementClosed = sqlite3_close(replacement.handle) == SQLITE_OK
        if replacementClosed {
            replacement.handle = nil
        }
        guard populated, replacementClosed else {
            Self.removeReplacementFiles(path: replacementPath)
            return false
        }
        let checkpointBusy = checkedQuery(
            "PRAGMA wal_checkpoint(TRUNCATE)",
            decode: { stmt -> Int32 in sqlite3_column_int(stmt, 0) }
        )
        guard checkpointBusy == [0], sqlite3_close(handle) == SQLITE_OK else {
            Self.removeReplacementFiles(path: replacementPath)
            return false
        }
        handle = nil
        isValid = false
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fileManager.removeItem(atPath: path + suffix)
        }
        let swapped = rename(replacementPath, path) == 0
        if !swapped {
            Self.removeReplacementFiles(path: replacementPath)
        }
        if openConnection(path: path, flags: flags, encryptionKey: nil), case .readable = readability() {
            rawExecute("PRAGMA journal_mode=WAL")
            rawExecute("PRAGMA journal_size_limit=\(Self.walSizeLimitBytes)")
            rawExecute("PRAGMA synchronous=NORMAL")
            rawExecute("PRAGMA foreign_keys=ON")
            isValid = true
        } else {
            closeHandle()
            os_log(.error, log: Self.log, "database reopen failed after replacing contents: %{public}@", path)
        }
        return swapped && isValid
    }

    var lastErrorCode: Int32 {
        handle.map { sqlite3_errcode($0) } ?? SQLITE_ERROR
    }

    private static func removeReplacementFiles(path: String) {
        let fm = FileManager.default
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? fm.removeItem(atPath: path + suffix)
        }
    }

    func beginTransaction()  { rawExecute("BEGIN") }
    func commitTransaction() { rawExecute("COMMIT") }
    func rollback()          { rawExecute("ROLLBACK") }
}
