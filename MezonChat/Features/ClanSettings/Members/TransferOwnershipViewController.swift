import UIKit

final class TransferOwnershipViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let targetMember: ClanMemberRecord

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let ackView = UIView()
    private let transferButton = UIButton(type: .system)
    
    private let padH: CGFloat = 16.sw
    private var isAcknowledged = false
    private var isSubmitting = false

    init(context: AccountContext, clanId: Int64, targetMember: ClanMemberRecord) {
        self.context = context
        self.clanId = clanId
        self.targetMember = targetMember
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupContent()
        updateTransferButton()
    }

    override func applyTheme() {
        super.applyTheme()
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        ackView.backgroundColor = boxBackgroundColor
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        titleLabel.text = L(L10n.ClanSetting.Members.transferTitle)
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

    private func setupContent() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 24.sh
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 40.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: padH),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -padH),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * padH)
        ])

        setupAvatars()
        setupWarningText()
        setupAcknowledgment()
        setupTransferButton()
    }

    private func setupAvatars() {
        let avatarStack = UIStackView()
        avatarStack.axis = .horizontal
        avatarStack.spacing = 20.sw
        avatarStack.alignment = .center
        avatarStack.translatesAutoresizingMaskIntoConstraints = false

        let myMember = context.currentUser
        let myAvatarUrl = myMember?.avatarURL?.absoluteString ?? ""
        let myUsername = myMember?.username ?? ""
        let myAvatar = createAvatarView(url: myAvatarUrl, username: myUsername)
        avatarStack.addArrangedSubview(myAvatar)

        let arrowView = UIImageView(image: UIImage.mezonSystemImage("arrow.right")?.withRenderingMode(.alwaysTemplate))
        arrowView.tintColor = UIColor.theme.textDisabled
        arrowView.contentMode = .scaleAspectFit
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        avatarStack.addArrangedSubview(arrowView)

        let targetContainer = UIView()
        targetContainer.translatesAutoresizingMaskIntoConstraints = false

        let targetAvatarUrl = targetMember.clanAvatar.isEmpty ? targetMember.userAvatarURL : targetMember.clanAvatar
        let targetAvatar = createAvatarView(url: targetAvatarUrl, username: targetMember.username)
        targetAvatar.translatesAutoresizingMaskIntoConstraints = false
        targetContainer.addSubview(targetAvatar)

        let crownView = UIImageView(image: UIImage.mezonSystemImage("crown.fill")?.withRenderingMode(.alwaysTemplate))
        crownView.tintColor = UIColor.systemYellow
        crownView.contentMode = .scaleAspectFit
        crownView.translatesAutoresizingMaskIntoConstraints = false
        targetContainer.addSubview(crownView)

        NSLayoutConstraint.activate([
            targetAvatar.topAnchor.constraint(equalTo: targetContainer.topAnchor),
            targetAvatar.bottomAnchor.constraint(equalTo: targetContainer.bottomAnchor),
            targetAvatar.leadingAnchor.constraint(equalTo: targetContainer.leadingAnchor),
            targetAvatar.trailingAnchor.constraint(equalTo: targetContainer.trailingAnchor),

            crownView.centerXAnchor.constraint(equalTo: targetContainer.centerXAnchor),
            crownView.bottomAnchor.constraint(equalTo: targetAvatar.topAnchor, constant: 14.sh),
            crownView.widthAnchor.constraint(equalToConstant: 36.swh),
            crownView.heightAnchor.constraint(equalToConstant: 36.swh)
        ])

        avatarStack.addArrangedSubview(targetContainer)

        NSLayoutConstraint.activate([
            arrowView.widthAnchor.constraint(equalToConstant: 24.swh),
            arrowView.heightAnchor.constraint(equalToConstant: 24.swh)
        ])

        contentStack.addArrangedSubview(avatarStack)
    }

    private func createAvatarView(url: String, username: String) -> UIView {
        let size: CGFloat = 80.swh
        let textAvatar = TextAvatarView(username: username, size: size, fontSize: 28.sf)
        textAvatar.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = size / 2
        imageView.translatesAutoresizingMaskIntoConstraints = false
        textAvatar.addSubview(imageView)

        if !url.isEmpty {
            imageView.isHidden = false
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: url, width: 200, height: 200)) { image in
                if let image {
                    imageView.image = image
                    textAvatar.showImageMode()
                }
            }
        } else {
            imageView.isHidden = true
            imageView.image = nil
            textAvatar.showPlaceholder()
        }

        NSLayoutConstraint.activate([
            textAvatar.widthAnchor.constraint(equalToConstant: size),
            textAvatar.heightAnchor.constraint(equalToConstant: size),
            imageView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),
        ])

        return textAvatar
    }

    private func setupWarningText() {
        let clanRecord = context.account.postbox.read({ tx in tx.getClan(id: clanId) })
        let clanName = clanRecord?.name ?? ""
        let targetName = targetMember.clanNick.isEmpty ? targetMember.displayName : targetMember.clanNick
        let nameToDisplay = targetName.isEmpty ? targetMember.username : targetName

        let clanNameLabel = UILabel()
        clanNameLabel.text = clanName
        clanNameLabel.font = .systemFont(ofSize: 24.sf, weight: .bold)
        clanNameLabel.textColor = UIColor.theme.textStrong
        clanNameLabel.textAlignment = .center
        contentStack.addArrangedSubview(clanNameLabel)

        let warningLabel = UILabel()
        warningLabel.text = L(L10n.ClanSetting.Members.transferWarning, clanName, nameToDisplay)
        warningLabel.font = .systemFont(ofSize: 15.sf, weight: .regular)
        warningLabel.textColor = UIColor.theme.textStrong
        warningLabel.textAlignment = .center
        warningLabel.numberOfLines = 0
        contentStack.addArrangedSubview(warningLabel)
        
        contentStack.setCustomSpacing(12.sh, after: clanNameLabel)
        contentStack.setCustomSpacing(40.sh, after: warningLabel)
    }

    private func setupAcknowledgment() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanSetting.Members.transferAcknowledgmentTitle)
        titleLabel.font = .systemFont(ofSize: 13.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textDisabled
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        ackView.backgroundColor = boxBackgroundColor
        ackView.layer.cornerRadius = 10.swh
        ackView.clipsToBounds = true
        ackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(ackView)

        let checkBox = UIView()
        checkBox.layer.cornerRadius = 4.swh
        checkBox.layer.borderWidth = 1.5
        checkBox.layer.borderColor = UIColor.theme.textDisabled.cgColor
        checkBox.translatesAutoresizingMaskIntoConstraints = false
        ackView.addSubview(checkBox)

        let checkmark = UIImageView(image: UIImage.mezonSystemImage("checkmark")?.withRenderingMode(.alwaysTemplate))
        checkmark.tintColor = .white
        checkmark.contentMode = .scaleAspectFit
        checkmark.isHidden = true
        checkmark.tag = 100
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkBox.addSubview(checkmark)

        let targetName = targetMember.clanNick.isEmpty ? targetMember.displayName : targetMember.clanNick
        let nameToDisplay = targetName.isEmpty ? targetMember.username : targetName

        let ackLabel = UILabel()
        ackLabel.text = L(L10n.ClanSetting.Members.transferAcknowledgment, nameToDisplay)
        ackLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
        ackLabel.textColor = UIColor.theme.textStrong
        ackLabel.numberOfLines = 0
        ackLabel.translatesAutoresizingMaskIntoConstraints = false
        ackView.addSubview(ackLabel)

        let btn = UIButton(type: .custom)
        btn.addTarget(self, action: #selector(toggleAcknowledgment), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        ackView.addSubview(btn)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            ackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            ackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            checkBox.leadingAnchor.constraint(equalTo: ackView.leadingAnchor, constant: 14.sw),
            checkBox.centerYAnchor.constraint(equalTo: ackView.centerYAnchor),
            checkBox.widthAnchor.constraint(equalToConstant: 20.swh),
            checkBox.heightAnchor.constraint(equalToConstant: 20.swh),

            checkmark.centerXAnchor.constraint(equalTo: checkBox.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: checkBox.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 12.swh),
            checkmark.heightAnchor.constraint(equalToConstant: 12.swh),

            ackLabel.leadingAnchor.constraint(equalTo: checkBox.trailingAnchor, constant: 12.sw),
            ackLabel.trailingAnchor.constraint(equalTo: ackView.trailingAnchor, constant: -14.sw),
            ackLabel.topAnchor.constraint(equalTo: ackView.topAnchor, constant: 14.sh),
            ackLabel.bottomAnchor.constraint(equalTo: ackView.bottomAnchor, constant: -14.sh),

            btn.topAnchor.constraint(equalTo: ackView.topAnchor),
            btn.bottomAnchor.constraint(equalTo: ackView.bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: ackView.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: ackView.trailingAnchor),
        ])

        contentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func setupTransferButton() {
        transferButton.setTitle(L(L10n.ClanSetting.Members.transferButton), for: .normal)
        transferButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .bold)
        transferButton.layer.cornerRadius = 10.swh
        transferButton.clipsToBounds = true
        transferButton.addTarget(self, action: #selector(transferTapped), for: .touchUpInside)
        transferButton.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(transferButton)

        NSLayoutConstraint.activate([
            transferButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            transferButton.heightAnchor.constraint(equalToConstant: 46.sh)
        ])
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func toggleAcknowledgment() {
        guard !isSubmitting else { return }
        isAcknowledged.toggle()

        if let checkBox = view.viewWithTag(100)?.superview {
            checkBox.backgroundColor = isAcknowledged
                ? UIColor.systemBlue
                : .clear
            checkBox.layer.borderColor = isAcknowledged
                ? UIColor.systemBlue.cgColor
                : UIColor.theme.textDisabled.cgColor
        }
        view.viewWithTag(100)?.isHidden = !isAcknowledged

        updateTransferButton()
    }

    private func updateTransferButton() {
        transferButton.isEnabled = isAcknowledged && !isSubmitting
        transferButton.backgroundColor = transferButton.isEnabled ? .systemBlue : boxBackgroundColor
        transferButton.setTitleColor(transferButton.isEnabled ? .white : UIColor.theme.textDisabled, for: .normal)
    }

    @objc private func transferTapped() {
        if #available(iOS 13.0, *) {
            guard isAcknowledged, !isSubmitting else { return }
            isSubmitting = true
            updateTransferButton()

            Task { [weak self] in
                guard let self else { return }
                do {
                    guard let token = await self.context.getToken() else {
                        throw RolesRepositoryError.notAuthenticated
                    }
                    try await self.context.engine.account.network.transferClanOwnership(
                        clanId: self.clanId,
                        newOwnerId: self.targetMember.userId,
                        token: token
                    )
                    self.context.account.postbox.writeSync { tx in
                        if let clan = tx.getClan(id: self.clanId) {
                            let updatedClan = ClanRecord(
                                id: clan.id,
                                name: clan.name,
                                icon: clan.icon,
                                ownerId: String(self.targetMember.userId),
                                data: clan.data
                            )
                            tx.updateClans([updatedClan])
                        }
                    }
                    await MainActor.run {
                        Toast.success(L(L10n.ClanSetting.Members.transferSuccess))
                        if let nav = self.navigationController {
                            if let index = nav.viewControllers.firstIndex(where: { $0 is ClanSettingsViewController }), index > 0 {
                                nav.popToViewController(nav.viewControllers[index - 1], animated: true)
                            } else {
                                nav.popToRootViewController(animated: true)
                            }
                        } else {
                            self.dismiss(animated: true)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.isSubmitting = false
                        self.updateTransferButton()
                        Toast.error(L(L10n.ClanSetting.Members.transferFailed))
                    }
                }
            }
        }
    }
}
