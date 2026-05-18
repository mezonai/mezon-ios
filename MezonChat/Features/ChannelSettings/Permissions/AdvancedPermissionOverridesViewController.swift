import UIKit

@MainActor
final class AdvancedPermissionOverridesViewController: BaseViewController {

    enum Target {
        case role(id: Int64, title: String)
        case member(id: Int64, name: String)
    }

    private let context: AccountContext
    private let repository: ChannelPermissionsRepository
    private let clanId: Int64
    private let channelId: Int64
    private let target: Target

    private var permissions: [Mezon_Api_Permission] = []
    private var originValues: [Int64: ChannelPermissionsRepository.PermissionStatus] = [:]
    private var currentValues: [Int64: ChannelPermissionsRepository.PermissionStatus] = [:]

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let sectionLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        target: Target
    ) {
        self.context = context
        self.repository = ChannelPermissionsRepository(context: context)
        self.clanId = clanId
        self.channelId = channelId
        self.target = target
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        setupHeader()
        setupBody()
    }

    private func setupHeader() {
        headerView.backgroundColor = .mezonSecondary
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(handleBack), for: .touchUpInside)

        titleLabel.text = L(L10n.ChannelPermission.permissionOverrides)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        saveButton.setTitle(L(L10n.ChannelPermission.save), for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        saveButton.addTarget(self, action: #selector(handleSave), for: .touchUpInside)
        saveButton.isHidden = true

        [backButton, titleLabel, saveButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14.sw),
            saveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupBody() {
        sectionLabel.text = L(L10n.ChannelPermission.generalChannelPermission)
        sectionLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        sectionLabel.textColor = UIColor.theme.textDisabled
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sectionLabel)

        tableView.backgroundColor = .mezonSecondary
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 90.sh
        tableView.rowHeight = UITableView.automaticDimension
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.register(PermissionTriToggleCell.self, forCellReuseIdentifier: PermissionTriToggleCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10.sh),
            sectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18.sw),
            sectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18.sw),

            tableView.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 18.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18.sw),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18.sw),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        permissions = repository.channelOverridePermissionRows()
        for p in permissions {
            originValues[p.id] = .none
            currentValues[p.id] = .none
        }
        tableView.reloadData()
        Task { [weak self] in await self?.loadCurrentOverrides() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func loadCurrentOverrides() async {
        let roleId: Int64 = {
            if case .role(let id, _) = target { return id }
            return 0
        }()
        let userId: Int64 = {
            if case .member(let id, _) = target { return id }
            return 0
        }()
        let overrides = await repository.fetchPermissionOverrides(
            channelId: channelId,
            roleId: roleId,
            userId: userId
        )
        var statusById: [Int64: ChannelPermissionsRepository.PermissionStatus] = [:]
        for p in permissions { statusById[p.id] = .none }
        for o in overrides {
            statusById[o.permissionID] = o.active ? .allow : .deny
        }
        originValues = statusById
        currentValues = statusById
        tableView.reloadData()
        refreshSaveButton()
    }

    private func refreshSaveButton() {
        let isDirty = originValues != currentValues
        saveButton.isHidden = !isDirty
    }

    @objc private func handleBack() {
        if originValues == currentValues {
            navigationController?.popViewController(animated: true)
            return
        }
        let alert = UIAlertController(
            title: L(L10n.ChannelPermission.warnTitle),
            message: L(L10n.ChannelPermission.warnContent),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.ChannelPermission.warnCancel), style: .destructive, handler: { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }))
        alert.addAction(UIAlertAction(title: L(L10n.ChannelPermission.warnConfirm), style: .default, handler: { [weak self] _ in
            self?.handleSave()
        }))
        present(alert, animated: true)
    }

    @objc private func handleSave() {
        guard originValues != currentValues else { return }
        let updates: [(Int64, String, ChannelPermissionsRepository.PermissionStatus)] = permissions.map { p in
            (p.id, p.slug, currentValues[p.id] ?? .none)
        }
        let roleId: Int64 = {
            if case .role(let id, _) = target { return id }
            return 0
        }()
        let userId: Int64 = {
            if case .member(let id, _) = target { return id }
            return 0
        }()
        let roleLabel: String = {
            switch target {
            case .role(_, let title): return title
            case .member: return ""
            }
        }()
        Task { [weak self] in
            guard let self else { return }
            guard !updates.isEmpty else { return }
            do {
                try await self.repository.setPermissionOverrides(
                    clanId: self.clanId,
                    channelId: self.channelId,
                    roleId: roleId,
                    userId: userId,
                    roleLabel: roleLabel,
                    permissionUpdates: updates
                )
                self.originValues = self.currentValues
                self.refreshSaveButton()
                Toast.success(L(L10n.ChannelPermission.toastSuccess))
            } catch {
                Toast.error(L(L10n.ChannelPermission.toastFailed))
            }
        }
    }
}

extension AdvancedPermissionOverridesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        permissions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let p = permissions[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: PermissionTriToggleCell.reuseId, for: indexPath) as! PermissionTriToggleCell
        let status = currentValues[p.id] ?? .none
        cell.configure(
            title: RolePermissionLocalization.title(forSlug: p.slug, fallback: p.title),
            description: RolePermissionLocalization.description(forSlug: p.slug),
            status: status
        )
        cell.onChange = { [weak self] newStatus in
            guard let self else { return }
            self.currentValues[p.id] = newStatus
            self.refreshSaveButton()
        }
        return cell
    }
}

@MainActor
private final class PermissionTriToggleCell: UITableViewCell {

    static let reuseId = "PermissionTriToggleCell"

    private static let noneAccent = UIColor(red: 64 / 255, green: 66 / 255, blue: 73 / 255, alpha: 1)

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let segmentOuter = UIView()
    private let denyButton = UIButton(type: .system)
    private let noneButton = UIButton(type: .system)
    private let allowButton = UIButton(type: .system)
    private let divider1 = UIView()
    private let divider2 = UIView()

    var onChange: ((ChannelPermissionsRepository.PermissionStatus) -> Void)?
    private var current: ChannelPermissionsRepository.PermissionStatus = .none

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        onChange = nil
    }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .medium)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        descriptionLabel.font = .systemFont(ofSize: 10.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0

        segmentOuter.layer.borderWidth = 1 / max(UIScreen.main.scale, 1)
        segmentOuter.layer.borderColor = UIColor.theme.border.cgColor
        segmentOuter.layer.cornerRadius = 4.swh
        segmentOuter.clipsToBounds = true

        let hairline = 1 / max(UIScreen.main.scale, 1)
        divider1.backgroundColor = UIColor.theme.border
        divider2.backgroundColor = UIColor.theme.border
        divider1.translatesAutoresizingMaskIntoConstraints = false
        divider2.translatesAutoresizingMaskIntoConstraints = false

        setupSegmentButton(denyButton, systemName: "xmark", pointSize: 12.swh)
        setupSegmentButton(noneButton, systemName: "slash.circle", pointSize: 14.swh)
        setupSegmentButton(allowButton, systemName: "checkmark", pointSize: 12.swh)

        denyButton.addTarget(self, action: #selector(denyTapped), for: .touchUpInside)
        noneButton.addTarget(self, action: #selector(noneTapped), for: .touchUpInside)
        allowButton.addTarget(self, action: #selector(allowTapped), for: .touchUpInside)

        let inner = UIStackView(arrangedSubviews: [
            denyButton, divider1, noneButton, divider2, allowButton,
        ])
        inner.axis = .horizontal
        inner.spacing = 0
        inner.distribution = .fill
        inner.alignment = .fill
        inner.translatesAutoresizingMaskIntoConstraints = false
        segmentOuter.addSubview(inner)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        segmentOuter.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(segmentOuter)

        let segmentH = max(30.sh, 28.swh)
        let segmentW = max(104.sw, 96)

        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: segmentOuter.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: segmentOuter.trailingAnchor),
            inner.topAnchor.constraint(equalTo: segmentOuter.topAnchor),
            inner.bottomAnchor.constraint(equalTo: segmentOuter.bottomAnchor),

            divider1.widthAnchor.constraint(equalToConstant: hairline),
            divider2.widthAnchor.constraint(equalToConstant: hairline),

            denyButton.widthAnchor.constraint(equalTo: noneButton.widthAnchor),
            noneButton.widthAnchor.constraint(equalTo: allowButton.widthAnchor),

            segmentOuter.widthAnchor.constraint(equalToConstant: segmentW),
            segmentOuter.heightAnchor.constraint(equalToConstant: segmentH),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6.sh),

            segmentOuter.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            segmentOuter.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: segmentOuter.leadingAnchor, constant: -12.sw),

            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10.sh),
        ])
    }

    private func setupSegmentButton(_ b: UIButton, systemName: String, pointSize: CGFloat) {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        b.setImage(UIImage(systemName: systemName, withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(
        title: String,
        description: String,
        status: ChannelPermissionsRepository.PermissionStatus
    ) {
        titleLabel.text = title
        descriptionLabel.text = description
        current = status
        applyStatus(status)
    }

    private func applyStatus(_ status: ChannelPermissionsRepository.PermissionStatus) {
        let inactiveFill = UIColor.mezonSecondary
        let red = UIColor.systemRed
        let green = UIColor.systemGreen
        let noneTintInactive = Self.noneAccent

        denyButton.backgroundColor = status == .deny ? red : inactiveFill
        denyButton.tintColor = status == .deny ? .white : red

        noneButton.backgroundColor = status == .none ? Self.noneAccent : inactiveFill
        noneButton.tintColor = status == .none ? .white : noneTintInactive

        allowButton.backgroundColor = status == .allow ? green : inactiveFill
        allowButton.tintColor = status == .allow ? .white : green
    }

    @objc private func denyTapped() { apply(.deny) }
    @objc private func noneTapped() { apply(.none) }
    @objc private func allowTapped() { apply(.allow) }

    private func apply(_ status: ChannelPermissionsRepository.PermissionStatus) {
        guard current != status else { return }
        current = status
        applyStatus(status)
        onChange?(status)
    }
}
