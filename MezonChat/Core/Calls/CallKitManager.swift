import AVFoundation
import CallKit
import Foundation
import LiveKitWebRTC
import PushKit
import UIKit

private final class VoIPPushCompletionGate {
    private var consumed = false
    private let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }

    func consume() {
        guard !consumed else { return }
        consumed = true
        body()
    }
}

final class CallKitManager: NSObject {

    static let shared = CallKitManager()

    private enum DefaultsKeys {
        static let notificationPayload = "mezon.voip.notificationPayload"
        static let activeCallUUID = "mezon.voip.activeCallUUID"
        static let notificationTimestamp = "mezon.voip.notificationTimestamp"
        static let quitSnapshotChannelId = "mezon.voip.quitSnapshot.channelId"
        static let quitSnapshotCallerId = "mezon.voip.quitSnapshot.callerId"
        static let quitSnapshotReceiverId = "mezon.voip.quitSnapshot.receiverId"
    }

    private let pushRegistry = PKPushRegistry(queue: .main)
    private var provider: CXProvider?
    private let callController = CXCallController()
    private let payloadValiditySeconds: TimeInterval = 120

    private(set) var voipToken: String?

    private override init() {
        super.init()
    }

    func configure() {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.isAudioEnabled = false

        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        let config = CXProviderConfiguration(localizedName: "Mezon")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = "ringing.mp3"
        config.includesCallsInRecents = false

        let prov = CXProvider(configuration: config)
        prov.setDelegate(self, queue: nil)
        provider = prov
    }

