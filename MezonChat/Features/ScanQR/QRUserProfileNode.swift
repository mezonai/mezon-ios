import AsyncDisplayKit
import Foundation
import SwiftProtobuf

struct QRUserProfileData: Codable {
    let id: String
    let avatar: String?
    let name: String
}

final class QRUserProfileNode: ASDisplayNode {
    private let profile: QRUserProfileData
    private let theme: ThemeAttributes

    private let containerNode = ASDisplayNode()
    private let titleNode = ASTextNode()
    private let avatarNode = ASNetworkImageNode()
    private let nameNode = ASTextNode()
    private let messageButton = ASButtonNode()
    private let closeButton = ASButtonNode()

    var onMessage: (() -> Void)?
    var onClose: (() -> Void)?

    init(profile: QRUserProfileData, theme: ThemeAttributes) {
        self.profile = profile
        self.theme = theme
        super.init()

        backgroundColor = UIColor.mezonPrimary

        containerNode.backgroundColor = theme.secondary
        containerNode.cornerRadius = 24
        containerNode.clipsToBounds = true
        addSubnode(containerNode)

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.userProfile).uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: theme.textDisabled,
                .paragraphStyle: centeredParagraphStyle(),
            ])
        containerNode.addSubnode(titleNode)

        avatarNode.style.preferredSize = CGSize(width: 80, height: 80)
        avatarNode.cornerRadius = 40
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = theme.bgInfor
        if let avatar = profile.avatar, let url = URL(string: avatar) {
            avatarNode.url = url
        }
        containerNode.addSubnode(avatarNode)

        nameNode.attributedText = NSAttributedString(
            string: profile.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: theme.white,
                .paragraphStyle: centeredParagraphStyle(),
            ])
        containerNode.addSubnode(nameNode)

        messageButton.backgroundColor = UIColor(hex: 0x5e65de)
        messageButton.setTitle(
            L(L10n.QRScanner.message), with: .systemFont(ofSize: 16, weight: .bold),
            with: .white, for: .normal)
        messageButton.cornerRadius = 24
        messageButton.style.height = ASDimensionMake(48)
        messageButton.addTarget(
            self, action: #selector(messageTapped), forControlEvents: .touchUpInside)
        containerNode.addSubnode(messageButton)

        closeButton.backgroundColor = .mezonPrimary
        closeButton.setTitle(
            L(L10n.QRScanner.noThanks), with: .systemFont(ofSize: 16, weight: .bold),
            with: .black, for: .normal)
        closeButton.cornerRadius = 24
        closeButton.style.height = ASDimensionMake(48)
        closeButton.addTarget(
            self, action: #selector(closeTapped), forControlEvents: .touchUpInside)
        containerNode.addSubnode(closeButton)
    }

    private func setupButton(
        _ button: ASButtonNode, title: String, bgColor: UIColor, textColor: UIColor
    ) {
        // Obsolete but kept for reference if needed, though removed from init
        button.setAttributedTitle(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: textColor,
                ]), for: .normal)
        button.backgroundColor = bgColor
        button.cornerRadius = 24
        button.style.height = ASDimensionMake(48)
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    @objc private func messageTapped() {
        onMessage?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.alignSelf = .center
        avatarNode.style.alignSelf = .center
        nameNode.style.alignSelf = .center
        
        messageButton.style.width = ASDimensionMakeWithFraction(1.0)
        closeButton.style.width = ASDimensionMakeWithFraction(1.0)

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 24,
            justifyContent: .center,
            alignItems: .stretch,
            children: [titleNode, avatarNode, nameNode, messageButton, closeButton]
        )

        let containerPadding = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24), child: contentStack)

        containerNode.style.width = ASDimensionMakeWithPoints(constrainedSize.max.width - 40)

        containerNode.layoutSpecBlock = { _, _ in return containerPadding }

        return ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: .minimumXY, child: containerNode)
    }
}
