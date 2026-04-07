import AsyncDisplayKit
import UIKit

@MainActor
final class MediaGalleryNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var attachments: [Mezon_Api_ChannelAttachment] = []

    private let collectionNode: ASCollectionNode

    init(context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2

        self.collectionNode = ASCollectionNode(collectionViewLayout: layout)

        super.init()
        self.automaticallyManagesSubnodes = true

        collectionNode.dataSource = self
        collectionNode.delegate = self
        collectionNode.backgroundColor = .clear

        fetchMedia()
    }

    private func fetchMedia() {
        Task {
            do {
                let token = await context.getToken() ?? ""
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listChannelAttachments(
                    clanId: targetClanId,
                    channelId: channelId,
                    fileType: "image",
                    limit: 50,
                    token: token
                )
                self.attachments = res.attachments
                await self.collectionNode.reloadData()
            } catch {
                AppLogger.network.error("Fetch media failed: \(error)")
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASWrapperLayoutSpec(layoutElement: collectionNode)
    }
}

extension MediaGalleryNode: ASCollectionDataSource, ASCollectionDelegate {
    func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int)
        -> Int
    {
        return attachments.count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        let attachment = attachments[indexPath.item]
        return {
            let node = MediaCellNode(attachment: attachment)
            return node
        }
    }
}

private final class MediaCellNode: ASCellNode {
    private let imageNode = ASNetworkImageNode()

    init(attachment: Mezon_Api_ChannelAttachment) {
        super.init()
        self.automaticallyManagesSubnodes = true

        imageNode.url = URL(string: attachment.url)
        imageNode.contentMode = .scaleAspectFill
        imageNode.clipsToBounds = true
    }

    @MainActor
    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let width = constrainedSize.max.width / 3 - 2
        imageNode.style.preferredSize = CGSize(width: width, height: width)
        return ASWrapperLayoutSpec(layoutElement: imageNode)
    }
}
