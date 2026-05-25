import Foundation
import Sentry

enum SentryLogger {

    static func start() {
        SentrySDK.start { options in
            options.dsn = Secrets.sentryDSN
            options.environment = MezonEnvironment.current == .prod ? "production" : "development"
            options.releaseName = Self.releaseName()

            options.debug = false
            options.attachStacktrace = true
            options.enableAutoPerformanceTracing = false
            options.enableNetworkTracking = false
            options.enableUserInteractionTracing = false
            options.enableNetworkBreadcrumbs = true
            options.enableAutoBreadcrumbTracking = true
            options.enableAppHangTracking = true
        }
    }

    static func setUser(username: String?) {
        guard let username, !username.isEmpty else {
            SentrySDK.setUser(nil)
            return
        }
        let user = Sentry.User(userId: username)
        user.username = username
        SentrySDK.setUser(user)
    }

    static func capture(_ error: Error, extras: [String: Any]? = nil) {
        let ns = error as NSError
        let transient = Self.isTransientNetworkError(ns)
        var merged = extras ?? [:]
        if transient {
            merged["transient"] = true
            merged["urlErrorCode"] = ns.code
        }
        let level: SentryLevel = transient ? .warning : .error
        SentrySDK.capture(error: error) { scope in
            scope.setLevel(level)
            for (key, value) in merged {
                scope.setExtra(value: value, key: key)
            }
        }
    }

    static func captureMediaError(_ error: Error, extras: [String: Any]? = nil) {
        let ns = error as NSError
        if Self.isTransientNetworkError(ns) {
            var data = extras ?? [:]
            data["urlErrorCode"] = ns.code
            data["domain"] = ns.domain
            addBreadcrumb(
                category: "media.load.fail",
                message: ns.localizedDescription,
                level: .info,
                data: data
            )
            return
        }
        capture(error, extras: extras)
    }

    static func capture(message: String, level: SentryLevel = .info, extras: [String: Any]? = nil) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            if let extras {
                for (key, value) in extras {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
    }

    static func addBreadcrumb(category: String, message: String, level: SentryLevel = .info, data: [String: Any]? = nil) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }

    private static let transientURLErrorCodes: Set<Int> = [
        NSURLErrorCancelled,
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        NSURLErrorDataNotAllowed,
        NSURLErrorRequestBodyStreamExhausted,
        NSURLErrorBackgroundSessionWasDisconnected,
    ]

    private static func isTransientNetworkError(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain else { return false }
        return transientURLErrorCodes.contains(error.code)
    }

    private static func releaseName() -> String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let identifier = bundle.bundleIdentifier ?? "mezon.ios"
        return "\(identifier)@\(version)+\(build)"
    }
}
