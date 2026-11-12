import UIKit
import AsyncDisplayKit

final class ClanCommunityViewController: BaseViewController {
    private let context: AccountContext
    private let clanId: Int64
    private var savedDraft: ClanCommunityDraft?
    private var bannerURL = ""
    private var isCommunity = false
    private var isSaving = false
    private var isDisabling = false
    private var isUploading = false
    private var imagePicker: PublicImagePicker?
    private var pendingClanUpdate: (clan: Mezon_Api_ClanDesc, resetDraft: Bool)?

    private let header = UIView()
    private let titleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let intro = UIStackView()
    private let introTitle = UILabel()
    private let introDescription = UILabel()
    private let enableButton = UIButton(type: .system)
    private let form = UIStackView()
    private let bannerLabel = UILabel()
    private let bannerButton = UIButton(type: .custom)
    private let bannerImage = UIImageView()
    private let bannerHint = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let saveButton = UIButton(type: .system)
    private let disableButton = UIButton(type: .system)
    private let descriptionField = CommunityTextField(limit: ClanCommunityDraft.descriptionLimit)
    private let aboutField = CommunityTextField(limit: ClanCommunityDraft.aboutLimit)
    private let hashtagsField = CommunityHashtagsField(tags: ClanCommunityHashtags.options)
    private let vanityField = CommunityVanityURLField(prefix: "\(MezonConfig.chatWebAppBaseURL)/clans/clan/")

