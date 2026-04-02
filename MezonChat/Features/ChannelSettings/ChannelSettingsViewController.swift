import UIKit
import AsyncDisplayKit

final class ChannelSettingsViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let categoryId: Int64
    private let initialName: String
    private let initialTopic: String

    private var settingsNode: ChannelSettingsContainerNode { displayNode as! ChannelSettingsContainerNode }

    init(context: AccountContext, clanId: Int64, channelId: Int64, categoryId: Int64, channelName: String, channelTopic: String) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.categoryId = categoryId
        self.initialName = channelName
        self.initialTopic = channelTopic
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ChannelSettingsContainerNode(
            channelName: initialName,
            channelTopic: initialTopic,
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSave: { [weak self] name, topic in
                self?.saveSettings(name: name, topic: topic)
            }
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        settingsNode.applyTheme()
    }

    private func saveSettings(name: String, topic: String) {
        Task {
            do {
                guard let token = await self.context.getToken() else { return }
                try await self.context.engine.channels.updateChannelDescription(
                    clanId: self.clanId,
                    channelId: self.channelId,
                    name: name == self.initialName ? nil : name,
                    topic: topic == self.initialTopic ? nil : topic,
                    categoryId: self.categoryId,
                    token: token
                )

                await MainActor.run {
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {

            }
        }
    }
}
