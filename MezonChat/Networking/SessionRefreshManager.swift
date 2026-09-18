import Foundation
import Sentry

@MainActor
final class SessionRefreshManager {

    static let shared = SessionRefreshManager()

    private let maxRetriesSameToken = 5
    private let maxAppLaunchRetries = 5

    private var lastRefreshToken: String = ""
    private var failCount: Int = 0
    private var activeTask: Task<MezonSession, Error>?
    private var lastSuccessfulRefresh: (at: Date, session: MezonSession)?
    private let minSuccessfulRefreshInterval: TimeInterval = 2.0
    private var lastFailedRefresh: (at: Date, error: Error)?
    private let minFailedRefreshInterval: TimeInterval = 1.5

    private let refreshThrottleBaseSeconds: TimeInterval = 60
    private let refreshThrottleCapSeconds: TimeInterval = 300
    private var refreshThrottleSeconds: TimeInterval = 60
    private var refreshHoldUntil: Date?
    private var lastThrottledError: Error?

    private init() {}

    var mayRefresh: Bool {
        guard let until = refreshHoldUntil else { return true }
        return Date() >= until
    }

    func releaseRefreshThrottle() {
        refreshHoldUntil = nil
        refreshThrottleSeconds = refreshThrottleBaseSeconds
        lastThrottledError = nil
    }

    private func isThrottled(_ error: Error) -> Bool {
        guard let mezon = error as? MezonError, case .httpError(let code, _) = mezon else { return false }
        return code == 429 || code == 503
    }

    private func holdRefresh(after error: Error) {
        refreshHoldUntil = Date().addingTimeInterval(refreshThrottleSeconds)
        lastThrottledError = error
        SentryLogger.addBreadcrumb(
            category: "session.refresh",
            message: "throttled",
            level: .warning,
            data: ["hold_seconds": Int(refreshThrottleSeconds)]
        )
        refreshThrottleSeconds = doubledBackoff(refreshThrottleSeconds, cap: refreshThrottleCapSeconds)
    }

    private func isDefinitiveAuthFailure(_ error: Error) -> Bool {
        guard let mezon = error as? MezonError, case .httpError(let code, let message) = mezon else {
            return false
        }
        if code == 401 { return true }
        guard code == 403 else { return false }
        let text = message.lowercased()
        return text.contains("authenticate")
            || text.contains("unauthorized")
            || text.contains("token")
            || text.contains("jwt")
            || text.contains("expired")
    }

    private func isDefinitiveExpiry(_ error: Error) -> Bool {
        if let sessionError = error as? SessionError, case .maxRetriesExceeded = sessionError {
            return true
        }
        return false
    }

    func awaitInflightRefresh() async {
        guard let active = activeTask else { return }
        _ = try? await active.value
    }

    func refresh(session: MezonSession) async throws -> MezonSession {
        if let active = activeTask {
            return try await active.value
        }
        if !mayRefresh, let throttled = lastThrottledError {
            throw throttled
        }
        if let recent = lastSuccessfulRefresh,
           Date().timeIntervalSince(recent.at) < minSuccessfulRefreshInterval,
           !recent.session.isExpired {
            return recent.session
        }
        if let recentFail = lastFailedRefresh,
           Date().timeIntervalSince(recentFail.at) < minFailedRefreshInterval {
            throw recentFail.error
        }
        let task = Task<MezonSession, Error> { [weak self] in
            guard let self else { throw SessionError.notInitialized }
            return try await self.doRefresh(session: session)
        }
        activeTask = task
        defer {
            activeTask = nil
        }
        return try await task.value
    }

    private func doRefresh(session: MezonSession) async throws -> MezonSession {
        let newSession: MezonSession
        do {
            newSession = try await MezonHTTPClient.shared.sessionRefresh(
                refreshToken: session.refreshToken
            )
        } catch {
            if isDefinitiveAuthFailure(error) {
                if lastRefreshToken == session.refreshToken {
                    failCount += 1
                } else {
                    lastRefreshToken = session.refreshToken
                    failCount = 1
                }
                if failCount >= maxRetriesSameToken {
                    reset()
                    throw SessionError.maxRetriesExceeded
                }
            } else {
                lastFailedRefresh = (Date(), error)
                if isThrottled(error) {
                    holdRefresh(after: error)
                }
            }
            throw error
        }
        let merged = SessionStore.applyIdTokenFallback(newSession.mergedPreservingLocalCredentials(from: session))
        lastRefreshToken = merged.refreshToken
        failCount = 0
        lastSuccessfulRefresh = (Date(), merged)
        lastFailedRefresh = nil
        releaseRefreshThrottle()
        return merged
    }

    private let launchRefreshTimeout: UInt64 = 15_000_000_000

    func refreshOnAppLaunch(
        session: MezonSession,
        onSuccess: @escaping (MezonSession) -> Void,
        onExpired: @escaping () -> Void,
        onReady: @escaping () -> Void
    ) {
        Task { @MainActor in
            var onReadyCalled = false
            func safeOnReady() {
                guard !onReadyCalled else { return }
                onReadyCalled = true
                onReady()
            }

            func endLaunchRefreshExpired() async {
                guard NetworkMonitor.shared.isConnected else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                onExpired()
            }

            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: launchRefreshTimeout)
                safeOnReady()
            }
            defer { timeoutTask.cancel() }

            var retriesLeft = maxAppLaunchRetries

            while retriesLeft > 0 {
                do {
                    let newSession = try await refresh(session: session)
                    onSuccess(newSession)
                    safeOnReady()
                    return
                } catch {
                    if isDefinitiveExpiry(error) {
                        safeOnReady()
                        await endLaunchRefreshExpired()
                        return
                    }
                    retriesLeft -= 1
                    if retriesLeft == 0 {
                        safeOnReady()
                        return
                    }
                    let delay = UInt64(maxAppLaunchRetries - retriesLeft) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    func reset() {
        activeTask?.cancel()
        lastRefreshToken = ""
        failCount = 0
        activeTask = nil
        lastSuccessfulRefresh = nil
        lastFailedRefresh = nil
        releaseRefreshThrottle()
    }
}

enum SessionError: LocalizedError {
    case notInitialized
    case maxRetriesExceeded
    case noSession

    var errorDescription: String? {
        switch self {
        case .notInitialized:     return "Session manager not initialized."
        case .maxRetriesExceeded: return "Session refresh failed: max retries with same token."
        case .noSession:          return "No saved session found."
        }
    }
}
