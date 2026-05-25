import UIKit
import AsyncDisplayKit

@MainActor
final class SetupPermissionsViewController: BaseViewController {

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
    private var hasAdministrator: Bool = false
    private var hasManageClan: Bool = false
    private var isClanOwner: Bool = false

    private var allPermissions: [Mezon_Api_Permission] = []
    private var filteredPermissions: [Mezon_Api_Permission] = []
    private var originalSelectedIDs: Set<Int64> = []
    private var selectedIDs: Set<Int64> = []
    private var searchText: String = ""

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    private let searchField = UITextField()
    private let searchContainer = UIView()
    private let headingLabel = UILabel()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let bottomBar = UIStackView()
    private let nextButton = UIButton(type: .custom)
    private let skipButton = UIButton(type: .system)
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private let tableBottomInsetWithBar: CGFloat = 130.sh

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
        setupHeading()
        setupSearch()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardFrameChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        loadFromStore(resettingDraft: true)
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

        saveButton.setTitle(L(L10n.ClanRoles.save), for: .normal)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.isHidden = true

        [backButton, titleLabel, subtitleLabel, saveButton].forEach {
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
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.sh),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupHeading() {
        headingLabel.text = L(L10n.ClanRoles.permissionsHeading)
        headingLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        headingLabel.textColor = UIColor.theme.textDisabled
        headingLabel.numberOfLines = 0
        headingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headingLabel)
        NSLayoutConstraint.activate([
            headingLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 6.sh),
            headingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12.sw),
            headingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12.sw)
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
            string: L(L10n.ClanRoles.permissionsSearch),
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
            searchContainer.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 12.sh),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12.sw),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12.sw),
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
        tableView.backgroundColor = .mezonSecondary
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 72.sh
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        tableView.cellLayoutMarginsFollowReadableWidth = false
        tableView.register(PermissionRowCell.self, forCellReuseIdentifier: PermissionRowCell.reuseId)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBottomBar() {
        bottomBar.axis = .vertical
        bottomBar.spacing = 10.sh
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        nextButton.setTitle(L(L10n.ClanRoles.permissionsNext), for: .normal)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        nextButton.backgroundColor = UIColor.theme.bgViolet
        nextButton.layer.cornerRadius = 12.swh
        nextButton.clipsToBounds = true
        nextButton.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        skipButton.setTitle(L(L10n.ClanRoles.skipStep), for: .normal)
        skipButton.setTitleColor(.mezonTextPrimary, for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        skipButton.backgroundColor = UIColor.theme.tertiary
        skipButton.layer.cornerRadius = 12.swh
        skipButton.heightAnchor.constraint(equalToConstant: 46.sh).isActive = true
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        bottomBar.addArrangedSubview(nextButton)
        bottomBar.addArrangedSubview(skipButton)

        view.addSubview(bottomBar)
        let bottomC = bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12.sh)
        bottomBarBottomConstraint = bottomC
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12.sw),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12.sw),
            bottomC,
        ])

        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: tableBottomInsetWithBar, right: 0)
        tableView.verticalScrollIndicatorInsets.bottom = tableBottomInsetWithBar
    }

    @objc private func handleKeyboardFrameChange(_ notification: Notification) {
        guard let info = notification.userInfo,
            let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        bottomBarBottomConstraint?.constant = -12.sh - overlap
        let baseInset: CGFloat = isEditMode ? 0 : tableBottomInsetWithBar
        let insetBottom = baseInset + overlap
        tableView.contentInset.bottom = insetBottom
        tableView.verticalScrollIndicatorInsets.bottom = insetBottom
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
        loadFromStore(resettingDraft: false)
    }

    private func loadFromStore(resettingDraft: Bool) {
        role = repository.role(roleId: roleId, clanId: clanId)
        canEdit = repository.canManageRoles(clanId: clanId)
        isClanOwner = repository.isClanOwner(clanId: clanId)
        hasAdministrator = repository.hasClanPermission(.administrator, clanId: clanId)
        hasManageClan = repository.hasClanPermission(.manageClan, clanId: clanId)

        allPermissions = repository.allPermissions()

        if let role {
            let active = role.permissionList.permissions.filter { $0.active != 0 }
            let activeIds = Set(active.map { $0.id })
            originalSelectedIDs = activeIds
            if resettingDraft {
                selectedIDs = activeIds
            }
        }

        if isEditMode {
            titleLabel.text = role?.title ?? ""
            subtitleLabel.text = L(L10n.ClanRoles.role)
        } else {
            titleLabel.text = L(L10n.ClanRoles.permissionsTitle)
            subtitleLabel.text = nil
        }

        applyFilter()
        refreshSaveButton()
    }

    private func applyFilter() {
        let q = searchText.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if q.isEmpty {
            filteredPermissions = allPermissions
        } else {
            filteredPermissions = allPermissions.filter { perm in
                let title = RolePermissionLocalization.title(forSlug: perm.slug, fallback: perm.title)
                return title.folding(options: .diacriticInsensitive, locale: .current)
                    .lowercased().contains(q)
            }
        }
        tableView.reloadData()
    }

    private func refreshSaveButton() {
        let dirty = originalSelectedIDs != selectedIDs
        saveButton.isHidden = !(isEditMode && dirty)
        let nextEnabled = !selectedIDs.isEmpty
        nextButton.isEnabled = nextEnabled
        nextButton.alpha = 1
        nextButton.backgroundColor = nextEnabled ? UIColor.theme.bgViolet : UIColor.theme.tertiary
        nextButton.setTitleColor(nextEnabled ? .white : UIColor.theme.textDisabled, for: .normal)
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

    @objc private func saveTapped() {
        let add = Array(selectedIDs.subtracting(originalSelectedIDs))
        let remove = Array(originalSelectedIDs.subtracting(selectedIDs))
        guard !add.isEmpty || !remove.isEmpty else { return }

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
                    activePermissionIds: add,
                    removeUserIds: [],
                    removePermissionIds: remove
                )
                Toast.success(L(L10n.ClanRoles.saved))
                self.originalSelectedIDs = self.selectedIDs
                self.refreshSaveButton()
                self.navigationController?.popViewController(animated: true)
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }

    @objc private func nextTapped() {
        let add = Array(selectedIDs.subtracting(originalSelectedIDs))
        let remove = Array(originalSelectedIDs.subtracting(selectedIDs))
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
                    activePermissionIds: add,
                    removeUserIds: [],
                    removePermissionIds: remove
                )
                let next = SetupMembersViewController(
                    context: self.context, clanId: self.clanId, mode: .wizard(roleId: self.roleId))
                self.navigationController?.pushViewController(next, animated: true)
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
    }

    @objc private func skipTapped() {
        let next = SetupMembersViewController(
            context: context, clanId: clanId, mode: .wizard(roleId: roleId))
        navigationController?.pushViewController(next, animated: true)
    }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
        applyFilter()
    }

    fileprivate func isPermissionDisabled(_ permission: Mezon_Api_Permission) -> Bool {
        RolePermissionLocalization.isDisabledFor(
            permission: permission,
            role: role,
            isClanOwner: isClanOwner,
            hasAdministrator: hasAdministrator,
            hasManageClan: hasManageClan,
            canEdit: canEdit
        )
    }

    fileprivate func togglePermission(_ permission: Mezon_Api_Permission) {
        guard !isPermissionDisabled(permission) else { return }
        if selectedIDs.contains(permission.id) {
            selectedIDs.remove(permission.id)
        } else {
            selectedIDs.insert(permission.id)
        }
        refreshSaveButton()
        if let idx = filteredPermissions.firstIndex(where: { $0.id == permission.id }) {
            tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
        }
    }
}

