import AsyncDisplayKit
import UIKit

final class MessageTopicNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let viewTopicLabel = ASTextNode2()
    private let repliesLabel = ASTextNode2()
    private let chevronNode = ASImageNode()

    private var cachedTotalSize: CGSize = .zero

    var onTapped: (() -> Void)?

    override init() {
        super.init()
        addSubnode(containerNode)
        containerNode.addSubnode(viewTopicLabel)
        containerNode.addSubnode(repliesLabel)
        containerNode.addSubnode(chevronNode)
    }

    func configure(topicData: TopicData) {
        let t = UIColor.theme

        containerNode.backgroundColor = t.border
        containerNode.cornerRadius = 6
        containerNode.clipsToBounds = true

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

        chevronNode.image = UIImage.mezonSystemImage("chevron.right", withConfiguration: MezonSymbolConfiguration(pointSize: 10.sf, weight: .semibold))
        chevronNode.tintColor = t.textDisabled
        chevronNode.contentMode = .scaleAspectFit
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

        let sView = viewTopicLabel.measure(constraintSize)
        let sReplies = repliesLabel.measure(constraintSize)

        let contentW = sView.width + spacing + sReplies.width + spacing + chevronSize
        let totalW = min(contentW + padH * 2, maxWidth)
        let rowH = max(sView.height, sReplies.height)
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

        let sView = viewTopicLabel.calculatedSize
        viewTopicLabel.frame = CGRect(x: x, y: padV + (rowH - sView.height) / 2, width: sView.width, height: sView.height)
        x += sView.width + spacing

        let sReplies = repliesLabel.calculatedSize
        repliesLabel.frame = CGRect(x: x, y: padV + (rowH - sReplies.height) / 2, width: sReplies.width, height: sReplies.height)
        x += sReplies.width + spacing

        chevronNode.frame = CGRect(x: x, y: padV + (rowH - chevronSz) / 2, width: chevronSz, height: chevronSz)
    }
}
