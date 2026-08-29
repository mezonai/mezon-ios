import Foundation

// Session lifecycle for the iOS 12 path. `SessionRefreshManager` is @MainActor and
// coalesces in-flight refreshes through `Task`, so it cannot be reused here.
// This replacement is deliberately simpler and does NOT coalesce: concurrent
// callers of `validToken()` on an expired session would each issue a refresh.
// That is acceptable while `LegacyHomeViewController` is the only caller; add
// coalescing before wiring up more of the iOS 12 UI.
final class LegacySessionManager {

    static let shared = LegacySessionManager()

    private(set) var session: MezonSession?
    private var logoutDisposable: MetaDisposable?

    private init() {
        session = SessionStore.load()
        if let session = session {
            MezonHTTPClient.shared.updateBaseURL(from: session)
        }
    }

    var isLoggedIn: Bool {
        return session != nil
    }

    func store(_ session: MezonSession) {
        self.session = session
        SessionStore.save(session)
        MezonHTTPClient.shared.updateBaseURL(from: session)
    }

    func clear() {
        logoutDisposable?.dispose()
        logoutDisposable = nil
        clearState()
    }

    // Separate from `clear()` so the logout callback can drop the session without
    // disposing the very disposable whose callback is running.
    private func clearState() {
        session = nil
        SessionStore.clear()
        MezonHTTPClient.shared.resetProtoBaseURLToDefault()
    }

    func validToken() -> Signal<String, MezonError> {
        guard let session = session else {
            return fail(String.self, MezonError.httpError(statusCode: 401, message: "No session"))
        }
        if !session.isExpired {
            return Signal<String, MezonError>.single(session.token)
        }
        return MezonHTTPClient.shared.signalSessionRefresh(refreshToken: session.refreshToken)
            |> deliverOnMainQueue
            |> map { [weak self] refreshed -> String in
                self?.store(refreshed)
                return refreshed.token
            }
    }

    func logout(completion: @escaping () -> Void) {
        guard let session = session else {
            completion()
            return
        }
        let disposable = MetaDisposable()
        logoutDisposable = disposable
        disposable.set((MezonHTTPClient.shared.signalSessionLogout(session: session)
            |> deliverOnMainQueue).start(
                error: { [weak self] _ in
                    self?.clearState()
                    completion()
                },
                completed: { [weak self] in
                    self?.clearState()
                    completion()
                }
            ))
    }
}
