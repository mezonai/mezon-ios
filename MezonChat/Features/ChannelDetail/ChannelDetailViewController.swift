import UIKit
import AsyncDisplayKit

final class ChannelDetailViewController: ViewController {

    private let context: AccountContext
    private let clanId: Int64
    private var channel: Mezon_Api_ChannelDescription

    private var detailNode: ChannelDetailContainerNode { displayNode as! ChannelDetailContainerNode }

    private func resolvedChannelTypeForDetail() -> Int32 {
        if channel.type != 0 { return channel.type }
        if let ch = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID),
            ch.type != 0 {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelDescriptionDidUpdate(_:)),
            name: .mezonChannelDescriptionDidUpdate,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshChannelFromStores()
    }

    private static func notificationInt64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        guard let cid = Self.notificationInt64(notification.userInfo?["channelId"]), cid == channel.channelID else {
            return
        }
        refreshChannelFromStores()
    }

    private func resolvedChannelSnapshot() -> Mezon_Api_ChannelDescription {
        if let ch = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID) {
            return ch
        }
        return channel
    }

    private func refreshChannelFromStores() {
        channel = resolvedChannelSnapshot()
        detailNode.applyUpdatedChannel(channel)
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
        let t = resolvedChannelTypeForDetail()
        let settingsVC = ChannelSettingsViewController(
            context: context,
            clanId: clanId,
            channelId: channel.channelID,
            categoryId: channel.categoryID,
            channelType: t,
            channelPrivate: channel.channelPrivate == 1,
            channelName: channel.channelLabel,
            channelTopic: channel.topic
        )
        navigationController?.pushViewController(settingsVC, animated: true)
    }
}
