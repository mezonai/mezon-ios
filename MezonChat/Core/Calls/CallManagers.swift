import Foundation
import UIKit

@MainActor
final class WebRTCCallManager {
    static let shared = WebRTCCallManager()
    private init() {}

    private(set) var isPeerCallDetailScreenActive = false

    func notePeerCallDetailAppeared() {
        isPeerCallDetailScreenActive = true
    }

    func notePeerCallDetailDisappeared() {
        isPeerCallDetailScreenActive = false
    }

    weak var signalingSession: PeerWebRTCCallSession?

    private var awaitingIncomingAttachment = false
    private var expectedIncomingBufferKey: (channelId: Int64, calleeUserId: Int64)?
    private var bufferedSignaling: [Mezon_Realtime_WebrtcSignalingFwd] = []
    private var pendingIncomingPeerCallUserInfo: [AnyHashable: Any]?

    private var preWarmedIncomingSession: PeerWebRTCCallSession?
    private var preWarmedIncomingKey: (channelId: Int64, callerId: Int64)?

    func attachSignalingSession(_ session: PeerWebRTCCallSession) {
        print("[DMCall] attachSignalingSession bufferedCount=\(bufferedSignaling.count) awaitingAttachment=\(awaitingIncomingAttachment)")
        signalingSession = session
        awaitingIncomingAttachment = false
        let batch = bufferedSignaling
        bufferedSignaling.removeAll()
        expectedIncomingBufferKey = nil
        if !batch.isEmpty {
            print("[DMCall] attachSignalingSession draining \(batch.count) buffered signaling messages")
        }
        for m in batch {
            session.handleIncomingSignaling(m)
        }
    }

    func detachSession(_ session: PeerWebRTCCallSession) {
        print("[DMCall] detachSession wasSig=\(signalingSession === session) wasWarm=\(preWarmedIncomingSession === session)")
        if signalingSession === session {
            signalingSession = nil
        }
        if preWarmedIncomingSession === session {
            preWarmedIncomingSession = nil
            preWarmedIncomingKey = nil
        }
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        bufferedSignaling.removeAll()
    }

    func abandonIncomingPresentation() {
        print("[DMCall] abandonIncomingPresentation hasWarm=\(preWarmedIncomingSession != nil) pendingUserInfo=\(pendingIncomingPeerCallUserInfo != nil)")
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        bufferedSignaling.removeAll()
        pendingIncomingPeerCallUserInfo = nil
        if let warm = preWarmedIncomingSession {
            warm.hangUp()
        }
        preWarmedIncomingSession = nil
        preWarmedIncomingKey = nil
    }

    func endActivePeerCallFromCallKitAction() {
        print("[DMCall] endActivePeerCallFromCallKitAction hasSig=\(signalingSession != nil) hasWarm=\(preWarmedIncomingSession != nil)")
        if let session = signalingSession {
            session.hangUp()
        } else if let warm = preWarmedIncomingSession {
            warm.hangUp()
            preWarmedIncomingSession = nil
            preWarmedIncomingKey = nil
        }
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        bufferedSignaling.removeAll()
        pendingIncomingPeerCallUserInfo = nil
    }

