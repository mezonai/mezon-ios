import UIKit
import AsyncDisplayKit

final class WebhookAvatarCache {
    static let shared = NSCache<NSString, UIImage>()
}

final class WebhookEditViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private var webhook: Mezon_Api_Webhook

    private var webhookName: String
    private var avatarURL: String
    private var selectedImage: UIImage?
    private var selectedImageData: Data?
    private var selectedChannelId: Int64
    private var isSaving: Bool = false

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let avatarContainer = UIView()
    private let avatarView = TextAvatarView(username: "", size: 80)
    private let avatarImageView = UIImageView()
    private let avatarHintLabel = UILabel()

    private let nameField = UITextField()
    private let nameErrorLabel = UILabel()
    private let channelLabel = UILabel()
    private let channelIconView = UIImageView()
    private let urlLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let resetTokenButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    private var imageTask: URLSessionDataTask?
    
    private let isClanIntegration: Bool
    
    var onWebhookUpdated: (() -> Void)?

    init(context: AccountContext, clanId: Int64, channelId: Int64, webhook: Mezon_Api_Webhook, isClanIntegration: Bool = false) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.webhook = webhook
        self.webhookName = webhook.webhookName
        self.avatarURL = webhook.avatar
        self.selectedChannelId = webhook.channelID
        self.isClanIntegration = isClanIntegration
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupScrollView()
        if #available(iOS 13.0, *) {
            setupAvatarSection()
        }
        setupNameSection()
        if !isClanIntegration {
            setupChannelSection()
        }
        setupURLSection()
        setupActionButtonsSection()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        populateData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        saveButton.tintColor = t.bgViolet
        avatarHintLabel.textColor = t.textDisabled
        nameField.textColor = t.textStrong
        nameField.backgroundColor = t.secondary
        channelLabel.textColor = t.textStrong
        urlLabel.textColor = t.textDisabled
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.text = L(L10n.Webhook.editTitle)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center

        saveButton.setTitle(L(L10n.Common.save), for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        saveButton.tintColor = UIColor.theme.bgViolet
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        [backButton, titleLabel, saveButton].forEach {
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
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 20.sh
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw)
        ])
    }

    private func setupAvatarSection() {
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.isUserInteractionEnabled = true
        avatarContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickAvatarTapped)))

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.isUserInteractionEnabled = false
        avatarContainer.addSubview(avatarView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 40
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.isHidden = true
        avatarContainer.addSubview(avatarImageView)

        let uploadIndicatorContainer = UIView()
        uploadIndicatorContainer.backgroundColor = .white
        uploadIndicatorContainer.layer.cornerRadius = 14.swh
        uploadIndicatorContainer.layer.masksToBounds = true
        uploadIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let uploadIcon = UIImageView(image: UIImage(named: "ChannelSetting/UploadPlusIcon")?.withRenderingMode(.alwaysTemplate))
        uploadIcon.tintColor = .gray
        uploadIcon.contentMode = .scaleAspectFit
        uploadIcon.translatesAutoresizingMaskIntoConstraints = false
        
        uploadIndicatorContainer.addSubview(uploadIcon)
        avatarContainer.addSubview(uploadIndicatorContainer)

        avatarHintLabel.text = L(L10n.Webhook.recommendImage)
        avatarHintLabel.font = .systemFont(ofSize: 12.sf)
        avatarHintLabel.textColor = UIColor.theme.textDisabled
        avatarHintLabel.textAlignment = .center
        avatarHintLabel.numberOfLines = 0
        avatarHintLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatarHintLabel)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 80.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 80.swh),

            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 80.swh),
            avatarImageView.heightAnchor.constraint(equalToConstant: 80.swh),

            uploadIndicatorContainer.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: 0),
            uploadIndicatorContainer.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 0),
            uploadIndicatorContainer.widthAnchor.constraint(equalToConstant: 28.swh),
            uploadIndicatorContainer.heightAnchor.constraint(equalToConstant: 28.swh),
            
            uploadIcon.centerXAnchor.constraint(equalTo: uploadIndicatorContainer.centerXAnchor),
            uploadIcon.centerYAnchor.constraint(equalTo: uploadIndicatorContainer.centerYAnchor),
            uploadIcon.widthAnchor.constraint(equalToConstant: 16.swh),
            uploadIcon.heightAnchor.constraint(equalToConstant: 16.swh),

            avatarHintLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 10.sh),
            avatarHintLabel.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarHintLabel.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarHintLabel.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor)
        ])

        stackView.addArrangedSubview(avatarContainer)
    }

    private func setupNameSection() {
        let section = createSection(title: L(L10n.Webhook.name))

        nameField.font = .systemFont(ofSize: 15.sf)
        nameField.textColor = UIColor.theme.textStrong
        nameField.backgroundColor = UIColor.theme.secondary
        nameField.layer.cornerRadius = 10
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        nameField.leftViewMode = .always
        nameField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        nameField.rightViewMode = .always
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        section.addArrangedSubview(nameField)
        nameField.heightAnchor.constraint(equalToConstant: 44.sh).isActive = true

        nameErrorLabel.text = L(L10n.Webhook.nameLengthError)
        nameErrorLabel.font = .systemFont(ofSize: 12.sf)
        nameErrorLabel.textColor = .mezonError
        nameErrorLabel.numberOfLines = 0
        nameErrorLabel.isHidden = true
        section.addArrangedSubview(nameErrorLabel)

        stackView.addArrangedSubview(section)
    }

    private func setupChannelSection() {
        let section = createSection(title: L(L10n.Webhook.channel))

        let channelRow = UIButton(type: .system)
        channelRow.backgroundColor = UIColor.theme.secondary
        channelRow.layer.cornerRadius = 10
        channelRow.translatesAutoresizingMaskIntoConstraints = false
        channelRow.addTarget(self, action: #selector(channelTapped), for: .touchUpInside)

        channelIconView.image = UIImage.mezonSystemImage("number")?.withRenderingMode(.alwaysTemplate)
        channelIconView.tintColor = UIColor.theme.textDisabled
        channelIconView.contentMode = .scaleAspectFit
        channelIconView.translatesAutoresizingMaskIntoConstraints = false
        channelIconView.isUserInteractionEnabled = false

        channelLabel.font = .systemFont(ofSize: 15.sf)
        channelLabel.textColor = UIColor.theme.textStrong
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        channelLabel.isUserInteractionEnabled = false
        
        let arrowImage = UIImage(named: "Channel/ChevronRight")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate)
        let arrowIcon = UIImageView(image: arrowImage)
        arrowIcon.tintColor = UIColor.theme.textStrong
        arrowIcon.contentMode = .scaleAspectFit
        arrowIcon.translatesAutoresizingMaskIntoConstraints = false
        arrowIcon.isUserInteractionEnabled = false

        channelRow.addSubview(channelIconView)
        channelRow.addSubview(channelLabel)
        channelRow.addSubview(arrowIcon)

        NSLayoutConstraint.activate([
            channelIconView.leadingAnchor.constraint(equalTo: channelRow.leadingAnchor, constant: 12.sw),
            channelIconView.centerYAnchor.constraint(equalTo: channelRow.centerYAnchor),
            channelIconView.widthAnchor.constraint(equalToConstant: 18.swh),
            channelIconView.heightAnchor.constraint(equalToConstant: 18.swh),

            channelLabel.leadingAnchor.constraint(equalTo: channelIconView.trailingAnchor, constant: 8.sw),
            channelLabel.trailingAnchor.constraint(lessThanOrEqualTo: arrowIcon.leadingAnchor, constant: -8.sw),
            channelLabel.centerYAnchor.constraint(equalTo: channelRow.centerYAnchor),
            
            arrowIcon.trailingAnchor.constraint(equalTo: channelRow.trailingAnchor, constant: -12.sw),
            arrowIcon.centerYAnchor.constraint(equalTo: channelRow.centerYAnchor),
            arrowIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            arrowIcon.heightAnchor.constraint(equalToConstant: 14.swh)
        ])

        section.addArrangedSubview(channelRow)
        channelRow.heightAnchor.constraint(equalToConstant: 44.sh).isActive = true

        stackView.addArrangedSubview(section)
    }

    private func setupURLSection() {
        let section = createSection(title: L(L10n.Webhook.webhookURL))

        let urlRow = UIView()
        urlRow.backgroundColor = UIColor.theme.secondary
        urlRow.layer.cornerRadius = 10
        urlRow.translatesAutoresizingMaskIntoConstraints = false

        urlLabel.font = .systemFont(ofSize: 13.sf)
        urlLabel.textColor = UIColor.theme.textDisabled
        urlLabel.numberOfLines = 1
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        copyButton.setTitle(L(L10n.Webhook.copy), for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        copyButton.tintColor = UIColor.theme.bgViolet
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        urlRow.addSubview(urlLabel)
        urlRow.addSubview(copyButton)

        NSLayoutConstraint.activate([
            urlLabel.leadingAnchor.constraint(equalTo: urlRow.leadingAnchor, constant: 12.sw),
            urlLabel.centerYAnchor.constraint(equalTo: urlRow.centerYAnchor),
            urlLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8.sw),

            copyButton.trailingAnchor.constraint(equalTo: urlRow.trailingAnchor, constant: -12.sw),
            copyButton.centerYAnchor.constraint(equalTo: urlRow.centerYAnchor)
        ])

        section.addArrangedSubview(urlRow)
        urlRow.heightAnchor.constraint(equalToConstant: 44.sh).isActive = true

        stackView.addArrangedSubview(section)
    }

    private func setupActionButtonsSection() {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 10.sh).isActive = true
        stackView.addArrangedSubview(spacer)

        let actionsStack = UIStackView()
        actionsStack.axis = .vertical
        actionsStack.spacing = 16.sh
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        if isClanIntegration {
            resetTokenButton.setTitle(L(L10n.Webhook.resetToken), for: .normal)
            resetTokenButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
            resetTokenButton.setTitleColor(.white, for: .normal)
            resetTokenButton.backgroundColor = UIColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1)
            resetTokenButton.layer.cornerRadius = 12
            resetTokenButton.addTarget(self, action: #selector(resetTokenTapped), for: .touchUpInside)
            resetTokenButton.translatesAutoresizingMaskIntoConstraints = false
            actionsStack.addArrangedSubview(resetTokenButton)
            resetTokenButton.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        }

        deleteButton.setTitle(L(L10n.Webhook.delete), for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = .mezonError
        deleteButton.layer.cornerRadius = 12
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        actionsStack.addArrangedSubview(deleteButton)
        deleteButton.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true

        stackView.addArrangedSubview(actionsStack)
    }

    private func createSection(title: String) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        label.textColor = UIColor.theme.textStrong

        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.spacing = 8.sh
        return stack
    }

    private func populateData() {
        nameField.text = webhook.webhookName

        if let ch = context.account.postbox.resolvedChannelDescription(
            clanId: clanId, channelId: selectedChannelId
        ) {
            channelLabel.text = ch.channelLabel
            let iconName = ch.channelListIconAssetName()
            channelIconView.image = (UIImage(named: iconName) ?? UIImage.mezonSystemImage(iconName))?.withRenderingMode(.alwaysTemplate)
        } else {
            channelLabel.text = "#\(selectedChannelId)"
            channelIconView.image = UIImage.mezonSystemImage("number")?.withRenderingMode(.alwaysTemplate)
        }

        urlLabel.text = webhook.url.isEmpty ? "No URL" : webhook.url

        avatarView.configure(username: webhook.webhookName)
        loadAvatarImage(webhook.avatar)
        
        updateSaveButtonVisibility()
    }

    private func loadAvatarImage(_ urlString: String) {
        imageTask?.cancel()
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            avatarImageView.isHidden = true
            avatarView.showPlaceholder()
            return
        }
        if let cachedImage = WebhookAvatarCache.shared.object(forKey: urlString as NSString) {
            avatarImageView.image = cachedImage
            avatarImageView.isHidden = false
            avatarView.showImageMode()
            return
        }
        avatarView.showSkeleton()
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard error == nil, let data = data, let image = UIImage.decompressedImage(from: data) else { 
                DispatchQueue.main.async {
                    self?.avatarImageView.isHidden = true
                    self?.avatarView.showPlaceholder()
                }
                return 
            }
            WebhookAvatarCache.shared.setObject(image, forKey: urlString as NSString)
            DispatchQueue.main.async {
                self?.avatarImageView.image = image
                self?.avatarImageView.isHidden = false
                self?.avatarView.showImageMode()
            }
        }
        imageTask?.resume()
    }

    private var isResettingToken = false

    private func updateSaveButtonVisibility() {
        let nameChanged = webhookName != webhook.webhookName
        let avatarChanged = avatarURL != webhook.avatar || selectedImage != nil
        let channelChanged = !isClanIntegration && selectedChannelId != webhook.channelID
        let hasChanges = nameChanged || avatarChanged || channelChanged
        
        let trimmedName = webhookName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNameTooLong = trimmedName.count > 64
        nameErrorLabel.isHidden = !isNameTooLong
        
        let isValidName = !isNameTooLong && !trimmedName.isEmpty
        saveButton.isEnabled = hasChanges && isValidName && !isSaving
        saveButton.isHidden = !hasChanges
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func nameChanged() {
        webhookName = nameField.text ?? ""
        updateSaveButtonVisibility()
    }

    @objc private func channelTapped() {
        let vc = WebhookSelectChannelViewController(
            context: context,
            clanId: clanId,
            currentChannelId: selectedChannelId
        ) { [weak self] selectedChannel in
            self?.selectedChannelId = selectedChannel.channelID
            self?.channelLabel.text = selectedChannel.channelLabel
            let iconName = selectedChannel.channelListIconAssetName()
            self?.channelIconView.image = (UIImage(named: iconName) ?? UIImage.mezonSystemImage(iconName))?.withRenderingMode(.alwaysTemplate)
            self?.updateSaveButtonVisibility()
        }
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            vc.sheetPresentationController?.detents = [.medium(), .large()]
        }
        present(vc, animated: true)
    }

    @objc private func pickAvatarTapped() {
        if #available(iOS 13.0, *) {
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    @objc private func saveTapped() {
        handleSave()
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = webhook.url
        Toast.success(L(L10n.Webhook.copied))
    }

    @objc private func resetTokenTapped() {
        if #available(iOS 13.0, *) {
            guard !isResettingToken else { return }
            isResettingToken = true
            resetTokenButton.isEnabled = false
        
            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.isResettingToken = false
                    self.resetTokenButton.isEnabled = true
                }
                guard let token = await self.context.getToken() else {
                    Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                    return
                }
            
                do {
                    var req = Mezon_Api_UpdateClanWebhookRequest()
                    req.id = self.webhook.id
                    req.clanID = self.clanId
                    req.webhookName = self.webhook.webhookName
                    req.avatar = self.webhook.avatar
                    req.resetToken = true
                    _ = try await MezonHTTPClient.shared.updateClanWebhookById(request: req, token: token)
                
                    Toast.success(L(L10n.Webhook.resetSuccess))
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay for backend sync
                    self.onWebhookUpdated?()
                    self.fetchLatestWebhook()
                } catch {
                    Toast.error(L(L10n.Webhook.saveError))
                }
            }
        }
    }

    @objc private func deleteTapped() {
        if #available(iOS 13.0, *) {
            handleDelete()
        }
    }

    private func handleSave() {
        if #available(iOS 13.0, *) {
            guard !isSaving else { return }
            let trimmedName = webhookName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty && trimmedName.count <= 64 else { return }
        
            isSaving = true
            saveButton.isEnabled = false

            Task { [weak self] in
                guard let self else { return }
                defer { 
                    self.isSaving = false
                    self.updateSaveButtonVisibility()
                }
                guard let token = await self.context.getToken() else {
                    Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                    return
                }
            
                if let imgData = self.selectedImageData, let img = self.selectedImage {
                    do {
                        let uploadInfo = try await self.context.account.network.uploadAttachmentFile(
                            filename: "webhook_\(self.webhook.id)_\(Int(Date().timeIntervalSince1970)).jpg",
                            filetype: "image/jpeg",
                            size: imgData.count,
                            width: Int(img.size.width),
                            height: Int(img.size.height),
                            token: token
                        )
                        try await self.context.account.network.uploadToMinIO(
                            url: uploadInfo.url,
                            data: imgData,
                            contentType: "image/jpeg"
                        )
                        self.avatarURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                    } catch {
                        Toast.error(L(L10n.Webhook.saveError))
                        return
                    }
                }

                do {
                    if self.isClanIntegration {
                        var req = Mezon_Api_UpdateClanWebhookRequest()
                        req.id = self.webhook.id
                        req.clanID = self.clanId
                        req.webhookName = trimmedName
                        req.avatar = self.avatarURL
                        _ = try await MezonHTTPClient.shared.updateClanWebhookById(request: req, token: token)
                    } else {
                        var req = Mezon_Api_WebhookUpdateRequestById()
                        req.id = self.webhook.id
                        req.clanID = self.clanId
                        req.webhookName = trimmedName
                        req.avatar = self.avatarURL
                        req.channelID = self.webhook.channelID
                        req.channelIDUpdate = self.selectedChannelId
                        _ = try await MezonHTTPClient.shared.updateWebhookById(request: req, token: token)
                    }
                    Toast.success(L(L10n.Webhook.saveSuccess))
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay for backend sync
                    self.onWebhookUpdated?()
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    Toast.error(L(L10n.Webhook.saveError))
                }
            }
        }
    }

    @available(iOS 13.0, *)
    private func fetchLatestWebhook() {
        Task { [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                if self.isClanIntegration {
                    let clanWebhooks = try await MezonHTTPClient.shared.listClanWebhooks(clanId: self.clanId, token: token)
                    if let updated = clanWebhooks.first(where: { $0.id == self.webhook.id }) {
                        self.webhook = updated.toWebhook()
                    }
                } else {
                    let fetchChannelId = self.selectedChannelId
                    let webhooks = try await MezonHTTPClient.shared.listWebhooksByChannelId(channelId: fetchChannelId, clanId: self.clanId, token: token)
                    if let updated = webhooks.first(where: { $0.id == self.webhook.id }) {
                        self.webhook = updated
                    }
                }
                
                self.webhookName = self.webhook.webhookName
                self.avatarURL = self.webhook.avatar
                self.selectedChannelId = self.webhook.channelID
                self.selectedImage = nil
                self.selectedImageData = nil
                self.populateData()
            } catch {
                
            }
        }
    }

    @available(iOS 13.0, *)
    private func handleDelete() {
        let alert = UIAlertController(
            title: L(L10n.Webhook.deleteTitle),
            message: String(format: L(L10n.Webhook.deleteConfirm), webhook.webhookName),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.Common.delete), style: .destructive, handler: { [weak self] _ in
            self?.performDelete()
        }))
        present(alert, animated: true)
    }

    @available(iOS 13.0, *)
    private func performDelete() {
        guard !isSaving else { return }
        isSaving = true
        deleteButton.isEnabled = false
        saveButton.isEnabled = false

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSaving = false
                self.deleteButton.isEnabled = true
                self.updateSaveButtonVisibility()
            }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            var req = Mezon_Api_WebhookDeleteRequestById()
            req.id = self.webhook.id
            req.clanID = self.clanId
            req.channelID = self.webhook.channelID
            do {
                if self.isClanIntegration {
                    try await MezonHTTPClient.shared.deleteClanWebhookById(request: req, token: token)
                } else {
                    try await MezonHTTPClient.shared.deleteWebhookById(request: req, token: token)
                }
                Toast.success(L(L10n.Webhook.deleteSuccess))
                self.onWebhookUpdated?()
                self.navigationController?.popViewController(animated: true)
            } catch {
                Toast.error(L(L10n.Webhook.deleteError))
            }
        }
    }

    deinit {
        imageTask?.cancel()
    }
}

extension WebhookEditViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [weak self] in
            guard let self, let image else { return }
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            if data.count > 10 * 1024 * 1024 {
                Toast.error("File size exceeds 10MB limit")
                return
            }
            self.selectedImage = image
            self.selectedImageData = data
            self.avatarImageView.image = image
            self.avatarImageView.isHidden = false
            self.avatarView.showImageMode()
            self.updateSaveButtonVisibility()
        }
    }
}
