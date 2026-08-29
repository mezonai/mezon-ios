import UIKit

final class ClanStickersViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let repository: StickersRepository

    private var stickers: [CachedClanStickerRecord] = []
    private var clanMembers: [Int64: ClanMemberRecord] = [:]
    private weak var openSwipeCell: StickerItemCell?
    private var isSwipeInteractionActive = false

    private static let listHorizontalInset: CGFloat = 16
    private static let maxUploadFileSize = 512 * 1024
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
        t.register(StickerItemCell.self, forCellReuseIdentifier: StickerItemCell.reuseId)
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
        uploadButton.setTitle(L(L10n.ClanSetting.Stickers.uploadButton), for: .normal)
        uploadButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        uploadButton.setTitleColor(.white, for: .normal)
        uploadButton.backgroundColor = UIColor.theme.bgViolet
        uploadButton.layer.cornerRadius = 22.sh
        uploadButton.clipsToBounds = true
        uploadButton.addTarget(self, action: #selector(addStickerTapped), for: .touchUpInside)

        requirementsTitleLabel.text = L(L10n.ClanSetting.Stickers.uploadRequirementsTitle).uppercased()
        requirementsTitleLabel.font = .systemFont(ofSize: 13.sf, weight: .bold)
        requirementsTitleLabel.textColor = UIColor.theme.textStrong

        requirementsStack.axis = .vertical
        requirementsStack.spacing = 10.sh
        requirementsStack.alignment = .fill
        requirementsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        [
            L(L10n.ClanSetting.Stickers.uploadRequirement1),
            L(L10n.ClanSetting.Stickers.uploadRequirement2),
            L(L10n.ClanSetting.Stickers.uploadRequirement3)
        ].forEach { requirementsStack.addArrangedSubview(makeRequirementRow(text: $0)) }

        [uploadButton, requirementsTitleLabel, requirementsStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            tableHeaderContainer.addSubview($0)
        }

        NSLayoutConstraint.activate([
            uploadButton.topAnchor.constraint(equalTo: tableHeaderContainer.topAnchor, constant: 8.sh),
            uploadButton.leadingAnchor.constraint(equalTo: tableHeaderContainer.leadingAnchor, constant: 16.sw),
            uploadButton.trailingAnchor.constraint(equalTo: tableHeaderContainer.trailingAnchor, constant: -16.sw),
            uploadButton.heightAnchor.constraint(equalToConstant: 44.sh),

            requirementsTitleLabel.topAnchor.constraint(equalTo: uploadButton.bottomAnchor, constant: Self.uploadSectionSpacing),
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
        self.repository = StickersRepository(context: context)
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
            UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        headerTitleLabel.text = L(L10n.ClanSetting.sticker)
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
            selector: #selector(handleStickersChanged),
            name: .mezonStickerListDidUpdate,
            object: nil
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
        if #available(iOS 13.0, *) {
            fetchClanMembersIfNeeded()
        }
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
        applyStickerListChrome()
        tableView.reloadData()
    }

    private func applyStickerListChrome() {
        tableView.isHidden = false
        if stickers.isEmpty {
            tableView.backgroundColor = UIColor.theme.primary
            tableView.layer.cornerRadius = 0
        } else {
            tableView.backgroundColor = UIColor.theme.secondary
            tableView.layer.cornerRadius = 12.swh
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
        applyStickerListChrome()
        tableView.tableHeaderView = nil
        tableView.frame = CGRect(
            x: inset,
            y: listTop,
            width: contentWidth,
            height: layout.size.height - listTop
        )
        if stickers.isEmpty {
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        } else if abs(lastTableHeaderWidth - layout.size.width) > 0.5 {
            lastTableHeaderWidth = layout.size.width
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    private var currentUserId: Int64 {
        Int64(context.currentUser?.id ?? "") ?? 0
    }

    private var hasClanStickerAdminPermission: Bool {
        let perms = context.rolePermissions
        return perms.isClanOwner(clanId: clanId)
            || perms.hasClanPermission(.administrator, clanId: clanId)
            || perms.canManageClan(clanId: clanId)
    }

    private func canEdit(_ sticker: CachedClanStickerRecord) -> Bool {
        hasClanStickerAdminPermission || (currentUserId != 0 && currentUserId == sticker.creatorID)
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

    @objc private func handleStickersChanged() {
        reloadData()
    }

    @objc private func addStickerTapped() {
        if #available(iOS 13.0, *) {
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true
            present(picker, animated: true)
        }
    }

    private func reloadData() {
        stickers = repository.stickers(clanId: clanId)
        let members = context.engine.account.postbox.read { $0.getClanMembers(clanId: self.clanId) }
        clanMembers = Dictionary(members.map { ($0.userId, $0) }, uniquingKeysWith: { $1 })

        let atLimit = repository.isAtUploadLimit(clanId: clanId)
        uploadButton.isEnabled = !atLimit
        uploadButton.alpha = atLimit ? 0.5 : 1.0
        tableView.reloadData()
        applyStickerListChrome()
        if let layout = currentlyAppliedLayout {
            applyChromeLayout(layout)
        }
    }

    @available(iOS 13.0, *)
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
                    self.clanMembers = Dictionary(records.map { ($0.userId, $0) }, uniquingKeysWith: { $1 })
                    self.tableView.reloadData()
                }
            } catch {}
        }
    }

    private func validateShortname(_ name: String, excludingId: Int64? = nil) -> Bool {
        let trimmed = ClanStickerNameValidator.normalized(name)
        guard ClanStickerNameValidator.isValid(trimmed) else {
            Toast.error(String(
                format: L(L10n.ClanSetting.Stickers.validateName),
                ClanStickerNameValidator.minLength,
                ClanStickerNameValidator.maxLength
            ))
            return false
        }
        guard !stickers.contains(where: { $0.shortname == trimmed && $0.id != excludingId }) else {
            Toast.error(L(L10n.ClanSetting.Stickers.duplicateName))
            return false
        }
        return true
    }

    @available(iOS 13.0, *)
    private func commitShortnameChange(
        for sticker: CachedClanStickerRecord,
        newName: String,
        completion: @escaping (Bool) -> Void
    ) {
        let text = ClanStickerNameValidator.normalized(newName)
        guard !text.isEmpty, text != sticker.shortname else {
            completion(true)
            return
        }
        guard validateShortname(text, excludingId: sticker.id) else {
            completion(false)
            return
        }
        Task {
            do {
                try await repository.updateSticker(
                    id: sticker.id,
                    clanId: clanId,
                    source: sticker.source,
                    shortname: text,
                    category: sticker.category
                )
                await MainActor.run {
                    Toast.success(L(L10n.ClanSetting.Stickers.updateSuccess))
                    completion(true)
                    reloadData()
                }
            } catch {
                await MainActor.run {
                    Toast.error(L(L10n.ClanSetting.Stickers.errorUpdating))
                    completion(false)
                }
            }
        }
    }

    @available(iOS 13.0, *)
    private func deleteSticker(_ sticker: CachedClanStickerRecord) {
        guard canEdit(sticker) else { return }
        MezonConfirm.present(
            from: self,
            title: L(L10n.ClanSetting.Stickers.deleteConfirmTitle),
            content: L(L10n.ClanSetting.Stickers.deleteConfirmDesc),
            confirmTitle: L(L10n.Common.delete),
            isDanger: true
        ) { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.repository.deleteSticker(
                        id: sticker.id,
                        clanId: self.clanId,
                        shortname: sticker.shortname
                    )
                    Toast.success(L(L10n.ClanSetting.Stickers.deleteSuccess))
                } catch {
                    Toast.error(L(L10n.ClanSetting.Stickers.errorUpdating))
                }
            }
        }
    }
}

