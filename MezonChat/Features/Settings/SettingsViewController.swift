import UIKit

final class SettingsViewController: BaseViewController {

    private let sharedContext: SharedAccountContext

    private lazy var logoutButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = L(L10n.Common.logOut)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .systemRed
        config.cornerStyle = .large
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addAction(UIAction { [weak self] _ in self?.logoutTapped() }, for: .touchUpInside)
        return btn
    }()

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L(L10n.Settings.title)
        view.backgroundColor = .mezonBackground
        navigationController?.navigationBar.isHidden = false
        setupUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.isHidden = true
    }

    override func setupUI() {
        view.addSubview(logoutButton)
        NSLayoutConstraint.activate([
            logoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            logoutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24.sh),
            logoutButton.heightAnchor.constraint(equalToConstant: 48.sh),
        ])
    }

    private func logoutTapped() {
        sharedContext.appContext.logout()
    }
}