    func preWarmIncomingPeerCallIfNeeded(
        channelId: Int64,
        callerId: Int64,
        receiverId: Int64,
        currentUserId: Int64,
        compressedOffer: String
    ) {
        print("[DMCall] preWarmIncomingPeerCallIfNeeded channelId=\(channelId) callerId=\(callerId) receiverId=\(receiverId) currentUserId=\(currentUserId) hasSig=\(signalingSession != nil) hasWarm=\(preWarmedIncomingSession != nil)")
        guard signalingSession == nil, preWarmedIncomingSession == nil else {
            print("[DMCall] preWarmIncomingPeerCallIfNeeded skip: hasSig=\(signalingSession != nil) hasWarm=\(preWarmedIncomingSession != nil)")
            return
        }
        guard channelId != 0, callerId != 0, !compressedOffer.isEmpty else {
            print("[DMCall] preWarmIncomingPeerCallIfNeeded skip: missing ids or offer empty=\(compressedOffer.isEmpty)")
            return
        }
        guard receiverId == currentUserId || receiverId == 0 else {
            print("[DMCall] preWarmIncomingPeerCallIfNeeded skip: receiverId=\(receiverId) != currentUserId=\(currentUserId)")
            return
        }

        let session = PeerWebRTCCallSession(
            direction: .incoming,
            myUserId: currentUserId,
            peerUserId: callerId,
            channelId: channelId,
            callerDisplayNameForPush: "",
            callerAvatarURLStringForPush: "",
            wantsVideo: false,
            incomingStartsRinging: true,
            initialCompressedOffer: compressedOffer
        )
        preWarmedIncomingSession = session
        preWarmedIncomingKey = (channelId, callerId)
        signalingSession = session
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        let buffered = bufferedSignaling
        bufferedSignaling.removeAll()
        print("[DMCall] preWarmIncomingPeerCallIfNeeded session created draining \(buffered.count) buffered messages")
        for m in buffered {
            session.handleIncomingSignaling(m)
        }
        Task { @MainActor [weak session] in
            guard let session else { return }
            do {
                try await session.prepareIncomingAnswerInBackground()
            } catch {
                print("[DMCall] preWarmIncomingPeerCallIfNeeded prepareIncomingAnswerInBackground threw: \(error)")
            }
        }
    }

    func consumePreWarmedIncomingSession(channelId: Int64, callerId: Int64) -> PeerWebRTCCallSession? {
        guard let key = preWarmedIncomingKey,
              key.channelId == channelId, key.callerId == callerId,
              let session = preWarmedIncomingSession else {
            print("[DMCall] consumePreWarmedIncomingSession miss channelId=\(channelId) callerId=\(callerId) warmKey=\(String(describing: preWarmedIncomingKey))")
            return nil
        }
        print("[DMCall] consumePreWarmedIncomingSession HIT channelId=\(channelId) callerId=\(callerId)")
        preWarmedIncomingSession = nil
        preWarmedIncomingKey = nil
        return session
    }

    func stashIncomingPeerCallPresentation(_ userInfo: [AnyHashable: Any]) {
        pendingIncomingPeerCallUserInfo = userInfo
    }

    func peekPendingIncomingPeerCallPresentation() -> [AnyHashable: Any]? {
        pendingIncomingPeerCallUserInfo
    }

    func clearPendingIncomingPeerCallPresentation() {
        pendingIncomingPeerCallUserInfo = nil
    }

    func armIncomingSignalingBufferIfDetached(channelId: Int64, calleeUserId: Int64) {
        print("[DMCall] armIncomingSignalingBufferIfDetached channelId=\(channelId) calleeUserId=\(calleeUserId) hasSig=\(signalingSession != nil)")
        guard signalingSession == nil else {
            print("[DMCall] armIncomingSignalingBufferIfDetached skip: session already attached")
            return
        }
        let nextKey = (channelId: channelId, calleeUserId: calleeUserId)
        if let key = expectedIncomingBufferKey {
            if key.channelId != nextKey.channelId || key.calleeUserId != nextKey.calleeUserId {
                print("[DMCall] armIncomingSignalingBufferIfDetached key changed oldKey=(\(key.channelId),\(key.calleeUserId)) newKey=(\(channelId),\(calleeUserId)) -> clearing buffer")
                bufferedSignaling.removeAll()
            }
        }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = nextKey
    }

    func prepareIncomingCallFromVoIPUserInfo(_ userInfo: [AnyHashable: Any], currentUserId: Int64) {
        print("[DMCall] prepareIncomingCallFromVoIPUserInfo currentUserId=\(currentUserId)")
        guard let payload = IncomingPeerCallPayload(userInfo: userInfo) else {
            print("[DMCall] prepareIncomingCallFromVoIPUserInfo skip: invalid payload")
            return
        }
        print("[DMCall] prepareIncomingCallFromVoIPUserInfo channelId=\(payload.channelId) callerId=\(payload.callerId) receiverId=\(payload.receiverId) hasPushOffer=\(payload.compressedOfferFromPush?.isEmpty == false) hasSigOffer=\(payload.compressedOfferFromSignaling?.isEmpty == false)")
        guard payload.receiverId == currentUserId || payload.receiverId == 0 else {
            print("[DMCall] prepareIncomingCallFromVoIPUserInfo skip: receiverId mismatch \(payload.receiverId) != \(currentUserId)")
            return
        }

        if let session = signalingSession, preWarmedIncomingSession == nil {
            print("[DMCall] prepareIncomingCallFromVoIPUserInfo existing session found isSame=\(session.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId)) isRinging=\(session.isRingingIncomingPeerCallMatching(channelId: payload.channelId, callerId: payload.callerId))")
            guard session.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId) else {
                return
            }
            if session.isRingingIncomingPeerCallMatching(channelId: payload.channelId, callerId: payload.callerId) {
                print("[DMCall] prepareIncomingCallFromVoIPUserInfo -> mezonCallKitMatchedExistingIncoming -> answerIncomingCall")
                NotificationCenter.default.post(
                    name: .mezonCallKitMatchedExistingIncoming,
                    object: nil,
                    userInfo: [
                        "channelId": NSNumber(value: payload.channelId),
                        "callerId": NSNumber(value: payload.callerId),
                    ]
                )
                session.answerIncomingCall()
            }
            return
        }

