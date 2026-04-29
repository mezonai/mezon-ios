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
            searchButtonNode, icon: "magnifyingglass", assetName: "Channel/Search", label: searchLabel,
            text: L(L10n.Common.search))
        setupButton(
            threadsButtonNode, icon: "text.bubble", assetName: "Channel/channelThread", label: threadsLabel,
            text: L(L10n.Channel.thread))
        setupButton(
            muteButtonNode, icon: "bell.fill", assetName: "ClanSetting/BellIcon", label: muteLabel,
            text: L(L10n.ChannelAction.mute))
        setupButton(
            settingsButtonNode, icon: "gearshape.fill", assetName: "Profile/SettingIcon", label: settingsLabel,
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

    private func setupButton(
        _ button: ASButtonNode,
        icon: String,
        assetName: String?,
        label: ASTextNode2,
        text: String
    )
    {
        let t = UIColor.theme
        let size: CGFloat = 52.sw
        button.style.preferredSize = CGSize(width: size, height: size)
        button.cornerRadius = size / 2
        button.backgroundColor = t.secondary
        button.imageNode.contentMode = .scaleAspectFit
        button.imageNode.style.preferredSize = CGSize(width: 24.sw, height: 24.sw)

        button.setImage(
            actionIconImage(
                assetName: assetName,
                fallbackSystemName: icon,
                fallbackTintColor: t.textStrong
            ),
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
        let pairs: [(ASButtonNode, ASTextNode2, String, String?)] = [
            (searchButtonNode, searchLabel, "magnifyingglass", "Channel/Search"),
            (threadsButtonNode, threadsLabel, "text.bubble", "Channel/channelThread"),
            (muteButtonNode, muteLabel, "bell.fill", "ClanSetting/BellIcon"),
            (settingsButtonNode, settingsLabel, "gearshape.fill", "Profile/SettingIcon"),
        ]
        for (button, label, iconName, assetName) in pairs {
            button.backgroundColor = t.secondary
            button.imageNode.contentMode = .scaleAspectFit
            button.imageNode.style.preferredSize = CGSize(width: 24.sw, height: 24.sw)
            button.setImage(
                actionIconImage(
                    assetName: assetName,
                    fallbackSystemName: iconName,
                    fallbackTintColor: t.textStrong
                ),
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

    private func actionIconImage(assetName: String?, fallbackSystemName: String, fallbackTintColor: UIColor)
        -> UIImage?
    {
        if let assetName, let assetImage = UIImage(named: assetName) {
            if assetName.hasPrefix("ChannelSetting/") {
                return assetImage.withRenderingMode(.alwaysOriginal)
            }
            return resizedOriginalIcon(assetImage)
        }
        let baseConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let symbolImage = UIImage(systemName: fallbackSystemName, withConfiguration: baseConfig)
        return symbolImage?.withTintColor(fallbackTintColor, renderingMode: .alwaysOriginal)
    }

    private func resizedOriginalIcon(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 20.sw, height: 20.sw)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let sourceSize = image.size
        let scale = min(
            targetSize.width / max(sourceSize.width, 1),
            targetSize.height / max(sourceSize.height, 1)
        )
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )
        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }.withRenderingMode(.alwaysOriginal)
    }
}
