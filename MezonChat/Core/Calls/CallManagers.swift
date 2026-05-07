import Foundation
import UIKit

@MainActor
final class WebRTCCallManager {
    static let shared = WebRTCCallManager()
    private init() {}

    weak var signalingSession: PeerWebRTCCallSession?

    private var awaitingIncomingAttachment = false
    private var expectedIncomingBufferKey: (channelId: Int64, calleeUserId: Int64)?
    private var bufferedSignaling: [Mezon_Realtime_WebrtcSignalingFwd] = []
    private var pendingIncomingPeerCallUserInfo: [AnyHashable: Any]?

    private var preWarmedIncomingSession: PeerWebRTCCallSession?
    private var preWarmedIncomingKey: (channelId: Int64, callerId: Int64)?

    func attachSignalingSession(_ session: PeerWebRTCCallSession) {
        signalingSession = session
        awaitingIncomingAttachment = false
        let batch = bufferedSignaling
        bufferedSignaling.removeAll()
        expectedIncomingBufferKey = nil
        for m in batch {
            session.handleIncomingSignaling(m)
        }
    }

    func detachSession(_ session: PeerWebRTCCallSession) {
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

    func preWarmIncomingPeerCallIfNeeded(
        channelId: Int64,
        callerId: Int64,
        receiverId: Int64,
        currentUserId: Int64,
        compressedOffer: String
    ) {
        guard signalingSession == nil, preWarmedIncomingSession == nil else {
            return
        }
        guard channelId != 0, callerId != 0, !compressedOffer.isEmpty else {
            return
        }
        guard receiverId == currentUserId || receiverId == 0 else {
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
        for m in buffered {
            session.handleIncomingSignaling(m)
        }
        Task { @MainActor [weak session] in
            guard let session else { return }
            do {
                try await session.prepareIncomingAnswerInBackground()
            } catch {
            }
        }
    }

    func consumePreWarmedIncomingSession(channelId: Int64, callerId: Int64) -> PeerWebRTCCallSession? {
        guard let key = preWarmedIncomingKey,
              key.channelId == channelId, key.callerId == callerId,
              let session = preWarmedIncomingSession else {
            return nil
        }
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
        guard signalingSession == nil else {
            return
        }
        let nextKey = (channelId: channelId, calleeUserId: calleeUserId)
        if let key = expectedIncomingBufferKey {
            if key.channelId != nextKey.channelId || key.calleeUserId != nextKey.calleeUserId {
                bufferedSignaling.removeAll()
            }
        }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = nextKey
    }

    func prepareIncomingCallFromVoIPUserInfo(_ userInfo: [AnyHashable: Any], currentUserId: Int64) {
        guard let payload = IncomingPeerCallPayload(userInfo: userInfo) else {
            return
        }
        guard payload.receiverId == currentUserId || payload.receiverId == 0 else {
            return
        }

        if let session = signalingSession, preWarmedIncomingSession == nil {
            guard session.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId) else {
                return
            }
            if session.isRingingIncomingPeerCallMatching(channelId: payload.channelId, callerId: payload.callerId) {
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
            return
        }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = (payload.channelId, currentUserId)
        if attemptPresentIncomingPeerCallViaNativeWindowRoot(payload: payload) {
            if let warm = preWarmedIncomingSession,
               warm.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId) {
                warm.answerIncomingCall()
            }
            return
        }
        NotificationCenter.default.post(
            name: .mezonIncomingPeerCall,
            object: nil,
            userInfo: Self.userInfo(for: payload, skipIncomingRingingUI: true)
        )
        if let warm = preWarmedIncomingSession,
           warm.isSameIncomingPeerCall(channelId: payload.channelId, callerId: payload.callerId) {
            warm.answerIncomingCall()
        }
    }

    @discardableResult
    private func attemptPresentIncomingPeerCallViaNativeWindowRoot(payload: IncomingPeerCallPayload) -> Bool {
        guard let ctx = VoIPAnswerAccountBridge.context else { return false }
        guard let mainWindow = ctx.sharedContextImpl.mainWindow else { return false }
        guard let native = mainWindow.hostView.nativeController?() else { return false }
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
        native.present(vc, animated: false, completion: nil)
        clearPendingIncomingPeerCallPresentation()
        return true
    }

    func handleIncomingCallPush(_ push: Mezon_Realtime_IncomingCallPush, currentUserId: Int64) {
        guard push.callerID != currentUserId else {
            return
        }
        guard signalingSession == nil else {
            return
        }
        guard push.receiverID == currentUserId || push.receiverID == 0 else {
            return
        }
        guard push.channelID != 0, push.callerID != 0 else { return }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = (push.channelID, currentUserId)
    }

    func handleSignalingMessage(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) {
        deliverSignaling(msg, currentUserId: currentUserId)
    }

    private func deliverSignaling(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) {
        if let session = signalingSession {
            session.handleIncomingSignaling(msg)
            return
        }

        if Self.isTerminalSignalingDataType(msg.dataType) {
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
            bufferedSignaling.append(msg)
            return
        }

        if shouldBuffer(msg, currentUserId: currentUserId) {
            bufferedSignaling.append(msg)
            return
        }

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