        guard let offer = payload.resolvedCompressedOffer(), !offer.isEmpty else {
            print("[DMCall] prepareIncomingCallFromVoIPUserInfo skip: no resolved offer")
            return
        }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = (payload.channelId, currentUserId)
        let presentedViaNative = attemptPresentIncomingPeerCallViaNativeWindowRoot(payload: payload)
        print("[DMCall] prepareIncomingCallFromVoIPUserInfo presentedViaNativeWindow=\(presentedViaNative) hasWarm=\(preWarmedIncomingSession != nil)")
        if presentedViaNative {
            if let warm = preWarmedIncomingSession,
               warm.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId) {
                print("[DMCall] prepareIncomingCallFromVoIPUserInfo nativeWindow path -> answerIncomingCall on warm session")
                warm.answerIncomingCall()
            }
            return
        }
        print("[DMCall] prepareIncomingCallFromVoIPUserInfo posting mezonIncomingPeerCall notification")
        NotificationCenter.default.post(
            name: .mezonIncomingPeerCall,
            object: nil,
            userInfo: Self.userInfo(for: payload, skipIncomingRingingUI: true)
        )
        if let warm = preWarmedIncomingSession,
           warm.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId) {
            print("[DMCall] prepareIncomingCallFromVoIPUserInfo notification path -> answerIncomingCall on warm session")
            warm.answerIncomingCall()
        }
    }

    @discardableResult
    private func attemptPresentIncomingPeerCallViaNativeWindowRoot(payload: IncomingPeerCallPayload) -> Bool {
        guard let ctx = VoIPAnswerAccountBridge.context else { return false }
        guard let mainWindow = ctx.sharedContextImpl.mainWindow else { return false }
        guard let native = mainWindow.hostView.nativeController?() else { return false }
        let navStack = Self.navigationControllerForPeerCallScreen(from: native)
        if let nav = navStack, nav.viewControllers.contains(where: { $0 is PeerCallViewController }) {
            clearPendingIncomingPeerCallPresentation()
            return true
        }
        var walk: UIViewController? = native
        while let cur = walk {
            if cur is PeerCallViewController {
                clearPendingIncomingPeerCallPresentation()
                return true
            }
            walk = cur.presentedViewController
        }
        let display = IncomingPeerCallPayloadParser.callerDisplay(for: payload, skipDecompressOffer: true)
        let vc = PeerCallViewController(
            context: ctx,
            incoming: payload,
            remoteDisplayName: display.name,
            remoteAvatarURL: display.avatar,
            skipIncomingRingingUI: true
        )
        if let nav = navStack {
            let push = { nav.pushViewController(vc, animated: false) }
            if nav.presentedViewController != nil {
                nav.dismiss(animated: false, completion: push)
            } else {
                push()
            }
        } else {
            native.present(vc, animated: false, completion: nil)
        }
        clearPendingIncomingPeerCallPresentation()
        return true
    }

    private static func navigationControllerForPeerCallScreen(from root: UIViewController) -> UINavigationController? {
        if let nav = root as? UINavigationController { return nav }
        return root.navigationController
    }

    func handleIncomingCallPush(_ push: Mezon_Realtime_IncomingCallPush, currentUserId: Int64) {
        print("[DMCall] handleIncomingCallPush channelId=\(push.channelID) callerId=\(push.callerID) receiverId=\(push.receiverID) currentUserId=\(currentUserId) hasSig=\(signalingSession != nil)")
        guard push.callerID != currentUserId else {
            print("[CallKitDebug] handleIncomingCallPush ignored selfEcho callerId=\(push.callerID)")
            return
        }
        guard push.receiverID == currentUserId || push.receiverID == 0 else {
            print("[CallKitDebug] handleIncomingCallPush ignored receiverMismatch receiverId=\(push.receiverID) currentUserId=\(currentUserId)")
            return
        }
        guard push.channelID != 0, push.callerID != 0 else { return }
        if Self.incomingCallPushIsCancel(push.jsonData) {
            let isConnectedFlag = Self.incomingCallPushIsConnectedTrue(push.jsonData)
            print("[CallKitDebug] handleIncomingCallPush CANCEL_CALL via socket channelId=\(push.channelID) callerId=\(push.callerID) isConnected=\(isConnectedFlag)")
            if let session = signalingSession,
               session.isSameIncomingPeerCall(channelId: push.channelID, callerId: push.callerID) {
                let isRinging = session.isRingingIncomingPeerCallMatching(
                    channelId: push.channelID,
                    callerId: push.callerID
                )
                if isRinging {
                    print("[CallKitDebug] handleIncomingCallPush -> session.hangUp() (still ringing)")
                    session.hangUp()
                } else if !isConnectedFlag {
                    print("[CallKitDebug] handleIncomingCallPush -> session.hangUp() (active session, isConnected=false caller-cancelled)")
                    session.hangUp()
                } else {
                    print("[CallKitDebug] handleIncomingCallPush -> SKIP session.hangUp() (active session, isConnected=true means caller signaling answered-elsewhere; this device is the answerer)")
                }
            }
            if let warm = preWarmedIncomingSession,
               warm.isSameIncomingPeerCall(channelId: push.channelID, callerId: push.callerID) {
                warm.hangUp()
                preWarmedIncomingSession = nil
                preWarmedIncomingKey = nil
            }
            bufferedSignaling.removeAll()
            awaitingIncomingAttachment = false
            expectedIncomingBufferKey = nil
            pendingIncomingPeerCallUserInfo = nil
            CallKitManager.shared.endRingingCallIfMatching(
                channelId: push.channelID,
                callerId: push.callerID,
                remoteIsConnected: isConnectedFlag
            )
            return
        }
        guard signalingSession == nil else {
            return
        }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = (push.channelID, currentUserId)
    }

    private static func incomingCallPushIsCancel(_ jsonData: String) -> Bool {
        let trimmed = jsonData.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (obj["offer"] as? String) == "CANCEL_CALL"
    }

    private static func incomingCallPushIsConnectedTrue(_ jsonData: String) -> Bool {
        let trimmed = jsonData.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if let b = obj["isConnected"] as? Bool { return b }
        if let n = obj["isConnected"] as? NSNumber { return n.boolValue }
        return false
    }

    func handleSignalingMessage(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) {
        deliverSignaling(msg, currentUserId: currentUserId)
    }

    private func deliverSignaling(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) {
        print("[DMCall] deliverSignaling dataType=\(msg.dataType) channelId=\(msg.channelID) callerId=\(msg.callerID) receiverId=\(msg.receiverID) hasSig=\(signalingSession != nil) awaitingAttachment=\(awaitingIncomingAttachment) buffered=\(bufferedSignaling.count)")

        if msg.dataType == WebRTCSignalingDataType.sdpOffer,
           msg.callerID != currentUserId,
           msg.callerID != 0,
           msg.channelID != 0,
           (msg.receiverID == currentUserId || msg.receiverID == 0),
           isBusyWithDifferentPeer(channelId: msg.channelID, callerId: msg.callerID) {
            print("[DMCall] deliverSignaling sdpOffer from DIFFERENT peer while busy -> sdpJoinedOtherCall to caller=\(msg.callerID) channelId=\(msg.channelID)")
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: msg.callerID,
                dataType: WebRTCSignalingDataType.sdpJoinedOtherCall,
                jsonData: "",
                channelId: msg.channelID,
                callerId: currentUserId
            )
            return
        }

        if let session = signalingSession {
            print("[DMCall] deliverSignaling -> forwarding to attached session")
            session.handleIncomingSignaling(msg)
            return
        }

        if Self.isTerminalSignalingDataType(msg.dataType) {
            print("[DMCall] deliverSignaling -> terminal dataType=\(msg.dataType) no session")
            handleTerminalSignalingWithoutSession(msg, currentUserId: currentUserId)
            return
        }

        if msg.dataType == WebRTCSignalingDataType.sdpOffer,
           msg.callerID != currentUserId,
           msg.channelID != 0,
           msg.callerID != 0,
           (msg.receiverID == currentUserId || msg.receiverID == 0) {
            if !awaitingIncomingAttachment {
                awaitingIncomingAttachment = true
                expectedIncomingBufferKey = (msg.channelID, currentUserId)
            }
            print("[DMCall] deliverSignaling sdpOffer buffered awaitingAttachment=\(awaitingIncomingAttachment) bufferedCount=\(bufferedSignaling.count + 1)")
            bufferedSignaling.append(msg)
            return
        }

        if shouldBuffer(msg, currentUserId: currentUserId) {
            print("[DMCall] deliverSignaling buffered (shouldBuffer) dataType=\(msg.dataType) bufferedCount=\(bufferedSignaling.count + 1)")
            bufferedSignaling.append(msg)
            return
        }

        print("[DMCall] deliverSignaling dropped: no session, not terminal, not bufferable dataType=\(msg.dataType)")
    }

    private func handleTerminalSignalingWithoutSession(
        _ msg: Mezon_Realtime_WebrtcSignalingFwd,
        currentUserId: Int64
    ) {
        guard msg.callerID != currentUserId, msg.callerID != 0, msg.channelID != 0 else { return }
        guard msg.receiverID == currentUserId || msg.receiverID == 0 else { return }
        print("[CallKitDebug] handleTerminalSignalingWithoutSession dataType=\(msg.dataType) channelId=\(msg.channelID) callerId=\(msg.callerID)")
        bufferedSignaling.removeAll()
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        pendingIncomingPeerCallUserInfo = nil
        if let warm = preWarmedIncomingSession,
           warm.isSameIncomingPeerCall(channelId: msg.channelID, callerId: msg.callerID) {
            warm.hangUp()
            preWarmedIncomingSession = nil
            preWarmedIncomingKey = nil
        }
        CallKitManager.shared.endRingingCallIfMatching(
            channelId: msg.channelID,
            callerId: msg.callerID
        )
    }

    private static func isTerminalSignalingDataType(_ dt: Int32) -> Bool {
        switch dt {
        case WebRTCSignalingDataType.sdpQuit,
             WebRTCSignalingDataType.sdpTimeout,
             WebRTCSignalingDataType.sdpNotAvailable,
             WebRTCSignalingDataType.sdpJoinedOtherCall,
             WebRTCSignalingDataType.clearCall:
            return true
        default:
            return false
        }
    }

    private func isBusyWithDifferentPeer(channelId: Int64, callerId: Int64) -> Bool {
        if let session = signalingSession,
           !session.isMatchingPeerCall(channelId: channelId, callerId: callerId) {
            return true
        }
        if let warm = preWarmedIncomingSession,
           !warm.isMatchingPeerCall(channelId: channelId, callerId: callerId) {
            return true
        }
        return false
    }

    private func shouldBuffer(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) -> Bool {
        guard let key = expectedIncomingBufferKey else { return false }
        guard msg.channelID == key.channelId else { return false }
        let callee = key.calleeUserId
        if msg.receiverID == callee { return true }
        if msg.receiverID == 0, msg.callerID != 0, msg.callerID != callee { return true }
        return false
    }

    private static func userInfo(for payload: IncomingPeerCallPayload, skipIncomingRingingUI: Bool = false) -> [AnyHashable: Any] {
        var d: [AnyHashable: Any] = [
            "channelId": payload.channelId,
            "callerId": payload.callerId,
            "receiverId": payload.receiverId,
            "compressedOfferFromPush": payload.compressedOfferFromPush as Any,
            "compressedOfferFromSignaling": payload.compressedOfferFromSignaling as Any,
            "pushJsonData": payload.pushJsonData as Any,
        ]
        if skipIncomingRingingUI {
            d["mezonSkipIncomingRingingUI"] = true
        }
        return d
    }
}

