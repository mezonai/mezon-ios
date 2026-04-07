import AsyncDisplayKit
import UIKit

@MainActor
final class ChannelDetailActionButtonsNode: ASDisplayNode {

    private let searchButtonNode = ASButtonNode()
    private let threadsButtonNode = ASButtonNode()
    private let muteButtonNode = ASButtonNode()
    private let settingsButtonNode = ASButtonNode()

    private let searchLabel = ASTextNode2()
    private let threadsLabel = ASTextNode2()
    private let muteLabel = ASTextNode2()
    private let settingsLabel = ASTextNode2()

    private let showSearch: Bool
    private let showThreads: Bool
    private let showMute: Bool
    private let showSettings: Bool

    var onSettingsTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onThreadsTapped: (() -> Void)?

    init(channel: Mezon_Api_ChannelDescription, context: AccountContext) {
        let dm = MezonConstants.ChannelType.dm.rawValue
        let group = MezonConstants.ChannelType.group.rawValue
        let channelType = MezonConstants.ChannelType.channel.rawValue
        let isDMOrGroup = channel.type == dm || channel.type == group
        let myId = context.currentUser.flatMap { Int64($0.id) }
        let isSelfDM = channel.type == dm && channel.userIds.first == myId

        if channel.clanID == 0 {
            self.showSearch = true
            self.showThreads = false
            self.showSettings = false
            self.showMute = !isSelfDM
        } else {
            self.showSearch = true
            self.showThreads = channel.type == channelType
            self.showMute = !isSelfDM
            self.showSettings = !isDMOrGroup
        }

        super.init()
        automaticallyManagesSubnodes = true

        setupButton(
            searchButtonNode, icon: "magnifyingglass", label: searchLabel,
            text: L(L10n.Common.search))
        setupButton(
            threadsButtonNode, icon: "text.bubble", label: threadsLabel,
            text: L(L10n.Channel.thread))
        setupButton(
            muteButtonNode, icon: "bell.slash", label: muteLabel, text: L(L10n.ChannelAction.mute))
        setupButton(
            settingsButtonNode, icon: "gearshape", label: settingsLabel,
            text: L(L10n.Common.settings))

        threadsButtonNode.isHidden = !showThreads
        threadsLabel.isHidden = !showThreads
        muteButtonNode.isHidden = !showMute
        muteLabel.isHidden = !showMute
        settingsButtonNode.isHidden = !showSettings
        settingsLabel.isHidden = !showSettings

        settingsButtonNode.addTarget(
            self, action: #selector(settingsPressed), forControlEvents: .touchUpInside)
        searchButtonNode.addTarget(
            self, action: #selector(searchPressed), forControlEvents: .touchUpInside)
        threadsButtonNode.addTarget(
            self, action: #selector(threadsPressed), forControlEvents: .touchUpInside)
    }

    @objc private func searchPressed() {
        onSearchTapped?()
    }

    @objc private func threadsPressed() {
        onThreadsTapped?()
    }

    @objc private func settingsPressed() {
        onSettingsTapped?()
    }

    private func setupButton(_ button: ASButtonNode, icon: String, label: ASTextNode2, text: String)
    {
        let t = UIColor.theme
        let size: CGFloat = 52.sw
        button.style.preferredSize = CGSize(width: size, height: size)
        button.cornerRadius = size / 2
        button.backgroundColor = t.secondary

        button.setImage(
            UIImage(systemName: icon)?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            )
            .withTintColor(t.textStrong, renderingMode: .alwaysOriginal),
            for: .normal
        )

        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        var children: [ASLayoutElement] = []

        if showSearch {
            children.append(
                ASStackLayoutSpec(
                    direction: .vertical,
                    spacing: 12.sw,
                    justifyContent: .center,
                    alignItems: .center,
                    children: [searchButtonNode, searchLabel]
                ))
        }
        if showThreads {
            children.append(
                ASStackLayoutSpec(
                    direction: .vertical,
                    spacing: 12.sw,
                    justifyContent: .center,
                    alignItems: .center,
                    children: [threadsButtonNode, threadsLabel]
                ))
        }
        if showMute {
            children.append(
                ASStackLayoutSpec(
                    direction: .vertical,
                    spacing: 12.sw,
                    justifyContent: .center,
                    alignItems: .center,
                    children: [muteButtonNode, muteLabel]
                ))
        }
        if showSettings {
            children.append(
                ASStackLayoutSpec(
                    direction: .vertical,
                    spacing: 12.sw,
                    justifyContent: .center,
                    alignItems: .center,
                    children: [settingsButtonNode, settingsLabel]
                ))
        }

        let mainStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 30.sw,
            justifyContent: .center,
            alignItems: .center,
            children: children
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 20.sf, left: 0, bottom: 0, right: 0),
            child: mainStack
        )
    }

    func applyTheme() {
        let t = UIColor.theme
        let pairs: [(ASButtonNode, ASTextNode2, String)] = [
            (searchButtonNode, searchLabel, "magnifyingglass"),
            (threadsButtonNode, threadsLabel, "text.bubble"),
            (muteButtonNode, muteLabel, "bell.slash"),
            (settingsButtonNode, settingsLabel, "gearshape"),
        ]
        for (button, label, iconName) in pairs {
            button.backgroundColor = t.secondary
            button.setImage(
                UIImage(systemName: iconName)?.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
                )
                .withTintColor(t.textStrong, renderingMode: .alwaysOriginal),
                for: .normal
            )
            if let text = label.attributedText?.string {
                label.attributedText = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 13.sf, weight: .semibold),
                        .foregroundColor: t.textStrong,
                    ]
                )
            }
        }
    }
}
