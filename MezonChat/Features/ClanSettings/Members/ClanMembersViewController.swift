import UIKit

final class ClanMembersViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    private let context: AccountContext
    private let clanId: Int64

    private var allMembers: [ClanMemberRecord] = []
    private var filteredMembers: [ClanMemberRecord] = []
    private var roles: [Mezon_Api_Role] = []
    private var searchText = ""
    private var searchDebounceTimer: Foundation.Timer?

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let searchContainer = UIView()
    private let searchField = UITextField()
    private let searchClearButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateLabel = UILabel()

    private let padH: CGFloat = 12.sw

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupSearchField()
        setupTableView()
        setupEmptyState()
        loadMembers()
        loadRoles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        loadMembers()
    }

    override func setupBindings() {
        disposables.add((context.engine.clanData.clanUsersUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, updatedClanId == self.clanId else { return }
                self.loadMembers()
            }))
        disposables.add((context.engine.clanData.clanRolesUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, updatedClanId == self.clanId else { return }
                self.loadRoles()
                self.tableView.reloadData()
            }))
    }

    override func applyTheme() {
        super.applyTheme()
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        searchContainer.backgroundColor = t.tertiary
        searchField.textColor = t.textStrong
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanSetting.Members.searchPlaceholder),
            attributes: [.foregroundColor: t.textDisabled]
        )
        tableView.backgroundColor = t.primary
        tableView.reloadData()
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        titleLabel.text = L(L10n.ClanSetting.Members.title)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24.swh),
            backButton.heightAnchor.constraint(equalToConstant: 24.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupSearchField() {
        searchContainer.backgroundColor = UIColor.theme.tertiary
        searchContainer.layer.cornerRadius = 12.swh
        searchContainer.clipsToBounds = true
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchContainer)

        searchField.placeholder = L(L10n.ClanSetting.Members.searchPlaceholder)
        searchField.font = .systemFont(ofSize: 14.sf, weight: .regular)
        searchField.textColor = UIColor.theme.textStrong
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanSetting.Members.searchPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .never
        searchField.autocorrectionType = .no
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        let config = MezonSymbolConfiguration(pointSize: 10.sf, weight: .bold)
        searchClearButton.setImage(UIImage.mezonSystemImage("xmark", withConfiguration: config), for: .normal)
        searchClearButton.tintColor = UIColor.theme.iconSecondary
        searchClearButton.backgroundColor = UIColor.theme.border
        searchClearButton.layer.cornerRadius = 10.swh
        searchClearButton.translatesAutoresizingMaskIntoConstraints = false
        searchClearButton.isHidden = true
        searchClearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        searchContainer.addSubview(searchClearButton)

        let searchIcon = UIImageView(image: UIImage.mezonSystemImage("magnifyingglass")?.withRenderingMode(.alwaysTemplate))
        searchIcon.tintColor = UIColor.theme.textDisabled
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchIcon)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10.sh),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padH),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padH),
            searchContainer.heightAnchor.constraint(equalToConstant: 44.sh),

            searchClearButton.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12.sw),
            searchClearButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchClearButton.widthAnchor.constraint(equalToConstant: 20.swh),
            searchClearButton.heightAnchor.constraint(equalToConstant: 20.swh),

            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10.sw),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16.swh),
            searchIcon.heightAnchor.constraint(equalToConstant: 16.swh),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8.sw),
            searchField.trailingAnchor.constraint(equalTo: searchClearButton.leadingAnchor, constant: -8.sw),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = UIColor.theme.primary
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.theme.border
        tableView.separatorInset = .zero
        tableView.register(MemberCell.self, forCellReuseIdentifier: MemberCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72.sh
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyStateLabel.text = L(L10n.ClanRoles.membersNotFound)
        emptyStateLabel.textColor = UIColor.theme.textDisabled
        emptyStateLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -20.sh)
        ])
    }

    private func loadMembers() {
        allMembers = context.engine.account.postbox.read { $0.getClanMembers(clanId: clanId) }
        applyFilter()
    }

    private func loadRoles() {
        if let response = context.engine.clanData.getClanRoles(clanId: clanId) {
            roles = response.roles.roles.filter { $0.active != 0 }.sorted {
                if $0.orderRole != $1.orderRole { return $0.orderRole < $1.orderRole }
                return $0.id < $1.id
            }
        }
    }

    private func applyFilter() {
        if searchText.isEmpty {
            filteredMembers = allMembers
        } else {
            filteredMembers = allMembers.filter { RoleMemberDisplay.matches($0, query: searchText) }
        }
        tableView.reloadData()

        let isSearchEmpty = searchText.isEmpty
        if !isSearchEmpty && filteredMembers.isEmpty {
            emptyStateLabel.isHidden = false
            tableView.isHidden = true
        } else {
            emptyStateLabel.isHidden = true
            tableView.isHidden = false
        }
    }

    private func canManageMembers() -> Bool {
        context.rolePermissions.isClanOwner(clanId: clanId) ||
        context.rolePermissions.hasClanPermission(.administrator, clanId: clanId) ||
        context.rolePermissions.canManageClan(clanId: clanId)
    }

    private func rolesForMember(_ member: ClanMemberRecord) -> [Mezon_Api_Role] {
        return roles.filter { role in
            if role.slug == "everyone-\(role.clanID)" { return false }
            if role.hasRoleUserList {
                return role.roleUserList.roleUsers.contains { $0.id == member.userId }
            }
            return member.roleIds.contains(role.id)
        }
    }

    @objc private func clearSearchTapped() {
        searchField.text = ""
        searchText = ""
        searchClearButton.isHidden = true
        applyFilter()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func searchTextChanged() {
        searchClearButton.isHidden = (searchField.text ?? "").isEmpty
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.searchText = (self.searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.applyFilter()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredMembers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MemberCell.reuseId, for: indexPath) as! MemberCell
        let member = filteredMembers[indexPath.row]
        let memberRoles = rolesForMember(member)
        cell.configure(member: member, roles: memberRoles, showChevron: canManageMembers())

        if indexPath.row == filteredMembers.count - 1 {
            cell.separatorInset = UIEdgeInsets(top: 0, left: tableView.bounds.width + 1000, bottom: 0, right: 0)
        } else {
            cell.separatorInset = .zero
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard canManageMembers() else { return }
        let member = filteredMembers[indexPath.row]
        let vc = ManageUserViewController(context: context, clanId: clanId, member: member)
        navigationController?.pushViewController(vc, animated: true)
    }
}

private final class MemberCell: UITableViewCell {
    static let reuseId = "MemberCell"

    private let textAvatar = TextAvatarView(username: "", size: 40.swh)
    private let avatarView = UIImageView()
    private let displayNameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let roleWrapView = UIStackView()
    private let chevronView = UIImageView()
    private let avatarSize: CGFloat = 40.swh

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupCell() {
        backgroundColor = UIColor.theme.primary
        selectionStyle = .none

        let containerStack = UIStackView()
        containerStack.axis = .horizontal
        containerStack.alignment = .center
        containerStack.spacing = 10.sw
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerStack)

        textAvatar.translatesAutoresizingMaskIntoConstraints = false

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = avatarSize / 2
        textAvatar.addSubview(avatarView)
        
        NSLayoutConstraint.activate([
            textAvatar.widthAnchor.constraint(equalToConstant: avatarSize),
            textAvatar.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),
            avatarView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),
        ])

        containerStack.addArrangedSubview(textAvatar)

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2.sh
        textStack.alignment = .leading

        displayNameLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        displayNameLabel.textColor = UIColor.theme.textStrong

        usernameLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        usernameLabel.textColor = UIColor.theme.textDisabled

        roleWrapView.axis = .vertical
        roleWrapView.spacing = 6.sh
        roleWrapView.alignment = .leading
        roleWrapView.translatesAutoresizingMaskIntoConstraints = false

        textStack.addArrangedSubview(displayNameLabel)
        textStack.addArrangedSubview(usernameLabel)
        textStack.addArrangedSubview(roleWrapView)
        textStack.setCustomSpacing(6.sh, after: usernameLabel)

        containerStack.addArrangedSubview(textStack)

        let arrowImage = UIImage(named: "Channel/ChevronRight")?.withRenderingMode(.alwaysTemplate) ?? UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate)
        chevronView.image = arrowImage
        chevronView.tintColor = UIColor.theme.textStrong
        chevronView.contentMode = .scaleAspectFit
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(chevronView)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.sh),
            containerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10.sh),
            containerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12.sw),
            containerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),



            chevronView.widthAnchor.constraint(equalToConstant: 16.swh),
            chevronView.heightAnchor.constraint(equalToConstant: 16.swh)
        ])
    }

    func configure(member: ClanMemberRecord, roles: [Mezon_Api_Role], showChevron: Bool) {
        let name = member.clanNick.isEmpty ? member.displayName : member.clanNick
        let priorityName = name.isEmpty ? member.username : name
        displayNameLabel.text = priorityName
        usernameLabel.text = member.username

        chevronView.isHidden = !showChevron

        let avatarURL = member.clanAvatar.isEmpty ? member.userAvatarURL : member.clanAvatar
        textAvatar.configure(username: member.username)
        
        if !avatarURL.isEmpty {
            avatarView.isHidden = false
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: avatarURL, width: 100, height: 100)) { [weak self] image in
                if let image {
                    self?.avatarView.image = image
                    self?.textAvatar.showImageMode()
                }
            }
        } else {
            avatarView.image = nil
            avatarView.isHidden = true
            textAvatar.showPlaceholder()
        }

        roleWrapView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        roleWrapView.isHidden = roles.isEmpty
        
        let availableWidth = UIScreen.main.bounds.width - 104.sw
        var currentLineStack = UIStackView()
        currentLineStack.axis = .horizontal
        currentLineStack.spacing = 6.sw
        currentLineStack.alignment = .center
        roleWrapView.addArrangedSubview(currentLineStack)
        
        var currentLineWidth: CGFloat = 0
        
        for role in roles {
            let badge = createRoleBadge(role: role)
            badge.layoutIfNeeded()
            let badgeWidth = badge.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            
            if currentLineWidth + badgeWidth > availableWidth && currentLineWidth > 0 {
                currentLineStack = UIStackView()
                currentLineStack.axis = .horizontal
                currentLineStack.spacing = 6.sw
                currentLineStack.alignment = .center
                roleWrapView.addArrangedSubview(currentLineStack)
                currentLineWidth = 0
            }
            
            currentLineStack.addArrangedSubview(badge)
            currentLineWidth += badgeWidth + 6.sw
        }
    }

    private func createRoleBadge(role: Mezon_Api_Role) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.theme.tertiary
        container.layer.cornerRadius = 6.swh
        container.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4.sw
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let dot = UIView()
        dot.layer.cornerRadius = 5.swh
        dot.backgroundColor = RoleColors.uiColor(forRole: role)
        dot.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(dot)
        
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10.swh),
            dot.heightAnchor.constraint(equalToConstant: 10.swh)
        ])

        let rawURL = role.roleIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL = SharingImageProxy.resolvedAssetURLString(rawURL)
        if !resolvedURL.isEmpty {
            let iconImageView = UIImageView()
            iconImageView.contentMode = .scaleAspectFill
            iconImageView.clipsToBounds = true
            iconImageView.layer.cornerRadius = 7.swh
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            
            let url = ImgproxyURL.create(from: resolvedURL, width: 40, height: 40)
            ImageCache.shared.loadImage(urlString: url) { [weak iconImageView] image in
                DispatchQueue.main.async {
                    if let image = image {
                        iconImageView?.image = image
                    }
                }
            }
            stack.addArrangedSubview(iconImageView)
            
            NSLayoutConstraint.activate([
                iconImageView.widthAnchor.constraint(equalToConstant: 14.swh),
                iconImageView.heightAnchor.constraint(equalToConstant: 14.swh)
            ])
        }

        let label = UILabel()
        label.text = role.title
        label.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        label.textColor = UIColor.theme.textStrong
        label.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(label)

        label.widthAnchor.constraint(lessThanOrEqualToConstant: 200.sw).isActive = true

        stack.layoutIfNeeded()
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        container.frame = CGRect(origin: .zero, size: CGSize(width: size.width + 12.sw, height: size.height + 8.sh))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6.sw),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6.sw),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4.sh),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4.sh),
        ])

        return container
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.image = nil
        avatarView.isHidden = true
        displayNameLabel.text = nil
        usernameLabel.text = nil
        roleWrapView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chevronView.isHidden = false
    }
}
