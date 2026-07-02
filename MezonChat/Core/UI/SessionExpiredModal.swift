import UIKit

enum SessionExpiredModal {

    static func show(onLoginAgain: @escaping () -> Void) {
        Toast.isSessionInvalid = true
        DispatchQueue.main.async {
            SessionExpiredModalManager.shared.present(onLoginAgain: onLoginAgain)
        }
    }

    @MainActor
    static func removeOverlayIfPresented() {
        SessionExpiredModalManager.shared.removeOverlayImmediately()
    }
}

private final class PassthroughView: UIView {}

private final class SessionExpiredOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === rootViewController?.view {
            return nil
        }
        return hit
    }
}

private final class SessionExpiredRootViewController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 13.0, *) {
            return .darkContent
        }
        return .default
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
}

private final class SessionExpiredModalManager: NSObject, UIGestureRecognizerDelegate {

    static let shared = SessionExpiredModalManager()

    private var overlayWindow: SessionExpiredOverlayWindow?
    private var dimmingView: UIView?
    private var contentView: SessionExpiredContentView?

    private override init() {
        super.init()
    }

    func removeOverlayImmediately() {
        Toast.isSessionInvalid = false
        tearDownWindow()
    }

    func present(onLoginAgain: @escaping () -> Void) {
        tearDownWindow()

        guard let scene = activeScene else { return }

        let window = SessionExpiredOverlayWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let root = SessionExpiredRootViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root

        let dimming = UIView()
        dimming.translatesAutoresizingMaskIntoConstraints = false
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        root.view.addSubview(dimming)

        let content = SessionExpiredContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.onLoginAgain = { [weak self] in
            self?.dismiss(completion: {
                Task { @MainActor in
                    onLoginAgain()
                }
            })
        }
        content.onCancel = { [weak self] in
            self?.dismiss()
        }
        root.view.addSubview(content)

        NSLayoutConstraint.activate([
            dimming.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            dimming.topAnchor.constraint(equalTo: root.view.topAnchor),
            dimming.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),

            content.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: root.view.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: root.view.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: root.view.trailingAnchor, constant: -24),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissByTappingBackground(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        dimming.addGestureRecognizer(tap)

        window.isHidden = false
        window.makeKeyAndVisible()

        dimming.alpha = 0
        content.alpha = 0
        UIView.animate(withDuration: 0.25) {
            dimming.alpha = 1
            content.alpha = 1
        }

        overlayWindow = window
        dimmingView = dimming
        contentView = content
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let content = contentView else { return true }
        let p = touch.location(in: content)
        return !content.bounds.insetBy(dx: -1, dy: -1).contains(p)
    }

    @objc private func dismissByTappingBackground(_ gesture: UITapGestureRecognizer) {
        guard let content = contentView else { return }
        let loc = gesture.location(in: content)
        guard !content.bounds.contains(loc) else { return }
        dismiss()
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        Toast.isSessionInvalid = false
        let window = overlayWindow
        let dimming = dimmingView
        let content = contentView
        UIView.animate(withDuration: 0.2) {
            dimming?.alpha = 0
            content?.alpha = 0
        } completion: { [weak self] _ in
            window?.isHidden = true
            window?.rootViewController = nil
            if self?.overlayWindow === window {
                self?.overlayWindow = nil
                self?.dimmingView = nil
                self?.contentView = nil
            }
            completion?()
        }
    }

    private func tearDownWindow() {
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
        dimmingView = nil
        contentView = nil
    }

    private var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

private final class SessionExpiredContentView: UIView {

    var onLoginAgain: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func loginAgainTapped() { onLoginAgain?() }
    @objc private func cancelTapped() { onCancel?() }

    private func setup() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        layer.cornerRadius = 16
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = t.border.cgColor
        isUserInteractionEnabled = true

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.Error.sessionExpiredOrNetwork)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = t.textStrong
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = t.borderDim
        separator.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = L(L10n.Error.sessionExpiredContent)
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = t.text
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let loginBtn = UIButton(type: .custom)
        loginBtn.setTitle(L(L10n.Error.sessionExpiredConfirm), for: .normal)
        loginBtn.setTitleColor(.white, for: .normal)
        loginBtn.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .highlighted)
        loginBtn.backgroundColor = t.loginButtonBg
        loginBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        loginBtn.layer.cornerRadius = 10
        loginBtn.addTarget(self, action: #selector(loginAgainTapped), for: .touchUpInside)
        loginBtn.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = UIButton(type: .custom)
        cancelBtn.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelBtn.setTitleColor(t.textStrong, for: .normal)
        cancelBtn.setTitleColor(t.textStrong.withAlphaComponent(0.6), for: .highlighted)
        cancelBtn.backgroundColor = t.tertiary
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelBtn.layer.cornerRadius = 10
        cancelBtn.layer.borderWidth = 1
        cancelBtn.layer.borderColor = t.border.cgColor
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(separator)
        addSubview(messageLabel)
        addSubview(loginBtn)
        addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            separator.heightAnchor.constraint(equalToConstant: 1),

            messageLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            loginBtn.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            loginBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            loginBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            loginBtn.heightAnchor.constraint(equalToConstant: 48),

            cancelBtn.topAnchor.constraint(equalTo: loginBtn.bottomAnchor, constant: 12),
            cancelBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            cancelBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cancelBtn.heightAnchor.constraint(equalToConstant: 48),
            cancelBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }
}
