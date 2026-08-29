import AsyncDisplayKit
import CoreImage
import Photos
import UIKit

private final class ClanInviteSearchWrapNode: ASDisplayNode {
    let textField = UITextField()
    let clearButton = UIButton(type: .system)
    private let iconView = UIImageView(image: UIImage.mezonSystemImage("magnifyingglass"))

    override init() {
        super.init()
        backgroundColor = UIColor.theme.secondary
        cornerRadius = 8.swh
        clipsToBounds = true
    }

    override func didLoad() {
        super.didLoad()
        iconView.tintColor = UIColor.theme.textDisabled
        view.addSubview(iconView)

        textField.placeholder = L(L10n.ClanInviteSheet.searchPlaceholder)
        textField.borderStyle = .none
        textField.font = .systemFont(ofSize: 15.sf, weight: .regular)
        textField.clearButtonMode = .never
        view.addSubview(textField)

        clearButton.setImage(
            UIImage.mezonSystemImage("xmark.circle.fill")?.mezonWithConfiguration(
                MezonSymbolConfiguration(pointSize: 16.sf, weight: .regular)
            ),
            for: .normal
        )
        clearButton.isHidden = true
        view.addSubview(clearButton)
    }

    override func layout() {
        super.layout()
        let b = bounds
        let iconSize: CGFloat = 18.swh
        let clearSize: CGFloat = 24.swh

        iconView.frame = CGRect(
            x: 8.sw,
            y: (b.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        clearButton.frame = CGRect(
            x: b.width - 8.sw - clearSize,
            y: (b.height - clearSize) / 2,
            width: clearSize,
            height: clearSize
        )
        textField.frame = CGRect(
            x: iconView.frame.maxX + 8.sw,
            y: 0,
            width: clearButton.frame.minX - 4.sw - iconView.frame.maxX - 8.sw,
            height: b.height
        )
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        iconView.tintColor = UIColor.theme.textDisabled
        textField.textColor = UIColor.theme.textStrong
        textField.tintColor = UIColor.theme.textDisabled
        clearButton.tintColor = UIColor.theme.textStrong
        textField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanInviteSheet.searchPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
    }
}

private final class ClanInviteActionButtonNode: ASDisplayNode {
    private let iconWrapNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let labelNode = ASTextNode()
    var onTap: (() -> Void)?

    init(iconAsset: String, fallbackSystemIcon: String, title: String) {
        super.init()
        automaticallyManagesSubnodes = false

        iconWrapNode.isLayerBacked = true
        iconNode.isLayerBacked = true
        labelNode.isLayerBacked = true

        iconWrapNode.backgroundColor = UIColor.theme.secondary
        iconWrapNode.cornerRadius = 20.swh
        iconWrapNode.clipsToBounds = true

        if !iconAsset.isEmpty, let assetImage = UIImage(named: iconAsset) {
            iconNode.image = assetImage.withRenderingMode(.alwaysOriginal)
            iconNode.tintColor = .clear
        } else {
            let symbol = UIImage.mezonSystemImage(fallbackSystemIcon)?.withRenderingMode(.alwaysTemplate)
            iconNode.image = symbol
            iconNode.tintColor = UIColor.theme.textStrong
        }
        iconNode.contentMode = .scaleAspectFit

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        labelNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf * 0.75, weight: .regular),
                .foregroundColor: UIColor.theme.text,
                .paragraphStyle: para,
            ]
        )
        
        addSubnode(iconWrapNode)
        addSubnode(iconNode)
        addSubnode(labelNode)
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @objc private func handleTap() { onTap?() }

    func setEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        alpha = enabled ? 1 : 0.45
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let labelSz = labelNode.calculateSizeThatFits(CGSize(width: 200, height: 40))
        let maxW = max(40.swh, labelSz.width)
        return CGSize(width: maxW, height: 62.sh) 
    }

    override func layout() {
        super.layout()
        let b = bounds
        
        let iconSz: CGFloat = 40.swh
        let iconFrame = CGRect(x: (b.width - iconSz) / 2, y: 0, width: iconSz, height: iconSz)
        iconWrapNode.frame = iconFrame
        
        let innerIconSz: CGFloat = 24.swh
        iconNode.frame = CGRect(
            x: iconFrame.minX + (iconSz - innerIconSz) / 2,
            y: iconFrame.minY + (iconSz - innerIconSz) / 2,
            width: innerIconSz,
            height: innerIconSz
        )
        
        let labelSz = labelNode.calculateSizeThatFits(CGSize(width: b.width, height: 20))
        labelNode.frame = CGRect(
            x: (b.width - labelSz.width) / 2,
            y: iconFrame.maxY + 6.sh,
            width: labelSz.width,
            height: labelSz.height
        )
    }
}

private final class ClanInviteQRCodeViewController: UIViewController {
    private enum PhotoLibrarySaveAuthorizationResult {
        case authorized
        case denied
        case restricted
    }

