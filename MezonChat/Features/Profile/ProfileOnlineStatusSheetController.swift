import UIKit

final class ProfileOnlineStatusSheetController: UIViewController {

    private let context: AccountContext

    private let tableView = UITableView.mezonInsetGrouped()

    private var currentUserObserver: NSObjectProtocol?

    private enum Section: Int {
        case presence = 0
        case custom = 1
    }

    private let presenceCases: [(User.OnlineStatus, String)] = [
        (.online, L10n.Profile.userStatusOnline),
        (.idle, L10n.Profile.userStatusIdle),
        (.doNotDisturb, L10n.Profile.userStatusDoNotDisturb),
        (.invisible, L10n.Profile.userStatusInvisible),
    ]

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondaryBackground

        setupPaddedNavigationTitle()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorInset = .zero
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(ProfileSheetPresenceCell.self, forCellReuseIdentifier: ProfileSheetPresenceCell.reuseId)
        tableView.register(ProfileSheetCustomStatusCell.self, forCellReuseIdentifier: ProfileSheetCustomStatusCell.reuseId)
        tableView.rowHeight = 56
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        currentUserObserver = NotificationCenter.default.addObserver(
            forName: .mezonAccountCurrentUserDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let currentUserObserver {
            NotificationCenter.default.removeObserver(currentUserObserver)
        }
    }

    private func setupPaddedNavigationTitle() {
        let label = UILabel()
        label.text = L(L10n.Profile.changeOnlineStatus)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .mezonTextStrong
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        navigationItem.titleView = wrap
    }

    private func iconForPresence(_ s: User.OnlineStatus) -> UIImage? {
        let name: String
        switch s {
        case .online: name = "OnlineIcon"
        case .idle: name = "IdleIcon"
        case .doNotDisturb: name = "DisturbIcon"
        case .invisible, .offline: name = "InvisibleIcon"
        }
        guard let img = UIImage(named: "Profile/\(name)", in: Bundle.main, compatibleWith: nil) else { return nil }
        let canvas: CGFloat = 20
        let drawSide: CGFloat
        switch s {
        case .online, .invisible, .offline:
            drawSide = 14
        case .idle, .doNotDisturb:
            drawSide = 20
        }
        let r = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas))
        return r.image { _ in
            let o = (canvas - drawSide) / 2
            img.draw(in: CGRect(x: o, y: o, width: drawSide, height: drawSide))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func faceIconScaled() -> UIImage? {
        guard let img = UIImage(named: "Profile/FaceIcon", in: Bundle.main, compatibleWith: nil) else { return nil }
        let sz: CGFloat = 20
        let r = UIGraphicsImageRenderer(size: CGSize(width: sz, height: sz))
        return r.image { _ in
            img.draw(in: CGRect(x: 0, y: 0, width: sz, height: sz))
        }.withRenderingMode(.alwaysOriginal)
    }

    @available(iOS 13.0, *)
    private func clearCustomStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.context.submitCustomStatus(text: "", minutes: 0, noClear: false)
                self.tableView.reloadData()
            } catch {
                Toast.error(L(L10n.Profile.statusUpdateFailed))
            }
        }
    }

    @objc private func clearAccessoryTapped() {
        if #available(iOS 13.0, *) {
            clearCustomStatus()
        }
    }

    @available(iOS 13.0, *)
    private func selectPresence(_ status: User.OnlineStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.context.updatePresenceStatus(status)
                self.dismiss(animated: true)
            } catch {
                Toast.error(L(L10n.Profile.presenceUpdateFailed))
            }
        }
    }
}

extension ProfileOnlineStatusSheetController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch Section(rawValue: section)! {
        case .presence: return 44
        case .custom: return .leastNormalMagnitude
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .presence:
            let v = UIView()
            v.backgroundColor = .clear
            let l = UILabel()
            l.translatesAutoresizingMaskIntoConstraints = false
            l.text = L(L10n.Profile.onlineStatusSection)
            l.font = .systemFont(ofSize: 15.sf, weight: .semibold)
            l.textColor = .mezonTextStrong
            v.addSubview(l)
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: v.leadingAnchor),
                l.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor),
                l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8.sh),
            ])
            return v
        case .custom:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .presence: return presenceCases.count
        case .custom: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .presence:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ProfileSheetPresenceCell.reuseId, for: indexPath) as? ProfileSheetPresenceCell else {
                return UITableViewCell()
            }
            let item = presenceCases[indexPath.row]
            let current = context.currentUser?.status ?? .offline
            let selected = current == item.0
            cell.configure(title: L(item.1), icon: iconForPresence(item.0), selected: selected)
            cell.separatorInset = .zero
            return cell
        case .custom:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ProfileSheetCustomStatusCell.reuseId, for: indexPath) as? ProfileSheetCustomStatusCell else {
                return UITableViewCell()
            }
            let text = context.currentUser?.customStatus
            let title = (text?.isEmpty == false) ? text! : L(L10n.Profile.setCustomStatus)
            cell.configure(
                title: title,
                icon: faceIconScaled(),
                showClear: text?.isEmpty == false,
                clearTarget: self,
                clearAction: #selector(clearAccessoryTapped)
            )
            cell.separatorInset = .zero
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .presence:
            if #available(iOS 13.0, *) {
                selectPresence(presenceCases[indexPath.row].0)
            }
        case .custom:
            let host = presentingViewController
            let ctx = context
            dismiss(animated: true) {
                let vc = ProfileAddStatusViewController(context: ctx)
                let nav = UINavigationController(rootViewController: vc)
                nav.modalPresentationStyle = .pageSheet
                host?.present(nav, animated: true)
            }
        }
    }
}
