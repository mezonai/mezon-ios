import UIKit
import AsyncDisplayKit

final class ClanRolesViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let repository: RolesRepository

    private var resolvedClanId: Int64 {
        clanId != 0 ? clanId : context.currentClanId
    }

    private var everyoneRole: Mezon_Api_Role?
    private var roles: [Mezon_Api_Role] = []
    private var canManage: Bool = false

    private lazy var tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .insetGrouped)
        t.backgroundColor = .mezonSecondary
        t.dataSource = self
        t.delegate = self
        t.separatorStyle = .none
        t.estimatedRowHeight = 60.sh
        t.rowHeight = UITableView.automaticDimension
        t.register(ClanRoleCell.self, forCellReuseIdentifier: ClanRoleCell.reuseId)
        t.cellLayoutMarginsFollowReadableWidth = false
        t.preservesSuperviewLayoutMargins = false
        t.insetsLayoutMarginsFromSafeArea = false
        t.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        return t
    }()

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let headerTitleLabel = UILabel()
    private let addButton = UIButton(type: .system)

    private lazy var tableHeader: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 60.sh))
        let label = UILabel()
        label.text = L(L10n.ClanRoles.roleDescription)
        label.font = .systemFont(ofSize: 13.sf, weight: .regular)
        label.textColor = UIColor.theme.textDisabled
        label.numberOfLines = 0
        v.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10.sw),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10.sw),
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 12.sh),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8.sh)
        ])
        return v
    }()

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        self.repository = RolesRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        viewRespectsSystemMinimumLayoutMargins = false
        setupHeader()
        view.addSubview(tableView)
    }

    private func setupHeader() {
        headerView.backgroundColor = .mezonSecondary
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        headerTitleLabel.text = L(L10n.ClanRoles.title)
        headerTitleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        headerTitleLabel.textColor = .mezonTextPrimary
        headerTitleLabel.textAlignment = .center

        addButton.setImage(
            UIImage(systemName: "plus")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        addButton.tintColor = UIColor.theme.textStrong
        addButton.addTarget(self, action: #selector(addRoleTapped), for: .touchUpInside)

        [backButton, headerTitleLabel, addButton].forEach {
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

            headerTitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            addButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8.sw),
            addButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 44.swh),
            addButton.heightAnchor.constraint(equalToConstant: 44.swh)
        ])
    }

    override func setupBindings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRolesChanged),
            name: .mezonRolesDidChange,
            object: nil
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
        Task { [weak self] in
            await self?.repository.refresh(clanId: self?.resolvedClanId ?? 0)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadData()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = layout.safeInsets.top
        let headerH: CGFloat = 50.sh
        tableView.frame = CGRect(
            x: 0,
            y: top + headerH,
            width: layout.size.width,
            height: layout.size.height - top - headerH
        )
    }

    override func applyTheme() {
        view.backgroundColor = .mezonSecondary
        headerView.backgroundColor = .mezonSecondary
        headerTitleLabel.textColor = .mezonTextPrimary
        backButton.tintColor = UIColor.theme.textStrong
        addButton.tintColor = canManage ? UIColor.theme.textStrong : UIColor.theme.textDisabled
        tableView.backgroundColor = .mezonSecondary
        tableView.reloadData()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func handleRolesChanged() {
        reloadData()
    }

    @objc private func addRoleTapped() {
        guard canManage else { return }
        let vc = CreateNewRoleViewController(context: context, clanId: resolvedClanId)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func reloadData() {
        let clanId = resolvedClanId
        let all = repository.roles(clanId: clanId)
        everyoneRole = all.first { $0.slug == "everyone-\(clanId)" }
        roles = all.filter { $0.slug != "everyone-\(clanId)" }
        canManage = repository.canManageRoles(clanId: clanId)
        addButton.isEnabled = canManage
        addButton.tintColor = canManage ? UIColor.theme.textStrong : UIColor.theme.textDisabled
        tableView.reloadData()
    }

    fileprivate enum Section: Int, CaseIterable {
        case everyone
        case roles
    }
}

extension ClanRolesViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .everyone:
            return everyoneRole == nil ? 0 : 1
        case .roles:
            return max(roles.count, 1)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .everyone:
            return tableHeader
        case .roles:
            let wrap = UIView()
            wrap.backgroundColor = .clear
            let label = UILabel()
            label.text = String(format: L(L10n.ClanRoles.rolesCount), roles.count)
            label.font = .systemFont(ofSize: 13.sf, weight: .semibold)
            label.textColor = UIColor.theme.textStrong
            label.numberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 10.sw),
                label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -10.sw),
                label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10.sh),
                label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -6.sh)
            ])
            return wrap
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let s = Section(rawValue: section) else { return CGFloat.leastNonzeroMagnitude }
        switch s {
        case .everyone: return 60.sh
        case .roles: return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .everyone: return 60.sh
        case .roles: return 36.sh
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ClanRoleCell.reuseId, for: indexPath) as! ClanRoleCell
        switch Section(rawValue: indexPath.section)! {
        case .everyone:
            if let role = everyoneRole {
                cell.configureEveryone(role: role)
            }
        case .roles:
            if roles.isEmpty {
                cell.configureEmpty(text: L(L10n.ClanRoles.noRole))
            } else {
                let role = roles[indexPath.row]
                let canEdit = repository.canEditRole(role, clanId: resolvedClanId)
                cell.configure(role: role, memberCount: role.roleUserList.roleUsers.count, isLocked: !canEdit)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.preservesSuperviewLayoutMargins = false
        cell.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        cell.separatorInset = .zero
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .everyone:
            guard let role = everyoneRole else { return }
            let vc = SetupPermissionsViewController(
                context: context,
                clanId: resolvedClanId,
                mode: .edit(roleId: role.id)
            )
            navigationController?.pushViewController(vc, animated: true)
        case .roles:
            guard !roles.isEmpty else { return }
            let role = roles[indexPath.row]
            let vc = RoleDetailViewController(
                context: context, clanId: resolvedClanId, roleId: role.id)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

private final class ClanRoleCell: UITableViewCell {

    static let reuseId = "ClanRoleCell"

    private let iconView = UIImageView()
    private let roleIconView = UIImageView()
    private let colorIndicator = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let lockIcon = UIImageView()
    private let chevron = UIImageView()
    private var roleIconTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = UIColor.theme.tertiary.withAlphaComponent(0.6)
        selectedBackgroundView = selected
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.theme.text

        roleIconView.contentMode = .scaleAspectFill
        roleIconView.clipsToBounds = true
        roleIconView.layer.cornerRadius = 6.swh
        roleIconView.isHidden = true

        colorIndicator.layer.cornerRadius = 6.swh
        colorIndicator.layer.borderWidth = 1
        colorIndicator.layer.borderColor = UIColor.theme.borderDim.cgColor

        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.textDisabled
        subtitleLabel.numberOfLines = 1

        lockIcon.image = UIImage(systemName: "lock.fill")?.withRenderingMode(.alwaysTemplate)
        lockIcon.tintColor = UIColor.theme.textDisabled
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.isHidden = true

        chevron.image = UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit

        [iconView, roleIconView, colorIndicator, titleLabel, subtitleLabel, lockIcon, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6.sw),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28.swh),
            iconView.heightAnchor.constraint(equalToConstant: 28.swh),

            roleIconView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            roleIconView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            roleIconView.widthAnchor.constraint(equalToConstant: 28.swh),
            roleIconView.heightAnchor.constraint(equalToConstant: 28.swh),

            colorIndicator.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            colorIndicator.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2.sh),
            colorIndicator.widthAnchor.constraint(equalToConstant: 12.swh),
            colorIndicator.heightAnchor.constraint(equalToConstant: 12.swh),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10.sw),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.sh),

            lockIcon.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6.sw),
            lockIcon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            lockIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            lockIcon.heightAnchor.constraint(equalToConstant: 14.swh),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.sh),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10.sh),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -6.sw),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6.sw),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10.swh),
            chevron.heightAnchor.constraint(equalToConstant: 14.swh)
        ])
    }

    func configureEveryone(role: Mezon_Api_Role) {
        iconView.image = UIImage(systemName: "person.3.fill")?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .mezonTextPrimary
        iconView.isHidden = false
        roleIconView.isHidden = true
        roleIconTask?.cancel()
        colorIndicator.isHidden = true
        titleLabel.text = L(L10n.ClanRoles.everyone)
        subtitleLabel.text = L(L10n.ClanRoles.defaultRole)
        lockIcon.isHidden = true
        chevron.isHidden = false
        isUserInteractionEnabled = true
    }

    func configure(role: Mezon_Api_Role, memberCount: Int, isLocked: Bool) {
        loadRoleIcon(role.roleIcon)
        iconView.image = UIImage(systemName: "shield.lefthalf.filled")?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = RoleColors.uiColor(forRole: role)
        colorIndicator.isHidden = false
        colorIndicator.backgroundColor = RoleColors.uiColor(forRole: role)
        titleLabel.text = role.title
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        subtitleLabel.text = "\(memberCount) \(L(L10n.ClanRoles.members))"
        lockIcon.isHidden = !isLocked
        chevron.isHidden = false
        isUserInteractionEnabled = true
    }

    func configureEmpty(text: String) {
        roleIconTask?.cancel()
        roleIconView.isHidden = true
        iconView.image = nil
        iconView.isHidden = true
        colorIndicator.isHidden = true
        titleLabel.text = text
        titleLabel.textColor = UIColor.theme.textDisabled
        titleLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        subtitleLabel.text = nil
        lockIcon.isHidden = true
        chevron.isHidden = true
        isUserInteractionEnabled = false
    }

    private func loadRoleIcon(_ urlString: String) {
        roleIconTask?.cancel()
        roleIconView.image = nil
        roleIconView.isHidden = true
        iconView.isHidden = false
        guard !urlString.isEmpty else { return }
        let resolved = ImgproxyURL.create(from: urlString, width: 80, height: 80)
        roleIconTask = ImageCache.shared.loadImage(urlString: resolved) { [weak self] image in
            guard let self else { return }
            DispatchQueue.main.async {
                if let image {
                    self.roleIconView.image = image
                    self.roleIconView.isHidden = false
                    self.iconView.isHidden = true
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        roleIconTask?.cancel()
        roleIconView.image = nil
        roleIconView.isHidden = true
    }
}
