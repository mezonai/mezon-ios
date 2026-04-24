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

    private var socketEventsDisposable: Disposable?
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

    func applyCurrentUser(_ user: User) {
        currentUser = user
        NotificationCenter.default.post(name: .mezonAccountCurrentUserDidChange, object: nil)
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
            return await inflight.value
        }
        let task = Task<Bool, Never> { @MainActor in
            defer { self.activeRefreshTask = nil }
            for attempt in 1...2 {
                do {
                    try await self.refreshSession()
                    return true
                } catch {
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
            }
            if let freshSession = self.session {
                applySession(freshSession, user: currentUser, connectSocket: true, fetchAccount: false)
            }
            self.registerFCMTokenIfNeeded()
        }
    }

    func logout() {
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
        SessionStore.clear()
        MmnWalletStore.shared.clear()
        SessionRefreshManager.shared.reset()
        session = nil
        currentUser = nil
        NotificationCenter.default.post(name: .mezonAccountCurrentUserDidChange, object: nil)
        currentClanId = 0
        currentChannel = nil
        account.postbox.clearAll()
        UserDefaults.standard.removeObject(forKey: "mezon_selectedClanId")

        UserDefaults(suiteName: "group.mezon.mobile")?.set(0, forKey: "badgeCount")
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }

        setLoggedIn(false)
    }

    private func registerFCMTokenIfNeeded() {
        guard let fcmToken = Messaging.messaging().fcmToken else {
            return
        }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        Task {
            guard let authToken = await self.getToken() else { return }
            do {
                _ = try await account.network.registFcmDeviceToken(
                    fcmToken: fcmToken, deviceId: deviceId, platform: "ios", authToken: authToken
                )
            } catch {
            }
        }
    }

    func refreshSession() async throws {
        guard let current = session else { throw SessionError.noSession }
        let new = try await engine.auth.sessionRefresh(session: current)
        let merged = mergeIdToken(into: new, previous: current)
        MmnDebugLog.line("refreshSession applied idToken.len=\(merged.idToken?.count ?? 0) (server=\(new.idToken?.count ?? 0), prev=\(current.idToken?.count ?? 0))")
        applySession(merged, user: currentUser, connectSocket: false, fetchAccount: false)
    }

    private func mergeIdToken(into newSession: MezonSession, previous: MezonSession?) -> MezonSession {
        let merged = previous.map { newSession.mergedPreservingIdToken(from: $0) } ?? newSession
        return SessionStore.applyIdTokenFallback(merged)
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
            DispatchQueue.main.async { [weak self] in
                guard let self, let token = self.session?.token else { return }
                self.account.socket.connect(token: token, wsHostOverride: nil)
            }
        }
    }


    private func refreshSessionWithRetry() async -> Bool {
        for attempt in 1...maxForegroundRecoverRetries {
            do {
                try await refreshSession()
                return true
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, (code == 401 || code == 403) {
                    SessionExpiredModal.show(onLoginAgain: { [self] in self.logout() })
                    return false
                }
                #if DEBUG
                print(
                    "[SessionRefresh] refreshSessionWithRetry MezonError attempt=\(attempt)/\(maxForegroundRecoverRetries): \(error.localizedDescription)"
                )
                #endif
            } catch {
                #if DEBUG
                print(
                    "[SessionRefresh] refreshSessionWithRetry attempt=\(attempt)/\(maxForegroundRecoverRetries): \(error.localizedDescription)"
                )
                #endif
            }

            if attempt < maxForegroundRecoverRetries {
                let delay = UInt64(attempt) * 2_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        account.socket.reconnectFromForeground()
        return false
    }

    @objc private func handleSessionExpired() {
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
        setLoggedIn(true)
        account.network.updateBaseURL(from: saved)

        SessionRefreshManager.shared.refreshOnAppLaunch(
            session: saved,
            onSuccess: { [weak self] newSession in
                guard let self else { return }
                let merged = self.mergeIdToken(into: newSession, previous: saved)
                MmnDebugLog.line("restoreAndRefreshSession applied idToken.len=\(merged.idToken?.count ?? 0) (server=\(newSession.idToken?.count ?? 0), prev=\(saved.idToken?.count ?? 0))")
                self.applySession(merged, user: self.currentUser, connectSocket: true)
                self.registerFCMTokenIfNeeded()
                self.markSessionReady()
            },
            onExpired: { [weak self] in
                guard let self else { return }
                self.markSessionReady()
                SessionExpiredModal.show(onLoginAgain: { [self] in self.logout() })
            },
            onReady: { [weak self] in
                guard let self else { return }
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

        account.network.bearerUnauthorizedRecovery = { [weak self] in
            guard let self else { return nil }
            do {
                try await self.refreshSession()
                return self.session?.token
            } catch {
                return nil
            }
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
                try await self.refreshSession()
                guard let t = self.session?.token else { throw SessionError.noSession }
                return t
            }
            account.socket.connect(token: session.token, wsHostOverride: nil)
        }
        if let user { applyCurrentUser(user) }

        guard fetchAccount else { return }
        Task { @MainActor in
            do {
                let apiAccount = try await engine.auth.getAccount(token: session.token)
                if let data = try? apiAccount.serializedData() {
                    account.postbox.setPreferenceData(key: PreferencesKeys.account, value: data)
                }
                applyCurrentUser(mapAccountToUser(apiAccount))
            } catch {
                applyCachedAccountIfAvailable()
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
                Task { [weak self] in
                    await self?.engine.prefetchMediaPanelCaches(token: token)
                }
            } catch {
            }
        }
    }

    private func joinDirectMessageClanOnSocketConnected() {
        account.socket.joinClanChat(clanId: 0)

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

    private func handleSocketEvent(_ event: SocketEvent) {
        switch event {
        case .connected:
            joinDirectMessageClanOnSocketConnected()
            rejoinCurrentChannel()

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
                account.postbox.write { tx in tx.deleteMessage(id: "\(apiMessage.messageID)") }
                return
            }
            let mid = "\(apiMessage.messageID)"
            let merged = account.postbox.read { tx in
                MessageRecord.fromApi(apiMessage, merging: tx.getMessageById(mid))
            }
            account.postbox.write { tx in tx.addMessages([merged]) }
            guard apiMessage.code != 1 else { return }

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

        case .voiceEnded(let ev):
            let cid = Int64(ev.voiceChannelID) ?? 0
            guard cid != 0 else { return }
            engine.clanData.applyVoiceEnded(clanId: ev.clanID, channelId: cid)

        case .notification(let noti):
            handleSocketNotification(noti)

        case .webRTC(let msg):
            WebRTCCallManager.shared.handleSignalingMessage(msg)

        case .customStatus(let e):
            applyIncomingCustomStatusEvent(e)

        case .userStatus(let e):
            applyIncomingUserStatusEvent(e)

        case .statusPresence(let e):
            applyIncomingStatusPresenceEvent(e)

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
        return User(
            id: "\(u.id)",
            username: u.username.isEmpty ? "me" : u.username,
            displayName: u.displayName.isEmpty ? u.username : u.displayName,
            avatarURL: u.avatarURL.isEmpty ? nil : URL(string: u.avatarURL),
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
