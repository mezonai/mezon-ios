import AsyncDisplayKit
import UIKit

final class ClanSettingsContainerNode: ASDisplayNode {

    var onClose: (() -> Void)?
    var onSelectOverview: (() -> Void)?
    var onSelectRoles: (() -> Void)?
    var onSelectAuditLog: (() -> Void)?
    var onSelectIntegrations: (() -> Void)?
    var onSelectStickers: (() -> Void)?
    var onSelectSoundStickers: (() -> Void)?
    var onSelectEmojis: (() -> Void)?
    var onSelectInvites: (() -> Void)?
    var onSelectMembers: (() -> Void)?
    var onChangeAvatar: (() -> Void)?
    var onRemoveAvatar: (() -> Void)?

    private let context: AccountContext
    private let clanId: Int64
    private var clanName: String
    private var avatarURL: String
    private var canShowRoles: Bool
    private var canShowIntegrations: Bool
    private var canShowOverview: Bool
    private var canShowAuditLog: Bool

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var validLayout: ContainerViewLayout?
    
    private let nameLabel = UILabel()
    private lazy var textAvatar: TextAvatarView = {
        let view = TextAvatarView(username: clanName, size: 56.swh, fontSize: 14.sf)
        view.layer.cornerRadius = 16.swh
        return view
    }()
    private let avatarContainer = UIView()
    private let avatarImageView = UIImageView()
    private let removeAvatarBtn = UIButton(type: .system)

    private let headerH: CGFloat = 64.sh
    private let padH: CGFloat = 12.sw

    init(context: AccountContext, clanId: Int64, clanName: String, avatarURL: String, canShowRoles: Bool, canShowIntegrations: Bool, canShowOverview: Bool, canShowAuditLog: Bool) {
        self.context = context
        self.clanId = clanId
        self.clanName = clanName
        self.avatarURL = avatarURL
        self.canShowRoles = canShowRoles
        self.canShowIntegrations = canShowIntegrations
        self.canShowOverview = canShowOverview
        self.canShowAuditLog = canShowAuditLog
        super.init()
        backgroundColor = UIColor.theme.primary
    }

    override func didLoad() {
        super.didLoad()
        setupUI()
    }

