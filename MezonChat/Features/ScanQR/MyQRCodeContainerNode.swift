import AsyncDisplayKit
import Foundation
import UIKit

@MainActor
final class MyQRCodeContainerNode: ASDisplayNode {

    private let context: AccountContext
    private var selectedTab: Int = 0
    private var layout: ContainerViewLayout?

    private let backgroundNode = ASDisplayNode()
    private let headerContainer = ASDisplayNode()
    private let backButton = ASButtonNode()
    private let titleNode = ASTextNode()

    private let tabContainerNode = ASDisplayNode()
    private let tabSelectionBackgroundNode = ASDisplayNode()
    private let profileTabButton = ASButtonNode()
    private let transferTabButton = ASButtonNode()

    private let cardNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let nameNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let dividerNode = ASDisplayNode()

    private let mezonLogoIcon = ASImageNode()
    private let mezonLogoText = ASTextNode()

    private let qrImageNode = ASImageNode()
    private let qrLogoNode = ASNetworkImageNode()

    private let poweredByLine = ASDisplayNode()
    private let poweredByText = ASTextNode()

    private let downloadButton = ASButtonNode()
    private let shareButton = ASButtonNode()

    private let scanInstructionNode = ASTextNode()

    var onTabChanged: ((Int) -> Void)?
    var onBackTapped: (() -> Void)?
    var onDownloadTapped: ((UIImage) -> Void)?
    var onShareTapped: ((UIImage) -> Void)?

