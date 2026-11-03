import Foundation
import UserNotifications

// Shared by the app's duplicate cleanup and the notification service extension.
enum CallStartNotificationPolicy {
    static let missedCallCategory = "MEZON_MISSED_CALL"

    private static let startBodies: Set<String> = [
        "Started voice call", "Started video call", "Đã bắt đầu cuộc gọi thoại", "Đã bắt đầu cuộc gọi video",
        "Тавышлы шалтырату башлады", "Видео-шалтырату башлады", "Inició llamada de voz", "Inició llamada de video",
        "Rozpoczęto połączenie głosowe", "Rozpoczęto połączenie wideo", "Stembellen is gestart", "Videobellen is gestart",
        "음성 통화 시작", "영상 통화 시작", "Appel vocal commencé", "Appel vidéo commencé",
        "Chamada de voz iniciada", "Chamada de vídeo iniciada", "Sprachanruf gestartet", "Videoanruf gestartet",
        "Пачаты галасавы званок", "Пачаты відэазванок", "音声通話を開始しました", "ビデオ通話を開始しました",
        "Avviata chiamata vocale", "Avviata videochiamata", "Började röstsamtal", "Började videosamtal",
        "Начал голосовой вызов", "Начал видео-звонок", "Розпочато голосовий дзвінок", "Розпочато відеодзвінок",
    ]

    static func isCallStart(_ request: UNNotificationRequest) -> Bool {
        let content = request.content
        let info = payload(content)
        guard content.categoryIdentifier != missedCallCategory,
              !request.identifier.hasPrefix("mezon.missed-call."),
              info["notification_type"] as? String != "missed_call" else { return false }
        let message = dictionary(info["message"])
        let structured = dictionary(message?["content"] ?? info["content"])
            ?? (message?["callLog"] != nil ? message : nil)
        if let structured {
            return int64(dictionary(structured["callLog"])?["callLogType"]) == 1
        }
        // Legacy FCM carries only message ID/body. Cleanup additionally requires a received VoIP call.
        let body = content.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return startBodies.contains(body)
            || [" started a audio call", " started an audio call", " started a video call"].contains { suffix in
                guard body.hasSuffix(suffix) else { return false }
                let username = body.dropLast(suffix.count)
                return !username.isEmpty && !username.contains(where: { $0.isWhitespace })
            }
    }

    static func matchesSource(_ content: UNNotificationContent, channelId: Int64, callerId: Int64, receiverId: Int64) -> Bool {
        let info = payload(content)
        guard int64(info["channel"] ?? info["channelId"]) == channelId,
              int64(info["sender"] ?? info["senderId"]) == callerId else { return false }
        if let recipient = int64(info["recipient"]), receiverId != 0, recipient != receiverId { return false }
        return true
    }

    @discardableResult
    static func silenceIfNeeded(_ request: UNNotificationRequest, content: UNMutableNotificationContent) -> Bool {
        let info = payload(content)
        guard isCallStart(request), isDirectMessage(info),
              let channel = int64(info["channel"] ?? info["channelId"]), channel != 0,
              let sender = int64(info["sender"] ?? info["senderId"]), sender != 0 else { return false }
        // Apply before avatar work, including when FCM arrives before the VoIP push.
        content.sound = nil
        if #available(iOS 15.0, *) { content.interruptionLevel = .passive }
        return true
    }

    private static func isDirectMessage(_ info: [AnyHashable: Any]) -> Bool {
        if let link = info["link"] as? String, let url = URL(string: link),
           url.path.contains("/chat/direct/message/") {
            return url.pathComponents.last == "3"
        }
        return int64(info["mode"]) == 4 || int64(info["channel_type"]) == 3
    }

    private static func payload(_ content: UNNotificationContent) -> [AnyHashable: Any] {
        dictionary(content.userInfo["data"]) ?? content.userInfo
    }

    private static func dictionary(_ value: Any?) -> [AnyHashable: Any]? {
        if let value = value as? [AnyHashable: Any] { return value }
        guard let raw = value as? String, let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [AnyHashable: Any]
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? String { return Int64(value) }
        return (value as? NSNumber)?.int64Value
    }
}
