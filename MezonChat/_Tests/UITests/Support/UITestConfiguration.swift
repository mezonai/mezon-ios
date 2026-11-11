import Foundation

/// Environment variables win, then `MezonChat/_Tests/uitest.env`.
/// Never print the resolved credentials or commit them in the shared scheme.
enum UITestConfiguration {
    private static let fileValues: [String: String] = {
        let envFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // UITests
            .deletingLastPathComponent() // _Tests
            .appendingPathComponent("uitest.env")
        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let body = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst("export ".count)) : trimmed
            guard let separator = body.firstIndex(of: "=") else { continue }
            var key = String(body[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(body[body.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("TEST_RUNNER_") {
                key.removeFirst("TEST_RUNNER_".count)
            }
            if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }()

    private static func value(_ key: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[key] ?? fileValues[key]
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static var observationDelaySeconds: Int {
        let seconds = value("UITEST_OBSERVATION_DELAY_SECONDS").flatMap { Int($0) } ?? 0
        return min(max(seconds, 0), 60)
    }

    enum Login {
        static var email: String? { value("UITEST_EMAIL") }
        static var otp: String? { value("UITEST_OTP") }
        static var invalidOTP: String { value("UITEST_INVALID_OTP") ?? "111111" }
    }

    enum Channel {
        static var clanID: String? { value("UITEST_CLAN_ID") }
        static var id: String? { value("UITEST_CHANNEL_ID") }
        static var name: String { value("UITEST_CHANNEL_NAME") ?? "general" }
    }
}
