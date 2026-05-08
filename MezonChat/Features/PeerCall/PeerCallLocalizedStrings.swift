import Foundation

enum PeerCallLocalizedStrings {

    static var actionEnd: String { L(L10n.PeerCall.actionEnd) }
    static var actionMic: String { L(L10n.PeerCall.actionMic) }
    static var actionSpeaker: String { L(L10n.PeerCall.actionSpeaker) }
    static var actionCancel: String { L(L10n.PeerCall.actionCancel) }
    static var actionOK: String { L(L10n.PeerCall.actionOK) }

    static var titleDefaultOutgoing: String { L(L10n.PeerCall.titleDefaultOutgoing) }
    static var titleDefaultIncoming: String { L(L10n.PeerCall.titleDefaultIncoming) }

    static var statusRinging: String { L(L10n.PeerCall.statusRinging) }
    static var statusIncoming: String { L(L10n.PeerCall.statusIncoming) }
    static var statusConnecting: String { L(L10n.PeerCall.statusConnecting) }
    static var statusConnected: String { L(L10n.PeerCall.statusConnected) }
    static var statusMissed: String { L(L10n.PeerCall.statusMissed) }
    static var statusNoAnswer: String { L(L10n.PeerCall.statusNoAnswer) }
    static var statusCouldNotConnect: String { L(L10n.PeerCall.statusCouldNotConnect) }
    static var statusBusyOnAnotherCall: String { "User is currently on another call" }
    static var statusUserOffline: String { "User is not available" }
    static var statusRemoteDeclined: String { "Call declined" }
    static var statusRemoteEnded: String { "Call ended" }

    static var errorMicrophoneDenied: String { L(L10n.PeerCall.errorMicrophoneDenied) }
    static var errorCameraDenied: String { L(L10n.PeerCall.errorCameraDenied) }
    static var errorCouldNotStartCall: String { L(L10n.PeerCall.errorCouldNotStartCall) }
    static var errorCouldNotAnswerCall: String { L(L10n.PeerCall.errorCouldNotAnswerCall) }

    static var alertEndCallTitle: String { L(L10n.PeerCall.alertEndCallTitle) }
    static var alertEndCallMessage: String { L(L10n.PeerCall.alertEndCallMessage) }

    static var bannerWeakNetwork: String { L(L10n.PeerCall.bannerWeakNetwork) }

    static func remoteMicOffBanner(name: String) -> String {
        L(L10n.PeerCall.remoteMicOffBanner, name)
    }
}
