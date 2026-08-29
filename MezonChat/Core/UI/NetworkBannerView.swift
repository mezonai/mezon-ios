import UIKit

final class NetworkBannerView: UIView {

    private let iconView = UIImageView()
    private let label = UILabel()

    private var isShowing = false
    private var hideWorkItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        hideWorkItem?.cancel()
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

        let config = MezonSymbolConfiguration(pointSize: 16, weight: .semibold)
        iconView.image = UIImage.mezonSystemImage("wifi.slash")?.mezonWithConfiguration(config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.text = "No internet connection"
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard !isShowing else { return }
        isShowing = true
        isHidden = false
        UIView.animate(withDuration: 0.3) { self.alpha = 1 }
    }

    private func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isShowing = false
        let needsAnimate = !isHidden || alpha > 0.01
        guard needsAnimate else { return }
        UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }) { _ in
            self.isHidden = true
        }
    }

    private func syncBannerToMonitor() {
        if NetworkMonitor.shared.isConnected {
            hide()
        } else {
            show()
        }
    }

    private func scheduleDeferredSync() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.syncBannerToMonitor()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    @discardableResult
    static func install(on window: UIWindow) -> NetworkBannerView {
        let banner = NetworkBannerView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 4),
            banner.centerXAnchor.constraint(equalTo: window.centerXAnchor),
        ])

        banner.observers.append(NotificationCenter.default.addObserver(
            forName: NetworkMonitor.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak banner] notification in
            guard let banner else { return }
            let connected = (notification.userInfo?["isConnected"] as? Bool) ?? NetworkMonitor.shared.isConnected
            if connected {
                banner.hide()
            } else {
                banner.show()
                banner.scheduleDeferredSync()
            }
        })

        banner.observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak banner] _ in
            banner?.syncBannerToMonitor()
        })

        banner.observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak banner] _ in
            banner?.syncBannerToMonitor()
        })

        if NetworkMonitor.shared.isConnected {
            banner.hide()
        } else {
            banner.show()
            banner.scheduleDeferredSync()
        }

        return banner
    }
}
