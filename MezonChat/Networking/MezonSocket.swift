import Foundation
import SwiftProtobuf

enum WebRTCSignalingType: Int32 {
    case offer = 1
    case answer = 2
    case iceCandidate = 3
    case hangUp = 4
}

@MainActor
final class MezonSocket: NSObject {

    static let shared = MezonSocket()

    var onMessageReceived: ((Mezon_Api_ChannelMessage) -> Void)?

    var onTyping:             ((Mezon_Realtime_MessageTypingEvent)         -> Void)?
    var onReaction:           ((Mezon_Api_MessageReaction)                 -> Void)?
    var onPresence:           ((Mezon_Realtime_ChannelPresenceEvent)       -> Void)?
    var onNotification:       ((Mezon_Api_Notification)                    -> Void)?
    var onStatusPresence:     ((Mezon_Realtime_StatusPresenceEvent)        -> Void)?
    var onLastSeen:           ((Mezon_Realtime_LastSeenMessageEvent)       -> Void)?
    var onLastPin:            ((Mezon_Realtime_LastPinMessageEvent)        -> Void)?
    var onUnpinMessage:       ((Mezon_Realtime_UnpinMessageEvent)          -> Void)?
    var onMessageRemoved:     ((Mezon_Realtime_ChannelMessageRemove)       -> Void)?
    var onMessageButton:      ((Mezon_Realtime_MessageButtonClicked)       -> Void)?

    var onChannelCreated:     ((Mezon_Realtime_ChannelCreatedEvent)        -> Void)?
    var onChannelDeleted:     ((Mezon_Realtime_ChannelDeletedEvent)        -> Void)?
    var onChannelUpdated:     ((Mezon_Realtime_ChannelUpdatedEvent)        -> Void)?
    var onCategoryEvent:      ((Mezon_Realtime_CategoryEvent)              -> Void)?
    var onNotiUserChannel:    ((Mezon_Api_NotificationUserChannel)         -> Void)?
    var onUserChannelAdded:   ((Mezon_Realtime_UserChannelAdded)           -> Void)?
    var onUserChannelRemoved: ((Mezon_Realtime_UserChannelRemoved)         -> Void)?
    var onMarkAsRead:         ((Mezon_Realtime_UnmuteEvent)                -> Void)?

    var onClanUpdated:        ((Mezon_Realtime_ClanUpdatedEvent)           -> Void)?
    var onClanProfileUpdated: ((Mezon_Realtime_ClanProfileUpdatedEvent)    -> Void)?
    var onClanDeleted:        ((Mezon_Realtime_ClanDeletedEvent)           -> Void)?
    var onUserClanRemoved:    ((Mezon_Realtime_UserClanRemoved)            -> Void)?
    var onUserClanAdded:      ((Mezon_Realtime_AddClanUserEvent)           -> Void)?

    var onVoiceJoined:        ((Mezon_Realtime_VoiceJoinedEvent)           -> Void)?
    var onVoiceLeaved:        ((Mezon_Realtime_VoiceLeavedEvent)           -> Void)?
    var onVoiceEnded:         ((Mezon_Realtime_VoiceEndedEvent)            -> Void)?
    var onVoiceReaction:      ((Mezon_Realtime_VoiceReactionSend)          -> Void)?
    var onStreamingJoined:    ((Mezon_Realtime_StreamingJoinedEvent)       -> Void)?
    var onStreamingLeaved:    ((Mezon_Realtime_StreamingLeavedEvent)       -> Void)?
    var onWebRTC:             ((Mezon_Realtime_WebrtcSignalingFwd)         -> Void)?

    var onCustomStatus:       ((Mezon_Realtime_CustomStatusEvent)          -> Void)?
    var onUserStatus:         ((Mezon_Realtime_UserStatusEvent)            -> Void)?
    var onUserProfileUpdated: ((Mezon_Realtime_UserProfileUpdatedEvent)    -> Void)?
    var onRemoveFriend:       ((Mezon_Realtime_RemoveFriend)               -> Void)?
    var onBlockFriend:        ((Mezon_Realtime_BlockFriend)                -> Void)?
    var onTokenSent:          ((Mezon_Api_TokenSentEvent)                  -> Void)?
    var onGiveCoffee:         ((Mezon_Api_GiveCoffeeEvent)                 -> Void)?

