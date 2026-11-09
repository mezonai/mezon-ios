import UIKit

@MainActor
final class ChannelPermissionsViewController: BaseViewController {

    enum Tab: Int {
        case basic = 0
        case advanced = 1
    }

    private let context: AccountContext
    private let repository: ChannelPermissionsRepository
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var isPrivate: Bool

    private var channelMemberIds: Set<Int64> = []
    private var channelRoles: [Mezon_Api_Role] = []
    private var channelMembers: [ClanMemberRecord] = []

    private var fetchMembersTask: Task<Void, Never>?
    private var socketDisposable: Disposable?
    private var privacyUpdateInFlight = false

    private var currentTab: Tab = .basic

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private let tabContainer = UIView()
    private let basicTabButton = UIButton(type: .system)
    private let advancedTabButton = UIButton(type: .system)
    private var tabContainerHeightConstraint: NSLayoutConstraint?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let privateToggleCard = UIView()
    private let privateToggleLabel = UILabel()
    private let privateSwitch = UISwitch()

    private let descriptionLabel = UILabel()
    private let addMemberCard = UIView()
    private let addMemberTitleLabel = UILabel()
    private let addMemberIcon = UIImageView()
    private let addMemberChevron = UIImageView()
    private let whoCanAccessLabel = UILabel()
    private let listCard = UIView()
    private let listContentStack = UIStackView()
    private var listSectionHeaders: [(label: UILabel, localizationKey: String)] = []
    private var listSeparators: [UIView] = []
    private let emptyAdvancedLabel = UILabel()

    init(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        channelType: Int32,
        channelPrivate: Bool
    ) {
        self.context = context
        self.repository = ChannelPermissionsRepository(context: context)
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType
        self.isPrivate = channelPrivate
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        setupHeader()
        setupTabs()
        setupContent()
    }

    override func applyTheme() {
        view.backgroundColor = .mezonSecondary
        headerView.backgroundColor = .mezonSecondary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
        tabContainer.backgroundColor = UIColor.theme.primary
        privateToggleCard.backgroundColor = UIColor.theme.primary
        privateToggleLabel.textColor = UIColor.theme.textStrong
        privateSwitch.onTintColor = UIColor.theme.iconPrimary
        descriptionLabel.textColor = UIColor.theme.textNormal
        addMemberCard.backgroundColor = UIColor.theme.primary
        addMemberTitleLabel.textColor = UIColor.theme.textStrong
        addMemberIcon.tintColor = UIColor.theme.textStrong
        addMemberChevron.tintColor = UIColor.theme.textDisabled
        whoCanAccessLabel.textColor = UIColor.theme.textNormal
        listCard.backgroundColor = UIColor.theme.primary
        emptyAdvancedLabel.textColor = UIColor.theme.textDisabled
        refreshVisibility()
        applyListTheme()
    }

