import Foundation
import UIKit

enum VoIPMinimalCallBootstrap {
    private static let minimalChromeKey = "mezon.voip.minimalChromeActive"
    private static let activeCallUUIDKey = "mezon.voip.activeCallUUID"
    private static let notificationPayloadKey = "mezon.voip.notificationPayload"
    private static let notificationTimestampKey = "mezon.voip.notificationTimestamp"
    private static let payloadValiditySeconds: TimeInterval = 120

    static var isMinimalChromeActive: Bool {
        UserDefaults.standard.bool(forKey: minimalChromeKey)
    }

    static func activateForIncomingVoIPStoredPayload(wantsMinimalChrome: Bool) {
        UserDefaults.standard.set(wantsMinimalChrome, forKey: minimalChromeKey)
    }

    static func clearMinimalChromeFlagOnly() {
        UserDefaults.standard.set(false, forKey: minimalChromeKey)
    }

    static func reconcileAfterAppColdStartIfNoActiveVoIPCall() {
        let hasUUID = UserDefaults.standard.string(forKey: activeCallUUIDKey) != nil
        let hasPayload = UserDefaults.standard.dictionary(forKey: notificationPayloadKey) != nil
        let payloadFresh: Bool = {
            guard let ts = UserDefaults.standard.object(forKey: notificationTimestampKey) as? Double else {
                return false
            }
            return Date().timeIntervalSince1970 - ts <= payloadValiditySeconds
        }()
        let isOrphan = hasUUID && (!hasPayload || !payloadFresh)
        if !hasUUID || isOrphan {
            UserDefaults.standard.removeObject(forKey: activeCallUUIDKey)
            UserDefaults.standard.removeObject(forKey: notificationPayloadKey)
            UserDefaults.standard.removeObject(forKey: notificationTimestampKey)
            UserDefaults.standard.set(false, forKey: minimalChromeKey)
            UserDefaults.standard.synchronize()
        }
    }
}
