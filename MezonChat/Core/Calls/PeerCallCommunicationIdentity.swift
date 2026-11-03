import Foundation
import Intents
import UIKit
import UserNotifications

enum PeerCallCommunicationIdentity {
    static func loadAvatarData(url: String?, completion: @escaping (Data?) -> Void) {
        guard let url, !url.isEmpty else { completion(nil); return }
        if let data = NotificationAvatarStore.data(for: url), UIImage(data: data) != nil {
            completion(data)
            return
        }
        ImageCache.shared.loadAvatar(urlString: ImgproxyURL.iconURL(from: url)) { image in
            let data = image?.pngData()
            if let data { NotificationAvatarStore.store(data, for: url) }
            completion(data)
        }
    }

    @available(iOS 14.0, *)
    static func callIntent(callerId: Int64, name: String, avatarData: Data?) -> INStartCallIntent {
        let caller = INPerson(
            personHandle: INPersonHandle(value: String(callerId), type: .unknown),
            nameComponents: nil, displayName: name,
            image: avatarData.map { INImage(imageData: $0) },
            contactIdentifier: nil, customIdentifier: String(callerId)
        )
        return INStartCallIntent(
            callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown,
            destinationType: .normal, contacts: [caller], callCapability: .audioCall
        )
    }

    static func prepareMissedCallContent(
        _ content: UNMutableNotificationContent, callerId: Int64, name: String,
        avatarURL: String?, callId: String, completion: @escaping (UNNotificationContent) -> Void
    ) {
        guard #available(iOS 15.0, *) else { completion(content); return }
        loadAvatarData(url: avatarURL) { data in
            let intent = callIntent(callerId: callerId, name: name, avatarData: data)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.identifier = "mezon.missed-call.\(callId)"
            interaction.direction = .incoming
            interaction.donate { error in
                if let error { NSLog("[CallKit] Missed call intent donation failed: %@", error.localizedDescription) }
                let updated = (try? content.updating(from: intent)) ?? content
                // Match message notifications: the system image proxy can lag behind intent donation.
                if data != nil, !hasProxiedAvatar(updated) {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        let retry = callIntent(callerId: callerId, name: name, avatarData: data)
                        let retried = (try? content.updating(from: retry)) ?? updated
                        completion(preservingMissedCallContent(retried, original: content))
                    }
                } else {
                    completion(preservingMissedCallContent(updated, original: content))
                }
            }
        }
    }

    @available(iOS 15.0, *)
    private static func preservingMissedCallContent(_ updated: UNNotificationContent, original: UNMutableNotificationContent) -> UNNotificationContent {
        guard let result = updated.mutableCopy() as? UNMutableNotificationContent else { return original }
        result.title = original.title
        result.body = original.body
        result.sound = original.sound
        result.interruptionLevel = original.interruptionLevel
        result.categoryIdentifier = original.categoryIdentifier
        result.threadIdentifier = original.threadIdentifier
        result.userInfo = original.userInfo
        return result
    }

    private static func hasProxiedAvatar(_ content: UNNotificationContent) -> Bool {
        guard let archive = try? NSKeyedArchiver.archivedData(withRootObject: content, requiringSecureCoding: true) else { return true }
        return archive.range(of: Data("intents-remote-image-proxy".utf8)) != nil
    }
}
