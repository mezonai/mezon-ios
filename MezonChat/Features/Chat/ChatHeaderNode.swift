import AsyncDisplayKit
import UIKit

final class ChatHeaderNode: ASDisplayNode {

    private let backButtonNode = ASButtonNode()
    private let channelIconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()
    private let searchButtonNode = ASButtonNode()
    private let separatorNode = ASDisplayNode()

    var onBackTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = true

        backButtonNode.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        backButtonNode.addTarget(self, action: #selector(backPressed), forControlEvents: .touchUpInside)

        searchButtonNode.setImage(
            UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        searchButtonNode.addTarget(self, action: #selector(searchPressed), forControlEvents: .touchUpInside)

        channelIconNode.contentMode = .scaleAspectFit

        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail

        subtitleNode.maximumNumberOfLines = 1
        subtitleNode.truncationMode = .byTruncatingTail
    }

    func configure(
        title: String, subtitle: String? = nil, channelType: Int32, isPrivate: Bool,
        isAgeRestricted: Bool
    ) {
        let t = UIColor.theme

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )

        let isSubtitleVisible: Bool
        if let subtitle = subtitle, !subtitle.isEmpty {
            subtitleNode.attributedText = NSAttributedString(
                string: subtitle,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                    .foregroundColor: t.textStrong.withAlphaComponent(0.8),
                ]
            )
            subtitleNode.isHidden = false
            isSubtitleVisible = true
        } else {
            subtitleNode.attributedText = nil
            subtitleNode.isHidden = true
            isSubtitleVisible = false
        }

        let iconName: String
        switch channelType {
        case 10: iconName = "Channel/channelVoice"
        case 4:  iconName = "Channel/ChevronRight"
        case 6:  iconName = "Channel/channelStream"
        case 8:  iconName = "Channel/channelApp"
        case 7:
            if isPrivate { iconName = "Channel/channelThreadPrivate" }
            else {iconName = "Channel/channelThread"}
        case 1:
            if isPrivate { iconName = "Channel/channelPrivate" }
            else if isAgeRestricted { iconName = "Channel/channelWarning" }
            else { iconName = "Channel/channel" }
        default: iconName = "Channel/channel"
        }
        let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
        channelIconNode.image = image?.withRenderingMode(.alwaysTemplate)
        channelIconNode.tintColor = t.textStrong

        self.setNeedsLayout()
    }

    func applyTheme() {
        let t = UIColor.theme
        backButtonNode.tintColor = t.textStrong
        searchButtonNode.tintColor = t.textStrong
        channelIconNode.tintColor = t.textStrong
        separatorNode.backgroundColor = t.border
        if let currentTitle = titleNode.attributedText {
            titleNode.attributedText = NSAttributedString(
                string: currentTitle.string,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16.sf, weight: .semibold),
                    .foregroundColor: t.textStrong,
                ]
            )
        }
        if let currentSubtitle = subtitleNode.attributedText {
            subtitleNode.attributedText = NSAttributedString(
                string: currentSubtitle.string,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                    .foregroundColor: t.textStrong.withAlphaComponent(0.6),
                ]
            )
        }
    }

    @objc private func backPressed() {
        onBackTapped?()
    }

    @objc private func searchPressed() {
        onSearchTapped?()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        backButtonNode.style.preferredSize = CGSize(width: 44, height: 44)
        channelIconNode.style.preferredSize = CGSize(width: 16.swh, height: 16.swh)
        searchButtonNode.style.preferredSize = CGSize(width: 44, height: 44)
        titleNode.style.flexShrink = 1
        subtitleNode.style.flexShrink = 1

        let titleStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .center,
            alignItems: .start,
            children: [titleNode, subtitleNode]
        )
        titleStack.style.flexShrink = 1
        titleStack.style.flexGrow = 1

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [backButtonNode, channelIconNode, titleStack, searchButtonNode]
        )

        let insets = UIEdgeInsets(top: 0, left: 12.sw, bottom: 0, right: 4.sw)
        let insetSpec = ASInsetLayoutSpec(insets: insets, child: row)
        insetSpec.style.height = ASDimensionMake(44)

        separatorNode.style.height = ASDimensionMake(0.5)
        separatorNode.style.alignSelf = .stretch

        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [insetSpec, separatorNode]
        )
    }
}
