import UIKit

final class ClanEmojisViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let repository: EmojisRepository

    private var emojis: [CachedClanEmojiRecord] = []
    private var clanMembers: [Int64: ClanMemberRecord] = [:]
    private weak var openSwipeCell: EmojiItemCell?
    private var isSwipeInteractionActive = false

    private static let listHorizontalInset: CGFloat = 16
    private static let maxUploadFileSize = 256 * 1024
    private static let uploadSectionSpacing: CGFloat = 20.sh

    private lazy var tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.backgroundColor = UIColor.theme.secondary
        t.layer.cornerRadius = 12.swh
        t.clipsToBounds = true
        t.dataSource = self
        t.delegate = self
        t.separatorStyle = .none
        t.showsVerticalScrollIndicator = false
        t.estimatedRowHeight = 60.sh
        t.rowHeight = UITableView.automaticDimension
        t.register(EmojiItemCell.self, forCellReuseIdentifier: EmojiItemCell.reuseId)
        t.cellLayoutMarginsFollowReadableWidth = false
        t.preservesSuperviewLayoutMargins = false
        t.insetsLayoutMarginsFromSafeArea = false
        if #available(iOS 15.0, *) {
            t.sectionHeaderTopPadding = 0
        }
        t.disablesInteractiveTransitionGestureRecognizerNow = { [weak self] in
            guard let self else { return false }
            return self.isSwipeInteractionActive || self.openSwipeCell != nil
        }
        return t
    }()

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let headerTitleLabel = UILabel()
    private let uploadButton = UIButton(type: .system)
    private let descriptionLabel = UILabel()
    private let requirementsTitleLabel = UILabel()
    private let requirementsStack = UIStackView()
    private let tableHeaderContainer = UIView()

    private var headerTopConstraint: NSLayoutConstraint!
    private var headerHeightConstraint: NSLayoutConstraint!
    private var tableHeaderHeight: CGFloat = 200.sh
    private var lastTableHeaderWidth: CGFloat = 0

    private var headerBarHeight: CGFloat {
        max(50.sh, 44.swh + 10.sh)
    }

    private lazy var tableHeader: UIView = {
        setupTableHeader()
        return tableHeaderContainer
    }()

    private func setupTableHeader() {
        tableHeaderContainer.backgroundColor = UIColor.theme.primary
        uploadButton.setTitle(L(L10n.ClanSetting.Emojis.uploadButton), for: .normal)
        uploadButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        uploadButton.setTitleColor(.white, for: .normal)
        uploadButton.backgroundColor = UIColor.theme.bgViolet
        uploadButton.layer.cornerRadius = 22.sh
        uploadButton.clipsToBounds = true
        uploadButton.addTarget(self, action: #selector(addEmojiTapped), for: .touchUpInside)

        descriptionLabel.text = L(L10n.ClanSetting.Emojis.uploadDescription)
        descriptionLabel.font = .systemFont(ofSize: 13.sf)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0

        requirementsTitleLabel.text = L(L10n.ClanSetting.Emojis.uploadRequirementsTitle).uppercased()
        requirementsTitleLabel.font = .systemFont(ofSize: 13.sf, weight: .bold)
        requirementsTitleLabel.textColor = UIColor.theme.textStrong

        requirementsStack.axis = .vertical
        requirementsStack.spacing = 10.sh
        requirementsStack.alignment = .fill
        requirementsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        [
            L(L10n.ClanSetting.Emojis.uploadRequirement1),
            L(L10n.ClanSetting.Emojis.uploadRequirement2),
            L(L10n.ClanSetting.Emojis.uploadRequirement3),
            L(L10n.ClanSetting.Emojis.uploadRequirement4)
        ].forEach { requirementsStack.addArrangedSubview(makeRequirementRow(text: $0)) }

        [uploadButton, descriptionLabel, requirementsTitleLabel, requirementsStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            tableHeaderContainer.addSubview($0)
        }

        NSLayoutConstraint.activate([
            uploadButton.topAnchor.constraint(equalTo: tableHeaderContainer.topAnchor, constant: 8.sh),
            uploadButton.leadingAnchor.constraint(equalTo: tableHeaderContainer.leadingAnchor, constant: 16.sw),
            uploadButton.trailingAnchor.constraint(equalTo: tableHeaderContainer.trailingAnchor, constant: -16.sw),
            uploadButton.heightAnchor.constraint(equalToConstant: 44.sh),

            descriptionLabel.topAnchor.constraint(equalTo: uploadButton.bottomAnchor, constant: 12.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: uploadButton.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: uploadButton.trailingAnchor),

            requirementsTitleLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Self.uploadSectionSpacing),
            requirementsTitleLabel.leadingAnchor.constraint(equalTo: uploadButton.leadingAnchor),
            requirementsTitleLabel.trailingAnchor.constraint(equalTo: uploadButton.trailingAnchor),

            requirementsStack.topAnchor.constraint(equalTo: requirementsTitleLabel.bottomAnchor, constant: 12.sh),
            requirementsStack.leadingAnchor.constraint(equalTo: uploadButton.leadingAnchor),
            requirementsStack.trailingAnchor.constraint(equalTo: uploadButton.trailingAnchor),
            requirementsStack.bottomAnchor.constraint(equalTo: tableHeaderContainer.bottomAnchor, constant: -Self.uploadSectionSpacing)
        ])
    }

    private func makeRequirementRow(text: String) -> UIView {
        let bullet = UILabel()
        bullet.text = "•"
        bullet.font = .systemFont(ofSize: 13.sf)
        bullet.textColor = UIColor.theme.textDisabled
        bullet.setContentHuggingPriority(.required, for: .horizontal)
        bullet.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13.sf)
        label.textColor = UIColor.theme.textStrong
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [bullet, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8.sw
        return row
    }

    private func updateTableHeaderHeight(for width: CGFloat) {
        guard width > 0 else { return }
        tableHeaderContainer.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        tableHeaderContainer.setNeedsLayout()
        tableHeaderContainer.layoutIfNeeded()
        let height = tableHeaderContainer.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        tableHeaderHeight = height
        tableHeaderContainer.frame.size.height = tableHeaderHeight
    }

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        self.repository = EmojisRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        viewRespectsSystemMinimumLayoutMargins = false
        setupHeader()
        _ = tableHeader
        view.addSubview(tableHeaderContainer)
        view.addSubview(tableView)
    }

    private func setupHeader() {
        headerView.backgroundColor = UIColor.theme.primary
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        headerTitleLabel.text = L(L10n.ClanSetting.emoji)
        headerTitleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        headerTitleLabel.textColor = .mezonTextPrimary
        headerTitleLabel.textAlignment = .center

        [backButton, headerTitleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        headerTopConstraint = headerView.topAnchor.constraint(equalTo: view.topAnchor)
        headerHeightConstraint = headerView.heightAnchor.constraint(equalToConstant: headerBarHeight)
        NSLayoutConstraint.activate([
            headerTopConstraint,
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerHeightConstraint,

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            headerTitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            headerTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8.sw),
            headerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -52.sw)
        ])
    }

    override func setupBindings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEmojisChanged),
            name: .mezonEmojiListDidUpdate,
            object: nil
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
        fetchClanMembersIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        applyChromeLayout(layout)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let layout = currentlyAppliedLayout {
            applyChromeLayout(layout)
        }
    }

    override func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        headerView.backgroundColor = UIColor.theme.primary
        headerTitleLabel.textColor = .mezonTextPrimary
        backButton.tintColor = UIColor.theme.textStrong
        uploadButton.backgroundColor = UIColor.theme.bgViolet
        uploadButton.setTitleColor(.white, for: .normal)
        requirementsTitleLabel.textColor = UIColor.theme.textStrong
        requirementsStack.arrangedSubviews.forEach { row in
            guard let stack = row as? UIStackView else { return }
            stack.arrangedSubviews.forEach { view in
                guard let label = view as? UILabel else { return }
                let isBullet = label.text == "•"
                label.textColor = isBullet ? UIColor.theme.textDisabled : UIColor.theme.textStrong
            }
        }
        tableHeaderContainer.backgroundColor = UIColor.theme.primary
        applyEmojiListChrome()
        tableView.reloadData()
    }

    private func applyEmojiListChrome() {
        let hasEmojis = !emojis.isEmpty
        tableView.isHidden = !hasEmojis
        if hasEmojis {
            tableView.backgroundColor = UIColor.theme.secondary
            tableView.layer.cornerRadius = 12.swh
        } else {
            tableView.backgroundColor = .clear
            tableView.layer.cornerRadius = 0
        }
    }

    private func resolvedSafeTop(for layout: ContainerViewLayout) -> CGFloat {
        let viewSafeTop = isViewLoaded ? view.safeAreaInsets.top : 0
        return max(layout.safeInsets.top, layout.statusBarHeight ?? 0, viewSafeTop)
    }

    private func applyChromeLayout(_ layout: ContainerViewLayout) {
        let safeTop = resolvedSafeTop(for: layout)
        headerTopConstraint.constant = safeTop
        headerHeightConstraint.constant = headerBarHeight
        let headerH = headerBarHeight
        let inset = Self.listHorizontalInset.sw
        let contentWidth = layout.size.width - inset * 2
        updateTableHeaderHeight(for: contentWidth)
        tableHeaderContainer.frame = CGRect(
            x: inset,
            y: safeTop + headerH,
            width: contentWidth,
            height: tableHeaderHeight
        )
        let listTop = safeTop + headerH + tableHeaderHeight
        let hasEmojis = !emojis.isEmpty
        applyEmojiListChrome()
        tableView.tableHeaderView = nil
        tableView.frame = CGRect(
            x: inset,
            y: listTop,
            width: contentWidth,
            height: hasEmojis ? layout.size.height - listTop : 0
        )
        if abs(lastTableHeaderWidth - layout.size.width) > 0.5 {
            lastTableHeaderWidth = layout.size.width
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    private var currentUserId: Int64 {
        Int64(context.currentUser?.id ?? "") ?? 0
    }

    private var hasClanEmojiAdminPermission: Bool {
        let perms = context.rolePermissions
        return perms.isClanOwner(clanId: clanId)
            || perms.hasClanPermission(.administrator, clanId: clanId)
            || perms.canManageClan(clanId: clanId)
    }

    private func canEdit(_ emoji: CachedClanEmojiRecord) -> Bool {
        hasClanEmojiAdminPermission || (currentUserId != 0 && currentUserId == emoji.creatorID)
    }

    private func resolvedCreatorInfo(for creatorId: Int64) -> (avatar: String?, name: String) {
        let member = clanMembers[creatorId]
        let profile = context.engine.account.postbox.read {
            $0.getProfile(userId: "\(creatorId)")
        }
        let profileAvatar = profile?.avatarUrl
        if let member {
            return (
                member.resolvedAvatarURL(fallbackProfileAvatar: profileAvatar),
                member.resolvedDisplayName
            )
        }
        let name: String = {
            if let displayName = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !displayName.isEmpty {
                return displayName
            }
            let username = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return username
        }()
        let avatar = profileAvatar?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (avatar?.isEmpty == false ? avatar : nil, name)
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func handleEmojisChanged() {
        reloadData()
    }

    private func showUploadLimitToastIfNeeded() -> Bool {
        guard repository.isAtUploadLimit(clanId: clanId) else { return false }
        Toast.error(L(L10n.ClanSetting.Emojis.uploadLimit))
        return true
    }

    @objc private func addEmojiTapped() {
        if showUploadLimitToastIfNeeded() { return }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        present(picker, animated: true)
    }

    private func reloadData() {
        emojis = repository.emojis(clanId: clanId)
        let members = context.engine.account.postbox.read { $0.getClanMembers(clanId: self.clanId) }
        clanMembers = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })

        let atLimit = repository.isAtUploadLimit(clanId: clanId)
        uploadButton.isEnabled = true
        uploadButton.alpha = atLimit ? 0.5 : 1.0
        tableView.reloadData()
        applyEmojiListChrome()
        if let layout = currentlyAppliedLayout {
            applyChromeLayout(layout)
        }
    }

    private func fetchClanMembersIfNeeded() {
        guard clanMembers.isEmpty else { return }
        Task {
            guard let token = await context.getToken() else { return }
            do {
                let res = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                let records = res.clanUsers.map { ClanMemberRecord(from: $0) }
                context.engine.account.postbox.write { tx in
                    tx.updateClanMembers(records, clanId: self.clanId)
                }
                await MainActor.run {
                    self.clanMembers = Dictionary(uniqueKeysWithValues: records.map { ($0.userId, $0) })
                    self.tableView.reloadData()
                }
            } catch {}
        }
    }

    private func validateInnerName(_ innerName: String, excludingId: Int64? = nil) -> Bool {
        let name = innerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ClanStickerNameValidator.isValid(name) else {
            Toast.error(String(
                format: L(L10n.ClanSetting.Emojis.validateName),
                ClanStickerNameValidator.minLength,
                ClanStickerNameValidator.maxLength
            ))
            return false
        }
        let wrapped = CachedClanEmojiRecord.wrappedShortname(name)
        guard !emojis.contains(where: { $0.shortname == wrapped && $0.id != excludingId }) else {
            Toast.error(L(L10n.ClanSetting.Emojis.duplicateName))
            return false
        }
        return true
    }

    private func commitEmojiNameChange(
        for emoji: CachedClanEmojiRecord,
        innerName: String,
        completion: @escaping (Bool) -> Void
    ) {
        let text = innerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapped = CachedClanEmojiRecord.wrappedShortname(text)
        let currentInner = CachedClanEmojiRecord.innerName(from: emoji.shortname)
        guard !text.isEmpty, text != currentInner else {
            completion(true)
            return
        }
        guard validateInnerName(text, excludingId: emoji.id) else {
            completion(false)
            return
        }
        Task {
            do {
                try await repository.updateEmoji(
                    id: emoji.id,
                    clanId: clanId,
                    shortname: wrapped
                )
                await MainActor.run {
                    Toast.success(L(L10n.ClanSetting.Emojis.updateSuccess))
                    completion(true)
                    reloadData()
                }
            } catch {
                await MainActor.run {
                    Toast.error(L(L10n.ClanSetting.Emojis.errorUpdating))
                    completion(false)
                }
            }
        }
    }

    private func deleteEmoji(_ emoji: CachedClanEmojiRecord) {
        guard canEdit(emoji) else { return }
        MezonConfirm.present(
            from: self,
            title: L(L10n.ClanSetting.Emojis.deleteConfirmTitle),
            content: L(L10n.ClanSetting.Emojis.deleteConfirmDesc),
            confirmTitle: L(L10n.Common.delete),
            isDanger: true
        ) { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.repository.deleteEmoji(
                        id: emoji.id,
                        clanId: self.clanId,
                        shortname: emoji.shortname
                    )
                    Toast.success(L(L10n.ClanSetting.Emojis.deleteSuccess))
                } catch {
                    Toast.error(L(L10n.ClanSetting.Emojis.errorUpdating))
                }
            }
        }
    }
}

