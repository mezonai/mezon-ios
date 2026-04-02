import AsyncDisplayKit
import UIKit

final class MyQRCodeViewController: ViewController {

    private let context: AccountContext
    private var myQRCodeNode: MyQRCodeContainerNode {
        return self.displayNode as! MyQRCodeContainerNode
    }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
        self.title = L(L10n.QRScanner.myQRCode)
        self.displayNavigationBar = false
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        self.displayNode = MyQRCodeContainerNode(context: self.context)

        myQRCodeNode.onTabChanged = { [weak self] index in
            self?.myQRCodeNode.updateTab(index)
        }
        
        myQRCodeNode.onBackTapped = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.tintColor = UIColor.mezonTextStrong
    }

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition
    ) {
        super.containerLayoutUpdated(layout, transition: transition)
        myQRCodeNode.updateLayout(layout: layout, transition: transition)
    }
}