    @available(iOS 16.0, *)
    private static let contentDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "mezon.clanInvite.qr.content"
    )

    private let inviteLink: String
    private let inviteURL: URL
    private let clanName: String
    private let clanLogoURL: String

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cardView = UIView()
    private let qrImageView = UIImageView()
    private let avatarContainerView = UIView()
    private let avatarImageView = UIImageView()
    private let avatarFallbackLabel = UILabel()
    private let shareButton = UIButton(type: .system)

    init(inviteLink: String, inviteURL: URL, clanName: String, clanLogoURL: String) {
        self.inviteLink = inviteLink
        self.inviteURL = inviteURL
        self.clanName = clanName
        self.clanLogoURL = clanLogoURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        buildViewHierarchy()
        configureContent()
        loadClanLogo()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        scrollView.isScrollEnabled = scrollView.contentSize.height > scrollView.bounds.height + 1
    }

    private func configureSheet() {
        view.backgroundColor = UIColor.theme.primary
        if #available(iOS 13.0, *) {
            isModalInPresentation = false
        }
        if #available(iOS 15.0, *), let sheet = sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24.swh
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false

            if #available(iOS 16.0, *) {
                let identifier = Self.contentDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(
                    identifier: identifier
                ) { context in
                    let proportionalHeight = context.maximumDetentValue * 0.8
                    return min(context.maximumDetentValue, max(520.sh, proportionalHeight))
                }
                sheet.detents = [contentDetent]
                sheet.selectedDetentIdentifier = identifier
            } else {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
        }
    }

    private func buildViewHierarchy() {
        [scrollView, contentView, cardView, qrImageView, avatarContainerView, avatarImageView,
         avatarFallbackLabel, shareButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isScrollEnabled = false

        let brandIcon = UIImageView(image: UIImage(named: "Setting/LogoMezon")?.withRenderingMode(.alwaysOriginal))
        brandIcon.contentMode = .scaleAspectFit
        brandIcon.translatesAutoresizingMaskIntoConstraints = false

        let brandLabel = UILabel()
        brandLabel.text = "Mezon"
        brandLabel.font = .systemFont(ofSize: 28.sf, weight: .bold)
        brandLabel.textColor = UIColor.theme.textStrong

        let brandStack = UIStackView(arrangedSubviews: [brandIcon, brandLabel])
        brandStack.axis = .horizontal
        brandStack.alignment = .center
        brandStack.spacing = 10.sw
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        cardView.backgroundColor = UIColor.theme.secondary
        cardView.layer.cornerRadius = 16.swh
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)
        cardView.addSubview(brandStack)

        let qrBackgroundView = UIView()
        qrBackgroundView.backgroundColor = .white
        qrBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(qrBackgroundView)

        qrImageView.contentMode = .scaleAspectFit
        qrImageView.layer.magnificationFilter = .nearest
        qrImageView.layer.minificationFilter = .nearest
        qrBackgroundView.addSubview(qrImageView)

        avatarContainerView.backgroundColor = UIColor.theme.secondary
        avatarContainerView.layer.cornerRadius = 8.swh
        avatarContainerView.clipsToBounds = true
        qrBackgroundView.addSubview(avatarContainerView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 6.swh
        avatarContainerView.addSubview(avatarImageView)

        avatarFallbackLabel.font = .systemFont(ofSize: 20.sf, weight: .bold)
        avatarFallbackLabel.textAlignment = .center
        avatarFallbackLabel.textColor = .white
        avatarFallbackLabel.backgroundColor = UIColor.theme.textLink
        avatarFallbackLabel.layer.cornerRadius = 6.swh
        avatarFallbackLabel.clipsToBounds = true
        avatarContainerView.addSubview(avatarFallbackLabel)

        let divider = UIView()
        divider.backgroundColor = UIColor.theme.border
        divider.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(divider)

        let poweredByLabel = UILabel()
        poweredByLabel.text = L(L10n.QRScanner.poweredBy)
        poweredByLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
        poweredByLabel.textColor = UIColor.theme.textDisabled
        poweredByLabel.textAlignment = .center
        poweredByLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(poweredByLabel)

        let saveButton = UIButton(type: .system)
        configureActionButton(
            saveButton,
            systemImage: "square.and.arrow.down",
            accessibilityLabel: L(L10n.ClanInviteSheet.saveQR),
            selector: #selector(saveQR)
        )
        configureActionButton(
            shareButton,
            systemImage: "square.and.arrow.up",
            accessibilityLabel: L(L10n.ClanInviteSheet.shareQR),
            selector: #selector(shareQR)
        )

        let actionStack = UIStackView(arrangedSubviews: [saveButton, shareButton])
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.spacing = 16.sw
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionStack)

        let hintLabel = UILabel()
        hintLabel.text = L(L10n.ClanInviteSheet.qrHint)
        hintLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        hintLabel.textColor = UIColor.theme.textDisabled
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16.sh),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),

            brandIcon.widthAnchor.constraint(equalToConstant: 34.swh),
            brandIcon.heightAnchor.constraint(equalTo: brandIcon.widthAnchor),
            brandStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24.sh),
            brandStack.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            qrBackgroundView.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 20.sh),
            qrBackgroundView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24.sw),
            qrBackgroundView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24.sw),
            qrBackgroundView.heightAnchor.constraint(equalTo: qrBackgroundView.widthAnchor),

            qrImageView.topAnchor.constraint(equalTo: qrBackgroundView.topAnchor, constant: 12.swh),
            qrImageView.leadingAnchor.constraint(equalTo: qrBackgroundView.leadingAnchor, constant: 12.swh),
            qrImageView.trailingAnchor.constraint(equalTo: qrBackgroundView.trailingAnchor, constant: -12.swh),
            qrImageView.bottomAnchor.constraint(equalTo: qrBackgroundView.bottomAnchor, constant: -12.swh),

            avatarContainerView.centerXAnchor.constraint(equalTo: qrBackgroundView.centerXAnchor),
            avatarContainerView.centerYAnchor.constraint(equalTo: qrBackgroundView.centerYAnchor),
            avatarContainerView.widthAnchor.constraint(equalToConstant: 46.swh),
            avatarContainerView.heightAnchor.constraint(equalTo: avatarContainerView.widthAnchor),

            avatarImageView.topAnchor.constraint(equalTo: avatarContainerView.topAnchor, constant: 3.swh),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainerView.leadingAnchor, constant: 3.swh),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarContainerView.trailingAnchor, constant: -3.swh),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainerView.bottomAnchor, constant: -3.swh),
            avatarFallbackLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            avatarFallbackLabel.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            avatarFallbackLabel.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor),
            avatarFallbackLabel.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor),

            divider.topAnchor.constraint(equalTo: qrBackgroundView.bottomAnchor, constant: 24.sh),
            divider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24.sw),
            divider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24.sw),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            poweredByLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 20.sh),
            poweredByLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16.sw),
            poweredByLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16.sw),
            poweredByLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -22.sh),

            actionStack.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 20.sh),
            actionStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            actionStack.widthAnchor.constraint(equalToConstant: 112.sw),
            actionStack.heightAnchor.constraint(equalToConstant: 48.swh),
            saveButton.widthAnchor.constraint(equalToConstant: 48.swh),
            saveButton.heightAnchor.constraint(equalTo: saveButton.widthAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 48.swh),
            shareButton.heightAnchor.constraint(equalTo: shareButton.widthAnchor),

            hintLabel.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 12.sh),
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24.sw),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24.sw),
            hintLabel.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -20.sh),
        ])
    }

    private func configureContent() {
        guard let image = Self.makeQRCode(from: inviteLink) else {
            Toast.error(L(L10n.ClanInviteSheet.cannotCreateInvite))
            dismiss(animated: true)
            return
        }
        qrImageView.image = image
        avatarFallbackLabel.text = clanName.trimmingCharacters(in: .whitespacesAndNewlines).first
            .map { String($0).uppercased() } ?? "M"
    }

    private func loadClanLogo() {
        let source = ImgproxyURL.absoluteResourceURL(from: clanLogoURL)
        guard !source.isEmpty else { return }

        let proxied = ImgproxyURL.create(from: source, width: 160, height: 160)
        let candidates = [proxied, source].reduce(into: [String]()) { result, candidate in
            guard !candidate.isEmpty,
                  let url = URL(string: candidate),
                  url.scheme != nil,
                  !result.contains(candidate) else { return }
            result.append(candidate)
        }
        loadClanLogo(candidates: candidates, index: 0)
    }

    private func loadClanLogo(candidates: [String], index: Int) {
        guard candidates.indices.contains(index) else { return }
        let candidate = candidates[index]

        if let cached = ImageCache.shared.cachedImage(forURL: candidate) {
            applyClanLogo(cached)
            return
        }

        ImageCache.shared.loadImage(urlString: candidate) { [weak self] image in
            guard let self else { return }
            if let image {
                self.applyClanLogo(image)
            } else {
                self.loadClanLogo(candidates: candidates, index: index + 1)
            }
        }
    }

    private func applyClanLogo(_ image: UIImage) {
        avatarImageView.image = image
        avatarFallbackLabel.isHidden = true
    }

    private static func makeQRCode(from value: String) -> UIImage? {
        guard let data = value.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let targetSize: CGFloat = 1024
        let scale = floor(targetSize / output.extent.width)
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func configureActionButton(
        _ button: UIButton,
        systemImage: String,
        accessibilityLabel: String,
        selector: Selector
    ) {
        let configuration = MezonSymbolConfiguration(pointSize: 18.sf, weight: .medium)
        button.setImage(UIImage.mezonSystemImage(systemImage, withConfiguration: configuration), for: .normal)
        button.tintColor = UIColor.theme.textStrong
        button.backgroundColor = UIColor.theme.secondary
        button.layer.cornerRadius = 12.swh
        button.layer.borderWidth = 1 / UIScreen.main.scale
        button.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.7).cgColor
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: selector, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func renderedCardImage() -> UIImage? {
        cardView.layoutIfNeeded()
        guard cardView.bounds.width > 0, cardView.bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: cardView.bounds)
        return renderer.image { _ in
            cardView.drawHierarchy(in: cardView.bounds, afterScreenUpdates: true)
        }
    }

    @objc private func shareQR() {
        guard let image = renderedCardImage() else { return }
        let controller = UIActivityViewController(
            activityItems: [image, inviteURL],
            applicationActivities: nil
        )
        if let popover = controller.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(controller, animated: true)
    }

    @objc private func saveQR() {
        guard let image = renderedCardImage() else { return }
        requestPhotoLibrarySaveAuthorization { [weak self] result in
            switch result {
            case .authorized:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            Toast.success(L(L10n.ClanInviteSheet.qrSaved))
                        } else {
                            Toast.error(error?.localizedDescription ?? L(L10n.ClanInviteSheet.qrSaveFailed))
                        }
                    }
                })
            case .denied:
                DispatchQueue.main.async {
                    self?.presentPhotoPermissionSettingsAlert()
                }
            case .restricted:
                DispatchQueue.main.async {
                    Toast.error(L(L10n.Gallery.photoPermissionDenied))
                }
            }
        }
    }

    private func requestPhotoLibrarySaveAuthorization(
        completion: @escaping (PhotoLibrarySaveAuthorizationResult) -> Void
    ) {
        if #available(iOS 14.0, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    switch status {
                    case .authorized, .limited:
                        completion(.authorized)
                    case .restricted:
                        completion(.restricted)
                    case .denied, .notDetermined:
                        completion(.denied)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .restricted:
                completion(.restricted)
            case .denied:
                completion(.denied)
            @unknown default:
                completion(.denied)
            }
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    switch status {
                    case .authorized:
                        completion(.authorized)
                    case .restricted:
                        completion(.restricted)
                    case .denied, .notDetermined:
                        completion(.denied)
                    case .limited:
                        completion(.authorized)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .restricted:
                completion(.restricted)
            case .denied:
                completion(.denied)
            case .limited:
                completion(.authorized)
            @unknown default:
                completion(.denied)
            }
        }
    }

    private func presentPhotoPermissionSettingsAlert() {
        let alert = UIAlertController(
            title: L(L10n.Gallery.photoPermissionTitle),
            message: L(L10n.Gallery.photoPermissionMessage),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.Common.settings), style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
}

