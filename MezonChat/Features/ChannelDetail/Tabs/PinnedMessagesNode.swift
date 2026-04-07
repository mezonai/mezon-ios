import AsyncDisplayKit
import UIKit

@MainActor
final class PinnedMessagesNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var pinnedMessages: [Mezon_Api_PinMessage] = []
    
    private let tableNode: ASTableNode

    init(context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType
        
        self.tableNode = ASTableNode()
        
        super.init()
        self.automaticallyManagesSubnodes = true
        
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        
        fetchPins()
    }
    
    private func fetchPins() {
        Task {
            do {
                let token = await context.getToken() ?? ""
                let targetClanId = (channelType == MezonConstants.ChannelType.dm.rawValue || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listPinMessages(
                    clanId: targetClanId,
                    channelId: channelId,
                    token: token
                )
                self.pinnedMessages = res.pinMessagesList
                await self.tableNode.reloadData()
            } catch {
                AppLogger.network.error("Fetch pinned messages failed: \(error)")
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASWrapperLayoutSpec(layoutElement: tableNode)
    }
}

extension PinnedMessagesNode: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return pinnedMessages.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let pin = pinnedMessages[indexPath.row]
        return {
            return PinnedMessageCellNode(pin: pin)
        }
    }
}

private final class PinnedMessageCellNode: ASCellNode {
    private let avatarNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let contentNode = ASTextNode2()
    
    init(pin: Mezon_Api_PinMessage) {
        super.init()
        self.automaticallyManagesSubnodes = true
        
        avatarNode.style.preferredSize = CGSize(width: 32.sf, height: 32.sf)
        avatarNode.cornerRadius = 16.sf
        avatarNode.backgroundColor = UIColor.theme.secondary
        
        nameNode.attributedText = NSAttributedString(
            string: pin.username,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
                .foregroundColor: UIColor.theme.textStrong
            ]
        )
        
        contentNode.attributedText = NSAttributedString(
            string: pin.content,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textStrong
            ]
        )
        contentNode.maximumNumberOfLines = 2
    }
    
    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let textStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 4,
            justifyContent: .start,
            alignItems: .stretch,
            children: [nameNode, contentNode]
        )
        textStack.style.flexShrink = 1
        textStack.style.flexGrow = 1
        
        let rowStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarNode, textStack]
        )
        
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16), child: rowStack)
    }
}
