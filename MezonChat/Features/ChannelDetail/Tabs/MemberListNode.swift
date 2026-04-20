import AsyncDisplayKit
import UIKit

@MainActor
final class MemberListNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private let dmMemberLabelByUserId: [Int64: String]
    private let useClanListWhenChannelUsersEmpty: Bool
    private let tableNode = ASTableNode()

    private enum MemberListItem {
        case channel(ChannelMemberRecord)
        case clan(ClanMemberRecord)
    }

    private enum MemberData {
        case channel([ChannelMemberRecord])
        case clan([ClanMemberRecord])

        var count: Int {
            switch self {
            case .channel(let members): return members.count
            case .clan(let members): return members.count
            }
        }
    }

    private var onlineMembers: MemberData = .channel([])
    private var offlineMembers: MemberData = .channel([])
    private var roles: [Int64: String] = [:]
    private var ownerId: String?
    private let disposables = DisposableSet()
    private var didStartMemberLoading = false

    init(
        context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32,
        channelDescription: Mezon_Api_ChannelDescription
    ) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType
        self.dmMemberLabelByUserId = Self.dmMemberLabels(from: channelDescription)
        let dm = MezonConstants.ChannelType.dm.rawValue
        let group = MezonConstants.ChannelType.group.rawValue
        self.useClanListWhenChannelUsersEmpty =
            clanId > 0
            && channelDescription.channelPrivate == 0
            && channelDescription.type != dm
            && channelDescription.type != group
        super.init()
        self.automaticallyManagesSubnodes = true

        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.allowsSelection = true
    }

    func loadTabDataIfNeeded() {
        guard !didStartMemberLoading else { return }
        didStartMemberLoading = true
        loadClanData()
        observeMembers()
        fetchMembersIfNeeded()
    }

    private static func dmMemberLabels(from channel: Mezon_Api_ChannelDescription) -> [Int64: String] {
        let dm = MezonConstants.ChannelType.dm.rawValue
        let group = MezonConstants.ChannelType.group.rawValue
        guard channel.type == dm || channel.type == group else { return [:] }

        var result: [Int64: String] = [:]
        let ids = channel.userIds
        let displayNames = channel.displayNames
        let usernames = channel.usernames
        for i in ids.indices {
            let id = ids[i]
            let dn = i < displayNames.count ? displayNames[i] : ""
            let un = i < usernames.count ? usernames[i] : ""
            let label = !dn.isEmpty ? dn : un
            if !label.isEmpty {
                result[id] = label
            }
        }
        return result
    }

    private func resolvedChannelMemberListName(_ record: ChannelMemberRecord) -> String {
        if !record.clanNick.isEmpty { return record.clanNick }
        if !record.displayName.isEmpty { return record.displayName }
        if !record.username.isEmpty { return record.username }
        if let fb = dmMemberLabelByUserId[record.userId], !fb.isEmpty { return fb }
        return ""
    }

    private func loadClanData() {
        guard clanId > 0 else { return }
        context.account.postbox.read { tx in
            let clan = tx.getClan(id: clanId)
            self.ownerId = clan?.ownerId

            if let data = tx.getSetting(key: PreferencesKeys.clanRoles(clanId: clanId)) {
                if let roleList = try? Mezon_Api_RoleList(serializedBytes: data) {
                    var roleMap: [Int64: String] = [:]
                    for role in roleList.roles {
                        if !role.color.isEmpty {
                            roleMap[role.id] = role.color
                        }
                    }
                    self.roles = roleMap
                }
            }
        }
    }

    private func fetchMembersIfNeeded() {
        Task {
            guard channelId > 0 else { return }
            let token = await context.getToken() ?? ""
            do {
                let res = try await context.account.network.listChannelUsers(
                    clanId: clanId,
                    channelId: channelId,
                    channelType: channelType,
                    token: token
                )
                if res.channelUsers.isEmpty, useClanListWhenChannelUsersEmpty {
                    try await applyClanMembersFallback(token: token)
                    return
                }
                applyChannelUserList(res.channelUsers)
            } catch {
                if useClanListWhenChannelUsersEmpty {
                    try? await applyClanMembersFallback(token: token)
                }
            }
        }
    }

    private func applyChannelUserList(_ channelUsers: [Mezon_Api_ChannelUserList.ChannelUser]) {
        if channelUsers.isEmpty {
            let hasCached = !(context.account.postbox.read { tx in
                tx.getChannelMeta(channelId: self.channelId)?.members ?? []
            }).isEmpty
            if hasCached { return }
        }
        context.account.postbox.write { tx in
            for u in channelUsers {
                let merged = self.mergedProfile(
                    tx: tx,
                    channelUser: u,
                    dmLabel: self.dmMemberLabelByUserId[u.userID]
                )
                tx.updateProfile(merged)
            }
            let members = channelUsers.map { u in
                let uid = String(u.userID)
                let profile = tx.getProfile(userId: uid)
                var displayName = profile?.displayName ?? ""
                var username = profile?.username ?? ""
                if displayName.isEmpty, username.isEmpty,
                    let fb = self.dmMemberLabelByUserId[u.userID], !fb.isEmpty
                {
                    displayName = fb
                }
                return ChannelMemberRecord(
                    id: u.id, userId: u.userID, roleIds: u.roleID,
                    threadId: u.threadID, clanNick: u.clanNick,
                    clanAvatar: u.clanAvatar, clanId: u.clanID,
                    isBanned: u.isBanned, expiredBanTime: u.expiredBanTime,
                    isOnline: profile?.isOnline ?? false,
                    displayName: displayName,
                    username: username
                )
            }
            tx.updateChannelMembers(members, channelId: self.channelId)
        }
    }

    private func applyClanMembersFallback(token: String) async throws {
        let clanRes = try await context.account.network.listClanUsers(clanId: clanId, token: token)
        if clanRes.clanUsers.isEmpty {
            let hasCached = !context.account.postbox.read({ tx in
                tx.getClanMembers(clanId: self.clanId)
            }).isEmpty
            if hasCached { return }
        }
        context.account.postbox.write { tx in
            let clanMembers = clanRes.clanUsers.map { ClanMemberRecord(from: $0) }
            tx.updateClanMembers(clanMembers, clanId: self.clanId)
            for u in clanRes.clanUsers {
                tx.updateProfile(ProfileRecord(from: u))
            }
            let members = clanRes.clanUsers.map { ChannelMemberRecord(from: $0) }
            tx.updateChannelMembers(members, channelId: self.channelId)
        }
    }

    private func mergedProfile(
        tx: PostboxTransaction,
        channelUser u: Mezon_Api_ChannelUserList.ChannelUser,
        dmLabel: String?
    ) -> ProfileRecord {
        let uid = String(u.userID)
        let existing = tx.getProfile(userId: uid)
        let trimmedAvatar = u.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        let nick = u.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)

        let avatarUrl: String?
        if !trimmedAvatar.isEmpty {
            avatarUrl = trimmedAvatar
        } else if let a = existing?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
            !a.isEmpty
        {
            avatarUrl = a
        } else {
            avatarUrl = nil
        }

        let displayName: String?
        if !nick.isEmpty {
            displayName = nick
        } else if let e = existing?.displayName, !e.isEmpty {
            displayName = e
        } else if let fb = dmLabel, !fb.isEmpty {
            displayName = fb
        } else {
            displayName = existing?.displayName
        }

        let username: String
        if let e = existing, !e.username.isEmpty {
            username = e.username
        } else if !nick.isEmpty {
            username = nick
        } else if let fb = dmLabel, !fb.isEmpty {
            username = fb
        } else {
            username = ""
        }

        return ProfileRecord(
            userId: uid,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            status: existing?.status ?? 0,
            isOnline: existing?.isOnline ?? false
        )
    }

    private func observeMembers() {
        guard channelId > 0 else { return }
        let isDMOrGroup =
            channelType == MezonConstants.ChannelType.dm.rawValue
            || channelType == MezonConstants.ChannelType.group.rawValue
        let signal =
            context.account.postbox.channelMetaView(channelId: channelId)
            |> map { $0.record?.members ?? [] }
        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] members in
                guard let self else { return }
                if isDMOrGroup {
                    let sorted = members.sorted {
                        self.getName(member: .channel($0)) < self.getName(member: .channel($1))
                    }
                    self.onlineMembers = .channel(sorted)
                    self.offlineMembers = .channel([])
                } else {
                    let online = members.filter { $0.isOnline }.sorted {
                        self.getName(member: .channel($0)) < self.getName(member: .channel($1))
                    }
                    let offline = members.filter { !$0.isOnline }.sorted {
                        self.getName(member: .channel($0)) < self.getName(member: .channel($1))
                    }
                    self.onlineMembers = .channel(online)
                    self.offlineMembers = .channel(offline)
                }
                self.tableNode.reloadData()
            }))
    }

    private func getName(member: MemberListItem) -> String {
        let name: String
        switch member {
        case .channel(let record):
            name = resolvedChannelMemberListName(record)
        case .clan(let record):
            name =
                !record.clanNick.isEmpty
                ? record.clanNick
                : !record.displayName.isEmpty
                    ? record.displayName
                    : record.username
        }
        return name.lowercased()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        tableNode.style.flexGrow = 1
        return ASWrapperLayoutSpec(layoutElement: tableNode)
    }

    deinit {
        disposables.dispose()
    }
}

