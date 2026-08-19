import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging
import SwiftProtobuf

final class MessageEchoRegistry {
    static let shared = MessageEchoRegistry()

    private let lock = NSLock()
    private var echoTimestamps: [String: Date] = [:]
    private let ttl: TimeInterval = 120

    func recordEcho(messageId: String) {
        guard !messageId.isEmpty, messageId != "0" else { return }
        lock.lock(); defer { lock.unlock() }
        pruneLocked()
        echoTimestamps[messageId] = Date()
    }

    func hasEcho(messageId: String) -> Bool {
        guard !messageId.isEmpty, messageId != "0" else { return false }
        lock.lock(); defer { lock.unlock() }
        pruneLocked()
        return echoTimestamps[messageId] != nil
    }

    private func pruneLocked() {
        let now = Date()
        echoTimestamps = echoTimestamps.filter { now.timeIntervalSince($0.value) < ttl }
    }
}

@MainActor
final class AccountContextImpl: AccountContext {

    let sharedContextImpl: SharedAccountContextImpl
    var sharedContext: SharedAccountContext { sharedContextImpl }

    let account: Account
    let engine: MezonEngine
    private(set) lazy var rolePermissions: RolePermissionService = {
        let service = RolePermissionService(
            engine: self.engine,
            userIdProvider: { [weak self] in self?.currentUser?.id },
            currentClanIdProvider: { [weak self] in self?.currentClanId ?? 0 },
            tokenProvider: { [weak self] in await self?.getToken() }
        )
        service.start()
        return service
    }()

    private var socketEventsDisposable: Disposable?
    private let isLoggedInPipe = ValuePipe<Bool>()
    var isLoggedInSignal: Signal<Bool, NoError> { isLoggedInPipe.signal() }

    private(set) var session: MezonSession?
    private(set) var currentUser: User?
    private(set) var isLoggedIn: Bool = false
    private(set) var sessionEpoch: Int = 1
    private var hasCompletedInitialSetup = false
    private(set) var isSessionReady: Bool = false
    private var sessionReadyContinuations: [CheckedContinuation<Void, Never>] = []
    private var activeRefreshTask: Task<Bool, Never>?
    private var activeBearerRecoveryTask: Task<String?, Never>?
    private var didNotifySessionExpired = false
    private var heavyAccountBootstrapTask: Task<Void, Never>?
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

    private func waitForSessionReadyBounded(maxWaitNanos: UInt64) async {
        guard !isSessionReady else { return }
        let step: UInt64 = 100_000_000
        var waited: UInt64 = 0
        while !isSessionReady, waited < maxWaitNanos {
            try? await Task.sleep(nanoseconds: step)
            waited += step
        }
    }

    func applyCurrentUser(_ user: User) {
        currentUser = user
        SentryLogger.setUser(username: user.username)
        NotificationCenter.default.post(name: .mezonAccountCurrentUserDidChange, object: nil)
    }

    func isStillCurrentSession(epoch: Int) -> Bool {
        sessionEpoch == epoch
    }

    func refreshAccountProfile() async {
        guard let token = await getToken() else {
            applyCachedAccountIfAvailable()
            return
        }
        do {
            let apiAccount = try await engine.auth.getAccount(token: token)
            if let data = try? apiAccount.serializedData() {
                account.postbox.setPreferenceData(key: PreferencesKeys.account, value: data)
            }
            applyCurrentUser(mapAccountToUser(apiAccount))
        } catch {
            applyCachedAccountIfAvailable()
        }
    }

    func updatePresenceStatus(_ status: User.OnlineStatus) async throws {
        guard let token = await getToken() else {
            throw MezonError.socketError("Not authenticated")
        }
        let api = status.apiPresenceString
        var req = Mezon_Api_UserStatusUpdate()
        req.status = api
        req.minutes = 0
        req.untilTurnOn = true
        try await account.network.updateUserStatus(req, token: token)
        if var u = currentUser {
            u.status = status
            applyCurrentUser(u)
        }
        await refreshAccountProfile()
        if var u = currentUser, u.status != status {
            u.status = status
            applyCurrentUser(u)
        }
    }

