import AsyncDisplayKit
import UIKit

final class DeepLinkNodeOverlayController: UIViewController {
    private let contentNode: ASDisplayNode

    init(node: ASDisplayNode) {
        self.contentNode = node
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        view.addSubnode(contentNode)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentNode.frame = view.bounds
    }

    func dismissOverlay(completion: (() -> Void)? = nil) {
        dismiss(animated: true, completion: completion)
    }
}
