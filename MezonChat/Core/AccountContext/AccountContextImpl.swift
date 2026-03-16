import Foundation
import SwiftProtobuf

@MainActor
final class AccountContextImpl: AccountContext {

    let sharedContextImpl: SharedAccountContextImpl
    var sharedContext: SharedAccountContext { sharedContextImpl }

    let account: Account
    let engine: MezonEngine

    private let isLoggedInPipe = ValuePipe<Bool>()
    var isLoggedInSignal: Signal<Bool, NoError> { isLoggedInPipe.signal() }

    private(set) var session: MezonSession?
    private(set) var currentUser: User?
    private(set) var isLoggedIn: Bool = false
    private(set) var isSessionReady: Bool = false

    var currentClanId: Int64 = 0
    var currentChannel: Mezon_Api_ChannelDescription?

    static let preview: AccountContext = {
        let shared = SharedAccountContextImpl(mainWindow: nil)
        let account = Account(id: "preview")
        return AccountContextImpl(sharedContext: shared, account: account, session: nil, user: nil, onReady: { _ in })
    }()

    init(
        sharedContext: SharedAccountContextImpl,
        account: Account,
        session: MezonSession?,
        user: User?,
        onReady: @escaping @MainActor (AccountContextImpl) -> Void
    ) {
        self.sharedContextImpl = sharedContext
        self.account = account
        self.engine = MezonEngine(account: account)
        self.session = session
        self.currentUser = user

        if let session {
            restoreAndRefreshSession(saved: session, onReady: onReady)
        } else {
            isSessionReady = true
            onReady(self)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired),
            name: Notification.Name("MezonSessionExpired"),
            object: nil
        )
    }

    func login(user: User, session: MezonSession) {
        applySession(session, user: user)
        setLoggedIn(true)
    }

    func logout() {
        if let s = session {
            Task { try? await engine.auth.sessionLogout(session: s) }
        }
        SessionStore.clear()
        SessionRefreshManager.shared.reset()
        session = nil
        currentUser = nil
        currentClanId = 0
        currentChannel = nil
        account.socket.disconnect()
        account.postbox.clearAll()
        setLoggedIn(false)
    }

    func refreshSession() async throws {
        guard let current = session else { throw SessionError.noSession }
        let new = try await engine.auth.sessionRefresh(session: current)
        applySession(new, user: currentUser, connectSocket: false, fetchAccount: false)
    }

    private var lastRecoverTime: Date?
    private let recoverThrottle: TimeInterval = 20

    func recoverFromForeground() {
        guard session != nil, isLoggedIn else { return }
        let now = Date()
        if let last = lastRecoverTime, now.timeIntervalSince(last) < recoverThrottle { return }
        lastRecoverTime = now
        Task { @MainActor in
            do {
                try await refreshSession()
                if let token = session?.token {
                    account.socket.connect(token: token, wsHostOverride: nil)
                }
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, (code == 401 || code == 403) {
                    SessionExpiredModal.show(onLoginAgain: { [weak self] in self?.logout() })
                } else {
                    account.socket.reconnectFromForeground()
                }
            } catch {
                account.socket.reconnectFromForeground()
            }
        }
    }

    @objc private func handleSessionExpired() {
        SessionExpiredModal.show(onLoginAgain: { [weak self] in self?.logout() })
    }

    private func setLoggedIn(_ value: Bool) {
        isLoggedIn = value
        isLoggedInPipe.putNext(value)
    }

    private func restoreAndRefreshSession(
        saved: MezonSession,
        onReady: @escaping @MainActor (AccountContextImpl) -> Void
    ) {
        session = saved
        currentUser = User(
            id: saved.userId ?? UUID().uuidString,
            username: saved.username ?? "me",
            displayName: saved.username ?? "Me",
            avatarURL: nil, status: .online, bio: nil
        )
        setLoggedIn(true)
        account.network.updateBaseURL(from: saved)

        SessionRefreshManager.shared.refreshOnAppLaunch(
            session: saved,
            onSuccess: { [weak self] newSession in
                guard let self else { return }
                self.applySession(newSession, user: self.currentUser, connectSocket: true)
            },
            onExpired: { [weak self] in
                SessionExpiredModal.show(onLoginAgain: { [weak self] in self?.logout() })
            },
            onReady: { [weak self] in
                guard let self else { return }
                self.isSessionReady = true
                onReady(self)
            }
        )
    }

    private func applySession(
        _ session: MezonSession,
        user: User?,
        connectSocket: Bool = true,
        fetchAccount: Bool = true
    ) {
        self.session = session
        SessionStore.save(session)
        account.network.updateBaseURL(from: session)

        if connectSocket {
            account.socket.tokenProvider = { [weak self] in
                guard let self else { throw SessionError.noSession }
                try await self.refreshSession()
                guard let t = self.session?.token else { throw SessionError.noSession }
                return t
            }
            account.socket.onConnected = { [weak self] in self?.rejoinCurrentChannel() }
            account.socket.onMessageReceived = { [weak self] apiMessage in
                self?.account.postbox.write { tx in
                    tx.addMessages([MessageRecord(from: apiMessage)])
                }
                let channelId = Int64(apiMessage.channelID) ?? 0
                let clanId = Int64(apiMessage.clanID) ?? 0
                AppLogger.app.info("[Badge] onMessageReceived channelId=\(channelId) clanId=\(clanId) senderId=\(apiMessage.senderID) mode=\(apiMessage.mode)")
                NotificationCenter.default.post(
                    name: Notification.Name("MezonNewMessageReceived"),
                    object: nil,
                    userInfo: [
                        "channelId": channelId,
                        "clanId": clanId,
                        "senderId": apiMessage.senderID,
                        "mode": apiMessage.mode,
                        "timestampSeconds": apiMessage.createTimeSeconds
                    ]
                )
            }
            account.socket.onLastSeen = { event in
                NotificationCenter.default.post(
                    name: Notification.Name("MezonChannelMarkedAsRead"),
                    object: nil,
                    userInfo: [
                        "channelId": event.channelID,
                        "clanId": event.clanID
                    ]
                )
            }
            account.socket.onNotification = { [weak self] noti in
                guard noti.channelID != 0 else { return }
                AppLogger.app.info("[Badge] onNotification channelId=\(noti.channelID) clanId=\(noti.clanID)")
                NotificationCenter.default.post(
                    name: Notification.Name("MezonMentionReceived"),
                    object: nil,
                    userInfo: [
                        "channelId": noti.channelID,
                        "clanId": noti.clanID,
                        "senderId": String(noti.senderID),
                        "mode": noti.channelType,
                        "timestampSeconds": noti.createTimeSeconds
                    ]
                )
            }
            account.socket.connect(token: session.token, wsHostOverride: nil)
        }
        if let user { currentUser = user }

        guard fetchAccount else { return }
        Task { @MainActor in
            do {
                let apiAccount = try await engine.auth.getAccount(token: session.token)
                if let data = try? apiAccount.serializedData() {
                    account.postbox.setPreferenceData(key: PreferencesKeys.account, value: data)
                }
                currentUser = mapAccountToUser(apiAccount)
            } catch {
                AppLogger.network.warning("[Auth] getAccount failed: \(error)")
            }
        }
    }

    private func rejoinCurrentChannel() {
        guard let channel = currentChannel else { return }
        account.socket.joinClanChat(clanId: currentClanId)
        let channelType: Int32 = currentClanId == 0
            ? (channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue)
            : (channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue)
        let isPublic = currentClanId == 0
            ? false
            : (channel.parentID != 0 ? false : (channel.channelPrivate == 0))
        account.socket.joinChannel(
            clanId: currentClanId,
            channelId: channel.channelID,
            channelType: channelType,
            isPublic: isPublic
        )
    }

    private func mapAccountToUser(_ api: Mezon_Api_Account) -> User {
        let u = api.user
        return User(
            id: "\(u.id)",
            username: u.username.isEmpty ? "me" : u.username,
            displayName: u.displayName.isEmpty ? u.username : u.displayName,
            avatarURL: u.avatarURL.isEmpty ? nil : URL(string: u.avatarURL),
            status: u.online ? .online : .offline,
            bio: u.aboutMe.isEmpty ? nil : u.aboutMe,
            email: api.email.isEmpty ? nil : api.email,
            phoneNumber: u.phoneNumber.isEmpty ? nil : u.phoneNumber,
            isBot: false
        )
    }
}
