import UIKit
import MobileCoreServices

final class ClanSoundsViewController: BaseViewController {
    private let context: AccountContext
    private let clanId: Int64
    private let repository: SoundsRepository
    private var sounds: [CachedClanStickerRecord] = []
    private var members: [Int64: ClanMemberRecord] = [:]
    private var soundDurations: [String: TimeInterval] = [:]
    private var pendingIds = Set<Int64>()
    private var isLoading = true
    private weak var openSwipeCell: SoundItemCell?
    private var isSwipeInteractionActive = false

    private let header = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let uploadButton = UIButton(type: .system)
    private let requirementsLabel = UILabel()
    private let uploadSection = UIStackView()
    private let emptyLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        repository = SoundsRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func setupUI() {
        [header, uploadSection, tableView, emptyLabel].forEach { view.addSubview($0) }
        [backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        titleLabel.text = L(L10n.ClanSetting.soundEffect)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8.sw),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -52.sw)
        ])
        uploadSection.axis = .vertical
        uploadSection.spacing = 12.sh
        uploadSection.isLayoutMarginsRelativeArrangement = true
        uploadSection.layoutMargins = UIEdgeInsets(top: 8.sh, left: 16.sw, bottom: 20.sh, right: 16.sw)
        uploadButton.setTitle(L(L10n.ClanSetting.Sounds.upload), for: .normal)
        uploadButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        uploadButton.setTitleColor(.white, for: .normal)
        uploadButton.layer.cornerRadius = 22.sh
        uploadButton.heightAnchor.constraint(equalToConstant: 44.sh).isActive = true
        uploadButton.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
        requirementsLabel.text = L(L10n.ClanSetting.Sounds.requirements)
        requirementsLabel.font = .systemFont(ofSize: 13.sf)
        requirementsLabel.numberOfLines = 0
        uploadSection.addArrangedSubview(uploadButton)
        uploadSection.addArrangedSubview(requirementsLabel)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.disablesInteractiveTransitionGestureRecognizerNow = { [weak self] in
            guard let self else { return false }
            return self.isSwipeInteractionActive || self.openSwipeCell != nil
        }
        tableView.separatorInset = .zero
        tableView.layer.cornerRadius = 12.swh
        tableView.clipsToBounds = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60.sh
        tableView.tableFooterView = UIView()
        tableView.register(SoundItemCell.self, forCellReuseIdentifier: SoundItemCell.reuseId)
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15.sf)
        emptyLabel.numberOfLines = 0
        applyTheme()
    }

    override func setupBindings() {
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .mezonStickerListDidUpdate, object: nil)
        disposables.add((context.engine.clanData.clanPermissionsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] id in
                guard let self, id == self.clanId else { return }
                self.updateVisibleCells()
            }))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
        Task { [weak self] in
            guard let self else { return }
            do { try await repository.refresh() }
            catch { Toast.error(error.localizedDescription) }
            isLoading = false
            reloadData()
        }
        Task { [weak self] in
            guard let self, let token = await context.getToken() else { return }
            do {
                let response = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                let records = response.clanUsers.map { ClanMemberRecord(from: $0) }
                context.account.postbox.write { $0.updateClanMembers(records, clanId: self.clanId) }
                members = Dictionary(records.map { ($0.userId, $0) }, uniquingKeysWith: { $1 })
                updateVisibleCells()
            } catch { /* Cached member and profile data remain available. */ }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        openSwipeCell?.closeSwipe(animated: false)
        stopPlayback()
    }

    override func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        header.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
        uploadButton.backgroundColor = UIColor.theme.bgViolet
        requirementsLabel.textColor = UIColor.theme.textDisabled
        emptyLabel.textColor = UIColor.theme.textDisabled
        tableView.backgroundColor = UIColor.theme.secondary
        tableView.separatorColor = UIColor.theme.border
        updateVisibleCells()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let safeTop = max(layout.safeInsets.top, layout.statusBarHeight ?? 0, view.safeAreaInsets.top)
        let headerHeight = max(50.sh, 44.swh + 10.sh)
        header.frame = CGRect(x: 0, y: safeTop, width: layout.size.width, height: headerHeight)
        let width = layout.size.width - 32.sw
        let uploadHeight = uploadSection.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        uploadSection.frame = CGRect(x: 16.sw, y: header.frame.maxY, width: width, height: uploadHeight)
        let listTop = uploadSection.frame.maxY
        tableView.frame = CGRect(x: 16.sw, y: listTop, width: width, height: max(0, layout.size.height - listTop))
        tableView.contentInset.bottom = layout.intrinsicInsets.bottom
        emptyLabel.frame = tableView.frame
    }

    @objc private func reloadData() {
        let updatedSounds = repository.sounds(clanId: clanId)
        let records = context.account.postbox.read { $0.getClanMembers(clanId: self.clanId) }
        let updatedMembers = Dictionary(records.map { ($0.userId, $0) }, uniquingKeysWith: { $1 })
        let contentChanged = sounds != updatedSounds || members != updatedMembers
        members = updatedMembers
        tableView.isHidden = updatedSounds.isEmpty
        emptyLabel.isHidden = !updatedSounds.isEmpty
        emptyLabel.text = L(isLoading ? L10n.ClanSetting.Sounds.loading : L10n.ClanSetting.Sounds.empty)
        if contentChanged { updateSounds(updatedSounds) }
    }

    private func updateSounds(_ updatedSounds: [CachedClanStickerRecord]) {
        guard !sounds.isEmpty else {
            sounds = updatedSounds
            tableView.reloadData()
            return
        }
        let changes = updatedSounds.map(\.id).difference(from: sounds.map(\.id)).inferringMoves()
        if changes.isEmpty {
            sounds = updatedSounds
        } else {
            UIView.performWithoutAnimation {
                self.tableView.performBatchUpdates {
                    self.sounds = updatedSounds
                    for change in changes {
                        switch change {
                        case let .remove(offset, _, destination):
                            let indexPath = IndexPath(row: offset, section: 0)
                            if let destination {
                                self.tableView.moveRow(at: indexPath, to: IndexPath(row: destination, section: 0))
                            } else {
                                self.tableView.deleteRows(at: [indexPath], with: .none)
                            }
                        case let .insert(offset, _, source):
                            if source == nil {
                                self.tableView.insertRows(at: [IndexPath(row: offset, section: 0)], with: .none)
                            }
                        }
                    }
                }
                self.tableView.layoutIfNeeded()
            }
        }
        updateVisibleCells()
    }

    private func updateVisibleCells() {
        for case let cell as SoundItemCell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            configure(cell, sound: sounds[indexPath.row])
        }
    }

    private func canManage(_ sound: CachedClanStickerRecord) -> Bool {
        let permissions = context.rolePermissions
        let userId = Int64(context.currentUser?.id ?? "") ?? 0
        return (userId != 0 && userId == sound.creatorID)
            || permissions.isClanOwner(clanId: clanId)
            || permissions.hasClanPermission(.administrator, clanId: clanId)
            || permissions.canManageClan(clanId: clanId)
    }

    private func stopPlayback() {
        tableView.visibleCells.compactMap { $0 as? SoundItemCell }.forEach { $0.stopPlayback() }
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }

    @objc private func uploadTapped() {
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeMP3 as String, kUTTypeWaveformAudio as String], in: .import)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func rename(_ sound: CachedClanStickerRecord) {
        guard canManage(sound), !pendingIds.contains(sound.id) else { return }
        stopPlayback()
        let alert = UIAlertController(title: L(L10n.ClanSetting.Sounds.rename), message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = sound.shortname
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.spellCheckingType = .no
        }
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.Common.save), style: .default) { [weak self, weak alert] _ in
            guard let self, self.canManage(sound) else { return }
            let name = ClanStickerNameValidator.normalized(alert?.textFields?.first?.text ?? "")
            guard name != sound.shortname else { return }
            guard ClanStickerNameValidator.isValid(name) else {
                Toast.error(L(L10n.ClanSetting.Sounds.nameRequirement))
                return
            }
            self.performMutation(sound) { try await self.repository.rename(sound, name: name) }
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ sound: CachedClanStickerRecord) {
        guard canManage(sound), !pendingIds.contains(sound.id) else { return }
        MezonConfirm.present(
            from: self, title: L(L10n.ClanSetting.Sounds.deleteTitle),
            content: String(format: L(L10n.ClanSetting.Sounds.deleteDescription), sound.shortname),
            confirmTitle: L(L10n.Common.delete), isDanger: true
        ) { [weak self] in
            guard let self, self.canManage(sound) else { return }
            self.stopPlayback()
            self.performMutation(sound) { try await self.repository.delete(sound) }
        }
    }

    private func performMutation(_ sound: CachedClanStickerRecord, action: @escaping () async throws -> Void) {
        guard pendingIds.insert(sound.id).inserted else { return }
        Task {
            defer { pendingIds.remove(sound.id) }
            do {
                try await action()
                Toast.success(L(L10n.ClanSetting.Sounds.saved))
            } catch { Toast.error(error.localizedDescription) }
        }
    }
}

