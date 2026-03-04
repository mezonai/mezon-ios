import UIKit
import Combine

class BaseViewController: UIViewController {
    var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    func setupUI() {}
    func setupBindings() {}

    func applyTheme() {}

    @objc private func handleThemeChange() {
        applyTheme()
    }

    deinit {
        cancellables.removeAll()
    }
}
