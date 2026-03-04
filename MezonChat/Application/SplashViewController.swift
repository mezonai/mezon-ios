import UIKit

final class SplashViewController: UIViewController {

    private lazy var splashImageView: UIImageView = {
        let iv = UIImageView(image: UIImage(named: "SplashScreen"))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(splashImageView)

        NSLayoutConstraint.activate([
            splashImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            splashImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            splashImageView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            splashImageView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
    }
}