struct IncomingPeerCallPayload {
    var channelId: Int64
    var callerId: Int64
    var receiverId: Int64
    var compressedOfferFromPush: String?
    var compressedOfferFromSignaling: String?
    var pushJsonData: String?

    mutating func mergeSignalingOffer(_ compressed: String) {
        if compressedOfferFromSignaling == nil {
            compressedOfferFromSignaling = compressed
        }
    }

    func resolvedCompressedOffer() -> String? {
        let a = compressedOfferFromPush?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let b = compressedOfferFromSignaling?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !a.isEmpty { return a }
        if !b.isEmpty { return b }
        return nil
    }

    init(
        channelId: Int64,
        callerId: Int64,
        receiverId: Int64,
        compressedOfferFromPush: String?,
        compressedOfferFromSignaling: String?,
        pushJsonData: String?
    ) {
        self.channelId = channelId
        self.callerId = callerId
        self.receiverId = receiverId
        self.compressedOfferFromPush = compressedOfferFromPush
        self.compressedOfferFromSignaling = compressedOfferFromSignaling
        self.pushJsonData = pushJsonData
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo else { return nil }
        func i64(_ v: Any?) -> Int64? {
            if let x = v as? Int64 { return x }
            if let x = v as? Int { return Int64(x) }
            if let x = v as? NSNumber { return x.int64Value }
            if let x = v as? String { return Int64(x) }
            return nil
        }
        guard let channelId = i64(info["channelId"]) else { return nil }
        guard let callerId = i64(info["callerId"]) else { return nil }
        let receiverId = i64(info["receiverId"]) ?? 0
        let fromPush = info["compressedOfferFromPush"] as? String
        let fromSig = info["compressedOfferFromSignaling"] as? String
        let pushJson = info["pushJsonData"] as? String
        self.init(
            channelId: channelId,
            callerId: callerId,
            receiverId: receiverId,
            compressedOfferFromPush: fromPush,
            compressedOfferFromSignaling: fromSig,
            pushJsonData: pushJson
        )
    }
}

