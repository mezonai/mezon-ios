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
