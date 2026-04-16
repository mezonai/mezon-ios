import CoreImage
import UIKit

final class ClanInviteSheetViewController: ViewController {
    private static let inviteIdRegex = try? NSRegularExpression(pattern: "/invite/(\\d+)", options: [])

    private enum InviteTarget: Hashable {
        case friend(userId: Int64)
        case direct(channelId: Int64, type: Int32, isPublic: Bool)
    }

    private struct FriendItem: Hashable {
        let id: Int64
        let name: String
        let avatarURL: String?
        let isGroupDM: Bool
        let target: InviteTarget
    }

    private let context: AccountContext
    private let clanId: Int64

    private var inviteLink: String?
    private var allFriends: [FriendItem] = []
    private var filteredFriends: [FriendItem] = []
    private var sentIds = Set<Int64>()
    private var sendingIds = Set<Int64>()
    private var dmChannelsByUserId: [Int64: Mezon_Api_ChannelDescription] = [:]

    private let rootStack = UIStackView()
    private let headerWrap = UIView()
    private let titleLabel = UILabel()
    private let actionWrap = UIView()
    private let actionRow = UIStackView()
    private let actionBottomDivider = UIView()
    private let searchWrap = UIView()
    private let searchField = UITextField()
    private let searchClearButton = UIButton(type: .system)
    private let listContainer = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let loadingLabel = UILabel()
    private let loadingSpinner = UIActivityIndicatorView(style: .medium)
    private let emptyStateView = UIStackView()
    private let emptyImageView = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptyDescriptionLabel = UILabel()
    private let emptyActionButton = UIButton(type: .system)

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        applyTheme()
        loadData()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        view.layer.cornerRadius = 8.swh
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true

        rootStack.axis = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        headerWrap.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(headerWrap)

        titleLabel.text = L(L10n.ClanInviteSheet.title)
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerWrap.addSubview(titleLabel)

        actionWrap.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(actionWrap)

        actionRow.axis = .horizontal
        actionRow.distribution = .equalSpacing
        actionRow.spacing = 0
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionWrap.addSubview(actionRow)

