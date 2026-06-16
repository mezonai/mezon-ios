import UIKit

final class ManageUserViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private var member: ClanMemberRecord
    private let repository: RolesRepository

    private var editMode = false
    private var selectedRoleIds: Set<Int64> = []
    private var isLoading = false

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let padH: CGFloat = 14.sw

    init(context: AccountContext, clanId: Int64, member: ClanMemberRecord) {
        self.context = context
        self.clanId = clanId
        self.member = member
        self.repository = RolesRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        selectedRoleIds = Set(member.roleIds)
        setupHeader()
        setupScrollView()
        buildContent()
    }

    private var boxBackgroundColor: UIColor {
        let theme = ThemeManager.shared.current
        if theme == .light || theme == .sunrise {
            return UIColor.theme.secondary
        } else if theme == .system {
            return UIScreen.main.traitCollection.userInterfaceStyle == .light ? UIColor.theme.secondary : UIColor.theme.tertiary
        } else {
            return UIColor.theme.tertiary
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func applyTheme() {
        super.applyTheme()
        view.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        titleLabel.text = L(L10n.ClanSetting.Members.manageUserTitle)
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

    private func setupScrollView() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20.sh
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: padH),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -padH),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * padH)
        ])
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { contentStack.removeArrangedSubview($0); $0.removeFromSuperview() }

        contentStack.addArrangedSubview(createUserInfoCard())

        contentStack.addArrangedSubview(createRolesSection())

        let actions = createActionsSection()
        if let actions {
            contentStack.addArrangedSubview(actions)
        }
    }

    private func createUserInfoCard() -> UIView {
        let card = UIView()
        card.backgroundColor = boxBackgroundColor
        card.layer.cornerRadius = 14.swh
        card.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10.sw
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let avatarSize: CGFloat = 40.swh
        let textAvatar = TextAvatarView(username: member.username, size: avatarSize)
        textAvatar.translatesAutoresizingMaskIntoConstraints = false

        let avatarImageView = UIImageView()
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        textAvatar.addSubview(avatarImageView)

        NSLayoutConstraint.activate([
            textAvatar.widthAnchor.constraint(equalToConstant: avatarSize),
            textAvatar.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),
        ])

        let priorityName = member.clanNick.isEmpty ? (member.displayName.isEmpty ? member.username : member.displayName) : member.clanNick
        
        let avatarURL = member.clanAvatar.isEmpty ? member.userAvatarURL : member.clanAvatar
        if !avatarURL.isEmpty {
            avatarImageView.isHidden = false
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: avatarURL, width: 100, height: 100)) { image in
                if let image {
                    avatarImageView.image = image
                    textAvatar.showImageMode()
                }
            }
        } else {
            avatarImageView.isHidden = true
            avatarImageView.image = nil
            textAvatar.showPlaceholder()
        }

        stack.addArrangedSubview(textAvatar)

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 2.sh
        let nameLabel = UILabel()
        nameLabel.text = priorityName
        nameLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        nameLabel.textColor = UIColor.theme.textStrong
        textStack.addArrangedSubview(nameLabel)

        let usernameLabel = UILabel()
        usernameLabel.text = member.username
        usernameLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        usernameLabel.textColor = UIColor.theme.textDisabled
        textStack.addArrangedSubview(usernameLabel)

        stack.addArrangedSubview(textStack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12.sh),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12.sh),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12.sw),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12.sw),

        ])

        return card
    }

    private func createRolesSection() -> UIView {
        let section = UIView()

        let sectionTitle = UILabel()
        sectionTitle.text = L(L10n.ClanSetting.Members.roles)
        sectionTitle.font = .systemFont(ofSize: 14.sf, weight: .bold)
        sectionTitle.textColor = UIColor.theme.textStrong
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(sectionTitle)

        let roleListContainer = UIView()
        roleListContainer.backgroundColor = boxBackgroundColor
        roleListContainer.layer.cornerRadius = 10.swh
        roleListContainer.clipsToBounds = true
        roleListContainer.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(roleListContainer)

        let roleStack = UIStackView()
        roleStack.axis = .vertical
        roleStack.translatesAutoresizingMaskIntoConstraints = false
        roleListContainer.addSubview(roleStack)

        let allRoles = repository.roles(clanId: clanId)
        let isClanOwner = repository.isClanOwner(clanId: clanId)
        let userMaxLevel = repository.userMaxPermissionLevel(clanId: clanId)

        if editMode {
            let editableRoles = allRoles.filter { !repository.isEveryone(role: $0) }
            for (i, role) in editableRoles.enumerated() {
                let isSelected = selectedRoleIds.contains(role.id)
                let isDisabled = isLoading || (!isClanOwner && userMaxLevel <= role.maxLevelPermission)
                let row = createEditRoleRow(role: role, isSelected: isSelected, isDisabled: isDisabled)
                roleStack.addArrangedSubview(row)
                if i < editableRoles.count - 1 {
                    let sep = UIView()
                    sep.backgroundColor = UIColor.theme.border
                    sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                    roleStack.addArrangedSubview(sep)
                }
            }
        } else {
            let userRoles = allRoles.filter { selectedRoleIds.contains($0.id) && !repository.isEveryone(role: $0) }
            for (i, role) in userRoles.enumerated() {
                let row = createDisplayRoleRow(role: role)
                roleStack.addArrangedSubview(row)
                if i < userRoles.count - 1 {
                    let sep = UIView()
                    sep.backgroundColor = UIColor.theme.border
                    sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                    roleStack.addArrangedSubview(sep)
                }
            }
        }

        let editSep = UIView()
        editSep.backgroundColor = UIColor.theme.border
        editSep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        roleStack.addArrangedSubview(editSep)

        let editBtn = UIButton(type: .system)
        editBtn.setTitle(editMode ? L(L10n.Common.cancel) : L(L10n.ClanSetting.Members.editRoles), for: .normal)
        editBtn.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .regular)
        editBtn.setTitleColor(UIColor(red: 0.345, green: 0.396, blue: 0.949, alpha: 1), for: .normal)
        editBtn.setTitleColor(UIColor.theme.textDisabled, for: .disabled)
        editBtn.contentHorizontalAlignment = .leading
        editBtn.contentEdgeInsets = UIEdgeInsets(top: 14.sh, left: 14.sw, bottom: 14.sh, right: 14.sw)
        editBtn.isEnabled = !isLoading
        editBtn.addTarget(self, action: #selector(toggleEditMode), for: .touchUpInside)
        roleStack.addArrangedSubview(editBtn)

        NSLayoutConstraint.activate([
            sectionTitle.topAnchor.constraint(equalTo: section.topAnchor),
            sectionTitle.leadingAnchor.constraint(equalTo: section.leadingAnchor),

            roleListContainer.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 8.sh),
            roleListContainer.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            roleListContainer.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            roleListContainer.bottomAnchor.constraint(equalTo: section.bottomAnchor),

            roleStack.topAnchor.constraint(equalTo: roleListContainer.topAnchor),
            roleStack.bottomAnchor.constraint(equalTo: roleListContainer.bottomAnchor),
            roleStack.leadingAnchor.constraint(equalTo: roleListContainer.leadingAnchor),
            roleStack.trailingAnchor.constraint(equalTo: roleListContainer.trailingAnchor),
        ])

        return section
    }

    private func createDisplayRoleRow(role: Mezon_Api_Role) -> UIView {
        let v = UIView()
        let label = UILabel()
        label.text = role.title
        label.font = .systemFont(ofSize: 15.sf, weight: .regular)
        label.textColor = UIColor.theme.textStrong
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 14.sh),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -14.sh),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14.sw),
            label.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -14.sw),
        ])
        return v
    }

    private func createEditRoleRow(role: Mezon_Api_Role, isSelected: Bool, isDisabled: Bool) -> UIView {
        let v = UIView()
        v.tag = Int(role.id)

        let checkBox = UIView()
        checkBox.layer.cornerRadius = 4.swh
        checkBox.layer.borderWidth = 1.5
        checkBox.layer.borderColor = isSelected
            ? UIColor(red: 0.345, green: 0.396, blue: 0.949, alpha: 1).cgColor
            : UIColor.theme.textDisabled.cgColor
        checkBox.backgroundColor = isSelected
            ? UIColor(red: 0.345, green: 0.396, blue: 0.949, alpha: 1)
            : .clear
        checkBox.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(checkBox)

        if isSelected {
            let checkmark = UIImageView(image: UIImage(systemName: "checkmark")?.withRenderingMode(.alwaysTemplate))
            checkmark.tintColor = .white
            checkmark.contentMode = .scaleAspectFit
            checkmark.translatesAutoresizingMaskIntoConstraints = false
            checkBox.addSubview(checkmark)
            NSLayoutConstraint.activate([
                checkmark.centerXAnchor.constraint(equalTo: checkBox.centerXAnchor),
                checkmark.centerYAnchor.constraint(equalTo: checkBox.centerYAnchor),
                checkmark.widthAnchor.constraint(equalToConstant: 12.swh),
                checkmark.heightAnchor.constraint(equalToConstant: 12.swh),
            ])
        }

        let dot = UIView()
        dot.layer.cornerRadius = 6.swh
        dot.backgroundColor = RoleColors.uiColor(forRole: role)
        dot.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(dot)

        let label = UILabel()
        label.text = role.title
        label.font = .systemFont(ofSize: 15.sf, weight: .regular)
        label.textColor = isDisabled ? UIColor.theme.textDisabled : UIColor.theme.textStrong
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)

        let btn = UIButton(type: .custom)
        btn.tag = Int(role.id)
        btn.isEnabled = !isDisabled
        btn.addTarget(self, action: #selector(roleCheckboxTapped(_:)), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(btn)

        NSLayoutConstraint.activate([
            checkBox.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14.sw),
            checkBox.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            checkBox.widthAnchor.constraint(equalToConstant: 20.swh),
            checkBox.heightAnchor.constraint(equalToConstant: 20.swh),

            dot.leadingAnchor.constraint(equalTo: checkBox.trailingAnchor, constant: 10.sw),
            dot.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12.swh),
            dot.heightAnchor.constraint(equalToConstant: 12.swh),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6.sw),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -14.sw),
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 14.sh),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -14.sh),

            btn.topAnchor.constraint(equalTo: v.topAnchor),
            btn.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])

        return v
    }

    private func createActionsSection() -> UIView? {
        let myId = Int64(context.account.id) ?? 0
        let isItMe = member.userId == myId
        let isClanOwner = context.rolePermissions.isClanOwner(clanId: clanId)
        let hasAdmin = context.rolePermissions.hasClanPermission(.administrator, clanId: clanId)

        let clanRecord = context.account.postbox.read({ tx in tx.getClan(id: clanId) })
        let clanOwnerId = clanRecord?.ownerId
        let isThatClanOwner: Bool = {
            guard let ownerId = clanOwnerId, let ownerInt = Int64(ownerId) else { return false }
            return ownerInt == member.userId
        }()

        var actions: [(title: String, icon: String, action: Selector, show: Bool)] = [
            (
                title: L(L10n.ClanSetting.Members.transferOwnership),
                icon: "ClanSetting/TransferOwnerIcon",
                action: #selector(transferOwnershipTapped),
                show: !isItMe && isClanOwner
            ),
            (
                title: L(L10n.ClanSetting.Members.kick),
                icon: "ClanSetting/KickIcon",
                action: #selector(kickTapped),
                show: !isItMe && (isClanOwner || (hasAdmin && !isThatClanOwner))
            )
        ]

        let visibleActions = actions.filter { $0.show }
        guard !visibleActions.isEmpty else { return nil }

        let section = UIView()

        let sectionTitle = UILabel()
        sectionTitle.text = L(L10n.Common.actions)
        sectionTitle.font = .systemFont(ofSize: 14.sf, weight: .bold)
        sectionTitle.textColor = UIColor.theme.textStrong
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(sectionTitle)

        let actionContainer = UIView()
        actionContainer.backgroundColor = boxBackgroundColor
        actionContainer.layer.cornerRadius = 10.swh
        actionContainer.clipsToBounds = true
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(actionContainer)

        let actionStack = UIStackView()
        actionStack.axis = .vertical
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.addSubview(actionStack)

        for (i, item) in visibleActions.enumerated() {
            let row = createActionRow(title: item.title, iconName: item.icon, action: item.action)
            actionStack.addArrangedSubview(row)
            if i < visibleActions.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                actionStack.addArrangedSubview(sep)
            }
        }

        NSLayoutConstraint.activate([
            sectionTitle.topAnchor.constraint(equalTo: section.topAnchor),
            sectionTitle.leadingAnchor.constraint(equalTo: section.leadingAnchor),

            actionContainer.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 8.sh),
            actionContainer.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            actionContainer.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            actionContainer.bottomAnchor.constraint(equalTo: section.bottomAnchor),

            actionStack.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            actionStack.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor),
            actionStack.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
        ])

        return section
    }

    private func createActionRow(title: String, iconName: String, action: Selector) -> UIView {
        let v = UIView()

        var iconImage = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        if iconImage == nil {
            let symbolName = iconName.contains("Transfer") ? "arrow.right.arrow.left" : "person.fill.xmark"
            iconImage = UIImage(systemName: symbolName)?.withRenderingMode(.alwaysTemplate)
        }
        let icon = UIImageView(image: iconImage)
        icon.tintColor = .systemRed
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(icon)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14.sf, weight: .medium)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)

        let btn = UIButton(type: .custom)
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(btn)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14.sw),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22.swh),
            icon.heightAnchor.constraint(equalToConstant: 22.swh),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12.sw),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 14.sh),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -14.sh),

            btn.topAnchor.constraint(equalTo: v.topAnchor),
            btn.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])

        return v
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func toggleEditMode() {
        editMode.toggle()
        buildContent()
    }

    @objc private func roleCheckboxTapped(_ sender: UIButton) {
        guard !isLoading else { return }
        let roleId = Int64(sender.tag)
        let isCurrentlySelected = selectedRoleIds.contains(roleId)

        isLoading = true

        if isCurrentlySelected {
            selectedRoleIds.remove(roleId)
        } else {
            selectedRoleIds.insert(roleId)
        }

        buildContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = self.repository.role(roleId: roleId, clanId: self.clanId)
                if isCurrentlySelected {
                    try await self.repository.updateRole(
                        roleId: roleId, clanId: self.clanId,
                        title: nil, color: nil, roleIcon: nil,
                        addUserIds: [], activePermissionIds: [],
                        removeUserIds: [self.member.userId], removePermissionIds: []
                    )
                } else {
                    try await self.repository.updateRole(
                        roleId: roleId, clanId: self.clanId,
                        title: nil, color: nil, roleIcon: nil,
                        addUserIds: [self.member.userId], activePermissionIds: [],
                        removeUserIds: [], removePermissionIds: []
                    )
                }
                await MainActor.run {
                    self.isLoading = false
                    Toast.success(L(L10n.ClanRoles.saved))
                    self.buildContent()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    if isCurrentlySelected {
                        self.selectedRoleIds.insert(roleId)
                    } else {
                        self.selectedRoleIds.remove(roleId)
                    }
                    Toast.error(L(L10n.ClanRoles.failed))
                    self.buildContent()
                }
            }
        }
    }

    @objc private func transferOwnershipTapped() {
        let vc = TransferOwnershipViewController(context: context, clanId: clanId, targetMember: member)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func kickTapped() {
        let vc = KickMemberViewController(context: context, clanId: clanId, member: member)
        vc.onKickCompleted = { [weak self] in
            self?.navigationController?.popViewController(animated: false)
        }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}
