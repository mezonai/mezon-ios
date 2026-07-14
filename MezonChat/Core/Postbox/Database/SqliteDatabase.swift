import Foundation
import os.log

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SqliteDatabase {

    private(set) var handle: OpaquePointer?
    private(set) var isValid = false
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

    func beginTransaction()  { rawExecute("BEGIN") }
    func commitTransaction() { rawExecute("COMMIT") }
    func rollback()          { rawExecute("ROLLBACK") }
}
