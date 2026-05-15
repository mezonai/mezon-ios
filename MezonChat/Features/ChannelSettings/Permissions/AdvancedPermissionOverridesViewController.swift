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
    private let subtitleLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let sectionLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

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

        subtitleLabel.text = targetTitle()
        subtitleLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.textDisabled
        subtitleLabel.textAlignment = .center

        saveButton.setTitle(L(L10n.ChannelPermission.save), for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        saveButton.addTarget(self, action: #selector(handleSave), for: .touchUpInside)
        saveButton.isHidden = true

        [backButton, titleLabel, subtitleLabel, saveButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8.sh),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.sh),
            subtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14.sw),
            saveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupBody() {
        sectionLabel.text = L(L10n.ChannelPermission.generalChannelPermission)
        sectionLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        sectionLabel.textColor = UIColor.theme.textDisabled
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sectionLabel)

        tableView.backgroundColor = .mezonSecondary
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.theme.tertiary.withAlphaComponent(0.4)
        tableView.estimatedRowHeight = 90.sh
        tableView.rowHeight = UITableView.automaticDimension
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.register(PermissionTriToggleCell.self, forCellReuseIdentifier: PermissionTriToggleCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 14.sh),
            sectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            sectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            tableView.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        permissions = repository.allPermissions()
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

    private func targetTitle() -> String {
        switch target {
        case .role(_, let title): return title
        case .member(_, let name): return name
        }
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
        let updates: [(Int64, String, ChannelPermissionsRepository.PermissionStatus)] = permissions.map { p in
            let status = currentValues[p.id] ?? .none
            return (p.id, p.slug, status)
        }
        let roleId: Int64 = {
            if case .role(let id, _) = target { return id }
            return 0
        }()
        let userId: Int64 = {
            if case .member(let id, _) = target { return id }
            return 0
        }()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.setPermissionOverrides(
                    clanId: self.clanId,
                    channelId: self.channelId,
                    roleId: roleId,
                    userId: userId,
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

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let denyButton = UIButton(type: .system)
    private let noneButton = UIButton(type: .system)
    private let allowButton = UIButton(type: .system)

    var onChange: ((ChannelPermissionsRepository.PermissionStatus) -> Void)?
    private var current: ChannelPermissionsRepository.PermissionStatus = .none

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor.theme.tertiary
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.numberOfLines = 1

        descriptionLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0

        configureButton(denyButton, system: "xmark", color: UIColor.systemRed)
        configureButton(noneButton, system: "slash.circle", color: UIColor.theme.textDisabled)
        configureButton(allowButton, system: "checkmark", color: UIColor.systemGreen)

        denyButton.addTarget(self, action: #selector(denyTapped), for: .touchUpInside)
        noneButton.addTarget(self, action: #selector(noneTapped), for: .touchUpInside)
        allowButton.addTarget(self, action: #selector(allowTapped), for: .touchUpInside)

        let toggleStack = UIStackView(arrangedSubviews: [denyButton, noneButton, allowButton])
        toggleStack.axis = .horizontal
        toggleStack.spacing = 6.sw
        toggleStack.distribution = .equalSpacing
        toggleStack.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, descriptionLabel, toggleStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14.sh),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggleStack.leadingAnchor, constant: -8.sw),

            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.topAnchor.constraint(greaterThanOrEqualTo: toggleStack.bottomAnchor, constant: 6.sh),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6.sh),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14.sh),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),

            toggleStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            toggleStack.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])
    }

    private func configureButton(_ b: UIButton, system: String, color: UIColor) {
        b.setImage(UIImage(systemName: system)?.withRenderingMode(.alwaysTemplate), for: .normal)
        b.tintColor = color
        b.layer.cornerRadius = 14.swh
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 28.swh).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28.swh).isActive = true
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
        denyButton.backgroundColor = status == .deny ? UIColor.systemRed : .clear
        denyButton.tintColor = status == .deny ? .white : UIColor.systemRed
        noneButton.backgroundColor = status == .none ? UIColor.theme.tertiary : .clear
        noneButton.tintColor = status == .none ? .white : UIColor.theme.textDisabled
        allowButton.backgroundColor = status == .allow ? UIColor.systemGreen : .clear
        allowButton.tintColor = status == .allow ? .white : UIColor.systemGreen
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
