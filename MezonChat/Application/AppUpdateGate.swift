import UIKit

@MainActor
enum AppUpdateGate {
    private static let appStoreID = "6502750046"
    private static let countryCode = "vn"
    private static let checkDelay: TimeInterval = 2
    private static var didScheduleCheck = false
    private static var didPresentUpdateSheet = false

    static func scheduleVersionCheckIfNeeded(mainWindow: Window1?) {
        guard !didScheduleCheck else { return }
        didScheduleCheck = true
        DispatchQueue.main.asyncAfter(deadline: .now() + checkDelay) {
            Task { await performCheck(mainWindow: mainWindow) }
        }
    }

    private static func performCheck(mainWindow: Window1?) async {
        guard !didPresentUpdateSheet else { return }
        guard let mainWindow else { return }
        let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        print("[AppUpdateGate] Local version: \(localVersion)")
        guard let (remoteVersion, storeURL) = await fetchAppStoreVersion() else {
            print("[AppUpdateGate] Remote version: (unavailable)")
            return
        }
        print("[AppUpdateGate] Remote version: \(remoteVersion)")
        guard remoteVersion.compare(localVersion, options: .numeric) == .orderedDescending else { return }
        didPresentUpdateSheet = true
        let content = AppUpdateRequiredSheetViewController(storeURL: storeURL, remoteVersion: remoteVersion)
        let nav = UINavigationController(rootViewController: content)
        nav.setNavigationBarHidden(true, animated: false)
        nav.modalPresentationStyle = .pageSheet
        nav.isModalInPresentation = true
        mainWindow.presentNative(nav)
    }

    private static func fetchAppStoreVersion() async -> (String, URL)? {
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)&country=\(countryCode)")!
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
            guard let first = decoded.results.first else { return nil }
            guard let storeURL = URL(string: first.trackViewUrl) else { return nil }
            return (first.version, storeURL)
        } catch {
            return nil
        }
    }
}

private struct ITunesLookupResponse: Decodable {
    let results: [ITunesLookupResult]
}

private struct ITunesLookupResult: Decodable {
    let version: String
    let trackViewUrl: String
}

@MainActor
private final class AppUpdateRequiredSheetViewController: UIViewController {
    private let storeURL: URL
    private let remoteVersion: String
    private var contentStack: UIStackView?
    private var lastAppliedDetentHeight: CGFloat = 0
    private static let contentTopPadding: CGFloat = 32
    private static let contentBottomPadding: CGFloat = 24

    init(storeURL: URL, remoteVersion: String) {
        self.storeURL = storeURL
        self.remoteVersion = remoteVersion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondaryBackground

        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor(hex: 0xF3E8FF)
        iconContainer.layer.cornerRadius = 40
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
        iconView.tintColor = ThemeManager.shared.attributes.loginButtonBg
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.UpdateGate.outOfDateVersion)
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .mezonTextStrong
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = L(L10n.UpdateGate.updateExperience)
        descLabel.font = .systemFont(ofSize: 16)
        descLabel.textColor = .mezonTextSecondary
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = UILabel()
        versionLabel.text = L(L10n.UpdateGate.versionInfo) + " " + remoteVersion
        versionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .mezonTextSecondary
        versionLabel.textAlignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let updateButton = UIButton(type: .system)
        updateButton.setTitle(L(L10n.UpdateGate.updateNow), for: .normal)
        updateButton.setTitleColor(.white, for: .normal)
        updateButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        updateButton.backgroundColor = ThemeManager.shared.attributes.loginButtonBg
        updateButton.layer.cornerRadius = 25
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        updateButton.addTarget(self, action: #selector(didTapUpdate), for: .touchUpInside)

        let iconRow = UIStackView(arrangedSubviews: [UIView(), iconContainer, UIView()])
        iconRow.axis = .horizontal
        iconRow.alignment = .center
        iconRow.translatesAutoresizingMaskIntoConstraints = false
        if let a = iconRow.arrangedSubviews.first, let b = iconRow.arrangedSubviews.last {
            a.widthAnchor.constraint(equalTo: b.widthAnchor).isActive = true
        }

        let stack = UIStackView(arrangedSubviews: [iconRow, titleLabel, descLabel, updateButton, versionLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.setCustomSpacing(24, after: iconRow)
        stack.setCustomSpacing(32, after: descLabel)
        stack.setCustomSpacing(16, after: updateButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentStack = stack

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 80),
            iconContainer.heightAnchor.constraint(equalToConstant: 80),
            updateButton.heightAnchor.constraint(equalToConstant: 50),
        ])

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.contentTopPadding),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        if #available(iOS 15.0, *), let sp = navigationController?.sheetPresentationController {
            sp.prefersGrabberVisible = true
            sp.preferredCornerRadius = 16
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, let stack = contentStack else { return }
        view.layoutIfNeeded()
        let horizontalPadding: CGFloat = 24 * 2
        let w = view.bounds.width - horizontalPadding
        let stackH = stack.systemLayoutSizeFitting(
            CGSize(width: w, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let h = view.safeAreaInsets.top
            + Self.contentTopPadding
            + stackH
            + Self.contentBottomPadding
            + view.safeAreaInsets.bottom
        if abs(h - lastAppliedDetentHeight) < 0.5 { return }
        lastAppliedDetentHeight = h
        applySheetDetent(fittedHeight: h)
    }

    private func applySheetDetent(fittedHeight: CGFloat) {
        guard #available(iOS 15.0, *), let sp = navigationController?.sheetPresentationController else { return }
        if #available(iOS 16.0, *) {
            let id = UISheetPresentationController.Detent.Identifier("mezon.appUpdate.fitContent")
            let detent = UISheetPresentationController.Detent.custom(identifier: id) { [fittedHeight] context in
                min(fittedHeight, context.maximumDetentValue)
            }
            sp.detents = [detent]
            sp.selectedDetentIdentifier = id
        } else {
            sp.detents = [.medium()]
        }
    }

    @objc private func didTapUpdate() {
        UIApplication.shared.open(storeURL)
    }
}