extension ClanEmojisViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        emojis.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EmojiItemCell.reuseId, for: indexPath) as! EmojiItemCell
        let rowCount = emojis.count
        let isLast = indexPath.row == rowCount - 1
        let emoji = emojis[indexPath.row]
        let creatorInfo = resolvedCreatorInfo(for: emoji.creatorID)
        let editable = canEdit(emoji)
        cell.configure(
            emoji: emoji,
            creatorAvatar: creatorInfo.avatar,
            creatorName: creatorInfo.name,
            isEditable: editable,
            isLast: isLast
        )
        cell.onShortnameCommit = { [weak self] innerName, done in
            guard let self,
                  let current = self.emojis.first(where: { $0.id == emoji.id })
            else {
                done(false)
                return
            }
            self.commitEmojiNameChange(for: current, innerName: innerName, completion: done)
        }
        cell.onDelete = { [weak self] in
            self?.deleteEmoji(emoji)
        }
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
        return cell
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        openSwipeCell?.closeSwipe(animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !emojis.isEmpty else { return }
        openSwipeCell?.closeSwipe(animated: true)
        let emoji = emojis[indexPath.row]
        guard canEdit(emoji) else { return }
        (tableView.cellForRow(at: indexPath) as? EmojiItemCell)?.beginEditingName()
    }

}

