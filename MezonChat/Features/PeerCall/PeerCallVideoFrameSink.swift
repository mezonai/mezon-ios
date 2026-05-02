import Foundation
import LiveKitWebRTC

@objcMembers
class PeerCallVideoFrameSink: NSObject, LKRTCVideoRenderer {

    init(label _: String) {
        super.init()
    }

    func setSize(_ size: CGSize) {
    }

    func renderFrame(_ frame: LKRTCVideoFrame?) {
    }
}
