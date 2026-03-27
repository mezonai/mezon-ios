import UIKit
import AsyncDisplayKit

@MainActor
final class ProfileContainerNode: ASDisplayNode {

    private let fixedHeaderView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let context: AccountContext

    var onBackTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?

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
        v.backgroundColor = .colorAvatarDefault
        v.clipsToBounds = true
        return v
    }()
    private let avatarImageView = UIImageView()
    private let onlineDot: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonSuccess
        return v
    }()
    private let addStatusButton: UIButton = {
        let btn = UIButton(type: .system)
        return btn
    }()
    private let statusBubbleContainer = UIView()
    private let statusBubbleShapeLayer = CAShapeLayer()

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
        var cfg = UIButton.Configuration.filled()
        cfg.cornerStyle = .capsule
        cfg.baseForegroundColor = .white
        cfg.baseBackgroundColor = .outgoingBubble
        cfg.imagePadding = 8
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        btn.configuration = cfg
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

    private static func profileImageResized(named: String, size: CGFloat = 24) -> UIImage? {
        guard let img = profileImage(named: named) else { return nil }
        let target = CGSize(width: size, height: size)
        let ratio = min(target.width / img.size.width, target.height / img.size.height)
        let drawSize = CGSize(width: img.size.width * ratio, height: img.size.height * ratio)
        let drawRect = CGRect(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { ctx in
            img.draw(in: drawRect)
        }
        return resized.withRenderingMode(img.renderingMode)
    }

    init(context: AccountContext) {
        self.context = context
        super.init()
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

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeOrLanguageChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeOrLanguageChange), name: LanguageManager.didChangeNotification, object: nil)
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
        onlineDot.layer.borderColor = UIColor.mezonTertiary.cgColor
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
        }
        statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor

        var statusCfg = addStatusButton.configuration ?? UIButton.Configuration.plain()
        statusCfg.image = Self.makePlusIconInCircle(containerColor: .outgoingBubble, iconColor: .white)
        statusCfg.baseForegroundColor = .mezonTextPrimary
        statusCfg.attributedTitle = AttributedString(
            L(L10n.Profile.addStatus),
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .medium),
                .foregroundColor: UIColor.mezonTextPrimary
            ])
        )
        addStatusButton.configuration = statusCfg
    }

    private func setupHeader() {
        fixedHeaderView.addSubview(headerBackgroundView)
        fixedHeaderView.sendSubviewToBack(headerBackgroundView)

        avatarContainerView.layer.cornerRadius = 16.swh
        avatarContainerView.layer.borderWidth = 3
        avatarContainerView.layer.borderColor = UIColor.mezonSecondaryBackground.cgColor
        fixedHeaderView.addSubview(avatarContainerView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarContainerView.addSubview(avatarImageView)

        let dotSize: CGFloat = 16.swh
        onlineDot.layer.cornerRadius = dotSize / 2
        onlineDot.layer.borderWidth = 2
        onlineDot.layer.borderColor = UIColor.mezonTertiary.cgColor
        fixedHeaderView.addSubview(onlineDot)

        statusBubbleContainer.backgroundColor = .clear
        statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
        statusBubbleContainer.layer.insertSublayer(statusBubbleShapeLayer, at: 0)

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
        statusBubbleContainer.addSubview(addStatusButton)
        fixedHeaderView.addSubview(statusBubbleContainer)
    }

    private func setupNameArea() {
        nameLabel.font = .systemFont(ofSize: 22.sf, weight: .bold)
        nameLabel.textColor = .mezonTextStrong
        fixedHeaderView.addSubview(nameLabel)
        fixedHeaderView.addSubview(chevronDown)

        usernameLabel.font = .systemFont(ofSize: 14.sf)
        usernameLabel.textColor = .mezonTextPrimary
        fixedHeaderView.addSubview(usernameLabel)

        let iconBtnSize: CGFloat = 36.swh
        headphoneButton.layer.cornerRadius = iconBtnSize / 2
        headphoneButton.clipsToBounds = true
        fixedHeaderView.addSubview(headphoneButton)

        micButton.layer.cornerRadius = iconBtnSize / 2
        micButton.clipsToBounds = true
        micButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        fixedHeaderView.addSubview(micButton)
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
    }

    private func setupAboutMeCard() {
        styleCard(aboutMeCard)
        contentView.addSubview(aboutMeCard)

        let cardInset: CGFloat = 16.sw
        for v in [aboutMeTitleLabel, aboutMeContentLabel, memberSinceTitleLabel, memberSinceDateLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            aboutMeCard.addSubview(v)
        }

        NSLayoutConstraint.activate([
            aboutMeTitleLabel.topAnchor.constraint(equalTo: aboutMeCard.topAnchor, constant: 16.sh),
            aboutMeTitleLabel.leadingAnchor.constraint(equalTo: aboutMeCard.leadingAnchor, constant: cardInset),
            aboutMeTitleLabel.trailingAnchor.constraint(equalTo: aboutMeCard.trailingAnchor, constant: -cardInset),

            aboutMeContentLabel.topAnchor.constraint(equalTo: aboutMeTitleLabel.bottomAnchor, constant: 4.sh),
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

    private func styleCard(_ card: UIView) {
        card.backgroundColor = .mezonPrimary
        card.layer.cornerRadius = 20.swh
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.mezonBorder.cgColor
        card.clipsToBounds = true
    }

    func updateContent() {
        let user = context.currentUser

        if let url = user?.avatarURL {
            Task {
                if let data = try? await URLSession.shared.data(from: url).0,
                   let img = UIImage.decodeImage(from: data) {
                    let color = img.dominantColor()
                    await MainActor.run {
                        self.avatarImageView.image = img
                        self.headerBackgroundView.backgroundColor = color ?? .mezonBackground
                        self.statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
                    }
                }
            }
        } else {
            avatarImageView.image = nil
            headerBackgroundView.backgroundColor = .mezonSecondaryBackground
            statusBubbleShapeLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
        }

        onlineDot.isHidden = user?.status != .online

        nameLabel.text = user?.displayName ?? "—"
        usernameLabel.text = user?.username.isEmpty == false ? user!.username : "—"

        let balanceAmount = "145.776"
        balanceRow.configure(
            icon: "checkmark.circle.fill",
            iconImage: Self.profileImage(named: "BalanceIcon"),
            iconColor: .mezonSuccess,
            text: "\(L(L10n.Profile.balance)): \(balanceAmount) \(L(L10n.Profile.currency))",
            textColor: .mezonTextStrong
        )
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
        editProfileButton.configuration?.image = editIcon
        editProfileButton.configuration?.title = L(L10n.Profile.editProfile)
        editProfileButton.configuration?.attributedTitle = AttributedString(
            L(L10n.Profile.editProfile),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold)])
        )

        aboutMeTitleLabel.text = L(L10n.Profile.aboutMe)
        aboutMeContentLabel.text = user?.bio ?? "—"
        memberSinceTitleLabel.text = L(L10n.Profile.mezonMemberSince)
        memberSinceDateLabel.text = formatMemberSince()

        friendsTitleLabel.text = L(L10n.Profile.yourFriends)
        setupFriendAvatars()

        copyRow.configure(
            text: L(L10n.Profile.copyUserId),
            textColor: .mezonTextStrong,
            font: .systemFont(ofSize: 13.sf, weight: .bold),
            trailingIconImage: Self.profileImage(named: "IDIcon")
        )
    }

    private func formatMemberSince() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: Date())
    }

    private func setupFriendAvatars() {
        friendsAvatarStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let friendColors: [UIColor] = [
            .systemOrange, .systemPurple, .systemTeal, .systemPink, .colorAvatarDefault
        ]
        let avatarSmall: CGFloat = 28.swh
        for color in friendColors {
            let circle = UIView()
            circle.backgroundColor = color
            circle.layer.cornerRadius = avatarSmall / 2
            circle.layer.borderWidth = 2
            circle.layer.borderColor = UIColor.mezonPrimary.cgColor
            circle.clipsToBounds = true
            circle.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                circle.widthAnchor.constraint(equalToConstant: avatarSmall),
                circle.heightAnchor.constraint(equalToConstant: avatarSmall),
            ])
            friendsAvatarStack.addArrangedSubview(circle)
        }
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
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
        avatarImageView.frame = avatarContainerView.bounds

        let dotSize: CGFloat = 16.swh
        onlineDot.frame = CGRect(
            x: avatarContainerView.frame.maxX - dotSize - 2,
            y: avatarContainerView.frame.maxY - dotSize - 2,
            width: dotSize,
            height: dotSize
        )

        addStatusButton.sizeToFit()
        let statusX = avatarContainerView.frame.maxX + 12.sw
        let bubbleBodyH: CGFloat = 44.sh
        let tailH: CGFloat = 8.sh
        let bubbleW = min(addStatusButton.intrinsicContentSize.width + 12, width - statusX - side)
        let totalBubbleH = bubbleBodyH + tailH

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
        nameLabel.frame = CGRect(x: side, y: y, width: nameLabel.intrinsicContentSize.width, height: 28.sh)

        let chevronSize: CGFloat = 14.swh
        chevronDown.frame = CGRect(
            x: nameLabel.frame.maxX + 6.sw,
            y: y + (28.sh - chevronSize) / 2,
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
        balanceCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: 0)
        balanceCard.layoutIfNeeded()
        let balanceHeight = balanceCard.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        balanceCard.frame = CGRect(x: side, y: scrollY, width: cardWidth, height: balanceHeight)
        scrollY += balanceHeight + cardSpacing

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

    @objc private func settingsTapped() {
        onSettingsTapped?()
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
