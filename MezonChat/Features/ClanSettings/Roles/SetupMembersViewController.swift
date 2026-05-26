import UIKit
import AsyncDisplayKit

@MainActor
final class SetupMembersViewController: BaseViewController {

    enum Mode {
        case edit(roleId: Int64)
        case wizard(roleId: Int64)
    }

    private let context: AccountContext
    private let clanId: Int64
    private let mode: Mode
    private let repository: RolesRepository

    private var role: Mezon_Api_Role?
    private var canEdit: Bool = false

    private var assignedMembers: [ClanMemberRecord] = []
    private var allMembers: [ClanMemberRecord] = []
    private var filteredAssigned: [ClanMemberRecord] = []
    private var filteredAll: [ClanMemberRecord] = []
    private var selectedIds: Set<Int64> = []
    private var searchText: String = ""

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let descriptionLabel = UILabel()
    private let searchContainer = UIView()
    private let searchField = UITextField()
    private let addMemberButton = UIButton(type: .custom)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let bottomBar = UIStackView()
    private let finishButton = UIButton(type: .custom)
    private let skipButton = UIButton(type: .system)
    private var tableBottomConstraint: NSLayoutConstraint?
    private var bottomBarBottomConstraint: NSLayoutConstraint?

    private var roleId: Int64 {
        switch mode {
        case .edit(let id), .wizard(let id): return id
        }
    }
    private var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    init(context: AccountContext, clanId: Int64, mode: Mode) {
        self.context = context
        self.clanId = clanId
        self.mode = mode
        self.repository = RolesRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        navigationController?.setNavigationBarHidden(true, animated: false)

        setupHeader()
        setupDescription()
        setupSearch()
        setupAddButton()
        setupTable()
        if !isEditMode { setupBottomBar() }
    }

