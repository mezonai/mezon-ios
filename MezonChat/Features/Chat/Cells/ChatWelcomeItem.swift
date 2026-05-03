import AsyncDisplayKit
import UIKit

final class ChatWelcomeItem: ListViewItem {

    let channelLabel: String
    let channelType: Int32
    let isPrivate: Bool
    let isAgeRestricted: Bool
    let isDM: Bool
    let dmPeerUsername: String
    let dmPeerDisplayName: String
    let dmAvatarURL: String
    let dmGroupAvatarURL: String

    var selectable: Bool { false }
    var approximateHeight: CGFloat { 128 }

    init(
        channelLabel: String,
        channelType: Int32,
        isPrivate: Bool,
        isAgeRestricted: Bool,
        isDM: Bool,
        dmPeerUsername: String,
        dmPeerDisplayName: String,
        dmAvatarURL: String,
        dmGroupAvatarURL: String
    ) {
        self.channelLabel = channelLabel
        self.channelType = channelType
        self.isPrivate = isPrivate
        self.isAgeRestricted = isAgeRestricted
        self.isDM = isDM
        self.dmPeerUsername = dmPeerUsername
        self.dmPeerDisplayName = dmPeerDisplayName
        self.dmAvatarURL = dmAvatarURL
        self.dmGroupAvatarURL = dmGroupAvatarURL
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatWelcomeItemNode()
            let layout = node.asyncLayout()
            let (nodeLayout, apply) = layout(self, params)

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
            guard let itemNode = node() as? ChatWelcomeItemNode else { return }
            let layout = itemNode.asyncLayout()
            async {
                let (nodeLayout, apply) = layout(self, params)
                Queue.mainQueue().async {
                    completion(nodeLayout, { _ in apply() })
                }
            }
        }
    }

    func selected(listView: ListView) {}
}

final class ChatWelcomeItemNode: ListViewItemNode {

    private var welcomeNode: WelcomeCellNode?

    init() {
        super.init(layerBacked: false, rotated: true)
        self.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
    }

    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) {
        guard let welcomeItem = item as? ChatWelcomeItem else { return }
        let layout = asyncLayout()
        let (nodeLayout, apply) = layout(welcomeItem, params)
        self.contentSize = nodeLayout.contentSize
        self.insets = nodeLayout.insets
        apply()
    }

    func asyncLayout() -> (ChatWelcomeItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params in
            let width = params.width
            let node = WelcomeCellNode(
                channelLabel: item.channelLabel,
                channelType: item.channelType,
                isPrivate: item.isPrivate,
                isAgeRestricted: item.isAgeRestricted,
                isDM: item.isDM,
                dmPeerUsername: item.dmPeerUsername,
                dmPeerDisplayName: item.dmPeerDisplayName,
                dmAvatarURL: item.dmAvatarURL,
                dmGroupAvatarURL: item.dmGroupAvatarURL
            )

            let measuredSize = node.measureSize(width: width)

            let nodeLayout = ListViewItemNodeLayout(
                contentSize: CGSize(width: width, height: measuredSize.height),
                insets: UIEdgeInsets()
            )

            return (nodeLayout, {
                guard let self else { return }
                self.welcomeNode?.removeFromSupernode()
                self.addSubnode(node)
                self.welcomeNode = node
                node.frame = CGRect(origin: .zero, size: measuredSize)
            })
        }
    }
}
