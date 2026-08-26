import AsyncDisplayKit
import Foundation
import UIKit

@MainActor
final class MyQRCodeContainerNode: ASDisplayNode, ASNetworkImageNodeDelegate {

    private enum CenterImageSelection {
        case profileAvatar
        case mezonLogo
        case custom(UIImage)
    }

    private enum Style {
        static let mezonLogoAsset = "Setting/LogoMezon"
        static let displayNameFontSize: CGFloat = 18
        static let usernameFontSize: CGFloat = 13
        static let gradientColors = [
            UIColor(hex: 0xF0EDFD).cgColor,
            UIColor(hex: 0xBEB5F8).cgColor,
            UIColor(hex: 0x9774FA).cgColor,
        ]
        static let primaryText = UIColor(hex: 0x070709)
        static let actionBlue = UIColor(hex: 0x2F80ED)
        static let badgeBackground = UIColor(hex: 0xF0EEFF)
        static let badgeText = UIColor(hex: 0x6657F5)
    }

    private let context: AccountContext
    private var selectedTab = 0
    private var centerImageSelection: CenterImageSelection = .profileAvatar
    private var containerLayout: ContainerViewLayout?

    private let backButton = ASButtonNode()
    private let titleNode = ASTextNode()

    private let tabContainerNode = ASDisplayNode()
    private let tabSelectionBackgroundNode = ASDisplayNode()
    private let profileTabButton = ASButtonNode()
    private let transferTabButton = ASButtonNode()

    private let cardNode = ASDisplayNode()
    private let cardGradientLayer = CAGradientLayer()
    private let editCenterImageButton = ASButtonNode()
    private let avatarFallbackNode = TextAvatarNode(username: "", size: 48.swh)
    private let avatarNode = ASNetworkImageNode()
    private let nameNode = ASTextNode()
    private let usernameNode = ASTextNode()
    private let usernameBackgroundNode = ASDisplayNode()

    private let qrPanelNode = ASDisplayNode()
    private let mezonLogoIcon = ASImageNode()
    private let mezonLogoText = ASTextNode()
    private let qrTypeNode = ASTextNode()
    private let qrTypeBackgroundNode = ASDisplayNode()
    private let qrImageNode = ASImageNode()
    private let qrLogoFallbackNode = TextAvatarNode(username: "", size: 48.swh)
    private let qrLogoNode = ASNetworkImageNode()
    private let verifiedIconNode = ASImageNode()
    private let verifiedTextNode = ASTextNode()
    private let verifiedBackgroundNode = ASDisplayNode()

    private let downloadButton = ASButtonNode()
    private let shareButton = ASButtonNode()

    var onTabChanged: ((Int) -> Void)?
    var onBackTapped: (() -> Void)?
    var onEditCenterImageTapped: (() -> Void)?
    var onDownloadTapped: ((UIImage) -> Void)?
    var onShareTapped: ((UIImage) -> Void)?
    var editAnchorView: UIView { editCenterImageButton.view }
    var shareAnchorView: UIView { shareButton.view }

    init(context: AccountContext) {
        self.context = context
        super.init()

        backgroundColor = .mezonPrimary
        setupNodes()
        updateContent()
    }

    override func didLoad() {
        super.didLoad()

        cardGradientLayer.colors = Style.gradientColors
        cardGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        cardGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        cardNode.view.layer.insertSublayer(cardGradientLayer, at: 0)
    }

    override func layout() {
        super.layout()
        cardGradientLayer.frame = cardNode.bounds
        cardGradientLayer.cornerRadius = cardNode.cornerRadius
    }

