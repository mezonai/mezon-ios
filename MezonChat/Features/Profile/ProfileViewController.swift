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
        displayNode = node
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        profileNode.updateLayout(layout: layout, transition: transition)
    }
}
