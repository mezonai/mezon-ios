import AsyncDisplayKit

extension ASDisplayNode {
    func measure(_ constrainedSize: CGSize) -> CGSize {
        let sizeRange = ASSizeRange(
            min: CGSize(width: 0, height: 0),
            max: constrainedSize
        )
        return layoutThatFits(sizeRange).size
    }
}
