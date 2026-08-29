import UIKit

final class SocketStatusBannerView: UIView {

    private let spinner = UIActivityIndicatorView.mezonMedium()
    private let dotView = UIView()
    private let label = UILabel()

    private var isShowing = false
    private var hideTimer: Foundation.Timer?
    private var socketObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = socketObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        hideTimer?.invalidate()
    }

    private func setup() {
        backgroundColor = UIColor(red: 63/255, green: 69/255, blue: 75/255, alpha: 0.89)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        alpha = 0
        isHidden = true

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        dotView.layer.cornerRadius = 5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.isHidden = true

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [spinner, dotView, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),
        ])
    }

    private func showConnecting() {
        hideTimer?.invalidate()
        hideTimer = nil
        spinner.startAnimating()
        spinner.isHidden = false
        dotView.isHidden = true
        label.text = "Connecting..."
        showBanner()
    }

    private func showConnected() {
        spinner.stopAnimating()
        spinner.isHidden = true
        dotView.isHidden = false
        dotView.backgroundColor = UIColor.systemGreen
        label.text = "Connected"
        showBanner()


        hideTimer?.invalidate()
        hideTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] (_: Foundation.Timer) in
            self?.hideBanner()
        }
    }

    private func showBanner() {
        guard !isShowing else { return }
        isShowing = true
        isHidden = false
        UIView.animate(withDuration: 0.3) { self.alpha = 1 }
    }

    private func hideBanner() {
        guard isShowing else { return }
        isShowing = false
        UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }) { _ in
            self.isHidden = true
        }
    }

    @discardableResult
    static func install(on window: UIWindow) -> SocketStatusBannerView {
        let banner = SocketStatusBannerView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 4),
            banner.centerXAnchor.constraint(equalTo: window.centerXAnchor),
        ])

        banner.socketObserver = NotificationCenter.default.addObserver(
            forName: .mezonSocketStatusChanged,
            object: nil,
            queue: .main
        ) { [weak banner] notification in
            guard let banner else { return }
            let connected = notification.userInfo?["isConnected"] as? Bool ?? false
            if connected {
                banner.showConnected()
            } else {
                banner.showConnecting()
            }
        }

        return banner
    }
}
