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

struct SfuParticipant: Equatable {
    let id: String
    let userId: String?
    let peerId: String?
    let role: SfuRole?
    let muted: Bool
    let audio: RTCAudioTrack?
    let video: RTCVideoTrack?
    let screen: RTCVideoTrack?
    let screenActive: Bool
    let screenPublishing: Bool
    let cameraActive: Bool

    static func == (lhs: SfuParticipant, rhs: SfuParticipant) -> Bool {
        lhs.id == rhs.id && lhs.userId == rhs.userId && lhs.peerId == rhs.peerId
            && lhs.role == rhs.role && lhs.muted == rhs.muted
            && lhs.audio === rhs.audio && lhs.video === rhs.video && lhs.screen === rhs.screen
            && lhs.screenActive == rhs.screenActive && lhs.screenPublishing == rhs.screenPublishing
            && lhs.cameraActive == rhs.cameraActive
    }
}

struct SfuPeerProfile: Equatable {
    let name: String?
    let avatarURL: String?

    init?(metadata: String?) {
        let raw = metadata?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        var name: String?
        var avatar: String?
        if raw.hasPrefix("{"),
           let data = raw.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            name = Self.field(object["username"])
            avatar = Self.field(object["avatar"])
        } else if let separator = raw.lastIndex(of: ";") {
            name = Self.field(String(raw[..<separator]))
            avatar = Self.field(String(raw[raw.index(after: separator)...]))
        } else {
            name = Self.field(raw)
        }
        guard name != nil || avatar != nil else { return nil }
        self.name = name
        self.avatarURL = avatar
    }

    private static func field(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text != "undefined" else { return nil }
        return text
    }
}

struct ExternalMeetingRoom: Equatable {
    let code: String
    let title: String
    let roomId: Int64

    init?(externalLink: String, title: String) {
        guard let url = MezonConfig.externalEventURL(externalLink) else { return nil }
        self.init(url: url, title: title)
    }

    init?(meetingURL url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let configuredHost = URL(string: MezonConfig.chatWebAppBaseURL)?.host?.lowercased()
        guard host == "mezon.ai" || host.hasSuffix(".mezon.ai") || host == configuredHost else { return nil }
        self.init(url: url, title: "")
    }

    private init?(url: URL, title: String) {
        let path = url.pathComponents
        guard path.count == 3, path[1].lowercased() == "meeting" else { return nil }
        let code = path[2]
        guard !code.isEmpty else { return nil }
        self.code = code
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.roomId = Self.roomId(code: code)
    }

    var channelDescription: Mezon_Api_ChannelDescription {
        var channel = Mezon_Api_ChannelDescription()
        channel.channelID = roomId
        channel.channelLabel = title.isEmpty ? L(L10n.VoiceChannel.externalCall) : title
        channel.type = MezonConstants.ChannelType.mezonVoice.rawValue
        return channel
    }

    static func sfuIdentity(username: String?, displayName: String?, userId: String?) -> String {
        for candidate in [username, displayName] {
            let identity = String((candidate ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12))
            if !identity.isEmpty { return identity }
        }
        if let id = userId.flatMap({ Int64($0) }), id > 0 {
            return String(String(id, radix: 36).prefix(12))
        }
        return "guest"
    }

    private static func roomId(code: String) -> Int64 {
        if let payload = code.split(separator: ".").first {
            var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            if let data = Data(base64Encoded: base64),
               let decoded = String(data: data, encoding: .utf8),
               let meetId = decoded.split(separator: ":").last.flatMap({ Int64($0) }), meetId > 0 {
                return meetId
            }
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in code.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int64(bitPattern: hash & UInt64(Int64.max)) | 1
    }
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