        actionRow.addArrangedSubview(makeActionButton(iconAsset: "Invite/ShareIcon", fallbackSystemIcon: "square.and.arrow.up", title: L(L10n.ClanInviteSheet.share), action: #selector(shareInvite)))
        actionRow.addArrangedSubview(makeActionButton(iconAsset: "Invite/LinkIcon", fallbackSystemIcon: "link", title: L(L10n.ClanInviteSheet.copy), action: #selector(copyInvite)))
        actionRow.addArrangedSubview(makeActionButton(iconAsset: "", fallbackSystemIcon: "qrcode", title: L(L10n.ClanInviteSheet.qrCode), action: #selector(showQR)))

        actionBottomDivider.translatesAutoresizingMaskIntoConstraints = false
        actionWrap.addSubview(actionBottomDivider)

        let searchOuter = UIView()
        searchOuter.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(searchOuter)

        searchWrap.backgroundColor = UIColor.theme.secondary
        searchWrap.layer.cornerRadius = 8.swh
        searchWrap.translatesAutoresizingMaskIntoConstraints = false
        searchOuter.addSubview(searchWrap)

        let iconView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iconView.tintColor = UIColor.theme.textDisabled
        iconView.translatesAutoresizingMaskIntoConstraints = false
        searchWrap.addSubview(iconView)

        searchField.placeholder = L(L10n.ClanInviteSheet.searchPlaceholder)
        searchField.borderStyle = .none
        searchField.font = .systemFont(ofSize: 15.sf, weight: .regular)
        searchField.clearButtonMode = .never
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchWrap.addSubview(searchField)

        searchClearButton.translatesAutoresizingMaskIntoConstraints = false
        searchClearButton.setImage(
            UIImage(systemName: "xmark.circle.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .regular)
            ),
            for: .normal
        )
        searchClearButton.isHidden = true
        searchClearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        searchWrap.addSubview(searchClearButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: searchWrap.leadingAnchor, constant: 8.sw),
            iconView.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18.swh),
            iconView.heightAnchor.constraint(equalToConstant: 18.swh),
            searchField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8.sw),
            searchField.trailingAnchor.constraint(equalTo: searchClearButton.leadingAnchor, constant: -4.sw),
            searchField.topAnchor.constraint(equalTo: searchWrap.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchWrap.bottomAnchor),
            searchClearButton.trailingAnchor.constraint(equalTo: searchWrap.trailingAnchor, constant: -8.sw),
            searchClearButton.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor),
            searchClearButton.widthAnchor.constraint(equalToConstant: 24.swh),
            searchClearButton.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let loadingWrap = UIStackView(arrangedSubviews: [loadingSpinner, loadingLabel])
        loadingWrap.axis = .horizontal
        loadingWrap.spacing = 8.sw
        loadingWrap.alignment = .center
        loadingWrap.isHidden = true
        rootStack.addArrangedSubview(loadingWrap)

        loadingSpinner.startAnimating()
        loadingLabel.text = L(L10n.ClanInviteSheet.loadingInviteLink)
        loadingLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorInset = .zero
        tableView.separatorColor = UIColor.theme.textDisabled.withAlphaComponent(0.45)
        tableView.layoutMargins = .zero
        tableView.separatorStyle = .singleLine
        tableView.backgroundColor = .clear
        tableView.layer.cornerRadius = 10.swh
        tableView.showsVerticalScrollIndicator = false
        tableView.register(ClanInviteFriendCell.self, forCellReuseIdentifier: ClanInviteFriendCell.id)
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.backgroundColor = UIColor.theme.secondary
        listContainer.layer.cornerRadius = 10.swh
        listContainer.clipsToBounds = true
        rootStack.addArrangedSubview(listContainer)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(tableView)
        setupEmptyStateUI()

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerWrap.heightAnchor.constraint(equalToConstant: 60.sh),
            titleLabel.leadingAnchor.constraint(equalTo: headerWrap.leadingAnchor, constant: 16.sw),
            titleLabel.trailingAnchor.constraint(equalTo: headerWrap.trailingAnchor, constant: -16.sw),
            titleLabel.topAnchor.constraint(equalTo: headerWrap.topAnchor, constant: 20.sh),

            actionRow.leadingAnchor.constraint(equalTo: actionWrap.leadingAnchor, constant: 8.sw),
            actionRow.trailingAnchor.constraint(equalTo: actionWrap.trailingAnchor, constant: -16.sw),
            actionRow.topAnchor.constraint(equalTo: actionWrap.topAnchor, constant: 16.sh),
            actionRow.heightAnchor.constraint(equalToConstant: 62.sh),
            actionBottomDivider.leadingAnchor.constraint(equalTo: actionWrap.leadingAnchor),
            actionBottomDivider.trailingAnchor.constraint(equalTo: actionWrap.trailingAnchor),
            actionBottomDivider.bottomAnchor.constraint(equalTo: actionWrap.bottomAnchor),
            actionBottomDivider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            actionWrap.heightAnchor.constraint(equalToConstant: 94.sh),

            listContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: 16.sw),
            listContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -16.sw),
            tableView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),

            searchOuter.heightAnchor.constraint(equalToConstant: 62.sh),
            searchWrap.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            searchWrap.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            searchWrap.topAnchor.constraint(equalTo: searchOuter.topAnchor, constant: 16.sh),
            searchWrap.heightAnchor.constraint(equalToConstant: 40.sh),

