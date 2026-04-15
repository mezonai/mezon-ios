import Foundation

final class CallKitManager {
    static let shared = CallKitManager()
    private init() {}

    var voipToken: String?
}

final class WebRTCCallManager {
    static let shared = WebRTCCallManager()
    private init() {}

    func handleSignalingMessage(_: Mezon_Realtime_WebrtcSignalingFwd) {
    }
}