    private func setupUI() {
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 24.sh
        stackView.alignment = .fill
        scrollView.addSubview(stackView)

        buildContent()
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let size = layout.size
        let safeTop = layout.safeInsets.top

        scrollView.frame = CGRect(
            x: 0, y: safeTop, width: size.width, height: size.height - safeTop)

        let stackW = size.width
        let stackH = stackView.systemLayoutSizeFitting(
            CGSize(width: stackW, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        stackView.frame = CGRect(x: 0, y: 0, width: stackW, height: stackH)
        scrollView.contentSize = stackView.frame.size
    }

    private func buildContent() {

        let header = createHeader()
        stackView.addArrangedSubview(header)


        let identity = createIdentityView()
        stackView.addArrangedSubview(identity)


        let settingsHeader = createSectionHeader(title: L(L10n.Common.settings))
        stackView.addArrangedSubview(settingsHeader)
        stackView.setCustomSpacing(10.sh, after: settingsHeader)

        var settingsActions: [SettingAction] = []
        
        if canShowOverview {
            settingsActions.append(.init(title: L(L10n.ClanSetting.overview), icon: "ClanSetting/Overview", navigate: .overview))
        }
        
        if canShowAuditLog {
            settingsActions.append(.init(title: L(L10n.ClanSetting.auditLog), icon: "ClanSetting/ActivityLogIcon", navigate: .auditLog))
        }
        
        if canShowIntegrations {
            settingsActions.append(.init(title: L(L10n.ClanSetting.integrations), icon: "ClanSetting/GamingIcon", navigate: .integrations))
        }
        
        settingsActions.append(contentsOf: [
            .init(title: L(L10n.ClanSetting.emoji), icon: "ClanSetting/emoji", navigate: .emojis),
            .init(title: L(L10n.ClanSetting.sticker), icon: "ClanSetting/StickerIcon", navigate: .stickers),
            .init(title: L(L10n.ClanSetting.soundEffect), icon: "ClanSetting/SoundEffectIcon", navigate: .soundStickers),
            .init(title: L(L10n.ClanSetting.enableCommunity), icon: "ClanSetting/EnableCommunityIcon")
        ])
        
        let settingsGroup = createGroup(actions: settingsActions)
        stackView.addArrangedSubview(settingsGroup)


        let userMgmtHeader = createSectionHeader(title: L(L10n.ClanSetting.userManagement))
        stackView.addArrangedSubview(userMgmtHeader)
        stackView.setCustomSpacing(10.sh, after: userMgmtHeader)

        var userActions: [SettingAction] = [
            .init(title: L(L10n.Clan.members), icon: "ClanSetting/MemberIcon", navigate: .members),
        ]
        if canShowRoles {
            userActions.append(.init(title: L(L10n.ClanSetting.roles), icon: "ClanSetting/RolesIcon", navigate: .roles))
        }
        userActions.append(.init(title: L(L10n.ClanSetting.invites), icon: "ClanSetting/Invite", navigate: .invites))
        let userGroup = createGroup(actions: userActions)
        stackView.addArrangedSubview(userGroup)

        let footerSpacer = UIView()
        footerSpacer.heightAnchor.constraint(equalToConstant: 40.sh).isActive = true
        stackView.addArrangedSubview(footerSpacer)
    }

    func updateCanShowRoles(_ canShowRoles: Bool, canShowIntegrations: Bool, canShowOverview: Bool, canShowAuditLog: Bool) {
        guard self.canShowRoles != canShowRoles || self.canShowIntegrations != canShowIntegrations || self.canShowOverview != canShowOverview || self.canShowAuditLog != canShowAuditLog else { return }
        self.canShowRoles = canShowRoles
        self.canShowIntegrations = canShowIntegrations
        self.canShowOverview = canShowOverview
        self.canShowAuditLog = canShowAuditLog
        guard isNodeLoaded else { return }
        rebuildContent()
    }

    private func rebuildContent() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buildContent()
        if let validLayout {
            updateLayout(layout: validLayout, transition: .immediate)
        }
    }

    private func createHeader() -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: headerH).isActive = true

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(
            UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeBtn.tintColor = UIColor.theme.textStrong
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        v.addSubview(closeBtn)

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.Clan.settings)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        v.addSubview(titleLabel)

        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            closeBtn.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: padH),
            closeBtn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 44.sw),
            closeBtn.heightAnchor.constraint(equalToConstant: 44.sh),

            titleLabel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func createIdentityView() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false

        let avatarSize: CGFloat = 56.swh
        avatarContainer.backgroundColor = .clear
        avatarContainer.layer.shadowColor = UIColor.black.cgColor
        avatarContainer.layer.shadowOffset = CGSize(width: 0, height: 4.sh)
        avatarContainer.layer.shadowRadius = 8.swh
        avatarContainer.layer.shadowOpacity = 0.2
        avatarContainer.clipsToBounds = false
        v.addSubview(avatarContainer)

        avatarContainer.addSubview(textAvatar)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 16.swh
        textAvatar.addSubview(avatarImageView)

        if !avatarURL.isEmpty {
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: avatarURL, width: 150, height: 150)) {
                [weak avatarImageView, weak textAvatar] image in
                if let image = image {
                    avatarImageView?.image = image
                    textAvatar?.showImageMode()
                }
            }
        }

        nameLabel.text = clanName
        nameLabel.font = .systemFont(ofSize: 16.sf, weight: .medium)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.textAlignment = .center
        v.addSubview(nameLabel)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 10.sf, weight: .bold)
        removeAvatarBtn.setImage(UIImage(systemName: "xmark", withConfiguration: symbolConfig), for: .normal)
        removeAvatarBtn.tintColor = .white
        removeAvatarBtn.backgroundColor = .systemRed
        removeAvatarBtn.layer.cornerRadius = 12.swh
        removeAvatarBtn.clipsToBounds = true
        removeAvatarBtn.addTarget(self, action: #selector(removeAvatarTapped), for: .touchUpInside)
        removeAvatarBtn.isHidden = avatarURL.isEmpty || !canShowOverview
        v.addSubview(removeAvatarBtn)

        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        textAvatar.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        removeAvatarBtn.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            avatarContainer.topAnchor.constraint(equalTo: v.topAnchor, constant: 16.sh),
            avatarContainer.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            avatarContainer.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarContainer.heightAnchor.constraint(equalToConstant: avatarSize),

            textAvatar.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            textAvatar.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            textAvatar.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            textAvatar.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),

            avatarImageView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),

            nameLabel.topAnchor.constraint(equalTo: avatarContainer.bottomAnchor, constant: 16.sh),
            nameLabel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: v.leadingAnchor, constant: 16.sw),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -16.sw),
            nameLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8.sh),

            removeAvatarBtn.topAnchor.constraint(equalTo: avatarContainer.topAnchor, constant: -4.sh),
            removeAvatarBtn.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 4.sw),
            removeAvatarBtn.widthAnchor.constraint(equalToConstant: 24.swh),
            removeAvatarBtn.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        avatarContainer.isUserInteractionEnabled = true
        let tapAvatar = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarContainer.addGestureRecognizer(tapAvatar)

        return v
    }

    @objc private func avatarTapped() {
        onChangeAvatar?()
    }

    @objc private func removeAvatarTapped() {
        onRemoveAvatar?()
    }

    func updateClanDetails(name: String, avatarURL: String) {
        self.clanName = name
        self.avatarURL = avatarURL
        
        nameLabel.text = name
        
        if !avatarURL.isEmpty {
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: avatarURL, width: 150, height: 150)) {
                [weak self] image in
                if let image = image {
                    self?.avatarImageView.image = image
                    self?.textAvatar.showImageMode()
                }
            }
            removeAvatarBtn.isHidden = !canShowOverview
        } else {
            avatarImageView.image = nil
            textAvatar.configure(username: name, fontSize: 14.sf)
            removeAvatarBtn.isHidden = true
        }
    }

    private func createSectionHeader(title: String) -> UIView {
        let v = UIView()
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 14.sf, weight: .bold)
        l.textColor = UIColor.theme.textStrong
        v.addSubview(l)
        l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: padH),
            l.topAnchor.constraint(equalTo: v.topAnchor),
            l.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }

    private func createGroup(actions: [SettingAction]) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.theme.secondary
        container.layer.cornerRadius = 12.swh
        container.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        for (i, action) in actions.enumerated() {
            let row = createRow(action: action)
            stack.addArrangedSubview(row)
            if i < actions.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                stack.addArrangedSubview(sep)
            }
        }

        let wrapper = UIView()
        wrapper.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: wrapper.topAnchor),
            container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: padH),
            container.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -padH),
        ])
        return wrapper
    }

    private func createRow(action: SettingAction) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: 60.sh).isActive = true

        let iconAssetName = action.icon.split(separator: "/").last.map(String.init) ?? action.icon
        let needsOriginalRendering = action.icon == "ClanSetting/Overview"
            || action.icon == "ClanSetting/emoji"
            || action.icon == "ClanSetting/Invite"
            || action.icon == "ClanSetting/ActivityLogIcon"
            || action.icon == "ClanSetting/GamingIcon"
            || action.icon == "ClanSetting/StickerIcon"
            || action.icon == "ClanSetting/SoundEffectIcon"
            || action.icon == "ClanSetting/EnableCommunityIcon"
            || action.icon == "ClanSetting/MemberIcon"
            || action.icon == "ClanSetting/RolesIcon"
        let loadedImage = UIImage(named: action.icon) ?? UIImage(named: iconAssetName)
        let iconImage = needsOriginalRendering
            ? loadedImage?.withRenderingMode(.alwaysOriginal)
            : loadedImage?.withRenderingMode(.alwaysTemplate)
        let icon = UIImageView(image: iconImage)
        if !needsOriginalRendering {
            icon.tintColor = .mezonTextPrimary
        }
        icon.contentMode = .scaleAspectFit
        v.addSubview(icon)

        let title = UILabel()
        title.text = action.title
        title.font = .systemFont(ofSize: 14.sf, weight: .medium)
        title.textColor = .mezonTextPrimary
        v.addSubview(title)

        let chevron = UIImageView(
            image: UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        v.addSubview(chevron)

        icon.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24.swh),
            icon.heightAnchor.constraint(equalToConstant: 24.swh),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12.sw),
            title.centerYAnchor.constraint(equalTo: v.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16.sw),
            chevron.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12.swh),
            chevron.heightAnchor.constraint(equalToConstant: 12.swh),
        ])

        let btn = UIButton(type: .custom)
        v.addSubview(btn)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: v.topAnchor),
            btn.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        btn.tag = action.navigate?.rawValue ?? -1
        btn.addTarget(self, action: #selector(rowButtonTapped(_:)), for: .touchUpInside)

        return v
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func rowButtonTapped(_ sender: UIButton) {
        guard let nav = ClanSettingsNavigateAction(rawValue: sender.tag) else { return }
        switch nav {
        case .overview:
            onSelectOverview?()
        case .roles:
            onSelectRoles?()
        case .integrations:
            onSelectIntegrations?()
        case .stickers:
            onSelectStickers?()
        case .soundStickers:
            onSelectSoundStickers?()
        case .emojis:
            onSelectEmojis?()
        case .invites:
            onSelectInvites?()
        case .members:
            onSelectMembers?()
        case .auditLog:
            onSelectAuditLog?()
        }
    }


}

private enum ClanSettingsNavigateAction: Int {
    case overview = 0
    case roles = 1
    case integrations = 2
    case stickers = 3
    case emojis = 4
    case invites = 5
    case members = 6
    case auditLog = 7
    case soundStickers = 8
}

private struct SettingAction {
    let title: String
    let icon: String
    var navigate: ClanSettingsNavigateAction?

    init(title: String, icon: String, navigate: ClanSettingsNavigateAction? = nil) {
        self.title = title
        self.icon = icon
        self.navigate = navigate
    }
}
