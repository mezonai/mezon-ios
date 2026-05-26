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
        displayNode = ChannelSettingsContainerNode(
            channelName: initialName,
            channelTopic: initialTopic,
            isThread: channelType == MezonConstants.ChannelType.thread.rawValue,
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSave: { [weak self] name, topic in
                self?.saveSettings(name: name, topic: topic)
            },
            onPermissionsTap: { [weak self] in
                self?.openChannelPermissions()
            },
            onChangeCategoryTap: { [weak self] in
                self?.openChangeCategory()
            }
        )
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