private final class ClanInviteEmptyStateNode: ASDisplayNode {
    private let imageNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let descriptionNode = ASTextNode()
    let actionButtonNode = ASButtonNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        isHidden = true

        imageNode.isLayerBacked = true
        titleNode.isLayerBacked = true
        descriptionNode.isLayerBacked = true

        imageNode.image = UIImage(named: "Invite/EmptyFriendIcon", in: .main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
        imageNode.contentMode = .scaleAspectFit
        imageNode.style.preferredSize = CGSize(width: 96.swh, height: 96.swh)
        updateText()
    }

    private func updateText() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.emptyTitle),
            attributes: [
                .font: UIFont.systemFont(ofSize: 30.sf * 0.6, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
                .paragraphStyle: center,
            ]
        )
        titleNode.maximumNumberOfLines = 2

        descriptionNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.emptyDescription),
            attributes: [
                .font: UIFont.systemFont(ofSize: 24.sf * 0.6, weight: .regular),
                .foregroundColor: UIColor.theme.textDisabled,
                .paragraphStyle: center,
            ]
        )
        descriptionNode.maximumNumberOfLines = 0

        actionButtonNode.setTitle(
            L(L10n.ClanInviteSheet.emptyAction),
            with: .systemFont(ofSize: 14.sf, weight: .semibold),
            with: UIColor.theme.textLink,
            for: .normal
        )
    }

    func applyTheme() { updateText() }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let topStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 10.sh,
            justifyContent: .center,
            alignItems: .center,
            children: [imageNode, titleNode, descriptionNode]
        )
        let outerStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 14.sh,
            justifyContent: .center,
            alignItems: .center,
            children: [topStack, actionButtonNode]
        )
        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 24.sw, bottom: 0, right: 24.sw),
            child: outerStack
        )
        return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: inset)
    }
}

