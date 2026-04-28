import UIKit

final class VoiceRecordingOverlayView: UIView {

    private enum AnimKey {
        static let slideHint = "slideHint"
        static let rightMicPulse = "rightMicPulse"
        static let rightIconPulse = "rightIconPulse"
    }

    private let gradientLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.startPoint = CGPoint(x: 1, y: 0)
        g.endPoint = CGPoint(x: 0, y: 0)
        return g
    }()

    private let leftMicBackdrop: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 20
        v.clipsToBounds = true
        return v
    }()

    private let leftMicImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iv.image = UIImage(systemName: "mic.fill")
        return iv
    }()

    private let timerLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        return l
    }()

    private let slideContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let slideChevron: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iv.image = UIImage(systemName: "chevron.left")
        return iv
    }()

    private let slideLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.text = "Slide to cancel"
        return l
    }()

    private let rightMicButton: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 20
        v.clipsToBounds = false
        return v
    }()

    private let rightMicImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iv.image = UIImage(systemName: "mic.fill")
        return iv
    }()

    private var displayLink: CADisplayLink?
    private var recordingStartedAt: CFTimeInterval = 0
    private var isSlideCancelHighlighted = false

    private static let verticalInset: CGFloat = 6
    private static let rightMicSize: CGFloat = 40
    private static let appearDuration: TimeInterval = 0.34
    private static let appearSpringDamping: CGFloat = 0.78
    private static let appearSpringVelocity: CGFloat = 0.55
    private static let appearSlideOffset: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
        clipsToBounds = false
        layer.insertSublayer(gradientLayer, at: 0)

        addSubview(leftMicBackdrop)
        leftMicBackdrop.addSubview(leftMicImageView)
        addSubview(timerLabel)
        addSubview(slideContainer)
        slideContainer.addSubview(slideChevron)
        slideContainer.addSubview(slideLabel)
        addSubview(rightMicButton)
        rightMicButton.addSubview(rightMicImageView)

        let inset = Self.verticalInset
        NSLayoutConstraint.activate([
            leftMicBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftMicBackdrop.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftMicBackdrop.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: inset),
            leftMicBackdrop.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -inset),
            leftMicBackdrop.widthAnchor.constraint(equalToConstant: 40),
            leftMicBackdrop.heightAnchor.constraint(equalToConstant: 40),

            leftMicImageView.centerXAnchor.constraint(equalTo: leftMicBackdrop.centerXAnchor),
            leftMicImageView.centerYAnchor.constraint(equalTo: leftMicBackdrop.centerYAnchor),

            timerLabel.leadingAnchor.constraint(equalTo: leftMicBackdrop.trailingAnchor, constant: 10),
            timerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timerLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: inset),
            timerLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -inset),

            slideContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            slideContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: inset),
            slideContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -inset),
            slideChevron.leadingAnchor.constraint(equalTo: slideContainer.leadingAnchor),
            slideChevron.centerYAnchor.constraint(equalTo: slideContainer.centerYAnchor),
            slideLabel.leadingAnchor.constraint(equalTo: slideChevron.trailingAnchor, constant: 4),
            slideLabel.trailingAnchor.constraint(equalTo: slideContainer.trailingAnchor),
            slideLabel.centerYAnchor.constraint(equalTo: slideContainer.centerYAnchor),

            rightMicButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightMicButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightMicButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: inset),
            rightMicButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -inset),
            rightMicButton.widthAnchor.constraint(equalToConstant: Self.rightMicSize),
            rightMicButton.heightAnchor.constraint(equalToConstant: Self.rightMicSize),

            rightMicImageView.centerXAnchor.constraint(equalTo: rightMicButton.centerXAnchor),
            rightMicImageView.centerYAnchor.constraint(equalTo: rightMicButton.centerYAnchor),
        ])

        slideContainer.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true

        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primaryGradient.cgColor, t.primary.cgColor]
        if isSlideCancelHighlighted {
            leftMicBackdrop.backgroundColor = Self.cancelTrashBackgroundColor
            leftMicImageView.tintColor = .white
        } else {
            leftMicBackdrop.backgroundColor = t.textStrong.withAlphaComponent(0.35)
            leftMicImageView.tintColor = t.textStrong
        }
        timerLabel.textColor = t.textStrong
        slideChevron.tintColor = t.textStrong
        slideLabel.textColor = t.textStrong
        rightMicButton.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        rightMicImageView.tintColor = .white
    }

    private static let cancelTrashBackgroundColor = UIColor(red: 0.90, green: 0.24, blue: 0.26, alpha: 1)

    func prepareForRecording() {
        layer.removeAllAnimations()
        transform = .identity
        setSlideCancelledHighlight(false, animated: false)
        timerLabel.text = "0:00"
        recordingStartedAt = 0
        stopDisplayLink()
        stopAllLayerAnimations()
        startSlideHintAnimation()
    }

    func markRecordingStarted() {
        recordingStartedAt = CACurrentMediaTime()
        startDisplayLink()
        startRightMicRecordingAnimations()
    }

    func tearDown() {
        stopDisplayLink()
        stopAllLayerAnimations()
        setSlideCancelledHighlight(false, animated: false)
        layer.removeAllAnimations()
        transform = .identity
        alpha = 1
    }

    func runAppearAnimation() {
        layer.removeAllAnimations()
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: Self.appearSlideOffset)
        layoutIfNeeded()
        UIView.animate(
            withDuration: Self.appearDuration,
            delay: 0,
            usingSpringWithDamping: Self.appearSpringDamping,
            initialSpringVelocity: Self.appearSpringVelocity,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(tickTimer))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tickTimer() {
        guard recordingStartedAt > 0 else { return }
        let elapsed = CACurrentMediaTime() - recordingStartedAt
        let totalSeconds = Int(elapsed)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        timerLabel.text = String(format: "%d:%02d", m, s)
    }

    private func startSlideHintAnimation() {
        slideContainer.layer.removeAnimation(forKey: AnimKey.slideHint)
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 6
        anim.toValue = -8
        anim.duration = 0.85
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        slideContainer.layer.add(anim, forKey: AnimKey.slideHint)
    }

    private func startRightMicRecordingAnimations() {
        stopRightMicAnimations()

        let rightPulse = CAKeyframeAnimation(keyPath: "transform.scale")
        rightPulse.values = [1.0, 1.09, 1.0]
        rightPulse.keyTimes = [0, 0.5, 1]
        rightPulse.duration = 0.95
        rightPulse.repeatCount = .infinity
        rightPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rightMicButton.layer.add(rightPulse, forKey: AnimKey.rightMicPulse)

        let iconPulse = CAKeyframeAnimation(keyPath: "transform.scale")
        iconPulse.values = [1.0, 1.14, 1.0]
        iconPulse.keyTimes = [0, 0.45, 1]
        iconPulse.duration = 0.55
        iconPulse.repeatCount = .infinity
        iconPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rightMicImageView.layer.add(iconPulse, forKey: AnimKey.rightIconPulse)
    }

    private func stopRightMicAnimations() {
        rightMicButton.layer.removeAnimation(forKey: AnimKey.rightMicPulse)
        rightMicImageView.layer.removeAnimation(forKey: AnimKey.rightIconPulse)
        rightMicButton.layer.transform = CATransform3DIdentity
        rightMicImageView.layer.transform = CATransform3DIdentity
        rightMicImageView.layer.opacity = 1
    }

    private func stopAllLayerAnimations() {
        slideContainer.layer.removeAnimation(forKey: AnimKey.slideHint)
        slideContainer.layer.transform = CATransform3DIdentity
        stopRightMicAnimations()
        rightMicButton.alpha = 1
    }

    func setSlideCancelledHighlight(_ cancelled: Bool, animated: Bool = true) {
        isSlideCancelHighlighted = cancelled
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let animations = {
            let t = UIColor.theme
            if cancelled {
                self.leftMicImageView.image = UIImage(systemName: "trash.fill", withConfiguration: iconConfig)
                self.leftMicBackdrop.backgroundColor = Self.cancelTrashBackgroundColor
                self.leftMicImageView.tintColor = .white
                self.slideLabel.text = "Release to delete"
            } else {
                self.leftMicImageView.image = UIImage(systemName: "mic.fill", withConfiguration: iconConfig)
                self.leftMicBackdrop.backgroundColor = t.textStrong.withAlphaComponent(0.35)
                self.leftMicImageView.tintColor = t.textStrong
                self.slideLabel.text = "Slide to cancel"
            }
            self.slideLabel.alpha = cancelled ? 0.85 : 1
            self.slideChevron.alpha = cancelled ? 0.85 : 1
            self.rightMicButton.alpha = cancelled ? 0.5 : 1
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: animations)
        } else {
            animations()
        }
    }
}
