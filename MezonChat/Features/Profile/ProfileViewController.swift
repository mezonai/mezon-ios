import UIKit
import Combine
import SwiftProtobuf

final class ProfileViewController: BaseViewController {

    private let sharedContext: SharedAccountContext
    private var scrollViewTopConstraint: NSLayoutConstraint?

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        sv.contentInsetAdjustmentBehavior = .never
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 0
        s.alignment = .fill
        return s
    }()

    private lazy var headerBanner: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .outgoingBubble
        v.clipsToBounds = true
        return v
    }()

    private lazy var mezonLogoLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "mezon"
        l.font = .systemFont(ofSize: 36.sf, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    private lazy var avatarContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 20.swh
        iv.backgroundColor = .mezonSecondaryBackground
        iv.layer.borderWidth = 3
        iv.layer.borderColor = UIColor.mezonBackground.cgColor
        return iv
    }()

    private lazy var onlineIndicator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .mezonSuccess
        v.layer.cornerRadius = 7.swh
        v.layer.borderWidth = 4
       v.layer.borderColor = UIColor.mezonSuccess.cgColor
        return v
    }()

    private lazy var statusBubbleView: StatusBubbleView = {
        let v = StatusBubbleView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var statusBubbleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14.sf, weight: .medium)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private lazy var displayNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 20.sf, weight: .bold)
        l.textColor = .mezonTextStrong
        return l
    }()

    private lazy var nameChevron: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.down"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .mezonTextSecondary
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }()

    private lazy var storeButton: UIButton = {
        makeRoundedIconButton(imageName: "Profile/Shop/IconShop")
    }()

    private lazy var settingsButton: UIButton = {
        let btn = makeRoundedIconButton(imageName: "Profile/Setting/IconSetting")
        btn.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var usernameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15.sf)
        l.textColor = .mezonTextPrimary
        return l
    }()

    private lazy var balanceCard: UIView = { makeCardView() }()
    private weak var balanceRowLabel: UILabel?

    private lazy var editProfileButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = L(L10n.Profile.editProfile)
        config.image = UIImage(bundleImageName: "Profile/Edit/IconEdit")
            ?? UIImage(named: "Profile/Edit/IconEdit")
            ?? UIImage(named: "IconEdit")
        config.imagePadding = 8.sw
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .outgoingBubble
        config.cornerStyle = .large
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var aboutMemberCard: UIView = { makeCardView() }()

    private lazy var friendsCard: UIView = { makeCardView() }()

    private lazy var copyUserIdCard: UIView = { makeCardView() }()

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonBackground
        extendedLayoutIncludesOpaqueBars = true
        setupUI()
        setupBindings()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let topInset = view.safeAreaInsets.top
        scrollViewTopConstraint?.constant = -(topInset + 44)
    }

    override func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        scrollViewTopConstraint = scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            scrollViewTopConstraint!,
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        setupHeaderBanner()
        setupAvatarArea()
        setupUserInfo()
        setupBalanceCard()
        setupEditProfileButton()
        setupAboutMemberCard()
        setupFriendsCard()
        setupCopyUserIdCard()
    }

    private func setupHeaderBanner() {
        headerBanner.addSubview(mezonLogoLabel)
        contentStack.addArrangedSubview(headerBanner)

        NSLayoutConstraint.activate([
            headerBanner.heightAnchor.constraint(equalToConstant: 140.sh),
            mezonLogoLabel.centerXAnchor.constraint(equalTo: headerBanner.centerXAnchor),
            mezonLogoLabel.centerYAnchor.constraint(equalTo: headerBanner.centerYAnchor, constant: -10.sh),
        ])
    }

    private func setupAvatarArea() {
        let avatarSize: CGFloat = 80.swh
        let overlapHeight: CGFloat = avatarSize / 2

        statusBubbleView.addSubview(statusBubbleLabel)
        avatarContainer.addSubviews(avatarImageView, onlineIndicator, statusBubbleView)
        contentStack.addArrangedSubview(avatarContainer)

        NSLayoutConstraint.activate([
            avatarContainer.heightAnchor.constraint(equalToConstant: overlapHeight + 8.sh),

            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor, constant: 16.sw),
            avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor, constant: -overlapHeight),
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),

            onlineIndicator.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: -18.sw),
            onlineIndicator.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: -2.sh),
            onlineIndicator.widthAnchor.constraint(equalToConstant: 14.swh),
            onlineIndicator.heightAnchor.constraint(equalToConstant: 14.swh),

            statusBubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8.sw),
            statusBubbleView.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            statusBubbleView.trailingAnchor.constraint(lessThanOrEqualTo: avatarContainer.trailingAnchor, constant: -16.sw),
            statusBubbleView.widthAnchor.constraint(greaterThanOrEqualToConstant: 70.sw),

            statusBubbleLabel.topAnchor.constraint(equalTo: statusBubbleView.topAnchor, constant: 8.sh),
            statusBubbleLabel.leadingAnchor.constraint(equalTo: statusBubbleView.leadingAnchor, constant: 14.sw),
            statusBubbleLabel.trailingAnchor.constraint(equalTo: statusBubbleView.trailingAnchor, constant: -14.sw),
            statusBubbleLabel.bottomAnchor.constraint(equalTo: statusBubbleView.bottomAnchor, constant: -(8 + 14).sh),
        ])
    }

    private func setupUserInfo() {
        let nameStack = UIStackView(arrangedSubviews: [displayNameLabel, nameChevron])
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        nameStack.axis = .horizontal
        nameStack.spacing = 6.sw
        nameStack.alignment = .center

        let rightIcons = UIStackView(arrangedSubviews: [storeButton, settingsButton])
        rightIcons.translatesAutoresizingMaskIntoConstraints = false
        rightIcons.axis = .horizontal
        rightIcons.spacing = 12.sw
        rightIcons.alignment = .center

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [nameStack, spacer, rightIcons])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.alignment = .center

        let infoStack = UIStackView(arrangedSubviews: [topRow, usernameLabel])
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 4.sh
        infoStack.alignment = .fill
        infoStack.isLayoutMarginsRelativeArrangement = true
        infoStack.layoutMargins = UIEdgeInsets(top: 8.sh, left: 16.sw, bottom: 12.sh, right: 16.sw)

        contentStack.addArrangedSubview(infoStack)
    }

    private func setupBalanceCard() {
        balanceCard.subviews.forEach { $0.removeFromSuperview() }
        let balanceContent = makeBalanceCardContent()
        balanceCard.addSubview(balanceContent)
        balanceContent.pinEdges(insets: UIEdgeInsets(top: 16.sh, left: 20.sw, bottom: 16.sh, right: 20.sw))

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(balanceCard)
        balanceCard.pinEdges(insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 16.sw))

        contentStack.addArrangedSubview(wrapper)
        contentStack.setCustomSpacing(16.sh, after: wrapper)
    }

    private func setupEditProfileButton() {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(editProfileButton)
        editProfileButton.pinEdges(insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 16.sw))
        editProfileButton.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true

        contentStack.addArrangedSubview(wrapper)
        contentStack.setCustomSpacing(16.sh, after: wrapper)
    }

    private func setupAboutMemberCard() {
        let aboutContent = makeAboutMemberCardContent()
        aboutMemberCard.addSubview(aboutContent)
        aboutContent.pinEdges(insets: UIEdgeInsets(top: 16.sh, left: 20.sw, bottom: 16.sh, right: 20.sw))

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(aboutMemberCard)
        aboutMemberCard.pinEdges(insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 16.sw))

        contentStack.addArrangedSubview(wrapper)
        contentStack.setCustomSpacing(16.sh, after: wrapper)
    }

    private func makeAboutMemberCardContent() -> UIView {
        let aboutMeTitle = UILabel()
        aboutMeTitle.text = L(L10n.Profile.aboutMe)
        aboutMeTitle.font = .systemFont(ofSize: 15.sf, weight: .bold)
        aboutMeTitle.textColor = .mezonTextPrimary
        let aboutMeValue = UILabel()
        aboutMeValue.text = "2028"
        aboutMeValue.font = .systemFont(ofSize: 15.sf)
        aboutMeValue.textColor = .mezonTextPrimary
        aboutMeValue.numberOfLines = 0

        let separator = UIView()
        separator.backgroundColor = .mezonBorder
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let memberSinceTitle = UILabel()
        memberSinceTitle.text = L(L10n.Profile.mezonMemberSince)
        memberSinceTitle.font = .systemFont(ofSize: 15.sf, weight: .bold)
        memberSinceTitle.textColor = .mezonTextPrimary

        let memberSinceDate = UILabel()
        memberSinceDate.text = "May 27, 2025"
        memberSinceDate.font = .systemFont(ofSize: 15.sf)
        memberSinceDate.textColor = .mezonTextPrimary

        let stack = UIStackView(arrangedSubviews: [
            aboutMeTitle,
            aboutMeValue,
            separator,
            memberSinceTitle,
            memberSinceDate,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4.sh
        stack.alignment = .leading
        stack.setCustomSpacing(12.sh, after: aboutMeValue)
        stack.setCustomSpacing(12.sh, after: separator)
        return stack
    }

    private func setupFriendsCard() {
        let friendsContent = makeFriendsContent()
        friendsCard.addSubview(friendsContent)
        friendsContent.pinEdges(insets: UIEdgeInsets(top: 12.sh, left: 20.sw, bottom: 12.sh, right: 20.sw))

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(friendsCard)
        friendsCard.pinEdges(insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 16.sw))

        contentStack.addArrangedSubview(wrapper)
        contentStack.setCustomSpacing(16.sh, after: wrapper)
    }

    private func setupCopyUserIdCard() {
        let copyContent = makeCopyUserIdContent()
        copyUserIdCard.addSubview(copyContent)
        copyContent.pinEdges(insets: UIEdgeInsets(top: 12.sh, left: 20.sw, bottom: 12.sh, right: 20.sw))

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(copyUserIdCard)
        copyUserIdCard.pinEdges(insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 16.sw))

        contentStack.addArrangedSubview(wrapper)
        contentStack.setCustomSpacing(24.sh, after: wrapper)
    }

    override func setupBindings() {
        sharedContext.sharedDataStore.authStore.$user
            .combineLatest(sharedContext.sharedDataStore.authStore.$account)
            .receive(on: RunLoop.main)
            .sink { [weak self] user, account in
                self?.updateUI(user: user, account: account)
            }
            .store(in: &cancellables)
    }

    private func updateUI(user: User?, account: Mezon_Api_Account?) {
        displayNameLabel.text = user?.displayName ?? "—"
        usernameLabel.text = user?.username.isEmpty == false ? user!.username : "—"

        if let url = user?.avatarURL ?? account.flatMap({ !$0.logo.isEmpty ? URL(string: $0.logo) : nil }) {
            Task {
                if let data = try? await URLSession.shared.data(from: url).0, let img = UIImage(data: data) {
                    await MainActor.run { avatarImageView.image = img }
                }
            }
        } else {
            avatarImageView.image = nil
        }

        onlineIndicator.isHidden = user?.status != .online

        if let status = user?.status {
            statusBubbleView.isHidden = false
            switch status {
            case .online: statusBubbleLabel.text = "Online"
            case .idle: statusBubbleLabel.text = "Idle"
            case .doNotDisturb: statusBubbleLabel.text = "Do Not Disturb"
            case .offline: statusBubbleLabel.text = "Offline"
            }
        } else {
            statusBubbleView.isHidden = true
        }

        balanceRowLabel?.text = "\(L(L10n.Profile.balance)): 0 \(L(L10n.Profile.currency))"
    }

    private func makeCardView() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .mezonSecondaryBackground
        v.layer.cornerRadius = 12.swh
        return v
    }

    private func makeBalanceCardContent() -> UIView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16.sh

        let balanceIcon = makeIconView(imageName: "Profile/Balance/IconBalance", size: 22.swh)
        balanceIcon.setContentHuggingPriority(.required, for: .horizontal)
        let balanceTextLabel = UILabel()
        balanceTextLabel.text = "\(L(L10n.Profile.balance)): 0 \(L(L10n.Profile.currency))"
        balanceTextLabel.font = .systemFont(ofSize: 15.sf)
        balanceTextLabel.textColor = .mezonTextPrimary
        balanceRowLabel = balanceTextLabel
        let balanceRow = UIStackView(arrangedSubviews: [balanceIcon, balanceTextLabel])
        balanceRow.axis = .horizontal
        balanceRow.spacing = 12.sw
        balanceRow.alignment = .center
        balanceRow.translatesAutoresizingMaskIntoConstraints = false
        balanceRow.clipsToBounds = true

        let transferIcon = makeIconView(imageName: "Profile/Transfer/IconTransfer", size: 22.swh)
        let transferLabel = UILabel()
        transferLabel.font = .systemFont(ofSize: 15.sf)
        transferLabel.textColor = .mezonTextPrimary
        transferLabel.text = L(L10n.Profile.transferFunds)
        let transferRow = makeIconRow(iconView: transferIcon, label: transferLabel)

        let historyIcon = makeIconView(imageName: "Profile/History/IconHistory", size: 22.swh)
        let historyLabel = UILabel()
        historyLabel.font = .systemFont(ofSize: 15.sf)
        historyLabel.textColor = .mezonTextPrimary
        historyLabel.text = L(L10n.Profile.historyTransaction)
        let historyRow = makeIconRow(iconView: historyIcon, label: historyLabel)

        stack.addArrangedSubview(balanceRow)
        stack.addArrangedSubview(transferRow)
        stack.addArrangedSubview(historyRow)
        return stack
    }

    private func makeFriendsContent() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = L(L10n.Profile.yourFriends)
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .bold)
        titleLabel.textColor = .mezonTextStrong
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let avatarsStack = makeFriendAvatarsStack()

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .mezonTextSecondary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, avatarsStack, chevron])
        stack.axis = .horizontal
        stack.spacing = 8.sw
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeFriendAvatarsStack() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let avatarSize: CGFloat = 28.swh
        let overlap: CGFloat = 8.sw
        let count = 4

        var previousView: UIView?
        for i in 0..<count {
            let circle = UIView()
            circle.translatesAutoresizingMaskIntoConstraints = false
            circle.backgroundColor = .colorAvatarDefault
            circle.layer.cornerRadius = avatarSize / 2
            circle.layer.borderWidth = 2
            circle.layer.borderColor = UIColor.mezonSecondaryBackground.cgColor
            container.addSubview(circle)

            NSLayoutConstraint.activate([
                circle.widthAnchor.constraint(equalToConstant: avatarSize),
                circle.heightAnchor.constraint(equalToConstant: avatarSize),
                circle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            if let prev = previousView {
                circle.leadingAnchor.constraint(equalTo: prev.leadingAnchor, constant: avatarSize - overlap).isActive = true
            } else {
                circle.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
            }

            if i == count - 1 {
                circle.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
            }
            previousView = circle
        }

        container.heightAnchor.constraint(equalToConstant: avatarSize).isActive = true
        return container
    }

    private func makeCopyUserIdContent() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = L(L10n.Profile.copyUserId)
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .bold)
        titleLabel.textColor = .mezonTextStrong

        let idBadge = UILabel()
        idBadge.translatesAutoresizingMaskIntoConstraints = false
        idBadge.text = " ID "
        idBadge.font = .systemFont(ofSize: 12.sf, weight: .bold)
        idBadge.textColor = .mezonTextPrimary
        idBadge.layer.cornerRadius = 4.swh
        idBadge.layer.borderWidth = 1.5
        idBadge.layer.borderColor = UIColor.mezonTextSecondary.cgColor
        idBadge.layer.masksToBounds = true
        idBadge.textAlignment = .center
        NSLayoutConstraint.activate([
            idBadge.widthAnchor.constraint(equalToConstant: 28.sw),
            idBadge.heightAnchor.constraint(equalToConstant: 20.sh),
        ])

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, spacer, idBadge])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(copyUserIdTapped))
        stack.addGestureRecognizer(tap)
        stack.isUserInteractionEnabled = true

        return stack
    }

    private func makeIconView(systemName: String, color: UIColor, size: CGFloat) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: size * 0.65, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: systemName, withConfiguration: config))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = color
        iv.contentMode = .center
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: size),
            iv.heightAnchor.constraint(equalToConstant: size),
        ])
        return iv
    }

    private func makeIconView(imageName: String, color: UIColor? = nil, size: CGFloat) -> UIImageView {
        let sourceImage = UIImage(bundleImageName: imageName)
            ?? UIImage(named: imageName)
            ?? UIImage(named: (imageName as NSString).lastPathComponent)
        let img = color != nil
            ? generateTintedImage(image: sourceImage, color: color!)
            : sourceImage
        let iv = UIImageView(image: img)
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .center
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: size),
            iv.heightAnchor.constraint(equalToConstant: size),
        ])
        return iv
    }

    private func makeIconRow(iconView: UIView, label: UILabel) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 12.sw
        stack.alignment = .center
        return stack
    }

    private func makeRoundedIconButton(systemName: String) -> UIButton {
        let size: CGFloat = 30.swh
        let config = UIImage.SymbolConfiguration(pointSize: 14.sf, weight: .medium)
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        btn.tintColor = .mezonTextPrimary
        btn.backgroundColor = .mezonSecondaryBackground
        btn.layer.cornerRadius = size / 2
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: size),
            btn.heightAnchor.constraint(equalToConstant: size),
        ])
        return btn
    }

    private func makeRoundedIconButton(imageName: String) -> UIButton {
        let size: CGFloat = 30.swh
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let sourceImage = UIImage(bundleImageName: imageName)
            ?? UIImage(named: imageName)
            ?? UIImage(named: (imageName as NSString).lastPathComponent)
        let img = generateTintedImage(image: sourceImage, color: .mezonTextPrimary)
        btn.setImage(img, for: .normal)
        btn.backgroundColor = .mezonSecondaryBackground
        btn.layer.cornerRadius = size / 2
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: size),
            btn.heightAnchor.constraint(equalToConstant: size),
        ])
        return btn
    }

    @objc private func settingsTapped() {
        let vc = SettingsViewController(sharedContext: sharedContext)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func copyUserIdTapped() {
        guard let userId = sharedContext.sharedDataStore.authStore.user?.id else { return }
        UIPasteboard.general.string = userId
        Toast.info(L(L10n.Profile.userIdCopied))
    }
}