    func submitCustomStatus(text: String, minutes: Int32, noClear: Bool) async throws {
        guard await getToken() != nil else {
            throw MezonError.socketError("Not authenticated")
        }
        let clanId = resolvedClanIdForCustomStatus()
        account.socket.writeCustomStatus(
            clanId: clanId,
            status: text,
            minutes: minutes,
            noClear: noClear
        )
        if var u = currentUser {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                u.customStatus = nil
                u.customStatusTimeReset = nil
                u.customStatusNoClear = nil
            } else {
                u.customStatus = trimmed
                u.customStatusTimeReset = minutes
                u.customStatusNoClear = noClear
            }
            applyCurrentUser(u)
        }
    }

    func fetchCurrentUserStatus() async {
        guard let token = await getToken() else { return }
        do {
            let resp = try await account.network.getUserStatus(token: token)
            let raw = resp.status.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                return
            }
            if var u = currentUser {
                u.status = User.presenceStatus(fromApiString: raw, onlineFallback: u.status == .online)
                applyCurrentUser(u)
            }
        } catch {
        }
    }

    private func resolvedClanIdForCustomStatus() -> Int64 {
        if currentClanId != 0 { return currentClanId }
        if let v = UserDefaults.standard.object(forKey: "mezon_selectedClanId") as? Int64 { return v }
        if let v = UserDefaults.standard.object(forKey: "mezon_selectedClanId") as? Int { return Int64(v) }
        return 0
    }

    func getToken() async -> String? {
        await waitForSessionReady()
        return await resolvedBearerTokenAfterSessionReadyAssumingMarked()
    }

    func getTokenPreferringCachedSkipSessionReadyWait() async -> String? {
        if let inflight = activeRefreshTask {
            _ = await inflight.value
        }
        await SessionRefreshManager.shared.awaitInflightRefresh()

        if !isSessionReady {
            await waitForSessionReadyBounded(maxWaitNanos: 2_500_000_000)
        }

        let fromMemory = session
        let fromDisk = SessionStore.load()
        for cand in [fromMemory, fromDisk].compactMap({ $0 }) {
            guard !cand.token.isEmpty else { continue }
            if !cand.isExpired { return cand.token }
        }
        await waitForSessionReady()
        return await resolvedBearerTokenAfterSessionReadyAssumingMarked()
    }

    private func resolvedBearerTokenAfterSessionReadyAssumingMarked() async -> String? {
        if let inflight = activeRefreshTask {
            _ = await inflight.value
        }
        if let session, session.isExpired {
            let refreshed = await ensureRefreshed()
            if !refreshed {
                if let recovered = self.session, !recovered.token.isEmpty, !recovered.isExpired {
                    return recovered.token
                }
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
            defer {
                self.activeRefreshTask = nil
            }
            for attempt in 1...2 {
                guard !Task.isCancelled else { return false }
                do {
                    try await self.refreshSession()
                    return true
                } catch is SessionError {
                    self.notifySessionExpiredAndStopRecovery()
                    return false
                } catch is CancellationError {
                    return false
                } catch {
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
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

    func clearPersistedSelectedChannelPreference(forClanId clanId: Int64) {
        guard clanId != 0 else { return }
        account.postbox.setPreferenceDataSync(key: PreferencesKeys.selectedChannelId(clanId: clanId), value: nil)
    }

    func clearAllPersistedSelectedChannelPreferences() {
        account.postbox.clearPreferencesSync(withPrefix: PreferencesKeys.selectedChannelIdPrefix)
    }

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

        _ = self.rolePermissions

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
        sessionEpoch &+= 1
        let startEpoch = sessionEpoch
        didNotifySessionExpired = false
        VoIPAnswerAccountBridge.context = self
        applySession(session, user: user, connectSocket: false)
        setLoggedIn(true)
        hasCompletedInitialSetup = true
        lastRecoverTime = Date()
        markSessionReady()
        rolePermissions.start()

        Task { @MainActor in
            do {
                try await refreshSession()
            } catch {
            }
            guard self.isStillCurrentSession(epoch: startEpoch) else { return }
            if let freshSession = self.session {
                applySession(freshSession, user: currentUser, connectSocket: true, fetchAccount: false)
                scheduleHeavyAccountBootstrapAfterYield(token: freshSession.token)
            }
            self.registerFCMTokenIfNeeded()
        }
    }

    func replaceCurrentSession(user: User, session: MezonSession) {
        didNotifySessionExpired = false
        VoIPAnswerAccountBridge.context = self
        applySession(session, user: user, connectSocket: !session.created, fetchAccount: false)
        setLoggedIn(true)
        hasCompletedInitialSetup = true
        lastRecoverTime = Date()
        markSessionReady()
        rolePermissions.start()
        scheduleHeavyAccountBootstrapAfterYield(token: session.token)
        registerFCMTokenIfNeeded()
    }

    func logout() {
        sessionEpoch &+= 1
        heavyAccountBootstrapTask?.cancel()
        heavyAccountBootstrapTask = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeBearerRecoveryTask?.cancel()
        activeBearerRecoveryTask = nil
        didNotifySessionExpired = false
        fcmRegistrationTask?.cancel()
        fcmRegistrationTask = nil
        lastRegisteredFcmKey = nil
        if VoIPAnswerAccountBridge.context === self {
            VoIPAnswerAccountBridge.context = nil
        }
        SessionExpiredModal.removeOverlayIfPresented()
        account.network.bearerUnauthorizedRecovery = nil
        account.network.bearerTokenProvider = nil
        socketEventsDisposable?.dispose()
        socketEventsDisposable = nil
        let s = session
        let deviceId = currentUser?.username ?? ""
        account.socket.disconnect()
        if let s = s {
            Task { try? await engine.auth.sessionLogout(session: s, deviceId: deviceId, platform: "ios") }
        }
        engine.friendsData.resetForLogout()
        engine.clanData.resetForLogout()
        rolePermissions.resetForLogout()
        SessionStore.clear()
        MandatoryUsernamePendingStore.clearPending()
        MmnWalletStore.shared.clear()
        SessionRefreshManager.shared.reset()
        account.network.resetProtoBaseURLToDefault()
        session = nil
        currentUser = nil
        SentryLogger.setUser(username: nil)
        NotificationCenter.default.post(name: .mezonAccountCurrentUserDidChange, object: nil)
        currentClanId = 0
        currentChannel = nil
        account.postbox.clearAllSync()
        ImageCache.shared.purgeAccountScopedCaches()
        EmbedFormState.shared.removeAll()
        UserDefaults.standard.removeObject(forKey: "mezon_selectedClanId")
        UserDefaults.standard.removeObject(forKey: "mezon_otp_cooldown_cache_email")
        UserDefaults.standard.removeObject(forKey: "mezon_otp_cooldown_cache_phone")
        AnonymousMessageStore.removeAllClanToggles()

        UserDefaults(suiteName: "group.mezon.mobile")?.set(0, forKey: "badgeCount")
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }

        setLoggedIn(false)
        hasCompletedInitialSetup = false
    }

    private var fcmRegistrationTask: Task<Void, Never>?
    private var lastRegisteredFcmKey: String?

    func registerFCMDeviceTokenIfNeededExternally() {
        registerFCMTokenIfNeeded()
    }

    private func registerFCMTokenIfNeeded() {
        guard !VoIPMinimalCallBootstrap.isMinimalChromeActive else { return }
        if let existing = fcmRegistrationTask, !existing.isCancelled { return }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        fcmRegistrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.fcmRegistrationTask = nil }
            guard let authToken = await self.getToken() else { return }
            let voipToken = CallKitManager.shared.voipToken ?? ""
            let fcmToken: String
            if let cached = Messaging.messaging().fcmToken, !cached.isEmpty {
                fcmToken = cached
            } else {
                do {
                    fcmToken = try await Messaging.messaging().token()
                } catch {
                    return
                }
            }
            guard !fcmToken.isEmpty else { return }
            let key = "\(fcmToken)|\(voipToken)|\(deviceId)|\(authToken)"
            if key == self.lastRegisteredFcmKey { return }
            do {
                _ = try await self.account.network.registFcmDeviceToken(
                    fcmToken: fcmToken, deviceId: deviceId, platform: "ios", voipToken: voipToken, authToken: authToken
                )
                self.lastRegisteredFcmKey = key
            } catch {
            }
        }
    }

    func refreshSession() async throws {
        guard let current = session else {
            throw SessionError.noSession
        }
        let startEpoch = sessionEpoch
        let new = try await engine.auth.sessionRefresh(session: current)
        guard isStillCurrentSession(epoch: startEpoch) else {
            throw CancellationError()
        }
        let merged = mergeIdToken(into: new, previous: current)
        applySession(merged, user: currentUser, connectSocket: false, fetchAccount: false)
    }

    private func tokenForSocketReconnect() async throws -> String {
        if let session,
           !session.token.isEmpty,
           !session.isExpired {
            return session.token
        }
        try await refreshSession()
        guard let token = session?.token, !token.isEmpty else {
            throw SessionError.noSession
        }
        return token
    }

    private func recoverBearerTokenAfterUnauthorized(failedToken: String, statusCode: Int) async -> String? {
        if let session,
           !session.token.isEmpty,
           session.token != failedToken,
           !session.isExpired {
            return session.token
        }

        if let inflight = activeBearerRecoveryTask {
            return await inflight.value
        }

        let task = Task<String?, Never> { @MainActor in
            defer {
                self.activeBearerRecoveryTask = nil
            }

            if let session = self.session,
               !session.token.isEmpty,
               session.token != failedToken,
               !session.isExpired {
                return session.token
            }

            do {
                try await self.refreshSession()
                guard let refreshed = self.session,
                      !refreshed.token.isEmpty,
                      refreshed.token != failedToken else {
                    return nil
                }
                return refreshed.token
            } catch is SessionError {
                self.notifySessionExpiredAndStopRecovery()
                return nil
            } catch {
                return nil
            }
        }

        activeBearerRecoveryTask = task
        return await task.value
    }

    @discardableResult
    private func stopSessionRecovery() -> Bool {
        guard !didNotifySessionExpired else {
            return false
        }
        didNotifySessionExpired = true
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeBearerRecoveryTask?.cancel()
        activeBearerRecoveryTask = nil
        account.network.bearerUnauthorizedRecovery = nil
        account.network.bearerTokenProvider = nil
        account.socket.disconnect()
        SessionRefreshManager.shared.reset()
        return true
    }

    private func notifySessionExpiredAndStopRecovery() {
        guard stopSessionRecovery() else { return }
        NotificationCenter.default.post(name: Notification.Name("MezonSessionExpired"), object: nil)
    }

    private func mergeIdToken(into newSession: MezonSession, previous: MezonSession?) -> MezonSession {
        let merged = previous.map { newSession.mergedPreservingLocalCredentials(from: $0) } ?? newSession
        return SessionStore.applyIdTokenFallback(merged)
    }

    private var lastRecoverTime: Date?
    private let recoverThrottle: TimeInterval = 5
    private let maxForegroundRecoverRetries = 3

    func recoverFromForeground() {
        guard hasCompletedInitialSetup, session != nil, isLoggedIn else {
            return
        }
        let now = Date()
        if let last = lastRecoverTime, now.timeIntervalSince(last) < recoverThrottle {
            return
        }
        lastRecoverTime = now

        engine.friendsData.scheduleRefreshFromSocket()

        let needsRefresh = session?.isExpired ?? true

        if needsRefresh {
            let task = Task<Bool, Never> { @MainActor in
                defer {
                    self.activeRefreshTask = nil
                }
                let refreshed = await self.refreshSessionWithRetry()
                if refreshed, let token = self.session?.token {
                    self.account.socket.connect(token: token, wsHostOverride: nil)
                }
                return refreshed
            }
            activeRefreshTask = task
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, let token = self.session?.token else { return }
                if self.account.socket.isConnected { return }
                self.account.socket.connect(token: token, wsHostOverride: nil)
            }
        }
    }


    private func refreshSessionWithRetry() async -> Bool {
        for attempt in 1...maxForegroundRecoverRetries {
            guard !Task.isCancelled else { return false }
            do {
                try await refreshSession()
                return true
            } catch is SessionError {
                notifySessionExpiredAndStopRecovery()
                return false
            } catch is CancellationError {
                return false
            } catch {
            }

            if attempt < maxForegroundRecoverRetries {
                let delay = UInt64(attempt) * 2_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        return false
    }

    @objc private func handleSessionExpired() {
        stopSessionRecovery()
        SessionExpiredModal.show(onLoginAgain: { [self] in self.logout() })
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
        applyCurrentUser(User(
            id: saved.userId ?? UUID().uuidString,
            username: saved.username ?? "me",
            displayName: saved.username ?? "Me",
            avatarURL: nil, status: .online, customStatus: nil, bio: nil
        ))
        applyCachedAccountIfAvailable()
        setLoggedIn(!saved.created)
        account.network.updateBaseURL(from: saved)

        let startEpoch = sessionEpoch
        SessionRefreshManager.shared.refreshOnAppLaunch(
            session: saved,
            onSuccess: { [weak self] newSession in
                guard let self else { return }
                guard self.isStillCurrentSession(epoch: startEpoch) else { return }
                let merged = self.mergeIdToken(into: newSession, previous: saved)
                self.applySession(merged, user: self.currentUser, connectSocket: !merged.created, fetchAccount: false)
                self.scheduleHeavyAccountBootstrapAfterYield(token: merged.token)
                if let s = self.session {
                    self.setLoggedIn(!s.created)
                }
                if !VoIPMinimalCallBootstrap.isMinimalChromeActive {
                    self.registerFCMTokenIfNeeded()
                }
                self.markSessionReady()
            },
            onExpired: { [weak self] in
                guard let self else { return }
                guard self.isStillCurrentSession(epoch: startEpoch) else { return }
                self.markSessionReady()
                SessionExpiredModal.show(onLoginAgain: { [self] in self.logout() })
            },
            onReady: { [weak self] in
                guard let self else { return }
                guard self.isStillCurrentSession(epoch: startEpoch) else { return }
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
        if let uid = session.userId, !uid.isEmpty {
            MmnWalletStore.shared.bind(userId: uid)
        }
        account.network.updateBaseURL(from: session)

        account.network.bearerUnauthorizedRecovery = { [weak self] failedToken, statusCode in
            guard let self else { return nil }
            return await self.recoverBearerTokenAfterUnauthorized(
                failedToken: failedToken,
                statusCode: statusCode
            )
        }

        account.network.bearerTokenProvider = { [weak self] in
            guard let self else { return nil }
            return await self.getToken()
        }

        if socketEventsDisposable == nil {
            socketEventsDisposable = account.socket.events().start(next: { [weak self] event in
                guard let self else { return }
                self.handleSocketEvent(event)
            })
        }

        if connectSocket {
            account.socket.tokenProvider = { [weak self] in
                guard let self else { throw SessionError.noSession }
                return try await self.tokenForSocketReconnect()
            }
            account.socket.sessionProvider = { [weak self] in
                self?.session
            }
            account.socket.connect(token: session.token, wsHostOverride: nil)
            if !session.token.isEmpty {
                hasCompletedInitialSetup = true
            }
        }
        if let user { applyCurrentUser(user) }

        guard fetchAccount else { return }
        scheduleHeavyAccountBootstrapAfterYield(token: session.token)
    }

    private func scheduleHeavyAccountBootstrapAfterYield(token: String) {
        guard !VoIPMinimalCallBootstrap.isMinimalChromeActive else { return }
        heavyAccountBootstrapTask?.cancel()
        heavyAccountBootstrapTask = Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            await performHeavyAccountBootstrap(token: token)
        }
    }

    private func performHeavyAccountBootstrap(token: String) async {
        let startEpoch = sessionEpoch
        do {
            let apiAccount = try await engine.auth.getAccount(token: token)
            guard isStillCurrentSession(epoch: startEpoch) else { return }
            if let data = try? apiAccount.serializedData() {
                account.postbox.setPreferenceData(key: PreferencesKeys.account, value: data)
            }
            applyCurrentUser(mapAccountToUser(apiAccount))
        } catch {
            guard isStillCurrentSession(epoch: startEpoch) else { return }
            applyCachedAccountIfAvailable()
        }
        guard isStillCurrentSession(epoch: startEpoch) else { return }
        fetchAllUserClansAndChannels(token: token)
    }

    func prepareForVoIPAnswerConnectivity() async -> Bool {
        let disk = SessionStore.load()
        let candidates = [session, disk].compactMap { $0 }
        guard let baseSession = candidates.first(where: { !$0.isExpired }) ?? candidates.first else {
            return false
        }
        if let s = session, !s.isExpired, account.socket.isConnected {
            markSessionReady()
            return true
        }
        if !baseSession.isExpired {
            account.network.updateBaseURL(from: baseSession)
            applySession(baseSession, user: currentUser, connectSocket: true, fetchAccount: false)
            markSessionReady()
            return true
        }
        account.network.updateBaseURL(from: baseSession)
        let refreshed: MezonSession
        do {
            refreshed = try await SessionRefreshManager.shared.refresh(session: baseSession)
        } catch {
            if baseSession.isExpired {
                return false
            }
            refreshed = baseSession
        }
        let merged = mergeIdToken(into: refreshed, previous: session ?? baseSession)
        applySession(merged, user: currentUser, connectSocket: true, fetchAccount: false)
        scheduleHeavyAccountBootstrapAfterYield(token: merged.token)
        markSessionReady()
        return true
    }

    private func fetchAllUserClansAndChannels(token: String) {
        let startEpoch = sessionEpoch
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let usersResult = self.account.network.listUserClansByUserId(token: token)
                async let channelsResult = self.account.network.listChannelByUserId(token: token)
                let (users, channels) = try await (usersResult, channelsResult)
                guard self.isStillCurrentSession(epoch: startEpoch) else { return }
                if let data = try? users.serializedData() {
                    self.account.postbox.setPreferenceData(key: PreferencesKeys.allUserClans, value: data)
                }
                if let data = try? channels.serializedData() {
                    self.account.postbox.setPreferenceData(key: PreferencesKeys.allChannelsByUser, value: data)
                }
                Task { [weak self] in
                    await self?.engine.prefetchMediaPanelCaches(token: token)
                }
            } catch {
            }
        }
    }

    private func joinDirectMessageClanOnSocketConnected() {
        joinDirectMessageSocketRoomOnSocketConnected()

        let cachedClanId: Int64
        if currentClanId != 0 {
            cachedClanId = currentClanId
        } else if let stored = UserDefaults.standard.object(forKey: "mezon_selectedClanId") as? Int {
            cachedClanId = Int64(stored)
        } else {
            cachedClanId = 0
        }
        if cachedClanId != 0 {
            currentClanId = cachedClanId
            Task { @MainActor [weak self] in
                guard let self else { return }
                await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: self, clanId: cachedClanId, force: true)
                self.account.socket.joinClanChat(clanId: cachedClanId)
            }
        }
    }

    private func joinDirectMessageSocketRoomOnSocketConnected() {
        account.socket.joinClanChat(clanId: 0)
    }

    private func rejoinCurrentChannel() {
        guard let channel = currentChannel else {
            return
        }
        let clanId = currentClanId
        Task { @MainActor [weak self] in
            guard let self else { return }
            await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: self, clanId: clanId, force: true)
            self.account.socket.joinClanChat(clanId: clanId)
            let channelType: Int32 = clanId == 0
                ? (channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue)
                : (channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue)
            let isPublic = clanId == 0
                ? false
                : (channel.parentID != 0 ? false : (channel.channelPrivate == 0))
            self.account.socket.joinChannel(
                clanId: clanId,
                channelId: channel.channelID,
                channelType: channelType,
                isPublic: isPublic
            )
        }
    }

    private func subscribeSocketRoomsForMergedChannel(_ channel: Mezon_Api_ChannelDescription) {
        guard account.socket.isConnected else { return }
        let clanId = channel.clanID
        guard clanId != 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: self, clanId: clanId)
            guard self.account.socket.isConnected else { return }
            self.account.socket.joinClanChat(clanId: clanId)
            let channelType: Int32 = channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue
            let isPublic = channel.parentID != 0 ? false : (channel.channelPrivate == 0)
            self.account.socket.joinChannel(
                clanId: clanId,
                channelId: channel.channelID,
                channelType: channelType,
                isPublic: isPublic
            )
            NotificationCenter.default.post(
                name: Notification.Name("MezonJoinedClanChatForBadges"),
                object: nil,
                userInfo: ["clanId": clanId]
            )
        }
    }

    private static func shouldIncrementDmBadgeForSocketMessage(
        _ message: Mezon_Api_ChannelMessage,
        channelId: Int64,
        currentUserId: String?,
        currentClanId: Int64
    ) -> Bool {
        let mode = message.mode
        let isDmOrGroup =
            mode == MezonConstants.ChannelStreamMode.dm.rawValue
            || mode == MezonConstants.ChannelStreamMode.group.rawValue
        guard isDmOrGroup else { return false }
        let code = message.code
        if code == 1 || code == 2 { return false }
        let senderId = message.senderID
        if let uid = currentUserId.flatMap({ Int64($0) }), uid == senderId { return false }
        if String(senderId) == currentUserId { return false }
        let visibleDmChannelId = ActiveChannelTracker.currentChannelId
        let viewingExactDmOrGroupThread = currentClanId == 0 && visibleDmChannelId == channelId
        guard !viewingExactDmOrGroupThread else { return false }
        return true
    }

    func refreshUserProfile() async {
        guard let token = session?.token else {
            applyCachedAccountIfAvailable()
            return
        }
        do {
            let apiAccount = try await engine.auth.getAccount(token: token)
            if let data = try? apiAccount.serializedData() {
                account.postbox.setPreferenceData(key: PreferencesKeys.account, value: data)
            }
            applyCurrentUser(mapAccountToUser(apiAccount))
        } catch {
            applyCachedAccountIfAvailable()
        }
    }

    func applyCachedAccountIfAvailable() {
        guard let data = account.postbox.getPreferenceData(key: PreferencesKeys.account),
              let api = try? Mezon_Api_Account(serializedData: data) else { return }
        applyCurrentUser(mapAccountToUser(api))
    }
    
    private func currentUserNumericId() -> Int64? {
        guard let id = currentUser?.id else { return nil }
        return Int64(id)
    }

    private func applyIncomingCustomStatusEvent(_ event: Mezon_Realtime_CustomStatusEvent) {
        guard let myId = currentUserNumericId(), event.userID == myId else { return }
        guard var u = currentUser else { return }
        let text = event.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            u.customStatus = nil
            u.customStatusTimeReset = nil
            u.customStatusNoClear = nil
        } else {
            u.customStatus = text
            u.customStatusTimeReset = event.timeReset
            u.customStatusNoClear = event.noClear
        }
        applyCurrentUser(u)
    }

    private func applyIncomingUserStatusEvent(_ event: Mezon_Realtime_UserStatusEvent) {
        guard let myId = currentUserNumericId(), event.userID == myId else { return }
        guard var u = currentUser else { return }
        let raw = event.customStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if let presence = User.knownPresenceStatus(fromApiString: raw) {
            u.status = presence
        } else {
            u.customStatus = raw
        }
        applyCurrentUser(u)
    }

    private func applyIncomingStatusPresenceEvent(_ event: Mezon_Realtime_StatusPresenceEvent) {
        guard let myId = currentUserNumericId(), var u = currentUser else { return }
        guard let presence = event.joins.first(where: { $0.userID == myId }) else { return }
        if presence.hasStatus {
            let raw = presence.status.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                u.status = User.presenceStatus(fromApiString: raw, onlineFallback: u.status == .online)
            }
        }
        let cust = presence.userStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cust.isEmpty {
            u.customStatus = cust
        }
        applyCurrentUser(u)
    }

    private func applySdTopicEvent(_ event: Mezon_Realtime_SdTopicEvent) {
        guard event.id != 0 else { return }
        let creatorId = event.userID != 0 ? event.userID : (Int64(currentUser?.id ?? "") ?? 0)
        let lastSent = event.hasLastSentMessage ? event.lastSentMessage : nil
        let topicContent = event.hasMessage ? event.message.content : ""
        let updateTime: UInt32 = {
            if let lastSent, lastSent.timestampSeconds != 0 { return lastSent.timestampSeconds }
            if event.hasMessage {
                if event.message.updateTimeSeconds != 0 { return event.message.updateTimeSeconds }
                if event.message.createTimeSeconds != 0 { return event.message.createTimeSeconds }
            }
            return UInt32(Date().timeIntervalSince1970)
        }()
        let topic = TopicRecord(
            id: event.id,
            channelID: event.channelID,
            clanID: event.clanID,
            creatorID: creatorId,
            lastSenderID: lastSent?.senderID ?? creatorId,
            content: topicContent,
            updateTimeSeconds: updateTime,
            lastSentMessageContent: lastSent?.content ?? ""
        )

        account.postbox.write { tx in
            if event.channelID != 0, event.messageID != 0 {
                tx.updateMessageTopicMetadata(
                    messageId: "\(event.messageID)",
                    channelId: "\(event.channelID)",
                    topicId: event.id,
                    creatorId: creatorId
                )
            }
            if event.clanID != 0 {
                var topics = tx.topicTable.getTopics(clanId: event.clanID)
                let resolvedTopic: TopicRecord
                if let existing = topics.first(where: { $0.id == topic.id }) {
                    let resolvedContent = existing.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? topic.content
                        : existing.content
                    resolvedTopic = TopicRecord(
                        id: existing.id,
                        channelID: existing.channelID,
                        clanID: existing.clanID,
                        creatorID: existing.creatorID,
                        lastSenderID: lastSent?.senderID ?? existing.lastSenderID,
                        senderAvatarURL: existing.senderAvatarURL,
                        senderDisplayName: existing.senderDisplayName,
                        content: resolvedContent,
                        updateTimeSeconds: updateTime,
                        lastSentMessageContent: lastSent?.content ?? existing.lastSentMessageContent
                    )
                } else {
                    resolvedTopic = topic
                }
                topics.removeAll { $0.id == resolvedTopic.id }
                topics.insert(resolvedTopic, at: 0)
                tx.updateTopics(topics, clanId: event.clanID)
            }
        }
    }

    private func applyTopicInMessageEvent(_ event: Mezon_Realtime_TopicInMessageEvent) {
        let topicId = Int64(event.tpID) ?? event.messageID
        guard topicId != 0 else { return }
        account.postbox.write { tx in
            tx.setTopicReplyCount(
                topicId: topicId,
                replyCount: Int(event.rpl),
                lastSentTimestamp: event.lsnt
            )
        }
    }

    private func handleSocketEvent(_ event: SocketEvent) {
        switch event {
        case .sessionRefreshed(let refreshed):
            guard let current = session else { return }
            let updated = current.applyingRefreshEvent(refreshed)
            session = updated
            SessionStore.save(updated)

        case .connected:
            let joinDelayNanos: UInt64 = 250_000_000
            let isMinimalChrome = VoIPMinimalCallBootstrap.isMinimalChromeActive
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: joinDelayNanos)
                guard let self, self.account.socket.isConnected else { return }
                if isMinimalChrome {
                    self.joinDirectMessageSocketRoomOnSocketConnected()
                } else {
                    self.joinDirectMessageClanOnSocketConnected()
                    self.rejoinCurrentChannel()
                }
            }

        case .typing(let e):
            NotificationCenter.default.post(
                name: .mezonMessageTypingReceived,
                object: nil,
                userInfo: [
                    "clanId": NSNumber(value: e.clanID),
                    "channelId": NSNumber(value: e.channelID),
                    "topicId": NSNumber(value: e.topicID),
                    "senderId": NSNumber(value: e.senderID),
                    "senderUsername": e.senderUsername,
                    "senderDisplayName": e.senderDisplayName,
                    "mode": NSNumber(value: e.mode)
                ]
            )

        case .messageReceived(let apiMessage):
            let channelId = Int64(apiMessage.channelID) ?? 0
            let clanId = Int64(apiMessage.clanID) ?? 0
            if apiMessage.code == 2 {
                account.postbox.write { tx in
                    tx.deleteMessage(id: "\(apiMessage.messageID)")
                    if apiMessage.topicID != 0 {
                        tx.updateTopicReplyCount(
                            parentChannelId: "\(apiMessage.channelID)",
                            topicId: apiMessage.topicID,
                            delta: -1
                        )
                    }
                }
                NotificationCenter.default.post(
                    name: Notification.Name("MezonChannelMessageDeleted"),
                    object: nil,
                    userInfo: ["channelId": channelId, "clanId": clanId]
                )
                return
            }

            if apiMessage.code == 12 {
                NotificationCenter.default.post(
                    name: Notification.Name("MezonNewMessageReceived"),
                    object: nil,
                    userInfo: [
                        "channelId": channelId,
                        "clanId": clanId,
                        "senderId": String(apiMessage.senderID),
                        "serializedChannelMessage": try? apiMessage.serializedData(),
                        "messageCode": Int64(apiMessage.code)
                    ] as [String: Any]
                )
                return
            }

            if apiMessage.code == 14 || apiMessage.code == 15 {
                NotificationCenter.default.post(
                    name: Notification.Name("MezonNewMessageReceived"),
                    object: nil,
                    userInfo: [
                        "channelId": channelId,
                        "clanId": clanId,
                        "senderId": String(apiMessage.senderID),
                        "serializedChannelMessage": try? apiMessage.serializedData(),
                        "messageCode": Int64(apiMessage.code)
                    ] as [String: Any]
                )
                return
            }

            
            let mid = "\(apiMessage.messageID)"
            let msgChannelId = apiMessage.topicID != 0 ? "topic-\(apiMessage.topicID)" : "\(apiMessage.channelID)"
            MessageEchoRegistry.shared.recordEcho(messageId: mid)
            let merged = account.postbox.read { tx in
                MessageRecord.fromApi(apiMessage, merging: tx.getMessageById(mid, channelId: msgChannelId))
            }
            let shouldIncrementTopicReplyCount = apiMessage.topicID != 0
                && apiMessage.code != 1
                && apiMessage.code != 2
                && apiMessage.code != 9
                && apiMessage.code != MezonConstants.MessageCode.updateEphemeral.rawValue
                && apiMessage.code != MezonConstants.MessageCode.deleteEphemeral.rawValue
            account.postbox.write { tx in
                tx.addMessages([merged])
                if shouldIncrementTopicReplyCount {
                    tx.updateTopicReplyCount(
                        parentChannelId: "\(apiMessage.channelID)",
                        topicId: apiMessage.topicID,
                        delta: 1
                    )
                }
            }
            
            if apiMessage.code == 1 {
                NotificationCenter.default.post(
                    name: Notification.Name("MezonNewMessageReceived"),
                    object: nil,
                    userInfo: [
                        "channelId": channelId,
                        "clanId": clanId,
                        "senderId": String(apiMessage.senderID),
                        "serializedChannelMessage": try? apiMessage.serializedData(),
                        "messageCode": Int64(apiMessage.code)
                    ] as [String: Any]
                )
                return
            }
            
            let messageCopy = apiMessage
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isSelf = String(messageCopy.senderID) == self.currentUser?.id
                if isSelf {
                    let now = UInt32(Date().timeIntervalSince1970)
                    NotificationCenter.default.post(
                        name: Notification.Name("MezonChannelMarkedAsRead"), object: nil,
                        userInfo: [
                            "channelId": channelId, "clanId": clanId,
                            "messageId": String(messageCopy.messageID),
                            "timestampSeconds": now, "fromSelf": true
                        ] as [String: Any]
                    )
                    let isDmListMessage = clanId == 0
                        && (messageCopy.mode == MezonConstants.ChannelStreamMode.dm.rawValue
                            || messageCopy.mode == MezonConstants.ChannelStreamMode.group.rawValue)
                    guard isDmListMessage else { return }
                }
                let incrementDmBadge = !isSelf && Self.shouldIncrementDmBadgeForSocketMessage(
                    messageCopy, channelId: channelId,
                    currentUserId: self.currentUser?.id, currentClanId: self.currentClanId
                )
                var userInfo: [String: Any] = [
                    "channelId": channelId, "clanId": clanId,
                    "senderId": String(messageCopy.senderID), "mode": messageCopy.mode,
                    "timestampSeconds": messageCopy.createTimeSeconds,
                    "messageCode": messageCopy.code,
                    "incrementDmBadge": incrementDmBadge, "topicId": messageCopy.topicID
                ]
                if let raw = try? messageCopy.serializedData() {
                    userInfo["serializedChannelMessage"] = raw
                }
                let notificationName = isSelf
                    ? Notification.Name("MezonDMListMessageReceived")
                    : Notification.Name("MezonNewMessageReceived")
                NotificationCenter.default.post(
                    name: notificationName, object: nil, userInfo: userInfo
                )
            }

        case .messageUpdated(let update):
            let mid = "\(update.messageID)"
            account.postbox.write { tx in
                guard let existing = tx.getMessageById(mid) else { return }
                let incomingContent = update.content.data(using: .utf8) ?? Data()
                let newContentData = PresignFinishContent.mergePresignFinishContent(
                    local: existing.content,
                    server: incomingContent
                )
                let contentChanged = !newContentData.isEmpty && newContentData != existing.content
                let attachmentsChanged = !update.attachments.isEmpty
                guard contentChanged || attachmentsChanged else { return }
                let newAttachmentsJSON: Data = {
                    guard !update.attachments.isEmpty else { return existing.attachmentsJSON }
                    var list = Mezon_Api_MessageAttachmentList()
                    list.attachments = update.attachments
                    return (try? list.serializedData()) ?? existing.attachmentsJSON
                }()
                let hideEdit = update.hideEditted
                    || (contentChanged
                        && PresignFinishContent.isPresignFinishOnlyChange(
                            newContent: newContentData,
                            oldContent: existing.content
                        ))
                let updated = MessageRecord(
                    id: existing.id,
                    channelId: existing.channelId,
                    clanId: existing.clanId,
                    senderId: existing.senderId,
                    content: contentChanged ? newContentData : existing.content,
                    createdAt: existing.createdAt,
                    editedAt: hideEdit ? nil : Date(),
                    isDeleted: existing.isDeleted,
                    code: existing.code,
                    senderDisplayName: existing.senderDisplayName,
                    senderAvatarURL: existing.senderAvatarURL,
                    sendingState: existing.sendingState,
                    attachmentsJSON: newAttachmentsJSON,
                    reactionsJSON: existing.reactionsJSON,
                    referencesData: existing.referencesData,
                    mentionsJSON: existing.mentionsJSON
                )
                tx.addMessages([updated])
            }

        case .reaction(let reaction):
            account.postbox.write { tx in tx.updateMessageReactions(messageId: "\(reaction.messageID)", reaction: reaction) }

        case .messageRemoved(let removed):
            account.postbox.write { tx in tx.deleteMessage(id: "\(removed.messageID)") }
            NotificationCenter.default.post(
                name: Notification.Name("MezonChannelMessageDeleted"),
                object: nil,
                userInfo: ["channelId": removed.channelID, "clanId": removed.clanID]
            )

        case .lastSeen(let e):
            NotificationCenter.default.post(
                name: Notification.Name("MezonChannelMarkedAsRead"), object: nil,
                userInfo: [
                    "channelId": e.channelID, "clanId": e.clanID,
                    "channelUnreadCount": e.badgeCount,
                    "messageId": String(e.messageID),
                    "timestampSeconds": e.timestampSeconds,
                    "mode": e.mode,
                ] as [String: Any]
            )

        case .voiceJoined(let ev):
            engine.clanData.applyVoiceJoined(clanId: ev.clanID, channelId: ev.voiceChannelID, userId: ev.userID)

        case .voiceLeaved(let ev):
            engine.clanData.applyVoiceLeaved(clanId: ev.clanID, channelId: ev.voiceChannelID, userId: ev.voiceUserID)

        case .streamingJoined(let ev):
            engine.clanData.applyStreamJoined(
                clanId: ev.clanID,
                channelId: ev.streamingChannelID,
                userId: ev.userID,
                entryId: ev.id,
                participant: ev.participant
            )

        case .streamingLeaved(let ev):
            engine.clanData.applyStreamLeaved(clanId: ev.clanID, entryId: ev.streamingUserID)

        case .voiceEnded(let ev):
            let cid = Int64(ev.voiceChannelID) ?? 0
            guard cid != 0 else { return }
            engine.clanData.applyVoiceEnded(clanId: ev.clanID, channelId: cid)

        case .sdTopicEvent(let event):
            applySdTopicEvent(event)

        case .topicInMessage(let event):
            applyTopicInMessageEvent(event)

        case .notification(let noti):
            handleSocketNotification(noti)

        case .webRTC(let msg):
            WebRTCCallManager.shared.handleSignalingMessage(msg, currentUserId: currentUserNumericId() ?? 0)

        case .incomingCallPush(let push):
            WebRTCCallManager.shared.handleIncomingCallPush(push, currentUserId: currentUserNumericId() ?? 0)

        case .customStatus(let e):
            applyIncomingCustomStatusEvent(e)

        case .userStatus(let e):
            applyIncomingUserStatusEvent(e)

        case .statusPresence(let e):
            applyIncomingStatusPresenceEvent(e)

        case .lastPin(let e):
            ChannelPinnedStatePersistence.applyPinMessage(
                postbox: account.postbox,
                accountId: account.id,
                clanId: e.clanID,
                channelId: e.channelID,
                messageId: e.messageID
            )
            NotificationCenter.default.post(
                name: .mezonChannelPinsNeedRefresh,
                object: nil,
                userInfo: [
                    "clanId": NSNumber(value: e.clanID),
                    "channelId": NSNumber(value: e.channelID),
                    "pinnedMessageId": NSNumber(value: e.messageID),
                ]
            )

        case .unpinMessage(let e):
            ChannelPinnedStatePersistence.applyUnpinMessage(
                postbox: account.postbox,
                accountId: account.id,
                clanId: e.clanID,
                channelId: e.channelID,
                messageId: e.messageID
            )
            NotificationCenter.default.post(
                name: .mezonChannelPinsNeedRefresh,
                object: nil,
                userInfo: [
                    "clanId": NSNumber(value: e.clanID),
                    "channelId": NSNumber(value: e.channelID),
                    "unpinnedMessageId": NSNumber(value: e.messageID),
                ]
            )

        case .channelCreated(let ev):
            var ch = Mezon_Api_ChannelDescription()
            ch.clanID = ev.clanID
            ch.categoryID = ev.categoryID
            ch.creatorID = ev.creatorID
            ch.parentID = ev.parentID
            ch.channelID = ev.channelID
            ch.channelLabel = ev.channelLabel
            ch.channelPrivate = ev.channelPrivate
            ch.type = ev.channelType
            ch.appID = ev.appID
            ch.clanName = ev.clanName
            ch.channelAvatar = ev.channelAvatar
            ch.active = 1
            engine.clanData.applyLocallyCreatedChannel(ch)

        case .channelDeleted(let ev):
            NotificationCenter.default.post(
                name: .mezonChannelDeletedLocally,
                object: nil,
                userInfo: ["clanId": ev.clanID, "channelId": ev.channelID]
            )

        case .userChannelAdded(let ev):
            guard let myId = currentUserNumericId() else { break }
            if let desc = engine.clanData.applyUserChannelAddedFromSocket(ev, currentUserNumericId: myId) {
                subscribeSocketRoomsForMergedChannel(desc)
            }
            engine.clanData.applyClanMembersFromUserChannelAddedForObservers(
                ev,
                observingClanId: currentClanId
            )

        case .userClanAdded(let ev):
            engine.clanData.applyClanUserAddedFromSocket(ev)

        case .userClanRemoved(let ev):
            engine.clanData.applyClanUserRemovedFromSocket(ev)

        case .clanUpdated(let ev):
            account.postbox.write { tx in
                guard let existingClan = tx.getClan(id: ev.clanID) else { return }
                var d = (try? Mezon_Api_ClanDesc(serializedBytes: existingClan.data)) ?? Mezon_Api_ClanDesc()
                d.clanID = ev.clanID
                if !ev.clanName.isEmpty { d.clanName = ev.clanName }
                d.logo = ev.logo
                d.banner = ev.banner
                d.status = ev.status
                d.isOnboarding = ev.isOnboarding
                d.welcomeChannelID = ev.welcomeChannelID
                if !ev.onboardingBanner.isEmpty { d.onboardingBanner = ev.onboardingBanner }
                if !ev.communityBanner.isEmpty { d.communityBanner = ev.communityBanner }
                d.isCommunity = ev.isCommunity
                if !ev.about.isEmpty { d.about = ev.about }
                if !ev.description_p.isEmpty { d.description_p = ev.description_p }
                d.preventAnonymous = ev.preventAnonymous

                let updatedClan = ClanRecord(
                    id: existingClan.id,
                    name: ev.clanName.isEmpty ? existingClan.name : ev.clanName,
                    icon: ev.logo,
                    ownerId: existingClan.ownerId,
                    data: (try? d.serializedData()) ?? existingClan.data
                )
                tx.updateClans([updatedClan])
            }
            NotificationCenter.default.post(name: Notification.Name("MezonClanDescUpdated"), object: nil, userInfo: ["clanId": ev.clanID])

        case .channelUpdated(let ev):
            guard ev.clanID != 0, ev.channelID != 0 else { break }
            let clanId = ev.clanID
            let channelId = ev.channelID
            let newName = ev.channelLabel.isEmpty ? nil : ev.channelLabel
            let newTopic = ev.topic.isEmpty ? nil : ev.topic   
            let newCategoryId: Int64? = ev.categoryID != 0 ? ev.categoryID : nil
            var newCategoryName: String? = nil
            if let catId = newCategoryId,
               let blob = account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)),
               !blob.isEmpty {
                let arr = ChannelPreferenceListCodec.decode(blob)
                if let existing = arr.first(where: { $0.categoryID == catId && !$0.categoryName.isEmpty }) {
                    newCategoryName = existing.categoryName
                }
            }
            
            account.postbox.write { tx in
                tx.updateChannelDescription(
                    clanId: clanId,
                    channelId: channelId,
                    name: newName,
                    topic: newTopic,   
                    categoryId: newCategoryId,
                    categoryName: newCategoryName
                )
            }
            
            if let blob = account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)),
               !blob.isEmpty {
                var arr = ChannelPreferenceListCodec.decode(blob)
                if let idx = arr.firstIndex(where: { $0.channelID == channelId }) {
                    if let newName { arr[idx].channelLabel = newName }
                    if let newTopic { arr[idx].topic = newTopic }  
                    if let catId = newCategoryId { 
                        arr[idx].categoryID = catId 
                        if let catName = newCategoryName {
                            arr[idx].categoryName = catName
                        } else if catId == 0 {
                            arr[idx].categoryName = ""
                        }
                    }
                    if let data = ChannelPreferenceListCodec.encode(arr) {
                        account.postbox.setPreferenceDataSync(
                            key: PreferencesKeys.channelList(clanId: clanId), value: data)
                    }
                }
            }
            NotificationCenter.default.post(
                name: .mezonChannelDescriptionDidUpdate,
                object: nil,
                userInfo: ["clanId": clanId, "channelId": channelId]
            )

        case .notiUserChannel(let m):
            let record = NotificationSettingRecord(from: m)
            account.postbox.write { tx in
                tx.updateNotificationSetting(record)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .mezonNotificationSettingDidUpdate,
                    object: nil,
                    userInfo: ["channelId": m.channelID, "record": record]
                )
            }

        case .stickerCreated, .stickerUpdated, .stickerDeleted:
            engine.handleStickerEvent(event)

        case .emojiEvent(let ev):
            engine.handleEmojiEvent(ev)

        default:
            break
        }
    }

    private static func notificationSuggestsFriendRelation(_ noti: Mezon_Api_Notification) -> Bool {
        var haystacks: [String] = [noti.subject]
        if let contentText = String(data: noti.content, encoding: .utf8) {
            haystacks.append(contentText)
        }
        let needles = [
            "friend_request", "friend-request", "friend request",
            "add_friend", "add-friend", "add friend", "addfriend", "request_friend",
            "sent you a friend request", "add you as a friend",
            "wants to add you", "wants to be your friend",
            "loi moi ket ban", "muon ket ban", "ket ban"
        ]
        for haystack in haystacks {
            let normalized = haystack
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            guard !normalized.isEmpty else { continue }
            if needles.contains(where: { normalized.contains($0) }) { return true }
        }
        return false
    }

    private func handleSocketNotification(_ noti: Mezon_Api_Notification) {
        if noti.code == -3 { 
            var senderName = ""
            if !noti.content.isEmpty {
                let firstByte = noti.content.first ?? 0
                if firstByte == 123 || firstByte == 91 {
                    if let obj = try? JSONSerialization.jsonObject(with: noti.content) as? [String: Any] {
                        let dn = obj["display_name"] as? String ?? ""
                        senderName = dn.isEmpty ? (obj["username"] as? String ?? "") : dn
                    }
                } else {
                    if let fcm = try? Mezon_Api_DirectFcmProto(serializedBytes: noti.content) {
                        senderName = fcm.displayName.isEmpty ? fcm.username : fcm.displayName
                    }
                }
            }
            if senderName.isEmpty {
                senderName = engine.account.postbox.read { tx in tx.getProfile(userId: String(noti.senderID))?.displayName } ?? "Someone"
            }
            let message = String(format: L(L10n.FriendRequest.toastAcceptSuccess), senderName)
            Toast.success(message)
            engine.friendsData.scheduleRefreshFromSocket()
            return
        }

        if noti.channelID == 0, Self.notificationSuggestsFriendRelation(noti) {
            engine.friendsData.scheduleRefreshFromSocket()
            return
        }

        guard noti.channelID != 0 else { return }
        if currentChannel?.channelID == noti.channelID, noti.clanID != 0 { return }

        let skipTypes: [Int32] = [
            MezonConstants.ChannelType.app.rawValue,
            MezonConstants.ChannelType.mezonVoice.rawValue
        ]
        guard !skipTypes.contains(noti.channelType) else { return }

        let notificationCodeMentioned: Int32 = -9
        let notificationCodeReplied: Int32 = -11
        guard noti.code == notificationCodeMentioned || noti.code == notificationCodeReplied else { return }

        var messageId: String = ""
        if !noti.content.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: noti.content) as? [String: Any] {
            for key in ["message_id", "messageId", "messageID", "msg_id", "id"] {
                if let v = json[key], !(v is NSNull) {
                    let s = "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty, s != "0" {
                        messageId = s
                        break
                    }
                }
            }
        }

        let clanId = noti.clanID
        let channelId = noti.channelID
        let topicId = noti.topicID

        if noti.topicID != 0 {
            NotificationCenter.default.post(
                name: Notification.Name("MezonMentionReceived"), object: nil,
                userInfo: [
                    "channelId": topicId, "clanId": clanId,
                    "senderId": String(noti.senderID), "mode": noti.channelType,
                    "timestampSeconds": noti.createTimeSeconds,
                    "messageId": messageId, "topicId": topicId
                ] as [String: Any]
            )
            NotificationCenter.default.post(
                name: Notification.Name("MezonMentionReceived"), object: nil,
                userInfo: [
                    "channelId": channelId, "clanId": clanId,
                    "senderId": String(noti.senderID), "mode": noti.channelType,
                    "timestampSeconds": noti.createTimeSeconds,
                    "messageId": messageId, "topicId": topicId,
                    "isParentOfTopic": true
                ] as [String: Any]
            )
        } else {
            NotificationCenter.default.post(
                name: Notification.Name("MezonMentionReceived"), object: nil,
                userInfo: [
                    "channelId": channelId, "clanId": clanId,
                    "senderId": String(noti.senderID), "mode": noti.channelType,
                    "timestampSeconds": noti.createTimeSeconds,
                    "messageId": messageId
                ] as [String: Any]
            )
        }
    }

    private func mapAccountToUser(_ api: Mezon_Api_Account) -> User {
        let u = api.user
        let presence = User.presenceStatus(fromApiString: u.status, onlineFallback: u.online)
        let newCustom = u.userStatus.isEmpty ? nil : u.userStatus
        let prev = currentUser
        let newTrim = newCustom?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prevTrim = prev?.customStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sameCustomText: Bool = {
            guard let nt = newTrim, !nt.isEmpty else { return false }
            return nt == prevTrim
        }()
        let trimmedLogo = api.logo.trimmingCharacters(in: .whitespacesAndNewlines)
        return User(
            id: "\(u.id)",
            username: u.username.isEmpty ? "me" : u.username,
            displayName: u.displayName.isEmpty ? u.username : u.displayName,
            avatarURL: u.avatarURL.isEmpty ? nil : URL(string: u.avatarURL),
            accountLogoURL: trimmedLogo.isEmpty ? nil : trimmedLogo,
            status: presence,
            customStatus: newCustom,
            customStatusTimeReset: newCustom == nil ? nil : (sameCustomText ? prev?.customStatusTimeReset : nil),
            customStatusNoClear: newCustom == nil ? nil : (sameCustomText ? prev?.customStatusNoClear : nil),
            bio: u.aboutMe.isEmpty ? nil : u.aboutMe,
            email: api.email.isEmpty ? nil : api.email,
            phoneNumber: u.phoneNumber.isEmpty ? nil : u.phoneNumber,
            isBot: false,
            createTimeSeconds: u.createTimeSeconds
        )
    }
}