fileprivate func memberListResolvedAvatarURL(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return "" }
    if let u = URL(string: t), u.scheme != nil { return t }
    if t.hasPrefix("//") { return "https:\(t)" }
    let base = MezonConfig.baseImgURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if t.hasPrefix("/") { return "\(base)\(t)" }
    return "\(base)/\(t)"
}

extension MemberListNode: ASTableDataSource, ASTableDelegate {
    func numberOfSections(in tableNode: ASTableNode) -> Int {
        return 3
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        if section == 1 { return onlineMembers.count }
        return offlineMembers.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        if indexPath.section == 0 {
            let type = self.channelType
            return {
                var title = L(L10n.ChannelDetail.inviteMembers)
                var icon = "person.badge.plus.fill"

                if type == MezonConstants.ChannelType.dm.rawValue {
                    title = L(L10n.ChannelDetail.newGroup)
                    icon = "person.2.fill"
                } else if type == MezonConstants.ChannelType.group.rawValue {
                    title = L(L10n.ChannelDetail.addMembers)
                    icon = "person.badge.plus.fill"
                }

                return ActionButtonCellNode(title: title, iconName: icon)
            }
        }

        let context = self.context
        if indexPath.section == 1 {
            switch onlineMembers {
            case .channel(let members):
                let member = members[indexPath.row]
                let color = getRoleColor(roleIds: member.roleIds)
                let isOwner = String(member.userId) == ownerId
                return {
                    let initialName = self.resolvedChannelMemberListName(member)
                    return MemberCellNode(
                        context: context, userId: member.userId, displayName: initialName,
                        avatarUrl: member.clanAvatar, clanNick: member.clanNick,
                        clanAvatar: member.clanAvatar, roleColor: color, isOwner: isOwner)
                }
            case .clan(let members):
                let member = members[indexPath.row]
                let color = getRoleColor(roleIds: member.roleIds)
                let isOwner = String(member.userId) == ownerId
                return {
                    let initialName =
                        !member.clanNick.isEmpty
                        ? member.clanNick
                        : !member.displayName.isEmpty ? member.displayName : member.username
                    return MemberCellNode(
                        context: context, userId: member.userId, displayName: initialName,
                        avatarUrl: member.clanAvatar, clanNick: member.clanNick,
                        clanAvatar: member.clanAvatar, roleColor: color, isOwner: isOwner)
                }
            }
        } else {
            switch offlineMembers {
            case .channel(let members):
                let member = members[indexPath.row]
                let isOwner = String(member.userId) == ownerId
                return {
                    let initialName = self.resolvedChannelMemberListName(member)
                    return MemberCellNode(
                        context: context, userId: member.userId, displayName: initialName,
                        avatarUrl: member.clanAvatar, clanNick: member.clanNick,
                        clanAvatar: member.clanAvatar, roleColor: nil, isOwner: isOwner)
                }
            case .clan(let members):
                let member = members[indexPath.row]
                let isOwner = String(member.userId) == ownerId
                return {
                    let initialName =
                        !member.clanNick.isEmpty
                        ? member.clanNick
                        : !member.displayName.isEmpty ? member.displayName : member.username
                    return MemberCellNode(
                        context: context, userId: member.userId, displayName: initialName,
                        avatarUrl: member.clanAvatar, clanNick: member.clanNick,
                        clanAvatar: member.clanAvatar, roleColor: nil, isOwner: isOwner)
                }
            }
        }
    }

