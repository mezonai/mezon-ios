import AVFoundation
import CallKit
import Foundation
import LiveKitWebRTC
import PushKit
import UIKit

final class CallKitManager: NSObject {

    static let shared = CallKitManager()

    private enum DefaultsKeys {
        static let notificationPayload = "mezon.voip.notificationPayload"
        static let activeCallUUID = "mezon.voip.activeCallUUID"
        static let notificationTimestamp = "mezon.voip.notificationTimestamp"
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
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        let config = CXProviderConfiguration(localizedName: "Mezon")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = "ringing.mp3"

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
                Self.clearStoredIncomingPayload()
            }
        }
    }

    func invalidateStoredVoIPPayloadOnly() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
    }

    private func forwardQuitToCallerFromStoredVoIPIfNeeded() {
        guard let info = storedUserInfoIfFresh(),
              let payload = IncomingPeerCallPayload(userInfo: info),
              let uidStr = SessionStore.load()?.userId,
              let myId = Int64(uidStr)
        else { return }
        guard payload.receiverId == myId || payload.receiverId == 0 else { return }
        let callerId = payload.callerId
        let channelId = payload.channelId
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

    private static func clearStoredIncomingPayload() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.activeCallUUID)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
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
    }

    private func storedUserInfoIfFresh() -> [AnyHashable: Any]? {
        if let ts = UserDefaults.standard.object(forKey: DefaultsKeys.notificationTimestamp) as? Double {
            if Date().timeIntervalSince1970 - ts > payloadValiditySeconds {
                Self.clearStoredIncomingPayload()
                return nil
            }
        }
        return UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload)
    }

    private func handleVoIPDictionary(_ payloadDict: [AnyHashable: Any], completion: @escaping () -> Void) {
        guard let offerValue = payloadDict["offer"] else {
            completion()
            return
        }

        guard let inner = parseOfferInner(offerValue) else {
            completion()
            return
        }

        let offerStr = inner["offer"] as? String ?? ""
        if offerStr == "CANCEL_CALL" {
            requestEndActiveVoIPCallIfNeeded()
            Self.clearStoredIncomingPayload()
            completion()
            return
        }

        guard !offerStr.isEmpty else {
            completion()
            return
        }

        let callerName = inner["callerName"] as? String ?? "Unknown"
        let callerId = int64(inner["callerId"]) ?? 0
        let channelId = int64(inner["channelId"]) ?? 0
        let receiverId = int64(inner["receiverId"]) ?? 0

        guard channelId != 0, callerId != 0 else {
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

        let meta = IncomingPeerCallPayloadParser.callerDisplayFromCompressedOffer(offerStr)
        let hasVideo = IncomingPeerCallPayloadParser.sdpContainsVideo(meta.sdpHint)

        let state = UIApplication.shared.applicationState
        if state == .active {
            if let uidStr = SessionStore.load()?.userId, let myId = Int64(uidStr) {
                Task { @MainActor in
                    WebRTCCallManager.shared.prepareIncomingCallFromVoIPUserInfo(userInfo, currentUserId: myId)
                }
            }
            completion()
            return
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

        provider?.reportNewIncomingCall(with: callUUID, update: update) { error in
            if error != nil {
                Self.clearStoredIncomingPayload()
            }
            completion()
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
        defer { action.fulfill() }
        guard let info = storedUserInfoIfFresh() else {
            Task { @MainActor in
                WebRTCCallManager.shared.abandonIncomingPresentation()
            }
            return
        }
        guard let uidStr = SessionStore.load()?.userId, let myId = Int64(uidStr) else { return }
        invalidateStoredVoIPPayloadOnly()
        Task { @MainActor in
            WebRTCCallManager.shared.prepareIncomingCallFromVoIPUserInfo(info, currentUserId: myId)
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

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        Self.clearStoredIncomingPayload()
        Task { @MainActor in
            WebRTCCallManager.shared.abandonIncomingPresentation()
        }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        LKRTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        LKRTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    }
}