            loadingWrap.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: 16.sw),
            loadingWrap.trailingAnchor.constraint(lessThanOrEqualTo: rootStack.trailingAnchor, constant: -16.sw),
        ])

        rootStack.setCustomSpacing(10.sh, after: listContainer)
    }

    private func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        actionBottomDivider.backgroundColor = UIColor.theme.border.withAlphaComponent(0.6)
        searchField.textColor = UIColor.theme.textStrong
        searchField.tintColor = UIColor.theme.textDisabled
        searchClearButton.tintColor = UIColor.theme.textStrong
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanInviteSheet.searchPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        loadingSpinner.color = UIColor.theme.textDisabled
        loadingLabel.textColor = UIColor.theme.textDisabled
        emptyTitleLabel.textColor = UIColor.theme.textStrong
        emptyDescriptionLabel.textColor = UIColor.theme.textDisabled
        emptyActionButton.setTitleColor(UIColor.theme.textLink, for: .normal)
        tableView.reloadData()
    }

    private func loadData() {
        Task { @MainActor in
            guard let token = await context.getToken() else {
                self.showSimpleAlert(message: L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            inviteLink = await resolveInviteLink(token: token)

            do {
                async let friendsTask = context.account.network.listFriends(
                    token: token,
                    limit: 100,
                    state: Int32(Mezon_Api_Friend.State.friend.rawValue)
                )
                async let directsTask = context.account.network.listDirectMessageChannels(token: token)
                let friends = try await friendsTask
                let directs = try await directsTask

                let memberIds = Set(context.account.postbox.read { tx in
                    tx.getClanMembers(clanId: self.clanId).map { $0.userId }
                })
                cacheDirectChannels(directs)

                let currentUserId = Int64(context.currentUser?.id ?? "") ?? 0
                var merged = [String: FriendItem]()

                for friend in friends.friends {
                    guard friend.state == Mezon_Api_Friend.State.friend.rawValue else { continue }
                    guard friend.hasUser else { continue }
                    let u = friend.user
                    let uid = u.id
                    guard uid != 0, uid != currentUserId, !memberIds.contains(uid) else { continue }
                    let name = !u.displayName.isEmpty ? u.displayName : (u.username.isEmpty ? "Unknown" : u.username)
                    let avatar = u.avatarURL.isEmpty ? nil : u.avatarURL
                    merged["user_\(uid)"] = FriendItem(
                        id: uid,
                        name: name,
                        avatarURL: avatar,
                        isGroupDM: false,
                        target: .friend(userId: uid)
                    )
                }

                for dm in directs {
                    let isDM = dm.type == MezonConstants.ChannelType.dm.rawValue
                    let isGroup = dm.type == MezonConstants.ChannelType.group.rawValue
                    guard isDM || isGroup else { continue }

                    if isDM {
                        guard let uid = dm.userIds.first else { continue }
                        guard uid != 0, uid != currentUserId, !memberIds.contains(uid) else { continue }
                        guard dm.channelID != 0 else { continue }
                        let name = !dm.channelLabel.isEmpty
                            ? dm.channelLabel
                            : (dm.displayNames.first(where: { !$0.isEmpty })
                                ?? dm.usernames.first(where: { !$0.isEmpty })
                                ?? "Unknown")
                        let avatar = dm.avatars.first(where: { !$0.isEmpty })
                        merged["user_\(uid)"] = FriendItem(
                            id: dm.channelID,
                            name: name,
                            avatarURL: avatar,
                            isGroupDM: false,
                            target: .direct(channelId: dm.channelID, type: dm.type, isPublic: dm.channelPrivate == 0)
                        )
                    } else if isGroup {
                        guard dm.channelID != 0 else { continue }
                        let name = !dm.channelLabel.isEmpty ? dm.channelLabel : "\(dm.creatorName)'s Group"
                        let hasCustomGroupAvatar = !dm.channelAvatar.isEmpty && !dm.channelAvatar.contains("avatar-group.png")
                        let avatar = hasCustomGroupAvatar ? dm.channelAvatar : nil
                        merged["group_\(dm.channelID)"] = FriendItem(
                            id: dm.channelID,
                            name: name,
                            avatarURL: avatar,
                            isGroupDM: true,
                            target: .direct(channelId: dm.channelID, type: dm.type, isPublic: dm.channelPrivate == 0)
                        )
                    }
                }

                self.allFriends = merged.values.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.applyFilter()
                self.loadingSpinner.stopAnimating()
            } catch {
                self.loadingSpinner.stopAnimating()
                self.filteredFriends = []
                self.updateEmptyStateVisibility()
                self.tableView.reloadData()
                AppLogger.network.warning("[ClanInviteSheet] load friend list failed: \(error)")
            }
        }
    }

    private func resolveInviteLink(token: String) async -> String? {
        let inviteChannelId = await resolveInviteChannelId(token: token)
        guard inviteChannelId != 0 else {
            AppLogger.network.warning("[ClanInviteSheet] missing welcome channel id for clan=\(clanId)")
            return nil
        }

        do {
            let invite = try await context.account.network.linkInviteUser(
                clanId: clanId,
                channelId: inviteChannelId,
                expiryTime: 10,
                token: token
            )
            return "\(MezonConfig.chatWebAppBaseURL)/invite/\(invite.inviteLink)"
        } catch {
            AppLogger.network.warning("[ClanInviteSheet] create invite link failed: \(error)")
        }
        return nil
    }

    private func resolveInviteChannelId(token: String) async -> Int64 {
        do {
            let clans = try await context.account.network.listClanDescs(token: token)
            if let clan = clans.first(where: { $0.clanID == clanId }) {
                return clan.welcomeChannelID
            }
        } catch {
            AppLogger.network.warning("[ClanInviteSheet] listClanDescs failed: \(error)")
        }
        return 0
    }

    private func applyFilter() {
        let keyword = (searchField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if keyword.isEmpty {
            filteredFriends = allFriends
        } else {
            filteredFriends = allFriends.filter {
                $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(keyword)
            }
        }
        updateEmptyStateVisibility()
        tableView.reloadData()
    }

    private func setupEmptyStateUI() {
        emptyStateView.axis = .vertical
        emptyStateView.alignment = .center
        emptyStateView.spacing = 10.sh
        emptyStateView.isHidden = true
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(emptyStateView)

        emptyImageView.image = UIImage(named: "Invite/EmptyFriendIcon", in: .main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)

        emptyImageView.contentMode = .scaleAspectFit
        emptyImageView.translatesAutoresizingMaskIntoConstraints = false

        emptyTitleLabel.text = L(L10n.ClanInviteSheet.emptyTitle)
        emptyTitleLabel.font = .systemFont(ofSize: 30.sf * 0.6, weight: .bold)
        emptyTitleLabel.textAlignment = .center
        emptyTitleLabel.numberOfLines = 2

        emptyDescriptionLabel.text = L(L10n.ClanInviteSheet.emptyDescription)
        emptyDescriptionLabel.font = .systemFont(ofSize: 24.sf * 0.6, weight: .regular)
        emptyDescriptionLabel.textAlignment = .center
        emptyDescriptionLabel.numberOfLines = 0

        emptyActionButton.setTitle(L(L10n.ClanInviteSheet.emptyAction), for: .normal)
        emptyActionButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        emptyActionButton.addTarget(self, action: #selector(emptyActionTapped), for: .touchUpInside)

        emptyStateView.addArrangedSubview(emptyImageView)
        emptyStateView.addArrangedSubview(emptyTitleLabel)
        emptyStateView.addArrangedSubview(emptyDescriptionLabel)
        emptyStateView.setCustomSpacing(14.sh, after: emptyDescriptionLabel)
        emptyStateView.addArrangedSubview(emptyActionButton)

        NSLayoutConstraint.activate([
            emptyStateView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: 24.sw),
            emptyStateView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -24.sw),
            emptyStateView.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            emptyImageView.widthAnchor.constraint(equalToConstant: 96.swh),
            emptyImageView.heightAnchor.constraint(equalToConstant: 96.swh),
        ])
    }

    private func updateEmptyStateVisibility() {
        let isEmpty = filteredFriends.isEmpty
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        loadingLabel.text = nil
    }

    private func makeActionButton(iconAsset: String, fallbackSystemIcon: String, title: String, action: Selector) -> UIView {
        let container = UIView()

        let iconWrap = UIView()
        iconWrap.backgroundColor = UIColor.theme.secondary
        iconWrap.layer.cornerRadius = 20.swh
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconWrap)

        let iconImage = UIImage(named: iconAsset)?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: fallbackSystemIcon)?.withRenderingMode(.alwaysTemplate)
        let iconView = UIImageView(image: iconImage)
        iconView.tintColor = UIColor.theme.textStrong
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(iconView)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16.sf * 0.75, weight: .regular)
        label.textColor = UIColor.theme.text
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let button = UIButton(type: .custom)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        NSLayoutConstraint.activate([
            iconWrap.topAnchor.constraint(equalTo: container.topAnchor),
            iconWrap.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 40.swh),
            iconWrap.heightAnchor.constraint(equalToConstant: 40.swh),
            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24.swh),
            iconView.heightAnchor.constraint(equalToConstant: 24.swh),
            label.topAnchor.constraint(equalTo: iconWrap.bottomAnchor, constant: 6.sh),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func inviteUser(_ item: FriendItem) {
        guard !sentIds.contains(item.id), !sendingIds.contains(item.id) else { return }
        sendingIds.insert(item.id)
        tableView.reloadData()

        Task { @MainActor in
            defer {
                self.sendingIds.remove(item.id)
                self.tableView.reloadData()
            }
            do {
                guard let token = await context.getToken() else { throw NSError(domain: "session", code: -1) }
                let resolvedInviteLink: String
                if let existing = inviteLink {
                    resolvedInviteLink = existing
                } else if let generated = await resolveInviteLink(token: token) {
                    inviteLink = generated
                    resolvedInviteLink = generated
                } else {
                    showSimpleAlert(message: L(L10n.ClanInviteSheet.cannotCreateInvite))
                    return
                }

                let dm: Mezon_Api_ChannelDescription
                let isPublic: Bool
                switch item.target {
                case .friend(let userId):
                    dm = try await resolveDirectChannel(for: userId, token: token)
                    isPublic = dm.channelPrivate == 0
                case .direct(let channelId, _, let channelIsPublic):
                    var directChannel = Mezon_Api_ChannelDescription()
                    directChannel.channelID = channelId
                    dm = directChannel
                    isPublic = channelIsPublic
                }

                let payload = try await buildInviteMessagePayload(url: resolvedInviteLink, token: token)
                let contentData = try JSONSerialization.data(withJSONObject: payload)
                let content = String(data: contentData, encoding: .utf8) ?? "{}"
                _ = try await context.account.network.sendChannelMessage(
                    clanId: 0,
                    channelId: dm.channelID,
                    mode: MezonConstants.ChannelStreamMode.dm.rawValue,
                    isPublic: isPublic,
                    content: content,
                    token: token
                )
                self.sentIds.insert(item.id)
            } catch {
                AppLogger.network.warning("[ClanInviteSheet] inviteUser failed: \(error)")
                self.showSimpleAlert(message: String(format: L(L10n.ClanInviteSheet.cannotSendInvite), item.name))
            }
        }
    }

    private func buildInviteMessagePayload(url: String, token: String) async throws -> [String: Any] {
        let linkLength = url.count
        var mk: [[String: Any]] = [
            ["s": 0, "e": linkLength, "type": "lk"]
        ]
        var payload: [String: Any] = ["t": url]

        if let inviteId = extractInviteId(from: url), !inviteId.isEmpty {
            do {
                let inviteInfo = try await context.account.network.getInviteInfo(code: inviteId, token: token)
                let memberCount = inviteInfo.member_count ?? 0
                let title = inviteInfo.clan_name ?? L(L10n.ClanInviteSheet.unknownClan)
                let description = L(L10n.ClanAction.memberCount, memberCount)
                let image = inviteInfo.clan_logo ?? ""

                mk.append([
                    "type": "lk_ogp",
                    "s": linkLength,
                    "e": linkLength + 1,
                    "index": 0,
                    "title": title,
                    "description": description,
                    "image": image
                ])
            } catch {
                AppLogger.network.warning("[ClanInviteSheet] getInviteInfo failed: \(error)")
            }
        }

        payload["mk"] = mk
        return payload
    }

    private func extractInviteId(from url: String) -> String? {
        guard let regex = Self.inviteIdRegex else {
            return nil
        }
        let ns = url as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: url, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private func cacheDirectChannels(_ directs: [Mezon_Api_ChannelDescription]) {
        var map: [Int64: Mezon_Api_ChannelDescription] = [:]
        for channel in directs where
            channel.type == MezonConstants.ChannelType.dm.rawValue &&
            channel.userIds.count == 1 &&
            channel.userIds[0] != 0 {
            map[channel.userIds[0]] = channel
        }
        dmChannelsByUserId = map
    }

    private func resolveDirectChannel(for userId: Int64, token: String) async throws -> Mezon_Api_ChannelDescription {
        if let cached = dmChannelsByUserId[userId] {
            return cached
        }

        let dmChannels = try await context.account.network.listDirectMessageChannels(token: token)
        cacheDirectChannels(dmChannels)
        if let existing = dmChannelsByUserId[userId] {
            return existing
        }

        let created = try await context.account.network.createDirectMessage(userId: userId, token: token)
        if created.userIds.count == 1, let peerId = created.userIds.first, peerId != 0 {
            dmChannelsByUserId[peerId] = created
        } else {
            dmChannelsByUserId[userId] = created
        }
        return created
    }

    @objc private func searchChanged() {
        searchClearButton.isHidden = (searchField.text ?? "").isEmpty
        applyFilter()
    }

    @objc private func clearSearchTapped() {
        searchField.text = ""
        searchClearButton.isHidden = true
        applyFilter()
    }

    @objc private func copyInvite() {
        guard let inviteLink else { return }
        UIPasteboard.general.string = inviteLink
        Toast.success(L(L10n.ClanInviteSheet.linkCopied))
    }

    @objc private func shareInvite() {
        guard let inviteLink else { return }
        let ac = UIActivityViewController(activityItems: [inviteLink], applicationActivities: nil)
        present(ac, animated: true)
    }

    @objc private func showQR() {
        guard let inviteLink else { return }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(inviteLink.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return }
        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let image = UIImage(ciImage: output.transformed(by: transform))
        let ac = UIActivityViewController(activityItems: [image, inviteLink], applicationActivities: nil)
        present(ac, animated: true)
    }

    @objc private func emptyActionTapped() {
        Toast.info(L(L10n.ClanInviteSheet.emptyAction))
    }

    private func showSimpleAlert(message: String) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
    }
}

