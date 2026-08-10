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
    case unBlockFriend(Mezon_Realtime_UnblockFriend)
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
    case topicInMessage(Mezon_Realtime_TopicInMessageEvent)

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
    private let maxReconnectDelaySeconds = 30
    private var backgroundedAt: Date?
    private let suspendedSocketDistrustSeconds: TimeInterval = 15
    private let stableReconnectResetNanoseconds: UInt64 = 10_000_000_000
    private var stableReconnectResetTask: Task<Void, Never>?
    private var pendingSendQueue: [(envelope: Mezon_Realtime_Envelope, queuedAt: Date)] = []
    private let pendingSendQueueCap = 32
    private let pendingSendStaleAge: TimeInterval = 10

    private var nextCid: UInt32 = 0
    private var pendingApiRequests: [UInt32: PendingApiRequest] = [:]
    private var apiResponseStreams: [UInt32: Data] = [:]
    private let defaultApiRequestTimeoutNanos: UInt64 = 10_000_000_000

    private var consecutiveApiTimeouts = 0
    private let apiDegradeThreshold = 1
    private let apiDegradeCooldown: TimeInterval = 12
    private var apiDegradedUntil: Date?

    var isApiTransportDegraded: Bool {
        guard let until = apiDegradedUntil else { return false }
        if Date() >= until {
            apiDegradedUntil = nil
            consecutiveApiTimeouts = 0
            return false
        }
        return true
    }

    func noteApiRequestSucceeded() {
        consecutiveApiTimeouts = 0
        apiDegradedUntil = nil
    }

    func noteApiRequestTimedOut() {
        consecutiveApiTimeouts += 1
        if consecutiveApiTimeouts >= apiDegradeThreshold {
            apiDegradedUntil = Date().addingTimeInterval(apiDegradeCooldown)
        }
        probeConnectionLiveness()
    }

    private func probeConnectionLiveness() {
        guard isConnected, livenessProbeTask == nil, let task = webSocketTask else { return }
        pendingLivenessProbe = task
        task.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.pendingLivenessProbe === task else { return }
                self.pendingLivenessProbe = nil
                self.livenessProbeTask?.cancel()
                self.livenessProbeTask = nil
                guard let error else { return }
                self.handleTransportFailure(error, for: task)
            }
        }
        let deadlineNanos = UInt64(livenessProbeTimeoutSeconds * 1_000_000_000)
        livenessProbeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: deadlineNanos)
            guard !Task.isCancelled, let self, self.pendingLivenessProbe === task else { return }
            self.pendingLivenessProbe = nil
            self.livenessProbeTask = nil
            MezonRPCLog.response("ws liveness probe timed out after \(self.livenessProbeTimeoutSeconds)s → treating socket as dead")
            self.handleTransportFailure(MezonError.socketError("WebSocket ping timed out"), for: task)
        }
    }

    private func cancelLivenessProbe() {
        livenessProbeTask?.cancel()
        livenessProbeTask = nil
        pendingLivenessProbe = nil
    }

    private let heartbeatIntervalSeconds: TimeInterval = 8
    private var heartbeatPongTimeoutSeconds: TimeInterval { heartbeatIntervalSeconds * 3 }
    private var heartbeatTask: Task<Void, Never>?
    private var lastPongAt: Date?
    private var lastPingSentAt: Date?
    private let livenessProbeTimeoutSeconds: TimeInterval = 5
    private var livenessProbeTask: Task<Void, Never>?
    private var pendingLivenessProbe: URLSessionWebSocketTask?

    private struct PendingApiRequest {
        let apiName: String
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    var tokenProvider: (() async throws -> String)?

    private var reconnectWorkItem: DispatchWorkItem?
    private var connectWatchdog: DispatchWorkItem?
    private let connectTimeoutSeconds: TimeInterval = 10

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NetworkMonitor.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard (note.userInfo?["isConnected"] as? Bool) == true else { return }
            Task { @MainActor in
                self?.handleNetworkBecameReachable()
            }
        }
    }

    func connect(token: String, wsHostOverride: String? = nil, resetReconnectState: Bool = true) {
        if self.token == token, self.wsHostOverride == wsHostOverride,
           webSocketTask != nil {
            return
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stableReconnectResetTask?.cancel()
        stableReconnectResetTask = nil
        if let old = webSocketTask {
            old.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
        }
        urlSession?.invalidateAndCancel()

        self.token = token
        self.wsHostOverride = wsHostOverride
        if resetReconnectState {
            reconnectAttempts = 0
        }

        let url = MezonConfig.wsURL(token: token, wsHostOverride: wsHostOverride)
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveLoop()
        armConnectWatchdog(for: webSocketTask)
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
        stableReconnectResetTask?.cancel()
        stableReconnectResetTask = nil
        stopHeartbeat()
        cancelLivenessProbe()
        cancelConnectWatchdog()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        token = nil
        wsHostOverride = nil
        isConnected = false
        NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
        reconnectAttempts = 0
        tokenProvider = nil
        pendingSendQueue.removeAll()
        failAllPendingApiRequests(reason: "WebSocket disconnected")
    }

    func reconnectFromForeground() {
        backgroundedAt = nil
        forceReconnect()
    }

    private func forceReconnect() {
        guard token != nil || tokenProvider != nil else {
            return
        }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempts = 0
        cleanupForReconnect()
        Task { @MainActor in
            await performReconnect(useTokenRefresh: tokenProvider != nil)
        }
    }

    private func handleNetworkBecameReachable() {
        guard !isConnected else { return }
        forceReconnect()
    }

    func ensureFreshConnection() {
        guard token != nil || tokenProvider != nil else { return }
        guard isConnected else {
            if reconnectWorkItem == nil, webSocketTask == nil {
                forceReconnect()
            }
            return
        }
        probeConnectionLiveness()
    }

    func noteEnteredBackground() {
        backgroundedAt = Date()
    }

    func noteWillEnterForeground() {
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        guard Date().timeIntervalSince(since) >= suspendedSocketDistrustSeconds else { return }
        reconnectFromForeground()
    }

    private func cleanupForReconnect() {
        isConnected = false
        cancelConnectWatchdog()
        NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
        stableReconnectResetTask?.cancel()
        stableReconnectResetTask = nil
        stopHeartbeat()
        cancelLivenessProbe()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        failAllPendingApiRequests(reason: "WebSocket reconnecting")
    }

    func send(_ envelope: Mezon_Realtime_Envelope) {
        guard isConnected, let task = webSocketTask else {
            enqueuePendingSend(envelope)
            return
        }
        guard let data = try? envelope.serializedData() else { return }
        task.send(.data(data)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.handleTransportFailure(error, for: task)
            }
        }
    }

    func sendApiRequest(
        apiName: String,
        body: Data,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> Data {
        guard isConnected, let task = webSocketTask else {
            throw MezonError.socketError("WebSocket is not connected")
        }

        let cid = generateCid()
        var apiReq = Mezon_Realtime_ApiRequestEvent()
        apiReq.apiName = apiName
        apiReq.apiIndex = MezonApiNameRegistry.index(of: apiName)
        apiReq.body = body
        var envelope = Mezon_Realtime_Envelope()
        envelope.cid = Int32(bitPattern: cid)
        envelope.apiRequestEvent = apiReq

        let payload: Data
        do {
            payload = try envelope.serializedData()
        } catch {
            throw MezonError.socketError("Encode api_request_event failed: \(error.localizedDescription)")
        }

        let timeoutNs = timeoutNanoseconds ?? defaultApiRequestTimeoutNanos

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let timeoutTask = Task { @MainActor [weak self] in
                let step: UInt64 = 50_000_000
                var elapsed: UInt64 = 0
                while elapsed < timeoutNs {
                    try? await Task.sleep(nanoseconds: step)
                    if Task.isCancelled { return }
                    elapsed += step
                }
                guard let self else { return }
                if let pending = self.pendingApiRequests.removeValue(forKey: cid) {
                    self.apiResponseStreams.removeValue(forKey: cid)
                    pending.continuation.resume(
                        throwing: MezonError.socketError(
                            "api_request_event '\(apiName)' timed out after \(timeoutNs / 1_000_000)ms"
                        )
                    )
                }
            }

            pendingApiRequests[cid] = PendingApiRequest(
                apiName: apiName,
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            task.send(.data(payload)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if let pending = self.pendingApiRequests.removeValue(forKey: cid) {
                        self.apiResponseStreams.removeValue(forKey: cid)
                        pending.timeoutTask.cancel()
                        pending.continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func generateCid() -> UInt32 {
        nextCid &+= 1
        if nextCid == 0 || nextCid > 0xFFFF {
            nextCid = 1
        }
        return nextCid
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        lastPongAt = Date()
        let intervalNs = UInt64(heartbeatIntervalSeconds * 1_000_000_000)
        MezonRPCLog.response("[ping-pong] heartbeat started (interval=\(Int(heartbeatIntervalSeconds))s, pongTimeout=\(Int(heartbeatPongTimeoutSeconds))s)")
        heartbeatTask = Task { @MainActor [weak self] in
            while true {
                guard let self else { return }
                guard self.isConnected, let task = self.webSocketTask else { return }

                if let last = self.lastPongAt,
                   Date().timeIntervalSince(last) > self.heartbeatPongTimeoutSeconds {
                    MezonRPCLog.response("[ping-pong] pong timeout: no pong for \(Int(Date().timeIntervalSince(last)))s → treating socket as dead, reconnecting")
                    self.handleTransportFailure(MezonError.socketError("Heartbeat pong timeout"), for: task)
                    return
                }

                var envelope = Mezon_Realtime_Envelope()
                envelope.ping = Mezon_Realtime_Ping()
                if let data = try? envelope.serializedData() {
                    self.lastPingSentAt = Date()
                    task.send(.data(data)) { [weak self] error in
                        guard let error else { return }
                        Task { @MainActor in
                            MezonRPCLog.response("[ping-pong] ping send failed: \(error.localizedDescription) → reconnecting")
                            self?.handleTransportFailure(error, for: task)
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: intervalNs)
                if Task.isCancelled { return }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func failAllPendingApiRequests(reason: String) {
        let snapshot = pendingApiRequests
        pendingApiRequests.removeAll()
        apiResponseStreams.removeAll()
        for (_, pending) in snapshot {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: MezonError.socketError(reason))
        }
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
        guard let task = webSocketTask else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard self.webSocketTask === task else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveLoop()
                case .failure(let error):
                    let nsErr = error as NSError
                    MezonRPCLog.response("ws receive-fail domain=\(nsErr.domain) code=\(nsErr.code) desc='\(nsErr.localizedDescription)' pendingRpc=\(self.pendingApiRequests.count)")
                    self.handleTransportFailure(error, for: task)
                }
            }
        }
    }

    private func handleTransportFailure(_ error: Error, for task: URLSessionWebSocketTask) {
        guard webSocketTask === task else { return }
        cleanupForReconnect()
        eventPipe.putNext(.error(error))
        scheduleReconnect()
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            if let first = data.first, first == 0xFF {
                handleFramedApiResponse(data)
                return
            }
            decodeEnvelope(data)
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

    private func handleFramedApiResponse(_ data: Data) {
        let headerLength = 7
        guard data.count >= headerLength else {
            MezonRPCLog.response("frame drop: too small bytes=\(data.count)")
            return
        }
        let bytes = [UInt8](data)
        let cid: UInt32 = (UInt32(bytes[1]) << 8) | UInt32(bytes[2])
        let statusWord: UInt32 =
            (UInt32(bytes[3]) << 24) |
            (UInt32(bytes[4]) << 16) |
            (UInt32(bytes[5]) << 8)  |
            UInt32(bytes[6])
        let responseCode = (statusWord >> 16) & 0xFFFF
        let finFlag = statusWord & 0xFFFF
        let payload = data.count > headerLength
            ? data.subdata(in: headerLength..<data.count)
            : Data()

        var buffer = apiResponseStreams[cid] ?? Data()
        if !payload.isEmpty {
            buffer.append(payload)
        }

        if finFlag == 0xFF {
            apiResponseStreams.removeValue(forKey: cid)
            guard let pending = pendingApiRequests.removeValue(forKey: cid) else {
                MezonRPCLog.response("frame FIN cid=\(cid) code=\(responseCode) totalBytes=\(buffer.count) (no pending)")
                return
            }
            pending.timeoutTask.cancel()
            if responseCode == 0 {
                pending.continuation.resume(returning: buffer)
            } else {
                let message = String(data: buffer, encoding: .utf8) ?? ""
                MezonRPCLog.response("recv ← cid=\(cid) error code=\(responseCode) bytes=\(buffer.count) msg='\(message.prefix(160))'")
                pending.continuation.resume(
                    throwing: MezonError.httpError(statusCode: Int(responseCode), message: message)
                )
            }
        } else {
            apiResponseStreams[cid] = buffer
        }
    }

    private func serializedPayloadForCompletedApiRequest(
        envelope: Mezon_Realtime_Envelope,
        apiName: String
    ) -> Data? {
        guard let msg = envelope.message else { return nil }
        switch msg {
        case .channelMessageAck(let ack):
            return try? ack.serializedData()
        case .listDataSocket(let wrapper):
            switch apiName {
            case "ListChannelBadgeCount":
                guard wrapper.hasChannelBadgeCount else { return nil }
                return try? wrapper.channelBadgeCount.serializedData()
            case "ListClanBadgeCount":
                guard wrapper.hasClanBadgeCount else { return nil }
                return try? wrapper.clanBadgeCount.serializedData()
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func routeEnvelope(_ envelope: Mezon_Realtime_Envelope) {
        let cid = UInt32(bitPattern: envelope.cid)
        if cid != 0, pendingApiRequests[cid] != nil {
            guard let pending = pendingApiRequests.removeValue(forKey: cid) else { return }
            apiResponseStreams.removeValue(forKey: cid)
            pending.timeoutTask.cancel()
            if case .some(.error(let err)) = envelope.message {
                MezonRPCLog.response("envelope-cid cid=\(cid) error msg='\(err.message)'")
                pending.continuation.resume(
                    throwing: MezonError.socketError(err.message.isEmpty ? "Server error" : err.message)
                )
            } else if let payload = serializedPayloadForCompletedApiRequest(
                envelope: envelope,
                apiName: pending.apiName
            ) {
                pending.continuation.resume(returning: payload)
            } else {
                pending.continuation.resume(returning: Data())
            }
            return
        }

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
        case .unBlockFriend(let m):
            eventPipe.putNext(.unBlockFriend(m))
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
        case .topicInMessageEvent(let m):
            eventPipe.putNext(.topicInMessage(m))
        case .ping:
            MezonRPCLog.response("[ping-pong] ← ping from server, → pong reply")
            var pong = Mezon_Realtime_Envelope()
            pong.pong = Mezon_Realtime_Pong()
            send(pong)
        case .pong:
            let now = Date()
            let rtt = lastPingSentAt.map { Int(now.timeIntervalSince($0) * 1000) } ?? -1
            MezonRPCLog.response("[ping-pong] ← pong received (rtt=\(rtt)ms)")
            lastPongAt = now
        case .rpc(_):
            break
        default:
            break
        }
    }

    private func armConnectWatchdog(for task: URLSessionWebSocketTask?) {
        connectWatchdog?.cancel()
        guard let task else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.isConnected, self.webSocketTask === task else { return }
                MezonRPCLog.response("ws connect watchdog: handshake stalled \(Int(self.connectTimeoutSeconds))s → reconnecting")
                self.handleTransportFailure(MezonError.socketError("WebSocket connect timed out"), for: task)
            }
        }
        connectWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeoutSeconds, execute: work)
    }

    private func cancelConnectWatchdog() {
        connectWatchdog?.cancel()
        connectWatchdog = nil
    }

    private func scheduleReconnect() {
        guard token != nil || tokenProvider != nil else { return }
        guard NetworkMonitor.shared.isConnected else {
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            return
        }
        reconnectAttempts += 1
        let useRefresh = tokenProvider != nil
        let delay = Double(min(reconnectAttempts * 2, maxReconnectDelaySeconds))
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
            } catch is SessionError {
                NotificationCenter.default.post(name: Notification.Name("MezonSessionExpired"), object: nil)
                return
            } catch {
                scheduleReconnect()
                return
            }
        }
        guard let token = tokenToUse else {
            return
        }
        connect(token: token, wsHostOverride: wsHostOverride, resetReconnectState: false)
        eventPipe.putNext(.reconnected)
    }

    private func scheduleStableReconnectReset(for openedTask: URLSessionWebSocketTask) {
        stableReconnectResetTask?.cancel()
        let resetDelay = stableReconnectResetNanoseconds
        stableReconnectResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: resetDelay)
            guard let self,
                  let currentTask = self.webSocketTask,
                  currentTask === openedTask,
                  self.isConnected else {
                return
            }
            self.reconnectAttempts = 0
        }
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
            guard let currentTask = self.webSocketTask, currentTask === webSocketTask else { return }
            self.isConnected = true
            self.cancelConnectWatchdog()
            self.noteApiRequestSucceeded()
            self.scheduleStableReconnectReset(for: currentTask)
            self.eventPipe.putNext(.connected)
            NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": true])
            self.flushPendingSendQueue()
            self.startHeartbeat()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            guard let currentTask = self.webSocketTask, currentTask === webSocketTask else { return }
            self.isConnected = false
            self.cancelConnectWatchdog()
            // Drop the dead task so the connect() dedupe guard knows the
            // socket really needs to be rebuilt next time.
            self.webSocketTask = nil
            NotificationCenter.default.post(name: .mezonSocketStatusChanged, object: nil, userInfo: ["isConnected": false])
            self.eventPipe.putNext(.disconnected)
            self.failAllPendingApiRequests(reason: "WebSocket closed")

            if closeCode != .normalClosure {
                self.scheduleReconnect()
            }
        }
    }
}

