import Foundation

enum WebRTCSignalingType: Int32 {
    case sdpOffer                = 1
    case sdpAnswer               = 2
    case iceCandidate            = 3
    case sdpQuit                 = 4
    case sdpTimeout              = 5
    case sdpInit                 = 6
    case sdpStatusRemoteMedia    = 7
    case sdpJoinedOtherCall      = 8
}