    private func getRoleColor(roleIds: [Int64]) -> UIColor? {
        for rid in roleIds {
            if let hex = roles[rid] {
                return UIColor(hexString: hex)
            }
        }
        return nil
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        guard indexPath.section != 0 else { return }

        let user: Mezon_Api_User?
        switch indexPath.section {
        case 1:
            switch onlineMembers {
            case .channel(let members):
                guard indexPath.row < members.count else { return }
                user = Self.apiUser(from: members[indexPath.row])
            case .clan(let members):
                guard indexPath.row < members.count else { return }
                user = Self.apiUser(from: members[indexPath.row])
            }
        case 2:
            switch offlineMembers {
            case .channel(let members):
                guard indexPath.row < members.count else { return }
                user = Self.apiUser(from: members[indexPath.row])
            case .clan(let members):
                guard indexPath.row < members.count else { return }
                user = Self.apiUser(from: members[indexPath.row])
            }
        default:
            user = nil
        }

        guard let user, user.id != 0 else { return }
        let isCurrentUser = String(user.id) == context.currentUser?.id

        guard let host = tableNode.view.findHostingViewController() else { return }

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            isCurrentUser: isCurrentUser,
            onSendMessage: { [weak self, weak host] dmChannel in
                guard let self, let host else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                host.navigationController?.pushViewController(chatVC, animated: true)
            }
        )
        host.presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private static func apiUser(from member: ChannelMemberRecord) -> Mezon_Api_User {
        var u = Mezon_Api_User()
        u.id = member.userId
        u.username = member.username
        u.displayName = displayName(for: member)
        if !member.clanAvatar.isEmpty {
            u.avatarURL = member.clanAvatar
        }
        u.online = member.isOnline
        return u
    }

