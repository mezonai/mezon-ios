import UIKit

enum SessionExpiredModal {

    static func show(onLoginAgain: @escaping () -> Void) {
        DispatchQueue.main.async {
            SessionExpiredModalManager.shared.present(onLoginAgain: onLoginAgain)
        }
    }
}

private final class SessionExpiredModalManager {

    static let shared = SessionExpiredModalManager()

    private var overlayContainer: UIView?

    private init() {}

    func present(onLoginAgain: @escaping () -> Void) {
        overlayContainer?.removeFromSuperview()

        guard let window = keyWindow else { return }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        let contentView = SessionExpiredContentView()
        contentView.onLoginAgain = { [weak self] in
            onLoginAgain()
            self?.dismiss()
        }
        contentView.onCancel = { [weak self] in
            self?.dismiss()
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)

        window.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            container.topAnchor.constraint(equalTo: window.topAnchor),
            container.bottomAnchor.constraint(equalTo: window.bottomAnchor),

            contentView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])

        overlayContainer = container
        contentView.alpha = 0
        container.alpha = 0
        UIView.animate(withDuration: 0.25) {
            container.alpha = 1
            contentView.alpha = 1
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissByTappingBackground(_:)))
        tap.cancelsTouchesInView = false
        container.addGestureRecognizer(tap)
    }

    @objc private func dismissByTappingBackground(_ gesture: UITapGestureRecognizer) {
        guard let container = overlayContainer, let contentView = container.subviews.first else { return }
        let loc = gesture.location(in: container)
        guard !contentView.frame.contains(loc) else { return }
        dismiss()
    }

    private func dismiss() {
        UIView.animate(withDuration: 0.2) {
            self.overlayContainer?.alpha = 0
        } completion: { _ in
            self.overlayContainer?.removeFromSuperview()
            self.overlayContainer = nil
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
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
        backgroundColor = .white
        layer.cornerRadius = 16
        clipsToBounds = true

        let t = UIColor.theme

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
        messageLabel.textColor = t.textNormal
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let loginBtn = UIButton(type: .system)
        loginBtn.setTitle(L(L10n.Error.sessionExpiredConfirm), for: .normal)
        loginBtn.setTitleColor(.white, for: .normal)
        loginBtn.backgroundColor = t.primary
        loginBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        loginBtn.layer.cornerRadius = 10
        loginBtn.addTarget(self, action: #selector(loginAgainTapped), for: .touchUpInside)
        loginBtn.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelBtn.setTitleColor(t.textStrong, for: .normal)
        cancelBtn.backgroundColor = t.tertiary
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelBtn.layer.cornerRadius = 10
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
