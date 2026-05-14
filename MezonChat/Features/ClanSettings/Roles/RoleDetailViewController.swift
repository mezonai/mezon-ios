import UIKit
import AsyncDisplayKit

@MainActor
final class RoleDetailViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let roleId: Int64
    private let repository: RolesRepository

    private var originalTitle: String = ""
    private var currentTitle: String = ""
    private var originalColor: String = ""
    private var currentColor: String = ""

    private var role: Mezon_Api_Role?
    private var canEdit: Bool = false
    private var isEveryone: Bool = false

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let headerTitleLabel = UILabel()
    private let headerSubtitleLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    private let nameField = UITextField()
    private let nameContainer = UIView()
    private let nameCounter = UILabel()

    private let colorRow = UIView()
    private let colorTitleLabel = UILabel()
    private let colorValueLabel = UILabel()
    private let colorIndicator = UIView()
    private let colorLockIcon = UIImageView()

    private let iconRow = UIView()
    private let iconTitleLabel = UILabel()
    private let iconPreview = UIImageView()
    private let iconRemoveButton = UIButton(type: .system)
    private let iconLockIcon = UIImageView()
    private let iconUploadSpinner = UIActivityIndicatorView(style: .medium)
    private var iconLoadTask: URLSessionDataTask?
    private var iconURL: String = ""
    private var isUploadingIcon: Bool = false

    private let actionsContainer = UIView()
    private let permissionsRow = UIView()
    private let permissionsLabel = UILabel()
    private let permissionsLock = UIImageView()
    private let membersRow = UIView()
    private let membersLabel = UILabel()
    private let membersLock = UIImageView()

    private let deleteButton = UIButton(type: .system)

    private let maxNameCharacters = 64

    init(context: AccountContext, clanId: Int64, roleId: Int64) {
        self.context = context
        self.clanId = clanId
        self.roleId = roleId
        self.repository = RolesRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        navigationController?.setNavigationBarHidden(true, animated: false)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16.sh
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        setupHeader()
        setupNameRow()
        setupColorRow()
        setupIconRow()
        setupActionsGroup()
        setupDeleteButton()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8.sh),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32.sh),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
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
        reloadFromStore(resettingDraft: true)
        if let role = role, role.roleUserList.roleUsers.isEmpty, !isEveryone {
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

        backButton.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        headerTitleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        headerTitleLabel.textColor = .mezonTextPrimary
        headerTitleLabel.textAlignment = .center

        headerSubtitleLabel.text = L(L10n.ClanRoles.role)
        headerSubtitleLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        headerSubtitleLabel.textColor = UIColor.theme.textDisabled
        headerSubtitleLabel.textAlignment = .center

        saveButton.setTitle(L(L10n.ClanRoles.save), for: .normal)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        [backButton, headerTitleLabel, headerSubtitleLabel, saveButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            headerTitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            headerTitleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 6.sh),

            headerSubtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            headerSubtitleLabel.topAnchor.constraint(equalTo: headerTitleLabel.bottomAnchor, constant: 2.sh),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])

        stack.addArrangedSubview(headerView)
    }

    private func setupNameRow() {
        nameContainer.backgroundColor = UIColor.theme.tertiary
        nameContainer.layer.cornerRadius = 12.swh

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanRoles.detailRoleName)
        titleLabel.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textDisabled

        nameField.font = .systemFont(ofSize: 15.sf, weight: .regular)
        nameField.textColor = .mezonTextPrimary
        nameField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanRoles.detailRoleName),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.returnKeyType = .done
        nameField.delegate = self

        nameCounter.font = .systemFont(ofSize: 11.sf, weight: .regular)
        nameCounter.textColor = UIColor.theme.textDisabled

        [titleLabel, nameField, nameCounter].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            nameContainer.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: nameContainer.topAnchor, constant: 10.sh),
            titleLabel.leadingAnchor.constraint(equalTo: nameContainer.leadingAnchor, constant: 14.sw),

            nameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4.sh),
            nameField.leadingAnchor.constraint(equalTo: nameContainer.leadingAnchor, constant: 14.sw),
            nameField.trailingAnchor.constraint(equalTo: nameCounter.leadingAnchor, constant: -8.sw),
            nameField.bottomAnchor.constraint(equalTo: nameContainer.bottomAnchor, constant: -12.sh),
            nameField.heightAnchor.constraint(equalToConstant: 24.sh),

            nameCounter.trailingAnchor.constraint(equalTo: nameContainer.trailingAnchor, constant: -14.sw),
            nameCounter.centerYAnchor.constraint(equalTo: nameField.centerYAnchor)
        ])

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        nameContainer.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(nameContainer)
        NSLayoutConstraint.activate([
            nameContainer.topAnchor.constraint(equalTo: wrapper.topAnchor),
            nameContainer.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            nameContainer.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16.sw),
            nameContainer.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16.sw)
        ])
        stack.addArrangedSubview(wrapper)
    }

    private func setupColorRow() {
        colorRow.backgroundColor = UIColor.theme.tertiary
        colorRow.layer.cornerRadius = 12.swh

        colorTitleLabel.text = L(L10n.ClanRoles.colorRow)
        colorTitleLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        colorTitleLabel.textColor = .mezonTextPrimary

        colorValueLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        colorValueLabel.textColor = UIColor.theme.textDisabled

        colorIndicator.layer.cornerRadius = 8.swh
        colorIndicator.layer.borderWidth = 1
        colorIndicator.layer.borderColor = UIColor.theme.borderDim.cgColor

        colorLockIcon.image = UIImage(systemName: "lock.fill")?.withRenderingMode(.alwaysTemplate)
        colorLockIcon.tintColor = UIColor.theme.textDisabled
        colorLockIcon.contentMode = .scaleAspectFit
        colorLockIcon.isHidden = true

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit

        [colorTitleLabel, colorValueLabel, colorIndicator, colorLockIcon, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            colorRow.addSubview($0)
        }

        NSLayoutConstraint.activate([
            colorRow.heightAnchor.constraint(equalToConstant: 56.sh),

            colorTitleLabel.leadingAnchor.constraint(equalTo: colorRow.leadingAnchor, constant: 14.sw),
            colorTitleLabel.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),

            colorLockIcon.leadingAnchor.constraint(equalTo: colorTitleLabel.trailingAnchor, constant: 6.sw),
            colorLockIcon.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),
            colorLockIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            colorLockIcon.heightAnchor.constraint(equalToConstant: 14.swh),

            chevron.trailingAnchor.constraint(equalTo: colorRow.trailingAnchor, constant: -12.sw),
            chevron.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10.swh),
            chevron.heightAnchor.constraint(equalToConstant: 14.swh),

            colorIndicator.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10.sw),
            colorIndicator.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),
            colorIndicator.widthAnchor.constraint(equalToConstant: 16.swh),
            colorIndicator.heightAnchor.constraint(equalToConstant: 16.swh),

            colorValueLabel.trailingAnchor.constraint(equalTo: colorIndicator.leadingAnchor, constant: -8.sw),
            colorValueLabel.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(colorRowTapped))
        colorRow.addGestureRecognizer(tap)

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        colorRow.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(colorRow)
        NSLayoutConstraint.activate([
            colorRow.topAnchor.constraint(equalTo: wrapper.topAnchor),
            colorRow.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            colorRow.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16.sw),
            colorRow.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16.sw)
        ])
        stack.addArrangedSubview(wrapper)
    }

    private func setupIconRow() {
        iconRow.backgroundColor = UIColor.theme.tertiary
        iconRow.layer.cornerRadius = 12.swh

        iconTitleLabel.text = L(L10n.ClanRoles.iconRow)
        iconTitleLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        iconTitleLabel.textColor = .mezonTextPrimary

        iconPreview.contentMode = .scaleAspectFill
        iconPreview.clipsToBounds = true
        iconPreview.layer.cornerRadius = 10.swh
        iconPreview.layer.borderWidth = 1
        iconPreview.layer.borderColor = UIColor.theme.borderDim.cgColor
        iconPreview.backgroundColor = UIColor.theme.secondary
        iconPreview.tintColor = UIColor.theme.textDisabled
        iconPreview.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)

        iconRemoveButton.setImage(
            UIImage(systemName: "xmark.circle.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        iconRemoveButton.tintColor = UIColor.systemRed
        iconRemoveButton.isHidden = true
        iconRemoveButton.addTarget(self, action: #selector(removeIconTapped), for: .touchUpInside)

        iconLockIcon.image = UIImage(systemName: "lock.fill")?.withRenderingMode(.alwaysTemplate)
        iconLockIcon.tintColor = UIColor.theme.textDisabled
        iconLockIcon.contentMode = .scaleAspectFit
        iconLockIcon.isHidden = true

        iconUploadSpinner.hidesWhenStopped = true
        iconUploadSpinner.color = UIColor.theme.textDisabled

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit

        [iconTitleLabel, iconPreview, iconRemoveButton, iconLockIcon, iconUploadSpinner, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            iconRow.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconRow.heightAnchor.constraint(equalToConstant: 60.sh),

            iconTitleLabel.leadingAnchor.constraint(equalTo: iconRow.leadingAnchor, constant: 14.sw),
            iconTitleLabel.centerYAnchor.constraint(equalTo: iconRow.centerYAnchor),

            iconLockIcon.leadingAnchor.constraint(equalTo: iconTitleLabel.trailingAnchor, constant: 6.sw),
            iconLockIcon.centerYAnchor.constraint(equalTo: iconRow.centerYAnchor),
            iconLockIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            iconLockIcon.heightAnchor.constraint(equalToConstant: 14.swh),

            chevron.trailingAnchor.constraint(equalTo: iconRow.trailingAnchor, constant: -12.sw),
            chevron.centerYAnchor.constraint(equalTo: iconRow.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10.swh),
            chevron.heightAnchor.constraint(equalToConstant: 14.swh),

            iconPreview.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10.sw),
            iconPreview.centerYAnchor.constraint(equalTo: iconRow.centerYAnchor),
            iconPreview.widthAnchor.constraint(equalToConstant: 36.swh),
            iconPreview.heightAnchor.constraint(equalToConstant: 36.swh),

            iconRemoveButton.trailingAnchor.constraint(equalTo: iconPreview.leadingAnchor, constant: -8.sw),
            iconRemoveButton.centerYAnchor.constraint(equalTo: iconRow.centerYAnchor),
            iconRemoveButton.widthAnchor.constraint(equalToConstant: 22.swh),
            iconRemoveButton.heightAnchor.constraint(equalToConstant: 22.swh),

            iconUploadSpinner.centerXAnchor.constraint(equalTo: iconPreview.centerXAnchor),
            iconUploadSpinner.centerYAnchor.constraint(equalTo: iconPreview.centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(iconRowTapped))
        iconRow.addGestureRecognizer(tap)

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        iconRow.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(iconRow)
        NSLayoutConstraint.activate([
            iconRow.topAnchor.constraint(equalTo: wrapper.topAnchor),
            iconRow.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            iconRow.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16.sw),
            iconRow.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16.sw)
        ])
        stack.addArrangedSubview(wrapper)
    }

    private func setupActionsGroup() {
        actionsContainer.backgroundColor = UIColor.theme.tertiary
        actionsContainer.layer.cornerRadius = 12.swh
        actionsContainer.clipsToBounds = true

        permissionsLabel.text = L(L10n.ClanRoles.detailPermissions)
        membersLabel.text = L(L10n.ClanRoles.detailMembers)
        for label in [permissionsLabel, membersLabel] {
            label.font = .systemFont(ofSize: 14.sf, weight: .medium)
            label.textColor = .mezonTextPrimary
        }
        for lock in [permissionsLock, membersLock] {
            lock.image = UIImage(systemName: "lock.fill")?.withRenderingMode(.alwaysTemplate)
            lock.tintColor = UIColor.theme.textDisabled
            lock.contentMode = .scaleAspectFit
            lock.isHidden = true
        }

        configureActionRow(permissionsRow, label: permissionsLabel, lock: permissionsLock, selector: #selector(openPermissions))
        configureActionRow(membersRow, label: membersLabel, lock: membersLock, selector: #selector(openMembers))

        let separator = UIView()
        separator.backgroundColor = UIColor.theme.border
        separator.translatesAutoresizingMaskIntoConstraints = false

        [permissionsRow, separator, membersRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            actionsContainer.addSubview($0)
        }

        NSLayoutConstraint.activate([
            permissionsRow.topAnchor.constraint(equalTo: actionsContainer.topAnchor),
            permissionsRow.leadingAnchor.constraint(equalTo: actionsContainer.leadingAnchor),
            permissionsRow.trailingAnchor.constraint(equalTo: actionsContainer.trailingAnchor),
            permissionsRow.heightAnchor.constraint(equalToConstant: 52.sh),

            separator.topAnchor.constraint(equalTo: permissionsRow.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: actionsContainer.leadingAnchor, constant: 14.sw),
            separator.trailingAnchor.constraint(equalTo: actionsContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            membersRow.topAnchor.constraint(equalTo: separator.bottomAnchor),
            membersRow.leadingAnchor.constraint(equalTo: actionsContainer.leadingAnchor),
            membersRow.trailingAnchor.constraint(equalTo: actionsContainer.trailingAnchor),
            membersRow.bottomAnchor.constraint(equalTo: actionsContainer.bottomAnchor),
            membersRow.heightAnchor.constraint(equalToConstant: 52.sh)
        ])

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        actionsContainer.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(actionsContainer)
        NSLayoutConstraint.activate([
            actionsContainer.topAnchor.constraint(equalTo: wrapper.topAnchor),
            actionsContainer.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            actionsContainer.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16.sw),
            actionsContainer.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16.sw)
        ])
        stack.addArrangedSubview(wrapper)
    }

    private func configureActionRow(_ row: UIView, label: UILabel, lock: UIImageView, selector: Selector) {
        label.translatesAutoresizingMaskIntoConstraints = false
        lock.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(lock)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14.sw),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            lock.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6.sw),
            lock.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: 14.swh),
            lock.heightAnchor.constraint(equalToConstant: 14.swh),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14.sw),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10.swh),
            chevron.heightAnchor.constraint(equalToConstant: 14.swh)
        ])

        let tap = UITapGestureRecognizer(target: self, action: selector)
        row.addGestureRecognizer(tap)
    }

    private func setupDeleteButton() {
        deleteButton.setTitle(L(L10n.ClanRoles.detailDelete), for: .normal)
        deleteButton.setTitleColor(UIColor.systemRed, for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        deleteButton.backgroundColor = UIColor.theme.tertiary
        deleteButton.layer.cornerRadius = 12.swh
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            deleteButton.topAnchor.constraint(equalTo: wrapper.topAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16.sw),
            deleteButton.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16.sw),
            deleteButton.heightAnchor.constraint(equalToConstant: 50.sh)
        ])
        stack.addArrangedSubview(wrapper)
    }

    // MARK: - Data

    @objc private func handleRolesChanged() {
        reloadFromStore(resettingDraft: false)
    }

    private func reloadFromStore(resettingDraft: Bool) {
        guard let role = repository.role(roleId: roleId, clanId: clanId) else {
            // role might have been deleted
            navigationController?.popViewController(animated: true)
            return
        }
        self.role = role
        self.isEveryone = repository.isEveryone(role: role)
        self.canEdit = repository.canEditRole(role, clanId: clanId)

        originalTitle = role.title
        originalColor = role.color
        if resettingDraft {
            currentTitle = role.title
            currentColor = role.color
            nameField.text = role.title
            applyIconURL(role.roleIcon)
        }
        refreshUI()
    }

    private func refreshUI() {
        headerTitleLabel.text = currentTitle.isEmpty ? originalTitle : currentTitle
        nameField.isEnabled = canEdit && !isEveryone
        nameField.textColor = nameField.isEnabled ? .mezonTextPrimary : UIColor.theme.textDisabled
        nameCounter.text = "\(currentTitle.count)/\(maxNameCharacters)"

        let hex = currentColor.isEmpty ? RolePermissionConstants.defaultRoleColor : currentColor
        colorIndicator.backgroundColor = UIColor(hexString: hex) ?? .systemGray
        colorValueLabel.text = currentColor.isEmpty ? "" : currentColor.uppercased()
        colorLockIcon.isHidden = canEdit
        colorRow.isUserInteractionEnabled = canEdit

        iconLockIcon.isHidden = canEdit
        iconRow.isUserInteractionEnabled = canEdit && !isUploadingIcon
        iconRemoveButton.isHidden = !canEdit || iconURL.isEmpty || isUploadingIcon
        if isUploadingIcon {
            iconUploadSpinner.startAnimating()
        } else {
            iconUploadSpinner.stopAnimating()
        }

        permissionsLock.isHidden = canEdit
        membersLock.isHidden = canEdit || isEveryone
        membersRow.isHidden = isEveryone

        deleteButton.isHidden = isEveryone || !canEdit

        let dirty = !isNotChanged()
        saveButton.isHidden = !dirty
    }

    private func isNotChanged() -> Bool {
        currentTitle == originalTitle && currentColor == originalColor
    }

    // MARK: - Actions

    @objc private func backTapped() {
        if isNotChanged() {
            navigationController?.popViewController(animated: true)
            return
        }
        MezonConfirm.present(
            from: self,
            title: L(L10n.ClanRoles.detailConfirmSaveTitle),
            content: L(L10n.ClanRoles.detailConfirmSaveContent),
            confirmTitle: L(L10n.ClanRoles.detailConfirmSaveYes),
            cancelTitle: L(L10n.ClanRoles.detailConfirmSaveDiscard),
            onConfirm: { [weak self] in self?.saveTapped() },
            onCancel: { [weak self] in self?.navigationController?.popViewController(animated: true) }
        )
    }

    @objc private func saveTapped() {
        guard !isNotChanged() else { return }
        let titleChanged = currentTitle != originalTitle
        let colorChanged = currentColor != originalColor
        let titleValue = titleChanged ? currentTitle : nil
        let colorValue = colorChanged ? currentColor : nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.updateRole(
                    roleId: self.roleId,
                    clanId: self.clanId,
                    title: titleValue,
                    color: colorValue,
                    roleIcon: nil,
                    addUserIds: [],
                    activePermissionIds: [],
                    removeUserIds: [],
                    removePermissionIds: []
                )
                Toast.success(L(L10n.ClanRoles.saved))
                self.originalTitle = self.currentTitle
                self.originalColor = self.currentColor
                self.refreshUI()
                self.navigationController?.popViewController(animated: true)
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }

    @objc private func nameChanged() {
        let raw = nameField.text ?? ""
        let trimmed = String(raw.prefix(maxNameCharacters))
        if trimmed != raw {
            nameField.text = trimmed
        }
        currentTitle = trimmed
        refreshUI()
    }

    @objc private func colorRowTapped() {
        guard canEdit else { return }
        let picker = RoleColorPickerSheetController(initialColor: currentColor) { [weak self] hex in
            self?.currentColor = hex
            self?.refreshUI()
        }
        present(picker, animated: true)
    }

    @objc private func openPermissions() {
        guard canEdit else { return }
        let vc = SetupPermissionsViewController(
            context: context, clanId: clanId, mode: .edit(roleId: roleId))
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func openMembers() {
        guard canEdit, !isEveryone else { return }
        let vc = SetupMembersViewController(
            context: context, clanId: clanId, mode: .edit(roleId: roleId))
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func deleteTapped() {
        guard canEdit, !isEveryone else { return }
        MezonConfirm.present(
            from: self,
            title: L(L10n.ClanRoles.detailDeleteTitle),
            content: L(L10n.ClanRoles.detailDeleteMessage),
            confirmTitle: L(L10n.ClanRoles.detailDeleteConfirm),
            isDanger: true,
            onConfirm: { [weak self] in self?.performDelete() }
        )
    }

    private func performDelete() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.deleteRole(roleId: self.roleId, clanId: self.clanId)
                self.navigationController?.popViewController(animated: true)
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }
}

