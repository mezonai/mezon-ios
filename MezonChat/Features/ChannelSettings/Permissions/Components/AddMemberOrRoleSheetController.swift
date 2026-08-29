import UIKit

final class AddMemberOrRoleSheetController: UIViewController {

    private enum Row {
        case sectionHeader(String)
        case role(Mezon_Api_Role)
        case member(ClanMemberRecord)
    }

    private let availableMembers: [ClanMemberRecord]
    private let availableRoles: [Mezon_Api_Role]
    private let onAdd: (_ memberIds: [Int64], _ roleIds: [Int64]) -> Void

    private var selectedMemberIds: Set<Int64> = []
    private var selectedRoleIds: Set<Int64> = []
    private var searchText: String = ""

    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let searchContainer = UIView()
    private let searchField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(
        availableMembers: [ClanMemberRecord],
        availableRoles: [Mezon_Api_Role],
        onAdd: @escaping (_ memberIds: [Int64], _ roleIds: [Int64]) -> Void
    ) {
        self.availableMembers = availableMembers
        self.availableRoles = availableRoles
        self.onAdd = onAdd
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondary
        setupHeader()
        setupSearch()
        setupTable()
        refreshAddButton()
    }

    private func setupHeader() {
        titleLabel.text = L(L10n.ChannelPermission.bsAddMembersOrRoles)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        cancelButton.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelButton.setTitleColor(UIColor.theme.textDisabled, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .regular)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        addButton.setTitle(L(L10n.ChannelPermission.bsAdd), for: .normal)
        addButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        [titleLabel, cancelButton, addButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14.sh),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            addButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])
    }

    private func setupSearch() {
        searchContainer.backgroundColor = UIColor.theme.tertiary
        searchContainer.layer.cornerRadius = 10.swh
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchContainer)

        let icon = UIImageView(image: UIImage.mezonSystemImage("magnifyingglass")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = UIColor.theme.textDisabled
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(icon)

        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ChannelPermission.searchPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        searchField.textColor = .mezonTextPrimary
        searchField.font = .systemFont(ofSize: 14.sf, weight: .regular)
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14.sh),
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

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 60.sh
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(ChannelPermissionRowCell.self, forCellReuseIdentifier: ChannelPermissionRowCell.reuseId)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func refreshAddButton() {
        let enabled = !selectedMemberIds.isEmpty || !selectedRoleIds.isEmpty
        addButton.isEnabled = enabled
        addButton.alpha = enabled ? 1.0 : 0.4
    }

    private func rows() -> [Row] {
        let q = normalize(searchText)
        let filteredRoles = availableRoles.filter {
            q.isEmpty || normalize($0.title).contains(q)
        }
        let filteredMembers = availableMembers.filter { member in
            if q.isEmpty { return true }
            return normalize(RoleMemberDisplay.displayName(member)).contains(q)
                || normalize(member.username).contains(q)
        }
        var out: [Row] = []
        if !filteredRoles.isEmpty {
            out.append(.sectionHeader(L(L10n.ChannelPermission.roles)))
            out.append(contentsOf: filteredRoles.map { .role($0) })
        }
        if !filteredMembers.isEmpty {
            out.append(.sectionHeader(L(L10n.ChannelPermission.members)))
            out.append(contentsOf: filteredMembers.map { .member($0) })
        }
        return out
    }

    private func normalize(_ str: String) -> String {
        str.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
        tableView.reloadData()
    }

    @objc private func addTapped() {
        let memberIds = Array(selectedMemberIds)
        let roleIds = Array(selectedRoleIds)
        let cb = onAdd
        dismiss(animated: true) { cb(memberIds, roleIds) }
    }
}

extension AddMemberOrRoleSheetController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = rows().count
        return max(count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rs = rows()
        if rs.isEmpty {
            let c = UITableViewCell()
            c.backgroundColor = .clear
            c.textLabel?.text = L(L10n.ClanRoles.membersNotFound)
            c.textLabel?.textColor = UIColor.theme.textDisabled
            c.textLabel?.textAlignment = .center
            c.textLabel?.font = .systemFont(ofSize: 13.sf, weight: .regular)
            c.selectionStyle = .none
            return c
        }
        let row = rs[indexPath.row]
        switch row {
        case .sectionHeader(let title):
            let c = UITableViewCell()
            c.backgroundColor = .clear
            c.textLabel?.text = "\(title):"
            c.textLabel?.font = .systemFont(ofSize: 13.sf, weight: .semibold)
            c.textLabel?.textColor = UIColor.theme.textDisabled
            c.selectionStyle = .none
            return c
        case .role(let role):
            let cell = tableView.dequeueReusableCell(withIdentifier: ChannelPermissionRowCell.reuseId, for: indexPath) as! ChannelPermissionRowCell
            cell.configureRole(
                title: role.title,
                color: RoleColors.uiColor(forRole: role),
                trailing: .checkbox(checked: selectedRoleIds.contains(role.id))
            )
            cell.selectionStyle = .none
            return cell
        case .member(let member):
            let cell = tableView.dequeueReusableCell(withIdentifier: ChannelPermissionRowCell.reuseId, for: indexPath) as! ChannelPermissionRowCell
            cell.configureMember(
                name: RoleMemberDisplay.displayName(member),
                subtitle: member.username,
                avatarURL: RoleMemberDisplay.avatarURL(member),
                isOwner: false,
                trailing: .checkbox(checked: selectedMemberIds.contains(member.userId))
            )
            cell.selectionStyle = .none
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let rs = rows()
        guard indexPath.row < rs.count else { return }
        switch rs[indexPath.row] {
        case .role(let role):
            if selectedRoleIds.contains(role.id) {
                selectedRoleIds.remove(role.id)
            } else {
                selectedRoleIds.insert(role.id)
            }
            if let cell = tableView.cellForRow(at: indexPath) as? ChannelPermissionRowCell {
                cell.setTrailing(.checkbox(checked: selectedRoleIds.contains(role.id)))
            }
            refreshAddButton()
        case .member(let member):
            if selectedMemberIds.contains(member.userId) {
                selectedMemberIds.remove(member.userId)
            } else {
                selectedMemberIds.insert(member.userId)
            }
            if let cell = tableView.cellForRow(at: indexPath) as? ChannelPermissionRowCell {
                cell.setTrailing(.checkbox(checked: selectedMemberIds.contains(member.userId)))
            }
            refreshAddButton()
        case .sectionHeader:
            break
        }
    }
}