extension SetupPermissionsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredPermissions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PermissionRowCell.reuseId, for: indexPath) as! PermissionRowCell
        let perm = filteredPermissions[indexPath.row]
        cell.configure(
            title: RolePermissionLocalization.title(forSlug: perm.slug, fallback: perm.title),
            description: RolePermissionLocalization.description(forSlug: perm.slug),
            isOn: selectedIDs.contains(perm.id),
            isDisabled: isPermissionDisabled(perm)
        )
        cell.onToggle = { [weak self] _ in
            self?.togglePermission(perm)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.preservesSuperviewLayoutMargins = false
        cell.layoutMargins = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        cell.separatorInset = .zero
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        togglePermission(filteredPermissions[indexPath.row])
    }
}

extension SetupPermissionsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private final class PermissionRowCell: UITableViewCell {

    static let reuseId = "PermissionRowCell"

    private let titleRowStack = UIStackView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let lockIcon = UIImageView()
    private let toggle = FlatPermissionSwitch()

    var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let bg = UIView()
        bg.backgroundColor = UIColor.theme.tertiary.withAlphaComponent(0.6)
        selectedBackgroundView = bg
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggle = nil
    }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        descriptionLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0
        descriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        lockIcon.image = UIImage(systemName: "lock.fill")?.withRenderingMode(.alwaysTemplate)
        lockIcon.tintColor = UIColor.theme.textDisabled
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.isHidden = true
        lockIcon.setContentHuggingPriority(.required, for: .horizontal)
        lockIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleRowStack.axis = .horizontal
        titleRowStack.alignment = .center
        titleRowStack.spacing = 6.sw
        titleRowStack.addArrangedSubview(titleLabel)
        titleRowStack.addArrangedSubview(lockIcon)

        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        [titleRowStack, descriptionLabel, toggle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleRowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12.sh),
            titleRowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10.sw),
            titleRowStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10.sw),

            lockIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            lockIcon.heightAnchor.constraint(equalToConstant: 14.swh),

            descriptionLabel.topAnchor.constraint(equalTo: titleRowStack.bottomAnchor, constant: 4.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleRowStack.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10.sw),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12.sh),

            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10.sw),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(title: String, description: String, isOn: Bool, isDisabled: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        toggle.setOn(isOn, animated: false)
        toggle.isEnabled = !isDisabled
        lockIcon.isHidden = !isDisabled
        titleLabel.textColor = isDisabled ? UIColor.theme.textDisabled : .mezonTextPrimary
    }

    @objc private func switchChanged(_ sender: FlatPermissionSwitch) {
        onToggle?(sender.isOn)
    }
}

