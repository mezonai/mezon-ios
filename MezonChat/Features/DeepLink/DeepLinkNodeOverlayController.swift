import AsyncDisplayKit
import UIKit

final class DeepLinkNodeOverlayController: UIViewController {
    private let contentNode: ASDisplayNode

    init(node: ASDisplayNode) {
        self.contentNode = node
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        view.addSubnode(contentNode)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentNode.frame = view.bounds
    }

    func dismissOverlay(completion: (() -> Void)? = nil) {
        dismiss(animated: true, completion: completion)
    }
}

final class ChannelDeepLinkLoadingView: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        titleLabel.text = L(L10n.DeepLink.openingChannel)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        detailLabel.text = L(L10n.DeepLink.checkingAccess)
        detailLabel.font = .systemFont(ofSize: 13)
        isAccessibilityElement = true
        accessibilityLabel = "\(titleLabel.text ?? "") \(detailLabel.text ?? "")"

        [spinner, titleLabel, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15)
        ])
        applyTheme()
        spinner.startAnimating()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange), name: ThemeManager.didChangeNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func applyTheme() {
        backgroundColor = .mezonSecondary
        layer.borderColor = UIColor.mezonBorder.cgColor
        spinner.color = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        titleLabel.textColor = .mezonTextStrong
        detailLabel.textColor = .mezonSecondaryLabel
    }

    @objc private func themeDidChange() {
        applyTheme()
    }
}

final class ChannelUnavailableSheetViewController: UIViewController {
    private let iconBackground = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let acknowledgeButton = UIButton(type: .system)

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        buildContent()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange), name: ThemeManager.didChangeNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureSheet() {
        guard #available(iOS 15.0, *), let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 24
        if #available(iOS 16.0, *) {
            let identifier = UISheetPresentationController.Detent.Identifier("mezon.channelUnavailable")
            sheet.detents = [.custom(identifier: identifier) { context in
                min(360, context.maximumDetentValue)
            }]
            sheet.selectedDetentIdentifier = identifier
        } else {
            sheet.detents = [.medium()]
        }
    }

    private func buildContent() {
        [iconBackground, iconView, titleLabel, messageLabel, closeButton, acknowledgeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        iconBackground.layer.cornerRadius = 32
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false

        titleLabel.text = L(L10n.DeepLink.channelUnavailableTitle)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        messageLabel.text = L(L10n.DeepLink.channelUnavailableMessage)
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = L(L10n.Common.close)
        closeButton.addTarget(self, action: #selector(dismissSheet), for: .touchUpInside)

        acknowledgeButton.setTitle(L(L10n.DeepLink.gotIt), for: .normal)
        acknowledgeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        acknowledgeButton.layer.cornerRadius = 12
        acknowledgeButton.addTarget(self, action: #selector(dismissSheet), for: .touchUpInside)

        view.addSubview(iconBackground)
        iconBackground.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        view.addSubview(closeButton)
        view.addSubview(acknowledgeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            iconBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 42),
            iconBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 64),
            iconBackground.heightAnchor.constraint(equalToConstant: 64),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            titleLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            acknowledgeButton.topAnchor.constraint(greaterThanOrEqualTo: messageLabel.bottomAnchor, constant: 20),
            acknowledgeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            acknowledgeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            acknowledgeButton.heightAnchor.constraint(equalToConstant: 48),
            acknowledgeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func applyTheme() {
        view.backgroundColor = .mezonPrimary
        iconBackground.backgroundColor = .mezonSecondary
        iconView.tintColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        titleLabel.textColor = .mezonTextStrong
        messageLabel.textColor = .mezonSecondaryLabel
        closeButton.tintColor = .mezonTextStrong
        acknowledgeButton.backgroundColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        acknowledgeButton.setTitleColor(.white, for: .normal)
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
}
