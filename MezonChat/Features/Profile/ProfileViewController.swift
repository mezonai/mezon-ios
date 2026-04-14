import UIKit
import SwiftProtobuf

final class ProfileViewController: ViewController {

    private let context: AccountContext

    private var profileNode: ProfileContainerNode {
        displayNode as! ProfileContainerNode
    }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ProfileContainerNode(context: context)
        node.onBackTapped = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        node.onSettingsTapped = { [weak self] in
            guard let self else { return }
            let vc = SettingsViewController(context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onEditProfileTapped = { [weak self] in
            guard let self else { return }
            let vc = ProfileSettingViewController(context: self.context, initialTab: .userProfile)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        displayNode = node
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        profileNode.updateContent()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        profileNode.updateLayout(layout: layout, transition: transition)
    }
}
