import UserNotifications
import Intents
import ImageIO

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
           let avatarURL = URL(string: AvatarProxyURL.normalized(avatarURLString)) {
            if let sharedAvatar = NotificationAvatarStore.data(for: avatarURLString).flatMap(Self.normalizedAvatarPNG) {
                communicationContent(from: bestAttemptContent, avatarData: sharedAvatar, completion: contentHandler)
                return
            }
            downloadImageData(from: avatarURL, attempts: Self.avatarDownloadAttempts) { [weak self] data in
                guard let self else {
                    contentHandler(bestAttemptContent)
                    return
                }
                let avatar = data.flatMap(Self.normalizedAvatarPNG)
                if let avatar {
                    NotificationAvatarStore.store(avatar, for: avatarURLString)
                }
                self.communicationContent(from: bestAttemptContent, avatarData: avatar, completion: contentHandler)
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
    private static let avatarProxyRetryDelay: TimeInterval = 0.5
    private static let avatarMaxPixelSize = 100
    private static let proxiedImageScheme = "intents-remote-image-proxy"
    private static let avatarSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

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
        let intent = sendMessageIntent(for: content, avatarData: avatarData)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { _ in
            guard let updated = try? content.updating(from: intent) else {
                completion(content)
                return
            }
            guard avatarData != nil, !Self.hasProxiedAvatar(updated) else {
                self.deliver(updated, original: content, completion: completion)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.avatarProxyRetryDelay) {
                let retryIntent = self.sendMessageIntent(for: content, avatarData: avatarData)
                let retried = (try? content.updating(from: retryIntent)) ?? updated
                self.deliver(retried, original: content, completion: completion)
            }
        }
    }

    @available(iOS 15.0, *)
    private func sendMessageIntent(for content: UNMutableNotificationContent, avatarData: Data?) -> INSendMessageIntent {
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

        return INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: channelId,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
    }

    @available(iOS 15.0, *)
    private func deliver(_ updated: UNNotificationContent, original: UNMutableNotificationContent, completion: (UNNotificationContent) -> Void) {
        guard original.interruptionLevel == .passive,
              let silenced = updated.mutableCopy() as? UNMutableNotificationContent else {
            completion(updated)
            return
        }
        silence(silenced)
        completion(silenced)
    }

    @available(iOS 15.0, *)
    private static func hasProxiedAvatar(_ content: UNNotificationContent) -> Bool {
        guard let archive = try? NSKeyedArchiver.archivedData(withRootObject: content, requiringSecureCoding: true) else {
            return true
        }
        return archive.range(of: Data(proxiedImageScheme.utf8)) != nil
    }

    private static func normalizedAvatarPNG(_ data: Data) -> Data? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: avatarMaxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func findAvatarURL(in userInfo: [AnyHashable: Any]) -> String? {
        if let url = userInfo["image"] as? String, !url.isEmpty { return url }
        if let url = userInfo["avatar"] as? String, !url.isEmpty { return url }
        if let opts = userInfo["fcm_options"] as? [String: Any],
           let url = opts["image"] as? String, !url.isEmpty { return url }
        return nil
    }

    private func downloadImageData(from url: URL, attempts: Int, completion: @escaping (Data?) -> Void) {
        let task = Self.avatarSession.dataTask(with: url) { data, response, error in
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
