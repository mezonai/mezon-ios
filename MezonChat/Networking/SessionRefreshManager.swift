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

        let newSession = try await MezonHTTPClient.shared.sessionRefresh(
            refreshToken: session.refreshToken
        )
        lastRefreshToken = newSession.refreshToken
        failCount = 0
        return newSession
    }

    func refreshOnAppLaunch(
        session: MezonSession,
        onSuccess: @escaping (MezonSession) -> Void,
        onExpired: @escaping () -> Void,
        onReady: @escaping () -> Void
    ) {
        Task {
            var retriesLeft = maxAppLaunchRetries

            while retriesLeft > 0 {
                do {
                    let newSession = try await refresh(session: session)
                    onSuccess(newSession)
                    onReady()
                    return
                } catch let error as MezonError {
                    retriesLeft -= 1
                    AppLogger.app.warning("Session refresh failed (retries left: \(retriesLeft)): \(error)")

                    onReady()

                    if retriesLeft == 0 {
                        switch error {
                        case .httpError(let code, _) where code == 401 || code == 403:
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            onExpired()
                        default:
                            break
                        }
                        return
                    }

                    let delay = UInt64(maxAppLaunchRetries - retriesLeft) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)

                } catch let error as SessionError {
                    retriesLeft -= 1
                    AppLogger.app.warning("Session refresh guard error: \(error)")
                    onReady()
                    if retriesLeft == 0 { onExpired() }
                    return
                } catch {
                    retriesLeft -= 1
                    AppLogger.app.warning("Unexpected refresh error: \(error)")
                    onReady()
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