enum MezonRPCLog {
    static func response(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[MezonRPC] \(message())")
        #endif
    }
}

enum MezonApiNameRegistry {
    static func index(of apiName: String) -> Int32 {
        if let v = nameToIndex[apiName] { return v }
        return -1
    }

    private static let orderedNames: [String] = [
        "ListChannelDescs",
        "GetAccount",
        "ListClanDescs",
        "ListClanUsers",
        "ListRoles",
        "ListEvents",
        "GetRoleOfUserInTheClan",
        "GetListPermission",
        "ListUserPermissionInChannel",
        "GetNotificationClan",
        "ListMutedChannel",
        "ListStreamingChannelUsers",
        "ListQuickMenuAccess",
        "GetNotificationChannel",
        "ListFriends",
        "EmojiRecentList",
        "GetListEmojisByUserId",
        "ListClanBadgeCount",
        "ListChannelBadgeCount",
        "ListLogedDevice",
        "ListClanUsersStatus",
        "ListChannelApps",
        "GetListFavoriteChannel",
        "ListCategoryDescs",
        "ListOnboarding",
        "GetListStickersByUserId",
        "GetSystemMessageByClanId",
        "GetPinMessagesList",
        "GetChannelCanvasList",
        "ListChannelTimeline",
        "ListChannelMessages",
        "ListActivity",
        "ListChannelByUserId",
        "ListUserClansByUserId",
        "GetUserProfileOnClan",
        "RegistFCMDeviceToken",
        "IsBanned",
        "ListThreadDescs",
        "ListArchivedChannelDescs",
        "ListChannelDetail",
        "GetChannelCategoryNotiSettingsList",
        "ListRoleUsers",
        "ListChannelUsers",
        "ListChannelAttachment",
        "ListChannelVoiceUsers",
        "ListUserOnline",
        "ListNotifications",
        "ListChannelUsersUC",
        "ListWebhookByChannelId",
        "GetPermissionByRoleIdChannelId",
        "ListChannelSetting",
        "ListApps",
        "GetApp",
        "ListForSaleItems",
        "ListClanWebhook",
        "GetUserStatus",
        "ListSdTopic",
        "AddFriends",
        "AddChannelUsers",
        "RegistrationEmail",
        "BlockFriends",
        "UnblockFriends",
        "UploadAttachmentFile",
        "UploadOauthFile",
        "AddRolesChannelDesc",
        "CreateCategoryDesc",
        "CreateChannelDesc",
        "CreateRole",
        "CreateEvent",
        "DeleteRole",
        "DeleteEvent",
        "DeleteRoleChannelDesc",
        "DeleteChannelDesc",
        "CloseDMByChannelId",
        "OpenDMByChannelId",
        "DeleteAccount",
        "DeleteFriends",
        "DeleteCategoryDesc",
        "DeleteNotifications",
        "DeleteClanDesc",
        "UpdateUser",
        "UpdateUserProfileByClan",
        "UpdateClanOrder",
        "RemoveChannelUsers",
        "LeaveThread",
        "ArchiveChannel",
        "LinkSMS",
        "ConfirmLinkMezonOTP",
        "LinkEmail",
        "CreateClanDesc",
        "RemoveClanUsers",
        "BanClanUsers",
        "CreateLinkInviteUser",
        "InviteUser",
        "SetRoleChannelPermission",
        "SetNotificationChannelSetting",
        "SetMuteChannel",
        "SetMuteCategory",
        "SetNotificationClanSetting",
        "SetNotificationCategorySetting",
        "DeleteNotificationCategorySetting",
        "DeleteNotificationChannel",
        "CreatePinMessage",
        "CreateMessage2Inbox",
        "UnlinkMezon",
        "UnlinkEmail",
        "UpdateAccount",
        "UpdateUsername",
        "UpdateCategory",
        "UpdateCategoryOrder",
        "UpdateRoleOrder",
        "UpdateClanDesc",
        "UpdateChannelDesc",
        "UpdateChannelPrivate",
        "UpdateRole",
        "UpdateEvent",
        "SearchMessage",
        "CreateClanEmoji",
        "DeleteByIdClanEmoji",
        "UpdateClanEmojiById",
        "GenerateWebhook",
        "HandleWebhook",
        "UpdateWebhookById",
        "DeleteWebhookById",
        "AddClanSticker",
        "UpdateClanStickerById",
        "DeleteClanStickerById",
        "ChangeChannelCategory",
        "CheckDuplicateName",
        "AddApp",
        "DeleteApp",
        "UpdateApp",
        "AddAppToClan",
        "CreateSystemMessage",
        "UpdateSystemMessage",
        "DeleteSystemMessage",
        "StreamingServerCallback",
        "EditChannelCanvases",
        "GetChannelCanvasDetail",
        "DeleteChannelCanvas",
        "AddChannelFavorite",
        "RemoveChannelFavorite",
        "CreateActiviy",
        "GetPubKeys",
        "PushPubKey",
        "GetChanEncryptionMethod",
        "SetChanEncryptionMethod",
        "GetKeyServer",
        "ListAuditLog",
        "GetOnboardingDetail",
        "CreateOnboarding",
        "UpdateOnboarding",
        "DeleteOnboarding",
        "ListOnboardingStep",
        "UpdateOnboardingStep",
        "GenerateClanWebhook",
        "UpdateClanWebhookById",
        "DeleteClanWebhookById",
        "HandleClanWebhook",
        "UpdateUserStatus",
        "UpdateUserCustomStatus",
        "GetTopicDetail",
        "CreateSdTopic",
        "DeleteSdTopic",
        "CreateExternalMezonMeet",
        "GenerateMeetToken",
        "RemoveParticipantMezonMeet",
        "MuteParticipantMezonMeet",
        "CreateRoomChannelApps",
        "GetMezonOauthClient",
        "DeleteMezonOauthClient",
        "UpdateMezonOauthClient",
        "SearchThread",
        "GenerateHashChannelApps",
        "DeleteUserEvent",
        "AddUserEvent",
        "DeleteQuickMenuAccess",
        "AddQuickMenuAccess",
        "UpdateQuickMenuAccess",
        "TransferOwnership",
        "SendChannelMessage",
        "UpdateChannelMessage",
        "DeleteChannelMessage",
        "ReportMessageAbuse",
        "MessageButtonClick",
        "DropdownBoxSelected",
        "ActiveArchivedThread",
        "UpdateChannelTimeline",
        "AddAgentToChannel",
        "DisconnectAgent",
        "CreateChannelTimeline",
        "DetailChannelTimeline",
        "CreatePoll",
        "VotePoll",
        "ClosePoll",
        "GetPoll",
        "ReactChannelMessage",
        "MultipartUploadAttachmentFileStart",
        "MultipartUploadAttachmentFileFinish",
        "SessionRefresh",
        "SessionLogout",
        "Healthcheck",
        "UnbanClanUsers",
        "ListBannedUsers",
        "GetNotificationCategory",
        "ListRolePermissions",
        "IsFollower",
        "DeletePinMessage",
        "MarkAsRead"
    ]

