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
        func isIdentifier(_ s: String) -> Bool {
            !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
        guard isIdentifier(table), isIdentifier(column) else { return }
        let columns: [String] = db.query("PRAGMA table_info('\(table)')") { stmt in
            String(cString: sqlite3_column_text(stmt, 1))
        }
        guard !columns.contains(column) else { return }
        db.rawExecute("ALTER TABLE \"\(table)\" ADD COLUMN \"\(column)\" \(definition)")
    }
}
