import AsyncDisplayKit
import UIKit

@MainActor
final class FileListNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var attachments: [Mezon_Api_ChannelAttachment] = []

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

        fetchFiles()
    }

    private func fetchFiles() {
        Task {
            do {
                let token = await context.getToken() ?? ""
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listChannelAttachments(
                    clanId: targetClanId,
                    channelId: channelId,
                    fileType: "file",
                    limit: 100,
                    token: token
                )
                self.attachments = res.attachments
                await self.tableNode.reloadData()
            } catch {
                AppLogger.network.error("Fetch files failed: \(error)")
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASWrapperLayoutSpec(layoutElement: tableNode)
    }
}

extension FileListNode: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return attachments.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        let attachment = attachments[indexPath.row]
        return {
            return FileCellNode(attachment: attachment)
        }
    }
}

private final class FileCellNode: ASCellNode {
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()

    init(attachment: Mezon_Api_ChannelAttachment) {
        super.init()
        self.automaticallyManagesSubnodes = true

        iconNode.image = UIImage(systemName: "doc.fill")?.withTintColor(
            UIColor.theme.textDisabled, renderingMode: .alwaysOriginal)
        iconNode.style.preferredSize = CGSize(width: 32, height: 32)

        titleNode.attributedText = NSAttributedString(
            string: attachment.filename,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .medium),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )

        subtitleNode.attributedText = NSAttributedString(
            string: attachment.filetype + " · " + attachment.filesize,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textDisabled,
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let textStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 2,
            justifyContent: .start,
            alignItems: .start,
            children: [titleNode, subtitleNode]
        )
        textStack.style.flexShrink = 1
        textStack.style.flexGrow = 1

        let rowStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, textStack]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16), child: rowStack)
    }
}
