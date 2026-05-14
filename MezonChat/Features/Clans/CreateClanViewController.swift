import UIKit

private let kCreateClanMaxImageBytes = 10 * 1024 * 1024

final class CreateClanViewController: BaseViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextViewDelegate, UITextFieldDelegate {

    private let context: AccountContext
    private let creationTemplate: ClanCreationTemplate?

    private var logoURL: String = ""
    private var uploadCount = 0
    private var isSubmitting = false

    private let logoDashedLayer = CAShapeLayer()

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.alwaysBounceVertical = true
        s.keyboardDismissMode = .interactive
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 16.sh
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let logoWrap = UIView()
    private let logoRingContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor.theme.secondary
        iv.isUserInteractionEnabled = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let logoCenterStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .center
        s.spacing = 4.sh
        s.isUserInteractionEnabled = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let logoCamIcon = UIImageView()
    private let logoUploadWord = UILabel()

    private let logoAddBadge: UIButton = {
        let b = UIButton(type: .system)
        b.backgroundColor = UIColor(red: 0.35, green: 0.55, blue: 1, alpha: 1)
        b.layer.cornerRadius = 14.swh
        b.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let logoSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let nameFieldContainer = UIView()
    private let nameField: UITextField = {
        let t = UITextField()
        t.borderStyle = .none
        t.font = .systemFont(ofSize: 15.sf)
        t.returnKeyType = .done
        t.autocorrectionType = .no
        t.clearButtonMode = .whileEditing
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }()

    private let nameErrorLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.numberOfLines = 0
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let guidelinesTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let createButton = UIButton(type: .system)
    private let createSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var guidelinesURL: URL {
        URL(string: "\(MezonConfig.chatWebAppBaseURL)/community-guidelines")
            ?? URL(string: "https://mezon.ai")!
    }

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let headerTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        l.textAlignment = .center
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let headerTrailingBalance = UIView()

    init(context: AccountContext, creationTemplate: ClanCreationTemplate?) {
        self.context = context
        self.creationTemplate = creationTemplate
        super.init(navigationBarPresentationData: nil)
        hidesBottomBarWhenPushed = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(headerTrailingBalance)
        headerView.addSubview(headerTitleLabel)
        headerTrailingBalance.translatesAutoresizingMaskIntoConstraints = false
        headerTrailingBalance.isUserInteractionEnabled = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        subtitleLabel.text = L(L10n.Clan.customizeClanSubtitle)

        logoWrap.translatesAutoresizingMaskIntoConstraints = false
        logoWrap.addSubview(logoRingContainer)
        logoRingContainer.addSubview(logoImageView)
        logoRingContainer.addSubview(logoCenterStack)
        logoWrap.addSubview(logoAddBadge)
        logoWrap.addSubview(logoSpinner)

        let camCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        logoCamIcon.image = UIImage(systemName: "camera.fill", withConfiguration: camCfg)
        logoUploadWord.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        logoUploadWord.text = L(L10n.Clan.uploadWordmark)
        logoCenterStack.addArrangedSubview(logoCamIcon)
        logoCenterStack.addArrangedSubview(logoUploadWord)

        logoAddBadge.addTarget(self, action: #selector(logoTapped), for: .touchUpInside)

        let logoTap = UITapGestureRecognizer(target: self, action: #selector(logoTapped))
        logoImageView.addGestureRecognizer(logoTap)

        nameLabel.text = L(L10n.Clan.createClanNameSection)
        nameField.placeholder = L(L10n.Clan.newClanNamePlaceholder)
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)

        nameFieldContainer.layer.cornerRadius = 12.swh
        nameFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        nameFieldContainer.addSubview(nameField)

        nameErrorLabel.text = L(L10n.Clan.invalidName)
        nameErrorLabel.textColor = .systemRed

        guidelinesTextView.delegate = self

        createButton.layer.cornerRadius = 12.swh
        createButton.clipsToBounds = true
        createButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        createButton.setTitle(L(L10n.Clan.createClan), for: .normal)
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let ringSize: CGFloat = 120.swh
        logoRingContainer.layer.addSublayer(logoDashedLayer)
        logoDashedLayer.fillColor = UIColor.clear.cgColor
        logoDashedLayer.lineWidth = 2

        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(logoWrap)
        contentStack.setCustomSpacing(24.sh, after: logoWrap)
        contentStack.addArrangedSubview(nameLabel)
        contentStack.addArrangedSubview(nameFieldContainer)
        contentStack.addArrangedSubview(nameErrorLabel)
        contentStack.setCustomSpacing(20.sh, after: nameErrorLabel)
        contentStack.addArrangedSubview(guidelinesTextView)
        contentStack.setCustomSpacing(24.sh, after: guidelinesTextView)
        contentStack.addArrangedSubview(createButton)
        createButton.addSubview(createSpinner)

        let headerHeight: CGFloat = 96

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8.sh),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            headerTrailingBalance.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            headerTrailingBalance.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            headerTrailingBalance.widthAnchor.constraint(equalTo: backButton.widthAnchor),
            headerTrailingBalance.heightAnchor.constraint(equalTo: backButton.heightAnchor),

            headerTitleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            headerTitleLabel.trailingAnchor.constraint(equalTo: headerTrailingBalance.leadingAnchor, constant: -8),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            logoWrap.heightAnchor.constraint(equalToConstant: ringSize + 8.sh),

            logoRingContainer.centerXAnchor.constraint(equalTo: logoWrap.centerXAnchor),
            logoRingContainer.centerYAnchor.constraint(equalTo: logoWrap.centerYAnchor),
            logoRingContainer.widthAnchor.constraint(equalToConstant: ringSize),
            logoRingContainer.heightAnchor.constraint(equalToConstant: ringSize),

            logoImageView.topAnchor.constraint(equalTo: logoRingContainer.topAnchor, constant: 3),
            logoImageView.leadingAnchor.constraint(equalTo: logoRingContainer.leadingAnchor, constant: 3),
            logoImageView.trailingAnchor.constraint(equalTo: logoRingContainer.trailingAnchor, constant: -3),
            logoImageView.bottomAnchor.constraint(equalTo: logoRingContainer.bottomAnchor, constant: -3),

            logoCenterStack.centerXAnchor.constraint(equalTo: logoRingContainer.centerXAnchor),
            logoCenterStack.centerYAnchor.constraint(equalTo: logoRingContainer.centerYAnchor),

            logoAddBadge.widthAnchor.constraint(equalToConstant: 28.swh),
            logoAddBadge.heightAnchor.constraint(equalToConstant: 28.swh),
            logoAddBadge.trailingAnchor.constraint(equalTo: logoRingContainer.trailingAnchor, constant: 4.swh),
            logoAddBadge.topAnchor.constraint(equalTo: logoRingContainer.topAnchor, constant: -4.swh),

            logoSpinner.centerXAnchor.constraint(equalTo: logoRingContainer.centerXAnchor),
            logoSpinner.centerYAnchor.constraint(equalTo: logoRingContainer.centerYAnchor),

            nameFieldContainer.heightAnchor.constraint(equalToConstant: 48),

            nameField.leadingAnchor.constraint(equalTo: nameFieldContainer.leadingAnchor, constant: 12),
            nameField.trailingAnchor.constraint(equalTo: nameFieldContainer.trailingAnchor, constant: -12),
            nameField.centerYAnchor.constraint(equalTo: nameFieldContainer.centerYAnchor),

            createButton.heightAnchor.constraint(equalToConstant: 50),

            createSpinner.centerXAnchor.constraint(equalTo: createButton.centerXAnchor),
            createSpinner.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
        ])

