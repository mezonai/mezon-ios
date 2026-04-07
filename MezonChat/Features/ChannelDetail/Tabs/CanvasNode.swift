import AsyncDisplayKit
import UIKit

@MainActor
final class CanvasNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var canvases: [Mezon_Api_ChannelCanvasItem] = []

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

        fetchCanvases()
    }

    private func fetchCanvases() {
        Task {
            do {
                let token = await context.getToken() ?? ""
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listChannelCanvases(
                    clanId: targetClanId,
                    channelId: channelId,
                    token: token
                )
                self.canvases = res.channelCanvases
                await self.tableNode.reloadData()
            } catch {
                AppLogger.network.error("Fetch canvases failed: \(error)")
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASWrapperLayoutSpec(layoutElement: tableNode)
    }
}

extension CanvasNode: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return canvases.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        let canvas = canvases[indexPath.row]
        return {
            return CanvasCellNode(canvas: canvas)
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
    }
}

private final class CanvasCellNode: ASCellNode {
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let copyLinkButton = ASButtonNode()
    private let canvas: Mezon_Api_ChannelCanvasItem

    init(canvas: Mezon_Api_ChannelCanvasItem) {
        self.canvas = canvas
        super.init()
        self.automaticallyManagesSubnodes = true

        iconNode.image = UIImage(systemName: "pencil.and.outline")?.withTintColor(
            UIColor.theme.textStrong, renderingMode: .alwaysOriginal)
        iconNode.style.preferredSize = CGSize(width: 24, height: 24)

        titleNode.attributedText = NSAttributedString(
            string: canvas.title.isEmpty ? L(L10n.ChannelDetail.untitledCanvas) : canvas.title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .medium),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )

        copyLinkButton.setTitle(
            L(L10n.ChannelAction.copyLink), with: UIFont.systemFont(ofSize: 12.sf, weight: .medium),
            with: UIColor.theme.textLink, for: .normal)
        copyLinkButton.backgroundColor = UIColor.theme.secondary
        copyLinkButton.cornerRadius = 6
        copyLinkButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        copyLinkButton.addTarget(
            self, action: #selector(copyLinkTapped), forControlEvents: .touchUpInside)
    }

    @objc private func copyLinkTapped() {
        UIPasteboard.general.string = canvas.title
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let leftStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, titleNode]
        )
        leftStack.style.flexShrink = 1
        leftStack.style.flexGrow = 1

        let rowStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .spaceBetween,
            alignItems: .center,
            children: [leftStack, copyLinkButton]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16), child: rowStack)
    }
}
