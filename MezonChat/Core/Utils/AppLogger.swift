import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "mezon.mobile"

    static let app     = Logger(subsystem: subsystem, category: "App")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let ui      = Logger(subsystem: subsystem, category: "UI")
    static let data    = Logger(subsystem: subsystem, category: "Data")
}
