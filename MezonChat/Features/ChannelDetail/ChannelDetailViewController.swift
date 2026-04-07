import UIKit
import AsyncDisplayKit

final class ChannelDetailViewController: ViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channel: Mezon_Api_ChannelDescription

    private var detailNode: ChannelDetailContainerNode { displayNode as! ChannelDetailContainerNode }

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
        let parentId: Int64 =
            channel.type == MezonConstants.ChannelType.thread.rawValue
            ? channel.parentID
            : channel.channelID
        let vc = ThreadListViewController(
            context: context,
            clanId: clanId,
            parentChannelId: parentId,
            parentChannelLabel: channel.channelLabel
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openChannelSearch() {
        let isPrivateOrThread = channel.channelPrivate != 0 || channel.parentID != 0
        let searchVC = SearchViewController(
            clanId: clanId,
            context: context,
            channelId: channel.channelID,
            channelLabel: channel.channelLabel,
            channelType: channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue,
            needsChannelMemberFilter: isPrivateOrThread
        )
        navigationController?.pushViewController(searchVC, animated: true)
    }

    private func openSettings() {
        let settingsVC = ChannelSettingsViewController(
            context: context,
            clanId: clanId,
            channelId: channel.channelID,
            categoryId: channel.parentID,
            channelName: channel.channelLabel,
            channelTopic: "" // Topic from description or store?
        )
        self.navigationController?.pushViewController(settingsVC, animated: true)
    }
}
