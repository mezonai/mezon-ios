import Foundation
import SwiftProtobuf

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
    private var isConnected = false
    private var reconnectAttempts = 0
    private var hasTriedRefreshSinceConnect = false
    private let maxReconnectAttempts = 2

    var tokenProvider: (() async throws -> String)?

    private override init() { super.init() }

    func connect(token: String, wsHostOverride: String? = nil) {
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
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        reconnectAttempts = 0
        hasTriedRefreshSinceConnect = false
        tokenProvider = nil
        onConnected = nil
    }

    func reconnectFromForeground() {
        guard token != nil || tokenProvider != nil else { return }
        reconnectAttempts = 0
        hasTriedRefreshSinceConnect = false
        AppLogger.app.info("MezonSocket reconnecting from foreground")
        Task { @MainActor in
            await performReconnect(useTokenRefresh: tokenProvider != nil)
        }
    }

    private func cleanupForReconnect() {
        isConnected = false
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

    func sendTyping(clanId: Int64, channelId: Int64) {
        var typing = Mezon_Realtime_MessageTypingEvent()
        typing.clanID = clanId
        typing.channelID = channelId
        var envelope = Mezon_Realtime_Envelope()
        envelope.messageTypingEvent = typing
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
            AppLogger.app.info("[MezonSocket] channelMessage clanId=\(m.clanID) channelId=\(m.channelID)")
            onMessageReceived?(m)
        case .messageTypingEvent(let m):
            onTyping?(m)
            AppLogger.app.debug("[MezonSocket] typing clanId=\(m.clanID) channelId=\(m.channelID)")
        case .messageReactionEvent(let m):
            onReaction?(m)
            AppLogger.app.debug("[MezonSocket] reaction messageId=\(m.messageID)")
        case .channelPresenceEvent(let m):
            onPresence?(m)
            AppLogger.app.debug("[MezonSocket] channelPresence joins=\(m.joins.count) leaves=\(m.leaves.count)")
        case .notifications(let m):
            m.notifications.forEach { onNotification?($0) }
            AppLogger.app.debug("[MezonSocket] notification count=\(m.notifications.count)")
        case .statusPresenceEvent(let m):
            onStatusPresence?(m)
            AppLogger.app.debug("[MezonSocket] statusPresence joins=\(m.joins.count) leaves=\(m.leaves.count)")
        case .lastSeenMessageEvent(let m):
            onLastSeen?(m)
            AppLogger.app.debug("[MezonSocket] lastSeen channelId=\(m.channelID)")
        case .lastPinMessageEvent(let m):
            onLastPin?(m)
            AppLogger.app.debug("[MezonSocket] lastPin channelId=\(m.channelID)")
        case .unpinMessageEvent(let m):
            onUnpinMessage?(m)
            AppLogger.app.debug("[MezonSocket] unpin channelId=\(m.channelID)")
        case .messageButtonClicked(let m):
            onMessageButton?(m)
            AppLogger.app.debug("[MezonSocket] messageButtonClicked messageId=\(m.messageID)")
        case .channelCreatedEvent(let m):
            onChannelCreated?(m)
            AppLogger.app.debug("[MezonSocket] channelCreated clanId=\(m.clanID) channelId=\(m.channelID)")
        case .channelDeletedEvent(let m):
            onChannelDeleted?(m)
            AppLogger.app.debug("[MezonSocket] channelDeleted clanId=\(m.clanID) channelId=\(m.channelID)")
        case .channelUpdatedEvent(let m):
            onChannelUpdated?(m)
            AppLogger.app.debug("[MezonSocket] channelUpdated channelId=\(m.channelID)")
        case .categoryEvent(let m):
            onCategoryEvent?(m)
            AppLogger.app.debug("[MezonSocket] categoryEvent clanId=\(m.clanID)")
        case .notiUserChannel(let m):
            onNotiUserChannel?(m)
            AppLogger.app.debug("[MezonSocket] notiUserChannel")
        case .userChannelAddedEvent(let m):
            onUserChannelAdded?(m)
            AppLogger.app.debug("[MezonSocket] userChannelAdded clanId=\(m.clanID)")
        case .userChannelRemovedEvent(let m):
            onUserChannelRemoved?(m)
            AppLogger.app.debug("[MezonSocket] userChannelRemoved channelId=\(m.channelID)")
        case .unmuteEvent(let m):
            onMarkAsRead?(m)
            AppLogger.app.debug("[MezonSocket] unmuteEvent channelId=\(m.channelID)")
        case .clanUpdatedEvent(let m):
            onClanUpdated?(m)
            AppLogger.app.debug("[MezonSocket] clanUpdated clanId=\(m.clanID)")
        case .clanProfileUpdatedEvent(let m):
            onClanProfileUpdated?(m)
            AppLogger.app.debug("[MezonSocket] clanProfileUpdated clanId=\(m.clanID)")
        case .clanDeletedEvent(let m):
            onClanDeleted?(m)
            AppLogger.app.debug("[MezonSocket] clanDeleted clanId=\(m.clanID)")
        case .userClanRemovedEvent(let m):
            onUserClanRemoved?(m)
            AppLogger.app.debug("[MezonSocket] userClanRemoved clanId=\(m.clanID)")
        case .addClanUserEvent(let m):
            onUserClanAdded?(m)
            AppLogger.app.debug("[MezonSocket] addClanUser clanId=\(m.clanID)")
        case .voiceJoinedEvent(let m):
            onVoiceJoined?(m)
            AppLogger.app.debug("[MezonSocket] voiceJoined clanId=\(m.clanID)")
        case .voiceLeavedEvent(let m):
            onVoiceLeaved?(m)
            AppLogger.app.debug("[MezonSocket] voiceLeaved clanId=\(m.clanID)")
        case .voiceEndedEvent(let m):
            onVoiceEnded?(m)
            AppLogger.app.debug("[MezonSocket] voiceEnded voiceChannelId=\(m.voiceChannelID)")
        case .streamingJoinedEvent(let m):
            onStreamingJoined?(m)
            AppLogger.app.debug("[MezonSocket] streamingJoined streamingChannelId=\(m.streamingChannelID)")
        case .streamingLeavedEvent(let m):
            onStreamingLeaved?(m)
            AppLogger.app.debug("[MezonSocket] streamingLeaved clanId=\(m.clanID)")
        case .webrtcSignalingFwd(let m):
            onWebRTC?(m)
            AppLogger.app.debug("[MezonSocket] webrtcSignaling receiverId=\(m.receiverID)")
        case .customStatusEvent(let m):
            onCustomStatus?(m)
            AppLogger.app.debug("[MezonSocket] customStatus userId=\(m.userID)")
        case .userStatusEvent(let m):
            onUserStatus?(m)
            AppLogger.app.debug("[MezonSocket] userStatus userId=\(m.userID)")
        case .userProfileUpdatedEvent(let m):
            onUserProfileUpdated?(m)
            AppLogger.app.debug("[MezonSocket] userProfileUpdated userId=\(m.userID)")
        case .removeFriend(let m):
            onRemoveFriend?(m)
            AppLogger.app.debug("[MezonSocket] removeFriend userId=\(m.userID)")
        case .blockFriend(let m):
            onBlockFriend?(m)
            AppLogger.app.debug("[MezonSocket] blockFriend userId=\(m.userID)")
        case .tokenSentEvent(let m):
            onTokenSent?(m)
            AppLogger.app.debug("[MezonSocket] tokenSent amount=\(m.amount)")
        case .giveCoffeeEvent(let m):
            onGiveCoffee?(m)
            AppLogger.app.debug("[MezonSocket] giveCoffee senderId=\(m.senderID)")
        case .roleEvent(let m):
            onRoleEvent?(m)
            AppLogger.app.debug("[MezonSocket] roleEvent userId=\(m.userID)")
        case .roleAssignEvent(let m):
            onRoleAssign?(m)
            AppLogger.app.debug("[MezonSocket] roleAssign clanId=\(m.clanID)")
        case .permissionSetEvent(let m):
            onPermissionSet?(m)
            AppLogger.app.debug("[MezonSocket] permissionSet channelId=\(m.channelID)")
        case .permissionChangedEvent(let m):
            onPermissionChanged?(m)
            AppLogger.app.debug("[MezonSocket] permissionChanged channelId=\(m.channelID)")
        case .stickerCreateEvent(let m):
            onStickerCreated?(m)
            AppLogger.app.debug("[MezonSocket] stickerCreate clanId=\(m.clanID)")
        case .stickerUpdateEvent(let m):
            onStickerUpdated?(m)
            AppLogger.app.debug("[MezonSocket] stickerUpdate stickerID=\(m.stickerID)")
        case .stickerDeleteEvent(let m):
            onStickerDeleted?(m)
            AppLogger.app.debug("[MezonSocket] stickerDelete stickerID=\(m.stickerID)")
        case .eventEmoji(let m):
            onEmojiEvent?(m)
            AppLogger.app.debug("[MezonSocket] emojiEvent clanId=\(m.clanID)")
        case .canvasEvent(let m):
            onCanvasEvent?(m)
            AppLogger.app.debug("[MezonSocket] canvasEvent channelId=\(m.channelID)")
        case .webhookEvent(let m):
            onWebhookEvent?(m)
            AppLogger.app.debug("[MezonSocket] webhookEvent name=\(m.webhookName)")
        case .sdTopicEvent(let m):
            onSdTopicEvent?(m)
            AppLogger.app.debug("[MezonSocket] sdTopicEvent channelId=\(m.channelID)")
        case .ping:
            var pong = Mezon_Realtime_Envelope()
            pong.pong = Mezon_Realtime_Pong()
            send(pong)
            AppLogger.app.debug("[MezonSocket] ping → pong")
        default:
            break
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
            AppLogger.app.info("MezonSocket reconnecting with refreshed token (attempt \(self.reconnectAttempts))")
        }
        let delay = Double(min(reconnectAttempts * 2, 30))
        AppLogger.app.info("MezonSocket reconnecting in \(delay)s (attempt \(self.reconnectAttempts))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                await self?.performReconnect(useTokenRefresh: useRefresh)
            }
        }
    }

    private func performReconnect(useTokenRefresh: Bool = false) async {
        var tokenToUse = token
        if useTokenRefresh, let provider = tokenProvider {
            do {
                tokenToUse = try await provider()
                reconnectAttempts = 0
                AppLogger.app.info("MezonSocket using fresh token from tokenProvider")
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
            AppLogger.app.info("MezonSocket connected")
            self.onConnected?()
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
            self.onDisconnect?()
            AppLogger.app.info("MezonSocket disconnected (code: \(closeCode.rawValue))")

            if closeCode != .normalClosure {
                self.scheduleReconnect()
            }
        }
    }
}