enum IncomingPeerCallPayloadParser {

    static func callerDisplayFromPushJsonData(_ json: String) -> (name: String?, avatar: String?) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, nil)
        }
        let name = obj["callerName"] as? String
        let avatar = obj["callerAvatar"] as? String
        return (name, avatar)
    }

    static func callerDisplay(for payload: IncomingPeerCallPayload, skipDecompressOffer: Bool) -> (name: String, avatar: String?) {
        let trimmedJson = payload.pushJsonData?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedJson.isEmpty {
            let m = callerDisplayFromPushJsonData(trimmedJson)
            if let n = m.name, !n.isEmpty { return (n, m.avatar) }
        }
        if !skipDecompressOffer, let compressed = payload.resolvedCompressedOffer() {
            let m = callerDisplayFromCompressedOffer(compressed)
            if let n = m.name, !n.isEmpty { return (n, m.avatar) }
        }
        return ("Incoming call", nil)
    }

    static func callerDisplayFromCompressedOffer(_ compressed: String) -> (name: String?, avatar: String?, sdpHint: String?) {
        guard let raw = try? PeerWebRTCStringCompression.decompressSignalingJson(compressed),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, nil, nil)
        }
        let name = obj["callerName"] as? String
        let avatar = obj["callerAvatar"] as? String
        let sdp = obj["sdp"] as? String
        return (name, avatar, sdp)
    }

    static func sdpContainsVideo(_ sdp: String?) -> Bool {
        guard let sdp else { return false }
        return sdp.range(of: "\nm=video ", options: .literal) != nil
                || sdp.uppercased().contains("M=VIDEO")
    }
}

