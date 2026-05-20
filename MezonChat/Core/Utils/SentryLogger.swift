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

    static func setUser(id: String?, username: String?) {
        guard let id else {
            SentrySDK.setUser(nil)
            return
        }
        let user = Sentry.User(userId: id)
        user.username = username
        SentrySDK.setUser(user)
    }

    static func capture(_ error: Error, extras: [String: Any]? = nil) {
        SentrySDK.capture(error: error) { scope in
            if let extras {
                for (key, value) in extras {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
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

    private static func releaseName() -> String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let identifier = bundle.bundleIdentifier ?? "mezon.ios"
        return "\(identifier)@\(version)+\(build)"
    }
}