extension ClanEmojisViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let image, let picked = Self.pickedEmojiImage(image: image, info: info) else { return }
        guard ClanGraphicImageUtils.isAllowedEmojiUpload(contentType: picked.contentType, data: picked.data) else {
            Toast.error(L(L10n.ClanSetting.Emojis.uploadRequirement1))
            return
        }
        guard picked.data.count <= Self.maxUploadFileSize else {
            Toast.error(L(L10n.ClanSetting.Emojis.uploadFileTooLarge))
            return
        }
        if showUploadLimitToastIfNeeded() { return }
        presentEmojiPreview(image: image, picked: picked)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func presentEmojiPreview(image: UIImage, picked: PickedEmojiImage) {
        let preview = ClanEmojiPreviewViewController(image: image)
        preview.onConfirm = { [weak self, weak preview] innerName, isForSale in
            guard let self else { return }
            guard self.validateInnerName(innerName) else { return }
            let wrapped = CachedClanEmojiRecord.wrappedShortname(innerName)
            preview?.dismiss(animated: true) {
                Task { await self.uploadEmoji(image: image, picked: picked, shortname: wrapped, isForSale: isForSale) }
            }
        }
        present(preview, animated: true)
    }

    private func uploadEmoji(image: UIImage, picked: PickedEmojiImage, shortname: String, isForSale: Bool) async {
        if repository.isAtUploadLimit(clanId: clanId) {
            Toast.error(L(L10n.ClanSetting.Emojis.uploadLimit))
            return
        }
        guard let uploadPayload = Self.prepareUploadPayload(image: image, picked: picked) else {
            Toast.error(L(L10n.ClanSetting.Emojis.errorUpdating))
            return
        }
        guard uploadPayload.data.count <= Self.maxUploadFileSize else {
            Toast.error(L(L10n.ClanSetting.Emojis.uploadFileTooLarge))
            return
        }
        let uploadId = Int64(Date().timeIntervalSince1970 * 1000)
        let filename = "emojis/\(uploadId).webp"
        do {
            guard let token = await context.getToken() else { return }
            let upload = try await context.account.network.uploadAttachmentFile(
                filename: filename,
                filetype: uploadPayload.contentType,
                size: uploadPayload.data.count,
                width: uploadPayload.width,
                height: uploadPayload.height,
                token: token
            )
            try await context.account.network.uploadToMinIO(
                url: upload.url,
                data: uploadPayload.data,
                contentType: uploadPayload.contentType
            )
            let cdnURL = "\(MezonConfig.baseImgURL)/\(upload.filename)"
            ImageCache.shared.setImage(image, data: uploadPayload.data, forKey: cdnURL)
            let listIconSide = Int(40 * UIScreen.main.scale)
            let listProxyURL = ImgproxyURL.createEmoji(from: cdnURL, width: listIconSide, height: listIconSide)
            if !listProxyURL.isEmpty {
                ImageCache.shared.setImage(image, data: uploadPayload.data, forKey: listProxyURL)
            }

            let requestId = Self.emojiId(fromUploadFilename: upload.filename) ?? uploadId

            if isForSale, let watermarked = ClanGraphicImageUtils.blurredWatermarkedImage(from: image),
               let previewData = ClanGraphicImageUtils.pngData(from: watermarked) {
                let previewUploadId = Int64(Date().timeIntervalSince1970 * 1000) + 1
                let previewFilename = "emojis/\(previewUploadId).webp"
                let previewUpload = try await context.account.network.uploadAttachmentFile(
                    filename: previewFilename,
                    filetype: "image/png",
                    size: previewData.count,
                    width: Int(watermarked.size.width),
                    height: Int(watermarked.size.height),
                    token: token
                )
                try await context.account.network.uploadToMinIO(
                    url: previewUpload.url,
                    data: previewData,
                    contentType: "image/png"
                )
            }

            try await repository.addEmoji(
                clanId: clanId,
                source: cdnURL,
                shortname: shortname,
                category: "Custom",
                isForSale: isForSale,
                id: requestId
            )
            context.engine.scheduleEmojiListNetworkSync()
            Toast.success(L(L10n.ClanSetting.Emojis.createSuccess))
        } catch {
            Toast.error(L(L10n.ClanSetting.Emojis.errorUpdating))
        }
    }

    private static func emojiId(fromUploadFilename filename: String) -> Int64? {
        let base = (filename as NSString).lastPathComponent
        let name = (base as NSString).deletingPathExtension
        return Int64(name)
    }

    private struct PickedEmojiImage {
        let data: Data
        let contentType: String
        let isGIF: Bool
    }

    private struct EmojiUploadPayload {
        let data: Data
        let contentType: String
        let width: Int
        let height: Int
    }

    private static func prepareUploadPayload(image: UIImage, picked: PickedEmojiImage) -> EmojiUploadPayload? {
        if picked.isGIF {
            return EmojiUploadPayload(
                data: picked.data,
                contentType: "image/gif",
                width: Int(image.size.width),
                height: Int(image.size.height)
            )
        }
        let dimensions = ClanGraphicImageUtils.uploadDimensions(for: image)
        if let webpData = ClanGraphicImageUtils.resizedWebPData(from: image) {
            return EmojiUploadPayload(
                data: webpData,
                contentType: "image/webp",
                width: dimensions.width,
                height: dimensions.height
            )
        }
        guard let jpegData = ClanGraphicImageUtils.resizedJPEGData(from: image) else { return nil }
        return EmojiUploadPayload(
            data: jpegData,
            contentType: "image/jpeg",
            width: dimensions.width,
            height: dimensions.height
        )
    }

    private static func pickedEmojiImage(
        image: UIImage,
        info: [UIImagePickerController.InfoKey: Any]
    ) -> PickedEmojiImage? {
        if info[.editedImage] != nil {
            guard let data = image.jpegData(compressionQuality: 1.0) else { return nil }
            return PickedEmojiImage(data: data, contentType: "image/jpeg", isGIF: false)
        }
        if let url = info[.imageURL] as? URL,
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            if ClanGraphicImageUtils.isGIF(data: data) {
                return PickedEmojiImage(data: data, contentType: "image/gif", isGIF: true)
            }
            let ext = fileExtension(for: url.pathExtension, data: data)
            return PickedEmojiImage(data: data, contentType: mimeType(for: ext), isGIF: false)
        }
        guard let data = image.jpegData(compressionQuality: 1.0) else { return nil }
        return PickedEmojiImage(data: data, contentType: "image/jpeg", isGIF: false)
    }

    private static func fileExtension(for urlExt: String, data: Data) -> String {
        let normalized = urlExt.lowercased()
        if !normalized.isEmpty, mimeType(for: normalized) != "application/octet-stream" {
            return normalized == "jpeg" ? "jpg" : normalized
        }
        return inferredExtension(from: data) ?? "jpg"
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    private static func inferredExtension(from data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           bytes.count >= 12,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "webp"
        }
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            switch brand {
            case "heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs": return "heic"
            case "mif1", "msf1": return "heif"
            default: break
            }
        }
        return nil
    }

}