    private func setupNodes() {
        backButton.setImage(
            UIImage(named: "Channel/ArrowLeft")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = .mezonTextStrong
        backButton.imageNode.contentMode = .scaleAspectFit
        backButton.style.preferredSize = CGSize(width: 24.swh, height: 24.swh)
        backButton.hitTestSlop = UIEdgeInsets(
            top: -16.sh, left: -16.sw, bottom: -16.sh, right: -16.sw)
        backButton.addTarget(self, action: #selector(backTapped), forControlEvents: .touchUpInside)

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.myQRCode),
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        tabContainerNode.backgroundColor = .mezonSecondary
        tabContainerNode.cornerRadius = 24.swh

        tabSelectionBackgroundNode.backgroundColor = .mezonPrimary
        tabSelectionBackgroundNode.cornerRadius = 20.swh
        tabSelectionBackgroundNode.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        tabSelectionBackgroundNode.shadowOffset = CGSize(width: 0, height: 2.sh)
        tabSelectionBackgroundNode.shadowRadius = 4.swh
        tabSelectionBackgroundNode.shadowOpacity = 1

        profileTabButton.addTarget(
            self, action: #selector(profileTabTapped), forControlEvents: .touchUpInside)
        transferTabButton.addTarget(
            self, action: #selector(transferTabTapped), forControlEvents: .touchUpInside)

        cardNode.backgroundColor = .clear
        cardNode.cornerRadius = 16.swh
        cardNode.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        cardNode.shadowOffset = CGSize(width: 0, height: 4.sh)
        cardNode.shadowRadius = 12.swh
        cardNode.shadowOpacity = 1

        editCenterImageButton.setImage(
            UIImage(systemName: "pencil")?.withRenderingMode(.alwaysTemplate), for: .normal)
        editCenterImageButton.backgroundColor = .white
        editCenterImageButton.cornerRadius = 20.swh
        editCenterImageButton.tintColor = Style.actionBlue
        editCenterImageButton.imageNode.contentMode = .scaleAspectFit
        editCenterImageButton.accessibilityLabel = L(L10n.QRScanner.centerImage)
        editCenterImageButton.addTarget(
            self, action: #selector(editCenterImageTapped), forControlEvents: .touchUpInside)

        avatarNode.cornerRadius = 24.swh
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.backgroundColor = .clear
        avatarNode.delegate = self

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        usernameNode.maximumNumberOfLines = 1
        usernameNode.truncationMode = .byTruncatingTail

        usernameBackgroundNode.backgroundColor = .white
        usernameBackgroundNode.cornerRadius = 12.swh

        qrPanelNode.backgroundColor = .white
        qrPanelNode.cornerRadius = 16.swh

        mezonLogoIcon.image = UIImage(named: Style.mezonLogoAsset)?.withRenderingMode(.alwaysOriginal)
        mezonLogoIcon.contentMode = .scaleAspectFit
        mezonLogoIcon.clipsToBounds = true
        mezonLogoText.attributedText = NSAttributedString(
            string: "MEZON",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                .foregroundColor: Style.primaryText,
            ])

        qrTypeNode.maximumNumberOfLines = 1
        qrTypeBackgroundNode.backgroundColor = Style.badgeBackground
        qrTypeBackgroundNode.cornerRadius = 10.swh

        qrImageNode.contentMode = .scaleAspectFit

        qrLogoNode.cornerRadius = 8.swh
        qrLogoNode.clipsToBounds = true
        qrLogoNode.contentMode = .scaleAspectFill
        qrLogoNode.backgroundColor = .clear
        qrLogoNode.borderColor = UIColor.white.cgColor
        qrLogoNode.borderWidth = 2.swh
        qrLogoNode.delegate = self
        qrLogoFallbackNode.cornerRadius = 8.swh

        verifiedIconNode.image = UIImage(systemName: "checkmark.seal.fill")?
            .withRenderingMode(.alwaysTemplate)
        verifiedIconNode.tintColor = Style.actionBlue
        verifiedIconNode.contentMode = .scaleAspectFit
        verifiedTextNode.maximumNumberOfLines = 1
        verifiedBackgroundNode.backgroundColor = Style.badgeBackground
        verifiedBackgroundNode.cornerRadius = 10.swh

        configureActionButton(downloadButton, systemName: "square.and.arrow.down")
        configureActionButton(shareButton, systemName: "square.and.arrow.up")
        downloadButton.accessibilityLabel = L(L10n.Common.download)
        shareButton.accessibilityLabel = L(L10n.Common.share)
        downloadButton.addTarget(
            self, action: #selector(downloadTapped), forControlEvents: .touchUpInside)
        shareButton.addTarget(
            self, action: #selector(shareTapped), forControlEvents: .touchUpInside)

        [
            backButton, titleNode,
            tabContainerNode, tabSelectionBackgroundNode, profileTabButton, transferTabButton,
            cardNode,
            avatarFallbackNode, avatarNode, nameNode, usernameBackgroundNode, usernameNode,
            qrPanelNode, mezonLogoIcon, mezonLogoText,
            qrTypeBackgroundNode, qrTypeNode, qrImageNode, qrLogoFallbackNode, qrLogoNode,
            verifiedBackgroundNode, verifiedIconNode, verifiedTextNode,
            downloadButton, shareButton, editCenterImageButton,
        ].forEach { addSubnode($0) }
    }

    private func configureActionButton(_ button: ASButtonNode, systemName: String) {
        button.setImage(
            UIImage(systemName: systemName)?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.backgroundColor = .white
        button.cornerRadius = 8.swh
        button.tintColor = Style.actionBlue
        button.imageNode.contentMode = .scaleAspectFit
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        containerLayout = layout
        setNeedsLayout()
    }

    func updateTab(_ index: Int) {
        selectedTab = index
        updateContent()
        setNeedsLayout()
    }

    func useProfileAvatar() {
        centerImageSelection = .profileAvatar
        updateCenterImage()
    }

    func useMezonLogo() {
        centerImageSelection = .mezonLogo
        updateCenterImage()
    }

    func useCustomCenterImage(_ image: UIImage) {
        centerImageSelection = .custom(image)
        updateCenterImage()
    }

    private func updateContent() {
        let user = context.currentUser

        let displayName = user.map { $0.displayName.isEmpty ? $0.username : $0.displayName }
            ?? "User"
        let username = user.map { $0.username.isEmpty ? displayName : $0.username }
            ?? displayName

        avatarFallbackNode.configure(username: user?.username ?? "")
        if let avatarURL = user?.avatarURL {
            if avatarNode.url == avatarURL, hasValidImage(avatarNode.image) {
                avatarFallbackNode.showImageMode()
            } else {
                if avatarNode.url != avatarURL {
                    avatarNode.image = nil
                }
                avatarNode.url = avatarURL
                avatarFallbackNode.showSkeleton()
            }
        } else {
            avatarNode.url = nil
            avatarNode.image = nil
        }

        nameNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [
                .font: UIFont.systemFont(ofSize: Style.displayNameFontSize, weight: .bold),
                .foregroundColor: Style.primaryText,
            ])
        usernameNode.attributedText = NSAttributedString(
            string: username.hasPrefix("@") ? username : "@\(username)",
            attributes: [
                .font: UIFont.systemFont(ofSize: Style.usernameFontSize, weight: .bold),
                .foregroundColor: Style.badgeText,
            ])

        let isProfile = selectedTab == 0
        let profileColor = isProfile ? UIColor.mezonTextStrong : UIColor.mezonTextMuted
        let transferColor = isProfile ? UIColor.mezonTextMuted : UIColor.mezonTextStrong
        profileTabButton.setTitle(
            L(L10n.QRScanner.qrProfile), with: .systemFont(ofSize: 14.sf, weight: .medium),
            with: profileColor, for: .normal)
        transferTabButton.setTitle(
            L(L10n.QRScanner.qrTransfer), with: .systemFont(ofSize: 14.sf, weight: .medium),
            with: transferColor, for: .normal)

        let qrType = isProfile ? L(L10n.QRScanner.profileBadge) : L(L10n.QRScanner.transferBadge)
        qrTypeNode.attributedText = badgeText(qrType)
        verifiedTextNode.attributedText = badgeText(L(L10n.QRScanner.verifiedByMezon).uppercased())

        if isProfile {
            generateQR(
                data: profileChatURLString(user: user)
                    ?? "https://mezon.ai/chat/\(user?.username ?? "")")
        } else {
            generateQR(data: transferPayload(user: user))
        }

        updateCenterImage()
    }

    private func badgeText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10.sf, weight: .bold),
                .foregroundColor: Style.badgeText,
            ])
    }

    private func updateCenterImage() {
        switch centerImageSelection {
        case .profileAvatar:
            let user = context.currentUser
            qrLogoFallbackNode.configure(username: user?.username ?? "")
            if let avatarURL = user?.avatarURL {
                if qrLogoNode.url == avatarURL, hasValidImage(qrLogoNode.image) {
                    qrLogoFallbackNode.showImageMode()
                } else {
                    if qrLogoNode.url != avatarURL {
                        qrLogoNode.image = nil
                    }
                    qrLogoNode.url = avatarURL
                    qrLogoFallbackNode.showSkeleton()
                }
            } else {
                qrLogoNode.url = nil
                qrLogoNode.image = nil
            }
        case .mezonLogo:
            qrLogoNode.url = nil
            qrLogoNode.image = UIImage(named: Style.mezonLogoAsset)
            qrLogoFallbackNode.showImageMode()
        case let .custom(image):
            qrLogoNode.url = nil
            qrLogoNode.image = image
            qrLogoFallbackNode.showImageMode()
        }
    }

    private func profileChatURLString(user: User?) -> String? {
        guard let user else { return nil }
        let profile = QRUserProfileData(
            id: user.id, avatar: user.avatarURL?.absoluteString, name: user.displayName)
        guard let jsonData = try? JSONEncoder().encode(profile) else { return nil }
        let base64 = jsonData.base64EncodedString()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "mezon.ai"
        let pathAllowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/"))
        let encodedUsername = user.username.addingPercentEncoding(withAllowedCharacters: pathAllowed)
            ?? user.username
        components.percentEncodedPath = "/chat/" + encodedUsername
        components.queryItems = [URLQueryItem(name: "data", value: base64)]
        return components.url?.absoluteString
    }

    private func transferPayload(user: User?) -> String {
        guard let user else { return "{}" }
        let receiverName = user.username.isEmpty ? user.displayName : user.username
        let payload: [String: Any] = [
            "receiver_name": receiverName,
            "receiver_display_name": user.displayName,
            "receiver_id": user.id,
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let value = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return value
    }

    private func generateQR(data: String) {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(data.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return }
        let scaleX = 400 / outputImage.extent.size.width
        let scaleY = 400 / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let imageContext = CIContext()
        if let image = imageContext.createCGImage(transformedImage, from: transformedImage.extent) {
            qrImageNode.image = UIImage(cgImage: image)
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let size = constrainedSize.max

        let tabWidth = size.width - 32.sw
        tabContainerNode.style.preferredSize = CGSize(width: tabWidth, height: 48.sh)
        tabSelectionBackgroundNode.style.preferredSize = CGSize(
            width: tabWidth / 2 - 4.sw, height: 40.sh)
        profileTabButton.style.preferredSize = CGSize(width: tabWidth / 2, height: 48.sh)
        transferTabButton.style.preferredSize = CGSize(width: tabWidth / 2, height: 48.sh)

        let tabIndicatorCenter = ASCenterLayoutSpec(
            centeringOptions: .Y, sizingOptions: [], child: tabSelectionBackgroundNode)
        tabIndicatorCenter.style.layoutPosition = CGPoint(
            x: selectedTab == 0 ? 2.sw : tabWidth / 2 + 2.sw, y: 0)
        let tabIndicatorPosition = ASAbsoluteLayoutSpec(children: [tabIndicatorCenter])

        let tabsStack = ASStackLayoutSpec.horizontal()
        tabsStack.children = [profileTabButton, transferTabButton]
        let tabsBackground = ASBackgroundLayoutSpec(child: tabsStack, background: tabContainerNode)
        let tabsWithIndicator = ASOverlayLayoutSpec(
            child: tabsBackground, overlay: tabIndicatorPosition)
        let tabsInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 24.sh, left: 16.sw, bottom: 20.sh, right: 16.sw),
            child: tabsWithIndicator)

        let cardWidth = max(0, size.width - 40.sw)
        let editButtonSize = 40.swh
        let editButtonMargin = 10.sw
        let headerSideInset = max(24.sw, editButtonSize + editButtonMargin + 8.sw)
        let maxHeaderTextWidth = max(
            80.sw,
            cardWidth - headerSideInset * 2 - 48.swh - 12.sw)
        avatarNode.style.preferredSize = CGSize(width: 48.swh, height: 48.swh)
        avatarFallbackNode.style.preferredSize = CGSize(width: 48.swh, height: 48.swh)
        nameNode.style.maxWidth = ASDimensionMake(maxHeaderTextWidth)
        usernameNode.style.maxWidth = ASDimensionMake(maxHeaderTextWidth - 16.sw)

        let usernameInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2.sh, left: 8.sw, bottom: 2.sh, right: 8.sw),
            child: usernameNode)
        let usernameBadge = ASBackgroundLayoutSpec(
            child: usernameInset, background: usernameBackgroundNode)

