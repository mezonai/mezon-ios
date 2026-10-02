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
    case iceConnected
    case dtlsHandshake
    case awaitingConfirmation
    case connected
    case disconnected
    case failed
}

enum SfuRemovalCause {
    case kicked
    case aloneTimeout
    case duplicateSession
    case disconnected
}

struct SfuParticipant {
    let id: String
    let userId: String?
    let peerId: String?
    let role: SfuRole?
    let muted: Bool
    let audio: RTCAudioTrack?
    let video: RTCVideoTrack?
    let screen: RTCVideoTrack?
    let screenActive: Bool
    let cameraActive: Bool
}

// First admission also waits for presence; recovered transports use SFU evidence.
struct SfuConnectionReadiness {
    var requiresVoiceJoined = true
    var iceConnected = false
    var transportConnected = false
    var roomConfirmed = false
    var peerId: String?
    private var confirmedPeerIds: [String] = []
    private var receivedLegacyVoiceJoined = false

    init(requiresVoiceJoined: Bool = true) {
        self.requiresVoiceJoined = requiresVoiceJoined
    }

    mutating func confirmVoiceJoined(peerId: String?) {
        guard let peerId, !peerId.isEmpty, peerId != "0" else {
            // Older presence payloads omit peer_id. The caller still checks
            // current user/clan/room; transport + snapshot remain mandatory.
            receivedLegacyVoiceJoined = true
            return
        }
        if !confirmedPeerIds.contains(peerId) {
            confirmedPeerIds.append(peerId)
            if confirmedPeerIds.count > 8 { confirmedPeerIds.removeFirst() }
        }
    }

    var voiceJoinedConfirmed: Bool {
        receivedLegacyVoiceJoined || peerId.map { confirmedPeerIds.contains($0) } == true
    }

    var isReady: Bool {
        guard iceConnected, transportConnected, roomConfirmed,
              let peerId, !peerId.isEmpty, peerId != "0" else { return false }
        return !requiresVoiceJoined || voiceJoinedConfirmed
    }
}
