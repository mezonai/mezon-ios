import Foundation
import SwiftProtobuf

@MainActor
final class MezonSocket: NSObject {

    static let shared = MezonSocket()

    var onChannelMessage:     ((Mezon_Api_ChannelMessage)                  -> Void)?
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
    var onError:              ((Error) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var token: String?
    private var wsHostOverride: String?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

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
        isConnected = false
        reconnectAttempts = 0
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
                guard nsErr.code != 57 && nsErr.code != NSURLErrorCancelled else { return }
                AppLogger.app.error("MezonSocket receive error: \(error)")
                Task { @MainActor in
                    self.isConnected = false
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
            onChannelMessage?(m)
            print("[Socket] channelMessage clanId=\(m.clanID) channelId=\(m.channelID)")
        case .messageTypingEvent(let m):
            onTyping?(m)
            print("[Socket] typing clanId=\(m.clanID) channelId=\(m.channelID)")
        case .messageReactionEvent(let m):
            onReaction?(m)
            print("[Socket] reaction messageId=\(m.messageID)")
        case .channelPresenceEvent(let m):
            onPresence?(m)
            print("[Socket] channelPresence joins=\(m.joins.count) leaves=\(m.leaves.count)")
        case .notifications(let m):
            m.notifications.forEach { onNotification?($0) }
            print("[Socket] notification count=\(m.notifications.count)")
        case .statusPresenceEvent(let m):
            onStatusPresence?(m)
            print("[Socket] statusPresence joins=\(m.joins.count) leaves=\(m.leaves.count)")
        case .lastSeenMessageEvent(let m):
            onLastSeen?(m)
            print("[Socket] lastSeen channelId=\(m.channelID)")
        case .lastPinMessageEvent(let m):
            onLastPin?(m)
            print("[Socket] lastPin channelId=\(m.channelID)")
        case .unpinMessageEvent(let m):
            onUnpinMessage?(m)
            print("[Socket] unpin channelId=\(m.channelID)")
        case .messageButtonClicked(let m):
            onMessageButton?(m)
            print("[Socket] messageButtonClicked messageId=\(m.messageID)")
        case .channelCreatedEvent(let m):
            onChannelCreated?(m)
            print("[Socket] channelCreated clanId=\(m.clanID) channelId=\(m.channelID)")
        case .channelDeletedEvent(let m):
            onChannelDeleted?(m)
            print("[Socket] channelDeleted clanId=\(m.clanID) channelId=\(m.channelID)")
        case .channelUpdatedEvent(let m):
            onChannelUpdated?(m)
            print("[Socket] channelUpdated channelId=\(m.channelID)")
        case .categoryEvent(let m):
            onCategoryEvent?(m)
            print("[Socket] categoryEvent clanId=\(m.clanID)")
        case .notiUserChannel(let m):
            onNotiUserChannel?(m)
            print("[Socket] notiUserChannel")
        case .userChannelAddedEvent(let m):
            onUserChannelAdded?(m)
            print("[Socket] userChannelAdded clanId=\(m.clanID)")
        case .userChannelRemovedEvent(let m):
            onUserChannelRemoved?(m)
            print("[Socket] userChannelRemoved channelId=\(m.channelID)")
        case .unmuteEvent(let m):
            onMarkAsRead?(m)
            print("[Socket] unmuteEvent channelId=\(m.channelID)")
        case .clanUpdatedEvent(let m):
            onClanUpdated?(m)
            print("[Socket] clanUpdated clanId=\(m.clanID)")
        case .clanProfileUpdatedEvent(let m):
            onClanProfileUpdated?(m)
            print("[Socket] clanProfileUpdated clanId=\(m.clanID)")
        case .clanDeletedEvent(let m):
            onClanDeleted?(m)
            print("[Socket] clanDeleted clanId=\(m.clanID)")
        case .userClanRemovedEvent(let m):
            onUserClanRemoved?(m)
            print("[Socket] userClanRemoved clanId=\(m.clanID)")
        case .addClanUserEvent(let m):
            onUserClanAdded?(m)
            print("[Socket] addClanUser clanId=\(m.clanID)")
        case .voiceJoinedEvent(let m):
            onVoiceJoined?(m)
            print("[Socket] voiceJoined clanId=\(m.clanID)")
        case .voiceLeavedEvent(let m):
            onVoiceLeaved?(m)
            print("[Socket] voiceLeaved clanId=\(m.clanID)")
        case .voiceEndedEvent(let m):
            onVoiceEnded?(m)
            print("[Socket] voiceEnded voiceChannelId=\(m.voiceChannelID)")
        case .streamingJoinedEvent(let m):
            onStreamingJoined?(m)
            print("[Socket] streamingJoined streamingChannelId=\(m.streamingChannelID)")
        case .streamingLeavedEvent(let m):
            onStreamingLeaved?(m)
            print("[Socket] streamingLeaved clanId=\(m.clanID)")
        case .webrtcSignalingFwd(let m):
            onWebRTC?(m)
            print("[Socket] webrtcSignaling receiverId=\(m.receiverID)")
        case .customStatusEvent(let m):
            onCustomStatus?(m)
            print("[Socket] customStatus userId=\(m.userID)")
        case .userStatusEvent(let m):
            onUserStatus?(m)
            print("[Socket] userStatus userId=\(m.userID)")
        case .userProfileUpdatedEvent(let m):
            onUserProfileUpdated?(m)
            print("[Socket] userProfileUpdated userId=\(m.userID)")
        case .removeFriend(let m):
            onRemoveFriend?(m)
            print("[Socket] removeFriend userId=\(m.userID)")
        case .blockFriend(let m):
            onBlockFriend?(m)
            print("[Socket] blockFriend userId=\(m.userID)")
        case .tokenSentEvent(let m):
            onTokenSent?(m)
            print("[Socket] tokenSent amount=\(m.amount)")
        case .giveCoffeeEvent(let m):
            onGiveCoffee?(m)
            print("[Socket] giveCoffee senderId=\(m.senderID)")
        case .roleEvent(let m):
            onRoleEvent?(m)
            print("[Socket] roleEvent userId=\(m.userID)")
        case .roleAssignEvent(let m):
            onRoleAssign?(m)
            print("[Socket] roleAssign clanId=\(m.clanID)")
        case .permissionSetEvent(let m):
            onPermissionSet?(m)
            print("[Socket] permissionSet channelId=\(m.channelID)")
        case .permissionChangedEvent(let m):
            onPermissionChanged?(m)
            print("[Socket] permissionChanged channelId=\(m.channelID)")
        case .stickerCreateEvent(let m):
            onStickerCreated?(m)
            print("[Socket] stickerCreate clanId=\(m.clanID)")
        case .stickerUpdateEvent(let m):
            onStickerUpdated?(m)
            print("[Socket] stickerUpdate stickerID=\(m.stickerID)")
        case .stickerDeleteEvent(let m):
            onStickerDeleted?(m)
            print("[Socket] stickerDelete stickerID=\(m.stickerID)")
        case .eventEmoji(let m):
            onEmojiEvent?(m)
            print("[Socket] emojiEvent clanId=\(m.clanID)")
        case .canvasEvent(let m):
            onCanvasEvent?(m)
            print("[Socket] canvasEvent channelId=\(m.channelID)")
        case .webhookEvent(let m):
            onWebhookEvent?(m)
            print("[Socket] webhookEvent name=\(m.webhookName)")
        case .sdTopicEvent(let m):
            onSdTopicEvent?(m)
            print("[Socket] sdTopicEvent channelId=\(m.channelID)")
        case .ping:
            var pong = Mezon_Realtime_Envelope()
            pong.pong = Mezon_Realtime_Pong()
            send(pong)
            print("[Socket] ping → pong")
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts, let token else { return }
        reconnectAttempts += 1
        let delay = Double(min(reconnectAttempts * 2, 30))
        AppLogger.app.info("MezonSocket reconnecting in \(delay)s (attempt \(self.reconnectAttempts))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect(token: token, wsHostOverride: self?.wsHostOverride)
            self?.onReconnect?()
        }
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
            AppLogger.app.info("MezonSocket connected")
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
        }
    }
}
