import UIKit
import UserNotifications

enum NotificationReplySender {

    private struct Target {
        let clanId: Int64
        let channelId: Int64
        let mode: Int32
        let isPublic: Bool
        let topicId: Int64
    }

    private enum ReplyError: Error {
        case notLoggedIn
        case missingChannel
        case emptyAck
    }

    private final class BackgroundTaskLease {
        private var id: UIBackgroundTaskIdentifier = .invalid

        init(name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                self?.end()
            }
        }

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    @MainActor
    static func send(text: String, notification: UNNotification, accountContext: AccountContext?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userInfo = notification.request.content.userInfo
        let lease = BackgroundTaskLease(name: "mezon.notification.reply")
        defer { lease.end() }

        var stage = "token"
        do {
            guard let token = await resolveToken(accountContext: accountContext) else {
                throw ReplyError.notLoggedIn
            }
            stage = "target"
            let target = try await resolveTarget(userInfo: userInfo, token: token)
            stage = "send"
            let ack = try await MezonHTTPClient.shared.sendChannelMessage(
                clanId: target.clanId,
                channelId: target.channelId,
                mode: target.mode,
                isPublic: target.isPublic,
                content: contentJSON(for: trimmed),
                avatar: accountContext?.currentUser?.avatarURL?.absoluteString ?? "",
                topicId: target.topicId,
                token: token
            )
            guard ack.messageID > 0 else { throw ReplyError.emptyAck }
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "NotificationReplySender.send",
                "stage": stage,
                "channel": AppDelegate.pushPayloadString(userInfo, keys: ["channel"]) ?? "",
                "link": AppDelegate.pushPayloadString(userInfo, keys: ["link"]) ?? ""
            ])
            await postFailureNotification(for: notification)
        }
    }

    @MainActor
    private static func resolveToken(accountContext: AccountContext?) async -> String? {
        if let accountContext, accountContext.isLoggedIn {
            return await accountContext.getTokenPreferringCachedSkipSessionReadyWait()
        }
        guard let saved = SessionStore.load(), !saved.token.isEmpty else { return nil }
        if !saved.isExpired { return saved.token }
        guard let refreshed = try? await SessionRefreshManager.shared.refresh(session: saved) else { return nil }
        SessionStore.save(refreshed)
        return refreshed.token
    }

    private static func resolveTarget(userInfo: [AnyHashable: Any], token: String) async throws -> Target {
        let routed = AppDelegate.parseFCMPayload(userInfo)
        guard let channelIdRaw = routed.channelId,
              let channelId = Int64(channelIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)),
              channelId != 0 else {
            throw ReplyError.missingChannel
        }
        let topicId = AppDelegate.pushPayloadInt64(userInfo, keys: ["topic", "topic_id", "topicId"]) ?? 0
        let clanId = routed.clanId.flatMap { Int64($0) } ?? 0

        if let cached = Postbox.shared.resolvedChannelDescription(clanId: clanId, channelId: channelId),
           cached.type != 0 {
            return target(from: cached, topicId: topicId)
        }

        if routed.isDM || clanId == 0 {
            let link = AppDelegate.pushPayloadString(userInfo, keys: ["link"]) ?? ""
            return Target(
                clanId: 0,
                channelId: channelId,
                mode: directMessageMode(fromLink: link),
                isPublic: false,
                topicId: topicId
            )
        }

        let descs = try await MezonHTTPClient.shared.listChannelDescs(clanId: clanId, token: token)
        guard let desc = descs.first(where: { $0.channelID == channelId }) else {
            throw ReplyError.missingChannel
        }
        return target(from: desc, topicId: topicId)
    }

    private static func target(from channel: Mezon_Api_ChannelDescription, topicId: Int64) -> Target {
        let isDM = channel.type == MezonConstants.ChannelType.dm.rawValue
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let clanId: Int64 = isDM || isGroup ? 0 : channel.clanID
        let mode: Int32
        if isThread {
            mode = MezonConstants.ChannelStreamMode.thread.rawValue
        } else if isDM {
            mode = MezonConstants.ChannelStreamMode.dm.rawValue
        } else if isGroup {
            mode = MezonConstants.ChannelStreamMode.group.rawValue
        } else {
            mode = clanId == 0
                ? MezonConstants.ChannelStreamMode.group.rawValue
                : MezonConstants.ChannelStreamMode.channel.rawValue
        }
        return Target(
            clanId: clanId,
            channelId: channel.channelID,
            mode: mode,
            isPublic: channel.channelPrivate == 0,
            topicId: topicId
        )
    }

    private static func directMessageMode(fromLink link: String) -> Int32 {
        let dm = MezonConstants.ChannelStreamMode.dm.rawValue
        let group = MezonConstants.ChannelStreamMode.group.rawValue
        guard let url = URL(string: link),
              let last = url.pathComponents.last,
              let encoded = Int32(last) else {
            return dm
        }
        let mode = encoded + 1
        return mode == group ? group : dm
    }

    private static func contentJSON(for text: String) -> String {
        let built = ComposerContentPayloadBuilder.build(rawInput: text, emojiIdByColon: [:])
        var content: [String: Any] = ["t": built.displayText]
        if !built.mk.isEmpty {
            content["mk"] = built.mk
        }
        if !built.ej.isEmpty {
            content["ej"] = built.ej
        }
        guard let data = try? JSONSerialization.data(withJSONObject: content),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func postFailureNotification(for notification: UNNotification) async {
        let original = notification.request.content
        let content = UNMutableNotificationContent()
        content.title = original.title
        content.body = L(L10n.NotificationActions.replyFailed)
        content.userInfo = original.userInfo
        content.threadIdentifier = original.threadIdentifier
        content.categoryIdentifier = MessageNotificationCategory.identifier
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "mezon.notification.reply.failed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