extension ClanInviteSheetViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredFriends.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        60.sh
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ClanInviteFriendCell.id,
            for: indexPath
        ) as? ClanInviteFriendCell else {
            return UITableViewCell()
        }
        let item = filteredFriends[indexPath.row]
        cell.configure(
            name: item.name,
            avatarURL: item.avatarURL,
            isGroupDM: item.isGroupDM,
            isSent: sentIds.contains(item.id),
            isLoading: sendingIds.contains(item.id)
        )
        cell.onInvite = { [weak self] in
            self?.inviteUser(item)
        }
        return cell
    }
}

private final class ClanInviteFriendCell: UITableViewCell {
    static let id = "ClanInviteFriendCell"

    var onInvite: (() -> Void)?

    private let avatarView = UIImageView()
    private let groupIconView = UIImageView()
    private let nameLabel = UILabel()
    private let inviteButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var representedAvatarURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        separatorInset = .zero
        layoutMargins = .zero
        preservesSuperviewLayoutMargins = false

        avatarView.layer.cornerRadius = 20.swh
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = UIColor.theme.border
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        groupIconView.image = UIImage(systemName: "person.2.fill")
        groupIconView.tintColor = .white
        groupIconView.contentMode = .scaleAspectFit
        groupIconView.isHidden = true
        groupIconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(groupIconView)