    private static func apiUser(from member: ClanMemberRecord) -> Mezon_Api_User {
        var u = Mezon_Api_User()
        u.id = member.userId
        u.username = member.username
        u.displayName = displayName(for: member)
        if !member.clanAvatar.isEmpty {
            u.avatarURL = member.clanAvatar
        }
        u.online = member.isOnline
        return u
    }

    private static func displayName(for member: ChannelMemberRecord) -> String {
        if !member.clanNick.isEmpty { return member.clanNick }
        if !member.displayName.isEmpty { return member.displayName }
        return member.username
    }

    private static func displayName(for member: ClanMemberRecord) -> String {
        if !member.clanNick.isEmpty { return member.clanNick }
        if !member.displayName.isEmpty { return member.displayName }
        return member.username
    }

    func tableNode(_ tableNode: ASTableNode, nodeForHeaderInSection section: Int) -> ASCellNode? {
        if section == 0 { return nil }
        let isDMOrGroup =
            channelType == MezonConstants.ChannelType.dm.rawValue
            || channelType == MezonConstants.ChannelType.group.rawValue

        if isDMOrGroup {
            if section == 1 {
                return HeaderCellNode(
                    title: L(L10n.ChannelDetail.members), count: onlineMembers.count)
            }
            return nil
        }

        let count = section == 1 ? onlineMembers.count : offlineMembers.count
        let title = section == 1 ? L(L10n.ChannelDetail.online) : L(L10n.ChannelDetail.offline)

        if count == 0 { return nil }
        return HeaderCellNode(title: title, count: count)
    }

    func tableNode(_ tableNode: ASTableNode, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 { return 0 }
        let isDMOrGroup =
            channelType == MezonConstants.ChannelType.dm.rawValue
            || channelType == MezonConstants.ChannelType.group.rawValue

        if isDMOrGroup {
            return section == 1 && onlineMembers.count > 0 ? 30 : 0
        }

        let count = section == 1 ? onlineMembers.count : offlineMembers.count
        return count > 0 ? 30 : 0
    }
}

private final class ActionButtonCellNode: ASCellNode {
    private let contentBgNode = ASDisplayNode()
    private let iconBackgroundNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let arrowNode = ASImageNode()

    init(title: String, iconName: String) {
        super.init()
        self.automaticallyManagesSubnodes = true
        self.backgroundColor = .clear
        self.selectionStyle = .none

        let t = UIColor.theme
        contentBgNode.backgroundColor = t.secondary
        contentBgNode.cornerRadius = 16.sf

        let iconCircle: CGFloat = 40.sf
        iconBackgroundNode.backgroundColor = t.bgViolet
        iconBackgroundNode.cornerRadius = iconCircle / 2
        iconBackgroundNode.clipsToBounds = true
        iconBackgroundNode.style.preferredSize = CGSize(width: iconCircle, height: iconCircle)

        let config = UIImage.SymbolConfiguration(pointSize: 20.sf, weight: .semibold)
        iconNode.image = UIImage(systemName: iconName, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )

        arrowNode.image = UIImage(systemName: "chevron.right")?.withTintColor(
            t.text.withAlphaComponent(0.55), renderingMode: .alwaysOriginal)
        arrowNode.style.preferredSize = CGSize(width: 14.sf, height: 14.sf)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let iconCentered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: iconNode
        )
        let iconWithBackground = ASOverlayLayoutSpec(
            child: iconBackgroundNode,
            overlay: iconCentered
        )

