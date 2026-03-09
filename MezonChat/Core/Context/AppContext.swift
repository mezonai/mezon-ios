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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired),
            name: Notification.Name("MezonSessionExpired"),
            object: nil
        )
    }

    @objc private func handleSessionExpired() {
        SessionExpiredModal.show(onLoginAgain: { [weak self] in
            self?.logout()
        })
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
        applySession(newSession, user: currentUser, connectSocket: false, fetchAccount: false)
    }

    private var lastRecoverFromForegroundTime: Date?
    private let recoverThrottleInterval: TimeInterval = 20

    func recoverFromForeground() {
        guard session != nil, isLoggedIn else { return }
        let now = Date()
        if let last = lastRecoverFromForegroundTime, now.timeIntervalSince(last) < recoverThrottleInterval {
            return
        }
        lastRecoverFromForegroundTime = now
        Task { @MainActor in
            do {
                try await refreshSession()
                if let token = session?.token {
                    MezonSocket.shared.connect(token: token, wsHostOverride: nil)
                }
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, code == 401 || code == 403 {
                    AppLogger.app.warning("[Auth] Session expired on foreground")
                    SessionExpiredModal.show(onLoginAgain: { [weak self] in
                        self?.logout()
                    })
                } else {
                    MezonSocket.shared.reconnectFromForeground()
                }
            } catch {
                AppLogger.network.warning("[Auth] recoverFromForeground refresh failed: \(error), trying socket reconnect")
                MezonSocket.shared.reconnectFromForeground()
            }
        }
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
                AppLogger.app.warning("Session expired after max retries")
                SessionExpiredModal.show(onLoginAgain: { [weak self] in
                    self?.logout()
                })
            },
            onReady: { [weak self] in
                self?.isSessionReady = true
            }
        )
    }

    private func applySession(_ session: MezonSession, user: User?, connectSocket: Bool = true, fetchAccount: Bool = true) {
        self.session = session
        SessionStore.save(session)
        MezonHTTPClient.shared.updateBaseURL(from: session)

        sharedDataStore?.authStore.setSession(session)
        AppLogger.app.info("[Auth] Session refreshed — token: \(session.token.prefix(50))...")

        if connectSocket {
            MezonSocket.shared.tokenProvider = { [weak self] in
                guard let self else { throw SessionError.noSession }
                try await self.refreshSession()
                guard let t = self.session?.token else { throw SessionError.noSession }
                return t
            }
            MezonSocket.shared.onConnected = { [weak self] in
                self?.rejoinCurrentChannel()
            }
            MezonSocket.shared.connect(token: session.token, wsHostOverride: nil)
        }
        if let user { currentUser = user }

        guard fetchAccount else { return }
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

    private func rejoinCurrentChannel() {
        guard let channelsStore = sharedDataStore?.channelsStore,
              let channel = channelsStore.currentChannel else { return }
        let clanId = channelsStore.currentClanId
        MezonSocket.shared.joinClanChat(clanId: clanId)
        let channelType: Int32 = clanId == 0
            ? (channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue)
            : (channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue)
        let isPublic = clanId == 0 ? false : (channel.parentID != 0 ? false : (channel.channelPrivate == 0))
        MezonSocket.shared.joinChannel(clanId: clanId, channelId: channel.channelID, channelType: channelType, isPublic: isPublic)
        AppLogger.app.info("[Auth] MezonSocket re-joined clanId=\(clanId) channelId=\(channel.channelID)")
    }
}
