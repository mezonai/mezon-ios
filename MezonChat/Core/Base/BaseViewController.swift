import UIKit
import AsyncDisplayKit

class BaseViewController: ViewController {

    var disposables = DisposableSet()

    convenience init() {
        self.init(navigationBarPresentationData: nil)
    }

    override init(navigationBarPresentationData: NavigationBarPresentationData?) {
        super.init(navigationBarPresentationData: navigationBarPresentationData)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: LanguageManager.didChangeNotification,
            object: nil
        )
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
    }

    func setupUI() {}
    func setupBindings() {}
    func applyTheme() {}

    @objc private func handleThemeChange() {
        applyTheme()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        disposables.dispose()
    }
}
