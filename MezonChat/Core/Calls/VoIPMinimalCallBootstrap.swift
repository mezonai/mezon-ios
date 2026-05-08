import Darwin
import Foundation
import UIKit

enum VoIPMinimalCallBootstrap {
    private static let minimalChromeKey = "mezon.voip.minimalChromeActive"
    private static let exitAfterPeerCallKey = "mezon.voip.exitProcessAfterPeerCall"
    private static let activeCallUUIDKey = "mezon.voip.activeCallUUID"
    private static let notificationPayloadKey = "mezon.voip.notificationPayload"
    private static let notificationTimestampKey = "mezon.voip.notificationTimestamp"
    private static let payloadValiditySeconds: TimeInterval = 120

    static var isMinimalChromeActive: Bool {
        UserDefaults.standard.bool(forKey: minimalChromeKey)
    }

    static func activateForIncomingVoIPStoredPayload(wantsMinimalChromeAndExitAfterCall: Bool) {
        if wantsMinimalChromeAndExitAfterCall {
            UserDefaults.standard.set(true, forKey: minimalChromeKey)
            UserDefaults.standard.set(true, forKey: exitAfterPeerCallKey)
        } else {
            UserDefaults.standard.set(false, forKey: minimalChromeKey)
            UserDefaults.standard.set(false, forKey: exitAfterPeerCallKey)
        }
    }

    static func clearMinimalChromeFlagOnly() {
        UserDefaults.standard.set(false, forKey: minimalChromeKey)
    }

    static func clearExitAfterPeerCallFlagOnly() {
        UserDefaults.standard.set(false, forKey: exitAfterPeerCallKey)
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
            UserDefaults.standard.set(false, forKey: exitAfterPeerCallKey)
            UserDefaults.standard.synchronize()
        }
    }

    static func consumeExitProcessIfNeeded(deferSeconds: TimeInterval = 0) {
        guard UserDefaults.standard.bool(forKey: exitAfterPeerCallKey) else { return }
        UserDefaults.standard.set(false, forKey: exitAfterPeerCallKey)
        UserDefaults.standard.synchronize()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deferSeconds)) {
            Self.terminateAndRemoveFromSwitcher()
        }
    }

    static func terminateAndRemoveFromSwitcher() {
        releaseLongLivedResourcesBeforeForcedExit()
        let sessions = UIApplication.shared.connectedScenes.map { $0.session }
        for session in sessions {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            Darwin._exit(0)
        }
    }

    private static func releaseLongLivedResourcesBeforeForcedExit() {
        MainActor.assumeIsolated {
            MezonSocket.shared.disconnect()
        }
        NetworkMonitor.shared.stop()
        CallKitManager.shared.tearDownForForcedProcessExit()
    }
}