extension RoleDetailViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Role icon

extension RoleDetailViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    fileprivate func applyIconURL(_ url: String) {
        iconURL = url
        iconLoadTask?.cancel()
        if url.isEmpty {
            iconPreview.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
            iconPreview.tintColor = UIColor.theme.textDisabled
            return
        }
        let resolved = ImgproxyURL.create(from: url, width: 100, height: 100)
        iconLoadTask = ImageCache.shared.loadImage(urlString: resolved) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                if let image {
                    self.iconPreview.image = image
                    self.iconPreview.tintColor = nil
                }
            }
        }
    }

    @objc fileprivate func iconRowTapped() {
        guard canEdit, !isUploadingIcon else { return }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        present(picker, animated: true)
    }

    @objc fileprivate func removeIconTapped() {
        guard canEdit, !isUploadingIcon else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.updateRole(
                    roleId: self.roleId,
                    clanId: self.clanId,
                    title: nil,
                    color: nil,
                    roleIcon: "",
                    addUserIds: [],
                    activePermissionIds: [],
                    removeUserIds: [],
                    removePermissionIds: []
                )
                self.applyIconURL("")
                self.refreshUI()
            } catch {
                Toast.error(L(L10n.ClanRoles.iconFailed))
            }
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
    ) {
        picker.dismiss(animated: true)
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let image else { return }
        let resized = Self.resizedImage(image, maxSide: 512)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        uploadIcon(image: resized, data: data)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func uploadIcon(image: UIImage, data: Data) {
        isUploadingIcon = true
        refreshUI()
        let filename = "role_icon_\(roleId)_\(Int(Date().timeIntervalSince1970)).jpg"
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isUploadingIcon = false
                self.refreshUI()
            }
            do {
                guard let token = await self.context.getToken() else {
                    Toast.error(L(L10n.ClanRoles.iconFailed))
                    return
                }
                let upload = try await self.context.account.network.uploadAttachmentFile(
                    filename: filename, filetype: "image/jpeg", size: data.count,
                    width: Int(image.size.width), height: Int(image.size.height), token: token
                )
                try await self.context.account.network.uploadToMinIO(
                    url: upload.url, data: data, contentType: "image/jpeg"
                )
                let cdnURL = "\(MezonConfig.baseImgURL)/\(upload.filename)"
                ImageCache.shared.setImage(image, data: data, forKey: cdnURL)

                try await self.repository.updateRole(
                    roleId: self.roleId,
                    clanId: self.clanId,
                    title: nil,
                    color: nil,
                    roleIcon: cdnURL,
                    addUserIds: [],
                    activePermissionIds: [],
                    removeUserIds: [],
                    removePermissionIds: []
                )
                self.applyIconURL(cdnURL)
            } catch {
                Toast.error(L(L10n.ClanRoles.iconFailed))
            }
        }
    }

    private static func resizedImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let maxDim = max(size.width, size.height)
        guard maxDim > maxSide, maxDim > 0 else { return image }
        let scale = maxSide / maxDim
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
