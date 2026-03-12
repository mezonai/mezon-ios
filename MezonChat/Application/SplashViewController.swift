import UIKit
import AsyncDisplayKit

final class SplashViewController: ViewController {

    init() {
        print("[SplashViewController] init")
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        print("[SplashViewController] loadDisplayNode")
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .black
    }

    override func viewDidLoad() {
        print("[SplashViewController] viewDidLoad")
        super.viewDidLoad()
        let iv = UIImageView(image: UIImage(named: "SplashScreen"))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iv.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            iv.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
    }
}