enum PeerCallEndReason {
    case finished
    case timeout
    case userCancel
    case remoteReject
}

@MainActor
enum PeerCallLogMessage {

    private struct OutgoingEntry {
        let messageId: Int64
        let isVideoCall: Bool
        let mode: Int32
        let isPublic: Bool
    }

    private static var outgoingByChannelId: [Int64: OutgoingEntry] = [:]

    static func sendStartCallLog(
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        isVideoCall: Bool
    ) {
        let channelId = channel.channelID
        let mode = streamMode(for: channel)
        let isPublic = channel.channelPrivate == 0
        Task { @MainActor in
            let ack = await sendStartCallLogAndReturnAck(
                context: context,
                channel: channel,
                isVideoCall: isVideoCall,
                mode: mode,
                isPublic: isPublic
            )
            guard let ack, ack.messageID != 0 else { return }
            outgoingByChannelId[channelId] = OutgoingEntry(
                messageId: ack.messageID,
                isVideoCall: isVideoCall,
                mode: mode,
                isPublic: isPublic
            )
        }
    }

    static func updateCallLogForOutgoing(
        channelId: Int64,
        reason: PeerCallEndReason,
        durationSeconds: Int?
    ) {
        guard let entry = outgoingByChannelId[channelId] else { return }
        guard let context = VoIPAnswerAccountBridge.context else { return }
        outgoingByChannelId.removeValue(forKey: channelId)

        let callLogType: CallLogType
        let titleText: String
        switch reason {
        case .finished:
            callLogType = .finishCall
            if let s = durationSeconds, s >= 0 {
                let m = s / 60
                let r = s % 60
                titleText = "\(m) mins \(r) secs"
            } else {
                titleText = ""
            }
        case .timeout:
            callLogType = .timeoutCall
            titleText = ""
        case .userCancel:
            callLogType = .cancelCall
            titleText = ""
        case .remoteReject:
            callLogType = .rejectCall
            titleText = ""
        }

        Task { @MainActor in
            try? await updateMessage(
                context: context,
                channelId: channelId,
                messageId: entry.messageId,
                mode: entry.mode,
                isPublic: entry.isPublic,
                isVideoCall: entry.isVideoCall,
                callLogType: callLogType,
                titleText: titleText
            )
        }
    }

