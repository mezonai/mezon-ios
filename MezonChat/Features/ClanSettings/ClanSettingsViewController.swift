import UIKit
import AsyncDisplayKit

final class ClanSettingsViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let clanName: String
    private let avatarURL: String

    private var settingsNode: ClanSettingsContainerNode {
        displayNode as! ClanSettingsContainerNode
    }

    init(context: AccountContext, clanId: Int64, clanName: String, avatarURL: String) {
        self.context = context
        self.clanId = clanId
        self.clanName = clanName
        self.avatarURL = avatarURL
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ClanSettingsContainerNode(
            context: context,
            clanId: clanId,
            clanName: clanName,
            avatarURL: avatarURL
        )
        node.onClose = { [weak self] in
            if let nav = self?.navigationController {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        }
        displayNode = node
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Force status bar style if needed, but normally handled by theme
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        settingsNode.updateLayout(layout: layout, transition: transition)
    }
}
