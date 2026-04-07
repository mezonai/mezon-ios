import AsyncDisplayKit
import UIKit

@MainActor
final class MemberListNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private let isPrivate: Bool
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

    init(
        context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32,
        isPrivate: Bool
    ) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType
        self.isPrivate = isPrivate
        super.init()
        self.automaticallyManagesSubnodes = true

        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.backgroundColor = .clear
        tableNode.view.separatorStyle = .none

        observeMembers()
        fetchMembersIfNeeded()
        loadClanData()
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
            do {
                let token = await context.getToken() ?? ""
                let isDMOrGroup =
                    channelType == MezonConstants.ChannelType.dm.rawValue
                    || channelType == MezonConstants.ChannelType.group.rawValue

                if clanId > 0 && !isPrivate && !isDMOrGroup {
                    let res = try await context.account.network.listClanUsers(
                        clanId: clanId, token: token)
                    context.account.postbox.write { tx in
                        let members = res.clanUsers.map { ClanMemberRecord(from: $0) }
                        tx.updateClanMembers(members, clanId: self.clanId)
                        for u in res.clanUsers {
                            tx.updateProfile(ProfileRecord(from: u))
                        }
                    }
                } else if channelId > 0 {
                    let res = try await context.account.network.listChannelUsers(
                        clanId: clanId,
                        channelId: channelId,
                        channelType: channelType,
                        token: token
                    )
                    context.account.postbox.write { tx in
                        let members = res.channelUsers.map { u in
                            let profile = tx.getProfile(userId: String(u.userID))
                            return ChannelMemberRecord(
                                id: u.id, userId: u.userID, roleIds: u.roleID,
                                threadId: u.threadID, clanNick: u.clanNick,
                                clanAvatar: u.clanAvatar, clanId: u.clanID,
                                isBanned: u.isBanned, expiredBanTime: u.expiredBanTime,
                                isOnline: profile?.isOnline ?? false,
                                displayName: profile?.displayName ?? "",
                                username: profile?.username ?? ""
                            )
                        }
                        tx.updateChannelMembers(members, channelId: self.channelId)
                    }
                }
            } catch {
                AppLogger.network.error("Fetch members failed")
            }
        }
    }

    private func observeMembers() {
        let isDMOrGroup =
            channelType == MezonConstants.ChannelType.dm.rawValue
            || channelType == MezonConstants.ChannelType.group.rawValue

        if clanId > 0 && !isPrivate && !isDMOrGroup {
            let signal =
                context.account.postbox.clanMemberView(clanId: clanId) |> map { $0.members }
            disposables.add(
                (signal |> deliverOnMainQueue).start(next: { [weak self] allMembers in
                    guard let self else { return }
                    let online = allMembers.filter { $0.isOnline }.sorted {
                        self.getName(member: .clan($0)) < self.getName(member: .clan($1))
                    }
                    let offline = allMembers.filter { !$0.isOnline }.sorted {
                        self.getName(member: .clan($0)) < self.getName(member: .clan($1))
                    }
                    self.onlineMembers = .clan(online)
                    self.offlineMembers = .clan(offline)
                    self.tableNode.reloadData()
                }))
        } else if channelId > 0 {
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
    }

    private func getName(member: MemberListItem) -> String {
        let name: String
        switch member {
        case .channel(let record):
            name =
                !record.clanNick.isEmpty
                ? record.clanNick
                : !record.displayName.isEmpty
                    ? record.displayName
                    : record.username
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
                    let initialName =
                        !member.clanNick.isEmpty
                        ? member.clanNick
                        : !member.displayName.isEmpty ? member.displayName : member.username
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
                    let initialName =
                        !member.clanNick.isEmpty
                        ? member.clanNick
                        : !member.displayName.isEmpty ? member.displayName : member.username
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

        contentBgNode.backgroundColor = .white
        contentBgNode.cornerRadius = 16.sf
        contentBgNode.shadowColor = UIColor.black.cgColor
        contentBgNode.shadowOffset = CGSize(width: 0, height: 2)
        contentBgNode.shadowRadius = 8
        contentBgNode.shadowOpacity = 0.05

        iconBackgroundNode.backgroundColor = UIColor.theme.textLink
        iconBackgroundNode.cornerRadius = 12.sf
        iconBackgroundNode.style.preferredSize = CGSize(width: 24.sf, height: 24.sf)

        let config = UIImage.SymbolConfiguration(pointSize: 14.sf, weight: .semibold)
        iconNode.image = UIImage(systemName: iconName, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        iconNode.style.preferredSize = CGSize(width: 18.sf, height: 18.sf)
        iconNode.contentMode = .scaleAspectFit

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )

        arrowNode.image = UIImage(systemName: "chevron.right")?.withTintColor(
            UIColor.theme.textDisabled, renderingMode: .alwaysOriginal)
        arrowNode.style.preferredSize = CGSize(width: 14.sf, height: 14.sf)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let iconCenter = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: iconNode
        )
        let iconWithBackground = ASBackgroundLayoutSpec(
            child: iconCenter, background: iconBackgroundNode)

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

        avatarContainerNode.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)
        avatarContainerNode.cornerRadius = 20.sf
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.backgroundColor = .colorAvatarDefault

        avatarNode.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)
        avatarNode.cornerRadius = 20.sf
        avatarNode.clipsToBounds = true

        avatarContainerNode.addSubnode(avatarPlaceholderNode)
        avatarContainerNode.addSubnode(avatarNode)
        self.addSubnode(avatarContainerNode)
        self.addSubnode(nameNode)

        statusNode.style.preferredSize = CGSize(width: 12.sf, height: 12.sf)
        statusNode.cornerRadius = 6.sf
        statusNode.borderColor = UIColor.theme.secondary.cgColor
        statusNode.borderWidth = 2.sf
        self.addSubnode(statusNode)

        separatorNode.backgroundColor = UIColor(hexString: "#E1E1E1")
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

        var nameTextColor = UIColor.theme.textStrong
        if isOnline {
            if let roleColor = self.roleColor {
                nameTextColor = roleColor
            }
        } else {
            nameTextColor = UIColor.theme.textDisabled
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

        if let urlString = !clanAvatar.isEmpty
            ? clanAvatar : (avatarUrl != nil && !avatarUrl!.isEmpty ? avatarUrl : initialAvatarUrl),
            !urlString.isEmpty, let url = URL(string: urlString)
        {
            avatarNode.isHidden = false
            avatarNode.url = url
            avatarPlaceholderNode.isHidden = true
        } else {
            avatarNode.isHidden = true
            avatarPlaceholderNode.isHidden = false
            avatarPlaceholderNode.attributedText = NSAttributedString(
                string: String(name.prefix(1)).uppercased(),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16.sf, weight: .semibold),
                    .foregroundColor: UIColor.white,
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
        let phSize = avatarPlaceholderNode.measure(CGSize(width: 40.sf, height: 40.sf))
        avatarPlaceholderNode.style.layoutPosition = CGPoint(
            x: (40.sf - phSize.width) / 2,
            y: (40.sf - phSize.height) / 2
        )
        avatarPlaceholderNode.style.preferredSize = phSize
        avatarNode.frame = CGRect(x: 0, y: 0, width: 40.sf, height: 40.sf)

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