        let identityStack = ASStackLayoutSpec.vertical()
        identityStack.spacing = 4.sh
        identityStack.alignItems = .start
        identityStack.children = [nameNode, usernameBadge]

        let headerStack = ASStackLayoutSpec.horizontal()
        headerStack.spacing = 12.sw
        headerStack.alignItems = .center
        let avatar = ASOverlayLayoutSpec(child: avatarFallbackNode, overlay: avatarNode)
        headerStack.children = [avatar, identityStack]
        let centeredHeader = ASCenterLayoutSpec(
            centeringOptions: .X, sizingOptions: [], child: headerStack)

        mezonLogoIcon.style.preferredSize = CGSize(width: 20.swh, height: 20.swh)
        let brandStack = ASStackLayoutSpec.horizontal()
        brandStack.spacing = 6.sw
        brandStack.alignItems = .center
        brandStack.children = [mezonLogoIcon, mezonLogoText]

        let qrTypeInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2.sh, left: 8.sw, bottom: 2.sh, right: 8.sw),
            child: qrTypeNode)
        let qrTypeBadge = ASBackgroundLayoutSpec(
            child: qrTypeInset, background: qrTypeBackgroundNode)

        let qrSize = min(264.swh, max(0, cardWidth - 64.sw))
        let panelWidth = qrSize + 32.sw
        let panelHeaderWidth = max(0, panelWidth - 32.sw)
        let panelHeader = ASStackLayoutSpec.horizontal()
        panelHeader.alignItems = .center
        panelHeader.justifyContent = .spaceBetween
        panelHeader.children = [brandStack, qrTypeBadge]
        panelHeader.style.preferredSize = CGSize(width: panelHeaderWidth, height: 20.sh)

        qrImageNode.style.preferredSize = CGSize(width: qrSize, height: qrSize)
        qrLogoFallbackNode.style.preferredSize = CGSize(width: 48.swh, height: 48.swh)
        qrLogoNode.style.preferredSize = CGSize(width: 48.swh, height: 48.swh)
        let qrLogo = ASOverlayLayoutSpec(child: qrLogoFallbackNode, overlay: qrLogoNode)
        let qrCenter = ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: [], child: qrLogo)
        let qrContainer = ASOverlayLayoutSpec(child: qrImageNode, overlay: qrCenter)

        verifiedIconNode.style.preferredSize = CGSize(width: 14.swh, height: 14.swh)
        let verifiedStack = ASStackLayoutSpec.horizontal()
        verifiedStack.spacing = 4.sw
        verifiedStack.alignItems = .center
        verifiedStack.children = [verifiedIconNode, verifiedTextNode]
        let verifiedInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 3.sh, left: 8.sw, bottom: 3.sh, right: 8.sw),
            child: verifiedStack)
        let verifiedBadge = ASBackgroundLayoutSpec(
            child: verifiedInset, background: verifiedBackgroundNode)

        let panelStack = ASStackLayoutSpec.vertical()
        panelStack.spacing = 8.sh
        panelStack.alignItems = .center
        panelStack.children = [panelHeader, qrContainer, verifiedBadge]
        let panelContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 14.sh, left: 16.sw, bottom: 14.sh, right: 16.sw),
            child: panelStack)
        let panel = ASBackgroundLayoutSpec(child: panelContent, background: qrPanelNode)

        downloadButton.style.preferredSize = CGSize(width: 60.sw, height: 42.sh)
        shareButton.style.preferredSize = CGSize(width: 60.sw, height: 42.sh)
        let actionStack = ASStackLayoutSpec.horizontal()
        actionStack.spacing = 16.sw
        actionStack.children = [downloadButton, shareButton]

        let cardContentStack = ASStackLayoutSpec.vertical()
        cardContentStack.spacing = 24.sh
        cardContentStack.alignItems = .center
        cardContentStack.children = [centeredHeader, panel, actionStack]
        let cardContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 24.sh, left: 0, bottom: 24.sh, right: 0),
            child: cardContentStack)
        let cardBackground = ASBackgroundLayoutSpec(child: cardContent, background: cardNode)

        editCenterImageButton.style.preferredSize = CGSize(
            width: editButtonSize, height: editButtonSize)
        editCenterImageButton.style.layoutPosition = CGPoint(
            x: max(0, cardWidth - editButtonSize - editButtonMargin), y: 10.sh)
        let editButtonPosition = ASAbsoluteLayoutSpec(children: [editCenterImageButton])
        let cardWithEditButton = ASOverlayLayoutSpec(
            child: cardBackground, overlay: editButtonPosition)
        let cardInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20.sw, bottom: 24.sh, right: 20.sw),
            child: cardWithEditButton)

        let backButtonInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 0), child: backButton)
        let backButtonCenter = ASCenterLayoutSpec(
            centeringOptions: .Y, sizingOptions: [], child: backButtonInset)
        backButtonCenter.style.layoutPosition = CGPoint(x: 0, y: 0)

        let headerTitleCenter = ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: [], child: titleNode)
        let headerOverlay = ASOverlayLayoutSpec(
            child: headerTitleCenter, overlay: ASAbsoluteLayoutSpec(children: [backButtonCenter]))
        headerOverlay.style.preferredSize = CGSize(width: size.width, height: 44.sh)

        let layoutTop = containerLayout?.safeInsets.top ?? 0
        let safeTop = isNodeLoaded ? max(view.safeAreaInsets.top, layoutTop) : layoutTop
        let headerInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: safeTop, left: 0, bottom: 0, right: 0),
            child: headerOverlay)

        let mainStack = ASStackLayoutSpec.vertical()
        mainStack.children = [headerInset, tabsInset, cardInset]
        return mainStack
    }

    @objc private func profileTabTapped() {
        onTabChanged?(0)
    }

    @objc private func transferTabTapped() {
        onTabChanged?(1)
    }

    @objc private func backTapped() {
        onBackTapped?()
    }

    @objc private func editCenterImageTapped() {
        onEditCenterImageTapped?()
    }

    @objc private func downloadTapped() {
        if let image = getCardSnapshot() {
            onDownloadTapped?(image)
        }
    }

    @objc private func shareTapped() {
        if let image = getCardSnapshot() {
            onShareTapped?(image)
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didFailWithError error: Error) {
        if imageNode === avatarNode {
            avatarFallbackNode.showPlaceholder()
        } else if imageNode === qrLogoNode, case .profileAvatar = centerImageSelection {
            qrLogoFallbackNode.showPlaceholder()
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didLoad image: UIImage) {
        let imageIsValid = hasValidImage(image)
        if imageNode === avatarNode {
            if imageIsValid {
                avatarFallbackNode.showImageMode()
            } else {
                avatarFallbackNode.showPlaceholder()
            }
        } else if imageNode === qrLogoNode, case .profileAvatar = centerImageSelection {
            if imageIsValid {
                qrLogoFallbackNode.showImageMode()
            } else {
                qrLogoFallbackNode.showPlaceholder()
            }
        }
    }

    private func hasValidImage(_ image: UIImage?) -> Bool {
        guard let image else { return false }
        return image.size.width >= 0.5 && image.size.height >= 0.5
    }

    private func getCardSnapshot() -> UIImage? {
        let previousEditHidden = editCenterImageButton.isHidden
        editCenterImageButton.isHidden = true
        defer {
            editCenterImageButton.isHidden = previousEditHidden
        }

        let targetFrame = cardNode.frame
        guard targetFrame.width > 0, targetFrame.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: targetFrame.size, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: -targetFrame.origin.x, y: -targetFrame.origin.y)
            self.view.layer.render(in: context.cgContext)
        }
    }
}