extension ClanSoundsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sounds.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SoundItemCell.reuseId, for: indexPath) as! SoundItemCell
        configure(cell, sound: sounds[indexPath.row])
        return cell
    }

    private func configure(_ cell: SoundItemCell, sound: CachedClanStickerRecord) {
        let member = members[sound.creatorID]
        let profile = context.account.postbox.read { $0.getProfile(userId: String(sound.creatorID)) }
        let name = [member?.clanNick, member?.displayName, profile?.displayName, member?.username, profile?.username]
            .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? ""
        let avatar = member?.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl) ?? profile?.avatarUrl
        cell.onDurationLoaded = { [weak self] duration in
            self?.soundDurations[sound.source] = duration
        }
        cell.configure(sound: sound, creatorName: name, creatorAvatarURL: avatar,
                       canDelete: canManage(sound), knownDuration: soundDurations[sound.source])
        cell.onDelete = { [weak self] in self?.confirmDelete(sound) }
        cell.onSwipeOpened = { [weak self, weak cell] in
            guard let self, let cell, self.openSwipeCell !== cell else { return }
            self.openSwipeCell?.closeSwipe(animated: true)
            self.openSwipeCell = cell
        }
        cell.onSwipeClosed = { [weak self, weak cell] in
            guard let self, let cell, self.openSwipeCell === cell else { return }
            self.openSwipeCell = nil
        }
        cell.onSwipeInteractionChanged = { [weak self] active in
            self?.isSwipeInteractionActive = active
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openSwipeCell?.closeSwipe(animated: true)
        rename(sounds[indexPath.row])
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? SoundItemCell)?.closeSwipe(animated: false)
        (cell as? SoundItemCell)?.stopPlayback()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        openSwipeCell?.closeSwipe(animated: true)
    }
}

extension ClanSoundsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    defer { try? FileManager.default.removeItem(at: url) }
                    return try ClanSoundAudio.importFile(url)
                }.value
                let preview = try ClanSoundPreviewViewController(source: source)
                preview.onUpload = { [repository, clanId] data, ext, name in
                    try await repository.create(clanId: clanId, data: data, fileExtension: ext, name: name)
                }
                stopPlayback()
                present(preview, animated: true)
            } catch { Toast.error(error.localizedDescription) }
        }
    }
}