    var onRoleEvent:          ((Mezon_Realtime_RoleEvent)                  -> Void)?
    var onRoleAssign:         ((Mezon_Realtime_RoleAssignedEvent)          -> Void)?
    var onPermissionSet:      ((Mezon_Realtime_PermissionSetEvent)         -> Void)?
    var onPermissionChanged:  ((Mezon_Realtime_PermissionChangedEvent)     -> Void)?

    var onStickerCreated:     ((Mezon_Realtime_StickerCreateEvent)         -> Void)?
    var onStickerUpdated:     ((Mezon_Realtime_StickerUpdateEvent)         -> Void)?
    var onStickerDeleted:     ((Mezon_Realtime_StickerDeleteEvent)         -> Void)?
    var onEmojiEvent:         ((Mezon_Realtime_EventEmoji)                 -> Void)?

    var onCanvasEvent:        ((Mezon_Realtime_ChannelCanvas)              -> Void)?
    var onWebhookEvent:       ((Mezon_Api_Webhook)                        -> Void)?
    var onSdTopicEvent:       ((Mezon_Realtime_SdTopicEvent)               -> Void)?

    var onDisconnect:         (() -> Void)?
    var onReconnect:          (() -> Void)?
    var onConnected:          (() -> Void)?
    var onError:              ((Error) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var token: String?
    private var wsHostOverride: String?
    private(set) var isConnected = false
    private var reconnectAttempts = 0
    private var hasTriedRefreshSinceConnect = false
    private let maxReconnectAttempts = 5

    var tokenProvider: (() async throws -> String)?

    private var pendingDataSocketCallbacks: [String: (Mezon_Realtime_ListDataSocket) -> Void] = [:]
    private var reconnectWorkItem: DispatchWorkItem?

    private override init() { super.init() }

    func connect(token: String, wsHostOverride: String? = nil) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        if let old = webSocketTask {
            old.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
        }
        urlSession?.invalidateAndCancel()

        self.token = token
        self.wsHostOverride = wsHostOverride
        reconnectAttempts = 0

        let url = MezonConfig.wsURL(token: token, wsHostOverride: wsHostOverride)
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveLoop()
        AppLogger.app.info("MezonSocket connecting to \(url)")
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
        reconnectAttempts = 0
        hasTriedRefreshSinceConnect = false
        tokenProvider = nil
        pendingDataSocketCallbacks.removeAll()
        onConnected = nil
    }

    func reconnectFromForeground() {
        guard token != nil || tokenProvider != nil else { return }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempts = 0
        hasTriedRefreshSinceConnect = false
        AppLogger.app.info("MezonSocket reconnecting from foreground")
        Task { @MainActor in
            await performReconnect(useTokenRefresh: tokenProvider != nil)
        }
    }

