import UIKit

enum ToastType {
    case success
    case error
    case info
    case notification
}

final class Toast {

    static let defaultDuration: TimeInterval = 3

    static var isSessionInvalid = false

    static func show(
        _ type: ToastType,
        title: String? = nil,
        message: String,
        duration: TimeInterval = defaultDuration
    ) {
        DispatchQueue.main.async {
            ToastManager.shared.present(type: type, title: title, message: message, duration: duration)
        }
    }

    static func success(_ message: String, title: String? = nil) {
        show(.success, title: title, message: message)
    }

    static func error(_ message: String, title: String? = nil) {
        if isSessionInvalid { return }
        show(.error, title: title, message: message)
    }

    static func info(_ message: String, title: String? = nil) {
        show(.info, title: title, message: message)
    }

    static func notification(title: String, message: String, onTap: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            ToastManager.shared.present(type: .notification, title: title, message: message, duration: 4, onTap: onTap)
        }
    }

    static func comingSoonLine(_ line: String, duration: TimeInterval = defaultDuration) {
        DispatchQueue.main.async {
            ToastManager.shared.presentComingSoonPill(message: line, duration: duration)
        }
    }
}

private final class ToastManager {

    static let shared = ToastManager()
    private static let overlayZPosition: CGFloat = 10_000

    private var toastContainer: UIView?
    private var toastWindow: UIWindow?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func present(type: ToastType, title: String?, message: String, duration: TimeInterval, onTap: (() -> Void)? = nil) {
        dismissWorkItem?.cancel()


        toastContainer?.removeFromSuperview()
        toastContainer = nil
        toastWindow?.isHidden = true
        toastWindow = nil

        guard let hostView = makeToastHostView() else { return }

        let toastView = ToastView(type: type, title: title, message: message)
        toastView.onClose = { [weak self] in self?.dismiss() }
        toastView.onTap = {
            onTap?()
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.zPosition = Self.overlayZPosition
        container.addSubview(toastView)

        hostView.addSubview(container)
        hostView.bringSubviewToFront(container)

        let safeTop = hostView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: hostView.leadingAnchor, constant: 16.sw),
            container.trailingAnchor.constraint(equalTo: hostView.trailingAnchor, constant: -16.sw),
            container.topAnchor.constraint(equalTo: safeTop.topAnchor, constant: 12.sh),
            toastView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toastView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toastView.topAnchor.constraint(equalTo: container.topAnchor),
            toastView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        toastContainer = container
        toastView.transform = CGAffineTransform(translationX: 0, y: -20)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            toastView.transform = .identity
        }

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        toastContainer?.removeFromSuperview()
        toastContainer = nil
        toastWindow?.isHidden = true
        toastWindow = nil
    }

    func presentComingSoonPill(message: String, duration: TimeInterval) {
        dismissWorkItem?.cancel()
        toastContainer?.removeFromSuperview()
        toastContainer = nil
        toastWindow?.isHidden = true
        toastWindow = nil
        guard let hostView = makeToastHostView() else { return }
        let pill = ComingSoonPillView(message: message)
        pill.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.zPosition = Self.overlayZPosition
        container.addSubview(pill)
        hostView.addSubview(container)
        hostView.bringSubviewToFront(container)
        let safe = hostView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: 20.sw),
            container.trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -20.sw),
            container.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -20.sh),
            container.widthAnchor.constraint(lessThanOrEqualTo: hostView.widthAnchor, constant: -40.sw),
            pill.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        toastContainer = container
        pill.transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            pill.transform = .identity
        }
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func makeToastHostView() -> UIView? {
        let window: ToastPassthroughWindow
        let statusBarStyle: UIStatusBarStyle
        if #available(iOS 13.0, *) {
            guard let scene = Self.findWindowScene() else { return nil }
            statusBarStyle = Self.currentStatusBarStyle(in: scene)
            window = ToastPassthroughWindow(windowScene: scene)
        } else {
            statusBarStyle = Self.legacyStatusBarStyle()
            window = ToastPassthroughWindow(frame: UIScreen.main.bounds)
        }
        window.backgroundColor = .clear
        window.windowLevel = .alert + 1
        let controller = ToastRootViewController(statusBarStyle: statusBarStyle)
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = false
        toastWindow = window
        return controller.view
    }

    private static func legacyStatusBarStyle() -> UIStatusBarStyle {
        if let root = UIApplication.shared.keyWindow?.rootViewController {
            return root.preferredStatusBarStyle
        }
        return ThemeManager.shared.preferredStatusBarStyle
    }

    @available(iOS 13.0, *)
    private static func currentStatusBarStyle(in scene: UIWindowScene) -> UIStatusBarStyle {
        let candidateWindows = scene.windows.filter { window in
            window.isKeyWindow && !window.isHidden && !(window is ToastPassthroughWindow)
        }

        if let rootViewController = candidateWindows.first?.rootViewController {
            return rootViewController.preferredStatusBarStyle
        }

        return ThemeManager.shared.preferredStatusBarStyle
    }

    @available(iOS 13.0, *)
    private static func findWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return scene
        }
        for scene in scenes {
            if let win = scene.windows.first(where: { $0.isKeyWindow }) {
                return win.windowScene
            }
        }
        return scenes.first
    }
}

private final class ToastRootViewController: UIViewController {
    private let statusBarStyle: UIStatusBarStyle

    init(statusBarStyle: UIStatusBarStyle) {
        self.statusBarStyle = statusBarStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        statusBarStyle
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }
}

