import Foundation

final class SessionRefreshManager {

    static let shared = SessionRefreshManager()

    private let maxRetriesSameToken = 5
    private let maxAppLaunchRetries = 5

    private var lastRefreshToken: String = ""
    private var failCount: Int = 0
    private var activeRefreshHandle: CancelHandle?
    private var activeRefreshWaiters: [(Result<MezonSession, Error>) -> Void] = []
    private var lastSuccessfulRefresh: (at: Date, session: MezonSession)?
    private let minSuccessfulRefreshInterval: TimeInterval = 2.0
    private var lastFailedRefresh: (at: Date, error: Error)?
    private let minFailedRefreshInterval: TimeInterval = 1.5

    private init() {}

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

    @available(iOS 13.0, *)
    @MainActor
    func awaitInflightRefresh() async {
        guard activeRefreshHandle != nil else { return }
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Result<MezonSession, Error>, Never>) in
            activeRefreshWaiters.append { continuation.resume(returning: $0) }
        }
    }

    private func flushRefreshWaiters(_ result: Result<MezonSession, Error>) {
        let waiters = activeRefreshWaiters
        activeRefreshWaiters.removeAll()
        for waiter in waiters { waiter(result) }
    }

    private func flushRefreshWaitersCancelled() {
        if #available(iOS 13.0, *) {
            flushRefreshWaiters(.failure(CancellationError()))
        } else {
            flushRefreshWaiters(.failure(SessionError.noSession))
        }
    }

    @available(iOS 13.0, *)
    @MainActor
    func refresh(session: MezonSession) async throws -> MezonSession {
        if activeRefreshHandle != nil {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<MezonSession, Error>, Never>) in
                activeRefreshWaiters.append { continuation.resume(returning: $0) }
            }
            return try result.get()
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
        activeRefreshHandle = CancelHandle { task.cancel() }
        do {
            let value = try await task.value
            activeRefreshHandle = nil
            flushRefreshWaiters(.success(value))
            return value
        } catch {
            activeRefreshHandle = nil
            flushRefreshWaiters(.failure(error))
            throw error
        }
    }

    @available(iOS 13.0, *)
    @MainActor
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
            }
            throw error
        }
        let merged = SessionStore.applyIdTokenFallback(newSession.mergedPreservingLocalCredentials(from: session))
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
        guard #available(iOS 13.0, *) else {
            legacyRefreshOnAppLaunch(
                session: session, onSuccess: onSuccess, onExpired: onExpired, onReady: onReady)
            return
        }
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

    /// Signal-based launch refresh for iOS 12, where Swift Concurrency is unavailable.
    private func legacyRefreshOnAppLaunch(
        session: MezonSession,
        onSuccess: @escaping (MezonSession) -> Void,
        onExpired: @escaping () -> Void,
        onReady: @escaping () -> Void
    ) {
        var readyCalled = false
        func safeOnReady() {
            guard !readyCalled else { return }
            readyCalled = true
            onReady()
        }

        let timeoutItem = DispatchWorkItem { safeOnReady() }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(launchRefreshTimeout) / 1_000_000_000,
            execute: timeoutItem
        )

        var retriesLeft = maxAppLaunchRetries
        var attempt: (() -> Void)?
        attempt = { [weak self] in
            guard let self else { timeoutItem.cancel(); safeOnReady(); return }
            let request = MezonHTTPClient.shared.signalSessionRefresh(refreshToken: session.refreshToken)
            _ = (request |> deliverOnMainQueue).start(
                next: { newSession in
                    timeoutItem.cancel()
                    let merged = SessionStore.applyIdTokenFallback(
                        newSession.mergedPreservingLocalCredentials(from: session))
                    self.lastRefreshToken = merged.refreshToken
                    self.failCount = 0
                    self.lastSuccessfulRefresh = (Date(), merged)
                    self.lastFailedRefresh = nil
                    onSuccess(merged)
                    safeOnReady()
                    attempt = nil
                },
                error: { error in
                    if self.isDefinitiveAuthFailure(error) {
                        if self.lastRefreshToken == session.refreshToken {
                            self.failCount += 1
                        } else {
                            self.lastRefreshToken = session.refreshToken
                            self.failCount = 1
                        }
                        if self.failCount >= self.maxRetriesSameToken {
                            timeoutItem.cancel()
                            safeOnReady()
                            attempt = nil
                            guard NetworkMonitor.shared.isConnected else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onExpired() }
                            return
                        }
                    }
                    retriesLeft -= 1
                    if retriesLeft <= 0 {
                        timeoutItem.cancel()
                        safeOnReady()
                        attempt = nil
                        return
                    }
                    let delay = Double(self.maxAppLaunchRetries - retriesLeft)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { attempt?() }
                }
            )
        }
        attempt?()
    }

    func reset() {
        activeRefreshHandle?.cancel()
        activeRefreshHandle = nil
        flushRefreshWaitersCancelled()
        lastRefreshToken = ""
        failCount = 0
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
