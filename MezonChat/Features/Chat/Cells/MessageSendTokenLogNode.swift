import AsyncDisplayKit
import UIKit

final class MessageSendTokenLogNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let iconBgNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let detailNode = ASTextNode2()
    private let separatorNode = ASDisplayNode()
    private let buttonNode = ASButtonNode()

    private var cachedTitleSize: CGSize = .zero
    private var cachedDetailSize: CGSize = .zero
    private var cachedButtonSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

    private static let containerPadding: CGFloat = 12
    private static let iconBoxSize: CGFloat = 40
    private static let iconImageSize: CGFloat = 22
    private static let iconGap: CGFloat = 8
    private static let separatorHeight: CGFloat = 1
    private static let titleDetailSpacing: CGFloat = 4
    private static let aboveSeparatorSpacing: CGFloat = 10
    private static let belowSeparatorSpacing: CGFloat = 10

    var onTransactionTapped: (() -> Void)?

    func configure(messageContent: String) {
        let t = UIColor.theme

        containerNode.backgroundColor = t.border
        containerNode.cornerRadius = 12
        containerNode.clipsToBounds = true

        iconBgNode.backgroundColor = UIColor.systemGreen
        iconBgNode.cornerRadius = Self.iconBoxSize / 2
        iconBgNode.clipsToBounds = true

        let symbol = UIImage.mezonSystemImage("arrow.left.arrow.right")?
            .mezonWithConfiguration(MezonSymbolConfiguration(pointSize: Self.iconImageSize, weight: .semibold))?
            .withRenderingMode(.alwaysTemplate)
        iconNode.image = symbol
        iconNode.tintColor = .white
        iconNode.contentMode = .scaleAspectFit

        let parts = messageContent.components(separatedBy: " | ")
        let title = parts.first ?? messageContent
        let description = parts.count > 1
            ? parts.dropFirst().joined(separator: " | ")
            : ""

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                .foregroundColor: t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 2

        let detailLabelString = "\(L(L10n.Common.detail)): "
        let detailString = NSMutableAttributedString(
            string: detailLabelString,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                .foregroundColor: t.textRoleLink,
            ]
        )
        if !description.isEmpty {
            detailString.append(NSAttributedString(
                string: description,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.text,
                ]
            ))
        }
        detailNode.attributedText = detailString
        detailNode.maximumNumberOfLines = 0

        separatorNode.backgroundColor = t.borderDim

        buttonNode.setTitle(
            L(L10n.Profile.mezonTransfer),
            with: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
            with: t.textRoleLink,
            for: .normal
        )
        buttonNode.contentHorizontalAlignment = .middle
        buttonNode.addTarget(self, action: #selector(transactionTapped), forControlEvents: .touchUpInside)

        addSubnode(containerNode)
        containerNode.addSubnode(iconBgNode)
        iconBgNode.addSubnode(iconNode)
        containerNode.addSubnode(titleNode)
        containerNode.addSubnode(detailNode)
        containerNode.addSubnode(separatorNode)
        containerNode.addSubnode(buttonNode)
    }

    @objc private func transactionTapped() {
        onTransactionTapped?()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let pad = Self.containerPadding
        let trailingMarginInsideBubble: CGFloat = 60
        let availableWidth = max(maxWidth - trailingMarginInsideBubble, 200)
        let contentWidth = availableWidth - pad * 2

        let textColumnWidth = max(contentWidth - Self.iconBoxSize - Self.iconGap, 1)
        cachedTitleSize = titleNode.measure(CGSize(width: textColumnWidth, height: .greatestFiniteMagnitude))
        cachedDetailSize = detailNode.measure(CGSize(width: textColumnWidth, height: .greatestFiniteMagnitude))

        let textColumnHeight = cachedTitleSize.height + Self.titleDetailSpacing + cachedDetailSize.height
        let topRowHeight = max(textColumnHeight, Self.iconBoxSize)

        cachedButtonSize = buttonNode.calculateSizeThatFits(CGSize(width: contentWidth, height: 30))

        let totalH = pad
            + topRowHeight
            + Self.aboveSeparatorSpacing
            + Self.separatorHeight
            + Self.belowSeparatorSpacing
            + max(cachedButtonSize.height, 22.sh)
            + pad

        cachedTotalSize = CGSize(width: availableWidth, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let pad = Self.containerPadding
        let width = bounds.width
        let contentWidth = width - pad * 2

        containerNode.frame = bounds

        var y: CGFloat = pad

        let textColumnHeight = cachedTitleSize.height + Self.titleDetailSpacing + cachedDetailSize.height
        let topRowHeight = max(textColumnHeight, Self.iconBoxSize)

        iconBgNode.frame = CGRect(
            x: pad,
            y: y + (topRowHeight - Self.iconBoxSize) / 2,
            width: Self.iconBoxSize,
            height: Self.iconBoxSize
        )
        iconNode.frame = CGRect(
            x: (Self.iconBoxSize - Self.iconImageSize) / 2,
            y: (Self.iconBoxSize - Self.iconImageSize) / 2,
            width: Self.iconImageSize,
            height: Self.iconImageSize
        )

        let textX = pad + Self.iconBoxSize + Self.iconGap
        let textWidth = max(contentWidth - Self.iconBoxSize - Self.iconGap, 1)
        let textColumnY = y + (topRowHeight - textColumnHeight) / 2

        titleNode.frame = CGRect(x: textX, y: textColumnY, width: textWidth, height: cachedTitleSize.height)
        detailNode.frame = CGRect(
            x: textX,
            y: textColumnY + cachedTitleSize.height + Self.titleDetailSpacing,
            width: textWidth,
            height: cachedDetailSize.height
        )

        y += topRowHeight + Self.aboveSeparatorSpacing
        separatorNode.frame = CGRect(x: pad, y: y, width: contentWidth, height: Self.separatorHeight)
        y += Self.separatorHeight + Self.belowSeparatorSpacing

        let btnH = max(cachedButtonSize.height, 22.sh)
        buttonNode.frame = CGRect(x: pad, y: y, width: contentWidth, height: btnH)
    }
}