        let leftStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [iconWithBackground, titleNode]
        )

        let mainStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 0,
            justifyContent: .spaceBetween,
            alignItems: .center,
            children: [leftStack, arrowNode]
        )

        let contentInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16), child: mainStack)

        let backgroundSpec = ASBackgroundLayoutSpec(child: contentInset, background: contentBgNode)

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4, left: 4.sw, bottom: 4, right: 4.sw),
            child: backgroundSpec)
    }
}

private final class MemberCellNode: ASCellNode {
    private let context: AccountContext
    private let userId: Int64
    private let initialDisplayName: String
    private let initialAvatarUrl: String
    private let clanNick: String
    private let clanAvatar: String

    private let avatarContainerNode = ASDisplayNode()
    private let avatarBackplate = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let avatarPlaceholderNode = ASTextNode2()
    private let nameNode = ASTextNode2()
    private let crownNode = ASTextNode2()
    private let statusNode = ASDisplayNode()
    private let separatorNode = ASDisplayNode()
    private let roleColor: UIColor?
    private let isOwner: Bool
    private let disposables = DisposableSet()

    init(
        context: AccountContext, userId: Int64, displayName: String, avatarUrl: String,
        clanNick: String, clanAvatar: String, roleColor: UIColor? = nil, isOwner: Bool = false
    ) {
        self.context = context
        self.userId = userId
        self.initialDisplayName = displayName
        self.initialAvatarUrl = avatarUrl
        self.clanNick = clanNick
        self.clanAvatar = clanAvatar
        self.roleColor = roleColor
        self.isOwner = isOwner
        super.init()
        self.automaticallyManagesSubnodes = true
        self.backgroundColor = .clear
        self.selectionStyle = .none

        avatarContainerNode.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)
        avatarContainerNode.cornerRadius = 20.sf
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.backgroundColor = .colorAvatarDefault
        avatarContainerNode.automaticallyManagesSubnodes = true

