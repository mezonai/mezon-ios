import AsyncDisplayKit
import UIKit

final class WelcomeCellNode: ASDisplayNode {

    private let iconContainerNode = ASDisplayNode()
    private let iconImageNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()

    private static let iconSize: CGFloat = 70
    private static let iconImageSize: CGFloat = 36

    private var cachedTitleSize: CGSize = .zero
    private var cachedSubtitleSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

    init(channelLabel: String, channelType: Int32, isPrivate: Bool, isAgeRestricted: Bool) {
        super.init()
        backgroundColor = .clear

        let t = UIColor.theme
        let name = channelLabel

        iconContainerNode.backgroundColor = t.secondaryLight
        iconContainerNode.cornerRadius = Self.iconSize / 2
        iconContainerNode.clipsToBounds = true
        addSubnode(iconContainerNode)

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
        iconContainerNode.addSubnode(iconImageNode)

        titleNode.attributedText = NSAttributedString(
            string: "Welcome to \(name)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 22.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 0
        addSubnode(titleNode)

        subtitleNode.attributedText = NSAttributedString(
            string: "This is the start of the \(name) channel",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.text,
            ]
        )
        subtitleNode.maximumNumberOfLines = 0
        addSubnode(subtitleNode)
    }

    func measureSize(width: CGFloat) -> CGSize {
        let insetH: CGFloat = 10.sw
        let insetV: CGFloat = 30.sh
        let spacing: CGFloat = 10.sh
        let contentW = width - insetH * 2

        cachedTitleSize = titleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
        cachedSubtitleSize = subtitleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))

        let totalH = insetV + Self.iconSize + spacing + cachedTitleSize.height + spacing + cachedSubtitleSize.height + insetV
        cachedTotalSize = CGSize(width: width, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let insetH: CGFloat = 10.sw
        let insetV: CGFloat = 30.sh
        let spacing: CGFloat = 10.sh
        let iconSz = Self.iconSize
        let imgSz = Self.iconImageSize
        var y = insetV

        iconContainerNode.frame = CGRect(x: insetH, y: y, width: iconSz, height: iconSz)
        iconImageNode.frame = CGRect(
            x: (iconSz - imgSz) / 2,
            y: (iconSz - imgSz) / 2,
            width: imgSz, height: imgSz
        )
        y += iconSz + spacing

        titleNode.frame = CGRect(x: insetH, y: y, width: cachedTitleSize.width, height: cachedTitleSize.height)
        y += cachedTitleSize.height + spacing

        subtitleNode.frame = CGRect(x: insetH, y: y, width: cachedSubtitleSize.width, height: cachedSubtitleSize.height)
    }
}
