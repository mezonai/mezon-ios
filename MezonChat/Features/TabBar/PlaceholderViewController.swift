import UIKit
import AsyncDisplayKit

final class PlaceholderViewController: ViewController {

    private let pageTitle: String

    init(title: String) {
        self.pageTitle = title
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ASDisplayNode()
        displayNode.backgroundColor = UIColor.theme.primary
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = pageTitle
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = UIColor.theme.textStrong
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
    }
}