        avatarBackplate.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)
        avatarBackplate.backgroundColor = .clear

        avatarNode.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)
        avatarNode.cornerRadius = 20.sf
        avatarNode.clipsToBounds = true

        avatarPlaceholderNode.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)

        avatarContainerNode.addSubnode(avatarBackplate)
        avatarContainerNode.addSubnode(avatarNode)
        avatarContainerNode.addSubnode(avatarPlaceholderNode)
        avatarContainerNode.layoutSpecBlock = { [weak self] _, _ in
            guard let self else { return ASLayoutSpec() }
            let imageCentered = ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: .minimumXY,
                child: self.avatarNode
            )
            let initialsCentered = ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: .minimumXY,
                child: self.avatarPlaceholderNode
            )
            return ASOverlayLayoutSpec(
                child: self.avatarBackplate,
                overlay: ASOverlayLayoutSpec(
                    child: imageCentered,
                    overlay: initialsCentered
                )
            )
        }
        self.addSubnode(avatarContainerNode)
        self.addSubnode(nameNode)

        statusNode.style.preferredSize = CGSize(width: 12.sf, height: 12.sf)
        statusNode.cornerRadius = 6.sf
        statusNode.borderColor = UIColor.theme.secondary.cgColor
        statusNode.borderWidth = 2.sf
        self.addSubnode(statusNode)

        separatorNode.backgroundColor = UIColor.theme.borderDim
        self.addSubnode(separatorNode)

        if isOwner {
            crownNode.attributedText = NSAttributedString(
                string: "👑",
                attributes: [.font: UIFont.systemFont(ofSize: 14.sf)]
            )
            self.addSubnode(crownNode)
        }

        self.updateUI(displayName: displayName, avatarUrl: avatarUrl, isOnline: false, status: 0)

        Task { @MainActor in
            observeProfile()
        }
    }

    @MainActor private func observeProfile() {
        let signal: Signal<ProfileView, NoError> = context.account.postbox.profileView(
            userId: String(userId))
        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] view in
                guard let self, let profile = view.record else { return }
                let name: String
                if !self.clanNick.isEmpty {
                    name = self.clanNick
                } else if let dn = profile.displayName, !dn.isEmpty {
                    name = dn
                } else if !profile.username.isEmpty {
                    name = profile.username
                } else {
                    name = ""
                }

                self.updateUI(
                    displayName: name,
                    avatarUrl: profile.avatarUrl,
                    isOnline: profile.isOnline,
                    status: profile.status)
            }))
    }

    private func updateUI(displayName: String, avatarUrl: String?, isOnline: Bool, status: Int32) {
        var name = displayName
        if name.isEmpty {
            name = !initialDisplayName.isEmpty ? initialDisplayName : "User \(userId)"
        }

        let t = UIColor.theme
        var nameTextColor = t.textStrong
        if isOnline {
            if let roleColor = self.roleColor {
                nameTextColor = roleColor
            }
        } else {
            nameTextColor = t.text
        }

        nameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .regular),
                .foregroundColor: nameTextColor,
            ]
        )
        nameNode.style.flexShrink = 1.0
        nameNode.style.flexGrow = 1.0

        let rawAvatar: String = {
            if !clanAvatar.isEmpty { return clanAvatar }
            if let a = avatarUrl, !a.isEmpty { return a }
            return initialAvatarUrl
        }()
        let absolute = memberListResolvedAvatarURL(rawAvatar)
        if !absolute.isEmpty,
            let url = URL(string: ImgproxyURL.create(from: absolute, width: 100, height: 100))
        {
            avatarNode.url = url
            avatarNode.alpha = 1.0
            avatarPlaceholderNode.alpha = 0.0
        } else {
            avatarNode.url = nil
            avatarNode.alpha = 0.0
            avatarPlaceholderNode.alpha = 1.0
            let initial = String(name.prefix(1)).uppercased()
            let side = 40.sf
            let font = UIFont.systemFont(ofSize: 16.sf, weight: .semibold)
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.minimumLineHeight = side
            p.maximumLineHeight = side
            avatarPlaceholderNode.maximumNumberOfLines = 1
            avatarPlaceholderNode.attributedText = NSAttributedString(
                string: initial,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: p,
                ]
            )
        }

        if isOnline {
            statusNode.backgroundColor = UIColor(hexString: "#00d4aa")
        } else {
            switch status {
            case 1:
                statusNode.backgroundColor = UIColor(hexString: "#00d4aa")
            case 2:
                statusNode.backgroundColor = .systemYellow
            case 3:
                statusNode.backgroundColor = .systemRed
            default:
                statusNode.backgroundColor = .lightGray
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let avatarWithStatus = ASCornerLayoutSpec(
            child: avatarContainerNode, corner: statusNode, location: .bottomRight)
        avatarWithStatus.offset = CGPoint(x: -2.sf, y: -2.sf)

        var nameChildren: [ASLayoutElement] = [nameNode]
        if isOwner {
            nameChildren.append(crownNode)
        }

        let nameStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 4.sw,
            justifyContent: .start,
            alignItems: .center,
            children: nameChildren
        )
        nameStack.style.flexShrink = 1.0
        nameStack.style.flexGrow = 1.0

        let contentStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarWithStatus, nameStack]
        )

        let insetSpec = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16), child: contentStack)

        let separatorWidth = max(0, constrainedSize.max.width - 68.sw)
        separatorNode.style.preferredSize = CGSize(width: separatorWidth, height: 1)
        let separatorInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 68.sw, bottom: 0, right: 0),
            child: separatorNode
        )

        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [insetSpec, separatorInset]
        )
    }

    deinit {
        disposables.dispose()
    }
}

private final class HeaderCellNode: ASCellNode {
    private let textNode = ASTextNode2()

    init(title: String, count: Int) {
        super.init()
        self.automaticallyManagesSubnodes = true
        self.backgroundColor = .clear

        textNode.attributedText = NSAttributedString(
            string: "\(title) - \(count)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .medium),
                .foregroundColor: UIColor.theme.textDisabled,
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 16, left: 16, bottom: 8, right: 16),
            child: textNode
        )
    }
}

private extension UIView {
    func findHostingViewController() -> ViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? ViewController { return vc }
            responder = next
        }
        return nil
    }
}
