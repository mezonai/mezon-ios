import UIKit
import AsyncDisplayKit

final class ChannelDetailViewController: ViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channel: Mezon_Api_ChannelDescription

    private var detailNode: ChannelDetailContainerNode { displayNode as! ChannelDetailContainerNode }

    private func resolvedChannelTypeForDetail() -> Int32 {
        if channel.type != 0 { return channel.type }
        if let (_, ch) = context.account.postbox.getChannelDescription(channelId: channel.channelID), ch.type != 0 {
            return ch.type
        }
        return context.engine.clanData.resolvedListChannelUsersType(channelId: channel.channelID)
    }

    init(context: AccountContext, clanId: Int64, channel: Mezon_Api_ChannelDescription) {
        self.context = context
        self.clanId = clanId
        self.channel = channel
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ChannelDetailContainerNode(
            context: context,
            clanId: clanId,
            channel: channel,
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSettingsTapped: { [weak self] in
                self?.openSettings()
            },
            onSearchTapped: { [weak self] in
                self?.openChannelSearch()
            },
            onThreadsTapped: { [weak self] in
                self?.openThreadList()
            }
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        detailNode.applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func openThreadList() {
        let t = resolvedChannelTypeForDetail()
        let parentId: Int64 =
            t == MezonConstants.ChannelType.thread.rawValue
            ? channel.parentID
            : channel.channelID
        let composerSurface = Self.surfaceChannelForThreadComposer(from: channel, resolvedType: t)
        let vc = ThreadListViewController(
            context: context,
            clanId: clanId,
            parentChannelId: parentId,
            parentCategoryId: channel.categoryID,
            parentChannelLabel: channel.channelLabel,
            composerParentChannel: composerSurface
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private static func surfaceChannelForThreadComposer(from channel: Mezon_Api_ChannelDescription, resolvedType: Int32)
        -> Mezon_Api_ChannelDescription {
        guard resolvedType == MezonConstants.ChannelType.thread.rawValue else { return channel }
        var d = channel
        d.channelID = channel.parentID
        d.parentID = 0
        d.type = MezonConstants.ChannelType.forum.rawValue
        return d
    }

    private func openChannelSearch() {
        let t = resolvedChannelTypeForDetail()
        let isPrivateOrThread = channel.channelPrivate != 0 || channel.parentID != 0
            || t == MezonConstants.ChannelType.thread.rawValue
        let searchVC = SearchViewController(
            clanId: clanId,
            context: context,
            channelId: channel.channelID,
            channelLabel: channel.channelLabel,
            channelType: t != 0 ? t : MezonConstants.ChannelType.channel.rawValue,
            needsChannelMemberFilter: isPrivateOrThread
        )
        navigationController?.pushViewController(searchVC, animated: true)
    }

    private func openSettings() {
        /*
        let settingsVC = ChannelSettingsViewController(
            context: context,
            clanId: clanId,
            channelId: channel.channelID,
            categoryId: channel.parentID,
            channelType: channel.type,
            channelPrivate: channel.channelPrivate == 1,
            channelName: channel.channelLabel,
            channelTopic: "" // Topic from description or store?
        )
        self.navigationController?.pushViewController(settingsVC, animated: true)
        */
    }
}