    private var isBusy: Bool { isSaving || isUploading || isDisabling }
    private var canManageCommunity: Bool {
        context.rolePermissions.canManageCommunity(clanId: clanId)
    }
    private var draft: ClanCommunityDraft {
        ClanCommunityDraft(banner: bannerURL, description: descriptionField.text,
                           about: aboutField.text, shortURL: vanityField.text, hashtags: hashtagsField.selection)
    }
    private var canDisableCommunity: Bool {
        canManageCommunity && isCommunity && !isBusy && draft == savedDraft
    }

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
        attemptNavigation = { [weak self] _ in !(self?.isBusy ?? false) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let record = context.account.postbox.read({ $0.getClan(id: clanId) }),
              let clan = try? Mezon_Api_ClanDesc(serializedBytes: record.data) else {
            Toast.error(L(L10n.ClanSetting.Community.loadError))
            return
        }
        applyClan(clan, resetDraft: true)
        NotificationCenter.default.addObserver(self, selector: #selector(clanDescDidUpdate(_:)), name: Notification.Name("MezonClanDescUpdated"), object: nil)
    }

    @objc private func clanDescDidUpdate(_ notification: Notification) {
        guard let id = notification.userInfo?["clanId"] as? Int64, id == clanId,
              let data = notification.userInfo?["clanData"] as? Data,
              let clan = try? Mezon_Api_ClanDesc(serializedBytes: data) else { return }
        receiveClanUpdate(clan)
    }

    private func receiveClanUpdate(_ clan: Mezon_Api_ClanDesc) {
        let previousEnabled = pendingClanUpdate?.clan.isCommunity ?? isCommunity
        let reset = (pendingClanUpdate?.resetDraft ?? false) || previousEnabled != clan.isCommunity
        if isBusy {
            pendingClanUpdate = (clan, reset)
        } else {
            applyClan(clan, resetDraft: reset)
        }
    }

    private func applyPendingClanUpdate() {
        guard !isBusy, let pending = pendingClanUpdate else { return }
        pendingClanUpdate = nil
        applyClan(pending.clan, resetDraft: pending.resetDraft)
    }

    private func applyClan(_ clan: Mezon_Api_ClanDesc, resetDraft: Bool) {
        let incoming = ClanCommunityDraft(clan: clan)
        let reset = resetDraft || savedDraft == nil || isCommunity != clan.isCommunity
        let value: ClanCommunityDraft
        if !reset, let savedDraft {
            value = draft.mergingUneditedFields(from: incoming, saved: savedDraft)
        } else {
            value = incoming
        }
        savedDraft = incoming
        if reset {
            view.endEditing(true)
            if imagePicker != nil {
                imagePicker = nil
                presentedViewController?.dismiss(animated: true)
            }
            isCommunity = clan.isCommunity
            intro.isHidden = isCommunity
            form.isHidden = !isCommunity
            scrollView.setContentOffset(.zero, animated: false)
        }
        setDraft(value)
        updateControls()
    }

    private func setDraft(_ value: ClanCommunityDraft) {
        if bannerURL != value.banner {
            bannerURL = value.banner
            bannerImage.image = nil
            if !value.banner.isEmpty {
                ImageCache.shared.loadImage(urlString: value.banner) { [weak self] image in
                    guard let self, self.bannerURL == value.banner else { return }
                    self.bannerImage.image = image
                }
            }
        }
        if descriptionField.text != value.description { descriptionField.text = value.description }
        if aboutField.text != value.about { aboutField.text = value.about }
        if vanityField.text != value.shortURL { vanityField.text = value.shortURL }
        if hashtagsField.selection != value.hashtags { hashtagsField.selection = value.hashtags }
    }

    override func setupUI() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        backButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        [backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)
        content.axis = .vertical
        content.spacing = 28.sh
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        let illustration = UIImageView(image: UIImage(named: "ClanSetting/MezonCommunity"))
        illustration.backgroundColor = UIColor.theme.bgViolet
        illustration.contentMode = .scaleAspectFill
        illustration.clipsToBounds = true
        illustration.layer.cornerRadius = 16.swh
        content.addArrangedSubview(illustration)
        illustration.heightAnchor.constraint(equalTo: illustration.widthAnchor, multiplier: 0.54).isActive = true

        intro.axis = .vertical
        intro.spacing = 20.sh
        introTitle.font = .systemFont(ofSize: 24.sf, weight: .bold)
        introTitle.textAlignment = .center
        introDescription.font = .systemFont(ofSize: 16.sf)
        introDescription.textAlignment = .center
        introDescription.numberOfLines = 0
        [introTitle, introDescription, enableButton].forEach { intro.addArrangedSubview($0) }
        content.addArrangedSubview(intro)
        configurePrimaryButton(enableButton, action: #selector(startSetup))

        form.axis = .vertical
        form.spacing = 20.sh
        form.isHidden = true
        content.addArrangedSubview(form)
        let bannerSection = UIStackView(arrangedSubviews: [bannerLabel, bannerButton, bannerHint])
        bannerSection.axis = .vertical
        bannerSection.spacing = 8.sh
        bannerLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        bannerHint.font = .systemFont(ofSize: 13.sf)
        bannerHint.numberOfLines = 0
        bannerButton.layer.cornerRadius = 12.swh
        bannerButton.clipsToBounds = true
        bannerButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        bannerButton.addTarget(self, action: #selector(pickBanner), for: .touchUpInside)
        bannerButton.heightAnchor.constraint(equalTo: bannerButton.widthAnchor, multiplier: 9.0 / 16.0).isActive = true
        bannerImage.contentMode = .scaleAspectFill
        bannerImage.clipsToBounds = true
        bannerImage.isUserInteractionEnabled = false
        bannerImage.translatesAutoresizingMaskIntoConstraints = false
        bannerButton.addSubview(bannerImage)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        bannerButton.addSubview(spinner)
        [bannerSection, descriptionField, aboutField, hashtagsField, vanityField, saveButton, disableButton].forEach { form.addArrangedSubview($0) }
        configurePrimaryButton(saveButton, action: #selector(saveTapped))
        disableButton.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        disableButton.layer.cornerRadius = 10.swh
        let disableButtonHeight = disableButton.heightAnchor.constraint(equalToConstant: 52.sh)
        disableButtonHeight.priority = UILayoutPriority(999)
        disableButtonHeight.isActive = true
        disableButton.addTarget(self, action: #selector(requestDisableCommunity), for: .touchUpInside)
        let updateControls: () -> Void = { [weak self] in self?.updateControls() }
        descriptionField.onChange = updateControls
        aboutField.onChange = updateControls
        hashtagsField.onChange = updateControls
        vanityField.onChange = updateControls

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52.sh),
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16.sh),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16.sw),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16.sw),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32.sh),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32.sw),
            bannerImage.topAnchor.constraint(equalTo: bannerButton.topAnchor),
            bannerImage.bottomAnchor.constraint(equalTo: bannerButton.bottomAnchor),
            bannerImage.leadingAnchor.constraint(equalTo: bannerButton.leadingAnchor),
            bannerImage.trailingAnchor.constraint(equalTo: bannerButton.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: bannerButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: bannerButton.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        updateControls()
    }

    override func setupBindings() {
        disposables.add((context.engine.clanData.clanPermissionsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] id in
                guard let self, id == self.clanId else { return }
                self.updateControls()
            }))
        disposables.add((context.engine.clanData.clanRolesUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] id in
                guard let self, id == self.clanId else { return }
                self.updateControls()
            }))
    }

    private func configurePrimaryButton(_ button: UIButton, action: Selector) {
        button.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10.swh
        button.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    override func applyTheme() {
        let theme = UIColor.theme
        view.backgroundColor = theme.primary
        header.backgroundColor = theme.primary
        titleLabel.textColor = theme.textStrong
        titleLabel.text = L(L10n.ClanSetting.Community.title)
        backButton.tintColor = theme.textStrong
        introTitle.text = L(L10n.ClanSetting.Community.enableTitle)
        introTitle.textColor = theme.textStrong
        introDescription.text = L(L10n.ClanSetting.Community.introduction)
        introDescription.textColor = theme.text
        enableButton.setTitle(L(L10n.ClanSetting.enableCommunity), for: .normal)
        bannerLabel.attributedText = communityRequiredTitle(L(L10n.ClanSetting.Community.banner))
        bannerHint.text = L(L10n.ClanSetting.Community.bannerHint)
        bannerHint.textColor = theme.text
        bannerButton.backgroundColor = theme.secondaryWeight
        bannerButton.tintColor = theme.textDisabled
        spinner.color = theme.textStrong
        descriptionField.configure(title: L(L10n.ClanSetting.Community.description), placeholder: L(L10n.ClanSetting.Community.descriptionPlaceholder))
        aboutField.configure(title: L(L10n.ClanSetting.Community.about), placeholder: L(L10n.ClanSetting.Community.aboutPlaceholder))
        hashtagsField.configure()
        vanityField.configure(title: L(L10n.ClanSetting.Community.vanityURL), placeholder: L(L10n.ClanSetting.Community.vanityURLPlaceholder))
        disableButton.setTitleColor(.systemRed, for: .normal)
        disableButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
        updateControls()
    }

    private func updateControls() {
        let allowed = canManageCommunity && savedDraft != nil
        enableButton.isEnabled = allowed && !isBusy
        bannerButton.isEnabled = allowed && !isBusy
        form.isUserInteractionEnabled = allowed && !isBusy
        backButton.isEnabled = !isBusy
        saveButton.isEnabled = allowed && !isBusy && (!isCommunity || draft != savedDraft)
        saveButton.setTitle(L(isCommunity ? L10n.Common.saveChanges : L10n.ClanSetting.Community.enableAndSave), for: .normal)
        if isSaving { saveButton.setTitle(L(L10n.Common.loading), for: .normal) }
        disableButton.isHidden = !isCommunity
        disableButton.isEnabled = canDisableCommunity
        disableButton.setTitle(L(isDisabling ? L10n.Common.loading : L10n.ClanSetting.Community.disable), for: .normal)
        disableButton.alpha = disableButton.isEnabled ? 1 : 0.5
        [enableButton, saveButton].forEach {
            $0.backgroundColor = UIColor.theme.bgViolet
            $0.alpha = $0.isEnabled ? 1 : 0.5
        }
        if isUploading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    @objc private func closeTapped() {
        guard !isBusy else { return }
        navigationController?.popViewController(animated: true)
    }

    @objc private func startSetup() {
        guard canManageCommunity, !isBusy else { return }
        if hashtagsField.selection.isEmpty {
            hashtagsField.selection = ClanCommunityHashtags.defaultSelection
        }
        intro.isHidden = true
        form.isHidden = false
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = scrollView.convert(scrollView.bounds, to: view).intersection(view.convert(frame, from: nil)).height
        scrollView.contentInset.bottom = max(0, overlap - view.safeAreaInsets.bottom)
        scrollView.verticalScrollIndicatorInsets.bottom = scrollView.contentInset.bottom
    }

    @objc private func pickBanner() {
        guard canManageCommunity, !isBusy, imagePicker == nil else { return }
        let picker = PublicImagePicker(allowsEditing: false, maxBytes: ClanCommunityDraft.bannerByteLimit,
                                       tooLargeMessage: L(L10n.ClanSetting.Community.bannerTooLarge), previewPixelSize: 1920) { [weak self] selection in
            guard let self, self.imagePicker != nil else { return }
            self.imagePicker = nil
            guard let selection else { return }
            self.uploadBanner(selection)
        }
        imagePicker = picker
        picker.present(from: self)
    }

    private func uploadBanner(_ selection: PublicImageSelection) {
        isUploading = true
        updateControls()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isUploading = false
                self.applyPendingClanUpdate()
                self.updateControls()
            }
            do {
                guard (selection.sourceByteCount ?? 0) <= ClanCommunityDraft.bannerByteLimit else {
                    Toast.error(L(L10n.ClanSetting.Community.bannerTooLarge))
                    return
                }
                let data = await Task.detached(priority: .userInitiated) {
                    selection.preservedData ?? selection.image.jpegData(compressionQuality: 0.85)
                }.value
                guard let data else { throw MezonError.invalidResponse }
                guard data.count <= ClanCommunityDraft.bannerByteLimit else {
                    Toast.error(L(L10n.ClanSetting.Community.bannerTooLarge))
                    return
                }
                guard let token = await self.context.getToken() else { return }
                let url = try await AttachmentUploader.shared.uploadPublicImage(
                    data: data, filename: "community-banner.jpg", filetype: selection.mimeType,
                    token: token, network: self.context.account.network, originalFilename: selection.originalFilename
                )
                self.bannerURL = url
                self.bannerImage.image = selection.image
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    @objc private func saveTapped() {
        guard canManageCommunity, !isBusy, let baseline = savedDraft else { return }
        view.endEditing(true)
        let editing = draft
        isSaving = true
        updateControls()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isSaving = false
                self.applyPendingClanUpdate()
                self.updateControls()
            }
            do {
                guard let token = await self.context.getToken() else { return }
                guard let record = self.context.account.postbox.read({ $0.getClan(id: self.clanId) }) else { return }
                let current = try Mezon_Api_ClanDesc(serializedBytes: record.data)
                guard current.isCommunity == self.isCommunity, self.pendingClanUpdate?.resetDraft != true else {
                    self.receiveClanUpdate(current)
                    return
                }
                let value = editing.mergingUneditedFields(from: ClanCommunityDraft(clan: current), saved: baseline).sanitized
                guard value.isValid else {
                    Toast.error(L(L10n.ClanSetting.Community.requiredFields))
                    return
                }
                let request = value.updateRequest(clanId: self.clanId, current: current)
                try await self.context.account.network.updateClanDesc(request: request, token: token)
                let latest = try self.updateLocalClan(unchangedSince: current) { clan in value.apply(to: &clan) }
                self.savedDraft = value
                self.setDraft(value)
                if let latest { self.receiveClanUpdate(latest) }
                Toast.success(L(L10n.ClanSetting.Community.saved))
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    @objc private func requestDisableCommunity() {
        guard canDisableCommunity else { return }
        let alert = UIAlertController(
            title: L(L10n.ClanSetting.Community.disableTitle),
            message: L(L10n.ClanSetting.Community.disableMessage),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.ClanSetting.Community.disable), style: .destructive) { [weak self] _ in
            self?.disableCommunity()
        })
        present(alert, animated: true)
    }

    private func disableCommunity() {
        guard canDisableCommunity else { return }
        view.endEditing(true)
        isDisabling = true
        updateControls()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isDisabling = false
                self.applyPendingClanUpdate()
                self.updateControls()
            }
            do {
                guard let token = await self.context.getToken() else { return }
                guard let record = self.context.account.postbox.read({ $0.getClan(id: self.clanId) }) else { return }
                let current = try Mezon_Api_ClanDesc(serializedBytes: record.data)
                guard current.isCommunity == self.isCommunity, self.pendingClanUpdate?.resetDraft != true else {
                    self.receiveClanUpdate(current)
                    return
                }
                let request = ClanCommunityDraft.disableRequest(clanId: self.clanId, current: current)
                try await self.context.account.network.updateClanDesc(request: request, token: token)
                let latest = try self.updateLocalClan(unchangedSince: current) { $0.isCommunity = false }
                if let latest { self.receiveClanUpdate(latest) }
                Toast.success(L(L10n.ClanSetting.Community.disabled))
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func updateLocalClan(unchangedSince original: Mezon_Api_ClanDesc,
                                 _ update: (inout Mezon_Api_ClanDesc) -> Void) throws -> Mezon_Api_ClanDesc? {
        var writeError: Error?
        var result: Mezon_Api_ClanDesc?
        context.account.postbox.writeSync { tx in
            guard let latest = tx.getClan(id: clanId) else { return }
            do {
                var clan = try Mezon_Api_ClanDesc(serializedBytes: latest.data)
                if clan.isCommunity == original.isCommunity && ClanCommunityDraft(clan: clan) == ClanCommunityDraft(clan: original) {
                    update(&clan)
                    tx.updateClans([ClanRecord(id: latest.id, name: latest.name, icon: latest.icon,
                                              ownerId: latest.ownerId, data: try clan.serializedData())])
                }
                result = clan
            } catch { writeError = error }
        }
        if let writeError { throw writeError }
        return result
    }
}

private func communityRequiredTitle(_ title: String) -> NSAttributedString {
    let text = NSMutableAttributedString(string: title, attributes: [.foregroundColor: UIColor.theme.textStrong])
    text.append(NSAttributedString(string: " *", attributes: [.foregroundColor: UIColor.systemRed]))
    return text
}

private final class CommunityTextField: UIStackView, UITextViewDelegate {
    var onChange: (() -> Void)?
    private let limit: Int
    private let titleLabel = UILabel()
    private let input = UITextView()
    private let placeholder = UILabel()
    private let counter = UILabel()
    var text: String {
        get { input.text ?? "" }
        set { input.text = newValue; updateCount() }
    }

    init(limit: Int) {
        self.limit = limit
        super.init(frame: .zero)
        axis = .vertical
        spacing = 6.sh
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.numberOfLines = 0
        input.font = .systemFont(ofSize: 16.sf)
        input.layer.cornerRadius = 12.swh
        input.textContainerInset = UIEdgeInsets(top: 12.sh, left: 8.sw, bottom: 12.sh, right: 8.sw)
        input.delegate = self
        input.heightAnchor.constraint(equalToConstant: 88.sh).isActive = true
        placeholder.font = input.font
        placeholder.numberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        input.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 12.sh),
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 13.sw),
            placeholder.widthAnchor.constraint(equalTo: input.widthAnchor, constant: -26.sw)
        ])
        counter.font = .systemFont(ofSize: 12.sf)
        counter.textAlignment = .right
        [titleLabel, input, counter].forEach { addArrangedSubview($0) }
        updateCount()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, placeholder: String) {
        titleLabel.attributedText = communityRequiredTitle(title)
        self.placeholder.text = placeholder
        input.textColor = UIColor.theme.textStrong
        input.backgroundColor = UIColor.theme.secondaryWeight
        self.placeholder.textColor = UIColor.theme.textDisabled
        counter.textColor = UIColor.theme.text
        input.accessibilityLabel = title
    }

    private func updateCount() {
        placeholder.isHidden = !text.isEmpty
        counter.text = "\(text.unicodeScalars.count)/\(limit)"
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView.markedTextRange == nil else { return }
        let normalized = ClanCommunityDraft.limited(text, to: limit)
        if normalized != text { text = normalized }
        updateCount()
        onChange?()
    }
}