extension ClanStickersViewController: UITableViewDataSource, UITableViewDelegate {
    private func emptyRowHeight(for tableView: UITableView) -> CGFloat {
        let boundsHeight = tableView.bounds.height
        if boundsHeight > 0 { return boundsHeight }
        guard let layout = currentlyAppliedLayout else { return 0 }
        let safeTop = resolvedSafeTop(for: layout)
        let listTop = safeTop + headerBarHeight + tableHeaderHeight
        return max(0, layout.size.height - listTop)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        stickers.isEmpty ? 1 : stickers.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard stickers.isEmpty else { return UITableView.automaticDimension }
        let height = emptyRowHeight(for: tableView)
        return height > 0 ? height : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StickerItemCell.reuseId, for: indexPath) as! StickerItemCell
        if stickers.isEmpty {
            cell.configureEmpty(text: L(L10n.ClanSetting.Stickers.empty))
            return cell
        }
        let rowCount = stickers.count
        let isLast = indexPath.row == rowCount - 1
        let sticker = stickers[indexPath.row]
        let creatorInfo = resolvedCreatorInfo(for: sticker.creatorID)
        let editable = canEdit(sticker)
        cell.configure(
            sticker: sticker,
            creatorAvatar: creatorInfo.avatar,
            creatorName: creatorInfo.name,
            isEditable: editable,
            isLast: isLast
        )
        cell.onShortnameCommit = { [weak self] newName, done in
            guard let self,
                  let current = self.stickers.first(where: { $0.id == sticker.id })
            else {
                done(false)
                return
            }
            if #available(iOS 13.0, *) {
                self.commitShortnameChange(for: current, newName: newName, completion: done)
            }
        }
        cell.onDelete = { [weak self] in
            if #available(iOS 13.0, *) {
                self?.deleteSticker(sticker)
            }
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
        guard !stickers.isEmpty else { return }
        openSwipeCell?.closeSwipe(animated: true)
        let sticker = stickers[indexPath.row]
        guard canEdit(sticker) else { return }
        (tableView.cellForRow(at: indexPath) as? StickerItemCell)?.beginEditingName()
    }

}

