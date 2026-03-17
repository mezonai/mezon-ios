import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            // Increment badge count
            let groupId = "group.mezon.mobile"
            if let shared = UserDefaults(suiteName: groupId) {
                let newCount = shared.integer(forKey: "badgeCount") + 1
                shared.set(newCount, forKey: "badgeCount")
                bestAttemptContent.badge = NSNumber(value: newCount)
            }

            // Try to attach image if available
            if let imageURLString = findImageURL(in: bestAttemptContent.userInfo),
               let imageURL = URL(string: imageURLString) {
                downloadImage(from: imageURL) { attachment in
                    if let attachment = attachment {
                        bestAttemptContent.attachments = [attachment]
                    }
                    contentHandler(bestAttemptContent)
                }
            } else {
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func findImageURL(in userInfo: [AnyHashable: Any]) -> String? {
        if let url = userInfo["attachment_link"] as? String, !url.isEmpty { return url }
        if let url = userInfo["avatar"] as? String, !url.isEmpty { return url }
        if let url = userInfo["image"] as? String, !url.isEmpty { return url }
        if let url = userInfo["imageUrl"] as? String, !url.isEmpty { return url }
        if let url = userInfo["image_url"] as? String, !url.isEmpty { return url }
        if let opts = userInfo["fcm_options"] as? [String: Any],
           let url = opts["image"] as? String, !url.isEmpty { return url }
        if let data = userInfo["data"] as? [String: Any],
           let url = data["image"] as? String, !url.isEmpty { return url }
        return nil
    }

    private func downloadImage(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { location, response, error in
            guard error == nil, let location = location else {
                completion(nil)
                return
            }

            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let tmpFile = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + ext)

            do {
                try FileManager.default.moveItem(at: location, to: tmpFile)
                let attachment = try UNNotificationAttachment(identifier: "image", url: tmpFile, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