    init(context: AccountContext) {
        self.context = context
        super.init()

        self.backgroundColor = .mezonPrimary

        setupNodes()
        updateContent()
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

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.myQRCode),
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        backButton.addTarget(self, action: #selector(backTapped), forControlEvents: .touchUpInside)

        addSubnode(headerContainer)
        addSubnode(backButton)
        addSubnode(titleNode)

        tabContainerNode.backgroundColor = .mezonSecondary
        tabContainerNode.cornerRadius = 24.swh

        tabSelectionBackgroundNode.backgroundColor = .mezonPrimary
        tabSelectionBackgroundNode.cornerRadius = 20.swh
        tabSelectionBackgroundNode.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        tabSelectionBackgroundNode.shadowOffset = CGSize(width: 0, height: 2.sh)
        tabSelectionBackgroundNode.shadowRadius = 4.swh
        tabSelectionBackgroundNode.shadowOpacity = 1

        cardNode.backgroundColor = .mezonSecondary
        cardNode.cornerRadius = 16.swh
        cardNode.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        cardNode.shadowOffset = CGSize(width: 0, height: 4.sh)
        cardNode.shadowRadius = 12.swh
        cardNode.shadowOpacity = 1

        avatarNode.cornerRadius = 12.swh
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = .mezonTertiary

        dividerNode.backgroundColor = .mezonTertiary

        mezonLogoIcon.image = UIImage(named: "Setting/LogoMezon")?.withRenderingMode(
            .alwaysOriginal)
        mezonLogoIcon.contentMode = .scaleAspectFit

        mezonLogoText.attributedText = NSAttributedString(
            string: "Mezon",
            attributes: [
                .font: UIFont.systemFont(ofSize: 22.sf, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        qrImageNode.contentMode = .scaleAspectFit

        qrLogoNode.cornerRadius = 8.swh
        qrLogoNode.clipsToBounds = true
        qrLogoNode.borderColor = UIColor.white.cgColor
        qrLogoNode.borderWidth = 2

        poweredByLine.backgroundColor = .mezonTertiary
        poweredByText.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.poweredBy),
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                .foregroundColor: UIColor.mezonTextMuted,
            ])

        downloadButton.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        downloadButton.backgroundColor = .mezonTertiary
        downloadButton.cornerRadius = 4.swh
        downloadButton.tintColor = UIColor.mezonTextPrimary

        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.backgroundColor = .mezonTertiary
        shareButton.cornerRadius = 4.swh
        shareButton.tintColor = UIColor.mezonTextPrimary

        addSubnode(tabContainerNode)
        addSubnode(tabSelectionBackgroundNode)
        addSubnode(profileTabButton)
        addSubnode(transferTabButton)

        addSubnode(cardNode)
        addSubnode(avatarNode)
        addSubnode(nameNode)
        addSubnode(subtitleNode)
        addSubnode(dividerNode)
        addSubnode(mezonLogoIcon)
        addSubnode(mezonLogoText)
        addSubnode(qrImageNode)
        addSubnode(qrLogoNode)
        addSubnode(poweredByLine)
        addSubnode(poweredByText)

        addSubnode(downloadButton)
        addSubnode(shareButton)
        addSubnode(scanInstructionNode)

        profileTabButton.addTarget(
            self, action: #selector(profileTabTapped), forControlEvents: .touchUpInside)
        transferTabButton.addTarget(
            self, action: #selector(transferTabTapped), forControlEvents: .touchUpInside)

        downloadButton.addTarget(
            self, action: #selector(downloadTapped), forControlEvents: .touchUpInside)
        shareButton.addTarget(
            self, action: #selector(shareTapped), forControlEvents: .touchUpInside)
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.layout = layout
        self.setNeedsLayout()
    }

    func updateTab(_ index: Int) {
        self.selectedTab = index
        updateContent()
        self.setNeedsLayout()
    }

    private func updateContent() {
        let user = context.currentUser
        avatarNode.url = user?.avatarURL
        qrLogoNode.url = user?.avatarURL

        nameNode.attributedText = NSAttributedString(
            string: user?.displayName ?? "User",
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        let profileColor = selectedTab == 0 ? UIColor.mezonTextStrong : UIColor.mezonTextMuted
        let transferColor = selectedTab == 1 ? UIColor.mezonTextStrong : UIColor.mezonTextMuted
        profileTabButton.setTitle(
            L(L10n.QRScanner.qrProfile), with: .systemFont(ofSize: 14.sf, weight: .medium),
            with: profileColor, for: .normal)
        transferTabButton.setTitle(
            L(L10n.QRScanner.qrTransfer), with: .systemFont(ofSize: 14.sf, weight: .medium),
            with: transferColor, for: .normal)

        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        if selectedTab == 0 {
            subtitleNode.isHidden = false
            subtitleNode.attributedText = NSAttributedString(
                string: L(L10n.QRScanner.shareWithOthers),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                ])
            scanInstructionNode.attributedText = NSAttributedString(
                string: L(L10n.QRScanner.scanProfileHelp),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                    .paragraphStyle: pStyle,
                ])

            if let urlString = profileChatURLString(user: user) {
                generateQR(data: urlString)
            } else {
                generateQR(data: "https://mezon.ai/chat/\(user?.username ?? "")")
            }
        } else {
            subtitleNode.isHidden = true
            subtitleNode.attributedText = nil
            scanInstructionNode.attributedText = NSAttributedString(
                string: L(L10n.QRScanner.scanTransferHelp),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                    .paragraphStyle: pStyle,
                ])

            generateQR(data: "{\"receiver_id\": \"\(user?.id ?? "")\"}")
        }
    }

    private func profileChatURLString(user: User?) -> String? {
        guard let user else { return nil }
        let profile = QRUserProfileData(
            id: user.id, avatar: user.avatarURL?.absoluteString, name: user.displayName)
        guard let jsonData = try? JSONEncoder().encode(profile) else { return nil }
        let b64 = jsonData.base64EncodedString()
        var c = URLComponents()
        c.scheme = "https"
        c.host = "mezon.ai"
        let pathSegAllowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/"))
        let enc = user.username.addingPercentEncoding(withAllowedCharacters: pathSegAllowed)
            ?? user.username
        c.percentEncodedPath = "/chat/" + enc
        c.queryItems = [URLQueryItem(name: "data", value: b64)]
        return c.url?.absoluteString
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

        let context = CIContext()
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            qrImageNode.image = UIImage(cgImage: cgImage)
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
        let tabIndicatorPos = ASAbsoluteLayoutSpec(children: [tabIndicatorCenter])
        tabIndicatorCenter.style.layoutPosition = CGPoint(
            x: selectedTab == 0 ? 2.sw : tabWidth / 2 + 2.sw, y: 0)

        let tabsStack = ASStackLayoutSpec.horizontal()
        tabsStack.children = [profileTabButton, transferTabButton]

        let tabsBackground = ASBackgroundLayoutSpec(child: tabsStack, background: tabContainerNode)
        let tabsWithIndicator = ASOverlayLayoutSpec(child: tabsBackground, overlay: tabIndicatorPos)
        let tabsInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 24.sh, left: 16.sw, bottom: 20.sh, right: 16.sw),
            child: tabsWithIndicator)

        avatarNode.style.preferredSize = CGSize(width: 56.swh, height: 56.swh)
        let identityStack = ASStackLayoutSpec.vertical()
        identityStack.spacing = 2.sh
        identityStack.children = [nameNode, subtitleNode]

        let headerStack = ASStackLayoutSpec.horizontal()
        headerStack.spacing = 12.sw
        headerStack.alignItems = .center
        headerStack.children = [avatarNode, identityStack]

        dividerNode.style.preferredSize = CGSize(width: size.width - 64.sw, height: 1)

        mezonLogoIcon.style.preferredSize = CGSize(width: 28.swh, height: 28.swh)
        let mezonLogoStack = ASStackLayoutSpec.horizontal()
        mezonLogoStack.spacing = 10.sw
        mezonLogoStack.alignItems = .center
        mezonLogoStack.children = [mezonLogoIcon, mezonLogoText]

        qrImageNode.style.preferredSize = CGSize(width: 240.swh, height: 240.swh)
        qrLogoNode.style.preferredSize = CGSize(width: 48.swh, height: 48.swh)
        let qrCenter = ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: [], child: qrLogoNode)
        let qrContainer = ASOverlayLayoutSpec(child: qrImageNode, overlay: qrCenter)

