import Foundation

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
        compressedOfferFromPush ?? compressedOfferFromSignaling
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

    static func from(push: Mezon_Realtime_IncomingCallPush) -> IncomingPeerCallPayload? {
        guard push.channelID != 0, push.callerID != 0 else { return nil }
        let offer = extractOfferString(fromPushJson: push.jsonData)
        return IncomingPeerCallPayload(
            channelId: push.channelID,
            callerId: push.callerID,
            receiverId: push.receiverID,
            compressedOfferFromPush: offer,
            compressedOfferFromSignaling: nil,
            pushJsonData: push.jsonData
        )
    }

    static func fromSignalingOffer(_ msg: Mezon_Realtime_WebrtcSignalingFwd) -> IncomingPeerCallPayload? {
        guard msg.channelID != 0, msg.callerID != 0, msg.receiverID != 0 else { return nil }
        guard msg.dataType == WebRTCSignalingDataType.sdpOffer else { return nil }
        return IncomingPeerCallPayload(
            channelId: msg.channelID,
            callerId: msg.callerID,
            receiverId: msg.receiverID,
            compressedOfferFromPush: nil,
            compressedOfferFromSignaling: msg.jsonData,
            pushJsonData: nil
        )
    }

    static func extractOfferString(fromPushJson json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let offer = obj["offer"] as? String
        else { return nil }
        if offer == "CANCEL_CALL" { return nil }
        return offer
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
