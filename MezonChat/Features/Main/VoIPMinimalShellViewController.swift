import AsyncDisplayKit
import UIKit

final class VoIPMinimalShellViewController: ViewController {
    private let context: AccountContext

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let container = ASDisplayNode()
        container.backgroundColor = UIColor.theme.primary
        displayNode = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncomingPeerCall(_:)),
            name: .mezonIncomingPeerCall,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        flushPendingIncomingPeerCallIfNeeded()
    }

    func flushPendingIncomingPeerCallIfNeeded() {
        guard WebRTCCallManager.shared.peekPendingIncomingPeerCallPresentation() != nil else { return }
        switch peerCallIncomingPresentHost() {
        case .noHost:
            return
        case .alreadyShowing, .ready:
            break
        }
        guard let info = WebRTCCallManager.shared.peekPendingIncomingPeerCallPresentation() else { return }
        handleIncomingPeerCall(Notification(name: .mezonIncomingPeerCall, object: nil, userInfo: info))
    }

    @objc private func handleIncomingPeerCall(_ notification: Notification) {
        guard let payload = IncomingPeerCallPayload(userInfo: notification.userInfo) else {
            return
        }
        let myId: Int64? = {
            if let s = context.currentUser?.id, let v = Int64(s) { return v }
            if let s = SessionStore.load()?.userId, let v = Int64(s) { return v }
            return nil
        }()
        guard let myId else {
            return
        }
        guard payload.receiverId == myId || payload.receiverId == 0 else {
            return
        }
        switch peerCallIncomingPresentHost() {
        case .noHost:
            stashIncomingPeerCallAndScheduleFlush(notification.userInfo ?? [:])
            return
        case .alreadyShowing:
            WebRTCCallManager.shared.clearPendingIncomingPeerCallPresentation()
            return
        case .ready(let top):
            let skipRing = (notification.userInfo?["mezonSkipIncomingRingingUI"] as? Bool) == true
            let display = IncomingPeerCallPayloadParser.callerDisplay(for: payload, skipDecompressOffer: skipRing)
            let vc = PeerCallViewController(
                context: context,
                incoming: payload,
                remoteDisplayName: display.name,
                remoteAvatarURL: display.avatar,
                skipIncomingRingingUI: skipRing
            )
            if let nav = top as? UINavigationController ?? top.navigationController {
                let push = { nav.pushViewController(vc, animated: false) }
                if nav.presentedViewController != nil {
                    nav.dismiss(animated: false, completion: push)
                } else {
                    push()
                }
            } else {
                top.present(vc, animated: false, completion: nil)
            }
            WebRTCCallManager.shared.clearPendingIncomingPeerCallPresentation()
        }
    }

    private enum PeerCallIncomingPresentHost {
        case noHost
        case alreadyShowing
        case ready(UIViewController)
    }

    private func stashIncomingPeerCallAndScheduleFlush(_ userInfo: [AnyHashable: Any]) {
        WebRTCCallManager.shared.stashIncomingPeerCallPresentation(userInfo)
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingIncomingPeerCallIfNeeded()
        }
        for delay in [0.05, 0.2, 0.6] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flushPendingIncomingPeerCallIfNeeded()
            }
        }
    }

    private func peerCallApplicationModalRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
            .filter { [.foregroundActive, .foregroundInactive].contains($0.activationState) }
        for scene in scenes {
            if let w = scene.windows.first(where: { $0.isKeyWindow }),
               let r = w.rootViewController,
               !(r is SplashViewController) {
                return r
            }
        }
        for scene in scenes {
            let ordered = scene.windows.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
            for w in ordered {
                guard !w.isHidden, w.alpha > 0 else { continue }
                guard w.windowLevel == .normal, let r = w.rootViewController else { continue }
                if r is SplashViewController { continue }
                return r
            }
        }
        if isViewLoaded, let w = view.window, let r = w.rootViewController, !(r is SplashViewController) {
            return r
        }
        return nil
    }

    private func peerCallIncomingPresentHost() -> PeerCallIncomingPresentHost {
        guard let root = peerCallApplicationModalRootViewController() else {
            return .noHost
        }
        if let nav = root as? UINavigationController,
           nav.viewControllers.contains(where: { $0 is PeerCallViewController }) {
            return .alreadyShowing
        }
        var top = root
        while let presented = top.presentedViewController {
            if presented is PeerCallViewController { return .alreadyShowing }
            top = presented
        }
        return .ready(top)
    }
}
