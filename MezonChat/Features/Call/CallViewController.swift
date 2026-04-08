import Foundation
import UIKit

final class CallViewController: UIViewController {

    private let context: AccountContext
    private let remoteUserName: String
    private let remoteAvatarURL: String?
    private let remoteUserId: Int64
    private let dmChannelId: Int64
    private let isOutgoing: Bool
    private let offerSdp: String?

    private let closeButton = UIButton(type: .system)
    private let avatarImageView = UIImageView()
    private let ringView = UIView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let durationLabel = UILabel()
    private let speakerButton = UIButton(type: .system)
    private let speakerLabel = UILabel()
    private let endButton = UIButton(type: .system)
    private let endLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let micLabel = UILabel()

    private var durationTimer: Foundation.Timer?
    private var rippleTimer: Foundation.Timer?
    private var callManager: WebRTCCallManager { WebRTCCallManager.shared }

    init(
        context: AccountContext,
        remoteUserName: String,
        remoteAvatarURL: String?,
        remoteUserId: Int64,
        dmChannelId: Int64,
        isOutgoing: Bool,
        offerSdp: String? = nil
    ) {
        self.context = context
        self.remoteUserName = remoteUserName
        self.remoteAvatarURL = remoteAvatarURL
        self.remoteUserId = remoteUserId
        self.dmChannelId = dmChannelId
        self.isOutgoing = isOutgoing
        self.offerSdp = offerSdp
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0)
        setupUI()
        bindCallManager()
        beginCall()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            unbindCallManager()
        }
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private func setupUI() {
        closeButton.setImage(UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.clipsToBounds = false
        view.addSubview(ringView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 55
        avatarImageView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(avatarImageView)
        loadAvatar()

        nameLabel.text = remoteUserName
        nameLabel.font = .systemFont(ofSize: 26, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        statusLabel.text = isOutgoing ? "Ringing..." : "Incoming call..."
        statusLabel.font = .systemFont(ofSize: 16, weight: .regular)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        durationLabel.text = "00:00"
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        durationLabel.textAlignment = .center
        durationLabel.isHidden = true
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(durationLabel)

        setupBottomControls()

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            ringView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ringView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            ringView.widthAnchor.constraint(equalToConstant: 260),
            ringView.heightAnchor.constraint(equalToConstant: 260),

            avatarImageView.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 110),
            avatarImageView.heightAnchor.constraint(equalToConstant: 110),

            nameLabel.topAnchor.constraint(equalTo: ringView.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            durationLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            durationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            durationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if rippleTimer == nil && callManager.connectionState != .connected && callManager.connectionState != .ended {
            startRippleAnimation()
        }
    }

    private func startRippleAnimation() {
        rippleTimer?.invalidate()
        rippleTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.addRippleLayer()
        }
        addRippleLayer()
    }

    private func stopRippleAnimation() {
        rippleTimer?.invalidate()
        rippleTimer = nil
        ringView.layer.sublayers?.forEach { sub in
            sub.removeAllAnimations()
            sub.removeFromSuperlayer()
        }
    }

    private func addRippleLayer() {
        let center = CGPoint(x: ringView.bounds.midX, y: ringView.bounds.midY)
        let initialRadius: CGFloat = 55
        let finalRadius: CGFloat = 130

        let ripple = CAShapeLayer()
        let initialPath = UIBezierPath(arcCenter: center, radius: initialRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        let finalPath = UIBezierPath(arcCenter: center, radius: finalRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ripple.path = initialPath.cgPath
        ripple.fillColor = UIColor.clear.cgColor
        ripple.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        ripple.lineWidth = 2
        ripple.opacity = 0
        ringView.layer.addSublayer(ripple)

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = initialPath.cgPath
        pathAnim.toValue = finalPath.cgPath

        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [0.0, 0.4, 0.0]
        opacityAnim.keyTimes = [0, 0.3, 1.0]

        let group = CAAnimationGroup()
        group.animations = [pathAnim, opacityAnim]
        group.duration = 2.0
        group.isRemovedOnCompletion = true
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak ripple] in
            ripple?.removeFromSuperlayer()
        }
        ripple.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    private func setupBottomControls() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        configureFunctionButton(speakerButton, icon: "speaker.wave.2.fill", size: 55, bg: UIColor.white.withAlphaComponent(0.15))
        speakerButton.addTarget(self, action: #selector(speakerTapped), for: .touchUpInside)
        speakerLabel.text = "Speaker"
        speakerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        speakerLabel.textColor = .white
        speakerLabel.textAlignment = .center
        let speakerStack = makeControlStack(button: speakerButton, label: speakerLabel)
        stack.addArrangedSubview(speakerStack)

        configureFunctionButton(endButton, icon: "phone.down.fill", size: 55, bg: .systemRed)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)
        endLabel.text = "End"
        endLabel.font = .systemFont(ofSize: 12, weight: .medium)
        endLabel.textColor = .white
        endLabel.textAlignment = .center
        let endStack = makeControlStack(button: endButton, label: endLabel)
        stack.addArrangedSubview(endStack)

        configureFunctionButton(micButton, icon: "mic.fill", size: 55, bg: .white)
        micButton.tintColor = .black
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micLabel.text = "Mic"
        micLabel.font = .systemFont(ofSize: 12, weight: .medium)
        micLabel.textColor = .white
        micLabel.textAlignment = .center
        let micStack = makeControlStack(button: micButton, label: micLabel)
        stack.addArrangedSubview(micStack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            stack.heightAnchor.constraint(equalToConstant: 90),
        ])
    }

    private func configureFunctionButton(_ button: UIButton, icon: String, size: CGFloat, bg: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        button.setImage(UIImage(systemName: icon)?.withConfiguration(config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = bg
        button.layer.cornerRadius = size / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])
    }

    private func makeControlStack(button: UIButton, label: UILabel) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [button, label])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    private func loadAvatar() {
        guard let urlString = remoteAvatarURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            setAvatarPlaceholder()
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { self?.setAvatarPlaceholder() }
                return
            }
            DispatchQueue.main.async { self?.avatarImageView.image = image }
        }.resume()
    }

    private func setAvatarPlaceholder() {
        let initial = String(remoteUserName.prefix(1).uppercased())
        let size: CGFloat = 110
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        if let ctx = UIGraphicsGetCurrentContext() {
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.4).cgColor)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.4, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = (initial as NSString).size(withAttributes: attrs)
            (initial as NSString).draw(
                at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
                withAttributes: attrs
            )
        }
        avatarImageView.image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }

    private func beginCall() {
        guard let myUserId = Int64(context.currentUser?.id ?? "") else { return }

        if isOutgoing {
            let myName = context.currentUser?.displayName ?? "Unknown"
            let myAvatar = context.currentUser?.avatarURL?.absoluteString ?? ""
            callManager.startCall(
                receiverId: remoteUserId,
                channelId: dmChannelId,
                callerId: myUserId,
                callerName: myName,
                callerAvatar: myAvatar
            )
        } else if let sdp = offerSdp {
            callManager.answerCall(
                receiverId: remoteUserId,
                channelId: dmChannelId,
                callerId: myUserId,
                offerSdp: sdp
            )
        }
    }

    private func bindCallManager() {
        callManager.onStateChanged = { [weak self] state in
            self?.updateUI(for: state)
        }
        callManager.onCallEnded = { [weak self] in
            self?.handleCallEnded()
        }
    }

    private func unbindCallManager() {
        durationTimer?.invalidate()
        durationTimer = nil
        callManager.onStateChanged = nil
        callManager.onCallEnded = nil
    }

    private func updateUI(for state: CallConnectionState) {
        switch state {
        case .idle:
            statusLabel.text = "Initializing..."
            statusLabel.isHidden = false
            durationLabel.isHidden = true
        case .ringing:
            statusLabel.text = isOutgoing ? "Ringing..." : "Incoming call..."
            statusLabel.isHidden = false
            durationLabel.isHidden = true
        case .connecting:
            statusLabel.text = "Connecting..."
            statusLabel.isHidden = false
            durationLabel.isHidden = true
        case .connected:
            statusLabel.isHidden = true
            durationLabel.isHidden = false
            startDurationTimer()
            stopRippleAnimation()
        case .ended:
            durationTimer?.invalidate()
            stopRippleAnimation()
            statusLabel.text = "Call ended"
            statusLabel.isHidden = false
            durationLabel.isHidden = true
        }
        updateMediaButtons()
    }

    private func updateMediaButtons() {
        let micOn = callManager.isMicEnabled
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        micButton.setImage(
            UIImage(systemName: micOn ? "mic.fill" : "mic.slash.fill")?.withConfiguration(config),
            for: .normal
        )
        micButton.backgroundColor = micOn ? .white : UIColor.white.withAlphaComponent(0.15)
        micButton.tintColor = micOn ? .black : .white

        let speakerOn = callManager.isSpeakerEnabled
        speakerButton.setImage(
            UIImage(systemName: speakerOn ? "speaker.wave.2.fill" : "speaker.wave.2")?.withConfiguration(config),
            for: .normal
        )
        speakerButton.backgroundColor = speakerOn ? .white : UIColor.white.withAlphaComponent(0.15)
        speakerButton.tintColor = speakerOn ? .black : .white
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (_: Foundation.Timer) in
            guard let self, let start = self.callManager.timeStartConnected else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let min = elapsed / 60
            let sec = elapsed % 60
            self.durationLabel.text = String(format: "%02d:%02d", min, sec)
        }
    }

    private func handleCallEnded() {
        durationTimer?.invalidate()
        statusLabel.text = "Call ended"
        statusLabel.isHidden = false
        durationLabel.isHidden = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.callManager.resetToIdle()
            self?.dismiss(animated: true)
        }
    }

    @objc private func closeTapped() {
        callManager.endCall(sendQuit: true)
    }

    @objc private func endTapped() {
        callManager.endCall(sendQuit: true)
    }

    @objc private func micTapped() {
        callManager.toggleMic()
        updateMediaButtons()
    }

    @objc private func speakerTapped() {
        callManager.toggleSpeaker()
        updateMediaButtons()
    }

    deinit {
        durationTimer?.invalidate()
        rippleTimer?.invalidate()
    }
}
