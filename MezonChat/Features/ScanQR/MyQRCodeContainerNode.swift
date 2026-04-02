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
        backButton.style.preferredSize = CGSize(width: 24, height: 24)
        backButton.hitTestSlop = UIEdgeInsets(top: -16, left: -16, bottom: -16, right: -16)

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.myQRCode),
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        backButton.addTarget(self, action: #selector(backTapped), forControlEvents: .touchUpInside)

        addSubnode(headerContainer)
        addSubnode(backButton)
        addSubnode(titleNode)

        tabContainerNode.backgroundColor = .mezonSecondary
        tabContainerNode.cornerRadius = 24

        tabSelectionBackgroundNode.backgroundColor = .mezonPrimary
        tabSelectionBackgroundNode.cornerRadius = 20
        tabSelectionBackgroundNode.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        tabSelectionBackgroundNode.shadowOffset = CGSize(width: 0, height: 2)
        tabSelectionBackgroundNode.shadowRadius = 4
        tabSelectionBackgroundNode.shadowOpacity = 1

        cardNode.backgroundColor = .mezonSecondary
        cardNode.cornerRadius = 16
        cardNode.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        cardNode.shadowOffset = CGSize(width: 0, height: 4)
        cardNode.shadowRadius = 12
        cardNode.shadowOpacity = 1

        avatarNode.cornerRadius = 12
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = .mezonTertiary

        dividerNode.backgroundColor = .mezonTertiary

        mezonLogoIcon.image = UIImage(named: "Setting/LogoMezon")?.withRenderingMode(
            .alwaysOriginal)
        mezonLogoIcon.contentMode = .scaleAspectFit

        mezonLogoText.attributedText = NSAttributedString(
            string: "Mezon",
            attributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        qrImageNode.contentMode = .scaleAspectFit

        qrLogoNode.cornerRadius = 8
        qrLogoNode.clipsToBounds = true
        qrLogoNode.borderColor = UIColor.white.cgColor
        qrLogoNode.borderWidth = 2

        poweredByLine.backgroundColor = .mezonTertiary
        poweredByText.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.poweredBy),
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.mezonTextMuted,
            ])

        downloadButton.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        downloadButton.backgroundColor = .mezonTertiary
        downloadButton.cornerRadius = 4
        downloadButton.tintColor = UIColor.mezonTextPrimary

        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.backgroundColor = .mezonTertiary
        shareButton.cornerRadius = 4
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
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.mezonTextStrong,
            ])

        let profileColor = selectedTab == 0 ? UIColor.mezonTextStrong : UIColor.mezonTextMuted
        let transferColor = selectedTab == 1 ? UIColor.mezonTextStrong : UIColor.mezonTextMuted
        profileTabButton.setTitle(
            L(L10n.QRScanner.qrProfile), with: .systemFont(ofSize: 14, weight: .medium),
            with: profileColor, for: .normal)
        transferTabButton.setTitle(
            L(L10n.QRScanner.qrTransfer), with: .systemFont(ofSize: 14, weight: .medium),
            with: transferColor, for: .normal)

        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        if selectedTab == 0 {
            subtitleNode.attributedText = NSAttributedString(
                string: L(L10n.QRScanner.shareWithOthers),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                ])
            scanInstructionNode.attributedText = NSAttributedString(
                string: L(L10n.QRScanner.scanProfileHelp),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                    .paragraphStyle: pStyle,
                ])

            if let payload = encodeProfilePayload(user: user) {
                generateQR(data: "https://mezon.ai/chat/\(user?.username ?? "")?data=\(payload)")
            } else {
                generateQR(data: "https://mezon.ai/chat/\(user?.username ?? "")")
            }
        } else {
            subtitleNode.attributedText = NSAttributedString(
                string: "\(L(L10n.Profile.balance)): 0 \(L(L10n.Profile.currency))",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                ])
            scanInstructionNode.attributedText = NSAttributedString(
                string: L(L10n.QRScanner.scanTransferHelp),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted,
                    .paragraphStyle: pStyle,
                ])

            generateQR(data: "{\"receiver_id\": \"\(user?.id ?? "")\"}")
        }
    }

    private func encodeProfilePayload(user: User?) -> String? {
        guard let user = user else { return nil }
        let payload: [String: Any] = [
            "id": user.id,
            "avatar": user.avatarURL?.absoluteString ?? "",
            "name": user.displayName,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
            let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return nil
        }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")

        guard let encodedJSON = jsonString.addingPercentEncoding(withAllowedCharacters: allowed),
            let encodedData = encodedJSON.data(using: .utf8)
        else {
            return nil
        }

        return encodedData.base64EncodedString()
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

        let tabWidth = size.width - 32
        tabContainerNode.style.preferredSize = CGSize(width: tabWidth, height: 48)
        tabSelectionBackgroundNode.style.preferredSize = CGSize(width: tabWidth / 2 - 4, height: 40)
        profileTabButton.style.preferredSize = CGSize(width: tabWidth / 2, height: 48)
        transferTabButton.style.preferredSize = CGSize(width: tabWidth / 2, height: 48)

        let tabIndicatorCenter = ASCenterLayoutSpec(
            centeringOptions: .Y, sizingOptions: [], child: tabSelectionBackgroundNode)
        let tabIndicatorPos = ASAbsoluteLayoutSpec(children: [tabIndicatorCenter])
        tabIndicatorCenter.style.layoutPosition = CGPoint(
            x: selectedTab == 0 ? 2 : tabWidth / 2 + 2, y: 0)

        let tabsStack = ASStackLayoutSpec.horizontal()
        tabsStack.children = [profileTabButton, transferTabButton]

        let tabsBackground = ASBackgroundLayoutSpec(child: tabsStack, background: tabContainerNode)
        let tabsWithIndicator = ASOverlayLayoutSpec(child: tabsBackground, overlay: tabIndicatorPos)
        let tabsInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 24, left: 16, bottom: 20, right: 16),
            child: tabsWithIndicator)

        avatarNode.style.preferredSize = CGSize(width: 56, height: 56)
        let identityStack = ASStackLayoutSpec.vertical()
        identityStack.spacing = 2
        identityStack.children = [nameNode, subtitleNode]

        let headerStack = ASStackLayoutSpec.horizontal()
        headerStack.spacing = 12
        headerStack.alignItems = .center
        headerStack.children = [avatarNode, identityStack]

        dividerNode.style.preferredSize = CGSize(width: size.width - 64, height: 1)

        mezonLogoIcon.style.preferredSize = CGSize(width: 28, height: 28)
        let mezonLogoStack = ASStackLayoutSpec.horizontal()
        mezonLogoStack.spacing = 10
        mezonLogoStack.alignItems = .center
        mezonLogoStack.children = [mezonLogoIcon, mezonLogoText]

        qrImageNode.style.preferredSize = CGSize(width: 240, height: 240)
        qrLogoNode.style.preferredSize = CGSize(width: 48, height: 48)
        let qrCenter = ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: [], child: qrLogoNode)
        let qrContainer = ASOverlayLayoutSpec(child: qrImageNode, overlay: qrCenter)

        poweredByLine.style.preferredSize = CGSize(width: 100, height: 1)
        let poweredStack = ASStackLayoutSpec.vertical()
        poweredStack.alignItems = .center
        poweredStack.spacing = 8
        poweredStack.children = [poweredByLine, poweredByText]

        downloadButton.style.preferredSize = CGSize(width: 60, height: 42)
        shareButton.style.preferredSize = CGSize(width: 60, height: 42)
        downloadButton.cornerRadius = 8
        shareButton.cornerRadius = 8

        let actionStack = ASStackLayoutSpec.horizontal()
        actionStack.spacing = 16
        actionStack.children = [downloadButton, shareButton]

        let footerStack = ASStackLayoutSpec.vertical()
        footerStack.spacing = 24
        footerStack.alignItems = .center
        footerStack.children = [actionStack, scanInstructionNode]

        let cardContentStack = ASStackLayoutSpec.vertical()
        cardContentStack.spacing = 24
        cardContentStack.alignItems = .center
        cardContentStack.children = [
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 24, left: 24, bottom: 0, right: 24), child: headerStack),
            dividerNode,
            mezonLogoStack,
            qrContainer,
            poweredStack,
            footerStack,
        ]

        let cardBackground = ASBackgroundLayoutSpec(
            child: ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 0, left: 0, bottom: 32, right: 0), child: cardContentStack
            ), background: cardNode)
        let cardInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20, bottom: 24, right: 20), child: cardBackground)

        let backButtonInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0), child: backButton)
        let backButtonCenter = ASCenterLayoutSpec(
            centeringOptions: .Y, sizingOptions: [], child: backButtonInset)
        backButtonCenter.style.layoutPosition = CGPoint(x: 0, y: 0)

        let headerTitleCenter = ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: [], child: titleNode)

        let headerOverlay = ASOverlayLayoutSpec(
            child: headerTitleCenter, overlay: ASAbsoluteLayoutSpec(children: [backButtonCenter]))
        headerOverlay.style.preferredSize = CGSize(width: size.width, height: 44)

        let safeTop = max(layout?.safeInsets.top ?? 0, 54)
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
}