    override func setupBindings() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRolesChanged),
            name: .mezonRolesDidChange, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadFromStore()
        if !isEditMode {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleKeyboardFrameChange(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
        }
        if isEditMode, let role = role, role.roleUserList.roleUsers.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await self.repository.fetchRoleMembers(roleId: self.roleId, clanId: self.clanId)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - Setup

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(
            UIImage(systemName: isEditMode ? "chevron.left" : "xmark")?
                .withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        subtitleLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.textDisabled
        subtitleLabel.textAlignment = .center

        [backButton, titleLabel, subtitleLabel].forEach {
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
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 6.sh),

            subtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.sh)
        ])
    }

    private func setupDescription() {
        descriptionLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = isEditMode ? nil : L(L10n.ClanRoles.membersAddDescription)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: isEditMode ? 0 : 6.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw)
        ])
    }

    private func setupSearch() {
        searchContainer.backgroundColor = UIColor.theme.tertiary
        searchContainer.layer.cornerRadius = 10.swh
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchContainer)

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = UIColor.theme.textDisabled
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(icon)

        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanRoles.membersSearch),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        searchField.textColor = .mezonTextPrimary
        searchField.font = .systemFont(ofSize: 14.sf, weight: .regular)
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.returnKeyType = .search
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 10.sh),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            searchContainer.heightAnchor.constraint(equalToConstant: 40.sh),

            icon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10.sw),
            icon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16.swh),
            icon.heightAnchor.constraint(equalToConstant: 16.swh),

            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8.sw),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10.sw),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])
    }

    private func setupAddButton() {
        addMemberButton.translatesAutoresizingMaskIntoConstraints = false
        addMemberButton.backgroundColor = UIColor.theme.tertiary
        addMemberButton.layer.cornerRadius = 12.swh
        addMemberButton.addTarget(self, action: #selector(openAddMemberSheet), for: .touchUpInside)
        view.addSubview(addMemberButton)

        let topConstant: CGFloat = isEditMode ? 12.sh : 0
        let heightConstant: CGFloat = isEditMode ? 48.sh : 0

        NSLayoutConstraint.activate([
            addMemberButton.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: topConstant),
            addMemberButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            addMemberButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            addMemberButton.heightAnchor.constraint(equalToConstant: heightConstant)
        ])

        guard isEditMode else {
            addMemberButton.isHidden = true
            return
        }

        let icon = UIImageView(image: UIImage(systemName: "plus.circle.fill")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = UIColor.theme.bgViolet
        let label = UILabel()
        label.text = L(L10n.ClanRoles.membersAdd)
        label.textColor = .mezonTextPrimary
        label.font = .systemFont(ofSize: 14.sf, weight: .medium)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textDisabled

        [icon, label, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addMemberButton.addSubview($0)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: addMemberButton.leadingAnchor, constant: 14.sw),
            icon.centerYAnchor.constraint(equalTo: addMemberButton.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22.swh),
            icon.heightAnchor.constraint(equalToConstant: 22.swh),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10.sw),
            label.centerYAnchor.constraint(equalTo: addMemberButton.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: addMemberButton.trailingAnchor, constant: -14.sw),
            chevron.centerYAnchor.constraint(equalTo: addMemberButton.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10.swh),
            chevron.heightAnchor.constraint(equalToConstant: 14.swh)
        ])
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .mezonSecondary
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 64.sh
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(MemberRowCell.self, forCellReuseIdentifier: MemberRowCell.reuseId)
        view.addSubview(tableView)

        let bottomConstraint = tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        tableBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: addMemberButton.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint
        ])
    }

    private func setupBottomBar() {
        bottomBar.axis = .vertical
        bottomBar.spacing = 10.sh
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        finishButton.setTitle(L(L10n.ClanRoles.membersFinish), for: .normal)
        finishButton.setTitleColor(.white, for: .normal)
        finishButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        finishButton.backgroundColor = UIColor.theme.bgViolet
        finishButton.layer.cornerRadius = 12.swh
        finishButton.clipsToBounds = true
        finishButton.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)

        skipButton.setTitle(L(L10n.ClanRoles.skipStep), for: .normal)
        skipButton.setTitleColor(.mezonTextPrimary, for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        skipButton.backgroundColor = UIColor.theme.tertiary
        skipButton.layer.cornerRadius = 12.swh
        skipButton.heightAnchor.constraint(equalToConstant: 46.sh).isActive = true
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        bottomBar.addArrangedSubview(finishButton)
        bottomBar.addArrangedSubview(skipButton)
        view.addSubview(bottomBar)

        let bottomC = bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12.sh)
        bottomBarBottomConstraint = bottomC
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            bottomC,
        ])
        tableBottomConstraint?.isActive = false
        let bottomConstraint = tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8.sh)
        tableBottomConstraint = bottomConstraint
        bottomConstraint.isActive = true
        tableView.contentInset = .zero
        tableView.verticalScrollIndicatorInsets.bottom = 0
    }

    @objc private func handleKeyboardFrameChange(_ notification: Notification) {
        guard let bottomBarBottomConstraint else { return }
        guard let info = notification.userInfo,
            let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        bottomBarBottomConstraint.constant = -12.sh - overlap
        tableView.contentInset.bottom = 0
        tableView.verticalScrollIndicatorInsets.bottom = 0
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveValue = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveValue << 16),
            animations: { self.view.layoutIfNeeded() }
        )
    }

    // MARK: - Data

    @objc private func handleRolesChanged() {
        loadFromStore()
    }

    private func loadFromStore() {
        role = repository.role(roleId: roleId, clanId: clanId)
        canEdit = repository.canManageRoles(clanId: clanId)

        let members = repository.clanMembers(clanId: clanId)
        allMembers = members.sorted { lhs, rhs in
            RoleMemberDisplay.displayName(lhs).localizedCaseInsensitiveCompare(
                RoleMemberDisplay.displayName(rhs)) == .orderedAscending
        }

        if let role {
            let assignedIds = Set(role.roleUserList.roleUsers.map { $0.id })
            assignedMembers = allMembers.filter { assignedIds.contains($0.userId) }
        } else {
            assignedMembers = []
        }

        if isEditMode {
            titleLabel.text = role?.title ?? ""
            subtitleLabel.text = L(L10n.ClanRoles.role)
        } else {
            titleLabel.text = L(L10n.ClanRoles.membersTitle)
            subtitleLabel.text = nil
        }
        applyFilter()
        refreshBottomBar()
    }

    private func applyFilter() {
        if searchText.isEmpty {
            filteredAssigned = assignedMembers
            filteredAll = allMembers
        } else {
            filteredAssigned = assignedMembers.filter { RoleMemberDisplay.matches($0, query: searchText) }
            filteredAll = allMembers.filter { RoleMemberDisplay.matches($0, query: searchText) }
        }
        tableView.reloadData()
    }

    private func refreshBottomBar() {
        let enabled = !selectedIds.isEmpty
        finishButton.isEnabled = enabled
        finishButton.alpha = 1
        finishButton.backgroundColor = enabled ? UIColor.theme.bgViolet : UIColor.theme.tertiary
        finishButton.setTitleColor(enabled ? .white : UIColor.theme.textDisabled, for: .normal)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        if isEditMode {
            navigationController?.popViewController(animated: true)
        } else {
            popToRolesList()
        }
    }

    private func popToRolesList() {
        guard let nav = navigationController else { return }
        if let target = nav.viewControllers.first(where: { $0 is ClanRolesViewController }) {
            nav.popToViewController(target, animated: true)
        } else {
            nav.popToRootViewController(animated: true)
        }
    }

    @objc private func openAddMemberSheet() {
        guard canEdit, let role else { return }
        let assignedIds = Set(role.roleUserList.roleUsers.map { $0.id })
        let candidates = allMembers.filter { !assignedIds.contains($0.userId) }
        let sheet = AddMembersSheetController(candidates: candidates) { [weak self] selected in
            guard let self, !selected.isEmpty else { return }
            self.commitAddMembers(ids: selected)
        }
        present(sheet, animated: true)
    }

    private func commitAddMembers(ids: [Int64]) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.updateRole(
                    roleId: self.roleId,
                    clanId: self.clanId,
                    title: nil,
                    color: nil,
                    roleIcon: nil,
                    addUserIds: ids,
                    activePermissionIds: [],
                    removeUserIds: [],
                    removePermissionIds: []
                )
                Toast.success(L(L10n.ClanRoles.membersAdded))
                self.loadFromStore()
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }

    private func removeMember(_ member: ClanMemberRecord) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.updateRole(
                    roleId: self.roleId,
                    clanId: self.clanId,
                    title: nil,
                    color: nil,
                    roleIcon: nil,
                    addUserIds: [],
                    activePermissionIds: [],
                    removeUserIds: [member.userId],
                    removePermissionIds: []
                )
                self.loadFromStore()
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }

    @objc private func finishTapped() {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.updateRole(
                    roleId: self.roleId,
                    clanId: self.clanId,
                    title: nil,
                    color: nil,
                    roleIcon: nil,
                    addUserIds: ids,
                    activePermissionIds: [],
                    removeUserIds: [],
                    removePermissionIds: []
                )
                Toast.success(L(L10n.ClanRoles.membersAdded))
                self.popToRolesList()
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }

    @objc private func skipTapped() {
        popToRolesList()
    }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
        applyFilter()
    }
}

