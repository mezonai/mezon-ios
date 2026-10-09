import AsyncDisplayKit
import UIKit

final class BuzzBadgeNode: ASDisplayNode {
    private let textNode = ASTextNode2()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = UIColor(red: 234 / 255, green: 36 / 255, blue: 32 / 255, alpha: 1)
        cornerRadius = 4.swh
        clipsToBounds = true
        textNode.maximumNumberOfLines = 1
        textNode.attributedText = NSAttributedString(string: "Buzz!!", attributes: [
            .font: UIFont.systemFont(ofSize: 12.sf, weight: .bold),
            .foregroundColor: UIColor.white,
        ])
        accessibilityLabel = "Buzz!!"
        isAccessibilityElement = true
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASInsetLayoutSpec(insets: UIEdgeInsets(top: 2.swh, left: 4.swh, bottom: 2.swh, right: 4.swh),
                          child: textNode)
    }
}
