import AVFoundation
import Foundation
import WebRTC

enum SfuRole: String {
    case speaker
    case audience

    static func fromWire(_ value: String?) -> SfuRole {
        value == "audience" ? .audience : .speaker
    }
}

enum SfuConnectionState {
    case connecting
    case joining
    case awaitingOffer
    case connected
    case disconnected
    case failed
}

struct SfuParticipant {
    let id: String
    let userId: String?
    let role: SfuRole?
    let muted: Bool
    let audio: RTCAudioTrack?
    let video: RTCVideoTrack?
    let screen: RTCVideoTrack?
    let screenActive: Bool
    let cameraActive: Bool
}