extension SetupMembersViewController: UITableViewDataSource, UITableViewDelegate {

    private var dataSource: [ClanMemberRecord] {
        isEditMode ? filteredAssigned : filteredAll
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(dataSource.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if dataSource.isEmpty {
            let cell = UITableViewCell()
            cell.backgroundColor = .clear
            cell.textLabel?.text = L(L10n.ClanRoles.membersNotFound)
            cell.textLabel?.textColor = UIColor.theme.textDisabled
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = .systemFont(ofSize: 13.sf, weight: .regular)
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: MemberRowCell.reuseId, for: indexPath) as! MemberRowCell
        let member = dataSource[indexPath.row]
        let accessory: MemberRowCell.Accessory
        if isEditMode {
            accessory = canEdit ? .removeButton : .none
        } else {
            accessory = .checkbox(checked: selectedIds.contains(member.userId))
        }
        cell.configure(
            name: RoleMemberDisplay.displayName(member),
            subtitle: member.username,
            avatarURL: RoleMemberDisplay.avatarURL(member),
            accessory: accessory
        )
        if isEditMode {
            cell.onAccessoryTapped = { [weak self] in
                self?.removeMember(member)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !dataSource.isEmpty else { return }
        let member = dataSource[indexPath.row]
        if isEditMode { return }
        if selectedIds.contains(member.userId) {
            selectedIds.remove(member.userId)
        } else {
            selectedIds.insert(member.userId)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshBottomBar()
    }
}

extension SetupMembersViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