extension ClanStickersViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let image, let picked = Self.pickedStickerImage(image: image, info: info) else { return }
        guard picked.data.count <= Self.maxUploadFileSize else {
            Toast.error(L(L10n.ClanSetting.Stickers.uploadFileTooLarge))
            return
        }
        presentStickerPreview(image: image, picked: picked)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func presentStickerPreview(image: UIImage, picked: PickedStickerImage) {
        if #available(iOS 13.0, *) {
            let preview = ClanStickerPreviewViewController(image: image)
            preview.onConfirm = { [weak self, weak preview] shortname, isForSale in
                guard let self else { return }
                let trimmed = ClanStickerNameValidator.normalized(shortname)
                guard self.validateShortname(trimmed) else { return }
                preview?.dismiss(animated: true) {
                    Task { await self.uploadSticker(image: image, picked: picked, shortname: trimmed, isForSale: isForSale) }
                }
            }
            present(preview, animated: true)
        }
    }

    @available(iOS 13.0, *)
    private func uploadSticker(image: UIImage, picked: PickedStickerImage, shortname: String, isForSale: Bool) async {
        if repository.isAtUploadLimit(clanId: clanId) {
            return
        }
        let uploadId = Int64(Date().timeIntervalSince1970 * 1000)
        let filename = "stickers/\(uploadId).\(picked.fileExtension)"
        do {
            guard let token = await context.getToken() else { return }
            let upload = try await context.account.network.uploadAttachmentFile(
                filename: filename,
                filetype: picked.contentType,
                size: picked.data.count,
                width: Int(image.size.width),
                height: Int(image.size.height),
                token: token
            )
            try await context.account.network.uploadToMinIO(
                url: upload.url,
                data: picked.data,
                contentType: picked.contentType
            )
            let cdnURL = "\(MezonConfig.baseImgURL)/\(upload.filename)"
            ImageCache.shared.setImage(image, data: picked.data, forKey: cdnURL)
            let listIconSide = Int(40 * UIScreen.main.scale)
            let listProxyURL = ImgproxyURL.create(from: cdnURL, width: listIconSide, height: listIconSide)
            if !listProxyURL.isEmpty {
                ImageCache.shared.setImage(image, data: picked.data, forKey: listProxyURL)
            }

            var requestId = Self.stickerId(fromUploadFilename: upload.filename) ?? uploadId

            if isForSale, let watermarked = ClanGraphicImageUtils.blurredWatermarkedImage(from: image),
               let watermarkedData = watermarked.jpegData(compressionQuality: 0.85) {
                let previewUploadId = Int64(Date().timeIntervalSince1970 * 1000) + 1
                let previewFilename = "stickers/\(previewUploadId).jpg"
                let previewUpload = try await context.account.network.uploadAttachmentFile(
                    filename: previewFilename,
                    filetype: "image/jpeg",
                    size: watermarkedData.count,
                    width: Int(watermarked.size.width),
                    height: Int(watermarked.size.height),
                    token: token
                )
                try await context.account.network.uploadToMinIO(
                    url: previewUpload.url,
                    data: watermarkedData,
                    contentType: "image/jpeg"
                )
                requestId = Self.stickerId(fromUploadFilename: previewUpload.filename) ?? previewUploadId
            }

            try await repository.addSticker(
                clanId: clanId,
                source: cdnURL,
                shortname: shortname,
                category: "Among Us",
                isForSale: isForSale,
                id: requestId
            )
            Toast.success(L(L10n.ClanSetting.Stickers.createSuccess))
        } catch {
            Toast.error(L(L10n.ClanSetting.Stickers.errorUpdating))
        }
    }

    private static func stickerId(fromUploadFilename filename: String) -> Int64? {
        let base = (filename as NSString).lastPathComponent
        let name = (base as NSString).deletingPathExtension
        return Int64(name)
    }

    private struct PickedStickerImage {
        let data: Data
        let contentType: String
        let fileExtension: String
    }

    private static func pickedStickerImage(
        image: UIImage,
        info: [UIImagePickerController.InfoKey: Any]
    ) -> PickedStickerImage? {
        if info[.editedImage] != nil {
            guard let data = image.jpegData(compressionQuality: 1.0) else { return nil }
            return PickedStickerImage(data: data, contentType: "image/jpeg", fileExtension: "jpg")
        }
        if let url = info[.imageURL] as? URL,
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            let ext = fileExtension(for: url.pathExtension, data: data)
            return PickedStickerImage(data: data, contentType: mimeType(for: ext), fileExtension: ext)
        }
        guard let data = image.jpegData(compressionQuality: 1.0) else { return nil }
        return PickedStickerImage(data: data, contentType: "image/jpeg", fileExtension: "jpg")
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