    private static func streamMode(for channel: Mezon_Api_ChannelDescription) -> Int32 {
        if channel.type == MezonConstants.ChannelType.group.rawValue {
            return MezonConstants.ChannelStreamMode.group.rawValue
        }
        return MezonConstants.ChannelStreamMode.dm.rawValue
    }

    private static func sendStartCallLogAndReturnAck(
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        isVideoCall: Bool,
        mode: Int32,
        isPublic: Bool
    ) async -> Mezon_Realtime_ChannelMessageAck? {
        guard let token = await context.getToken() else { return nil }

        let username = context.currentUser?.username ?? ""
        let mediaWord = isVideoCall ? "video" : "audio"
        let titleText = "\(username) started a \(mediaWord) call"

        let callLogObj: [String: Any] = [
            "isVideo": isVideoCall,
            "callLogType": CallLogType.startCall.rawValue,
        ]
        let contentObj: [String: Any] = [
            "t": titleText,
            "callLog": callLogObj,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: contentObj),
              let contentStr = String(data: data, encoding: .utf8) else {
            return nil
        }

        do {
            let ack = try await context.account.network.sendChannelMessage(
                clanId: 0,
                channelId: channel.channelID,
                mode: mode,
                isPublic: isPublic,
                content: contentStr,
                mentions: [],
                attachments: [],
                references: [],
                anonymous: false,
                mentionEveryone: false,
                avatar: "",
                topicId: 0,
                token: token
            )
            return ack
        } catch {
            return nil
        }
    }

    private static func updateMessage(
        context: AccountContext,
        channelId: Int64,
        messageId: Int64,
        mode: Int32,
        isPublic: Bool,
        isVideoCall: Bool,
        callLogType: CallLogType,
        titleText: String
    ) async throws {
        guard let token = await context.getToken() else { return }

        let callLogObj: [String: Any] = [
            "isVideo": isVideoCall,
            "callLogType": callLogType.rawValue,
        ]
        let contentObj: [String: Any] = [
            "t": titleText,
            "callLog": callLogObj,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: contentObj),
              let contentStr = String(data: data, encoding: .utf8) else {
            return
        }

        _ = try await context.account.network.updateChannelMessage(
            clanId: 0,
            channelId: channelId,
            mode: mode,
            isPublic: isPublic,
            messageId: messageId,
            content: contentStr,
            mentions: [],
            attachments: [],
            hideEditted: true,
            topicId: 0,
            isUpdateMsgTopic: false,
            token: token
        )
    }
}
