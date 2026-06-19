import UIKit

@MainActor
final class BlockedUsersViewController: BaseViewController {

    private let context: AccountContext
    private var blockedUsers: [Mezon_Api_Friend] = []
    private var inProgressUnblockIds: Set<Int64> = []

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let emptyView = UIView()
    private let emptyLabel = UILabel()

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupTableView()
        setupEmptyView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchBlockedUsers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
        emptyLabel.textColor = UIColor.theme.textDisabled
        tableView.reloadData()
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        titleLabel.text = L(L10n.AccountSetting.blockedUsers)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center

        [backButton, titleLabel].forEach {
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
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupTableView() {
        tableView.backgroundColor = UIColor.theme.secondary
        tableView.layer.cornerRadius = 12
        tableView.clipsToBounds = true
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(BlockedUserItemCell.self, forCellReuseIdentifier: BlockedUserItemCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.showsVerticalScrollIndicator = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16.sh)
        ])
    }

    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)

        emptyLabel.text = L(L10n.AccountSetting.noBlockedUsers)
        emptyLabel.font = .systemFont(ofSize: 16.sf, weight: .medium)
        emptyLabel.textColor = UIColor.theme.textDisabled
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.topAnchor.constraint(equalTo: emptyView.topAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyView.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyView.trailingAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyView.bottomAnchor)
        ])
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func fetchBlockedUsers() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                let response = try await MezonHTTPClient.shared.listFriends(token: token, limit: 100, state: 0)
                let currentUserId = Int64(self.context.currentUser?.id ?? "") ?? 0
                
                self.blockedUsers = response.friends.filter { friend in
                    let isBlocked = friend.state == 3
                    let isSource = friend.sourceID == currentUserId
                    return isBlocked && isSource
                }
                self.reloadUI()
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func reloadUI() {
        tableView.reloadData()
        emptyView.isHidden = !blockedUsers.isEmpty
        tableView.isHidden = blockedUsers.isEmpty
    }

    private func unblockUser(_ user: Mezon_Api_Friend) {
        let userId = user.user.id
        guard !inProgressUnblockIds.contains(userId) else { return }
        inProgressUnblockIds.insert(userId)
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.inProgressUnblockIds.remove(userId)
            }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                if user.user.id != 0 {
                    try await self.context.account.network.unblockFriends(ids: [user.user.id], token: token)
                } else if !user.user.username.isEmpty {
                    try await self.context.account.network.unblockFriends(usernames: [user.user.username], token: token)
                } else {
                    return
                }
                self.context.engine.friendsData.applyLocalBlockState(userId: user.user.id, blocked: false)
                
                let friendsData = self.context.engine.friendsData
                Task {
                    await friendsData.refreshFromNetwork(token: token, force: true)
                }
                
                Toast.success(L(L10n.DmMenu.unblockUserSuccess))
                
                if let index = self.blockedUsers.firstIndex(where: { $0.user.id == user.user.id }) {
                    self.blockedUsers.remove(at: index)
                    self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .none)
                    self.emptyView.isHidden = !self.blockedUsers.isEmpty
                    self.tableView.isHidden = self.blockedUsers.isEmpty
                }
            } catch {
                Toast.error(L(L10n.DmMenu.unblockUserError))
            }
        }
    }
}

extension BlockedUsersViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return blockedUsers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BlockedUserItemCell.reuseId, for: indexPath) as! BlockedUserItemCell
        let user = blockedUsers[indexPath.row]
        let isLast = indexPath.row == blockedUsers.count - 1
        
        cell.configure(with: user, isLast: isLast)
        cell.onUnblockTapped = { [weak self] in
            self?.unblockUser(user)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72.sh
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

final class BlockedUserItemCell: UITableViewCell {

    static let reuseId = "BlockedUserItemCell"

    private let avatarView = TextAvatarView(username: "", size: 40)
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let unblockButton = UIButton(type: .system)
    private let separatorView = UIView()
    private var currentAvatarUrl: String?
    
    var onUnblockTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 20.swh
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.isHidden = true
        contentView.addSubview(avatarImageView)

        nameLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(nameLabel)

        unblockButton.setTitle(L(L10n.AccountSetting.unblock), for: .normal)
        unblockButton.titleLabel?.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        unblockButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        unblockButton.backgroundColor = UIColor.theme.border
        unblockButton.layer.cornerRadius = 6.swh
        unblockButton.translatesAutoresizingMaskIntoConstraints = false
        unblockButton.addTarget(self, action: #selector(unblockTapped), for: .touchUpInside)
        unblockButton.contentEdgeInsets = UIEdgeInsets(top: 6.sh, left: 12.sw, bottom: 6.sh, right: 12.sw)
        unblockButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(unblockButton)

        separatorView.backgroundColor = UIColor.theme.border
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 40.swh),

            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.widthAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarImageView.heightAnchor.constraint(equalTo: avatarView.heightAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: unblockButton.leadingAnchor, constant: -8.sw),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            unblockButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            unblockButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    func configure(with friend: Mezon_Api_Friend, isLast: Bool) {
        let displayName = friend.user.displayName.isEmpty ? friend.user.username : friend.user.displayName
        nameLabel.text = displayName
        separatorView.isHidden = isLast

        avatarView.configure(username: friend.user.username)

        let targetUrl = friend.user.avatarURL
        if !targetUrl.isEmpty {
            avatarView.showSkeleton()
            let resolvedUrlString = ImgproxyURL.create(from: targetUrl, width: 40, height: 40)
            currentAvatarUrl = resolvedUrlString
            
            ImageCache.shared.loadImage(urlString: resolvedUrlString) { [weak self] image in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    guard self.currentAvatarUrl == resolvedUrlString else { return }
                    if let image = image {
                        self.avatarImageView.image = image
                        self.avatarImageView.isHidden = false
                        self.avatarView.showImageMode()
                    } else {
                        self.avatarImageView.isHidden = true
                        self.avatarView.showPlaceholder()
                    }
                }
            }
        } else {
            currentAvatarUrl = nil
            avatarImageView.isHidden = true
            avatarView.showPlaceholder()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentAvatarUrl = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarView.showPlaceholder()
    }
    
    @objc private func unblockTapped() {
        onUnblockTapped?()
    }
}