    func requestEndActiveVoIPCallIfNeeded() {
        guard let uuidString = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: uuidString)
        else { return }
        let action = CXEndCallAction(call: uuid)
        let tx = CXTransaction(action: action)
        callController.request(tx) { error in
            if error != nil {
                Self.clearStoredIncomingPayload(exitIfMinimalFlow: false)
            }
        }
    }

    func endActiveCallAndExitProcessFastIfMinimalFlow() {
        guard VoIPMinimalCallBootstrap.isMinimalChromeActive else { return }
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        requestEndActiveVoIPCallIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Self.clearStoredIncomingPayload(exitIfMinimalFlow: false)
            VoIPMinimalCallBootstrap.terminateAndRemoveFromSwitcher()
        }
    }

    private func hasStoredActiveVoIPCallUUID() -> Bool {
        guard let s = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) else { return false }
        return UUID(uuidString: s) != nil
    }

    func clearVoipQuitSnapshot() {
        Self.clearVoipQuitSnapshotStorage()
    }

    private static func clearVoipQuitSnapshotStorage() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.quitSnapshotChannelId)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.quitSnapshotCallerId)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.quitSnapshotReceiverId)
        UserDefaults.standard.synchronize()
    }

    private static func storeVoipQuitSnapshot(channelId: Int64, callerId: Int64, receiverId: Int64) {
        UserDefaults.standard.set(NSNumber(value: channelId), forKey: DefaultsKeys.quitSnapshotChannelId)
        UserDefaults.standard.set(NSNumber(value: callerId), forKey: DefaultsKeys.quitSnapshotCallerId)
        UserDefaults.standard.set(NSNumber(value: receiverId), forKey: DefaultsKeys.quitSnapshotReceiverId)
        UserDefaults.standard.synchronize()
    }

    private static func readVoipQuitSnapshot() -> (channelId: Int64, callerId: Int64, receiverId: Int64)? {
        guard let ch = UserDefaults.standard.object(forKey: DefaultsKeys.quitSnapshotChannelId) as? NSNumber,
              let ca = UserDefaults.standard.object(forKey: DefaultsKeys.quitSnapshotCallerId) as? NSNumber
        else { return nil }
        let rec = UserDefaults.standard.object(forKey: DefaultsKeys.quitSnapshotReceiverId) as? NSNumber
        let channelId = ch.int64Value
        let callerId = ca.int64Value
        let receiverId = rec?.int64Value ?? 0
        guard channelId != 0, callerId != 0 else { return nil }
        return (channelId, callerId, receiverId)
    }

    private func persistVoipQuitSnapshotFromIncomingPayload(_ info: [AnyHashable: Any]) {
        guard let channelId = int64(info["channelId"]), channelId != 0,
              let callerId = int64(info["callerId"]), callerId != 0 else { return }
        let receiverId = int64(info["receiverId"]) ?? 0
        Self.storeVoipQuitSnapshot(channelId: channelId, callerId: callerId, receiverId: receiverId)
    }

    func invalidateStoredVoIPPayloadOnly() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
    }

    private func forwardQuitToCallerFromStoredVoIPIfNeeded() {
        let channelId: Int64
        let callerId: Int64
        let receiverId: Int64
        if let info = storedUserInfoIfFresh(),
           let payload = IncomingPeerCallPayload(userInfo: info) {
            channelId = payload.channelId
            callerId = payload.callerId
            receiverId = payload.receiverId
        } else if let snap = Self.readVoipQuitSnapshot() {
            channelId = snap.channelId
            callerId = snap.callerId
            receiverId = snap.receiverId
        } else {
            return
        }
        let fallback = receiverId
        guard let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: fallback) else { return }
        guard receiverId == myId || receiverId == 0 else { return }
        Self.clearVoipQuitSnapshotStorage()
        Task { @MainActor in
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: callerId,
                dataType: WebRTCSignalingDataType.sdpQuit,
                jsonData: "",
                channelId: channelId,
                callerId: myId
            )
        }
    }

    private static func clearStoredIncomingPayload(exitIfMinimalFlow: Bool = true) {
        VoIPMinimalCallBootstrap.clearMinimalChromeFlagOnly()
        clearVoipQuitSnapshotStorage()
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.activeCallUUID)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
        if exitIfMinimalFlow {
            VoIPMinimalCallBootstrap.consumeExitProcessIfNeeded(deferSeconds: 0.3)
        } else {
            VoIPMinimalCallBootstrap.clearExitAfterPeerCallFlagOnly()
        }
    }

    private func storeIncomingUserInfo(_ info: [AnyHashable: Any], callUUID: UUID) {
        var dict: [String: Any] = [:]
        for (k, v) in info {
            if let ks = k as? String {
                dict[ks] = v
            }
        }
        UserDefaults.standard.set(dict, forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.set(callUUID.uuidString, forKey: DefaultsKeys.activeCallUUID)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
        let wantsMinimalChromeAndExitAfterCall = UIApplication.shared.applicationState != .active
        VoIPMinimalCallBootstrap.activateForIncomingVoIPStoredPayload(wantsMinimalChromeAndExitAfterCall: wantsMinimalChromeAndExitAfterCall)
        if wantsMinimalChromeAndExitAfterCall {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mezonVoIPMinimalCallChromeActivated, object: nil)
            }
        }
    }

    private func storedUserInfoIfFresh() -> [AnyHashable: Any]? {
        if let ts = UserDefaults.standard.object(forKey: DefaultsKeys.notificationTimestamp) as? Double {
            if Date().timeIntervalSince1970 - ts > payloadValiditySeconds {
                Self.clearStoredIncomingPayload(exitIfMinimalFlow: false)
                return nil
            }
        }
        return UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload)
    }

    private func handleVoIPDictionary(_ payloadDict: [AnyHashable: Any], completion: @escaping () -> Void) {
        guard let offerValue = payloadDict["offer"] else {
            reportAndEndPlaceholderCall(reason: .failed)
            completion()
            return
        }

        guard let inner = parseOfferInner(offerValue) else {
            reportAndEndPlaceholderCall(reason: .failed)
            completion()
            return
        }

        let offerStr = inner["offer"] as? String ?? ""
        if offerStr == "CANCEL_CALL" {
            let hadReportedIncoming = hasStoredActiveVoIPCallUUID()
            requestEndActiveVoIPCallIfNeeded()
            Self.clearStoredIncomingPayload()
            if !hadReportedIncoming {
                reportAndEndPlaceholderCall(reason: .remoteEnded)
            }
            completion()
            return
        }

        guard !offerStr.isEmpty else {
            reportAndEndPlaceholderCall(reason: .failed)
            completion()
            return
        }

        let callerName = inner["callerName"] as? String ?? "Unknown"
        let callerId = int64(inner["callerId"]) ?? 0
        let channelId = int64(inner["channelId"]) ?? 0
        let receiverId = int64(inner["receiverId"]) ?? 0

        guard channelId != 0, callerId != 0 else {
            reportAndEndPlaceholderCall(reason: .failed)
            completion()
            return
        }

        let pushJsonData: String = {
            if let data = try? JSONSerialization.data(withJSONObject: inner, options: []),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return ""
        }()

        let userInfo: [AnyHashable: Any] = [
            "channelId": NSNumber(value: channelId),
            "callerId": NSNumber(value: callerId),
            "receiverId": NSNumber(value: receiverId),
            "compressedOfferFromPush": offerStr,
            "pushJsonData": pushJsonData,
        ]

        let hasVideo = false

        guard let provider else {
            if let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: receiverId) {
                Task { @MainActor in
                    WebRTCCallManager.shared.armIncomingSignalingBufferIfDetached(channelId: channelId, calleeUserId: myId)
                    WebRTCCallManager.shared.prepareIncomingCallFromVoIPUserInfo(userInfo, currentUserId: myId)
                }
            }
            completion()
            return
        }

        if let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: receiverId) {
            Task { @MainActor in
                WebRTCCallManager.shared.armIncomingSignalingBufferIfDetached(channelId: channelId, calleeUserId: myId)
                Self.startConnectivityPreWarm()
                WebRTCCallManager.shared.preWarmIncomingPeerCallIfNeeded(
                    channelId: channelId,
                    callerId: callerId,
                    receiverId: receiverId,
                    currentUserId: myId,
                    compressedOffer: offerStr
                )
            }
        }

        let callUUID = UUID()
        storeIncomingUserInfo(userInfo, callUUID: callUUID)

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerId != 0 ? "\(callerId)" : callerName)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        let gate = VoIPPushCompletionGate(completion)
        provider.reportNewIncomingCall(with: callUUID, update: update) { error in
            if error != nil {
                Self.clearStoredIncomingPayload(exitIfMinimalFlow: false)
            }
            gate.consume()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            gate.consume()
        }
    }

    @MainActor
    private static func startConnectivityPreWarm() {
        if let ctx = VoIPAnswerAccountBridge.context {
            Task { @MainActor in
                _ = await ctx.prepareForVoIPAnswerConnectivity()
            }
        } else if let tok = SessionStore.load()?.token, !MezonSocket.shared.isConnected {
            MezonSocket.shared.connect(token: tok, wsHostOverride: nil)
        }
    }

    private func parseOfferInner(_ offerValue: Any) -> [String: Any]? {
        if let s = offerValue as? String,
           let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if let obj = offerValue as? [String: Any] {
            return obj
        }
        return nil
    }

    private func int64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        if let v = any as? String { return Int64(v) }
        return nil
    }

    private static func resolveLocalUserIdForVoIP(fallbackReceiverId: Int64) -> Int64? {
        if let uidStr = SessionStore.load()?.userId, let v = Int64(uidStr), v != 0 {
            return v
        }
        if fallbackReceiverId != 0 {
            return fallbackReceiverId
        }
        return nil
    }

    private func reportAndEndPlaceholderCall(reason: CXCallEndedReason) {
        guard let provider else { return }
        let placeholderUUID = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: " ")
        update.localizedCallerName = " "
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        provider.reportNewIncomingCall(with: placeholderUUID, update: update) { _ in
            provider.reportCall(with: placeholderUUID, endedAt: nil, reason: reason)
        }
    }
}

