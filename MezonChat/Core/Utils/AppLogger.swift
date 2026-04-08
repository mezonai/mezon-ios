import Foundation

enum AppLogger {

    static let app = Category()
    static let network = Category()

    struct Category {
        func info(_: String) {}
        func warning(_: String) {}
        func error(_: String) {}
    }
}
