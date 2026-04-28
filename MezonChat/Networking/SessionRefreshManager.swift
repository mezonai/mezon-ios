import Foundation

@MainActor
final class SessionRefreshManager {

    static let shared = SessionRefreshManager()

    private let maxRetriesSameToken = 5
    private let maxAppLaunchRetries = 5

    private var lastRefreshToken: String = ""
    private var failCount: Int = 0
    private var activeTask: Task<MezonSession, Error>?

    private init() {}

    private func isTransientURLError(_ error: Error) -> Bool {
        var e: Error? = error
        for _ in 0..<4 {
            guard let err = e else { break }
            let ns = err as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
                    NSURLErrorCannotConnectToHost, NSURLErrorDataNotAllowed:
                    return true
                default: break
                }
            }
            e = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }

    func refresh(session: MezonSession) async throws -> MezonSession {
        if let active = activeTask {
            return try await active.value
        }
        let task = Task<MezonSession, Error> { [weak self] in
            guard let self else { throw SessionError.notInitialized }
            return try await self.doRefresh(session: session)
        }
        activeTask = task
        defer { activeTask = nil }
        return try await task.value
    }

    private func doRefresh(session: MezonSession) async throws -> MezonSession {
        let isSameToken = lastRefreshToken == session.refreshToken
        if isSameToken {
            failCount += 1
        } else {
            lastRefreshToken = session.refreshToken
            failCount = 0
        }

        if failCount >= maxRetriesSameToken {
            reset()
            throw SessionError.maxRetriesExceeded
        }

        let newSession: MezonSession
        do {
            newSession = try await MezonHTTPClient.shared.sessionRefresh(
                refreshToken: session.refreshToken
            )
        } catch {
            let transient = isTransientURLError(error)
            if transient, isSameToken {
                failCount = max(0, failCount - 1)
            }
            throw error
        }
        let merged = SessionStore.applyIdTokenFallback(newSession.mergedPreservingIdToken(from: session))
        lastRefreshToken = merged.refreshToken
        failCount = 0
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
            func safeOnReady(source: String) {
                guard !onReadyCalled else {
                    return
                }
                onReadyCalled = true
                onReady()
            }

            func endLaunchRefreshExpired() async {
                if NetworkMonitor.shared.isConnected {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    onExpired()
                }
            }

            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: launchRefreshTimeout)
                safeOnReady(source: "timeout")
            }
            defer { timeoutTask.cancel() }

            var retriesLeft = maxAppLaunchRetries

            while retriesLeft > 0 {
                do {
                    let newSession = try await refresh(session: session)
                    onSuccess(newSession)
                    safeOnReady(source: "success")
                    return
                } catch is MezonError {
                    retriesLeft -= 1
                    if retriesLeft == 0 {
                        safeOnReady(source: "MezonError-exhausted")
                        await endLaunchRefreshExpired()
                        return
                    }

                    let delay = UInt64(maxAppLaunchRetries - retriesLeft) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)

                } catch is SessionError {
                    retriesLeft -= 1
                    if retriesLeft == 0 {
                        safeOnReady(source: "SessionError-exhausted")
                        await endLaunchRefreshExpired()
                        return
                    }
                    let delay = UInt64(maxAppLaunchRetries - retriesLeft) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                } catch {
                    retriesLeft -= 1
                    if retriesLeft == 0 {
                        safeOnReady(source: "catch-exhausted")
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
        lastRefreshToken = ""
        failCount = 0
        activeTask = nil
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
