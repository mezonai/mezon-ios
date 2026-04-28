import Foundation

enum MezonHTTPLogKind {
    case routine
    case issue
    case diagnostic
}

enum MezonConsoleLog {
    #if DEBUG
    static var httpVerbose: Bool {
        ProcessInfo.processInfo.arguments.contains("-MezonLogHTTP")
    }

    static var networkDiagnostics: Bool {
        ProcessInfo.processInfo.arguments.contains("-MezonLogDiagnostics")
    }
    #else
    static var httpVerbose: Bool { false }
    static var networkDiagnostics: Bool { false }
    #endif
}
