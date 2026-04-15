import Foundation

final class SqliteDatabase {

    private(set) var handle: OpaquePointer?

    init(path: String, encryptionKey: Data? = nil) {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            return
        }

        if let key = encryptionKey {
            let rc = key.withUnsafeBytes { ptr in
                sqlite3_key(handle, ptr.baseAddress, Int32(key.count))
            }
            if rc != SQLITE_OK {
            }
        }

        rawExecute("PRAGMA journal_mode=WAL")
        rawExecute("PRAGMA synchronous=NORMAL")
        rawExecute("PRAGMA foreign_keys=ON")
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
