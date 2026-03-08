import Foundation
import Combine

@MainActor
final class AppContext: ObservableObject {

    @Published var currentUser: User?
    @Published var isLoggedIn: Bool = false
    @Published var isSessionReady: Bool = false

    private(set) var session: MezonSession?
    private weak var sharedDataStore: SharedDataStore?

    init(sharedDataStore: SharedDataStore? = nil) {
        self.sharedDataStore = sharedDataStore
        restoreAndRefreshSession()
    }

    func login(user: User, session: MezonSession) {
        applySession(session, user: user)
        isLoggedIn = true
    }

    func logout() {
        if let session {
            Task { try? await MezonHTTPClient.shared.sessionLogout(session: session) }
        }
        SessionStore.clear()
        SessionRefreshManager.shared.reset()
        session = nil
        currentUser = nil
        isLoggedIn = false
        isSessionReady = true
        MezonSocket.shared.disconnect()
    }

    func refreshSession() async throws {
        guard let current = session else { throw SessionError.noSession }
        let newSession = try await SessionRefreshManager.shared.refresh(session: current)
        applySession(newSession, user: currentUser)
    }

    private func restoreAndRefreshSession() {
        guard let saved = SessionStore.load() else {
            isSessionReady = true
            return
        }

        session = saved
        currentUser = User(
            id: saved.userId ?? UUID().uuidString,
            username: saved.username ?? "me",
            displayName: saved.username ?? "Me",
            avatarURL: nil,
            status: .online,
            bio: nil
        )
        isLoggedIn = true
        MezonHTTPClient.shared.updateBaseURL(from: saved)

        sharedDataStore?.hydrateFromPostbox()

        SessionRefreshManager.shared.refreshOnAppLaunch(
            session: saved,
            onSuccess: { [weak self] newSession in
                guard let self else { return }
                self.applySession(newSession, user: self.currentUser, connectSocket: true)
                AppLogger.app.info("Session refreshed for: \(newSession.username ?? "unknown")")
            },
            onExpired: { [weak self] in
                AppLogger.app.warning("Session expired after max retries — logging out")
                self?.logout()
            },
            onReady: { [weak self] in
                self?.isSessionReady = true
            }
        )
    }

    private func applySession(_ session: MezonSession, user: User?, connectSocket: Bool = true) {
        self.session = session
        SessionStore.save(session)
        MezonHTTPClient.shared.updateBaseURL(from: session)

        sharedDataStore?.authStore.setSession(session)
        AppLogger.app.info("[Auth] Session refreshed — token: \(session.token.prefix(50))...")

        if connectSocket {
            MezonSocket.shared.connect(token: session.token, wsHostOverride: nil)
        }
        if let user { currentUser = user }

        Task { @MainActor in
            do {
                let account = try await MezonHTTPClient.shared.getAccount(token: session.token)
                sharedDataStore?.authStore.setAccount(account)
                currentUser = sharedDataStore?.authStore.user ?? currentUser
            } catch {
                AppLogger.network.warning("[Auth] getAccount failed: \(error)")
            }
        }
    }
}