private final class CommunityHashtagsField: UIStackView {
    var onChange: (() -> Void)?
    var selection: [String] {
        get { selectedTags }
        set {
            selectedTags = ClanCommunityHashtags.normalized(newValue)
            updateSelection()
        }
    }

    private var selectedTags: [String] = []
    private let baseTags: [String]
    private var tags: [String] = []
    private let titleLabel = UILabel()
    private let hashLabel = UILabel()
    private let countLabel = UILabel()
    private let badge = UIStackView()
    private let descriptionLabel = UILabel()
    private let card = UIStackView()
    private let tagRows = UIStackView()
    private let separator = UIView()
    private let hintLabel = UILabel()
    private var dots: [UIView] = []
    private var buttons: [UIButton] = []
    private let selectedCheckmark: UIImage = {
        let size = CGSize(width: 16.sf, height: 16.sf)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let checkmark = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.sf, weight: .bold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            checkmark?.draw(in: CGRect(x: 3.sf, y: 3.sf, width: 10.sf, height: 10.sf))
        }
    }()

    init(tags: [String]) {
        self.baseTags = tags
        super.init(frame: .zero)
        axis = .vertical
        spacing = 12.sh
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.numberOfLines = 0
        hashLabel.text = "#"
        hashLabel.font = .systemFont(ofSize: 20.sf, weight: .bold)
        hashLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.axis = .horizontal
        badge.alignment = .center
        badge.spacing = 4.sw
        badge.isLayoutMarginsRelativeArrangement = true
        badge.layoutMargins = UIEdgeInsets(top: 6.sh, left: 8.sw, bottom: 6.sh, right: 8.sw)
        badge.layer.cornerRadius = 14.swh
        badge.layer.borderWidth = 1
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.addArrangedSubview(countLabel)
        for _ in 0..<ClanCommunityHashtags.maximumCount {
            let dot = UIView()
            dot.layer.cornerRadius = 3.swh
            dot.widthAnchor.constraint(equalToConstant: 6.swh).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6.swh).isActive = true
            badge.addArrangedSubview(dot)
            dots.append(dot)
        }
        let header = UIStackView(arrangedSubviews: [hashLabel, titleLabel, badge])
        header.alignment = .center
        header.spacing = 8.sw
        descriptionLabel.font = .systemFont(ofSize: 14.sf)
        descriptionLabel.numberOfLines = 0
        card.axis = .vertical
        card.spacing = 10.sh
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 12.sh, left: 12.sw, bottom: 12.sh, right: 12.sw)
        card.layer.cornerRadius = 14.swh
        card.layer.borderWidth = 1
        tagRows.axis = .vertical
        tagRows.spacing = 10.sh
        card.addArrangedSubview(tagRows)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        card.addArrangedSubview(separator)
        hintLabel.font = .systemFont(ofSize: 12.sf)
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .right
        card.addArrangedSubview(hintLabel)
        [header, descriptionLabel, card].forEach { addArrangedSubview($0) }
        configure()
    }

    private func updateTagButtons() {
        let available = ClanCommunityHashtags.normalized(baseTags + selection)
        guard tags != available else { return }
        tags = available
        for row in tagRows.arrangedSubviews {
            tagRows.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        buttons.removeAll()
        for (index, tag) in tags.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.accessibilityIdentifier = AccessibilityID.ClanSettings.communityHashtag(tag)
            button.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.lineBreakMode = .byWordWrapping
            button.contentEdgeInsets = UIEdgeInsets(top: 8.sh, left: 8.sw, bottom: 8.sh, right: 8.sw)
            button.layer.cornerRadius = 12.swh
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52.sh).isActive = true
            button.addTarget(self, action: #selector(toggleHashtag(_:)), for: .touchUpInside)
            buttons.append(button)
        }
        for index in stride(from: 0, to: buttons.count, by: 2) {
            let row = UIStackView(arrangedSubviews: Array(buttons[index..<min(index + 2, buttons.count)]))
            row.distribution = .fillEqually
            row.spacing = 8.sw
            tagRows.addArrangedSubview(row)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure() {
        let theme = UIColor.theme
        titleLabel.attributedText = communityRequiredTitle(L(L10n.ClanSetting.Community.hashtagsTitle))
        hashLabel.textColor = theme.bgViolet
        countLabel.textColor = theme.textStrong
        badge.backgroundColor = theme.secondaryWeight
        badge.layer.borderColor = theme.borderDim.cgColor
        descriptionLabel.text = L(L10n.ClanSetting.Community.hashtagsDescription)
        descriptionLabel.textColor = theme.text
        card.backgroundColor = theme.secondaryWeight
        card.layer.borderColor = theme.borderDim.cgColor
        separator.backgroundColor = theme.borderDim
        hintLabel.textColor = theme.text
        updateSelection()
    }

    private func updateSelection() {
        updateTagButtons()
        let theme = UIColor.theme
        let maximum = ClanCommunityHashtags.maximumCount
        countLabel.text = "\(selection.count)/\(maximum)"
        hintLabel.text = selection.count >= maximum
            ? L(L10n.ClanSetting.Community.hashtagsMaximum)
            : selection.count <= ClanCommunityHashtags.minimumCount
                ? L(L10n.ClanSetting.Community.hashtagsMinimum) : ""
        for (index, dot) in dots.enumerated() {
            dot.backgroundColor = index < selection.count ? .systemBlue : theme.borderDim
        }
        for (index, button) in buttons.enumerated() {
            let tag = tags[index]
            let selected = selection.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            let label = DiscoverClanHashtags.label(tag)
            let title = NSMutableAttributedString(string: "#  ", attributes: [.foregroundColor: UIColor.systemBlue])
            title.append(NSAttributedString(string: label, attributes: [.foregroundColor: theme.textStrong]))
            if selected {
                title.append(NSAttributedString(string: "  "))
                let checkmark = NSTextAttachment()
                checkmark.image = selectedCheckmark
                let font = button.titleLabel?.font ?? .systemFont(ofSize: 14.sf, weight: .semibold)
                checkmark.bounds = CGRect(x: 0, y: (font.capHeight - 16.sf) / 2, width: 16.sf, height: 16.sf)
                title.append(NSAttributedString(attachment: checkmark))
            }
            button.setAttributedTitle(title, for: .normal)
            button.isSelected = selected
            button.isEnabled = selected || selection.count < maximum
            button.alpha = button.isEnabled ? 1 : 0.4
            button.layer.borderWidth = selected ? 2 : 1
            button.layer.borderColor = selected ? UIColor.systemBlue.cgColor : theme.borderDim.cgColor
            button.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.1) : theme.secondaryLight
            button.accessibilityLabel = label
            if selected { button.accessibilityTraits.insert(.selected) }
            else { button.accessibilityTraits.remove(.selected) }
            button.accessibilityHint = selected && selection.count == ClanCommunityHashtags.minimumCount
                ? L(L10n.ClanSetting.Community.hashtagsMinimum) : nil
        }
    }

    @objc private func toggleHashtag(_ sender: UIButton) {
        let updated = ClanCommunityHashtags.toggling(tags[sender.tag], in: selection)
        guard updated != selection else { return }
        selection = updated
        onChange?()
    }
}

