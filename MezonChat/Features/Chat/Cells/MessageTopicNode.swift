import AsyncDisplayKit
import UIKit

final class MessageTopicNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let creatorLabel = ASTextNode2()
    private let viewTopicLabel = ASTextNode2()
    private let repliesLabel = ASTextNode2()
    private let chevronNode = ASImageNode()

    private var cachedTotalSize: CGSize = .zero

    var onTapped: (() -> Void)?

    func configure(topicData: TopicData) {
        let t = UIColor.theme

        containerNode.backgroundColor = t.secondary
        containerNode.cornerRadius = 6
        containerNode.clipsToBounds = true

        creatorLabel.attributedText = NSAttributedString(
            string: "Creator",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .medium),
                .foregroundColor: t.textLink,
            ]
        )
        creatorLabel.maximumNumberOfLines = 1

        viewTopicLabel.attributedText = NSAttributedString(
            string: "View Topic",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        viewTopicLabel.maximumNumberOfLines = 1

        let count = topicData.replyCount
        let countText = count > 99 ? "99+" : "\(count)"
        let replyWord = count > 1 ? "replies" : "reply"
        repliesLabel.attributedText = NSAttributedString(
            string: "\(countText) \(replyWord)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .medium),
                .foregroundColor: t.textLink,
            ]
        )
        repliesLabel.maximumNumberOfLines = 1

        chevronNode.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.sf, weight: .semibold))
        chevronNode.tintColor = t.textDisabled
        chevronNode.contentMode = .scaleAspectFit

        addSubnode(containerNode)
        containerNode.addSubnode(creatorLabel)
        containerNode.addSubnode(viewTopicLabel)
        containerNode.addSubnode(repliesLabel)
        containerNode.addSubnode(chevronNode)
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        containerNode.view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTapped?()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let padH: CGFloat = 10
        let padV: CGFloat = 8
        let spacing: CGFloat = 6
        let chevronSize: CGFloat = 12

        let maxTextW = maxWidth - padH * 2 - chevronSize - spacing
        let constraintSize = CGSize(width: maxTextW, height: 30)

        let s1 = creatorLabel.measure(constraintSize)
        let s2 = viewTopicLabel.measure(constraintSize)
        let s3 = repliesLabel.measure(constraintSize)

        let contentW = s1.width + spacing + s2.width + spacing + s3.width + spacing + chevronSize
        let totalW = min(contentW + padH * 2, maxWidth)
        let rowH = max(s1.height, max(s2.height, s3.height))
        let totalH = rowH + padV * 2

        cachedTotalSize = CGSize(width: totalW, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        containerNode.frame = CGRect(origin: .zero, size: cachedTotalSize)

        let padH: CGFloat = 10
        let padV: CGFloat = 8
        let spacing: CGFloat = 6
        let chevronSz: CGFloat = 12
        let rowH = cachedTotalSize.height - padV * 2

        var x = padH

        let s1 = creatorLabel.calculatedSize
        creatorLabel.frame = CGRect(x: x, y: padV + (rowH - s1.height) / 2, width: s1.width, height: s1.height)
        x += s1.width + spacing

        let s2 = viewTopicLabel.calculatedSize
        viewTopicLabel.frame = CGRect(x: x, y: padV + (rowH - s2.height) / 2, width: s2.width, height: s2.height)
        x += s2.width + spacing

        let s3 = repliesLabel.calculatedSize
        repliesLabel.frame = CGRect(x: x, y: padV + (rowH - s3.height) / 2, width: s3.width, height: s3.height)
        x += s3.width + spacing

        chevronNode.frame = CGRect(x: x, y: padV + (rowH - chevronSz) / 2, width: chevronSz, height: chevronSz)
    }
}
