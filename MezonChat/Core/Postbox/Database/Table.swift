import Foundation

open class Table {

    let db: SqliteDatabase

    init(db: SqliteDatabase) {
        self.db = db
        createTable()
    }

    open func createTable() {}

    open func beforeCommit() {}

    open func clearMemoryCache() {}

    func addColumnIfNeeded(_ table: String, column: String, definition: String) {
        let columns: [String] = db.query("PRAGMA table_info(\(table))") { stmt in
            String(cString: sqlite3_column_text(stmt, 1))
        }
        guard !columns.contains(column) else { return }
        db.rawExecute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
