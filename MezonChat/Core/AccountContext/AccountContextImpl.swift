import Foundation
import FirebaseMessaging
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
    private var hasCompletedInitialSetup = false
    private(set) var isSessionReady: Bool = false
    private var sessionReadyContinuations: [CheckedContinuation<Void, Never>] = []
    private var activeRefreshTask: Task<Bool, Never>?
    func waitForSessionReady() async {
        if isSessionReady { return }
        await withCheckedContinuation { continuation in
            if isSessionReady {
                continuation.resume()
            } else {
                sessionReadyContinuations.append(continuation)
            }
        }
    }

    func getToken() async -> String? {
        await waitForSessionReady()

        if let inflight = activeRefreshTask {
            _ = await inflight.value
        }

        if let session, session.isExpired {
            let refreshed = await ensureRefreshed()
            if !refreshed {
                AppLogger.network.warning("[Auth] getToken: token still expired after refresh attempts")
                return nil
            }
        }
        if let session, session.isExpired {
            return nil
        }
        return session?.token
    }

    private func ensureRefreshed() async -> Bool {
        if let inflight = activeRefreshTask {
            return await inflight.value
        }
        let task = Task<Bool, Never> { @MainActor in
            defer { self.activeRefreshTask = nil }
            for attempt in 1...2 {
                do {
                    try await self.refreshSession()
                    AppLogger.network.info("[Auth] token was expired, refreshed on attempt \(attempt)")
                    return true
                } catch {
                    AppLogger.network.warning("[Auth] getToken refresh attempt \(attempt) failed: \(error)")
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
            return false
        }
        activeRefreshTask = task
        return await task.value
    }

    private func markSessionReady() {
        guard !isSessionReady else { return }
        isSessionReady = true
        let continuations = sessionReadyContinuations
        sessionReadyContinuations.removeAll()
        for c in continuations { c.resume() }
    }

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
            markSessionReady()
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
        applySession(session, user: user, connectSocket: false)
        setLoggedIn(true)
        hasCompletedInitialSetup = true
        lastRecoverTime = Date()
        markSessionReady()

        Task { @MainActor in
            do {
                try await refreshSession()
            } catch {
                AppLogger.network.warning("[Auth] cold launch refresh failed: \(error)")
            }
            if let freshSession = self.session {
                applySession(freshSession, user: currentUser, connectSocket: true, fetchAccount: false)
            }
            self.registerFCMTokenIfNeeded()
        }
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
        UserDefaults.standard.removeObject(forKey: "mezon_selectedClanId")
        setLoggedIn(false)
    }

    private func registerFCMTokenIfNeeded() {
        guard let fcmToken = Messaging.messaging().fcmToken else {
            AppLogger.network.info("[FCM] No FCM token available yet")
            return
        }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        Task {
            guard let authToken = await self.getToken() else { return }
            do {
                _ = try await account.network.registFcmDeviceToken(
                    fcmToken: fcmToken, deviceId: deviceId, platform: "ios", authToken: authToken
                )
                AppLogger.network.info("[FCM] Token registered on login")
            } catch {
                AppLogger.network.error("[FCM] Token registration on login failed: \(error)")
            }
        }
    }

    func refreshSession() async throws {
        guard let current = session else { throw SessionError.noSession }
        let new = try await engine.auth.sessionRefresh(session: current)
        applySession(new, user: currentUser, connectSocket: false, fetchAccount: false)
    }

    private var lastRecoverTime: Date?
    private let recoverThrottle: TimeInterval = 5
    private let maxForegroundRecoverRetries = 3

    func recoverFromForeground() {
        guard hasCompletedInitialSetup, session != nil, isLoggedIn else { return }
        let now = Date()
        if let last = lastRecoverTime, now.timeIntervalSince(last) < recoverThrottle { return }
        lastRecoverTime = now

        let needsRefresh = session?.isExpired ?? true

        if needsRefresh {
            AppLogger.network.info("[Auth] recoverFromForeground: token expired, refreshing...")
            let task = Task<Bool, Never> { @MainActor in
                defer { self.activeRefreshTask = nil }
                let refreshed = await self.refreshSessionWithRetry()
                if refreshed, let token = self.session?.token {
                    self.account.socket.connect(token: token, wsHostOverride: nil)
                }
                return refreshed
            }
            activeRefreshTask = task
        } else {
            AppLogger.network.info("[Auth] recoverFromForeground: token still valid, reconnecting socket only")
            if let token = session?.token {
                account.socket.connect(token: token, wsHostOverride: nil)
            }
        }
    }

    /// Retry refresh session up to maxForegroundRecoverRetries times.
    /// Returns true if refreshed successfully, false if session expired (modal shown).
    private func refreshSessionWithRetry() async -> Bool {
        for attempt in 1...maxForegroundRecoverRetries {
            do {
                try await refreshSession()
                AppLogger.network.info("[Auth] refreshSession succeeded on attempt \(attempt)")
                return true
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, (code == 401 || code == 403) {
                    AppLogger.network.warning("[Auth] refreshSession got \(code), session expired")
                    SessionExpiredModal.show(onLoginAgain: { [weak self] in self?.logout() })
                    return false
                }
                AppLogger.network.warning("[Auth] refreshSession attempt \(attempt) failed: \(error)")
            } catch {
                AppLogger.network.warning("[Auth] refreshSession attempt \(attempt) failed: \(error)")
            }

            if attempt < maxForegroundRecoverRetries {
                let delay = UInt64(attempt) * 2_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        AppLogger.network.warning("[Auth] refreshSession all \(self.maxForegroundRecoverRetries) attempts failed, trying socket reconnect")
        account.socket.reconnectFromForeground()
        return false
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
                self.registerFCMTokenIfNeeded()
                self.markSessionReady()
            },
            onExpired: { [weak self] in
                self?.markSessionReady()
                SessionExpiredModal.show(onLoginAgain: { [weak self] in self?.logout() })
            },
            onReady: { [weak self] in
                guard let self else { return }
                // Fallback: mark ready on timeout even if refresh hasn't completed
                self.markSessionReady()
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
                let channelId = Int64(apiMessage.channelID) ?? 0
                let clanId = Int64(apiMessage.clanID) ?? 0
                if apiMessage.code == 2 {
                    let messageId = "\(apiMessage.messageID)"
                    self?.account.postbox.write { tx in
                        tx.deleteMessage(id: messageId)
                    }
                    return
                }

                self?.account.postbox.write { tx in
                    tx.addMessages([MessageRecord(from: apiMessage)])
                }
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
            account.socket.onReaction = { [weak self] reaction in
                let messageId = "\(reaction.messageID)"

                self?.account.postbox.write { tx in
                    tx.updateMessageReactions(messageId: messageId, reaction: reaction)
                }
            }
            account.socket.onMessageRemoved = { [weak self] removed in
                let messageId = "\(removed.messageID)"
                self?.account.postbox.write { tx in
                    tx.deleteMessage(id: messageId)
                }
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
            self.fetchAllUserClansAndChannels(token: session.token)
        }
    }

    private func fetchAllUserClansAndChannels(token: String) {
        Task { @MainActor in
            do {
                async let usersResult = account.network.listUserClansByUserId(token: token)
                async let channelsResult = account.network.listChannelByUserId(token: token)
                let (users, channels) = try await (usersResult, channelsResult)
                if let data = try? users.serializedData() {
                    account.postbox.setPreferenceData(key: PreferencesKeys.allUserClans, value: data)
                }
                if let data = try? channels.serializedData() {
                    account.postbox.setPreferenceData(key: PreferencesKeys.allChannelsByUser, value: data)
                }
                AppLogger.network.info("[Auth] fetched allUserClans(\(users.users.count)) allChannelsByUser(\(channels.channeldesc.count))")
            } catch {
                AppLogger.network.warning("[Auth] fetchAllUserClansAndChannels failed: \(error)")
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