private final class CommunityVanityURLField: UIStackView, UITextFieldDelegate {
    var onChange: (() -> Void)?
    private let titleLabel = UILabel()
    private let container = UIView()
    private let prefixContainer = UIView()
    private let prefixLabel = UILabel()
    private let separator = UIView()
    private let input = UITextField()
    private let counter = UILabel()

    var text: String {
        get { input.text ?? "" }
        set { input.text = newValue; updateCount() }
    }

    init(prefix: String) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 6.sh
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.numberOfLines = 0
        container.layer.cornerRadius = 12.swh
        container.layer.borderWidth = 1
        container.clipsToBounds = true
        container.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        prefixLabel.text = prefix
        prefixLabel.font = .systemFont(ofSize: 16.sf)
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        input.font = .systemFont(ofSize: 16.sf)
        input.keyboardType = .asciiCapable
        input.autocapitalizationType = .none
        input.autocorrectionType = .no
        input.spellCheckingType = .no
        input.returnKeyType = .done
        input.delegate = self
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        input.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        prefixContainer.addSubview(prefixLabel)
        [prefixContainer, separator, input].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        NSLayoutConstraint.activate([
            prefixContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            prefixContainer.topAnchor.constraint(equalTo: container.topAnchor),
            prefixContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            prefixLabel.leadingAnchor.constraint(equalTo: prefixContainer.leadingAnchor, constant: 10.sw),
            prefixLabel.trailingAnchor.constraint(equalTo: prefixContainer.trailingAnchor, constant: -10.sw),
            prefixLabel.centerYAnchor.constraint(equalTo: prefixContainer.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: prefixContainer.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            input.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 10.sw),
            input.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12.sw),
            input.topAnchor.constraint(equalTo: container.topAnchor),
            input.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        counter.font = .systemFont(ofSize: 12.sf)
        counter.textAlignment = .right
        [titleLabel, container, counter].forEach { addArrangedSubview($0) }
        updateCount()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, placeholder: String) {
        let theme = UIColor.theme
        titleLabel.attributedText = communityRequiredTitle(title)
        prefixLabel.textColor = theme.textDisabled
        prefixContainer.backgroundColor = theme.secondaryLight
        container.backgroundColor = theme.secondaryWeight
        container.layer.borderColor = theme.borderDim.cgColor
        separator.backgroundColor = theme.borderDim
        input.textColor = theme.textStrong
        input.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: theme.textDisabled])
        input.accessibilityLabel = title
        counter.textColor = theme.text
    }

    private func updateCount() {
        counter.text = "\(text.unicodeScalars.count)/\(ClanCommunityDraft.vanityURLLimit)"
    }

    @objc private func textChanged() {
        guard input.markedTextRange == nil else { return }
        let normalized = ClanCommunityDraft.normalizedShortURL(text)
        if normalized != text { text = normalized }
        updateCount()
        onChange?()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
