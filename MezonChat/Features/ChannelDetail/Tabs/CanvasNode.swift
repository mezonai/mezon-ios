import AsyncDisplayKit
import UIKit

@MainActor
final class CanvasNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var canvases: [Mezon_Api_ChannelCanvasItem] = []
    private var didLoadCanvases = false

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
        tableNode.view.backgroundColor = .clear
        tableNode.view.delaysContentTouches = false
    }

    func loadTabDataIfNeeded() {
        guard !didLoadCanvases else { return }
        didLoadCanvases = true
        fetchCanvases()
    }

    override func didLoad() {
        super.didLoad()
        backgroundColor = UIColor.theme.primary
        tableNode.view.backgroundColor = .clear
    }

    private func fetchCanvases() {
        Task { @MainActor [weak self] in
            guard let self else { return }
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
            }
        }
    }

    private func presentCanvas(for item: Mezon_Api_ChannelCanvasItem) {
        guard let url = MezonConfig.canvasMobileURL(clanId: clanId, channelId: channelId, canvasId: item.id),
            let host = tableNode.view.findHostingViewController(),
            let nav = host.navigationController
        else { return }
        let title =
            item.title.isEmpty ? L(L10n.ChannelDetail.untitledCanvas) : item.title.replacingOccurrences(
                of: "\n", with: " ")
        let vc = CanvasWebViewController(pageURL: url, canvasTitle: title, accountContext: context)
        nav.pushViewController(vc, animated: true)
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
        let shareURL = MezonConfig.canvasShareURLString(
            clanId: clanId, channelId: channelId, canvasId: canvas.id)
        return {
            CanvasCellNode(
                canvas: canvas,
                onCopyLink: {
                    UIPasteboard.general.string = shareURL
                    Toast.success(L(L10n.MessageAction.copied))
                }
            )
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        let canvas = canvases[indexPath.row]
        presentCanvas(for: canvas)
    }
}

private final class CanvasCellNode: ASCellNode {
    private let cardNode = ASDisplayNode()
    private let titleNode = ASTextNode2()
    private let copyLinkButton = ASButtonNode()
    private let onCopyLink: () -> Void

    init(canvas: Mezon_Api_ChannelCanvasItem, onCopyLink: @escaping () -> Void) {
        self.onCopyLink = onCopyLink
        super.init()
        self.automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none

        let t = UIColor.theme

        cardNode.backgroundColor = t.secondary
        cardNode.cornerRadius = 10.sf
        cardNode.clipsToBounds = true

        let title =
            canvas.title.isEmpty ? L(L10n.ChannelDetail.untitledCanvas) : canvas.title.replacingOccurrences(
                of: "\n", with: " ")
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .medium),
                .foregroundColor: t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 2
        titleNode.truncationMode = .byTruncatingTail

        copyLinkButton.setTitle(
            L(L10n.ChannelAction.copyLink), with: UIFont.systemFont(ofSize: 12.sf, weight: .medium),
            with: t.textLink, for: .normal)
        copyLinkButton.backgroundColor = t.secondaryLight
        copyLinkButton.cornerRadius = 6
        copyLinkButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        copyLinkButton.addTarget(
            self, action: #selector(copyLinkTapped), forControlEvents: .touchUpInside)
    }

    @objc private func copyLinkTapped() {
        onCopyLink()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let rowStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .spaceBetween,
            alignItems: .center,
            children: [titleNode, copyLinkButton]
        )
        titleNode.style.flexShrink = 1
        titleNode.style.flexGrow = 1

        let cardContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14),
            child: rowStack
        )
        let card = ASBackgroundLayoutSpec(child: cardContent, background: cardNode)

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16),
            child: card
        )
    }
}

private extension UIView {
    func findHostingViewController() -> ViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? ViewController { return vc }
            responder = next
        }
        return nil
    }
}
