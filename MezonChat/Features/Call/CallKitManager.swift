import Foundation
import PushKit
@preconcurrency import CallKit
import AVFoundation
import UIKit

@MainActor
final class CallKitManager: NSObject {

    static let shared = CallKitManager()

    var onCallAnswered: ((_ callUUID: UUID, _ callerData: [String: Any]) -> Void)?
    var onCallEnded: ((_ callUUID: UUID) -> Void)?

    private var provider: CXProvider?
    private var callController: CXCallController?
    private var pushRegistry: PKPushRegistry?

    private(set) var voipToken: String?
    private var activeCallUUID: UUID?
    private var pendingCallData: [String: Any]?

    private override init() {
        super.init()
        setupCallKit()
        setupPushRegistry()
    }

    private func setupCallKit() {
        let config = CXProviderConfiguration(localizedName: "Mezon")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]

        if let icon = UIImage(named: "AppIcon") {
            config.iconTemplateImageData = icon.pngData()
        }

        provider = CXProvider(configuration: config)
        provider?.setDelegate(self, queue: nil)
        callController = CXCallController()
    }

    private func setupPushRegistry() {
        pushRegistry = PKPushRegistry(queue: DispatchQueue.main)
        pushRegistry?.delegate = self
        pushRegistry?.desiredPushTypes = [.voIP]
    }

    func startOutgoingCall(uuid: UUID, handle: String, displayName: String, isVideo: Bool = false) {
        activeCallUUID = uuid
        let startHandle = CXHandle(type: .generic, value: handle)
        let startAction = CXStartCallAction(call: uuid, handle: startHandle)
        startAction.contactIdentifier = displayName
        startAction.isVideo = isVideo

        let transaction = CXTransaction(action: startAction)
        callController?.request(transaction) { error in
            if let error {
                Task { @MainActor in
                }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let update = CXCallUpdate()
                update.remoteHandle = CXHandle(type: .generic, value: handle)
                update.localizedCallerName = displayName
                update.supportsHolding = false
                update.supportsGrouping = false
                update.supportsUngrouping = false
                update.supportsDTMF = false
                self.provider?.reportCall(with: uuid, updated: update)
            }
        }
    }

    func reportOutgoingCallConnected(uuid: UUID) {
        provider?.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func reportIncomingCall(
        uuid: UUID,
        callerName: String,
        callerId: String,
        isVideo: Bool,
        callerData: [String: Any],
        completion: ((Error?) -> Void)? = nil
    ) {
        activeCallUUID = uuid
        pendingCallData = callerData

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerId)
        update.localizedCallerName = callerName
        update.hasVideo = isVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider?.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                Task { @MainActor in
                    self.activeCallUUID = nil
                    self.pendingCallData = nil
                }
            }
            completion?(error)
        }
    }

    func endCall(uuid: UUID? = nil) {
        guard let callUUID = uuid ?? activeCallUUID else { return }
        let endAction = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: endAction)
        callController?.request(transaction) { error in
            if let error {
            }
        }
    }

    func reportCallEnded(uuid: UUID? = nil, reason: CXCallEndedReason = .remoteEnded) {
        guard let callUUID = uuid ?? activeCallUUID else { return }
        provider?.reportCall(with: callUUID, endedAt: Date(), reason: reason)
        activeCallUUID = nil
        pendingCallData = nil
    }

    var hasActiveCall: Bool { activeCallUUID != nil }
}

extension CallKitManager: CXProviderDelegate {

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.activeCallUUID = nil
            self.pendingCallData = nil
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            if let uuid = self.activeCallUUID, let data = self.pendingCallData {
                self.onCallAnswered?(uuid, data)
            }
        }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            self.onCallEnded?(action.callUUID)
            self.activeCallUUID = nil
            self.pendingCallData = nil
        }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    }
}

extension CallKitManager: PKPushRegistryDelegate {

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let tokenString = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            self.voipToken = tokenString
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        Task { @MainActor in
            self.voipToken = nil
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else { completion(); return }
        Task { @MainActor in
            self.handleVoIPPush(payload: payload, completion: completion)
        }
    }

    private func handleVoIPPush(payload: PKPushPayload, completion: @escaping () -> Void) {
        let payloadDict = payload.dictionaryPayload

        guard let offerValue = payloadDict["offer"] else {
            let uuid = UUID()
            reportIncomingCall(uuid: uuid, callerName: "Unknown", callerId: "", isVideo: false, callerData: [:]) { _ in
                self.reportCallEnded(uuid: uuid, reason: .failed)
                completion()
            }
            return
        }

        var callerName = "Unknown"
        var offer = ""
        var callerAvatar = ""
        var callerId = ""
        var channelId = ""

        if let offerString = offerValue as? String,
           let offerData = offerString.data(using: .utf8),
           let offerDict = try? JSONSerialization.jsonObject(with: offerData) as? [String: Any] {
            offer = offerDict["offer"] as? String ?? ""
            callerName = offerDict["callerName"] as? String ?? "Unknown"
            callerAvatar = offerDict["callerAvatar"] as? String ?? ""
            callerId = offerDict["callerId"] as? String ?? ""
            channelId = offerDict["channelId"] as? String ?? ""
        } else if let offerDict = offerValue as? [String: Any] {
            offer = offerDict["offer"] as? String ?? ""
            callerName = offerDict["callerName"] as? String ?? "Unknown"
            callerAvatar = offerDict["callerAvatar"] as? String ?? ""
            callerId = offerDict["callerId"] as? String ?? ""
            channelId = offerDict["channelId"] as? String ?? ""
        }

        if offer == "CANCEL_CALL" {
            if let uuid = activeCallUUID {
                reportCallEnded(uuid: uuid, reason: .remoteEnded)
            }
            completion()
            return
        }

        let callUUID = UUID()
        let callerData: [String: Any] = [
            "callerId": callerId,
            "callerName": callerName,
            "callerAvatar": callerAvatar,
            "channelId": channelId,
            "callUUID": callUUID.uuidString,
            "offer": offer
        ]

        reportIncomingCall(
            uuid: callUUID,
            callerName: callerName,
            callerId: callerId,
            isVideo: false,
            callerData: callerData
        ) { _ in
            completion()
        }
    }
}
