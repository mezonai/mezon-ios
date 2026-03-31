import UIKit
import AsyncDisplayKit

final class SplashViewController: ViewController {

    private let imageNode = ASImageNode()

    init() {
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let container = ASDisplayNode()
        container.backgroundColor = .black

        imageNode.image = UIImage(named: "SplashScreen")
        imageNode.contentMode = .scaleAspectFit

        container.addSubnode(imageNode)
        container.layoutSpecBlock = { [weak self] _, constrainedSize in
            guard let self else { return ASLayoutSpec() }
            return ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: .minimumXY,
                child: ASRatioLayoutSpec(ratio: 1.0, child: self.imageNode)
                    .styled { style in
                        style.maxWidth = ASDimensionMake(constrainedSize.max.width * 0.5)
                    }
            )
        }

        self.displayNode = container
    }
}
