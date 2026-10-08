import UserNotifications
import Intents

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let groupId = "group.mezon.mobile"
        if let shared = UserDefaults(suiteName: groupId) {
            let newCount = shared.integer(forKey: "badgeCount") + 1
            shared.set(newCount, forKey: "badgeCount")
            bestAttemptContent.badge = NSNumber(value: newCount)
            if Date().timeIntervalSince1970 < shared.double(forKey: Self.notificationsMutedUntilKey) {
                silence(bestAttemptContent)
            }
        }

        let userInfo = bestAttemptContent.userInfo
        let replyable = isReplyableMessage(userInfo)
        if replyable {
            bestAttemptContent.categoryIdentifier = Self.messageCategoryIdentifier
        }

        guard replyable, #available(iOS 15.0, *) else {
            contentHandler(bestAttemptContent)
            return
        }

        if let avatarURLString = findAvatarURL(in: userInfo),
           let avatarURL = URL(string: avatarURLString) {
            if let sharedAvatar = NotificationAvatarStore.data(for: avatarURLString) {
                communicationContent(from: bestAttemptContent, avatarData: sharedAvatar, completion: contentHandler)
                return
            }
            downloadImageData(from: avatarURL, attempts: Self.avatarDownloadAttempts) { [weak self] data in
                guard let self else {
                    contentHandler(bestAttemptContent)
                    return
                }
                if let data {
                    NotificationAvatarStore.store(data, for: avatarURLString)
                }
                self.communicationContent(from: bestAttemptContent, avatarData: data, completion: contentHandler)
            }
        } else {
            communicationContent(from: bestAttemptContent, avatarData: nil, completion: contentHandler)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private static let messageCategoryIdentifier = "MEZON_MESSAGE"
    private static let notificationsMutedUntilKey = "notificationsMutedUntil"
    private static let avatarDownloadAttempts = 2
    private static let avatarRetryDelay: TimeInterval = 1

    private func silence(_ content: UNMutableNotificationContent) {
        content.sound = nil
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
        }
    }

    private func isReplyableMessage(_ userInfo: [AnyHashable: Any]) -> Bool {
        if let e2ee = userInfo["e2ee"] as? String, e2ee.lowercased() == "true" { return false }
        guard let channel = userInfo["channel"] as? String,
              let channelId = Int64(channel), channelId != 0 else { return false }
        guard let link = (userInfo["link"] as? String)?.lowercased() else { return false }
        return link.contains("/chat/direct/message/") || link.contains("/channels/")
    }

    @available(iOS 15.0, *)
    private func communicationContent(from content: UNMutableNotificationContent, avatarData: Data?, completion: @escaping (UNNotificationContent) -> Void) {
        let userInfo = content.userInfo
        let senderId = (userInfo["sender"] as? String).flatMap { $0 == "0" ? nil : $0 }
        let channelId = (userInfo["channel"] as? String) ?? content.threadIdentifier
        let senderName = content.title.isEmpty ? "Mezon" : content.title

        let sender = INPerson(
            personHandle: INPersonHandle(value: senderId ?? channelId, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: avatarData.map { INImage(imageData: $0) },
            contactIdentifier: nil,
            customIdentifier: senderId ?? channelId
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: channelId,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { _ in
            do {
                let updated = try content.updating(from: intent)
                guard content.interruptionLevel == .passive,
                      let silenced = updated.mutableCopy() as? UNMutableNotificationContent else {
                    completion(updated)
                    return
                }
                self.silence(silenced)
                completion(silenced)
            } catch {
                completion(content)
            }
        }
    }

    private func findAvatarURL(in userInfo: [AnyHashable: Any]) -> String? {
        if let url = userInfo["image"] as? String, !url.isEmpty { return url }
        if let url = userInfo["avatar"] as? String, !url.isEmpty { return url }
        if let opts = userInfo["fcm_options"] as? [String: Any],
           let url = opts["image"] as? String, !url.isEmpty { return url }
        return nil
    }

    private func downloadImageData(from url: URL, attempts: Int, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data, !data.isEmpty else {
                guard attempts > 1 else {
                    completion(nil)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.avatarRetryDelay) {
                    self.downloadImageData(from: url, attempts: attempts - 1, completion: completion)
                }
                return
            }
            completion(data)
        }
        task.resume()
    }
}