        poweredByLine.style.preferredSize = CGSize(width: 100.sw, height: 1)
        let poweredStack = ASStackLayoutSpec.vertical()
        poweredStack.alignItems = .center
        poweredStack.spacing = 8.sh
        poweredStack.children = [poweredByLine, poweredByText]

        downloadButton.style.preferredSize = CGSize(width: 60.sw, height: 42.sh)
        shareButton.style.preferredSize = CGSize(width: 60.sw, height: 42.sh)
        downloadButton.cornerRadius = 8.swh
        shareButton.cornerRadius = 8.swh

        let actionStack = ASStackLayoutSpec.horizontal()
        actionStack.spacing = 16.sw
        actionStack.children = [downloadButton, shareButton]

        let scanInstructionInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 16.sw),
            child: scanInstructionNode)

        let footerStack = ASStackLayoutSpec.vertical()
        footerStack.spacing = 24.sh
        footerStack.alignItems = .center
        footerStack.children = [actionStack, scanInstructionInset]

        let cardContentStack = ASStackLayoutSpec.vertical()
        cardContentStack.spacing = 24.sh
        cardContentStack.alignItems = .center
        cardContentStack.children = [
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 24.sh, left: 24.sw, bottom: 0, right: 24.sw),
                child: headerStack),
            dividerNode,
            mezonLogoStack,
            qrContainer,
            poweredStack,
            footerStack,
        ]

        let cardBackground = ASBackgroundLayoutSpec(
            child: ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 0, left: 0, bottom: 32.sh, right: 0),
                child: cardContentStack
            ), background: cardNode)
        let cardInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20.sw, bottom: 24.sh, right: 20.sw),
            child: cardBackground)

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

        let layoutTop = layout?.safeInsets.top ?? 0
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

    private func getCardSnapshot() -> UIImage? {
        let prevDownloadHidden = downloadButton.isHidden
        let prevShareHidden = shareButton.isHidden
        let prevSubtitleHidden = subtitleNode.isHidden
        let prevCardBG = cardNode.backgroundColor

        downloadButton.isHidden = true
        shareButton.isHidden = true
        subtitleNode.isHidden = true
        cardNode.backgroundColor = .clear

        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = cardNode.bounds
        gradientLayer.colors = UIColor.loginGradientColors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = cardNode.cornerRadius
        cardNode.view.layer.insertSublayer(gradientLayer, at: 0)

        let qrBgNode = ASDisplayNode()
        qrBgNode.backgroundColor = .white
        qrBgNode.cornerRadius = 8
        let qrFrame = qrImageNode.view.convert(qrImageNode.view.bounds, to: cardNode.view)
        qrBgNode.frame = qrFrame.insetBy(dx: -8, dy: -8)
        cardNode.view.insertSubview(qrBgNode.view, belowSubview: qrImageNode.view)

        let targetFrame = cardNode.frame
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        let renderer = UIGraphicsImageRenderer(size: targetFrame.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -targetFrame.origin.x, y: -targetFrame.origin.y)
            self.view.layer.render(in: ctx.cgContext)
        }

        gradientLayer.removeFromSuperlayer()
        qrBgNode.view.removeFromSuperview()
        cardNode.backgroundColor = prevCardBG
        downloadButton.isHidden = prevDownloadHidden
        shareButton.isHidden = prevShareHidden
        subtitleNode.isHidden = prevSubtitleHidden

        return image
    }
}
