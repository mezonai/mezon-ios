import AsyncDisplayKit
import UIKit

final class ChannelOnboardingBannerCellNode: ASCellNode {

    var onTap: (() -> Void)?

    private static let cardCornerRadius: CGFloat = 16.swh

    private let cardNode = ASDisplayNode()
    private let iconWrapNode = ASDisplayNode()
    private var gradientLayer: CAGradientLayer?
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let chevronNode = ASImageNode()

    init(title: String, subtitle: String) {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        cardNode.cornerRadius = Self.cardCornerRadius
        cardNode.clipsToBounds = true

        iconWrapNode.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.98, alpha: 1)
        iconWrapNode.cornerRadius = 15.swh
        iconWrapNode.style.preferredSize = CGSize(width: 30.swh, height: 30.swh)

        iconNode.image = Self.bannerIcon()
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 18.swh, height: 18.swh)

        titleNode.attributedText = Self.titleAttributes(title)
        subtitleNode.attributedText = Self.subtitleAttributes(subtitle)

        chevronNode.image = Self.chevronImage()
        chevronNode.contentMode = .scaleAspectFit
        chevronNode.style.preferredSize = CGSize(width: 14.swh, height: 14.swh)
    }

    override func didLoad() {
        super.didLoad()
        let gradient = makeGradientLayer()
        gradientLayer = gradient
        cardNode.view.layer.insertSublayer(gradient, at: 0)
        cardNode.view.layer.cornerRadius = Self.cardCornerRadius
        cardNode.view.clipsToBounds = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let iconCenter = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: [],
            child: iconNode
        )

        let textStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 2,
            justifyContent: .center,
            alignItems: .start,
            children: [titleNode, subtitleNode]
        )
        textStack.style.flexShrink = 1
        textStack.style.flexGrow = 1

        let contentStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [
                ASOverlayLayoutSpec(child: iconWrapNode, overlay: iconCenter),
                textStack,
            ]
        )
        contentStack.style.flexShrink = 1
        contentStack.style.flexGrow = 1

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8.sw,
            justifyContent: .spaceBetween,
            alignItems: .center,
            children: [contentStack, chevronNode]
        )

        let cardInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 14.sh, left: 16.sw, bottom: 14.sh, right: 16.sw),
            child: row
        )

        let cardBackground = ASBackgroundLayoutSpec(child: cardInset, background: cardNode)

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12.sh, left: 12.sw, bottom: 12.sh, right: 12.sw),
            child: cardBackground
        )
    }

    override func layout() {
        super.layout()
        guard let gradient = gradientLayer else { return }
        gradient.frame = cardNode.bounds
        gradient.cornerRadius = Self.cardCornerRadius
    }

    func applyTheme() {
        titleNode.attributedText = Self.titleAttributes(titleNode.attributedText?.string ?? "")
        subtitleNode.attributedText = Self.subtitleAttributes(subtitleNode.attributedText?.string ?? "")
        chevronNode.image = Self.chevronImage()
        guard let gradient = gradientLayer else { return }
        let theme = UIColor.theme
        gradient.colors = [
            theme.primary.cgColor,
            theme.primaryGradient.cgColor,
            theme.primaryGradient.cgColor,
        ]
    }

    @objc private func handleTap() {
        onTap?()
    }

    private func makeGradientLayer() -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.startPoint = CGPoint(x: 1, y: 0.5)
        gradient.endPoint = CGPoint(x: 0, y: 0.5)
        gradient.cornerRadius = Self.cardCornerRadius
        gradient.masksToBounds = true
        let theme = UIColor.theme
        gradient.colors = [
            theme.primary.cgColor,
            theme.primaryGradient.cgColor,
            theme.primaryGradient.cgColor,
        ]
        return gradient
    }

    private static func bannerIcon() -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 14.sf, weight: .semibold)
        if let image = UIImage(systemName: "sparkles", withConfiguration: config) {
            return image.withTintColor(.white, renderingMode: .alwaysOriginal)
        }
        return UIImage(systemName: "star.fill", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
    }

    private static func chevronImage() -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 12.sf, weight: .semibold)
        return UIImage(systemName: "chevron.right", withConfiguration: config)?
            .withTintColor(UIColor.theme.text, renderingMode: .alwaysOriginal)
    }

    private static func titleAttributes(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )
    }

    private static func subtitleAttributes(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .regular),
                .foregroundColor: UIColor.theme.text,
            ]
        )
    }
}