private final class FlatPermissionSwitch: UIControl {

    private let trackView = UIView()
    private let thumbView = UIView()
    private(set) var isOn = false

    override var intrinsicContentSize: CGSize {
        CGSize(width: 52, height: 32)
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance(animated: false)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted && self.isEnabled ? 0.82 : 1.0
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        trackView.isUserInteractionEnabled = false
        trackView.layer.masksToBounds = true
        addSubview(trackView)

        thumbView.isUserInteractionEnabled = false
        thumbView.layer.masksToBounds = true
        addSubview(thumbView)

        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAppearance(animated: false)
    }

    func setOn(_ isOn: Bool, animated: Bool) {
        guard self.isOn != isOn else {
            updateAppearance(animated: false)
            return
        }
        self.isOn = isOn
        updateAppearance(animated: animated)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        isHighlighted = true
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        defer { isHighlighted = false }
        guard isEnabled, let location = touch?.location(in: self),
              bounds.insetBy(dx: -12, dy: -12).contains(location) else {
            return
        }
        setOn(!isOn, animated: true)
        sendActions(for: .valueChanged)
    }

    override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
    }

    private func updateAppearance(animated: Bool) {
        let trackHeight = max(0, min(bounds.height - 4, 28))
        let thumbDiameter = max(0, trackHeight - 2)
        let horizontalInset: CGFloat = 3
        let trackFrame = CGRect(
            x: 0,
            y: (bounds.height - trackHeight) / 2,
            width: bounds.width,
            height: trackHeight
        )
        let thumbX = isOn
            ? bounds.width - thumbDiameter - horizontalInset
            : horizontalInset
        let thumbFrame = CGRect(
            x: thumbX,
            y: (bounds.height - thumbDiameter) / 2,
            width: thumbDiameter,
            height: thumbDiameter
        )

        let trackColor: UIColor
        let thumbColor: UIColor
        if isEnabled {
            trackColor = isOn ? UIColor.theme.bgViolet : UIColor.theme.tertiary.withAlphaComponent(0.72)
            thumbColor = .white
        } else {
            trackColor = isOn ? UIColor.theme.bgViolet.withAlphaComponent(0.38) : UIColor.theme.tertiary.withAlphaComponent(0.55)
            thumbColor = UIColor.theme.textDisabled
        }

        let changes = {
            self.trackView.frame = trackFrame
            self.trackView.layer.cornerRadius = trackHeight / 2
            self.trackView.backgroundColor = trackColor
            self.thumbView.frame = thumbFrame
            self.thumbView.layer.cornerRadius = thumbDiameter / 2
            self.thumbView.backgroundColor = thumbColor
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: changes)
        } else {
            changes()
        }

        accessibilityValue = isOn ? "On" : "Off"
        if isOn {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }
}