private final class ClanInviteFriendCellNode: ASCellNode {
    var onInvite: (() -> Void)?

    private let avatarBgNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let textAvatarNode: TextAvatarNode
    private let groupIconNode = ASImageNode()
    private let nameNode = ASTextNode()
    private let inviteButtonNode = ASButtonNode()
    private let spinnerWrapNode: ASDisplayNode

    private enum AvatarMode { case image, group, initial }
    private let avatarMode: AvatarMode
    private let needsSpinner: Bool

    init(name: String, avatarURL: String?, isGroupDM: Bool, isSent: Bool, isLoading: Bool) {
        self.needsSpinner = isLoading

        spinnerWrapNode = ASDisplayNode { () -> UIView in
            let sp = UIActivityIndicatorView.mezonMedium()
            sp.hidesWhenStopped = true
            if isLoading {
                sp.startAnimating()
            }
            return sp
        }

        if let avatarURL, !avatarURL.isEmpty {
            avatarMode = .image
        } else if isGroupDM {
            avatarMode = .group
        } else {
            avatarMode = .initial
        }

        self.textAvatarNode = TextAvatarNode(username: name, size: 40.swh)

        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        avatarBgNode.isLayerBacked = true
        avatarNode.isLayerBacked = true
        groupIconNode.isLayerBacked = true
        nameNode.isLayerBacked = true

        let avatarSize: CGFloat = 40.swh
        avatarBgNode.cornerRadius = avatarSize / 2
        avatarBgNode.clipsToBounds = true

        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill

        groupIconNode.image = UIImage.mezonSystemImage("person.2.fill")?.withRenderingMode(.alwaysTemplate)
        groupIconNode.tintColor = .white
        groupIconNode.contentMode = .scaleAspectFit

        switch avatarMode {
        case .image:
            let px = Int(avatarSize * UIScreen.main.scale)
            let proxied = ImgproxyURL.create(from: avatarURL!, width: px, height: px)
            avatarNode.url = URL(string: proxied)
            avatarBgNode.backgroundColor = UIColor.theme.border
        case .group:
            avatarBgNode.backgroundColor = UIColor(red: 0.96, green: 0.55, blue: 0.16, alpha: 1)
        case .initial:
            break
        }

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )

        let title = isSent ? L(L10n.ClanInviteSheet.invited) : L(L10n.ClanInviteSheet.invite)
        inviteButtonNode.backgroundColor = UIColor.theme.tertiary
        inviteButtonNode.cornerRadius = 16.swh
        inviteButtonNode.clipsToBounds = true
        inviteButtonNode.borderWidth = 1 / UIScreen.main.scale
        inviteButtonNode.borderColor = UIColor.theme.border.withAlphaComponent(0.8).cgColor
        inviteButtonNode.contentEdgeInsets = UIEdgeInsets(top: 6.sh, left: 12.sw, bottom: 6.sh, right: 12.sw)
        inviteButtonNode.isEnabled = !isSent && !isLoading

        if isLoading {
            inviteButtonNode.setTitle("", with: .systemFont(ofSize: 14.sf, weight: .medium), with: .clear, for: .normal)
        } else {
            inviteButtonNode.setTitle(
                title,
                with: .systemFont(ofSize: 14.sf, weight: .medium),
                with: UIColor.theme.textStrong,
                for: .normal
            )
        }

        inviteButtonNode.addTarget(self, action: #selector(inviteTapped), forControlEvents: .touchUpInside)
        alpha = isSent ? 0.6 : 1.0
    }

    func updateState(isSent: Bool, isLoading: Bool) {
        let title = isSent ? L(L10n.ClanInviteSheet.invited) : L(L10n.ClanInviteSheet.invite)
        inviteButtonNode.isEnabled = !isSent && !isLoading
        alpha = isSent ? 0.6 : 1.0

        if isLoading {
            inviteButtonNode.setTitle("", with: .systemFont(ofSize: 14.sf, weight: .medium), with: .clear, for: .normal)
            if spinnerWrapNode.isNodeLoaded {
                ASPerformBlockOnMainThread {
                    if let spinner = self.spinnerWrapNode.view.subviews.first as? UIActivityIndicatorView {
                        spinner.startAnimating()
                    }
                }
            }
        } else {
            inviteButtonNode.setTitle(
                title,
                with: .systemFont(ofSize: 14.sf, weight: .medium),
                with: UIColor.theme.textStrong,
                for: .normal
            )
            if spinnerWrapNode.isNodeLoaded {
                ASPerformBlockOnMainThread {
                    if let spinner = self.spinnerWrapNode.view.subviews.first as? UIActivityIndicatorView {
                        spinner.stopAnimating()
                    }
                }
            }
        }
    }

    @objc private func inviteTapped() { onInvite?() }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let avatarSize: CGFloat = 40.swh

        avatarBgNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)

        let avatarComposite: ASLayoutElement
        switch avatarMode {
        case .image:
            avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
            avatarComposite = ASOverlayLayoutSpec(child: avatarBgNode, overlay: avatarNode)
        case .group:
            groupIconNode.style.preferredSize = CGSize(width: 20.swh, height: 20.swh)
            let overlay = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: groupIconNode)
            avatarComposite = ASOverlayLayoutSpec(child: avatarBgNode, overlay: overlay)
        case .initial:
            avatarComposite = textAvatarNode
        }
        avatarComposite.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)

        nameNode.style.flexShrink = 1
        nameNode.style.flexGrow = 0
        let nameOffset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 10.sh, left: 0, bottom: 0, right: 0),
            child: nameNode
        )
        nameOffset.style.flexShrink = 1

        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        inviteButtonNode.style.minWidth = ASDimensionMake(60.sw)
        inviteButtonNode.style.maxWidth = ASDimensionMake(90.sw)
        inviteButtonNode.style.height = ASDimensionMake(32.sh)

        let spinnerCenter = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: spinnerWrapNode)
        let buttonWithSpinner = ASOverlayLayoutSpec(child: inviteButtonNode, overlay: spinnerCenter)

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarComposite, nameOffset, spacer, buttonWithSpinner]
        )

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20.sw, bottom: 0, right: 20.sw),
            child: row
        )
        inset.style.height = ASDimensionMake(60.sh)
        return inset
    }
}

private final class ClanInviteSheetContainerNode: ASDisplayNode {
    let titleNode = ASTextNode()
    let shareButton: ClanInviteActionButtonNode
    let copyButton: ClanInviteActionButtonNode
    let qrButton: ClanInviteActionButtonNode
    let dividerNode = ASDisplayNode()
    let searchWrapNode = ClanInviteSearchWrapNode()
    let listContainerNode = ASDisplayNode()
    let tableNode = ASTableNode(style: .plain)
    let emptyStateNode = ClanInviteEmptyStateNode()
    let loadingSpinner = UIActivityIndicatorView.mezonMedium()
    let loadingLabel = UILabel()

    override init() {
        shareButton = ClanInviteActionButtonNode(
            iconAsset: "Invite/ShareIcon",
            fallbackSystemIcon: "square.and.arrow.up",
            title: L(L10n.ClanInviteSheet.share)
        )
        copyButton = ClanInviteActionButtonNode(
            iconAsset: "ClanSetting/Invite",
            fallbackSystemIcon: "link",
            title: L(L10n.ClanInviteSheet.copy)
        )
        qrButton = ClanInviteActionButtonNode(
            iconAsset: "Channel/QR",
            fallbackSystemIcon: "qrcode",
            title: L(L10n.ClanInviteSheet.qrCode)
        )

        super.init()
        automaticallyManagesSubnodes = false

        titleNode.isLayerBacked = true
        dividerNode.isLayerBacked = true

        backgroundColor = UIColor.theme.primary
        cornerRadius = 8.swh
        clipsToBounds = true

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
                .paragraphStyle: center,
            ]
        )

        listContainerNode.backgroundColor = UIColor.theme.secondary
        listContainerNode.cornerRadius = 10.swh
        listContainerNode.clipsToBounds = true

        tableNode.cornerRadius = 10.swh

        loadingSpinner.startAnimating()
        loadingLabel.text = L(L10n.ClanInviteSheet.loadingInviteLink)
        loadingLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)

        addSubnode(titleNode)
        addSubnode(shareButton)
        addSubnode(copyButton)
        addSubnode(qrButton)
        addSubnode(dividerNode)
        addSubnode(searchWrapNode)
        addSubnode(listContainerNode)
        listContainerNode.addSubnode(tableNode)
        listContainerNode.addSubnode(emptyStateNode)
    }

    override func didLoad() {
        super.didLoad()
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        tableNode.view.separatorStyle = .singleLine
        tableNode.view.separatorColor = UIColor.theme.textDisabled.withAlphaComponent(0.45)
        tableNode.view.separatorInset = .zero
        tableNode.view.layoutMargins = .zero
        tableNode.backgroundColor = .clear
        tableNode.view.showsVerticalScrollIndicator = false

        tableNode.leadingScreensForBatching = 2.0
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.primary

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
                .paragraphStyle: center,
            ]
        )

        dividerNode.backgroundColor = UIColor.theme.border.withAlphaComponent(0.6)
        searchWrapNode.applyTheme()
        loadingSpinner.color = UIColor.theme.textDisabled
        loadingLabel.textColor = UIColor.theme.textDisabled
        listContainerNode.backgroundColor = UIColor.theme.secondary
        emptyStateNode.applyTheme()
        tableNode.view.separatorColor = UIColor.theme.textDisabled.withAlphaComponent(0.45)
        tableNode.reloadData()
    }

    override func layout() {
        super.layout()
        let b = bounds
        let w = b.width
        var y: CGFloat = 0

        titleNode.frame = CGRect(x: 16.sw, y: 20.sh, width: w - 32.sw, height: 24.sh)
        y = 60.sh

        let aLead: CGFloat = 16.sw
        let aTrail: CGFloat = 16.sw
        let aTop = y + 16.sh

        let shareSz = shareButton.calculateSizeThatFits(CGSize(width: w, height: 62.sh))
        let copySz = copyButton.calculateSizeThatFits(CGSize(width: w, height: 62.sh))
        let qrSz = qrButton.calculateSizeThatFits(CGSize(width: w, height: 62.sh))

        let shareW = shareSz.width
        let copyW = copySz.width
        let qrW = qrSz.width

        shareButton.frame = CGRect(x: aLead, y: aTop, width: shareW, height: 62.sh)
        copyButton.frame = CGRect(x: (w - copyW) / 2, y: aTop, width: copyW, height: 62.sh)
        qrButton.frame = CGRect(x: w - aTrail - qrW, y: aTop, width: qrW, height: 62.sh)
        dividerNode.frame = CGRect(
            x: 0,
            y: y + 94.sh - 1 / UIScreen.main.scale,
            width: w,
            height: 1 / UIScreen.main.scale
        )
        y += 94.sh

        let lx: CGFloat = 16.sw
        let lw = w - 32.sw
        searchWrapNode.frame = CGRect(x: lx, y: y + 16.sh, width: lw, height: 40.sh)
        y += 62.sh

        let lh = max(0, b.height - y - 10.sh)
        listContainerNode.frame = CGRect(x: lx, y: y, width: lw, height: lh)
        tableNode.frame = listContainerNode.bounds
        emptyStateNode.frame = listContainerNode.bounds
    }

    func updateEmptyState(isEmpty: Bool) {
        emptyStateNode.isHidden = !isEmpty
        tableNode.isHidden = isEmpty
    }
}