    private func cleanupForReconnect() {
        isConnected = false
        NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    func send(_ envelope: Mezon_Realtime_Envelope) {
        guard let task = webSocketTask else { return }
        do {
            let data = try envelope.serializedData()
            task.send(.data(data)) { error in
                if let error { AppLogger.app.error("MezonSocket send error: \(error)") }
            }
        } catch {
            AppLogger.app.error("MezonSocket encode error: \(error)")
        }
    }

    func joinClanChat(clanId: Int64) {
        var join = Mezon_Realtime_ClanJoin()
        join.clanID = clanId
        var envelope = Mezon_Realtime_Envelope()
        envelope.clanJoin = join
        send(envelope)
    }

    func joinChannel(clanId: Int64, channelId: Int64, channelType: Int32, isPublic: Bool) {
        var join = Mezon_Realtime_ChannelJoin()
        join.clanID = clanId
        join.channelID = channelId
        join.channelType = channelType
        join.isPublic = isPublic
        var envelope = Mezon_Realtime_Envelope()
        envelope.channelJoin = join
        send(envelope)
    }

    func sendVoiceParticipantMeetState(clanId: Int64, channelId: Int64, roomName: String, displayName: String, join: Bool) {
        var ev = Mezon_Realtime_HandleParticipantMeetStateEvent()
        ev.clanID = clanId
        ev.channelID = channelId
        ev.displayName = displayName
        ev.roomName = roomName
        ev.state = join ? 0 : 1
        var envelope = Mezon_Realtime_Envelope()
        envelope.handleParticipantMeetStateEvent = ev
        send(envelope)
        AppLogger.app.info("[MezonSocket] voice meet state clan=\(clanId) channel=\(channelId) join=\(join)")
    }

    func sendVoiceReaction(channelId: Int64, senderId: Int64, emojis: [String], mediaType: Int32 = 0) {
        guard !emojis.isEmpty else { return }
        var r = Mezon_Realtime_VoiceReactionSend()
        r.channelID = channelId
        r.senderID = senderId
        r.emojis = emojis
        r.mediaType = mediaType
        var envelope = Mezon_Realtime_Envelope()
        envelope.voiceReactionSend = r
        send(envelope)
    }

    func sendMessageTyping(
        clanId: Int64,
        channelId: Int64,
        mode: Int32,
        isPublic: Bool,
        senderId: Int64,
        senderUsername: String,
        senderDisplayName: String,
        topicId: Int64
    ) {
        var typing = Mezon_Realtime_MessageTypingEvent()
        typing.clanID = clanId
        typing.channelID = channelId
        typing.mode = mode
        typing.isPublic = isPublic
        typing.senderID = senderId
        typing.senderUsername = senderUsername
        typing.senderDisplayName = senderDisplayName.isEmpty ? senderUsername : senderDisplayName
        typing.topicID = topicId
        var envelope = Mezon_Realtime_Envelope()
        envelope.messageTypingEvent = typing
        send(envelope)
    }

    func removeChannelMessage(clanId: Int64, channelId: Int64, mode: Int32, messageId: Int64, isPublic: Bool, topicId: Int64 = 0) {
        var remove = Mezon_Realtime_ChannelMessageRemove()
        remove.clanID = clanId
        remove.channelID = channelId
        remove.messageID = messageId
        remove.mode = mode
        remove.isPublic = isPublic
        remove.topicID = topicId
        var envelope = Mezon_Realtime_Envelope()
        envelope.channelMessageRemove = remove
        send(envelope)
        AppLogger.app.info("[MezonSocket] removeChannelMessage channelId=\(channelId) messageId=\(messageId)")
    }

    func writeLastSeenMessage(clanId: Int64, channelId: Int64, mode: Int32, messageId: Int64, timestampSeconds: UInt32, badgeCount: Int32) {
        var event = Mezon_Realtime_LastSeenMessageEvent()
        event.clanID = clanId
        event.channelID = channelId
        event.mode = mode
        event.messageID = messageId
        event.timestampSeconds = timestampSeconds
        event.badgeCount = badgeCount
        var envelope = Mezon_Realtime_Envelope()
        envelope.lastSeenMessageEvent = event
        send(envelope)
        AppLogger.app.info("[MezonSocket] writeLastSeenMessage channelId=\(channelId) messageId=\(messageId)")
    }

    /// Parity with RN `writeCustomStatus(clanId, text, minutes, noClear)`.
    func writeCustomStatus(clanId: Int64, status: String, minutes: Int32, noClear: Bool) {
        var ev = Mezon_Realtime_CustomStatusEvent()
        ev.clanID = clanId
        ev.status = status
        ev.timeReset = minutes
        ev.noClear = noClear
        var envelope = Mezon_Realtime_Envelope()
        envelope.customStatusEvent = ev
        send(envelope)
        AppLogger.app.info("[MezonSocket] writeCustomStatus clanId=\(clanId) noClear=\(noClear) minutes=\(minutes)")
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.handleMessage(message)
                    self.receiveLoop()
                }
            case .failure(let error):
                let nsErr = error as NSError
                guard nsErr.code != NSURLErrorCancelled else { return }
                AppLogger.app.error("MezonSocket receive error: \(error) (code=\(nsErr.code))")
                Task { @MainActor in
                    self.cleanupForReconnect()
                    self.onError?(error)
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):       decodeEnvelope(data)
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            decodeEnvelope(data)
        @unknown default: break
        }
    }

    private func decodeEnvelope(_ data: Data) {
        do {
            let envelope = try Mezon_Realtime_Envelope(serializedBytes: data)
            routeEnvelope(envelope)
        } catch {
            AppLogger.app.error("MezonSocket decode error: \(error)")
        }
    }

    private func routeEnvelope(_ envelope: Mezon_Realtime_Envelope) {
        switch envelope.message {
        case .channelMessage(let m):
            onMessageReceived?(m)
        case .channelMessageSend:
            break
        case .channelMessageUpdate:
            break
        case .channelMessageRemove(let m):
            onMessageRemoved?(m)
        case .messageTypingEvent(let m):
            onTyping?(m)
        case .messageReactionEvent(let m):
            onReaction?(m)
        case .channelPresenceEvent(let m):
            onPresence?(m)
        case .notifications(let m):
            m.notifications.forEach { onNotification?($0) }
        case .statusPresenceEvent(let m):
            onStatusPresence?(m)
        case .lastSeenMessageEvent(let m):
            onLastSeen?(m)
        case .lastPinMessageEvent(let m):
            onLastPin?(m)
        case .unpinMessageEvent(let m):
            onUnpinMessage?(m)
        case .messageButtonClicked(let m):
            onMessageButton?(m)
        case .channelCreatedEvent(let m):
            onChannelCreated?(m)
        case .channelDeletedEvent(let m):
            onChannelDeleted?(m)
        case .channelUpdatedEvent(let m):
            onChannelUpdated?(m)
        case .categoryEvent(let m):
            onCategoryEvent?(m)
        case .notiUserChannel(let m):
            onNotiUserChannel?(m)
        case .userChannelAddedEvent(let m):
            onUserChannelAdded?(m)
        case .userChannelRemovedEvent(let m):
            onUserChannelRemoved?(m)
        case .unmuteEvent(let m):
            onMarkAsRead?(m)
        case .clanUpdatedEvent(let m):
            onClanUpdated?(m)
        case .clanProfileUpdatedEvent(let m):
            onClanProfileUpdated?(m)
        case .clanDeletedEvent(let m):
            onClanDeleted?(m)
        case .userClanRemovedEvent(let m):
            onUserClanRemoved?(m)
        case .addClanUserEvent(let m):
            onUserClanAdded?(m)
        case .voiceJoinedEvent(let m):
            onVoiceJoined?(m)
        case .voiceLeavedEvent(let m):
            onVoiceLeaved?(m)
        case .voiceEndedEvent(let m):
            onVoiceEnded?(m)
        case .voiceReactionSend(let m):
            onVoiceReaction?(m)
        case .streamingJoinedEvent(let m):
            onStreamingJoined?(m)
        case .streamingLeavedEvent(let m):
            onStreamingLeaved?(m)
        case .webrtcSignalingFwd(let m):
            onWebRTC?(m)
        case .customStatusEvent(let m):
            onCustomStatus?(m)
        case .userStatusEvent(let m):
            onUserStatus?(m)
        case .userProfileUpdatedEvent(let m):
            onUserProfileUpdated?(m)
        case .removeFriend(let m):
            onRemoveFriend?(m)
        case .blockFriend(let m):
            onBlockFriend?(m)
        case .tokenSentEvent(let m):
            onTokenSent?(m)
        case .giveCoffeeEvent(let m):
            onGiveCoffee?(m)
        case .roleEvent(let m):
            onRoleEvent?(m)
        case .roleAssignEvent(let m):
            onRoleAssign?(m)
        case .permissionSetEvent(let m):
            onPermissionSet?(m)
        case .permissionChangedEvent(let m):
            onPermissionChanged?(m)
        case .stickerCreateEvent(let m):
            onStickerCreated?(m)
        case .stickerUpdateEvent(let m):
            onStickerUpdated?(m)
        case .stickerDeleteEvent(let m):
            onStickerDeleted?(m)
        case .eventEmoji(let m):
            onEmojiEvent?(m)
        case .canvasEvent(let m):
            onCanvasEvent?(m)
        case .webhookEvent(let m):
            onWebhookEvent?(m)
        case .sdTopicEvent(let m):
            onSdTopicEvent?(m)
        case .ping:
            var pong = Mezon_Realtime_Envelope()
            pong.pong = Mezon_Realtime_Pong()
            send(pong)
        case .listDataSocket(let m):
            let cid = envelope.cid
            if let cb = pendingDataSocketCallbacks.removeValue(forKey: cid) {
                cb(m)
            }
        default:
            break
        }
    }

    func listDataSocket(_ request: Mezon_Realtime_ListDataSocket) async throws -> Mezon_Realtime_ListDataSocket {
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID().uuidString
            var resumed = false
            pendingDataSocketCallbacks[id] = { [weak self] response in
                guard !resumed else { return }
                resumed = true
                self?.pendingDataSocketCallbacks.removeValue(forKey: id)
                continuation.resume(returning: response)
            }
            var envelope = Mezon_Realtime_Envelope()
            envelope.cid = id
            envelope.listDataSocket = request
            send(envelope)

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !resumed else { return }
                resumed = true
                self?.pendingDataSocketCallbacks.removeValue(forKey: id)
                continuation.resume(throwing: MezonError.socketError("listDataSocket timeout for \(request.apiName)"))
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts || (tokenProvider != nil && !hasTriedRefreshSinceConnect) else {
            AppLogger.app.error("MezonSocket reconnect abandoned after max attempts")
            return
        }
        reconnectAttempts += 1
        let useRefresh = tokenProvider != nil && !hasTriedRefreshSinceConnect
        if useRefresh {
            hasTriedRefreshSinceConnect = true
        }
        let delay = Double(min(reconnectAttempts * 2, 30))
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.performReconnect(useTokenRefresh: useRefresh)
            }
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performReconnect(useTokenRefresh: Bool = false) async {
        var tokenToUse = token
        if useTokenRefresh, let provider = tokenProvider {
            do {
                tokenToUse = try await provider()
                reconnectAttempts = 0
            } catch let error as MezonError {
                if case .httpError(let code, _) = error, code == 401 || code == 403 {
                    AppLogger.app.warning("MezonSocket token refresh failed with \(code) — session expired")
                    NotificationCenter.default.post(name: Notification.Name("MezonSessionExpired"), object: nil)
                    return
                }
                AppLogger.app.warning("MezonSocket token refresh failed: \(error), using stored token")
            } catch {
                AppLogger.app.warning("MezonSocket token refresh failed: \(error), using stored token")
            }
        }
        guard let token = tokenToUse else {
            AppLogger.app.error("MezonSocket reconnect aborted: no token")
            return
        }
        connect(token: token, wsHostOverride: wsHostOverride)
        onReconnect?()
    }

    // MARK: - WebRTC Signaling

    /// Forward a WebRTC signaling message to a remote peer (SDP offer/answer, ICE candidate, quit, etc.)
    func forwardWebrtcSignaling(
        receiverId: Int64,
        dataType: WebRTCSignalingType,
        jsonData: String,
        channelId: Int64,
        callerId: Int64
    ) {
        var fwd = Mezon_Realtime_WebrtcSignalingFwd()
        fwd.receiverID = receiverId
        fwd.dataType = dataType.rawValue
        fwd.jsonData = jsonData
        fwd.channelID = channelId
        fwd.callerID = callerId
        var envelope = Mezon_Realtime_Envelope()
        envelope.webrtcSignalingFwd = fwd
        send(envelope)
        let signalingTypeCode = Int(dataType.rawValue)
        AppLogger.app.info("[MezonSocket] forwardWebrtcSignaling type=\(signalingTypeCode) to=\(receiverId)")
    }

    /// Send VoIP push to receiver to trigger incoming call (CallKit on iOS)
    func makeCallPush(
        receiverId: Int64,
        jsonData: String,
        channelId: Int64,
        callerId: Int64
    ) {
        var push = Mezon_Realtime_IncomingCallPush()
        push.receiverID = receiverId
        push.jsonData = jsonData
        push.channelID = channelId
        push.callerID = callerId
        var envelope = Mezon_Realtime_Envelope()
        envelope.incomingCallPush = push
        send(envelope)
        AppLogger.app.info("[MezonSocket] makeCallPush to=\(receiverId)")
    }

    func fetchListChannelBadgeCount(clanId: Int64) async throws -> [Mezon_Api_ChannelDescription] {
        guard isConnected else {
            throw MezonError.socketError("Socket not connected")
        }
        var socketReq = Mezon_Realtime_ListDataSocket()
        socketReq.apiName = "ListChannelBadgeCount"
        var inner = Mezon_Api_ListChannelBadgeCountRequest()
        inner.clanID = clanId
        socketReq.listChannelBadgeCountReq = inner
        let response = try await listDataSocket(socketReq)
        guard response.hasChannelBadgeCount else { return [] }
        return response.channelBadgeCount.channeldesc
    }

    func fetchListClanBadgeCount() async throws -> [Mezon_Api_ClanBadgeCount] {
        guard isConnected else {
            throw MezonError.socketError("Socket not connected")
        }
        var socketReq = Mezon_Realtime_ListDataSocket()
        socketReq.apiName = "ListClanBadgeCount"
        let response = try await listDataSocket(socketReq)
        guard response.hasClanBadgeCount else { return [] }
        return response.clanBadgeCount.listBadge
    }
}

