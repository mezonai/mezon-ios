import UIKit
import AsyncDisplayKit

@MainActor
final class ProfileContainerNode: ASDisplayNode {

    private let fixedHeaderView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let context: AccountContext

    private var lastLayout: ContainerViewLayout?

    var onBackTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?
    var onTransferFundsTapped: (() -> Void)?
    var onEditProfileTapped: (() -> Void)?
    var onAvatarTapped: (() -> Void)?
    var onDisplayNameTapped: (() -> Void)?
    var onAddStatusTapped: (() -> Void)?
    var onYourFriendsTapped: (() -> Void)?
    var onHistoryTransactionTapped: (() -> Void)?

    private let avatarSize: CGFloat = 90.swh
    private let sideInset: CGFloat = 16.sw
    private let cardSpacing: CGFloat = 12.sh

    private let headerBackgroundView: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonSecondaryBackground
        return v
    }()

    private let avatarContainerView: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        return v
    }()
    private let avatarPlaceholderLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.clipsToBounds = true
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.5
        return l
    }()
    private let avatarImageView = UIImageView()
    private let statusBadgeImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        return iv
    }()
    private let addStatusButton: UIButton = {
        let btn = UIButton(type: .system)
        return btn
    }()
    private let statusBubbleContainer = UIView()
    private let statusBubbleShapeLayer = CAShapeLayer()
    private let statusTextLabel = UILabel()
    private static let maxStatusLines = 2
    private static let statusFont = UIFont.systemFont(ofSize: 14.sf, weight: .medium)
    private var statusBubbleText: String = ""
    private var statusBubbleHasCustom: Bool = false

    private let nameTapArea = UIView()
    private let nameLabel = UILabel()
    private let chevronDown: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.down")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
        iv.tintColor = .mezonTextPrimary
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    private let usernameLabel = UILabel()

    private let headphoneButton: UIButton = {
        let btn = UIButton(type: .custom)
        let img = UIImage(named: "Profile/ShopIcon", in: Bundle.main, compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        btn.setImage(img, for: .normal)
        btn.imageView?.contentMode = .scaleAspectFit
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        btn.backgroundColor = .mezonPrimary
        return btn
    }()

    private let micButton: UIButton = {
        let btn = UIButton(type: .custom)
        let img = UIImage(named: "Profile/SettingIcon", in: Bundle.main, compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        btn.setImage(img, for: .normal)
        btn.imageView?.contentMode = .scaleAspectFit
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        btn.backgroundColor = .mezonPrimary
        return btn
    }()

    private let balanceCard = UIView()
    private let balanceRow = ProfileIconRow()
    private let transferRow = ProfileIconRow()
    private let historyRow = ProfileIconRow()
    private let editProfileButton: UIButton = {
        let btn = UIButton(type: .system)
        if #available(iOS 15.0, *) {
            var cfg = UIButton.Configuration.filled()
            cfg.cornerStyle = .capsule
            cfg.baseForegroundColor = .white
            cfg.baseBackgroundColor = .outgoingBubble
            cfg.imagePadding = 8
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
            btn.configuration = cfg
        } else {
            btn.backgroundColor = .outgoingBubble
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
            btn.layer.cornerRadius = 20
            btn.clipsToBounds = true
            btn.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        }
        return btn
    }()

    private let aboutMeCard = UIView()
    private let aboutMeTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .bold)
        l.textColor = .mezonTextStrong
        return l
    }()
    private let aboutMeContentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 0
        return l
    }()
    private let memberSinceTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .bold)
        l.textColor = .mezonTextStrong
        return l
    }()
    private let memberSinceDateLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.textColor = .mezonTextStrong
        return l
    }()

    private var aboutMeTitleTopConstraint: NSLayoutConstraint!
    private var aboutMeContentTopConstraint: NSLayoutConstraint!
    private var aboutMeTitleHeightConstraint: NSLayoutConstraint!
    private var aboutMeContentHeightConstraint: NSLayoutConstraint!

    private let friendsCard = UIView()
    private let friendsTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .bold)
        l.textColor = .mezonTextStrong
        return l
    }()
    private let friendsAvatarStack = UIStackView()
    private let friendsChevron: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
        iv.tintColor = .mezonTextSecondary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private var friendsUpdatedDisposable: Disposable?
    private var walletFetchTask: Task<Void, Never>?
    private var walletDetail: WalletDetail?
    private var currentAvatarLoadKey: String?

    private let copyCard = UIView()
    private let copyRow = ProfileIconRow()

    private static func profileImage(named: String) -> UIImage? {
        UIImage(named: "Profile/\(named)", in: Bundle.main, compatibleWith: nil)
    }

    private static func makePlusIconInCircle(containerColor: UIColor, iconColor: UIColor, size: CGFloat = 24) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            containerColor.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
            let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            if let plus = UIImage(systemName: "plus", withConfiguration: cfg)?
                .withTintColor(iconColor, renderingMode: .alwaysOriginal) {
                let iconSize = plus.size
                let iconRect = CGRect(
                    x: (size - iconSize.width) / 2,
                    y: (size - iconSize.height) / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
                plus.draw(in: iconRect)
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func profileAvatarInitials(username: String?) -> String {
        let u = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return u.first.map { String($0).uppercased() } ?? ""
    }

    private static func statusBadgeAssetName(for status: User.OnlineStatus) -> String {
        switch status {
        case .online: return "OnlineIcon"
        case .idle: return "IdleIcon"
        case .doNotDisturb: return "DisturbIcon"
        case .invisible, .offline: return "InvisibleIcon"
        }
    }

    private static func statusBadgeDotSize(for status: User.OnlineStatus) -> CGFloat {
        switch status {
        case .idle, .doNotDisturb:
            return 22.swh
        case .online, .invisible, .offline:
            return 16.swh
        }
    }

    private static func statusBadgePositionCompensation(for status: User.OnlineStatus) -> CGPoint {
        switch status {
        case .idle, .doNotDisturb:
            return CGPoint(x: 3, y: 3)
        case .online, .invisible, .offline:
            return .zero
        }
    }

    private static func statusBadgeContentScale(for status: User.OnlineStatus) -> CGFloat {
        switch status {
        case .idle, .doNotDisturb:
            return 1.22
        case .online, .invisible, .offline:
            return 1.0
        }
    }

    private func configureAddStatusButton(user: User?) {
        let custom = user?.customStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasCustom = !custom.isEmpty
        statusBubbleText = custom
        statusBubbleHasCustom = hasCustom

        statusTextLabel.textColor = .mezonTextPrimary
        statusTextLabel.text = hasCustom ? custom : nil
        statusTextLabel.isHidden = !hasCustom

        if #available(iOS 15.0, *) {
            var statusCfg = UIButton.Configuration.plain()
            statusCfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 6, bottom: 14, trailing: 6)
            if hasCustom {
                statusCfg.image = nil
                statusCfg.imagePadding = 0
                statusCfg.attributedTitle = nil
            } else {
                statusCfg.image = Self.makePlusIconInCircle(containerColor: .outgoingBubble, iconColor: .white)
                statusCfg.imagePadding = 6
                statusCfg.baseForegroundColor = .mezonTextPrimary
                statusCfg.attributedTitle = AttributedString(
                    L(L10n.Profile.addStatus),
                    attributes: AttributeContainer([
                        .font: Self.statusFont,
                        .foregroundColor: UIColor.mezonTextPrimary
                    ])
                )
            }
            addStatusButton.configuration = statusCfg
        } else {
            if hasCustom {
                addStatusButton.setImage(nil, for: .normal)
                addStatusButton.setTitle(nil, for: .normal)
            } else {
                addStatusButton.setImage(Self.makePlusIconInCircle(containerColor: .outgoingBubble, iconColor: .white), for: .normal)
                addStatusButton.setTitle(L(L10n.Profile.addStatus), for: .normal)
                addStatusButton.setTitleColor(.mezonTextPrimary, for: .normal)
                addStatusButton.titleLabel?.font = Self.statusFont
                addStatusButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 6, bottom: 14, right: 6)
                addStatusButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
            }
        }
    }

    private static func profileImageResized(named: String, size: CGFloat = 24, contentScale: CGFloat = 1.0) -> UIImage? {
        guard let img = profileImage(named: named) else { return nil }
        let target = CGSize(width: size, height: size)
        let ratio = min(target.width / img.size.width, target.height / img.size.height) * contentScale
        let drawSize = CGSize(width: img.size.width * ratio, height: img.size.height * ratio)
        let drawRect = CGRect(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            img.draw(in: drawRect)
        }
        return resized.withRenderingMode(img.renderingMode)
    }

    init(context: AccountContext) {
        self.context = context
        super.init()
    }

    deinit {
        friendsUpdatedDisposable?.dispose()
        walletFetchTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func didLoad() {
        super.didLoad()
        view.backgroundColor = .mezonSecondaryBackground

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(fixedHeaderView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        setupHeader()
        setupNameArea()
        setupBalanceCard()
        setupAboutMeCard()
        setupFriendsCard()
        setupCopyCard()

        updateContent()

        friendsUpdatedDisposable = (context.engine.friendsData.friendsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.applyFriendAvatarsFromFriendsData()
            })

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeOrLanguageChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeOrLanguageChange), name: LanguageManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurrentUserDidChange), name: .mezonAccountCurrentUserDidChange, object: nil)
    }

    @objc private func handleCurrentUserDidChange() {
        updateContent()
    }

    @objc private func handleThemeOrLanguageChange() {
        applyTheme()
        updateContent()
    }

    private func applyTheme() {
        view.backgroundColor = .mezonSecondaryBackground
        fixedHeaderView.backgroundColor = .mezonSecondaryBackground
        scrollView.backgroundColor = .mezonSecondaryBackground
        contentView.backgroundColor = .mezonSecondaryBackground

        avatarContainerView.layer.borderColor = UIColor.mezonSecondaryBackground.cgColor
        statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor

        nameLabel.textColor = .mezonTextStrong
        chevronDown.tintColor = .mezonTextPrimary
        usernameLabel.textColor = .mezonTextPrimary

        headphoneButton.backgroundColor = .mezonPrimary
        micButton.backgroundColor = .mezonPrimary

        for card in [balanceCard, aboutMeCard, friendsCard, copyCard] {
            card.backgroundColor = .mezonPrimary
            card.layer.borderColor = UIColor.mezonBorder.cgColor
        }

        aboutMeTitleLabel.textColor = .mezonTextStrong
        aboutMeContentLabel.textColor = .mezonTextStrong
        memberSinceTitleLabel.textColor = .mezonTextStrong
        memberSinceDateLabel.textColor = .mezonTextStrong
        friendsTitleLabel.textColor = .mezonTextStrong
        friendsChevron.tintColor = .mezonTextSecondary

        if avatarImageView.image == nil {
            headerBackgroundView.backgroundColor = .mezonSecondaryBackground
            avatarContainerView.backgroundColor = UIColor.theme.secondaryLight
            avatarPlaceholderLabel.isHidden = false
        } else {
            avatarPlaceholderLabel.isHidden = true
        }
        statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
        avatarPlaceholderLabel.textColor = .mezonTextStrong

        configureAddStatusButton(user: context.currentUser)
    }

    private func setupHeader() {
        fixedHeaderView.addSubview(headerBackgroundView)
        fixedHeaderView.sendSubviewToBack(headerBackgroundView)

        avatarContainerView.layer.cornerRadius = 16.swh
        avatarContainerView.layer.borderWidth = 3
        avatarContainerView.layer.borderColor = UIColor.mezonSecondaryBackground.cgColor
        fixedHeaderView.addSubview(avatarContainerView)

        avatarPlaceholderLabel.font = .systemFont(ofSize: avatarSize * 0.36, weight: .semibold)
        avatarPlaceholderLabel.textColor = .mezonTextStrong
        avatarContainerView.addSubview(avatarPlaceholderLabel)
        avatarImageView.backgroundColor = .clear
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarContainerView.addSubview(avatarImageView)

        statusBadgeImageView.layer.borderWidth = 0
        statusBadgeImageView.layer.borderColor = nil
        statusBadgeImageView.backgroundColor = .clear
        statusBadgeImageView.clipsToBounds = true
        fixedHeaderView.addSubview(statusBadgeImageView)

        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarContainerView.addGestureRecognizer(avatarTap)
        avatarContainerView.isUserInteractionEnabled = true

        statusBubbleContainer.backgroundColor = .clear
        statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
        statusBubbleContainer.layer.insertSublayer(statusBubbleShapeLayer, at: 0)

        if #available(iOS 15.0, *) {
            var statusCfg = UIButton.Configuration.plain()
            statusCfg.image = Self.makePlusIconInCircle(containerColor: .outgoingBubble, iconColor: .white)
            statusCfg.imagePadding = 6
            statusCfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 6, bottom: 14, trailing: 6)
            statusCfg.baseForegroundColor = .mezonTextPrimary
            statusCfg.attributedTitle = AttributedString(
                L(L10n.Profile.addStatus),
                attributes: AttributeContainer([
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .medium),
                    .foregroundColor: UIColor.mezonTextPrimary
                ])
            )
            addStatusButton.configuration = statusCfg
        } else {
            addStatusButton.setImage(Self.makePlusIconInCircle(containerColor: .outgoingBubble, iconColor: .white), for: .normal)
            addStatusButton.setTitle(L(L10n.Profile.addStatus), for: .normal)
            addStatusButton.setTitleColor(.mezonTextPrimary, for: .normal)
            addStatusButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
            addStatusButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 6, bottom: 14, right: 6)
            addStatusButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        }
        statusBubbleContainer.addSubview(addStatusButton)

        statusTextLabel.numberOfLines = Self.maxStatusLines
        statusTextLabel.lineBreakMode = .byTruncatingTail
        statusTextLabel.font = Self.statusFont
        statusTextLabel.textColor = .mezonTextPrimary
        statusTextLabel.isUserInteractionEnabled = false
        statusTextLabel.isHidden = true
        statusBubbleContainer.addSubview(statusTextLabel)

        fixedHeaderView.addSubview(statusBubbleContainer)

        addStatusButton.addTarget(self, action: #selector(addStatusButtonTapped), for: .touchUpInside)
    }

    private func setupNameArea() {
        nameTapArea.backgroundColor = .clear
        nameTapArea.isUserInteractionEnabled = true
        let nameTap = UITapGestureRecognizer(target: self, action: #selector(displayNameTapped))
        nameTapArea.addGestureRecognizer(nameTap)

        nameLabel.font = .systemFont(ofSize: 22.sf, weight: .bold)
        nameLabel.textColor = .mezonTextStrong
        nameTapArea.addSubview(nameLabel)
        nameTapArea.addSubview(chevronDown)
        fixedHeaderView.addSubview(nameTapArea)

        usernameLabel.font = .systemFont(ofSize: 14.sf)
        usernameLabel.textColor = .mezonTextPrimary
        fixedHeaderView.addSubview(usernameLabel)

        let iconBtnSize: CGFloat = 36.swh
        headphoneButton.layer.cornerRadius = iconBtnSize / 2
        headphoneButton.clipsToBounds = true
        headphoneButton.addTarget(self, action: #selector(shopTapped), for: .touchUpInside)
        fixedHeaderView.addSubview(headphoneButton)

        micButton.layer.cornerRadius = iconBtnSize / 2
        micButton.clipsToBounds = true
        micButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        fixedHeaderView.addSubview(micButton)

        editProfileButton.addTarget(self, action: #selector(editProfileTapped), for: .touchUpInside)
    }

    private func setupBalanceCard() {
        styleCard(balanceCard)
        contentView.addSubview(balanceCard)

        let cardInset: CGFloat = 16.sw
        for row in [balanceRow, transferRow, historyRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            balanceCard.addSubview(row)
        }
        editProfileButton.translatesAutoresizingMaskIntoConstraints = false
        balanceCard.addSubview(editProfileButton)

        balanceRow.translatesAutoresizingMaskIntoConstraints = false
        transferRow.translatesAutoresizingMaskIntoConstraints = false
        historyRow.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            balanceRow.topAnchor.constraint(equalTo: balanceCard.topAnchor, constant: 16.sh),
            balanceRow.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: cardInset),
            balanceRow.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -cardInset),
            balanceRow.heightAnchor.constraint(equalToConstant: 24.sh),

            transferRow.topAnchor.constraint(equalTo: balanceRow.bottomAnchor, constant: 16.sh),
            transferRow.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: cardInset),
            transferRow.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -cardInset),
            transferRow.heightAnchor.constraint(equalToConstant: 24.sh),

            historyRow.topAnchor.constraint(equalTo: transferRow.bottomAnchor, constant: 16.sh),
            historyRow.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: cardInset),
            historyRow.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -cardInset),
            historyRow.heightAnchor.constraint(equalToConstant: 24.sh),

            editProfileButton.topAnchor.constraint(equalTo: historyRow.bottomAnchor, constant: 16.sh),
            editProfileButton.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: cardInset),
            editProfileButton.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -cardInset),
            editProfileButton.heightAnchor.constraint(equalToConstant: 44.sh),
            editProfileButton.bottomAnchor.constraint(equalTo: balanceCard.bottomAnchor, constant: -16.sh),
        ])

        transferRow.isUserInteractionEnabled = true
        let transferTap = UITapGestureRecognizer(target: self, action: #selector(transferFundsTapped))
        transferRow.addGestureRecognizer(transferTap)
        historyRow.isUserInteractionEnabled = true
        let historyTap = UITapGestureRecognizer(target: self, action: #selector(historyTransactionTapped))
        historyRow.addGestureRecognizer(historyTap)
    }

    private func setupAboutMeCard() {
        styleCard(aboutMeCard)
        contentView.addSubview(aboutMeCard)

        let cardInset: CGFloat = 16.sw
        for v in [aboutMeTitleLabel, aboutMeContentLabel, memberSinceTitleLabel, memberSinceDateLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            aboutMeCard.addSubview(v)
        }

        aboutMeTitleTopConstraint = aboutMeTitleLabel.topAnchor.constraint(equalTo: aboutMeCard.topAnchor, constant: 16.sh)
        aboutMeContentTopConstraint = aboutMeContentLabel.topAnchor.constraint(equalTo: aboutMeTitleLabel.bottomAnchor, constant: 4.sh)
        aboutMeTitleHeightConstraint = aboutMeTitleLabel.heightAnchor.constraint(equalToConstant: 0)
        aboutMeContentHeightConstraint = aboutMeContentLabel.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            aboutMeTitleTopConstraint,
            aboutMeTitleLabel.leadingAnchor.constraint(equalTo: aboutMeCard.leadingAnchor, constant: cardInset),
            aboutMeTitleLabel.trailingAnchor.constraint(equalTo: aboutMeCard.trailingAnchor, constant: -cardInset),

            aboutMeContentTopConstraint,
            aboutMeContentLabel.leadingAnchor.constraint(equalTo: aboutMeCard.leadingAnchor, constant: cardInset),
            aboutMeContentLabel.trailingAnchor.constraint(equalTo: aboutMeCard.trailingAnchor, constant: -cardInset),

            memberSinceTitleLabel.topAnchor.constraint(equalTo: aboutMeContentLabel.bottomAnchor, constant: 16.sh),
            memberSinceTitleLabel.leadingAnchor.constraint(equalTo: aboutMeCard.leadingAnchor, constant: cardInset),
            memberSinceTitleLabel.trailingAnchor.constraint(equalTo: aboutMeCard.trailingAnchor, constant: -cardInset),

            memberSinceDateLabel.topAnchor.constraint(equalTo: memberSinceTitleLabel.bottomAnchor, constant: 4.sh),
            memberSinceDateLabel.leadingAnchor.constraint(equalTo: aboutMeCard.leadingAnchor, constant: cardInset),
            memberSinceDateLabel.trailingAnchor.constraint(equalTo: aboutMeCard.trailingAnchor, constant: -cardInset),
            memberSinceDateLabel.bottomAnchor.constraint(equalTo: aboutMeCard.bottomAnchor, constant: -16.sh),
        ])
    }

    private func setupFriendsCard() {
        styleCard(friendsCard)
        contentView.addSubview(friendsCard)

        let cardInset: CGFloat = 16.sw

        friendsTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        friendsCard.addSubview(friendsTitleLabel)

        friendsAvatarStack.axis = .horizontal
        friendsAvatarStack.spacing = -8.sw
        friendsAvatarStack.alignment = .center
        friendsAvatarStack.translatesAutoresizingMaskIntoConstraints = false
        friendsCard.addSubview(friendsAvatarStack)

        friendsChevron.translatesAutoresizingMaskIntoConstraints = false
        friendsCard.addSubview(friendsChevron)

        NSLayoutConstraint.activate([
            friendsTitleLabel.leadingAnchor.constraint(equalTo: friendsCard.leadingAnchor, constant: cardInset),
            friendsTitleLabel.centerYAnchor.constraint(equalTo: friendsCard.centerYAnchor),

            friendsAvatarStack.leadingAnchor.constraint(equalTo: friendsTitleLabel.trailingAnchor, constant: 12.sw),
            friendsAvatarStack.centerYAnchor.constraint(equalTo: friendsCard.centerYAnchor),

            friendsChevron.trailingAnchor.constraint(equalTo: friendsCard.trailingAnchor, constant: -cardInset),
            friendsChevron.centerYAnchor.constraint(equalTo: friendsCard.centerYAnchor),
            friendsChevron.widthAnchor.constraint(equalToConstant: 16.swh),
            friendsChevron.heightAnchor.constraint(equalToConstant: 16.swh),

            friendsCard.heightAnchor.constraint(equalToConstant: 56.sh),
        ])
        friendsCard.isUserInteractionEnabled = true
        let friendsTap = UITapGestureRecognizer(target: self, action: #selector(yourFriendsTapped))
        friendsCard.addGestureRecognizer(friendsTap)
    }

    private func setupCopyCard() {
        styleCard(copyCard)
        contentView.addSubview(copyCard)

        let cardInset: CGFloat = 16.sw
        copyRow.translatesAutoresizingMaskIntoConstraints = false
        copyCard.addSubview(copyRow)

        NSLayoutConstraint.activate([
            copyRow.topAnchor.constraint(equalTo: copyCard.topAnchor, constant: 14.sh),
            copyRow.leadingAnchor.constraint(equalTo: copyCard.leadingAnchor, constant: cardInset),
            copyRow.trailingAnchor.constraint(equalTo: copyCard.trailingAnchor, constant: -cardInset),
            copyRow.heightAnchor.constraint(equalToConstant: 24.sh),
            copyRow.bottomAnchor.constraint(equalTo: copyCard.bottomAnchor, constant: -14.sh),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(copyUserIdTapped))
        copyCard.addGestureRecognizer(tap)
    }

    private func applyProfileAvatarPlaceholder() {
        let u = context.currentUser
        avatarPlaceholderLabel.text = Self.profileAvatarInitials(username: u?.username)
        avatarImageView.image = nil
        avatarPlaceholderLabel.isHidden = false
        avatarContainerView.backgroundColor = UIColor.theme.secondaryLight
        headerBackgroundView.backgroundColor = .mezonSecondaryBackground
        statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
    }

    private func styleCard(_ card: UIView) {
        card.backgroundColor = .mezonPrimary
        card.layer.cornerRadius = 20.swh
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.mezonBorder.cgColor
        card.clipsToBounds = true
    }

    func updateContent() {
        let user = context.currentUser

        let initials = Self.profileAvatarInitials(username: user?.username)
        avatarPlaceholderLabel.text = initials

        if let url = user?.avatarURL, !url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let proxiedURLString = ImgproxyURL.create(from: url.absoluteString, width: 150, height: 150)
            let rawURLString = url.absoluteString
            currentAvatarLoadKey = proxiedURLString
            if let cached = ImageCache.shared.memoryImage(forKey: proxiedURLString) ?? ImageCache.shared.memoryImage(forKey: rawURLString) {
                avatarImageView.image = cached
                avatarPlaceholderLabel.isHidden = true
                avatarContainerView.backgroundColor = .clear
                headerBackgroundView.backgroundColor = cached.dominantColor() ?? .mezonSecondaryBackground
                statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
            } else {
                avatarImageView.image = nil
                avatarPlaceholderLabel.isHidden = false
                avatarContainerView.backgroundColor = UIColor.theme.secondaryLight
                headerBackgroundView.backgroundColor = .mezonSecondaryBackground
                statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
                ImageCache.shared.loadAvatar(urlString: proxiedURLString) { [weak self] image in
                    guard let self else { return }
                    guard self.currentAvatarLoadKey == proxiedURLString else { return }
                    if let image {
                        self.avatarImageView.image = image
                        self.avatarPlaceholderLabel.isHidden = true
                        self.avatarContainerView.backgroundColor = .clear
                        self.headerBackgroundView.backgroundColor = image.dominantColor() ?? .mezonSecondaryBackground
                        self.statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
                    } else if proxiedURLString != rawURLString {
                        ImageCache.shared.loadAvatar(urlString: rawURLString) { [weak self] rawImage in
                            guard let self else { return }
                            guard self.currentAvatarLoadKey == proxiedURLString else { return }
                            if let rawImage {
                                self.avatarImageView.image = rawImage
                                self.avatarPlaceholderLabel.isHidden = true
                                self.avatarContainerView.backgroundColor = .clear
                                self.headerBackgroundView.backgroundColor = rawImage.dominantColor() ?? .mezonSecondaryBackground
                                self.statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
                            } else {
                                self.applyProfileAvatarPlaceholder()
                            }
                        }
                    } else {
                        self.applyProfileAvatarPlaceholder()
                    }
                }
            }
        } else {
            currentAvatarLoadKey = nil
            applyProfileAvatarPlaceholder()
        }

        statusBadgeImageView.isHidden = false
        let st = user?.status ?? .offline
        let badgeSize = Self.statusBadgeDotSize(for: st)
        let badgeScale = Self.statusBadgeContentScale(for: st)
        statusBadgeImageView.layer.cornerRadius = badgeSize / 2
        statusBadgeImageView.image = Self.profileImageResized(
            named: Self.statusBadgeAssetName(for: st),
            size: badgeSize,
            contentScale: badgeScale
        )

        nameLabel.text = user?.displayName ?? "—"
        usernameLabel.text = user?.username.isEmpty == false ? user!.username : "—"

        configureAddStatusButton(user: user)
        fetchWalletDetail()
        transferRow.configure(
            icon: "arrow.up.circle.fill",
            iconImage: Self.profileImage(named: "TransferIcon"),
            iconColor: .mezonSuccess,
            text: L(L10n.Profile.transferFunds),
            textColor: .mezonTextStrong
        )
        historyRow.configure(
            icon: "clock.arrow.circlepath",
            iconImage: Self.profileImage(named: "HistoryIcon"),
            iconColor: .mezonTextSecondary,
            text: L(L10n.Profile.historyTransaction),
            textColor: .mezonTextStrong
        )

        let editIcon = Self.profileImageResized(named: "EditIcon", size: 20)?.withRenderingMode(.alwaysOriginal)
            ?? UIImage(systemName: "pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf, weight: .semibold))
        if #available(iOS 15.0, *) {
            editProfileButton.configuration?.image = editIcon
            editProfileButton.configuration?.title = L(L10n.Profile.editProfile)
            editProfileButton.configuration?.attributedTitle = AttributedString(
                L(L10n.Profile.editProfile),
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold)])
            )
        } else {
            editProfileButton.setImage(editIcon, for: .normal)
            editProfileButton.setTitle(L(L10n.Profile.editProfile), for: .normal)
        }

        let bio = user?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasAboutMe = !bio.isEmpty
        aboutMeTitleLabel.isHidden = !hasAboutMe
        aboutMeContentLabel.isHidden = !hasAboutMe
        aboutMeTitleTopConstraint.constant = hasAboutMe ? 16.sh : 0
        aboutMeContentTopConstraint.constant = hasAboutMe ? 4.sh : 0
        aboutMeTitleHeightConstraint.isActive = !hasAboutMe
        aboutMeContentHeightConstraint.isActive = !hasAboutMe

        aboutMeTitleLabel.text = L(L10n.Profile.aboutMe)
        aboutMeContentLabel.text = bio
        memberSinceTitleLabel.text = L(L10n.Profile.mezonMemberSince)
        memberSinceDateLabel.text = formatMemberSince()

        aboutMeCard.setNeedsLayout()
        aboutMeCard.layoutIfNeeded()

        friendsTitleLabel.text = L(L10n.Profile.yourFriends)

        applyFriendAvatarsFromFriendsData()

        copyRow.configure(
            text: L(L10n.Profile.copyUserId),
            textColor: .mezonTextStrong,
            font: .systemFont(ofSize: 13.sf, weight: .bold),
            trailingIconImage: Self.profileImage(named: "IDIcon")
        )

        if let layout = lastLayout {
            let safeTop = layout.safeInsets.top
            layoutContent(width: layout.size.width, height: layout.size.height, safeTop: safeTop)
        }
    }

    private func applyFriendAvatarsFromFriendsData() {
        let list = context.engine.friendsData.allFriends()
        let previews: [(avatarURL: String?, username: String)] = Array(
            list
                .filter { $0.state == EStateFriend.friend.rawValue && $0.hasUser }
                .prefix(5)
                .map { f -> (avatarURL: String?, username: String) in
                    let u = f.user
                    let url = u.avatarURL.isEmpty ? nil : u.avatarURL
                    return (avatarURL: url, username: u.username)
                }
        )
        setupFriendAvatars(previews: previews)
    }

    private func fetchWalletDetail() {
        walletFetchTask?.cancel()
        walletFetchTask = Task { @MainActor [weak self] in
            guard let self, let userId = context.currentUser?.id, !userId.isEmpty else {
                self?.walletDetail = nil
                self?.updateBalanceUI()
                return
            }
            do {
                let detail = try await MmnClient.shared.getAccountByUserId(userId)
                guard !Task.isCancelled else { return }
                self.walletDetail = detail
            } catch {
                guard !Task.isCancelled else { return }
                self.walletDetail = nil
            }
            self.updateBalanceUI()
        }
    }

    private func updateBalanceUI() {
        let hasWallet = !(walletDetail?.address.isEmpty ?? true)
        balanceCard.isHidden = !hasWallet

        let formattedBalance = BalanceFormatter.format(walletDetail?.balance)
        balanceRow.configure(
            icon: "checkmark.circle.fill",
            iconImage: Self.profileImage(named: "BalanceIcon"),
            iconColor: .mezonSuccess,
            text: "\(L(L10n.Profile.balance)): \(formattedBalance) \(L(L10n.Profile.currency))",
            textColor: .mezonTextStrong
        )

        if let superview = balanceCard.superview {
            superview.setNeedsLayout()
            superview.layoutIfNeeded()
        }
    }

    private func formatMemberSince() -> String {
        let raw = context.currentUser?.createTimeSeconds ?? 0
        guard raw > 0 else { return "—" }
        let ts: TimeInterval
        let digitCount = String(raw).count
        if digitCount <= 10 {
            ts = TimeInterval(raw)
        } else {
            ts = TimeInterval(raw) / 1000
        }
        let date = Date(timeIntervalSince1970: ts)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .current
        return formatter.string(from: date)
    }

    private func setupFriendAvatars(previews: [(avatarURL: String?, username: String)]) {
        friendsAvatarStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let avatarSmall: CGFloat = 28.swh
        for item in previews {
            let view = friendAvatarView(
                avatarURL: item.avatarURL,
                username: item.username,
                size: avatarSmall
            )
            friendsAvatarStack.addArrangedSubview(view)
        }
    }

    private func friendAvatarView(
        avatarURL: String?,
        username: String,
        size: CGFloat
    ) -> UIView {
        let container = TextAvatarView(username: username, size: size, fontSize: size * 0.38)
        container.layer.borderWidth = 2
        container.layer.borderColor = UIColor.mezonPrimary.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
        ])

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        if let urlStr = avatarURL, !urlStr.isEmpty {
            let px = Int(size * UIScreen.main.scale)
            let proxied = ImgproxyURL.create(from: urlStr, width: px, height: px)
            if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
                imageView.image = cached
                container.showImageMode()
            } else {
                imageView.isHidden = true
                container.showSkeleton()
                ImageCache.shared.loadImage(urlString: proxied) { [weak imageView, weak container] image in
                    if let image {
                        imageView?.image = image
                        imageView?.isHidden = false
                        container?.showImageMode()
                    } else {
                        imageView?.image = nil
                        imageView?.isHidden = true
                        container?.showPlaceholder()
                    }
                }
            }
        } else {
            imageView.isHidden = true
        }
        return container
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        lastLayout = layout
        let safeTop = layout.safeInsets.top
        layoutContent(width: layout.size.width, height: layout.size.height, safeTop: safeTop)
    }

    private func layoutContent(width: CGFloat, height: CGFloat, safeTop: CGFloat) {
        let side = sideInset
        let contentWidth = width - side * 2
        let headerExtraHeight: CGFloat = 16.sh
        var y: CGFloat = safeTop + 40.sh + headerExtraHeight

        let headerBackgroundHeight = y + avatarSize * 5 / 6
        headerBackgroundView.frame = CGRect(x: 0, y: 0, width: width, height: headerBackgroundHeight)

        avatarContainerView.frame = CGRect(x: side, y: y, width: avatarSize, height: avatarSize)
        avatarPlaceholderLabel.frame = avatarContainerView.bounds
        avatarImageView.frame = avatarContainerView.bounds

        let st = context.currentUser?.status ?? .offline
        let dotSize = Self.statusBadgeDotSize(for: st)
        let compensation = Self.statusBadgePositionCompensation(for: st)
        statusBadgeImageView.layer.cornerRadius = dotSize / 2
        statusBadgeImageView.frame = CGRect(
            x: avatarContainerView.frame.maxX - dotSize - 2 + compensation.x,
            y: avatarContainerView.frame.maxY - dotSize - 2 + compensation.y,
            width: dotSize,
            height: dotSize
        )

        let statusX = avatarContainerView.frame.maxX + 12.sw
        let tailH: CGFloat = 8.sh
        let maxBubbleW = width - statusX - side
        let statusHInset: CGFloat = 12
        let statusVInset: CGFloat = 28
        let bubbleBodyH: CGFloat
        let bubbleW: CGFloat
        if statusBubbleHasCustom {
            let statusFont = Self.statusFont
            let textMaxW = max(0, maxBubbleW - statusHInset)
            let bounding = (statusBubbleText as NSString).boundingRect(
                with: CGSize(width: textMaxW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: statusFont],
                context: nil
            )
            let maxTextH = ceil(statusFont.lineHeight * CGFloat(Self.maxStatusLines))
            let textH = min(ceil(bounding.height), maxTextH)
            bubbleW = min(ceil(bounding.width) + statusHInset, maxBubbleW)
            bubbleBodyH = max(44.sh, textH + statusVInset)
        } else {
            addStatusButton.sizeToFit()
            bubbleW = min(addStatusButton.intrinsicContentSize.width + 12, maxBubbleW)
            bubbleBodyH = 44.sh
        }
        let totalBubbleH = bubbleBodyH + tailH
        statusTextLabel.frame = CGRect(
            x: statusHInset / 2,
            y: 0,
            width: max(0, bubbleW - statusHInset),
            height: bubbleBodyH
        )

        statusBubbleContainer.frame = CGRect(
            x: statusX,
            y: y + (avatarSize - bubbleBodyH) / 2 - 6.sh,
            width: bubbleW,
            height: totalBubbleH
        )
        addStatusButton.frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleBodyH)

        statusBubbleShapeLayer.frame = statusBubbleContainer.bounds
        let bubblePath = makeBubblePath(
            width: bubbleW, bodyHeight: bubbleBodyH,
            cornerRadius: 14.swh,
            tailHeight: tailH, tailOffset: 2.sw, tailWidth: 10.sw
        )
        statusBubbleShapeLayer.path = bubblePath.cgPath

        y = avatarContainerView.frame.maxY + 8.sh

        nameLabel.sizeToFit()
        let chevronSize: CGFloat = 14.swh
        let nameW = min(nameLabel.intrinsicContentSize.width, width - side * 2 - 100.sw)
        let nameBlockW = nameW + 6.sw + chevronSize
        nameTapArea.frame = CGRect(x: side, y: y, width: nameBlockW, height: 28.sh)
        nameLabel.frame = CGRect(x: 0, y: 0, width: nameW, height: 28.sh)
        chevronDown.frame = CGRect(
            x: nameLabel.frame.maxX + 6.sw,
            y: (28.sh - chevronSize) / 2,
            width: chevronSize,
            height: chevronSize
        )

        let iconBtnSize: CGFloat = 36.swh
        let iconSpacing: CGFloat = 8.sw
        micButton.frame = CGRect(
            x: width - side - iconBtnSize,
            y: y + (28.sh - iconBtnSize) / 2,
            width: iconBtnSize,
            height: iconBtnSize
        )
        headphoneButton.frame = CGRect(
            x: micButton.frame.minX - iconSpacing - iconBtnSize,
            y: micButton.frame.minY,
            width: iconBtnSize,
            height: iconBtnSize
        )

        y += 28.sh + 2.sh

        usernameLabel.sizeToFit()
        usernameLabel.frame = CGRect(x: side, y: y, width: contentWidth, height: 20.sh)
        y += 20.sh + 20.sh

        let fixedHeaderHeight = y
        fixedHeaderView.frame = CGRect(x: 0, y: 0, width: width, height: fixedHeaderHeight)
        scrollView.frame = CGRect(x: 0, y: fixedHeaderHeight, width: width, height: height - fixedHeaderHeight)

        var scrollY: CGFloat = 0
        let cardWidth = contentWidth
        if !balanceCard.isHidden {
            balanceCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: 0)
            balanceCard.layoutIfNeeded()
            let balanceHeight = balanceCard.systemLayoutSizeFitting(
                CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            balanceCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: balanceHeight)
            scrollY += balanceHeight + cardSpacing
        }

        aboutMeCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: 0)
        aboutMeCard.layoutIfNeeded()
        let aboutHeight = aboutMeCard.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        aboutMeCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: aboutHeight)
        scrollY += aboutHeight + cardSpacing

        friendsCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: 56.sh)
        scrollY += 56.sh + cardSpacing

        copyCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: 0)
        copyCard.layoutIfNeeded()
        let copyHeight = copyCard.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        copyCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: copyHeight)
        scrollY += copyHeight + 30.sh

        contentView.frame = CGRect(x: 0, y: 0, width: width, height: scrollY)
        scrollView.contentSize = CGSize(width: width, height: scrollY)
    }

    private func makeBubblePath(
        width w: CGFloat, bodyHeight h: CGFloat,
        cornerRadius cr: CGFloat,
        tailHeight: CGFloat, tailOffset: CGFloat, tailWidth: CGFloat
    ) -> UIBezierPath {
        let r = min(cr, h / 2)
        let path = UIBezierPath()

        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(withCenter: CGPoint(x: w - r, y: r), radius: r,
                     startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(withCenter: CGPoint(x: w - r, y: h - r), radius: r,
                     startAngle: 0, endAngle: .pi / 2, clockwise: true)

        path.addLine(to: CGPoint(x: tailOffset + tailWidth, y: h))
        path.addLine(to: CGPoint(x: tailOffset, y: h + tailHeight))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(withCenter: CGPoint(x: r, y: r), radius: r,
                     startAngle: .pi, endAngle: -.pi / 2, clockwise: true)

        path.close()
        return path
    }

    @objc private func copyUserIdTapped() {
        guard let userId = context.currentUser?.id else { return }
        UIPasteboard.general.string = userId
        Toast.info(L(L10n.Profile.userIdCopied))
    }

    @objc private func editProfileTapped() {
        onEditProfileTapped?()
    }

    @objc private func settingsTapped() {
        onSettingsTapped?()
    }

    @objc private func avatarTapped() {
        onAvatarTapped?()
    }

    @objc private func displayNameTapped() {
        onDisplayNameTapped?()
    }

    @objc private func addStatusButtonTapped() {
        onAddStatusTapped?()
    }

    @objc private func transferFundsTapped() {
        onTransferFundsTapped?()
    }

    @objc private func shopTapped() {
        showComingSoonToastLine(title: "Shop")
    }

    @objc private func historyTransactionTapped() {
        onHistoryTransactionTapped?()
    }

    @objc private func yourFriendsTapped() {
        onYourFriendsTapped?()
    }

    private func showComingSoonToastLine(title: String) {
        let line = "\(title) — \(L(L10n.Common.comingSoon))"
        Toast.comingSoonLine(line)
    }
}

