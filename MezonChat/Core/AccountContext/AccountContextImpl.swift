import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging
import SwiftProtobuf

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
    private var lastRecoveryIssuedToken: String?
    private var lastRecoveryIssuedRefreshToken: String?
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
            SessionRefreshDebugLog.log("account.ensureRefreshed join-active")
            return await inflight.value
        }
        SessionRefreshDebugLog.log("account.ensureRefreshed start session=\(SessionRefreshDebugLog.session(session))")
        let task = Task<Bool, Never> { @MainActor in
            defer {
                SessionRefreshDebugLog.log("account.ensureRefreshed clear-active")
                self.activeRefreshTask = nil
            }
            for attempt in 1...2 {
                do {
                    SessionRefreshDebugLog.log("account.ensureRefreshed attempt=\(attempt)")
                    try await self.refreshSession()
                    SessionRefreshDebugLog.log("account.ensureRefreshed success attempt=\(attempt)")
                    return true
                } catch {
                    SessionRefreshDebugLog.log("account.ensureRefreshed fail attempt=\(attempt) error=\(SessionRefreshDebugLog.error(error))")
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
            SessionRefreshDebugLog.log("account.ensureRefreshed exhausted")
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
        SessionRefreshDebugLog.log("account.login epoch=\(startEpoch) session=\(SessionRefreshDebugLog.session(session))")
        didNotifySessionExpired = false
        lastRecoveryIssuedToken = nil
        lastRecoveryIssuedRefreshToken = nil
        VoIPAnswerAccountBridge.context = self
        applySession(session, user: user, connectSocket: false)
        setLoggedIn(true)
        hasCompletedInitialSetup = true
        lastRecoverTime = Date()
        markSessionReady()
        rolePermissions.start()

        Task { @MainActor in
            do {
                SessionRefreshDebugLog.log("account.login bootstrap-refresh start epoch=\(startEpoch)")
                try await refreshSession()
                SessionRefreshDebugLog.log("account.login bootstrap-refresh success epoch=\(startEpoch) session=\(SessionRefreshDebugLog.session(self.session))")
            } catch {
                SessionRefreshDebugLog.log("account.login bootstrap-refresh fail epoch=\(startEpoch) error=\(SessionRefreshDebugLog.error(error))")
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
        SessionRefreshDebugLog.log("account.replaceCurrentSession session=\(SessionRefreshDebugLog.session(session))")
        didNotifySessionExpired = false
        lastRecoveryIssuedToken = nil
        lastRecoveryIssuedRefreshToken = nil
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
        SessionRefreshDebugLog.log("account.logout epoch=\(sessionEpoch) session=\(SessionRefreshDebugLog.session(session))")
        heavyAccountBootstrapTask?.cancel()
        heavyAccountBootstrapTask = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeBearerRecoveryTask?.cancel()
        activeBearerRecoveryTask = nil
        didNotifySessionExpired = false
        lastRecoveryIssuedToken = nil
        lastRecoveryIssuedRefreshToken = nil
        fcmRegistrationTask?.cancel()
        fcmRegistrationTask = nil
        if VoIPAnswerAccountBridge.context === self {
            VoIPAnswerAccountBridge.context = nil
        }
        SessionExpiredModal.removeOverlayIfPresented()
        account.network.bearerUnauthorizedRecovery = nil
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
            guard let apnsTokenData = Messaging.messaging().apnsToken, !apnsTokenData.isEmpty else { return }
            let apnsToken = apnsTokenData.map { String(format: "%02.2hhx", $0) }.joined()
            do {
                _ = try await self.account.network.registFcmDeviceToken(
                    fcmToken: apnsToken, deviceId: deviceId, platform: "ios", voipToken: voipToken, authToken: authToken
                )
            } catch {
            }
        }
    }

    func refreshSession() async throws {
        guard let current = session else {
            SessionRefreshDebugLog.log("account.refreshSession stop noSession")
            throw SessionError.noSession
        }
        SessionRefreshDebugLog.log("account.refreshSession start current=\(SessionRefreshDebugLog.session(current))")
        do {
            let new = try await engine.auth.sessionRefresh(session: current)
            let merged = mergeIdToken(into: new, previous: current)
            SessionRefreshDebugLog.log("account.refreshSession success merged=\(SessionRefreshDebugLog.session(merged))")
            applySession(merged, user: currentUser, connectSocket: false, fetchAccount: false)
        } catch {
            SessionRefreshDebugLog.log("account.refreshSession fail error=\(SessionRefreshDebugLog.error(error))")
            throw error
        }
    }

    private func tokenForSocketReconnect() async throws -> String {
        if let session,
           !session.token.isEmpty,
           !session.isExpired {
            SessionRefreshDebugLog.log("account.socketToken cached session=\(SessionRefreshDebugLog.session(session))")
            return session.token
        }
        SessionRefreshDebugLog.log("account.socketToken refresh-needed session=\(SessionRefreshDebugLog.session(session))")
        try await refreshSession()
        guard let token = session?.token, !token.isEmpty else {
            SessionRefreshDebugLog.log("account.socketToken stop noSessionAfterRefresh")
            throw SessionError.noSession
        }
        SessionRefreshDebugLog.log("account.socketToken refreshed token=\(SessionRefreshDebugLog.token(token))")
        return token
    }

    private func recoverBearerTokenAfterUnauthorized(failedToken: String, statusCode: Int) async -> String? {
        SessionRefreshDebugLog.log("account.bearerRecovery start status=\(statusCode) failed=\(SessionRefreshDebugLog.token(failedToken)) session=\(SessionRefreshDebugLog.session(session))")
        if let session,
           !session.token.isEmpty,
           session.token != failedToken,
           !session.isExpired {
            SessionRefreshDebugLog.log("account.bearerRecovery use-current current=\(SessionRefreshDebugLog.token(session.token))")
            return session.token
        }

        if let session,
           !session.isExpired,
           failedToken == lastRecoveryIssuedToken,
           session.refreshToken == lastRecoveryIssuedRefreshToken {
            SessionRefreshDebugLog.log("account.bearerRecovery stop refreshed-token-rejected failed=\(SessionRefreshDebugLog.token(failedToken))")
            notifySessionExpiredAndStopRecovery()
            return nil
        }

        if let inflight = activeBearerRecoveryTask {
            SessionRefreshDebugLog.log("account.bearerRecovery join-active")
            return await inflight.value
        }

        let task = Task<String?, Never> { @MainActor in
            defer {
                SessionRefreshDebugLog.log("account.bearerRecovery clear-active")
                self.activeBearerRecoveryTask = nil
            }

            if let session = self.session,
               !session.token.isEmpty,
               session.token != failedToken,
               !session.isExpired {
                SessionRefreshDebugLog.log("account.bearerRecovery task-use-current current=\(SessionRefreshDebugLog.token(session.token))")
                return session.token
            }

            do {
                SessionRefreshDebugLog.log("account.bearerRecovery task-refresh start")
                try await self.refreshSession()
                guard let refreshed = self.session,
                      !refreshed.token.isEmpty,
                      refreshed.token != failedToken else {
                    SessionRefreshDebugLog.log("account.bearerRecovery task-refresh stop invalidResult session=\(SessionRefreshDebugLog.session(self.session))")
                    self.notifySessionExpiredAndStopRecovery()
                    return nil
                }
                self.lastRecoveryIssuedToken = refreshed.token
                self.lastRecoveryIssuedRefreshToken = refreshed.refreshToken
                SessionRefreshDebugLog.log("account.bearerRecovery task-refresh success session=\(SessionRefreshDebugLog.session(refreshed))")
                return refreshed.token
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, code == 401 || code == 403 {
                    SessionRefreshDebugLog.log("account.bearerRecovery task-refresh authFail error=\(SessionRefreshDebugLog.error(error))")
                    self.notifySessionExpiredAndStopRecovery()
                } else {
                    SessionRefreshDebugLog.log("account.bearerRecovery task-refresh mezonFail error=\(SessionRefreshDebugLog.error(error))")
                }
                return nil
            } catch is SessionError {
                SessionRefreshDebugLog.log("account.bearerRecovery task-refresh sessionError")
                self.notifySessionExpiredAndStopRecovery()
                return nil
            } catch {
                SessionRefreshDebugLog.log("account.bearerRecovery task-refresh fail error=\(SessionRefreshDebugLog.error(error))")
                return nil
            }
        }

        activeBearerRecoveryTask = task
        return await task.value
    }

    @discardableResult
    private func stopSessionRecovery() -> Bool {
        guard !didNotifySessionExpired else {
            SessionRefreshDebugLog.log("account.stopRecovery ignored alreadyNotified")
            return false
        }
        SessionRefreshDebugLog.log("account.stopRecovery session=\(SessionRefreshDebugLog.session(session))")
        didNotifySessionExpired = true
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeBearerRecoveryTask?.cancel()
        activeBearerRecoveryTask = nil
        account.network.bearerUnauthorizedRecovery = nil
        account.socket.disconnect()
        SessionRefreshManager.shared.reset()
        return true
    }

    private func notifySessionExpiredAndStopRecovery() {
        guard stopSessionRecovery() else { return }
        SessionRefreshDebugLog.log("account.notifySessionExpired post")
        NotificationCenter.default.post(name: Notification.Name("MezonSessionExpired"), object: nil)
    }

    private func mergeIdToken(into newSession: MezonSession, previous: MezonSession?) -> MezonSession {
        let merged = previous.map { newSession.mergedPreservingIdToken(from: $0) } ?? newSession
        return SessionStore.applyIdTokenFallback(merged)
    }

    private var lastRecoverTime: Date?
    private let recoverThrottle: TimeInterval = 5
    private let maxForegroundRecoverRetries = 3

    func recoverFromForeground() {
        guard hasCompletedInitialSetup, session != nil, isLoggedIn else {
            SessionRefreshDebugLog.log("account.foregroundRecover skip setup=\(hasCompletedInitialSetup) hasSession=\(session != nil) loggedIn=\(isLoggedIn)")
            return
        }
        let now = Date()
        if let last = lastRecoverTime, now.timeIntervalSince(last) < recoverThrottle {
            SessionRefreshDebugLog.log("account.foregroundRecover throttle elapsed=\(String(format: "%.2f", now.timeIntervalSince(last)))")
            return
        }
        lastRecoverTime = now

        let needsRefresh = session?.isExpired ?? true
        SessionRefreshDebugLog.log("account.foregroundRecover start needsRefresh=\(needsRefresh) session=\(SessionRefreshDebugLog.session(session))")

        if needsRefresh {
            let task = Task<Bool, Never> { @MainActor in
                defer {
                    SessionRefreshDebugLog.log("account.foregroundRecover clear-active")
                    self.activeRefreshTask = nil
                }
                let refreshed = await self.refreshSessionWithRetry()
                if refreshed, let token = self.session?.token {
                    SessionRefreshDebugLog.log("account.foregroundRecover connectAfterRefresh token=\(SessionRefreshDebugLog.token(token))")
                    self.account.socket.connect(token: token, wsHostOverride: nil)
                } else {
                    SessionRefreshDebugLog.log("account.foregroundRecover noConnect refreshed=\(refreshed) session=\(SessionRefreshDebugLog.session(self.session))")
                }
                return refreshed
            }
            activeRefreshTask = task
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, let token = self.session?.token else { return }
                if self.account.socket.isConnected { return }
                SessionRefreshDebugLog.log("account.foregroundRecover connectExisting token=\(SessionRefreshDebugLog.token(token))")
                self.account.socket.connect(token: token, wsHostOverride: nil)
            }
        }
    }


    private func refreshSessionWithRetry() async -> Bool {
        for attempt in 1...maxForegroundRecoverRetries {
            do {
                SessionRefreshDebugLog.log("account.refreshWithRetry attempt=\(attempt) max=\(maxForegroundRecoverRetries)")
                try await refreshSession()
                SessionRefreshDebugLog.log("account.refreshWithRetry success attempt=\(attempt)")
                return true
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, (code == 401 || code == 403) {
                    SessionRefreshDebugLog.log("account.refreshWithRetry authFail attempt=\(attempt) error=\(SessionRefreshDebugLog.error(error))")
                    notifySessionExpiredAndStopRecovery()
                    return false
                }
                SessionRefreshDebugLog.log("account.refreshWithRetry mezonFail attempt=\(attempt) error=\(SessionRefreshDebugLog.error(error))")
            } catch is SessionError {
                SessionRefreshDebugLog.log("account.refreshWithRetry sessionError attempt=\(attempt)")
                notifySessionExpiredAndStopRecovery()
                return false
            } catch {
                SessionRefreshDebugLog.log("account.refreshWithRetry fail attempt=\(attempt) error=\(SessionRefreshDebugLog.error(error))")
            }

            if attempt < maxForegroundRecoverRetries {
                let delay = UInt64(attempt) * 2_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        SessionRefreshDebugLog.log("account.refreshWithRetry exhausted max=\(maxForegroundRecoverRetries)")
        return false
    }

    @objc private func handleSessionExpired() {
        SessionRefreshDebugLog.log("account.handleSessionExpired notification")
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
        SessionRefreshDebugLog.log("account.restore start saved=\(SessionRefreshDebugLog.session(saved))")
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
                SessionRefreshDebugLog.log("account.restore launchSuccess new=\(SessionRefreshDebugLog.session(newSession))")
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
                SessionRefreshDebugLog.log("account.restore launchExpired saved=\(SessionRefreshDebugLog.session(saved))")
                self.markSessionReady()
                SessionExpiredModal.show(onLoginAgain: { [self] in self.logout() })
            },
            onReady: { [weak self] in
                guard let self else { return }
                guard self.isStillCurrentSession(epoch: startEpoch) else { return }
                SessionRefreshDebugLog.log("account.restore onReady")
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
        SessionRefreshDebugLog.log("account.applySession connectSocket=\(connectSocket) fetchAccount=\(fetchAccount) session=\(SessionRefreshDebugLog.session(session))")
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

        if socketEventsDisposable == nil {
            socketEventsDisposable = account.socket.events().start(next: { [weak self] event in
                guard let self else { return }
                self.handleSocketEvent(event)
            })
        }

        if connectSocket {
            account.socket.tokenProvider = { [weak self] in
                guard let self else { throw SessionError.noSession }
                SessionRefreshDebugLog.log("account.socketTokenProvider invoked")
                return try await self.tokenForSocketReconnect()
            }
            SessionRefreshDebugLog.log("account.applySession socketConnect token=\(SessionRefreshDebugLog.token(session.token))")
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
            SessionRefreshDebugLog.log("account.voipPrepare stop noSession")
            return false
        }
        SessionRefreshDebugLog.log("account.voipPrepare start base=\(SessionRefreshDebugLog.session(baseSession)) memory=\(SessionRefreshDebugLog.session(session)) socketConnected=\(account.socket.isConnected)")
        if let s = session, !s.isExpired, account.socket.isConnected {
            markSessionReady()
            SessionRefreshDebugLog.log("account.voipPrepare ready existingSocket session=\(SessionRefreshDebugLog.session(s))")
            return true
        }
        if !baseSession.isExpired {
            account.network.updateBaseURL(from: baseSession)
            SessionRefreshDebugLog.log("account.voipPrepare use-valid-base")
            applySession(baseSession, user: currentUser, connectSocket: true, fetchAccount: false)
            markSessionReady()
            return true
        }
        account.network.updateBaseURL(from: baseSession)
        let refreshed: MezonSession
        do {
            SessionRefreshDebugLog.log("account.voipPrepare refresh expiredBase")
            refreshed = try await SessionRefreshManager.shared.refresh(session: baseSession)
        } catch {
            if baseSession.isExpired {
                SessionRefreshDebugLog.log("account.voipPrepare refresh-fail expiredBase error=\(SessionRefreshDebugLog.error(error))")
                return false
            }
            SessionRefreshDebugLog.log("account.voipPrepare refresh-fail useBase error=\(SessionRefreshDebugLog.error(error))")
            refreshed = baseSession
        }
        let merged = mergeIdToken(into: refreshed, previous: session ?? baseSession)
        SessionRefreshDebugLog.log("account.voipPrepare apply merged=\(SessionRefreshDebugLog.session(merged))")
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
            account.socket.joinClanChat(clanId: cachedClanId)
            currentClanId = cachedClanId
        }
    }

    private func joinDirectMessageSocketRoomOnSocketConnected() {
        account.socket.joinClanChat(clanId: 0)
    }

    private func rejoinCurrentChannel() {
        guard let channel = currentChannel else {
            return
        }
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

    private func subscribeSocketRoomsForMergedChannel(_ channel: Mezon_Api_ChannelDescription) {
        guard account.socket.isConnected else { return }
        let clanId = channel.clanID
        guard clanId != 0 else { return }
        account.socket.joinClanChat(clanId: clanId)
        let channelType: Int32 = channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue
        let isPublic = channel.parentID != 0 ? false : (channel.channelPrivate == 0)
        account.socket.joinChannel(
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
                topics.removeAll { $0.id == topic.id }
                topics.insert(topic, at: 0)
                tx.updateTopics(topics, clanId: event.clanID)
            }
        }
    }

    private func handleSocketEvent(_ event: SocketEvent) {
        switch event {
        case .connected:
            if VoIPMinimalCallBootstrap.isMinimalChromeActive {
                joinDirectMessageSocketRoomOnSocketConnected()
            } else {
                joinDirectMessageClanOnSocketConnected()
                rejoinCurrentChannel()
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
                    return
                }
                let incrementDmBadge = Self.shouldIncrementDmBadgeForSocketMessage(
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
                NotificationCenter.default.post(
                    name: Notification.Name("MezonNewMessageReceived"), object: nil, userInfo: userInfo
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
            let joinedIds = e.joins.map(\.userID).filter { $0 != 0 }
            let clanId = currentClanId
            if clanId != 0, !joinedIds.isEmpty {
                Task { @MainActor [weak self] in
                    guard let self, let token = await self.getToken() else { return }
                    self.engine.clanData.maybeRefreshClanMembersAfterPresenceJoins(
                        clanId: clanId,
                        joinedUserIds: joinedIds,
                        token: token
                    )
                }
            }

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

    private func handleSocketNotification(_ noti: Mezon_Api_Notification) {
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
