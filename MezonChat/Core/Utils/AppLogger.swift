import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "mezon.mobile"

    static let app     = AppLog(subsystem: subsystem, category: "App")
    static let network = AppLog(subsystem: subsystem, category: "Network")
    static let ui      = AppLog(subsystem: subsystem, category: "UI")
    static let data    = AppLog(subsystem: subsystem, category: "Data")
}

struct AppLog {
    private let osLog: OSLog

    init(subsystem: String, category: String) {
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }

    func info(_ message: String) {
        os_log("%{public}@", log: osLog, type: .info, message)
    }

    func error(_ message: String) {
        os_log("%{public}@", log: osLog, type: .error, message)
    }

    func warning(_ message: String) {
        os_log("%{public}@", log: osLog, type: .default, message)
    }

    func debug(_ message: String) {
        os_log("%{public}@", log: osLog, type: .debug, message)
    }
}