        refreshLogoOverlay()
        buildGuidelines()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let r = logoRingContainer.bounds
        guard r.width > 0 else { return }
        let circle = UIBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
        logoDashedLayer.path = circle.cgPath
        logoDashedLayer.frame = r
        let t = UIColor.theme
        logoDashedLayer.strokeColor = t.textStrong.withAlphaComponent(0.45).cgColor
        logoImageView.layer.cornerRadius = (r.width - 6) / 2
    }

    override func applyTheme() {
        view.backgroundColor = .mezonPrimary
        headerView.backgroundColor = .mezonPrimary
        headerTitleLabel.text = L(L10n.Clan.customizeClanTitle)
        headerTitleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        subtitleLabel.textColor = .mezonTextMuted
        nameLabel.textColor = .mezonTextStrong
        nameField.textColor = .mezonTextStrong
        nameField.tintColor = .mezonTextStrong
        nameFieldContainer.backgroundColor = .mezonSecondary
        logoImageView.backgroundColor = UIColor.theme.secondary
        logoCamIcon.tintColor = .mezonTextMuted
        logoUploadWord.textColor = .mezonTextMuted
        let ph = L(L10n.Clan.newClanNamePlaceholder)
        nameField.attributedPlaceholder = NSAttributedString(
            string: ph,
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        createButton.backgroundColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        createButton.setTitleColor(.white, for: .normal)
        createButton.setTitleColor(.white.withAlphaComponent(0.5), for: .disabled)
        logoSpinner.color = .mezonTextStrong
        createSpinner.color = .white
        buildGuidelines()
    }

    private func buildGuidelines() {
        let prefix = L(L10n.Clan.createClanAgreementPrefix)
        let linkText = L(L10n.Clan.createClanAgreementLink)
        let full = prefix + linkText
        let m = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: UIColor.mezonTextMuted,
            ])
        if let range = full.range(of: linkText) {
            let ns = NSRange(range, in: full)
            m.addAttributes([.foregroundColor: UIColor.mezonLink, .link: guidelinesURL], range: ns)
        }
        guidelinesTextView.attributedText = m
        guidelinesTextView.linkTextAttributes = [.foregroundColor: UIColor.mezonLink]
    }

    @objc private func nameChanged() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            nameErrorLabel.isHidden = true
        } else if !ClanCreationNameRules.isValid(name) {
            nameErrorLabel.text = L(L10n.Clan.invalidName)
            nameErrorLabel.isHidden = false
        } else {
            nameErrorLabel.isHidden = true
        }
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func logoTapped() {
        guard uploadCount == 0, !isSubmitting else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func createTapped() {
        guard !isSubmitting, uploadCount == 0 else { return }
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            Toast.error(L(L10n.Clan.nameRequired))
            return
        }
        guard ClanCreationNameRules.isValid(name) else {
            nameErrorLabel.isHidden = false
            return
        }
        nameErrorLabel.isHidden = true
        Task { @MainActor in
            guard let token = await context.getToken(), !token.isEmpty else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            isSubmitting = true
            createButton.isEnabled = false
            nameField.isEnabled = false
            createSpinner.startAnimating()
            createButton.setTitle("", for: .normal)
            do {
                let desc = try await context.engine.clanData.createClanDesc(
                    name: name,
                    logo: logoURL,
                    banner: "",
                    token: token
                )
                let newId = desc.clanID
                if let t = creationTemplate {
                    await context.engine.clanData.applyCreationTemplateChannels(clanId: newId, template: t, token: token)
                }
                popCreateFlowAndNotify(clanId: newId)
            } catch let error as MezonError {
                if case .httpError(let code, let msg) = error {
                    var toastMsg = msg
                    if let data = msg.data(using: .utf8),
                       let apiErr = try? JSONDecoder().decode(APIError.self, from: data),
                       let inner = apiErr.message, !inner.isEmpty {
                        toastMsg = inner
                    }
                    if toastMsg.hasPrefix("HTTP ") {
                        if let colonIdx = toastMsg.firstIndex(of: ":") {
                            toastMsg = String(toastMsg[toastMsg.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        } else {
                            toastMsg = ""
                        }
                    }
                    
                    if code == 6 || code == 13 || toastMsg.lowercased().contains("exist") {
                        toastMsg = L(L10n.Clan.duplicateName)
                    } else if toastMsg.lowercased().contains("valid") {
                        toastMsg = L(L10n.Clan.invalidName)
                    } 
                    
                    Toast.error(toastMsg)
                } else {
                    Toast.error(error.localizedDescription)
                }
                createButton.isEnabled = true
                nameField.isEnabled = true
                createSpinner.stopAnimating()
                createButton.setTitle(L(L10n.Clan.createClan), for: .normal)
                isSubmitting = false
            } catch {
                Toast.error(error.localizedDescription)
                createButton.isEnabled = true
                nameField.isEnabled = true
                createSpinner.stopAnimating()
                createButton.setTitle(L(L10n.Clan.createClan), for: .normal)
                isSubmitting = false
            }
        }
    }

    private func popCreateFlowAndNotify(clanId: Int64) {
        guard let nav = navigationController else { return }
        if let home = nav.viewControllers.first(where: { $0 is HomeViewController }) {
            nav.popToViewController(home, animated: true)
        } else {
            nav.popToRootViewController(animated: true)
        }
        NotificationCenter.default.post(
            name: .mezonQRSelectClan,
            object: nil,
            userInfo: ["clanId": "\(clanId)"]
        )
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in range: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(url)
        return false
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let raw = info[.originalImage] as? UIImage else { return }
        let image = Self.resizedImage(raw, maxSide: 512)
        guard let data = Self.jpegDataUnderLimit(image, maxBytes: kCreateClanMaxImageBytes) else {
            Toast.error(L(L10n.ProfileSetting.updateError))
            return
        }
        uploadCount += 1
        logoSpinner.startAnimating()
        logoCenterStack.isHidden = true
        Task { @MainActor in
            defer {
                uploadCount = max(0, uploadCount - 1)
                logoSpinner.stopAnimating()
            }
            guard let token = await context.getToken() else { return }
            do {
                let filename = "clan_create_logo_\(Int(Date().timeIntervalSince1970)).jpg"
                let uploadInfo = try await context.account.network.uploadAttachmentFile(
                    filename: filename, filetype: "image/jpeg", size: data.count,
                    width: Int(image.size.width), height: Int(image.size.height), token: token
                )
                try await context.account.network.uploadToMinIO(
                    url: uploadInfo.url, data: data, contentType: "image/jpeg"
                )
                let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                ImageCache.shared.setImage(image, data: data, forKey: cdnURL)
                logoURL = cdnURL
                logoImageView.image = image
                refreshLogoOverlay()
            } catch {
                Toast.error(error.localizedDescription)
                logoCenterStack.isHidden = false
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func refreshLogoOverlay() {
        let has = logoImageView.image != nil || !logoURL.isEmpty
        logoCenterStack.isHidden = has
    }

    private static func resizedImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let w = size.width
        let h = size.height
        let maxDim = max(w, h)
        guard maxDim > maxSide, maxDim > 0 else { return image }
        let scale = maxSide / maxDim
        let newSize = CGSize(width: w * scale, height: h * scale)
        let r = UIGraphicsImageRenderer(size: newSize)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private static func jpegDataUnderLimit(_ image: UIImage, maxBytes: Int) -> Data? {
        var q: CGFloat = 0.92
        while q >= 0.2 {
            if let d = image.jpegData(compressionQuality: q), d.count <= maxBytes { return d }
            q -= 0.12
        }
        return image.jpegData(compressionQuality: 0.18)
    }
}

extension CreateClanViewController {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = textField.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: r, with: string)
        return next.count <= ClanCreationNameRules.maxLength
    }
}
