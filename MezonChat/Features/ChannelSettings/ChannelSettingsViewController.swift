import UIKit
import AsyncDisplayKit

final class ChannelSettingsViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private var categoryId: Int64
    private var categoryName: String
    private let channelType: Int32
    private let channelPrivate: Bool
    private let initialName: String
    private let initialTopic: String

    private var settingsNode: ChannelSettingsContainerNode { displayNode as! ChannelSettingsContainerNode }

    init(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        categoryId: Int64,
        categoryName: String = "",
        channelType: Int32 = 1,
        channelPrivate: Bool = false,
        channelName: String,
        channelTopic: String
    ) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.channelType = channelType
        self.channelPrivate = channelPrivate
        self.initialName = channelName
        self.initialTopic = channelTopic
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let isGeneralChannel: Bool = context.account.postbox.read { tx in
            guard let data = tx.getClan(id: self.clanId)?.data, !data.isEmpty,
                  let desc = try? Mezon_Api_ClanDesc(serializedBytes: data) else { return false }
            return self.channelId == desc.welcomeChannelID
        }

        let isThread = channelType == MezonConstants.ChannelType.thread.rawValue
        let isPublicChannel = !channelPrivate
        let canManageChannel = context.rolePermissions.canManageChannel(clanId: clanId)
        let isAdministrator = context.rolePermissions.hasClanPermission(.administrator, clanId: clanId) || context.rolePermissions.isClanOwner(clanId: clanId)
        
        let showPermissions = canManageChannel &&
                              !isThread &&
                              !isGeneralChannel &&
                              channelType != MezonConstants.ChannelType.app.rawValue &&
                              channelType != MezonConstants.ChannelType.streaming.rawValue &&
                              channelType != MezonConstants.ChannelType.mezonVoice.rawValue
        let showChangeCategory = canManageChannel && !isThread
        
        let showWebhook = canManageChannel &&
                          channelType != MezonConstants.ChannelType.streaming.rawValue &&
                          channelType != MezonConstants.ChannelType.mezonVoice.rawValue
                          
        let showQuickAction = canManageChannel && 
                              (channelType == MezonConstants.ChannelType.channel.rawValue || 
                               channelType == MezonConstants.ChannelType.thread.rawValue ||
                               channelType == MezonConstants.ChannelType.app.rawValue)
                               
        let showBanList = isAdministrator

        displayNode = ChannelSettingsContainerNode(
            channelName: initialName,
            channelTopic: initialTopic,
            isThread: channelType == MezonConstants.ChannelType.thread.rawValue,
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSave: { [weak self] name, topic in
                if #available(iOS 13.0, *) {
                    self?.saveSettings(name: name, topic: topic)
                }
            },
            onPermissionsTap: { [weak self] in
                self?.openChannelPermissions()
            },
            onDeleteTap: { [weak self] in
                if #available(iOS 13.0, *) {
                    self?.presentDeleteChannelConfirm()
                }
            },
            onChangeCategoryTap: { [weak self] in
                self?.openChangeCategory()
            },
            onWebhookTap: { [weak self] in
                self?.openWebhookList()
            },
            showDeleteButton: !isGeneralChannel && canManageChannel,
            showPermissionsButton: showPermissions,
            showChangeCategoryButton: showChangeCategory,
            showWebhookButton: showWebhook,
            showQuickActionButton: showQuickAction,
            showBanListButton: showBanList
        )
    }

    @available(iOS 13.0, *)
    private func presentDeleteChannelConfirm() {
        let isThread = channelType == MezonConstants.ChannelType.thread.rawValue
        let title = isThread ? L(L10n.ChannelAction.deleteThread) : L(L10n.Channel.delete)
        let message = isThread ? L(L10n.Channel.deleteThreadConfirm) : L(L10n.Channel.deleteConfirm)

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] _ in
            self?.handleDeleteChannel()
        }))
        self.present(alert, animated: true)
    }

    @available(iOS 13.0, *)
    private func handleDeleteChannel() {
        settingsNode.setDeleteButtonEnabled(false)
        Task { @MainActor in
            guard let token = await context.getToken() else {
                settingsNode.setDeleteButtonEnabled(true)
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                try await MezonHTTPClient.shared.deleteChannelDesc(channelId: channelId, clanId: clanId, token: token)
                NotificationCenter.default.post(
                    name: .mezonChannelDeletedLocally,
                    object: nil,
                    userInfo: ["clanId": clanId, "channelId": channelId]
                )
                self.navigateBackAfterDelete()
            } catch {
                settingsNode.setDeleteButtonEnabled(true)
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func navigateBackAfterDelete() {
        guard let nav = self.navigationController as? NavigationController else {
            self.navigationController?.popToRootViewController(animated: true)
            return
        }
        var stack = nav.viewControllers
        if let idx = stack.firstIndex(where: { $0 === self }) {
            stack.remove(at: idx)
        }
        if let idx = stack.lastIndex(where: { $0 is ChannelDetailViewController }) {
            stack.remove(at: idx)
        }
        if let idx = stack.lastIndex(where: { $0 is ChatViewController }) {
            stack.remove(at: idx)
        }
        if stack.isEmpty {
            nav.popToRoot(animated: true)
        } else {
            nav.setViewControllers(stack, animated: true)
        }
    }

    private func openChannelPermissions() {
        let vc = ChannelPermissionsViewController(
            context: context,
            clanId: clanId,
            channelId: channelId,
            channelType: channelType,
            channelPrivate: channelPrivate
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openChangeCategory() {
        let vc = ChangeCategoryViewController(
            context: context,
            clanId: clanId,
            channelId: channelId,
            currentCategoryId: categoryId,
            currentCategoryName: categoryName,
            channelLabel: initialName,
            channelTopic: initialTopic
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openWebhookList() {
        let vc = WebhookListViewController(
            context: context,
            clanId: clanId,
            channelId: channelId
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        settingsNode.applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let ch = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channelId) {
            categoryId = ch.categoryID
            categoryName = ch.categoryName
        }
    }

    @available(iOS 13.0, *)
    private func saveSettings(name: String, topic: String) {
        Task {
            do {
                guard let token = await self.context.getToken() else { return }
                try await self.context.engine.channels.updateChannelDescription(
                    clanId: self.clanId,
                    channelId: self.channelId,
                    name: name,  
                    topic: topic, 
                    categoryId: self.categoryId,
                    token: token
                )

                await MainActor.run {
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                await MainActor.run {
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }
}