    private static let nameToIndex: [String: Int32] = {
        var dict: [String: Int32] = [:]
        for (i, name) in orderedNames.enumerated() {
            dict[name] = Int32(i)
        }
        return dict
    }()
}

enum ChannelUnreadBadgeSync {
    static func mergeSocketBadgeRows(
        into channels: inout [Mezon_Api_ChannelDescription],
        badgeRows: [Mezon_Api_ChannelDescription],
        preserveContentAcrossMessageIds: Bool = true
    ) {
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
                let bi = b.lastSentMessage
                let badgeSignalsActivity =
                    bi.timestampSeconds > 0 || !bi.content.isEmpty || bi.id != 0 || bi.senderID != 0
                if badgeSignalsActivity || channels[i].hasLastSentMessage {
                    var inc = bi
                    if channels[i].hasLastSentMessage {
                        let ex = channels[i].lastSentMessage
                        let existingLooksNewer: Bool
                        if ex.id != 0, inc.id != 0 {
                            existingLooksNewer = ex.id > inc.id
                                || (ex.id == inc.id && ex.timestampSeconds > inc.timestampSeconds)
                        } else {
                            existingLooksNewer = ex.timestampSeconds > inc.timestampSeconds
                        }
                        if !preserveContentAcrossMessageIds, existingLooksNewer {
                            inc = ex
                        } else {
                            let isSameMessage = inc.id != 0 && inc.id == ex.id
                            let hasNoNewerIdentity = inc.id == 0
                                && inc.timestampSeconds <= ex.timestampSeconds
                            let canReuseExistingContent = preserveContentAcrossMessageIds
                                || isSameMessage || hasNoNewerIdentity
                            if inc.content.isEmpty, !ex.content.isEmpty,
                               canReuseExistingContent {
                                inc.content = ex.content
                                if inc.senderID == 0 { inc.senderID = ex.senderID }
                                if inc.id == 0 { inc.id = ex.id }
                            }
                            inc.timestampSeconds = max(inc.timestampSeconds, ex.timestampSeconds)
                        }
                    }
                    channels[i].lastSentMessage = inc
                }
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
