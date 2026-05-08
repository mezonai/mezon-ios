import Foundation
import SwiftProtobuf

enum SocketEvent {
    case messageReceived(Mezon_Api_ChannelMessage)
    case messageUpdated(Mezon_Realtime_ChannelMessageUpdate)
    case typing(Mezon_Realtime_MessageTypingEvent)
    case reaction(Mezon_Api_MessageReaction)
    case presence(Mezon_Realtime_ChannelPresenceEvent)
    case notification(Mezon_Api_Notification)
    case statusPresence(Mezon_Realtime_StatusPresenceEvent)
    case lastSeen(Mezon_Realtime_LastSeenMessageEvent)
    case lastPin(Mezon_Realtime_LastPinMessageEvent)
    case unpinMessage(Mezon_Realtime_UnpinMessageEvent)
    case messageRemoved(Mezon_Realtime_ChannelMessageRemove)
    case messageButton(Mezon_Realtime_MessageButtonClicked)

    case channelCreated(Mezon_Realtime_ChannelCreatedEvent)
    case channelDeleted(Mezon_Realtime_ChannelDeletedEvent)
    case channelUpdated(Mezon_Realtime_ChannelUpdatedEvent)
    case categoryEvent(Mezon_Realtime_CategoryEvent)
    case notiUserChannel(Mezon_Api_NotificationUserChannel)
    case userChannelAdded(Mezon_Realtime_UserChannelAdded)
    case userChannelRemoved(Mezon_Realtime_UserChannelRemoved)
    case markAsRead(Mezon_Realtime_UnmuteEvent)

    case clanUpdated(Mezon_Realtime_ClanUpdatedEvent)
    case clanProfileUpdated(Mezon_Realtime_ClanProfileUpdatedEvent)
    case clanDeleted(Mezon_Realtime_ClanDeletedEvent)
    case userClanRemoved(Mezon_Realtime_UserClanRemoved)
    case userClanAdded(Mezon_Realtime_AddClanUserEvent)

    case voiceJoined(Mezon_Realtime_VoiceJoinedEvent)
    case voiceLeaved(Mezon_Realtime_VoiceLeavedEvent)
    case voiceEnded(Mezon_Realtime_VoiceEndedEvent)
    case voiceReaction(Mezon_Realtime_VoiceReactionSend)
    case aiAgentEnabled(Mezon_Realtime_AIAgentEnabledEvent)
    case streamingJoined(Mezon_Realtime_StreamingJoinedEvent)
    case streamingLeaved(Mezon_Realtime_StreamingLeavedEvent)
    case webRTC(Mezon_Realtime_WebrtcSignalingFwd)
    case incomingCallPush(Mezon_Realtime_IncomingCallPush)

    case customStatus(Mezon_Realtime_CustomStatusEvent)
    case userStatus(Mezon_Realtime_UserStatusEvent)
    case userProfileUpdated(Mezon_Realtime_UserProfileUpdatedEvent)
    case removeFriend(Mezon_Realtime_RemoveFriend)
    case blockFriend(Mezon_Realtime_BlockFriend)
    case addFriend(Mezon_Realtime_AddFriend)
    case tokenSent(Mezon_Api_TokenSentEvent)
    case giveCoffee(Mezon_Api_GiveCoffeeEvent)

    case roleEvent(Mezon_Realtime_RoleEvent)
    case roleAssign(Mezon_Realtime_RoleAssignedEvent)
    case permissionSet(Mezon_Realtime_PermissionSetEvent)
    case permissionChanged(Mezon_Realtime_PermissionChangedEvent)

    case stickerCreated(Mezon_Realtime_StickerCreateEvent)
    case stickerUpdated(Mezon_Realtime_StickerUpdateEvent)
    case stickerDeleted(Mezon_Realtime_StickerDeleteEvent)
    case emojiEvent(Mezon_Realtime_EventEmoji)

    case canvasEvent(Mezon_Realtime_ChannelCanvas)
    case webhookEvent(Mezon_Api_Webhook)
    case sdTopicEvent(Mezon_Realtime_SdTopicEvent)

    case disconnected
    case reconnected
    case connected
    case error(Error)
}

@MainActor
final class MezonSocket: NSObject {

    static let shared = MezonSocket()

    private let eventPipe = ValuePipe<SocketEvent>()

