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
        
        myQRCodeNode.onDownloadTapped = { [weak self] image in
            guard let self = self else { return }
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
        
        myQRCodeNode.onShareTapped = { [weak self] image in
            guard let self = self else { return }
            let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                let anchorView = self.myQRCodeNode.shareAnchorView
                popover.sourceView = anchorView
                popover.sourceRect = anchorView.bounds
            }
            self.present(activityVC, animated: true)
        }
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            Toast.error(error.localizedDescription)
        } else {
            Toast.success("Success")
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
