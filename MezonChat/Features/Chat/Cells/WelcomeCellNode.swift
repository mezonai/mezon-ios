import AsyncDisplayKit
import UIKit

final class WelcomeCellNode: ASCellNode {

    private let iconContainerNode = ASDisplayNode()
    private let iconImageNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()

    private static let iconSize: CGFloat = 70

    init(channelLabel: String, channelType: Int32, isPrivate: Bool, isAgeRestricted: Bool) {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        let t = UIColor.theme
        let name = channelLabel

        iconContainerNode.backgroundColor = t.secondaryLight
        iconContainerNode.cornerRadius = Self.iconSize / 2
        iconContainerNode.clipsToBounds = true

        let iconName: String
        switch channelType {
        case 10: iconName = "Channel/channelVoice"
        case 4: iconName = "Channel/ChevronRight"
        case 6: iconName = "Channel/channelStream"
        case 8: iconName = "Channel/channelApp"
        case 7:
            if isPrivate {
                iconName = "Channel/channelThreadPrivate"
            } else {
                iconName = "Channel/channelThread"
            }
        case 1:
            if isPrivate {
                iconName = "Channel/channelPrivate"
            } else if isAgeRestricted {
                iconName = "Channel/channelWarning"
            } else {
                iconName = "Channel/channel"
            }
        default: iconName = "Channel/channel"
        }
        let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
        iconImageNode.image = image?.withRenderingMode(.alwaysTemplate)
        iconImageNode.tintColor = t.textStrong
        iconImageNode.contentMode = .scaleAspectFit

        titleNode.attributedText = NSAttributedString(
            string: "Welcome to \(name)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 22.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 0

        subtitleNode.attributedText = NSAttributedString(
            string: "This is the start of the \(name) channel",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.text,
            ]
        )
        subtitleNode.maximumNumberOfLines = 0
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let iconSz = Self.iconSize
        iconImageNode.style.preferredSize = CGSize(width: 36, height: 36)

        let iconCenter = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: [],
            child: iconImageNode
        )
        iconCenter.style.preferredSize = CGSize(width: iconSz, height: iconSz)

        iconContainerNode.style.preferredSize = CGSize(width: iconSz, height: iconSz)
        let iconSpec = ASBackgroundLayoutSpec(child: iconCenter, background: iconContainerNode)

        let column = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 10.sh,
            justifyContent: .start,
            alignItems: .start,
            children: [iconSpec, titleNode, subtitleNode]
        )

        let insets = UIEdgeInsets(top: 30.sh, left: 10.sw, bottom: 30.sh, right: 10.sw)
        return ASInsetLayoutSpec(insets: insets, child: column)
    }
}
