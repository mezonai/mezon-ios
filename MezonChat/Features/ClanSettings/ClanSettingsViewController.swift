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
        node.onSelectRoles = { [weak self] in
            guard let self else { return }
            let vc = ClanRolesViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        displayNode = node
    }

    override func viewDidLoad() {
        super.viewDidLoad()

    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        settingsNode.updateLayout(layout: layout, transition: transition)
    }
}
