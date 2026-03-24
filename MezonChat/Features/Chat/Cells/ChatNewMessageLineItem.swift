import AsyncDisplayKit
import UIKit

final class ChatNewMessageLineItem: ListViewItem {

    var selectable: Bool { false }
    var approximateHeight: CGFloat { 28 }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatNewMessageLineNode()
            let layout = node.asyncLayout()
            let (nodeLayout, apply) = layout(params)

            node.contentSize = nodeLayout.contentSize
            node.insets = nodeLayout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let itemNode = node() as? ChatNewMessageLineNode else { return }
            let layout = itemNode.asyncLayout()
            async {
                let (nodeLayout, apply) = layout(params)
                Queue.mainQueue().async {
                    completion(nodeLayout, { _ in apply() })
                }
            }
        }
    }

    func selected(listView: ListView) {}
}

final class ChatNewMessageLineNode: ListViewItemNode {

    private let leftLine = ASDisplayNode()
    private let rightLine = ASDisplayNode()
    private let labelNode = ASTextNode2()

    private static let lineHeight: CGFloat = 1
    private static let totalHeight: CGFloat = 28
    private static let horizontalPadding: CGFloat = 12
    private static let labelSpacing: CGFloat = 8

    init() {
        super.init(layerBacked: false, rotated: true)
        self.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)

        leftLine.backgroundColor = UIColor.systemRed
        rightLine.backgroundColor = UIColor.systemRed

        labelNode.attributedText = NSAttributedString(
            string: "NEW MESSAGES",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.systemRed,
            ]
        )

        addSubnode(leftLine)
        addSubnode(labelNode)
        addSubnode(rightLine)
    }

    func asyncLayout() -> (ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        let labelNode = self.labelNode

        return { [weak self] params in
            let width = params.width
            let height = ChatNewMessageLineNode.totalHeight

            let labelSize = labelNode.measure(CGSize(width: width, height: height))

            let nodeLayout = ListViewItemNodeLayout(
                contentSize: CGSize(width: width, height: height),
                insets: UIEdgeInsets()
            )

            return (nodeLayout, {
                guard let self else { return }
                let hp = ChatNewMessageLineNode.horizontalPadding
                let sp = ChatNewMessageLineNode.labelSpacing
                let lh = ChatNewMessageLineNode.lineHeight
                let centerY = height / 2

                let labelX = (width - labelSize.width) / 2
                let labelY = (height - labelSize.height) / 2
                self.labelNode.frame = CGRect(x: labelX, y: labelY, width: labelSize.width, height: labelSize.height)

                let leftLineWidth = labelX - sp - hp
                self.leftLine.frame = CGRect(x: hp, y: centerY - lh / 2, width: max(leftLineWidth, 0), height: lh)

                let rightLineX = labelX + labelSize.width + sp
                let rightLineWidth = width - rightLineX - hp
                self.rightLine.frame = CGRect(x: rightLineX, y: centerY - lh / 2, width: max(rightLineWidth, 0), height: lh)

                self.leftLine.alpha = 0.5
                self.rightLine.alpha = 0.5
            })
        }
    }
}
