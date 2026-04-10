import Foundation

final class CallKitManager {
    static let shared = CallKitManager()
    private init() {}

    var voipToken: String?
}

final class WebRTCCallManager {
    static let shared = WebRTCCallManager()
    private init() {}

    func handleSignalingMessage(_ msg: Mezon_Realtime_WebrtcSignalingFwd) {
        AppLogger.app.info(
            "[WebRTC] signaling receiver=\(msg.receiverID) caller=\(msg.callerID) channel=\(msg.channelID) type=\(msg.dataType)"
        )
    }
}
