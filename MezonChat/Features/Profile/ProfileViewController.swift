import UIKit
import Combine
import SwiftProtobuf

final class ProfileViewController: BaseViewController {

    private let sharedContext: SharedAccountContext

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 0
        s.alignment = .fill
        s.isLayoutMarginsRelativeArrangement = true
        s.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 24, right: 20)
        return s
    }()

    private lazy var headerBanner: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        return v
    }()

    private lazy var mezonLogoLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "mezon"
        l.font = .systemFont(ofSize: 24, weight: .bold)
        l.textColor = .white
        return l
    }()

    private lazy var avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 40
        iv.backgroundColor = .mezonSecondaryBackground
        iv.layer.borderWidth = 3
        iv.layer.borderColor = UIColor.white.cgColor
        return iv
    }()

    private lazy var onlineIndicator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .mezonSuccess
        v.layer.cornerRadius = 6
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.mezonBackground.cgColor
        return v
    }()

    private lazy var addStatusButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "plus.circle.fill")
        config.title = " \(L(L10n.Profile.addStatus))"
        config.baseForegroundColor = .white
        config.imagePadding = 4
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.contentHorizontalAlignment = .leading
        return btn
    }()

    private lazy var displayNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 22, weight: .bold)
        l.textColor = .mezonTextPrimary
        return l
    }()

    private lazy var usernameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15)
        l.textColor = .mezonTextSecondary
        return l
    }()

    private lazy var balanceCard: UIView = {
        makeCardView()
    }()

    private lazy var editProfileButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = L(L10n.Profile.editProfile)
        config.image = UIImage(systemName: "pencil")
        config.imagePadding = 8
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .mezonPrimary
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var memberSinceCard: UIView = {
        makeCardView()
    }()

    private lazy var memberSinceLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15)
        l.textColor = .mezonTextPrimary
        l.numberOfLines = 2
        l.text = L(L10n.Profile.mezonMemberSince)
        return l
    }()

    private lazy var friendsCard: UIView = {
        makeCardView()
    }()

    private lazy var copyUserIdCard: UIView = {
        makeCardView()
    }()

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonBackground
        setupUI()
        setupBindings()
    }

    override func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        headerBanner.addSubview(mezonLogoLabel)
        headerBanner.addSubview(avatarImageView)
        avatarImageView.addSubview(onlineIndicator)
        headerBanner.addSubview(addStatusButton)
        contentStack.addArrangedSubview(headerBanner)

        let userInfoStack = UIStackView(arrangedSubviews: [displayNameLabel, usernameLabel])
        userInfoStack.axis = .vertical
        userInfoStack.spacing = 4
        userInfoStack.alignment = .leading
        userInfoStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(userInfoStack)

        let balanceContent = makeBalanceCardContent()
        balanceCard.addSubview(balanceContent)
        contentStack.addArrangedSubview(balanceCard)

        contentStack.addArrangedSubview(editProfileButton)

        let memberContent = makeMemberSinceContent()
        memberSinceCard.addSubview(memberContent)
        contentStack.addArrangedSubview(memberSinceCard)

        let friendsContent = makeFriendsContent()
        friendsCard.addSubview(friendsContent)
        contentStack.addArrangedSubview(friendsCard)

        let copyContent = makeCopyUserIdContent()
        copyUserIdCard.addSubview(copyContent)
        contentStack.addArrangedSubview(copyUserIdCard)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            headerBanner.heightAnchor.constraint(equalToConstant: 140),
            mezonLogoLabel.centerXAnchor.constraint(equalTo: headerBanner.centerXAnchor),
            mezonLogoLabel.centerYAnchor.constraint(equalTo: headerBanner.centerYAnchor),

            avatarImageView.leadingAnchor.constraint(equalTo: headerBanner.leadingAnchor, constant: 20),
            avatarImageView.centerYAnchor.constraint(equalTo: headerBanner.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 80),
            avatarImageView.heightAnchor.constraint(equalToConstant: 80),

            onlineIndicator.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor),
            onlineIndicator.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor),
            onlineIndicator.widthAnchor.constraint(equalToConstant: 14),
            onlineIndicator.heightAnchor.constraint(equalToConstant: 14),

            addStatusButton.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 16),
            addStatusButton.centerYAnchor.constraint(equalTo: headerBanner.centerYAnchor),
        ])

        userInfoStack.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        userInfoStack.isLayoutMarginsRelativeArrangement = true

        balanceCard.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        balanceContent.pinToSuperview()

        editProfileButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        contentStack.setCustomSpacing(20, after: userInfoStack)
        contentStack.setCustomSpacing(16, after: balanceCard)
        contentStack.setCustomSpacing(16, after: editProfileButton)
        contentStack.setCustomSpacing(16, after: memberSinceCard)
        contentStack.setCustomSpacing(16, after: friendsCard)
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
        usernameLabel.text = user?.username.isEmpty == false ? "@\(user!.username)" : "—"

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

        let createSec = account?.user.createTimeSeconds ?? 0
        if createSec > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(createSec))
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            formatter.locale = Locale(identifier: "en_US")
            memberSinceLabel.text = "\(L(L10n.Profile.mezonMemberSince))\n\(formatter.string(from: date))"
        } else {
            memberSinceLabel.text = L(L10n.Profile.mezonMemberSince)
        }
    }

    private func makeCardView() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .mezonSecondaryBackground
        v.layer.cornerRadius = 12
        v.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        return v
    }

    private func makeBalanceCardContent() -> UIView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16

        let balanceRow = makeRow(icon: "checkmark.circle.fill", title: "\(L(L10n.Profile.balance)): 0 \(L(L10n.Profile.currency))")
        let transferRow = makeRow(icon: "arrow.up.square", title: L(L10n.Profile.transferFunds))
        let historyRow = makeRow(icon: "folder", title: L(L10n.Profile.historyTransaction))

        stack.addArrangedSubview(balanceRow)
        stack.addArrangedSubview(transferRow)
        stack.addArrangedSubview(historyRow)

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
        ])
        return wrap
    }

    private func makeMemberSinceContent() -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(memberSinceLabel)
        NSLayoutConstraint.activate([
            memberSinceLabel.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 16),
            memberSinceLabel.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            memberSinceLabel.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
            memberSinceLabel.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
        ])
        return wrap
    }

    private func makeFriendsContent() -> UIView {
        let l = UILabel()
        l.text = L(L10n.Profile.yourFriends)
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.textColor = .mezonTextPrimary

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .mezonTextSecondary

        let stack = UIStackView(arrangedSubviews: [l, UIView(), chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
        ])
        return wrap
    }

    private func makeCopyUserIdContent() -> UIView {
        let l = UILabel()
        l.text = L(L10n.Profile.copyUserId)
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.textColor = .mezonTextPrimary

        let icon = UIImageView(image: UIImage(systemName: "doc.on.doc"))
        icon.tintColor = .mezonTextSecondary

        let stack = UIStackView(arrangedSubviews: [l, UIView(), icon])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        let tap = UITapGestureRecognizer(target: self, action: #selector(copyUserIdTapped))
        wrap.addGestureRecognizer(tap)
        wrap.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
        ])
        return wrap
    }

    private func makeRow(icon: String, title: String) -> UIView {
        let iv = UIImageView(image: UIImage(systemName: icon))
        iv.tintColor = .mezonTextSecondary
        iv.setContentHuggingPriority(.required, for: .horizontal)

        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 15)
        l.textColor = .mezonTextPrimary

        let stack = UIStackView(arrangedSubviews: [iv, l])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }

    @objc private func copyUserIdTapped() {
        guard let userId = sharedContext.sharedDataStore.authStore.user?.id else { return }
        UIPasteboard.general.string = userId
        Toast.info(L(L10n.Profile.userIdCopied))
    }
}

private extension UIView {
    func pinToSuperview() {
        guard let sv = superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: sv.topAnchor),
            leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            bottomAnchor.constraint(equalTo: sv.bottomAnchor),
        ])
    }
}
