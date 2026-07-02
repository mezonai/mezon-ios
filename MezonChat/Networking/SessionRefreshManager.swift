import Foundation

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

    private init() {}

    private func isDefinitiveAuthFailure(_ error: Error) -> Bool {
        if let mezon = error as? MezonError, case .httpError(let code, _) = mezon {
            return code == 401 || code == 403
        }
        return false
    }

    private func isDefinitiveExpiry(_ error: Error) -> Bool {
        if isDefinitiveAuthFailure(error) { return true }
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
            if isDefinitiveAuthFailure(error) || Date() >= session.expiresAt {
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
            }
            if !isDefinitiveAuthFailure(error) {
                lastFailedRefresh = (Date(), error)
            }
            throw error
        }
        let merged = SessionStore.applyIdTokenFallback(newSession.mergedPreservingIdToken(from: session))
        lastRefreshToken = merged.refreshToken
        failCount = 0
        lastSuccessfulRefresh = (Date(), merged)
        lastFailedRefresh = nil
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
                        await endLaunchRefreshExpired()
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
