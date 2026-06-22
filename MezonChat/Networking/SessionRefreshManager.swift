import Foundation

enum SessionRefreshDebugLog {
    static func log(_ message: @autoclosure () -> String) {
        print("[SessionRefreshDebug] \(message())")
    }

    static func token(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "empty" }
        return "len=\(token.count) fp=\(fingerprint(token))"
    }

    static func session(_ session: MezonSession?) -> String {
        guard let session else { return "nil" }
        let expiresIn = Int(session.expiresAt.timeIntervalSinceNow)
        return "access(\(token(session.token))) refresh(\(token(session.refreshToken))) expiresIn=\(expiresIn)s expired=\(session.isExpired) created=\(session.created)"
    }

    static func error(_ error: Error) -> String {
        let ns = error as NSError
        if let mezonError = error as? MezonError {
            return "\(mezonError.localizedDescription)"
        }
        return "domain=\(ns.domain) code=\(ns.code) desc='\(ns.localizedDescription)'"
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(String(format: "%016llx", CUnsignedLongLong(hash)).suffix(10))
    }
}

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
            SessionRefreshDebugLog.log("manager.refresh join-active session=\(SessionRefreshDebugLog.session(session))")
            return try await active.value
        }
        SessionRefreshDebugLog.log("manager.refresh start session=\(SessionRefreshDebugLog.session(session))")
        let task = Task<MezonSession, Error> { [weak self] in
            guard let self else { throw SessionError.notInitialized }
            return try await self.doRefresh(session: session)
        }
        activeTask = task
        defer {
            SessionRefreshDebugLog.log("manager.refresh clear-active")
            activeTask = nil
        }
        do {
            let result = try await task.value
            SessionRefreshDebugLog.log("manager.refresh success result=\(SessionRefreshDebugLog.session(result))")
            return result
        } catch {
            SessionRefreshDebugLog.log("manager.refresh fail error=\(SessionRefreshDebugLog.error(error))")
            throw error
        }
    }

    private func doRefresh(session: MezonSession) async throws -> MezonSession {
        let isSameToken = lastRefreshToken == session.refreshToken
        if isSameToken {
            failCount += 1
        } else {
            lastRefreshToken = session.refreshToken
            failCount = 0
        }
        SessionRefreshDebugLog.log("manager.doRefresh tokenState sameRefresh=\(isSameToken) failCount=\(failCount) max=\(maxRetriesSameToken) refresh=\(SessionRefreshDebugLog.token(session.refreshToken))")

        if failCount >= maxRetriesSameToken {
            SessionRefreshDebugLog.log("manager.doRefresh stop maxRetriesExceeded refresh=\(SessionRefreshDebugLog.token(session.refreshToken))")
            reset()
            throw SessionError.maxRetriesExceeded
        }

        let newSession: MezonSession
        do {
            SessionRefreshDebugLog.log("manager.doRefresh call-http refresh=\(SessionRefreshDebugLog.token(session.refreshToken))")
            newSession = try await MezonHTTPClient.shared.sessionRefresh(
                refreshToken: session.refreshToken
            )
        } catch {
            let transient = isTransientURLError(error)
            if transient, isSameToken {
                failCount = max(0, failCount - 1)
            }
            SessionRefreshDebugLog.log("manager.doRefresh http-fail transient=\(transient) failCount=\(failCount) error=\(SessionRefreshDebugLog.error(error))")
            throw error
        }
        let merged = SessionStore.applyIdTokenFallback(newSession.mergedPreservingIdToken(from: session))
        lastRefreshToken = merged.refreshToken
        failCount = 0
        SessionRefreshDebugLog.log("manager.doRefresh merged=\(SessionRefreshDebugLog.session(merged))")
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
            SessionRefreshDebugLog.log("launchRefresh start session=\(SessionRefreshDebugLog.session(session)) maxRetries=\(maxAppLaunchRetries)")
            var onReadyCalled = false
            func safeOnReady(source: String) {
                guard !onReadyCalled else {
                    SessionRefreshDebugLog.log("launchRefresh onReady ignored source=\(source)")
                    return
                }
                onReadyCalled = true
                SessionRefreshDebugLog.log("launchRefresh onReady source=\(source)")
                onReady()
            }

            func endLaunchRefreshExpired() async {
                if NetworkMonitor.shared.isConnected {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    SessionRefreshDebugLog.log("launchRefresh expired connected=true")
                    onExpired()
                } else {
                    SessionRefreshDebugLog.log("launchRefresh expired skipped connected=false")
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
                    let attempt = maxAppLaunchRetries - retriesLeft + 1
                    SessionRefreshDebugLog.log("launchRefresh attempt=\(attempt) retriesLeft=\(retriesLeft)")
                    let newSession = try await refresh(session: session)
                    SessionRefreshDebugLog.log("launchRefresh success session=\(SessionRefreshDebugLog.session(newSession))")
                    onSuccess(newSession)
                    safeOnReady(source: "success")
                    return
                } catch let error as MezonError {
                    retriesLeft -= 1
                    SessionRefreshDebugLog.log("launchRefresh mezonError retriesLeft=\(retriesLeft) error=\(SessionRefreshDebugLog.error(error))")
                    if retriesLeft == 0 {
                        safeOnReady(source: "MezonError-exhausted")
                        await endLaunchRefreshExpired()
                        return
                    }

                    let delay = UInt64(maxAppLaunchRetries - retriesLeft) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)

                } catch let error as SessionError {
                    retriesLeft -= 1
                    SessionRefreshDebugLog.log("launchRefresh sessionError retriesLeft=\(retriesLeft) error=\(SessionRefreshDebugLog.error(error))")
                    if retriesLeft == 0 {
                        safeOnReady(source: "SessionError-exhausted")
                        await endLaunchRefreshExpired()
                        return
                    }
                    let delay = UInt64(maxAppLaunchRetries - retriesLeft) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                } catch {
                    retriesLeft -= 1
                    SessionRefreshDebugLog.log("launchRefresh error retriesLeft=\(retriesLeft) error=\(SessionRefreshDebugLog.error(error))")
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
        SessionRefreshDebugLog.log("manager.reset active=\(activeTask != nil) lastRefresh=\(SessionRefreshDebugLog.token(lastRefreshToken)) failCount=\(failCount)")
        activeTask?.cancel()
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