extension MezonSocket: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.isConnected = true
            self.reconnectAttempts = 0
            self.hasTriedRefreshSinceConnect = false
            self.onConnected?()
            NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": true])
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.isConnected = false
            NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
            self.onDisconnect?()

            if closeCode != .normalClosure {
                self.scheduleReconnect()
            }
        }
    }
}

enum ChannelUnreadBadgeSync {
    static func mergeSocketBadgeRows(into channels: inout [Mezon_Api_ChannelDescription], badgeRows: [Mezon_Api_ChannelDescription]) {
        guard !badgeRows.isEmpty else { return }
        var byId: [Int64: Mezon_Api_ChannelDescription] = [:]
        for row in badgeRows {
            byId[row.channelID] = row
        }
        for i in channels.indices {
            guard let b = byId[channels[i].channelID] else { continue }
            channels[i].countMessUnread = b.countMessUnread
            if b.hasLastSeenMessage {
                channels[i].lastSeenMessage = b.lastSeenMessage
            }
            if b.hasLastSentMessage {
                var inc = b.lastSentMessage
                if channels[i].hasLastSentMessage {
                    let ex = channels[i].lastSentMessage
                    if inc.content.isEmpty, !ex.content.isEmpty {
                        inc.content = ex.content
                        if inc.senderID == 0 { inc.senderID = ex.senderID }
                        if inc.id == 0 { inc.id = ex.id }
                    }
                    inc.timestampSeconds = max(inc.timestampSeconds, ex.timestampSeconds)
                }
                channels[i].lastSentMessage = inc
            }
        }
    }

    static func applyClanBadgeRows(to clans: inout [Mezon_Api_ClanDesc], rows: [Mezon_Api_ClanBadgeCount]) {
        guard !rows.isEmpty else { return }
        var byId: [Int64: Mezon_Api_ClanBadgeCount] = [:]
        for r in rows {
            byId[r.clanID] = r
        }
        for i in clans.indices {
            guard let row = byId[clans[i].clanID] else { continue }
            clans[i].badgeCount = row.badge
            clans[i].hasUnreadMessage_p = row.hasUnread_p
        }
    }
}
