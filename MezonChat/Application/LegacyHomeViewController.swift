import UIKit

// Placeholder for the iOS 12 main UI. It exists to prove the legacy transport
// works end to end: it authenticates with the stored session and renders the
// account the server returns.
final class LegacyHomeViewController: UIViewController {

    var onLoggedOut: (() -> Void)?

    private let disposables = DisposableSet()

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()
    private let logoutButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .gray)

    deinit {
        disposables.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        buildLayout()
        loadAccount()
    }

    private func buildLayout() {
        nameLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        nameLabel.textColor = .black
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0

        detailLabel.font = UIFont.systemFont(ofSize: 15)
        detailLabel.textColor = UIColor(white: 0.35, alpha: 1.0)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = UIColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1.0)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        logoutButton.setTitle("Đăng xuất", for: .normal)
        logoutButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            nameLabel, detailLabel, spinner, statusLabel, logoutButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
    }

    private func loadAccount() {
        nameLabel.text = "Đang tải…"
        detailLabel.text = nil
        statusLabel.text = nil
        spinner.startAnimating()

        let request = LegacySessionManager.shared.validToken()
            |> mapToSignal { token -> Signal<Mezon_Api_Account, MezonError> in
                return MezonHTTPClient.shared.signalGetAccount(token: token)
            }

        disposables.add((request |> deliverOnMainQueue).start(
            next: { [weak self] account in
                guard let self = self else { return }
                self.spinner.stopAnimating()
                let user = account.user
                let name = user.displayName.isEmpty ? user.username : user.displayName
                self.nameLabel.text = name.isEmpty ? "(chưa có tên)" : name
                self.detailLabel.text = "@\(user.username)\n\(account.email)"
            },
            error: { [weak self] error in
                guard let self = self else { return }
                self.spinner.stopAnimating()
                if case .httpError(let statusCode, _) = error, statusCode == 401 || statusCode == 403 {
                    LegacySessionManager.shared.clear()
                    self.onLoggedOut?()
                    return
                }
                self.nameLabel.text = "Không tải được tài khoản"
                self.statusLabel.text = error.technicalDescription
            }
        ))
    }

    @objc private func logoutTapped() {
        logoutButton.isEnabled = false
        spinner.startAnimating()
        LegacySessionManager.shared.logout { [weak self] in
            self?.spinner.stopAnimating()
            self?.onLoggedOut?()
        }
    }
}
