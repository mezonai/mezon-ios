import AsyncDisplayKit
import UIKit

final class ChatHeaderNode: ASDisplayNode {

    private let backButtonNode = ASButtonNode()
    private let titleContainerNode = ASControlNode()
    private let channelIconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()
    private let callButtonNode = ASButtonNode()
    private let searchButtonNode = ASButtonNode()
    private let separatorNode = ASDisplayNode()

    private var isDM = false

    var statusBarClearance: CGFloat = 0 {
        didSet {
            if oldValue != statusBarClearance {
                setNeedsLayout()
            }
        }
    }

    var onBackTapped: (() -> Void)?
    var onHeaderTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onCallTapped: (() -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = true

        backButtonNode.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        backButtonNode.addTarget(self, action: #selector(backPressed), forControlEvents: .touchUpInside)

        titleContainerNode.automaticallyManagesSubnodes = true
        titleContainerNode.addTarget(self, action: #selector(headerPressed), forControlEvents: .touchUpInside)
        callButtonNode.setImage(
            UIImage(systemName: "phone.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        callButtonNode.addTarget(self, action: #selector(callPressed), forControlEvents: .touchUpInside)
        callButtonNode.isHidden = true

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

        titleContainerNode.addSubnode(channelIconNode)
        titleContainerNode.addSubnode(titleNode)
        titleContainerNode.addSubnode(subtitleNode)
    }

    func configure(
        title: String, subtitle: String? = nil, channelType: Int32, isPrivate: Bool,
        isAgeRestricted: Bool, isDM: Bool = false
    ) {
        let t = UIColor.theme

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
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

        if isDM {
            channelIconNode.isHidden = true
            callButtonNode.isHidden = false
        } else {
            channelIconNode.isHidden = false
            callButtonNode.isHidden = true
            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            channelIconNode.image = image?.withRenderingMode(.alwaysTemplate)
            channelIconNode.tintColor = t.textStrong
        }
        self.isDM = isDM

        self.setNeedsLayout()
    }

    func applyTheme() {
        let t = UIColor.theme
        backButtonNode.tintColor = t.textStrong
        callButtonNode.tintColor = t.textStrong
        searchButtonNode.tintColor = t.textStrong
        channelIconNode.tintColor = t.textStrong
        separatorNode.backgroundColor = t.border
        if let currentTitle = titleNode.attributedText {
            titleNode.attributedText = NSAttributedString(
                string: currentTitle.string,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
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

    @objc private func headerPressed() {
        onHeaderTapped?()
    }

    @objc private func searchPressed() {
        onSearchTapped?()
    }

    @objc private func callPressed() {
        onCallTapped?()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        backButtonNode.style.preferredSize = CGSize(width: 36, height: 36)
        channelIconNode.style.preferredSize = CGSize(width: 15.swh, height: 15.swh)
        callButtonNode.style.preferredSize = CGSize(width: 36, height: 36)
        searchButtonNode.style.preferredSize = CGSize(width: 36, height: 36)
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

        let titleRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8.sw,
            justifyContent: .start,
            alignItems: .center,
            children: channelIconNode.isHidden ? [titleStack] : [channelIconNode, titleStack]
        )
        titleContainerNode.layoutSpecBlock = { _, _ in
            return titleRow
        }
        titleContainerNode.style.flexShrink = 1
        titleContainerNode.style.flexGrow = 1

        var rowChildren: [ASLayoutElement] = [backButtonNode, titleContainerNode]
        if isDM && !callButtonNode.isHidden {
            rowChildren.append(callButtonNode)
        }
        rowChildren.append(searchButtonNode)

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8.sw,
            justifyContent: .start,
            alignItems: .center,
            children: rowChildren
        )

        let insets = UIEdgeInsets(top: 0, left: 10.sw, bottom: 0, right: 2.sw)
        let insetSpec = ASInsetLayoutSpec(insets: insets, child: row)
        insetSpec.style.height = ASDimensionMake(36)

        separatorNode.style.height = ASDimensionMake(0.5)
        separatorNode.style.alignSelf = .stretch

        let barStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [insetSpec, separatorNode]
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: statusBarClearance, left: 0, bottom: 0, right: 0),
            child: barStack
        )
    }
}