private final class ProfileIconRow: UIView {

    private let iconView = UIImageView()
    private let label = UILabel()
    private let trailingView = UIImageView()
    private var iconViewWidthConstraint: NSLayoutConstraint!
    private var labelLeadingConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        trailingView.contentMode = .scaleAspectFit
        trailingView.translatesAutoresizingMaskIntoConstraints = false
        trailingView.isHidden = true
        addSubview(trailingView)

        let iconSize: CGFloat = 22.swh
        iconViewWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: iconSize)
        labelLeadingConstraint = label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconViewWidthConstraint,
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            labelLeadingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingView.leadingAnchor, constant: -8.sw),

            trailingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingView.widthAnchor.constraint(equalToConstant: 18.swh),
            trailingView.heightAnchor.constraint(equalToConstant: 18.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        icon: String? = nil,
        iconImage: UIImage? = nil,
        iconColor: UIColor = .mezonTextSecondary,
        text: String,
        textColor: UIColor,
        font: UIFont? = nil,
        trailingIcon: String? = nil,
        trailingIconImage: UIImage? = nil
    ) {
        if let img = iconImage {
            iconView.image = img.withRenderingMode(.alwaysOriginal)
            iconView.isHidden = false
            iconViewWidthConstraint.constant = 22.swh
            labelLeadingConstraint.constant = 12.sw
        } else if let name = icon {
            let cfg = UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)
            iconView.image = UIImage(systemName: name, withConfiguration: cfg)
            iconView.tintColor = iconColor
            iconView.isHidden = false
            iconViewWidthConstraint.constant = 22.swh
            labelLeadingConstraint.constant = 12.sw
        } else {
            iconView.image = nil
            iconView.isHidden = true
            iconViewWidthConstraint.constant = 0
            labelLeadingConstraint.constant = 0
        }
        label.text = text
        label.textColor = textColor
        label.font = font ?? .systemFont(ofSize: 15.sf)

        if let img = trailingIconImage {
            trailingView.image = img.withRenderingMode(.alwaysTemplate)
            trailingView.tintColor = .mezonTextStrong
            trailingView.isHidden = false
        } else if let trailing = trailingIcon {
            trailingView.image = UIImage(systemName: trailing)
            trailingView.tintColor = .mezonTextStrong
            trailingView.isHidden = false
        } else {
            trailingView.isHidden = true
        }
    }
}
