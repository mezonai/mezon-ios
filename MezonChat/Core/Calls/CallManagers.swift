import Foundation

@MainActor
final class WebRTCCallManager {
    static let shared = WebRTCCallManager()
    private init() {}

    weak var signalingSession: PeerWebRTCCallSession?

    private var awaitingIncomingAttachment = false
    private var expectedIncomingBufferKey: (channelId: Int64, calleeUserId: Int64)?
    private var bufferedSignaling: [Mezon_Realtime_WebrtcSignalingFwd] = []

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
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        bufferedSignaling.removeAll()
    }

    func abandonIncomingPresentation() {
        awaitingIncomingAttachment = false
        expectedIncomingBufferKey = nil
        bufferedSignaling.removeAll()
    }

    func prepareIncomingCallFromVoIPUserInfo(_ userInfo: [AnyHashable: Any], currentUserId: Int64) {
        guard signalingSession == nil else { return }
        guard let payload = IncomingPeerCallPayload(userInfo: userInfo) else { return }
        guard payload.resolvedCompressedOffer() != nil else { return }
        guard payload.receiverId == currentUserId || payload.receiverId == 0 else { return }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = (payload.channelId, currentUserId)
        NotificationCenter.default.post(
            name: .mezonIncomingPeerCall,
            object: nil,
            userInfo: Self.userInfo(for: payload)
        )
    }

    func handleIncomingCallPush(_ push: Mezon_Realtime_IncomingCallPush, currentUserId: Int64) {
        guard signalingSession == nil else { return }
        guard push.receiverID == currentUserId || push.receiverID == 0 else { return }
        guard let parsed = IncomingPeerCallPayloadParser.from(push: push) else { return }
        awaitingIncomingAttachment = true
        expectedIncomingBufferKey = (parsed.channelId, currentUserId)
        NotificationCenter.default.post(
            name: .mezonIncomingPeerCall,
            object: nil,
            userInfo: Self.userInfo(for: parsed)
        )
    }

    func handleSignalingMessage(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) {
        deliverSignaling(msg, currentUserId: currentUserId)
    }

    private func deliverSignaling(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) {
        if let session = signalingSession {
            session.handleIncomingSignaling(msg)
            return
        }

        if msg.dataType == WebRTCSignalingDataType.sdpOffer,
           msg.receiverID == currentUserId,
           msg.callerID != currentUserId {
            if let incoming = IncomingPeerCallPayloadParser.fromSignalingOffer(msg) {
                if self.awaitingIncomingAttachment {
                    self.bufferedSignaling.append(msg)
                    return
                }
                self.awaitingIncomingAttachment = true
                self.expectedIncomingBufferKey = (incoming.channelId, currentUserId)
                self.bufferedSignaling.append(msg)
                NotificationCenter.default.post(
                    name: .mezonIncomingPeerCall,
                    object: nil,
                    userInfo: Self.userInfo(for: incoming)
                )
            }
            return
        }

        if shouldBuffer(msg, currentUserId: currentUserId) {
            bufferedSignaling.append(msg)
        }
    }

    private func shouldBuffer(_ msg: Mezon_Realtime_WebrtcSignalingFwd, currentUserId: Int64) -> Bool {
        guard let key = expectedIncomingBufferKey else { return false }
        guard msg.channelID == key.channelId else { return false }
        return msg.receiverID == currentUserId || msg.callerID == currentUserId
    }

    private static func userInfo(for payload: IncomingPeerCallPayload) -> [AnyHashable: Any] {
        [
            "channelId": payload.channelId,
            "callerId": payload.callerId,
            "receiverId": payload.receiverId,
            "compressedOfferFromPush": payload.compressedOfferFromPush as Any,
            "compressedOfferFromSignaling": payload.compressedOfferFromSignaling as Any,
            "pushJsonData": payload.pushJsonData as Any,
        ]
    }
}