private final class ToastPassthroughWindow: UIWindow {
    override var canBecomeKey: Bool {
        false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView === rootViewController?.view {
            return nil
        }
        return hitView
    }
}

private final class ToastView: UIView {

    var onClose: (() -> Void)?
    var onTap: (() -> Void)?

    private let type: ToastType
    private let titleText: String?
    private let messageText: String

    private let contentView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let cornerRadius: CGFloat = 12.sw

    init(type: ToastType, title: String?, message: String) {
        self.type = type
        self.titleText = title
        self.messageText = message
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    }

    private func setup() {
        let config = Self.config(for: type)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 10

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = UIColor.white
        contentView.layer.cornerRadius = cornerRadius
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = config.borderColor.cgColor
        contentView.layer.masksToBounds = true

        gradientLayer.colors = [
            config.bgGradientStart.cgColor,
            config.bgGradientEnd.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        contentView.layer.insertSublayer(gradientLayer, at: 0)

        addSubview(contentView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let leftBar = UIView()
        leftBar.backgroundColor = config.accentColor
        leftBar.translatesAutoresizingMaskIntoConstraints = false

        let iconBg = UIView()
        iconBg.backgroundColor = config.accentColor
        iconBg.layer.cornerRadius = 18.swh
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage.mezonSystemImage(config.iconName))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)

        let titleLabel = UILabel()
        let resolvedTitle: String? = {
            if let titleText {
                let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return config.defaultTitle
        }()
        titleLabel.text = resolvedTitle
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .bold)
        titleLabel.textColor = type == .notification ? UIColor.theme.textStrong : .init(white: 0.1, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = resolvedTitle == nil

        let messageLabel = UILabel()
        messageLabel.text = messageText
        messageLabel.font = .systemFont(ofSize: 14.sf)
        messageLabel.textColor = type == .notification ? UIColor.theme.text : .init(white: 0.25, alpha: 1)
        messageLabel.numberOfLines = 3
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage.mezonSystemImage("xmark"), for: .normal)
        closeBtn.tintColor = type == .notification ? UIColor.theme.iconSecondary : .init(white: 0.3, alpha: 1)
        closeBtn.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(leftBar)
        contentView.addSubview(iconBg)
        contentView.addSubview(closeBtn)

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 4.sh
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        if resolvedTitle != nil {
            textStack.addArrangedSubview(titleLabel)
        }
        textStack.addArrangedSubview(messageLabel)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            leftBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            leftBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            leftBar.widthAnchor.constraint(equalToConstant: 4.sw),

            iconBg.leadingAnchor.constraint(equalTo: leftBar.trailingAnchor, constant: 12.sw),
            iconBg.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 36.swh),
            iconBg.heightAnchor.constraint(equalToConstant: 36.swh),
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18.swh),
            iconView.heightAnchor.constraint(equalToConstant: 18.swh),

            textStack.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12.sw),
            textStack.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -12.sw),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 14.sh),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: textStack.bottomAnchor, constant: 14.sh),

            closeBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),
            closeBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 32.swh),
            closeBtn.heightAnchor.constraint(equalToConstant: 32.swh),
        ])
    }

    private static func config(for type: ToastType) -> (
        accentColor: UIColor,
        bgGradientStart: UIColor,
        bgGradientEnd: UIColor,
        borderColor: UIColor,
        iconName: String,
        defaultTitle: String
    ) {
        switch type {
        case .success:
            return (hex("#22c55e"), hex("#86efac"), hex("#dcfce7"), hex("#86efac"), "checkmark", "Success")
        case .error:
            return (hex("#ef4444"), hex("#fca5a5"), hex("#fef2f2"), hex("#fca5a5"), "xmark", "Error")
        case .info:
            return (hex("#3b82f6"), hex("#93c5fd"), hex("#eff6ff"), hex("#93c5fd"), "info.circle.fill", "Info")
        case .notification:
            return (UIColor.theme.iconPrimary, UIColor.theme.secondary, UIColor.theme.secondary, UIColor.theme.border, "bell.fill", "Notification")
        }
    }

    @objc private func closeButtonTapped() {
        onClose?()
    }

    @objc private func handleTap() {
        onTap?()
        onClose?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationY = gesture.translation(in: self).y
        switch gesture.state {
        case .changed:
            transform = CGAffineTransform(translationX: 0, y: min(0, translationY))
        case .ended, .cancelled:
            let velocityY = gesture.velocity(in: self).y
            if translationY < -24.sh || velocityY < -500 {
                dismissBySwipe()
            } else {
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                    self.transform = .identity
                }
            }
        default:
            break
        }
    }

    private func dismissBySwipe() {
        let target = -(bounds.height + 80.sh)
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
            self.transform = CGAffineTransform(translationX: 0, y: target)
            self.alpha = 0
        } completion: { _ in
            self.onClose?()
        }
    }
}

private final class ComingSoonPillView: UIView {
    init(message: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.2, alpha: 1)
        layer.cornerRadius = 24.swh
        layer.masksToBounds = true
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 15.sf, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18.sw),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18.sw),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12.sh),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12.sh)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private func hex(_ value: String) -> UIColor {
    var str = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.hasPrefix("#") { str = String(str.dropFirst()) }
    let scanner = Scanner(string: str)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return UIColor(
        red:   CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >>  8) & 0xFF) / 255,
        blue:  CGFloat( rgb        & 0xFF) / 255,
        alpha: 1
    )
}
