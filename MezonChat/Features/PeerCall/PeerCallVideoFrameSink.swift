import Foundation
import WebRTC

@objcMembers
class PeerCallVideoFrameSink: NSObject, RTCVideoRenderer {

    init(label _: String) {
        super.init()
    }

    func setSize(_ size: CGSize) {
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
    }
}