        nameLabel.font = .systemFont(ofSize: 15.sf, weight: .regular)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        inviteButton.layer.cornerRadius = 16.swh
        inviteButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)
        inviteButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inviteButton)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20.sw),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 40.swh),
            groupIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 20.swh),
            groupIconView.heightAnchor.constraint(equalToConstant: 20.swh),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10.sw),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 5.sh),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: inviteButton.leadingAnchor, constant: -10.sw),
            inviteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20.sw),
            inviteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            inviteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60.sw),
            inviteButton.heightAnchor.constraint(equalToConstant: 32.sh),
            spinner.centerYAnchor.constraint(equalTo: inviteButton.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: inviteButton.centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(name: String, avatarURL: String?, isGroupDM: Bool, isSent: Bool, isLoading: Bool) {
        nameLabel.text = name
        representedAvatarURL = avatarURL
        let title = isSent ? L(L10n.ClanInviteSheet.invited) : L(L10n.ClanInviteSheet.invite)
        inviteButton.setTitle(title, for: .normal)
        inviteButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        inviteButton.backgroundColor = UIColor.theme.tertiary
        inviteButton.contentEdgeInsets = UIEdgeInsets(top: 6.sh, left: 12.sw, bottom: 6.sh, right: 12.sw)
        inviteButton.layer.borderWidth = 1 / UIScreen.main.scale
        inviteButton.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.8).cgColor
        inviteButton.isEnabled = !isSent && !isLoading
        contentView.alpha = isSent ? 0.6 : 1.0

        if isLoading {
            inviteButton.setTitle(nil, for: .normal)
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
            inviteButton.setTitle(title, for: .normal)
        }

        avatarView.image = nil
        groupIconView.isHidden = true
        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
        if let avatarURL, !avatarURL.isEmpty {
            let px = Int(40.swh * UIScreen.main.scale)
            let proxied = ImgproxyURL.create(from: avatarURL, width: px, height: px)
            if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
                avatarView.image = cached
            } else {
                ImageCache.shared.loadAvatar(urlString: proxied) { [weak self] image in
                    guard let self, let image else { return }
                    DispatchQueue.main.async {
                        guard self.representedAvatarURL == avatarURL else { return }
                        self.avatarView.image = image
                    }
                }
            }
        } else {
            if isGroupDM {
                avatarView.backgroundColor = UIColor(
                    red: 0.96,
                    green: 0.55,
                    blue: 0.16,
                    alpha: 1
                )
                groupIconView.isHidden = false
            } else {
                avatarView.backgroundColor = UIColor.theme.border
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40.swh, height: 40.swh))
                avatarView.image = renderer.image { _ in
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                        .foregroundColor: UIColor.theme.textDisabled
                    ]
                    let textSize = initial.size(withAttributes: attrs)
                    let point = CGPoint(x: (40.swh - textSize.width) / 2, y: (40.swh - textSize.height) / 2)
                    initial.draw(at: point, withAttributes: attrs)
                }
            }
        }
    }

    @objc private func inviteTapped() {
        onInvite?()
    }
}