final class ClanInviteSheetViewController: ViewController {
    private static let inviteIdRegex = try? NSRegularExpression(pattern: "/invite/(\\d+)", options: [])

    private enum InviteTarget: Hashable {
        case friend(userId: Int64)
        case direct(channelId: Int64, type: Int32, isPublic: Bool)
    }

    private struct FriendItem: Hashable {
        let id: Int64
        let name: String
        let avatarURL: String?
        let isGroupDM: Bool
        let target: InviteTarget
    }

    private let context: AccountContext
    private let clanId: Int64
    private let nativeModalPresenter = UIViewController()

    private var inviteLink: String?
    private var clanName = ""
    private var clanLogoURL = ""
    private var allFriends: [FriendItem] = []
    private var filteredFriends: [FriendItem] = []
    private var sentIds = Set<Int64>()
    private var sendingIds = Set<Int64>()
    private var dmChannelsByUserId: [Int64: Mezon_Api_ChannelDescription] = [:]

    private var foldedNameCache: [Int64: String] = [:]

    private var containerNode: ClanInviteSheetContainerNode { displayNode as! ClanInviteSheetContainerNode }

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func loadDisplayNode() {
        let node = ClanInviteSheetContainerNode()
        displayNode = node

        node.shareButton.onTap = { [weak self] in self?.shareInvite() }
        node.copyButton.onTap = { [weak self] in self?.copyInvite() }
        node.qrButton.onTap = { [weak self] in self?.showQR() }
        node.shareButton.setEnabled(false)
        node.copyButton.setEnabled(false)
        node.qrButton.setEnabled(false)
        node.emptyStateNode.actionButtonNode.addTarget(
            self,
            action: #selector(emptyActionTapped),
            forControlEvents: .touchUpInside
        )

        node.tableNode.dataSource = self
        node.tableNode.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        attachNativeModalPresenter()
        containerNode.searchWrapNode.textField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        containerNode.searchWrapNode.clearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        applyTheme()
        if #available(iOS 13.0, *) {
            loadData()
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if let modal = nativeModalPresenter.presentedViewController ?? presentedViewController {
            modal.dismiss(animated: flag, completion: completion)
        } else {
            super.dismiss(animated: flag, completion: completion)
        }
    }

