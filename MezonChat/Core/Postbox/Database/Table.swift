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
}
