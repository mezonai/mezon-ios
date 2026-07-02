import UIKit

enum RapidClanSwitchNotice {

    static func show() {
        DispatchQueue.main.async {
            RapidClanSwitchNoticeManager.shared.present()
        }
    }
}

private final class RapidClanSwitchOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === rootViewController?.view {
            return nil
        }
        return hit
    }
}

private final class RapidClanSwitchRootViewController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        ThemeManager.shared.preferredStatusBarStyle
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
}

private final class RapidClanSwitchNoticeManager {

    static let shared = RapidClanSwitchNoticeManager()

    private var overlayWindow: RapidClanSwitchOverlayWindow?
    private var dimmingView: UIView?
    private var contentView: RapidClanSwitchContentView?
    private var isPresented = false

    private init() {}

    func present() {
        guard !isPresented else { return }
        guard let scene = activeScene else { return }

        let window = RapidClanSwitchOverlayWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let root = RapidClanSwitchRootViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root

        let dimming = UIView()
        dimming.translatesAutoresizingMaskIntoConstraints = false
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        root.view.addSubview(dimming)

        let content = RapidClanSwitchContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.onConfirm = { [weak self] in self?.dismiss() }
        root.view.addSubview(content)

        NSLayoutConstraint.activate([
            dimming.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            dimming.topAnchor.constraint(equalTo: root.view.topAnchor),
            dimming.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),

            content.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: root.view.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: root.view.leadingAnchor, constant: 32),
            content.trailingAnchor.constraint(equalTo: root.view.trailingAnchor, constant: -32),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissByTappingBackground(_:)))
        tap.cancelsTouchesInView = false
        dimming.addGestureRecognizer(tap)

        window.isHidden = false
        window.makeKeyAndVisible()

        dimming.alpha = 0
        content.alpha = 0
        content.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            dimming.alpha = 1
            content.alpha = 1
            content.transform = .identity
        }

        overlayWindow = window
        dimmingView = dimming
        contentView = content
        isPresented = true
    }

    @objc private func dismissByTappingBackground(_ gesture: UITapGestureRecognizer) {
        guard let content = contentView else { return }
        let loc = gesture.location(in: content)
        guard !content.bounds.contains(loc) else { return }
        dismiss()
    }

    private func dismiss() {
        let window = overlayWindow
        let dimming = dimmingView
        let content = contentView
        UIView.animate(withDuration: 0.18, animations: {
            dimming?.alpha = 0
            content?.alpha = 0
            content?.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { [weak self] _ in
            window?.isHidden = true
            window?.rootViewController = nil
            if self?.overlayWindow === window {
                self?.overlayWindow = nil
                self?.dimmingView = nil
                self?.contentView = nil
                self?.isPresented = false
            }
        })
    }

    private var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

private final class RapidClanSwitchContentView: UIView {

    var onConfirm: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func confirmTapped() { onConfirm?() }

    private func setup() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        layer.cornerRadius = 16
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = t.border.cgColor

        let iconBg = UIView()
        iconBg.backgroundColor = t.iconPrimary.withAlphaComponent(0.12)
        iconBg.layer.cornerRadius = 28
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "hand.raised.fill"))
        iconView.tintColor = t.iconPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanSwitch.rapidTitle)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = t.textStrong
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = L(L10n.ClanSwitch.rapidMessage)
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = t.text
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let confirmBtn = UIButton(type: .custom)
        confirmBtn.setTitle(L(L10n.ClanSwitch.rapidConfirm), for: .normal)
        confirmBtn.setTitleColor(.white, for: .normal)
        confirmBtn.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .highlighted)
        confirmBtn.backgroundColor = t.loginButtonBg
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        confirmBtn.layer.cornerRadius = 10
        confirmBtn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBg)
        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(confirmBtn)

        NSLayoutConstraint.activate([
            iconBg.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            iconBg.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 56),
            iconBg.heightAnchor.constraint(equalToConstant: 56),
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: iconBg.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            confirmBtn.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            confirmBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            confirmBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            confirmBtn.heightAnchor.constraint(equalToConstant: 48),
            confirmBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }
}
