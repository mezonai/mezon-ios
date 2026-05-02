import Foundation

enum WebRTCSignalingDataType {

    static let sdpInit: Int32 = 0
    static let sdpOffer: Int32 = 1
    static let sdpAnswer: Int32 = 2
    static let iceCandidate: Int32 = 3
    static let sdpQuit: Int32 = 4
    static let sdpTimeout: Int32 = 5
    static let sdpNotAvailable: Int32 = 6
    static let sdpJoinedOtherCall: Int32 = 7
    static let sdpStatusRemoteMedia: Int32 = 8

    static let clearCall: Int32 = 50
}