    override func setupBindings() {
        if channelType == MezonConstants.ChannelType.mezonVoice.rawValue {
            socketDisposable = (context.account.socket.events() |> deliverOnMainQueue).start(next: { [weak self] event in
                guard let self else { return }
                switch event {
                case .userChannelAdded(let event) where event.channelDesc.channelID == self.channelId &&
                    event.status != "Add Role Channel":
                    self.fetchMembersTask?.cancel()
                    self.channelMemberIds.formUnion(event.users.map(\.userID))
                    self.reloadLocalData()
                case .channelUpdated(let event) where event.channelID == self.channelId &&
                    event.channelType == MezonConstants.ChannelType.mezonVoice.rawValue &&
                    event.channelPrivate != self.isPrivate:
                    self.fetchMembersTask?.cancel()
                    self.channelMemberIds = event.channelPrivate ? Set(event.userIds) : []
                    self.reloadLocalData()
                default: break
                }
            })
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRolesChanged),
            name: .mezonRolesDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleChannelDescriptionDidUpdate(_:)),
            name: .mezonChannelDescriptionDidUpdate, object: nil
        )
    }

    deinit {
        socketDisposable?.dispose()
        fetchMembersTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupHeader() {
        headerView.backgroundColor = .mezonSecondary
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.text = L(L10n.ChannelPermission.title)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        [backButton, titleLabel].forEach {
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
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupTabs() {
        tabContainer.backgroundColor = UIColor.theme.primary
        tabContainer.layer.cornerRadius = 10.swh
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabContainer)

        styleTab(basicTabButton, title: L(L10n.ChannelPermission.basicView))
        basicTabButton.addTarget(self, action: #selector(selectBasicTab), for: .touchUpInside)

        styleTab(advancedTabButton, title: L(L10n.ChannelPermission.advancedView))
        advancedTabButton.addTarget(self, action: #selector(selectAdvancedTab), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [basicTabButton, advancedTabButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4.sw
        stack.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.addSubview(stack)

        let tabH = tabContainer.heightAnchor.constraint(equalToConstant: 40.sh)
        tabContainerHeightConstraint = tabH

        NSLayoutConstraint.activate([
            tabContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10.sh),
            tabContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tabContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            tabH,

            stack.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 3.sh),
            stack.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: 3.sw),
            stack.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: -3.sw),
            stack.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -3.sh)
        ])
    }

    private func styleTab(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        button.layer.cornerRadius = 8.swh
    }

    private func setupContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12.sh
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: 14.sh),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16.sw),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16.sw),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20.sh)
        ])

        setupPrivateToggleCard()
        setupDescription()
        setupAddMemberCard()
        setupWhoCanAccessLabel()
        setupListCard()
        setupEmptyAdvanced()

        contentStack.addArrangedSubview(privateToggleCard)
        contentStack.addArrangedSubview(descriptionLabel)
        contentStack.addArrangedSubview(addMemberCard)
        contentStack.addArrangedSubview(whoCanAccessLabel)
        contentStack.addArrangedSubview(listCard)
        contentStack.addArrangedSubview(emptyAdvancedLabel)

        applyTabSelection()
    }

    private func setupPrivateToggleCard() {
        privateToggleCard.backgroundColor = UIColor.theme.primary
        privateToggleCard.layer.cornerRadius = 12.swh
        privateToggleCard.translatesAutoresizingMaskIntoConstraints = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(privateCardTapped))
        tap.delegate = self
        privateToggleCard.addGestureRecognizer(tap)
        privateToggleCard.isUserInteractionEnabled = true

        privateToggleLabel.text = L(L10n.ChannelPermission.privateChannel)
        privateToggleLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        privateToggleLabel.textColor = .mezonTextPrimary
        privateToggleLabel.translatesAutoresizingMaskIntoConstraints = false
        privateToggleCard.addSubview(privateToggleLabel)

        privateSwitch.onTintColor = UIColor.theme.iconPrimary
        privateSwitch.addTarget(self, action: #selector(privateSwitchChanged), for: .valueChanged)
        privateSwitch.translatesAutoresizingMaskIntoConstraints = false
        privateSwitch.isOn = isPrivate
        privateToggleCard.addSubview(privateSwitch)

        NSLayoutConstraint.activate([
            privateToggleCard.heightAnchor.constraint(equalToConstant: 54.sh),
            privateToggleLabel.leadingAnchor.constraint(equalTo: privateToggleCard.leadingAnchor, constant: 14.sw),
            privateToggleLabel.centerYAnchor.constraint(equalTo: privateToggleCard.centerYAnchor),
            privateToggleLabel.trailingAnchor.constraint(lessThanOrEqualTo: privateSwitch.leadingAnchor, constant: -12.sw),
            privateSwitch.trailingAnchor.constraint(equalTo: privateToggleCard.trailingAnchor, constant: -14.sw),
            privateSwitch.centerYAnchor.constraint(equalTo: privateToggleCard.centerYAnchor)
        ])
    }

    @objc private func privateCardTapped() {
        guard !privacyUpdateInFlight else { return }
        privateSwitch.setOn(!privateSwitch.isOn, animated: true)
        privateSwitchChanged()
    }

    private func setupDescription() {
        descriptionLabel.text = L(L10n.ChannelPermission.basicViewDescription)
        descriptionLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textNormal
        descriptionLabel.numberOfLines = 0
    }

    private func setupAddMemberCard() {
        addMemberCard.backgroundColor = UIColor.theme.primary
        addMemberCard.layer.cornerRadius = 12.swh

        let tap = UITapGestureRecognizer(target: self, action: #selector(openAddMemberSheet))
        addMemberCard.addGestureRecognizer(tap)
        addMemberCard.isUserInteractionEnabled = true

        addMemberIcon.image = UIImage(systemName: "plus.circle")?.withRenderingMode(.alwaysTemplate)
        addMemberIcon.tintColor = .mezonTextPrimary
        addMemberIcon.contentMode = .scaleAspectFit
        addMemberIcon.translatesAutoresizingMaskIntoConstraints = false
        addMemberCard.addSubview(addMemberIcon)

        addMemberTitleLabel.text = L(L10n.ChannelPermission.addMemberAndRoles)
        addMemberTitleLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        addMemberTitleLabel.textColor = .mezonTextPrimary
        addMemberTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addMemberCard.addSubview(addMemberTitleLabel)

        addMemberChevron.image = UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
        addMemberChevron.tintColor = UIColor.theme.textDisabled
        addMemberChevron.contentMode = .scaleAspectFit
        addMemberChevron.translatesAutoresizingMaskIntoConstraints = false
        addMemberCard.addSubview(addMemberChevron)

        NSLayoutConstraint.activate([
            addMemberCard.heightAnchor.constraint(equalToConstant: 54.sh),

            addMemberIcon.leadingAnchor.constraint(equalTo: addMemberCard.leadingAnchor, constant: 14.sw),
            addMemberIcon.centerYAnchor.constraint(equalTo: addMemberCard.centerYAnchor),
            addMemberIcon.widthAnchor.constraint(equalToConstant: 22.swh),
            addMemberIcon.heightAnchor.constraint(equalToConstant: 22.swh),

            addMemberTitleLabel.leadingAnchor.constraint(equalTo: addMemberIcon.trailingAnchor, constant: 10.sw),
            addMemberTitleLabel.centerYAnchor.constraint(equalTo: addMemberCard.centerYAnchor),
            addMemberTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addMemberChevron.leadingAnchor, constant: -10.sw),

            addMemberChevron.trailingAnchor.constraint(equalTo: addMemberCard.trailingAnchor, constant: -14.sw),
            addMemberChevron.centerYAnchor.constraint(equalTo: addMemberCard.centerYAnchor),
            addMemberChevron.widthAnchor.constraint(equalToConstant: 12.swh),
            addMemberChevron.heightAnchor.constraint(equalToConstant: 18.swh)
        ])
    }

    private func setupWhoCanAccessLabel() {
        whoCanAccessLabel.text = L(L10n.ChannelPermission.whoCanAccess)
        whoCanAccessLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        whoCanAccessLabel.textColor = UIColor.theme.textNormal
    }

    private func setupListCard() {
        listCard.backgroundColor = UIColor.theme.primary
        listCard.layer.cornerRadius = 12.swh
        listCard.clipsToBounds = true

        listContentStack.axis = .vertical
        listContentStack.spacing = 0
        listContentStack.translatesAutoresizingMaskIntoConstraints = false
        listCard.addSubview(listContentStack)
        NSLayoutConstraint.activate([
            listContentStack.topAnchor.constraint(equalTo: listCard.topAnchor),
            listContentStack.leadingAnchor.constraint(equalTo: listCard.leadingAnchor),
            listContentStack.trailingAnchor.constraint(equalTo: listCard.trailingAnchor),
            listContentStack.bottomAnchor.constraint(equalTo: listCard.bottomAnchor)
        ])
    }

    private func setupEmptyAdvanced() {
        emptyAdvancedLabel.text = L(L10n.ChannelPermission.roleAndMemberEmpty)
        emptyAdvancedLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        emptyAdvancedLabel.textColor = UIColor.theme.textDisabled
        emptyAdvancedLabel.numberOfLines = 0
        emptyAdvancedLabel.textAlignment = .center
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadLocalData()
        fetchMembersTask = Task { [weak self] in await self?.refresh() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    @objc private func handleRolesChanged() { reloadLocalData() }

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        let nid: Int64? = {
            if let v = notification.userInfo?["channelId"] as? Int64 { return v }
            if let v = notification.userInfo?["channelId"] as? Int { return Int64(v) }
            if let n = notification.userInfo?["channelId"] as? NSNumber { return n.int64Value }
            return nil
        }()
        guard nid == channelId else { return }
        reloadLocalData()
    }

    private func channelSnapshotFromStores() -> Mezon_Api_ChannelDescription? {
        context.engine.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channelId)
    }

    private func resolvedChannelTypeForPermissions() -> Int32 {
        if let ch = channelSnapshotFromStores(), ch.type != 0 {
            return ch.type
        }
        return channelType
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }

    @objc private func selectBasicTab() {
        guard currentTab != .basic else { return }
        currentTab = .basic
        applyTabSelection()
    }

    @objc private func selectAdvancedTab() {
        guard isPrivate, resolvedChannelTypeForPermissions() != MezonConstants.ChannelType.mezonVoice.rawValue else { return }
        guard currentTab != .advanced else { return }
        currentTab = .advanced
        applyTabSelection()
    }

    private func applyTabSelection() {
        refreshVisibility()
        rebuildList()
    }

    private func refreshVisibility() {
        if !isPrivate, currentTab == .advanced {
            currentTab = .basic
        }
        advancedTabButton.isHidden = !isPrivate

        let showTabs = isPrivate && resolvedChannelTypeForPermissions() != MezonConstants.ChannelType.mezonVoice.rawValue
        tabContainer.isHidden = !showTabs
        tabContainerHeightConstraint?.constant = showTabs ? 40.sh : 0

        let active = UIColor.theme.iconPrimary
        let inactive = UIColor.clear
        let activeText = UIColor.white
        let inactiveText = UIColor.theme.text
        basicTabButton.backgroundColor = currentTab == .basic ? active : inactive
        basicTabButton.setTitleColor(currentTab == .basic ? activeText : inactiveText, for: .normal)
        advancedTabButton.backgroundColor = currentTab == .advanced ? active : inactive
        advancedTabButton.setTitleColor(currentTab == .advanced ? activeText : inactiveText, for: .normal)

        let isBasic = currentTab == .basic
        privateToggleCard.isHidden = !isBasic
        descriptionLabel.isHidden = !(isBasic && isPrivate)
        addMemberCard.isHidden = !(isBasic && isPrivate)
        whoCanAccessLabel.isHidden = !isBasic || !isPrivate
        let hasContent = !channelRoles.isEmpty || !channelMembers.isEmpty
        let advancedEmpty = currentTab == .advanced && !hasContent
        let hideBasicAccessList = isBasic && (!hasContent || !isPrivate)
        listCard.isHidden = advancedEmpty || hideBasicAccessList
        emptyAdvancedLabel.isHidden = !advancedEmpty
    }

    private func reloadLocalData() {
        if let latest = channelSnapshotFromStores() {
            isPrivate = latest.channelPrivate == 1
        }
        channelRoles = repository.channelRoles(
            clanId: clanId, channelId: channelId, channelType: resolvedChannelTypeForPermissions()
        )
        rebuildChannelMembers()
        privateSwitch.setOn(isPrivate, animated: false)
        refreshVisibility()
        rebuildList()
    }

    private func accessOwnerId() -> Int64? {
        if resolvedChannelTypeForPermissions() == MezonConstants.ChannelType.mezonVoice.rawValue {
            return channelSnapshotFromStores()?.creatorID
        }
        return repository.clanOwnerId(clanId: clanId).flatMap(Int64.init)
    }

    private func rebuildChannelMembers() {
        let clanOwnerId = repository.clanOwnerId(clanId: clanId)
        let allClanMembers = repository.clanMembers(clanId: clanId)
        if isPrivate {
            channelMembers = allClanMembers.filter { channelMemberIds.contains($0.userId) }
            if resolvedChannelTypeForPermissions() == MezonConstants.ChannelType.mezonVoice.rawValue,
               let owner = allClanMembers.first(where: { $0.userId == accessOwnerId() }),
               !channelMembers.contains(where: { $0.userId == owner.userId }) {
                channelMembers.insert(owner, at: 0)
            }
        } else if let ownerId = clanOwnerId, let oid = Int64(ownerId),
            let owner = allClanMembers.first(where: { $0.userId == oid }) {
            channelMembers = [owner]
        } else {
            channelMembers = []
        }
    }

    private func refresh() async {
        guard !Task.isCancelled else { return }
        if resolvedChannelTypeForPermissions() == MezonConstants.ChannelType.mezonVoice.rawValue {
            await repository.refreshRoles(clanId: clanId)
        }
        guard !Task.isCancelled, let ids = await repository.fetchChannelMembers(
            clanId: clanId, channelId: channelId, channelType: resolvedChannelTypeForPermissions()) else { return }
        guard !Task.isCancelled else { return }
        channelMemberIds = Set(ids)
        reloadLocalData()
    }

    private func applyListTheme() {
        for case let row as ChannelPermissionsRowView in listContentStack.arrangedSubviews {
            row.applyTheme()
        }
        for header in listSectionHeaders {
            header.label.text = "\(L(header.localizationKey)):"
            header.label.textColor = UIColor.theme.textStrong
        }
        listSeparators.forEach { $0.backgroundColor = UIColor.theme.borderPrimary }
    }

    private func rebuildList() {
        listSectionHeaders.removeAll()
        listSeparators.removeAll()
        listContentStack.arrangedSubviews.forEach {
            listContentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let isAdvanced = currentTab == .advanced

        if !channelRoles.isEmpty {
            listContentStack.addArrangedSubview(makeSubHeader(L10n.ChannelPermission.roles))
            for (idx, role) in channelRoles.enumerated() {
                let row = makeRoleRow(role, advanced: isAdvanced)
                listContentStack.addArrangedSubview(row)
                if idx < channelRoles.count - 1 {
                    listContentStack.addArrangedSubview(makeSeparator())
                }
            }
        }
        if !channelMembers.isEmpty {
            if !channelRoles.isEmpty {
                listContentStack.addArrangedSubview(makeSeparator())
            }
            listContentStack.addArrangedSubview(makeSubHeader(L10n.ChannelPermission.members))
            for (idx, member) in channelMembers.enumerated() {
                let row = makeMemberRow(member, advanced: isAdvanced)
                listContentStack.addArrangedSubview(row)
                if idx < channelMembers.count - 1 {
                    listContentStack.addArrangedSubview(makeSeparator())
                }
            }
        }
    }

    // MARK: - Toggle private

    @objc private func privateSwitchChanged() {
        guard !privacyUpdateInFlight else {
            privateSwitch.setOn(isPrivate, animated: true)
            return
        }
        let newPrivate = privateSwitch.isOn
        guard newPrivate != isPrivate else { return }
        let previous = isPrivate
        privacyUpdateInFlight = true
        privateSwitch.isEnabled = false
        fetchMembersTask?.cancel()
        fetchMembersTask = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.changeChannelPrivate(
                    clanId: self.clanId, channelId: self.channelId, makePrivate: newPrivate)
                self.isPrivate = newPrivate
                if self.resolvedChannelTypeForPermissions() == MezonConstants.ChannelType.mezonVoice.rawValue {
                    let ownerId = self.accessOwnerId()
                    self.channelMemberIds = newPrivate ? Set(ownerId.map { [$0] } ?? []) : []
                } else if newPrivate, let uid = self.context.currentUser?.id, let cuid = Int64(uid) {
                    self.channelMemberIds.insert(cuid)
                }
                self.rebuildChannelMembers()
                self.refreshVisibility()
                self.rebuildList()
                Toast.success(L(L10n.ChannelPermission.toastSuccess))
                await self.refresh()
            } catch {
                self.isPrivate = previous
                self.privateSwitch.setOn(previous, animated: true)
                self.refreshVisibility()
                self.rebuildList()
                Toast.error(L(L10n.ChannelPermission.toastFailed))
            }
            self.privacyUpdateInFlight = false
            self.privateSwitch.isEnabled = true
        }
    }

    // MARK: - Add / remove

    @objc private func openAddMemberSheet() {
        let allMembers = repository.clanMembers(clanId: clanId)
        let allRoles = repository.roles(clanId: clanId)
        let memberPool = allMembers.filter { !channelMemberIds.contains($0.userId) }
        let rolePool = allRoles.filter { role in
            !repository.isEveryone(role) && !repository.roleIsInChannel(
                role, channelId: channelId, channelType: resolvedChannelTypeForPermissions()
            )
        }
        let sheet = AddMemberOrRoleSheetController(
            availableMembers: memberPool,
            availableRoles: rolePool,
            onAdd: { [weak self] memberIds, roleIds in
                self?.performAdd(memberIds: memberIds, roleIds: roleIds)
            }
        )
        present(sheet, animated: true)
    }

    private func performAdd(memberIds: [Int64], roleIds: [Int64]) {
        fetchMembersTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                if !memberIds.isEmpty {
                    try await self.repository.addChannelMembers(
                        channelId: self.channelId, userIds: memberIds)
                }
                if !roleIds.isEmpty {
                    try await self.repository.addChannelRoles(
                        channelId: self.channelId, clanId: self.clanId, roleIds: roleIds)
                }
                await self.refresh()
                Toast.success(L(L10n.ChannelPermission.toastSuccess))
            } catch {
                Toast.error(L(L10n.ChannelPermission.toastFailed))
                await self.refresh()
            }
        }
    }

    private func removeMember(_ member: ClanMemberRecord) {
        fetchMembersTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.removeChannelUser(
                    clanId: self.clanId, channelId: self.channelId, userId: member.userId)
                if self.resolvedChannelTypeForPermissions() == MezonConstants.ChannelType.mezonVoice.rawValue,
                   String(member.userId) == self.context.currentUser?.id {
                    self.navigationController?.popToRootViewController(animated: true)
                    return
                }
                self.channelMemberIds.remove(member.userId)
                self.reloadLocalData()
                Toast.success(L(L10n.ChannelPermission.toastSuccess))
            } catch {
                Toast.error(L(L10n.ChannelPermission.toastFailed))
            }
        }
    }

    private func removeRole(_ role: Mezon_Api_Role) {
        fetchMembersTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.removeChannelRole(
                    channelId: self.channelId, clanId: self.clanId, roleId: role.id)
                self.reloadLocalData()
                Toast.success(L(L10n.ChannelPermission.toastSuccess))
            } catch {
                Toast.error(L(L10n.ChannelPermission.toastFailed))
            }
        }
    }

    private func openAdvancedOverrides(for target: AdvancedPermissionOverridesViewController.Target) {
        let vc = AdvancedPermissionOverridesViewController(
            context: context,
            clanId: clanId,
            channelId: channelId,
            target: target
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Row builders

    private func makeSubHeader(_ localizationKey: String) -> UIView {
        let v = UIView()
        let l = UILabel()
        l.text = "\(L(localizationKey)):"
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.textColor = UIColor.theme.textStrong
        listSectionHeaders.append((label: l, localizationKey: localizationKey))
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14.sw),
            l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14.sw),
            l.topAnchor.constraint(equalTo: v.topAnchor, constant: 12.sh),
            l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6.sh)
        ])
        return v
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        v.backgroundColor = UIColor.theme.borderPrimary
        listSeparators.append(v)
        return v
    }

    private func makeRoleRow(_ role: Mezon_Api_Role, advanced: Bool) -> UIView {
        let isEveryone = repository.isEveryone(role)
        let row = ChannelPermissionsRowView(
            kind: .role(title: role.title, color: RoleColors.uiColor(forRole: role)),
            trailing: advanced ? .chevron : .removeButton(enabled: !isEveryone),
            onTrailing: { [weak self] in
                guard !isEveryone else { return }
                self?.removeRole(role)
            },
            onTap: advanced ? { [weak self] in
                self?.openAdvancedOverrides(for: .role(id: role.id, title: role.title))
            } : nil
        )
        return row
    }

    private func makeMemberRow(_ member: ClanMemberRecord, advanced: Bool) -> UIView {
        let isOwner = accessOwnerId() == member.userId
        let isCurrentUser: Bool = {
            if let uid = context.currentUser?.id, let cuid = Int64(uid) { return cuid == member.userId }
            return false
        }()
        let canRemove = !isOwner && (!isCurrentUser || resolvedChannelTypeForPermissions() == MezonConstants.ChannelType.mezonVoice.rawValue)
        let row = ChannelPermissionsRowView(
            kind: .member(
                name: RoleMemberDisplay.displayName(member),
                username: member.username,
                avatarURL: RoleMemberDisplay.avatarURL(member),
                isOwner: isOwner
            ),
            trailing: advanced ? .chevron : .removeButton(enabled: canRemove),
            onTrailing: { [weak self] in
                guard canRemove else { return }
                self?.removeMember(member)
            },
            onTap: advanced ? { [weak self] in
                self?.openAdvancedOverrides(for: .member(id: member.userId, name: RoleMemberDisplay.displayName(member)))
            } : nil
        )
        return row
    }
}

extension ChannelPermissionsViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UIControl {
                return false
            }
            view = current.superview
        }
        return true
    }
}
