import Foundation
import os.log

final class SqliteDatabase {

    private(set) var handle: OpaquePointer?
    private(set) var isValid = false
    private static let log = OSLog(subsystem: "mezon.postbox", category: "sqlite")

    init(path: String, encryptionKey: Data? = nil) {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            os_log(.error, log: Self.log, "sqlite3_open_v2 failed: %d for %{public}@", rc, path)
            return
        }

        if let key = encryptionKey {
            let keyRC = key.withUnsafeBytes { ptr in
                sqlite3_key(handle, ptr.baseAddress, Int32(key.count))
            }
            if keyRC != SQLITE_OK {
                os_log(.error, log: Self.log, "sqlite3_key failed: %d for %{public}@", keyRC, path)
                sqlite3_close(handle)
                handle = nil
                return
            }
        }

        rawExecute("PRAGMA journal_mode=WAL")
        rawExecute("PRAGMA synchronous=NORMAL")
        rawExecute("PRAGMA foreign_keys=ON")
        isValid = true
    }

    deinit {
        if let h = handle { sqlite3_close(h) }
    }

    @discardableResult
    func rawExecute(_ sql: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        let rc = sqlite3_step(stmt)
        return rc == SQLITE_DONE || rc == SQLITE_OK
    }

    func run(_ sql: String, _ bind: ((OpaquePointer) -> Void)? = nil) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let s = stmt else { return }
        bind?(s)
        sqlite3_step(s)
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
