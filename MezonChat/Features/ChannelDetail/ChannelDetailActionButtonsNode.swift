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

    var onSettingsTapped: (() -> Void)?

    override init() {
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

        settingsButtonNode.addTarget(
            self, action: #selector(settingsPressed), forControlEvents: .touchUpInside)
    }

    @objc private func settingsPressed() {
        onSettingsTapped?()
    }

    private func setupButton(_ button: ASButtonNode, icon: String, label: ASTextNode2, text: String)
    {
        let size: CGFloat = 58.sw
        button.style.preferredSize = CGSize(width: size, height: size)
        button.cornerRadius = size / 2
        button.backgroundColor = .white

        button.shadowColor = UIColor.black.cgColor
        button.shadowOffset = CGSize(width: 0, height: 2)
        button.shadowRadius = 6
        button.shadowOpacity = 0.08

        button.setImage(
            UIImage(systemName: icon)?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            )
            .withTintColor(UIColor.theme.textStrong, renderingMode: .alwaysOriginal),
            for: .normal
        )

        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let searchStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8.sw,
            justifyContent: .center,
            alignItems: .center,
            children: [searchButtonNode, searchLabel]
        )

        let threadsStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8.sw,
            justifyContent: .center,
            alignItems: .center,
            children: [threadsButtonNode, threadsLabel]
        )

        let muteStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8.sw,
            justifyContent: .center,
            alignItems: .center,
            children: [muteButtonNode, muteLabel]
        )

        let settingsStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8.sw,
            justifyContent: .center,
            alignItems: .center,
            children: [settingsButtonNode, settingsLabel]
        )

        let mainStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 32.sw,
            justifyContent: .center,
            alignItems: .center,
            children: [searchStack, threadsStack, muteStack, settingsStack]
        )

        return mainStack
    }
}