    func events() -> Signal<SocketEvent, NoError> {
        return eventPipe.signal()
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var token: String?
    private var wsHostOverride: String?
    private(set) var isConnected = false
    private var reconnectAttempts = 0
    private var hasTriedRefreshSinceConnect = false
    private let maxReconnectAttempts = 5
    private var pendingSendQueue: [(envelope: Mezon_Realtime_Envelope, queuedAt: Date)] = []
    private let pendingSendQueueCap = 32
    private let pendingSendStaleAge: TimeInterval = 10

    var tokenProvider: (() async throws -> String)?

    private var reconnectWorkItem: DispatchWorkItem?

    private override init() { super.init() }

    func connect(token: String, wsHostOverride: String? = nil) {
        // Dedupe redundant connect calls. When two paths race to connect with
        // the same credentials (e.g. AccountContext.restoreAndRefreshSession
        // and CallKit.prepareForVoIPAnswerConnectivity both completing at
        // roughly the same time on a VoIP cold-launch), cancelling the
        // already-in-flight WebSocket and rebuilding it just adds a wasted
        // round-trip before we can send the answer SDP.
        if self.token == token, self.wsHostOverride == wsHostOverride,
           webSocketTask != nil {
            return
        }

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
    }

    func waitForConnected(timeoutNanoseconds: UInt64) async -> Bool {
        if isConnected { return true }
        let step: UInt64 = 50_000_000
        var elapsed: UInt64 = 0
        while elapsed < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: step)
            elapsed += step
            if isConnected { return true }
        }
        return isConnected
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
    }

    func reconnectFromForeground() {
        guard token != nil || tokenProvider != nil else { return }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempts = 0
        hasTriedRefreshSinceConnect = false
        // Force a fresh connection: callers of reconnectFromForeground
        // (e.g. protectedDataDidBecomeAvailable) intentionally suspect a
        // stale connection, so we must bypass connect()'s same-token dedupe.
        cleanupForReconnect()
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
        guard isConnected, let task = webSocketTask else {
            enqueuePendingSend(envelope)
            return
        }
        guard let data = try? envelope.serializedData() else { return }
        task.send(.data(data)) { _ in }
    }

    private func enqueuePendingSend(_ envelope: Mezon_Realtime_Envelope) {
        let now = Date()
        pendingSendQueue.removeAll { now.timeIntervalSince($0.queuedAt) > pendingSendStaleAge }
        if pendingSendQueue.count >= pendingSendQueueCap {
            pendingSendQueue.removeFirst()
        }
        pendingSendQueue.append((envelope, now))
    }

    private func flushPendingSendQueue() {
        guard isConnected, let task = webSocketTask else { return }
        guard !pendingSendQueue.isEmpty else { return }
        let now = Date()
        let batch = pendingSendQueue.filter { now.timeIntervalSince($0.queuedAt) <= pendingSendStaleAge }
        pendingSendQueue.removeAll()
        for entry in batch {
            guard let data = try? entry.envelope.serializedData() else { continue }
            task.send(.data(data)) { _ in }
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
    }

    func writeCustomStatus(clanId: Int64, status: String, minutes: Int32, noClear: Bool) {
        var ev = Mezon_Realtime_CustomStatusEvent()
        ev.clanID = clanId
        ev.status = status
        ev.timeReset = minutes
        ev.noClear = noClear
        var envelope = Mezon_Realtime_Envelope()
        envelope.customStatusEvent = ev
        send(envelope)
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
                Task { @MainActor in
                    self.cleanupForReconnect()
                    self.eventPipe.putNext(.error(error))
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
        if let envelope = try? Mezon_Realtime_Envelope(serializedBytes: data) {
            routeEnvelope(envelope)
            return
        }
        if let envelope = try? Mezon_Realtime_Envelope(jsonUTF8Data: data) {
            routeEnvelope(envelope)
            return
        }
    }

    private func routeEnvelope(_ envelope: Mezon_Realtime_Envelope) {
        switch envelope.message {
        case .channelMessage(let m):
            eventPipe.putNext(.messageReceived(m))
        case .channelMessageSend:
            break
        case .channelMessageUpdate(let m):
            eventPipe.putNext(.messageUpdated(m))
        case .channelMessageRemove(let m):
            eventPipe.putNext(.messageRemoved(m))
        case .messageTypingEvent(let m):
            eventPipe.putNext(.typing(m))
        case .messageReactionEvent(let m):
            eventPipe.putNext(.reaction(m))
        case .channelPresenceEvent(let m):
            eventPipe.putNext(.presence(m))
        case .notifications(let m):
            m.notifications.forEach { eventPipe.putNext(.notification($0)) }
        case .statusPresenceEvent(let m):
            eventPipe.putNext(.statusPresence(m))
        case .lastSeenMessageEvent(let m):
            eventPipe.putNext(.lastSeen(m))
        case .lastPinMessageEvent(let m):
            eventPipe.putNext(.lastPin(m))
        case .unpinMessageEvent(let m):
            eventPipe.putNext(.unpinMessage(m))
        case .messageButtonClicked(let m):
            eventPipe.putNext(.messageButton(m))
        case .channelCreatedEvent(let m):
            eventPipe.putNext(.channelCreated(m))
        case .channelDeletedEvent(let m):
            eventPipe.putNext(.channelDeleted(m))
        case .channelUpdatedEvent(let m):
            eventPipe.putNext(.channelUpdated(m))
        case .categoryEvent(let m):
            eventPipe.putNext(.categoryEvent(m))
        case .notiUserChannel(let m):
            eventPipe.putNext(.notiUserChannel(m))
        case .userChannelAddedEvent(let m):
            eventPipe.putNext(.userChannelAdded(m))
        case .userChannelRemovedEvent(let m):
            eventPipe.putNext(.userChannelRemoved(m))
        case .unmuteEvent(let m):
            eventPipe.putNext(.markAsRead(m))
        case .clanUpdatedEvent(let m):
            eventPipe.putNext(.clanUpdated(m))
        case .clanProfileUpdatedEvent(let m):
            eventPipe.putNext(.clanProfileUpdated(m))
        case .clanDeletedEvent(let m):
            eventPipe.putNext(.clanDeleted(m))
        case .userClanRemovedEvent(let m):
            eventPipe.putNext(.userClanRemoved(m))
        case .addClanUserEvent(let m):
            eventPipe.putNext(.userClanAdded(m))
        case .voiceJoinedEvent(let m):
            eventPipe.putNext(.voiceJoined(m))
        case .voiceLeavedEvent(let m):
            eventPipe.putNext(.voiceLeaved(m))
        case .voiceEndedEvent(let m):
            eventPipe.putNext(.voiceEnded(m))
        case .voiceReactionSend(let m):
            eventPipe.putNext(.voiceReaction(m))
        case .aiagentEnabledEvent(let m):
            eventPipe.putNext(.aiAgentEnabled(m))
        case .streamingJoinedEvent(let m):
            eventPipe.putNext(.streamingJoined(m))
        case .streamingLeavedEvent(let m):
            eventPipe.putNext(.streamingLeaved(m))
        case .webrtcSignalingFwd(let m):
            eventPipe.putNext(.webRTC(m))
        case .incomingCallPush(let m):
            eventPipe.putNext(.incomingCallPush(m))
        case .customStatusEvent(let m):
            eventPipe.putNext(.customStatus(m))
        case .userStatusEvent(let m):
            eventPipe.putNext(.userStatus(m))
        case .userProfileUpdatedEvent(let m):
            eventPipe.putNext(.userProfileUpdated(m))
        case .removeFriend(let m):
            eventPipe.putNext(.removeFriend(m))
        case .blockFriend(let m):
            eventPipe.putNext(.blockFriend(m))
        case .addFriend(let m):
            eventPipe.putNext(.addFriend(m))
        case .tokenSentEvent(let m):
            eventPipe.putNext(.tokenSent(m))
        case .giveCoffeeEvent(let m):
            eventPipe.putNext(.giveCoffee(m))
        case .roleEvent(let m):
            eventPipe.putNext(.roleEvent(m))
        case .roleAssignEvent(let m):
            eventPipe.putNext(.roleAssign(m))
        case .permissionSetEvent(let m):
            eventPipe.putNext(.permissionSet(m))
        case .permissionChangedEvent(let m):
            eventPipe.putNext(.permissionChanged(m))
        case .stickerCreateEvent(let m):
            eventPipe.putNext(.stickerCreated(m))
        case .stickerUpdateEvent(let m):
            eventPipe.putNext(.stickerUpdated(m))
        case .stickerDeleteEvent(let m):
            eventPipe.putNext(.stickerDeleted(m))
        case .eventEmoji(let m):
            eventPipe.putNext(.emojiEvent(m))
        case .canvasEvent(let m):
            eventPipe.putNext(.canvasEvent(m))
        case .webhookEvent(let m):
            eventPipe.putNext(.webhookEvent(m))
        case .sdTopicEvent(let m):
            eventPipe.putNext(.sdTopicEvent(m))
        case .ping:
            var pong = Mezon_Realtime_Envelope()
            pong.pong = Mezon_Realtime_Pong()
            send(pong)
        case .rpc(_):
            break
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts || (tokenProvider != nil && !hasTriedRefreshSinceConnect) else {
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
                    NotificationCenter.default.post(name: Notification.Name("MezonSessionExpired"), object: nil)
                    return
                }
            } catch {
            }
        }
        guard let token = tokenToUse else {
            return
        }
        connect(token: token, wsHostOverride: wsHostOverride)
        eventPipe.putNext(.reconnected)
    }

    func forwardWebrtcSignaling(
        receiverId: Int64,
        dataType: Int32,
        jsonData: String,
        channelId: Int64,
        callerId: Int64
    ) {
        var fwd = Mezon_Realtime_WebrtcSignalingFwd()
        fwd.receiverID = receiverId
        fwd.dataType = dataType
        fwd.jsonData = jsonData
        fwd.channelID = channelId
        fwd.callerID = callerId
        var envelope = Mezon_Realtime_Envelope()
        envelope.webrtcSignalingFwd = fwd
        send(envelope)
    }

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
    }

    func sendMessageButtonClicked(
        messageId: Int64,
        channelId: Int64,
        buttonId: String,
        senderId: Int64,
        userId: Int64,
        extraData: String
    ) {
        var btn = Mezon_Realtime_MessageButtonClicked()
        btn.messageID = messageId
        btn.channelID = channelId
        btn.buttonID = buttonId
        btn.senderID = senderId
        btn.userID = userId
        btn.extraData = extraData
        var envelope = Mezon_Realtime_Envelope()
        envelope.messageButtonClicked = btn
        send(envelope)
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
            self.eventPipe.putNext(.connected)
            NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": true])
            self.flushPendingSendQueue()
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
            // Drop the dead task so the connect() dedupe guard knows the
            // socket really needs to be rebuilt next time.
            self.webSocketTask = nil
            NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
            self.eventPipe.putNext(.disconnected)

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