extension CallKitManager: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        voipToken = token
        NotificationCenter.default.post(name: .mezonVoIPTokenDidUpdate, object: nil, userInfo: ["token": token])
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        voipToken = nil
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        handleVoIPDictionary(payload.dictionaryPayload, completion: completion)
    }
}

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        Self.clearStoredIncomingPayload()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let info = storedUserInfoIfFresh() else {
            Task { @MainActor in
                WebRTCCallManager.shared.abandonIncomingPresentation()
                action.fulfill()
            }
            return
        }
        let fallback = int64(info["receiverId"]) ?? 0
        guard let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: fallback) else {
            action.fulfill()
            return
        }
        let payload = info
        persistVoipQuitSnapshotFromIncomingPayload(payload)
        invalidateStoredVoIPPayloadOnly()
        action.fulfill(withDateConnected: Date())
        Task { @MainActor in
            var bgId = UIBackgroundTaskIdentifier.invalid
            bgId = UIApplication.shared.beginBackgroundTask(withName: "mezon.voip.answer") {
                UIApplication.shared.endBackgroundTask(bgId)
                bgId = .invalid
            }
            defer {
                if bgId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgId)
                    bgId = .invalid
                }
            }
            WebRTCCallManager.shared.prepareIncomingCallFromVoIPUserInfo(payload, currentUserId: myId)
            var prepared = false
            if let ctx = VoIPAnswerAccountBridge.context {
                prepared = await ctx.prepareForVoIPAnswerConnectivity()
            }
            if !prepared, let tok = SessionStore.load()?.token, !MezonSocket.shared.isConnected {
                MezonSocket.shared.connect(token: tok, wsHostOverride: nil)
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        Self.clearStoredIncomingPayload()
        Task { @MainActor in
            WebRTCCallManager.shared.abandonIncomingPresentation()
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming _: CXAction) {
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        Self.clearStoredIncomingPayload()
        Task { @MainActor in
            WebRTCCallManager.shared.abandonIncomingPresentation()
        }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.audioSessionDidActivate(audioSession)
        rtc.isAudioEnabled = true
        NotificationCenter.default.post(name: .mezonCallKitAudioActivated, object: nil)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.isAudioEnabled = false
        rtc.audioSessionDidDeactivate(audioSession)
    }
}
