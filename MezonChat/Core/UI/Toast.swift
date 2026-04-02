import UIKit

enum ToastType {
    case success
    case error
    case info
    case notification
}

final class Toast {

    static let defaultDuration: TimeInterval = 3

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
}

private final class ToastManager {

    static let shared = ToastManager()

    private var toastContainer: UIView?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func present(type: ToastType, title: String?, message: String, duration: TimeInterval, onTap: (() -> Void)? = nil) {
        dismissWorkItem?.cancel()


        toastContainer?.removeFromSuperview()
        toastContainer = nil

        guard let hostView = Self.findContainerView() else { return }

        let toastView = ToastView(type: type, title: title, message: message)
        toastView.onClose = { [weak self] in self?.dismiss() }
        toastView.onTap = {
            onTap?()
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.zPosition = 10000
        container.addSubview(toastView)

        hostView.addSubview(container)

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
        toastView.alpha = 0
        toastView.transform = CGAffineTransform(translationX: 0, y: -20)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            toastView.alpha = 1
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

        UIView.animate(withDuration: 0.2) {
            self.toastContainer?.alpha = 0
        } completion: { _ in
            self.toastContainer?.removeFromSuperview()
            self.toastContainer = nil
        }
    }


    private static func findContainerView() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let win = scene.windows.first(where: { $0.isKeyWindow }),
               let rootVC = win.rootViewController {
                return rootVC.view
            }
        }
        for scene in scenes {
            if let win = scene.windows.first,
               let rootVC = win.rootViewController {
                return rootVC.view
            }
        }
        return nil
    }
}

private final class ToastView: UIView {

    var onClose: (() -> Void)?
    var onTap: (() -> Void)?

    private let type: ToastType
    private let titleText: String?
    private let messageText: String

    init(type: ToastType, title: String?, message: String) {
        self.type = type
        self.titleText = title
        self.messageText = message
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let config = Self.config(for: type)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = config.bgColor
        layer.cornerRadius = 12.sw
        layer.borderWidth = 1
        layer.borderColor = config.borderColor.cgColor
        clipsToBounds = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let leftBar = UIView()
        leftBar.backgroundColor = config.accentColor
        leftBar.translatesAutoresizingMaskIntoConstraints = false

        let iconBg = UIView()
        iconBg.backgroundColor = config.accentColor
        iconBg.layer.cornerRadius = 18.swh
        iconBg.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: config.iconName))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = titleText ?? config.defaultTitle
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .bold)
        titleLabel.textColor = type == .notification ? .white : .init(white: 0.15, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = messageText
        messageLabel.font = .systemFont(ofSize: 14.sf)
        messageLabel.textColor = type == .notification ? .init(white: 0.8, alpha: 1) : .init(white: 0.35, alpha: 1)
        messageLabel.numberOfLines = 3
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = .init(white: 0.4, alpha: 1)
        closeBtn.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftBar)
        addSubview(iconBg)
        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(closeBtn)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        textStack.axis = .vertical
        textStack.spacing = 4.sh
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        NSLayoutConstraint.activate([
            leftBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftBar.topAnchor.constraint(equalTo: topAnchor),
            leftBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftBar.widthAnchor.constraint(equalToConstant: 4.sw),

            iconBg.leadingAnchor.constraint(equalTo: leftBar.trailingAnchor, constant: 12.sw),
            iconBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 36.swh),
            iconBg.heightAnchor.constraint(equalToConstant: 36.swh),
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18.swh),
            iconView.heightAnchor.constraint(equalToConstant: 18.swh),

            textStack.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12.sw),
            textStack.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -12.sw),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 14.sh),
            bottomAnchor.constraint(greaterThanOrEqualTo: textStack.bottomAnchor, constant: 14.sh),

            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12.sw),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 32.swh),
            closeBtn.heightAnchor.constraint(equalToConstant: 32.swh),
        ])
    }

    private static func config(for type: ToastType) -> (accentColor: UIColor, bgColor: UIColor, borderColor: UIColor, iconName: String, defaultTitle: String) {
        switch type {
        case .success:
            return (hex("#22c55e"), hex("#dcfce7"), hex("#bbf7d0"), "checkmark", "Success")
        case .error:
            return (hex("#ef4444"), hex("#fef2f2"), hex("#fecaca"), "xmark", "Error")
        case .info:
            return (hex("#3b82f6"), hex("#eff6ff"), hex("#bfdbfe"), "info.circle.fill", "Info")
        case .notification:
            return (hex("#7c3aed"), hex("#1e1b2e"), hex("#3b335a"), "bell.fill", "Notification")
        }
    }

    @objc private func handleTap() {
        onTap?()
        onClose?()
    }
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