    private func attachNativeModalPresenter() {
        nativeModalPresenter.definesPresentationContext = true
        nativeModalPresenter.view.backgroundColor = .clear
        nativeModalPresenter.view.isUserInteractionEnabled = false
        nativeModalPresenter.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(nativeModalPresenter)
        view.insertSubview(nativeModalPresenter.view, at: 0)
        NSLayoutConstraint.activate([
            nativeModalPresenter.view.topAnchor.constraint(equalTo: view.topAnchor),
            nativeModalPresenter.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nativeModalPresenter.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nativeModalPresenter.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        nativeModalPresenter.didMove(toParent: self)
    }

    private func presentNativeModal(_ controller: UIViewController) {
        guard nativeModalPresenter.presentedViewController == nil else { return }
        nativeModalPresenter.present(controller, animated: true)
    }

    private func applyTheme() {
        containerNode.applyTheme()
    }

    @available(iOS 13.0, *)
    private func loadData() {
        Task { @MainActor in
            guard let token = await context.getToken() else {
                self.showSimpleAlert(message: L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            inviteLink = await resolveInviteLink(token: token)
            updateInviteActionState()
            if inviteLink == nil {
                showSimpleAlert(message: L(L10n.ClanInviteSheet.cannotCreateInvite))
            }

            do {
                async let friendsTask = context.account.network.listFriends(
                    token: token,
                    limit: 100,
                    state: Int32(Mezon_Api_Friend.State.friend.rawValue)
                )
                async let directsTask = context.account.network.listDirectMessageChannels(token: token)
                let friends = try await friendsTask
                let directs = try await directsTask

                let memberIds = Set(context.account.postbox.read { tx in
                    tx.getClanMembers(clanId: self.clanId).map { $0.userId }
                })
                cacheDirectChannels(directs)

                let currentUserId = Int64(context.currentUser?.id ?? "") ?? 0
                var merged = [String: FriendItem]()

                for friend in friends.friends {
                    guard friend.state == Mezon_Api_Friend.State.friend.rawValue else { continue }
                    guard friend.hasUser else { continue }
                    let u = friend.user
                    let uid = u.id
                    guard uid != 0, uid != currentUserId, !memberIds.contains(uid) else { continue }
                    let name = !u.displayName.isEmpty ? u.displayName : (u.username.isEmpty ? "Unknown" : u.username)
                    let avatar = u.avatarURL.isEmpty ? nil : u.avatarURL
                    merged["user_\(uid)"] = FriendItem(
                        id: uid,
                        name: name,
                        avatarURL: avatar,
                        isGroupDM: false,
                        target: .friend(userId: uid)
                    )
                }

                for dm in directs {
                    let isDM = dm.type == MezonConstants.ChannelType.dm.rawValue
                    let isGroup = dm.type == MezonConstants.ChannelType.group.rawValue
                    guard isDM || isGroup else { continue }

                    if isDM {
                        guard let uid = dm.userIds.first else { continue }
                        guard uid != 0, uid != currentUserId, !memberIds.contains(uid) else { continue }
                        guard dm.channelID != 0 else { continue }
                        let name = !dm.channelLabel.isEmpty
                            ? dm.channelLabel
                            : (dm.displayNames.first(where: { !$0.isEmpty })
                                ?? dm.usernames.first(where: { !$0.isEmpty })
                                ?? "Unknown")
                        let avatar = dm.avatars.first(where: { !$0.isEmpty })
                        merged["user_\(uid)"] = FriendItem(
                            id: dm.channelID,
                            name: name,
                            avatarURL: avatar,
                            isGroupDM: false,
                            target: .direct(channelId: dm.channelID, type: dm.type, isPublic: dm.channelPrivate == 0)
                        )
                    } else if isGroup {
                        guard dm.channelID != 0 else { continue }
                        let name = !dm.channelLabel.isEmpty ? dm.channelLabel : "\(dm.creatorName)'s Group"
                        let hasCustomGroupAvatar = !dm.channelAvatar.isEmpty && !dm.channelAvatar.contains("avatar-group.png")
                        let avatar = hasCustomGroupAvatar ? dm.channelAvatar : nil
                        merged["group_\(dm.channelID)"] = FriendItem(
                            id: dm.channelID,
                            name: name,
                            avatarURL: avatar,
                            isGroupDM: true,
                            target: .direct(channelId: dm.channelID, type: dm.type, isPublic: dm.channelPrivate == 0)
                        )
                    }
                }

                self.allFriends = merged.values.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                self.rebuildFoldedNameCache()

                self.applyFilter()
                self.containerNode.loadingSpinner.stopAnimating()
            } catch {
                self.containerNode.loadingSpinner.stopAnimating()
                self.filteredFriends = []
                self.updateEmptyStateVisibility()
                await self.containerNode.tableNode.reloadData()
            }
        }
    }

    private func rebuildFoldedNameCache() {
        foldedNameCache.removeAll(keepingCapacity: true)
        for item in allFriends {
            foldedNameCache[item.id] = item.name.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
        }
    }

    @available(iOS 13.0, *)
    private func resolveInviteLink(token: String) async -> String? {
        guard let inviteContext = await resolveInviteContext(token: token) else {
            return nil
        }
        clanName = inviteContext.clanName
        clanLogoURL = inviteContext.clanLogoURL

        do {
            let invite = try await context.account.network.linkInviteUser(
                clanId: clanId,
                channelId: inviteContext.channelId,
                expiryTime: 10,
                token: token
            )
            return "\(MezonConfig.chatWebAppBaseURL)/invite/\(invite.inviteLink)"
        } catch {
        }
        return nil
    }

    @available(iOS 13.0, *)
    private func resolveInviteContext(
        token: String
    ) async -> (channelId: Int64, clanName: String, clanLogoURL: String)? {
        let cachedClan = context.account.postbox.read { transaction -> (name: String, logo: String)? in
            guard let record = transaction.getClan(id: clanId) else { return nil }
            let cachedDesc = record.data.isEmpty
                ? nil
                : try? Mezon_Api_ClanDesc(serializedBytes: record.data)
            let name = cachedDesc.flatMap { $0.clanName.isEmpty ? nil : $0.clanName } ?? record.name
            let logo = cachedDesc.flatMap { $0.logo.isEmpty ? nil : $0.logo } ?? (record.icon ?? "")
            return (name, logo)
        }

        do {
            let clans = try await context.account.network.listClanDescs(token: token)
            if let clan = clans.first(where: { $0.clanID == clanId }) {
                guard clan.welcomeChannelID != 0 else { return nil }
                let name = clan.clanName.isEmpty ? (cachedClan?.name ?? "") : clan.clanName
                let logo = clan.logo.isEmpty ? (cachedClan?.logo ?? "") : clan.logo
                return (clan.welcomeChannelID, name, logo)
            }
        } catch {
        }
        return nil
    }

    private func applyFilter() {
        let keyword = (containerNode.searchWrapNode.textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if keyword.isEmpty {
            filteredFriends = allFriends
        } else {
            filteredFriends = allFriends.filter {
                (foldedNameCache[$0.id] ?? "").contains(keyword)
            }
        }
        updateEmptyStateVisibility()
        containerNode.tableNode.reloadData()
    }

    private func updateEmptyStateVisibility() {
        let isEmpty = filteredFriends.isEmpty
        containerNode.updateEmptyState(isEmpty: isEmpty)
        containerNode.loadingLabel.text = nil
    }

    @available(iOS 13.0, *)
    private func updateCellState(for item: FriendItem) {
        Task { @MainActor in
            guard let rowIndex = self.filteredFriends.firstIndex(where: { $0.id == item.id }) else { return }
            let indexPath = IndexPath(row: rowIndex, section: 0)
            if let cell = self.containerNode.tableNode.nodeForRow(at: indexPath) as? ClanInviteFriendCellNode {
                let isSent = self.sentIds.contains(item.id)
                let isLoading = self.sendingIds.contains(item.id)
                cell.updateState(isSent: isSent, isLoading: isLoading)
            }
        }
    }

    @available(iOS 13.0, *)
    private func inviteUser(_ item: FriendItem) {
        guard !sentIds.contains(item.id), !sendingIds.contains(item.id) else { return }
        sendingIds.insert(item.id)
        updateCellState(for: item)

        Task { @MainActor in
            defer {
                self.sendingIds.remove(item.id)
                self.updateCellState(for: item)
            }
            do {
                guard let token = await context.getToken() else { throw NSError(domain: "session", code: -1) }
                let resolvedInviteLink: String
                if let existing = inviteLink {
                    resolvedInviteLink = existing
                } else if let generated = await resolveInviteLink(token: token) {
                    inviteLink = generated
                    updateInviteActionState()
                    resolvedInviteLink = generated
                } else {
                    showSimpleAlert(message: L(L10n.ClanInviteSheet.cannotCreateInvite))
                    return
                }

                let dm: Mezon_Api_ChannelDescription
                let isPublic: Bool
                switch item.target {
                case .friend(let userId):
                    dm = try await resolveDirectChannel(for: userId, token: token)
                    isPublic = dm.channelPrivate == 0
                case .direct(let channelId, _, let channelIsPublic):
                    var directChannel = Mezon_Api_ChannelDescription()
                    directChannel.channelID = channelId
                    dm = directChannel
                    isPublic = channelIsPublic
                }

                let payload = try await buildInviteMessagePayload(url: resolvedInviteLink, token: token)
                let contentData = try JSONSerialization.data(withJSONObject: payload)
                let content = String(data: contentData, encoding: .utf8) ?? "{}"
                _ = try await context.account.network.sendChannelMessage(
                    clanId: 0,
                    channelId: dm.channelID,
                    mode: MezonConstants.ChannelStreamMode.dm.rawValue,
                    isPublic: isPublic,
                    content: content,
                    token: token
                )
                self.sentIds.insert(item.id)
            } catch {
                self.showSimpleAlert(message: String(format: L(L10n.ClanInviteSheet.cannotSendInvite), item.name))
            }
        }
    }

    @available(iOS 13.0, *)
    private func buildInviteMessagePayload(url: String, token: String) async throws -> [String: Any] {
        let linkLength = url.count
        var mk: [[String: Any]] = [
            ["s": 0, "e": linkLength, "type": "lk"]
        ]
        var payload: [String: Any] = ["t": url]

        if let inviteId = extractInviteId(from: url), !inviteId.isEmpty {
            do {
                let inviteInfo = try await context.account.network.getInviteInfo(code: inviteId, token: token)
                let memberCount = inviteInfo.member_count ?? 0
                let title = inviteInfo.clan_name ?? L(L10n.ClanInviteSheet.unknownClan)
                let description = L(L10n.ClanAction.memberCount, memberCount)
                let image = inviteInfo.clan_logo ?? ""

                mk.append([
                    "type": "lk_ogp",
                    "s": linkLength,
                    "e": linkLength + 1,
                    "index": 0,
                    "title": title,
                    "description": description,
                    "image": image
                ])
            } catch {
            }
        }

        payload["mk"] = mk
        return payload
    }

    private func extractInviteId(from url: String) -> String? {
        guard let regex = Self.inviteIdRegex else {
            return nil
        }
        let ns = url as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: url, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private func cacheDirectChannels(_ directs: [Mezon_Api_ChannelDescription]) {
        var map: [Int64: Mezon_Api_ChannelDescription] = [:]
        for channel in directs where
            channel.type == MezonConstants.ChannelType.dm.rawValue &&
            channel.userIds.count == 1 &&
            channel.userIds[0] != 0 {
            map[channel.userIds[0]] = channel
        }
        dmChannelsByUserId = map
    }

    @available(iOS 13.0, *)
    private func resolveDirectChannel(for userId: Int64, token: String) async throws -> Mezon_Api_ChannelDescription {
        if let cached = dmChannelsByUserId[userId] {
            return cached
        }

        let dmChannels = try await context.account.network.listDirectMessageChannels(token: token)
        cacheDirectChannels(dmChannels)
        if let existing = dmChannelsByUserId[userId] {
            return existing
        }

        let created = try await context.account.network.createDirectMessage(userId: userId, token: token)
        if created.userIds.count == 1, let peerId = created.userIds.first, peerId != 0 {
            dmChannelsByUserId[peerId] = created
        } else {
            dmChannelsByUserId[userId] = created
        }
        return created
    }

    @objc private func searchChanged() {
        containerNode.searchWrapNode.clearButton.isHidden = (containerNode.searchWrapNode.textField.text ?? "").isEmpty
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedApplyFilter), object: nil)
        perform(#selector(debouncedApplyFilter), with: nil, afterDelay: 0.15)
    }

    @objc private func debouncedApplyFilter() {
        applyFilter()
    }

    @objc private func clearSearchTapped() {
        containerNode.searchWrapNode.textField.text = ""
        containerNode.searchWrapNode.clearButton.isHidden = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedApplyFilter), object: nil)
        applyFilter()
    }

    private func copyInvite() {
        guard let inviteLink else { return }
        UIPasteboard.general.string = inviteLink
        Toast.success(L(L10n.ClanInviteSheet.linkCopied))
    }

    private func shareInvite() {
        guard let inviteLink, let inviteURL = URL(string: inviteLink) else { return }
        let ac = UIActivityViewController(activityItems: [inviteURL], applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = containerNode.shareButton.view
            popover.sourceRect = containerNode.shareButton.view.bounds
        }
        presentNativeModal(ac)
    }

    private func showQR() {
        guard let inviteLink, let inviteURL = URL(string: inviteLink) else { return }
        let controller = ClanInviteQRCodeViewController(
            inviteLink: inviteLink,
            inviteURL: inviteURL,
            clanName: clanName.isEmpty ? L(L10n.ClanInviteSheet.unknownClan) : clanName,
            clanLogoURL: clanLogoURL
        )
        presentNativeModal(controller)
    }

    private func updateInviteActionState() {
        let isEnabled = inviteLink != nil
        containerNode.shareButton.setEnabled(isEnabled)
        containerNode.copyButton.setEnabled(isEnabled)
        containerNode.qrButton.setEnabled(isEnabled)
    }

    @objc private func emptyActionTapped() {
        Toast.info(L(L10n.ClanInviteSheet.emptyAction))
    }

    private func showSimpleAlert(message: String) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        presentNativeModal(ac)
    }
}

extension ClanInviteSheetViewController: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        filteredFriends.count
    }

    func tableNode(_ tableNode: ASTableNode, constrainedSizeForRowAt indexPath: IndexPath) -> ASSizeRange {
        ASSizeRange(
            min: CGSize(width: 0, height: 60.sh),
            max: CGSize(width: tableNode.bounds.width, height: 60.sh)
        )
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let item = filteredFriends[indexPath.row]
        let isSent = sentIds.contains(item.id)
        let isLoading = sendingIds.contains(item.id)
        return { [weak self] in
            let cell = ClanInviteFriendCellNode(
                name: item.name,
                avatarURL: item.avatarURL,
                isGroupDM: item.isGroupDM,
                isSent: isSent,
                isLoading: isLoading
            )
            cell.onInvite = { [weak self] in
                if #available(iOS 13.0, *) {
                    self?.inviteUser(item)
                }
            }
            return cell
        }
    }
}
