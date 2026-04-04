import AsyncDisplayKit
import UIKit

enum SearchTab: Int, CaseIterable {
    case members = 0
    case channels = 1
    case messages = 2

    var title: String {
        switch self {
        case .members:  return "Members"
        case .channels: return "Channels"
        case .messages: return "Messages"
        }
    }
}

enum SearchFilterOption {
    case from
    case mentions

    var symbol: String {
        switch self {
        case .from:     return ">"
        case .mentions: return "~"
        }
    }

    var label: String {
        switch self {
        case .from:     return "from:"
        case .mentions: return "mentions:"
        }
    }

    var description: String {
        switch self {
        case .from:     return "from user"
        case .mentions: return "mention user"
        }
    }

    var iconName: String {
        switch self {
        case .from:     return "person"
        case .mentions: return "at"
        }
    }
}

final class SearchViewController: ViewController {

    private let clanId: Int64
    private let context: AccountContext

    private var searchQuery: String = ""
    private var activeTab: SearchTab = .members

    private var allMembers: [Mezon_Api_User] = []
    private var filteredMembers: [Mezon_Api_User] = []
    private var clanNicks: [Int64: String] = [:]

    private var allChannels: [Mezon_Api_ChannelDescription] = []
    private var filteredChannels: [Mezon_Api_ChannelDescription] = []

    private var searchMessages: [Mezon_Api_SearchMessageDocument] = []
    private var groupedMessages: [(channelId: String, channelLabel: String, messages: [Mezon_Api_SearchMessageDocument])] = []
    private var messageTotalCount: Int32 = 0
    private var messageCurrentPage: Int32 = 0
    private var isLoadingMessages = false
    private var hasMoreMessages: Bool { Int32(searchMessages.count) < messageTotalCount }

    private let pageSize: Int32 = 25

    private var searchNode: SearchContainerNode { displayNode as! SearchContainerNode }

    private var activeFilterOption: SearchFilterOption?
    private var filterUser: Mezon_Api_User?
    private var isPickingFilterUser = false

    private let initialChannels: [Mezon_Api_ChannelDescription]

    private let scopedChannelId: Int64?
    private let scopedChannelLabel: String?
    private let scopedChannelType: Int32
    private let needsChannelMemberFilter: Bool
    private var isChannelScoped: Bool { scopedChannelId != nil }

    init(clanId: Int64, context: AccountContext, channels: [Mezon_Api_ChannelDescription] = [], channelId: Int64? = nil, channelLabel: String? = nil, channelType: Int32 = 1, needsChannelMemberFilter: Bool = false) {
        self.clanId = clanId
        self.context = context
        self.initialChannels = channels
        self.scopedChannelId = channelId
        self.scopedChannelLabel = channelLabel
        self.scopedChannelType = channelType
        self.needsChannelMemberFilter = needsChannelMemberFilter
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        var hiddenTabs: Set<SearchTab> = isChannelScoped ? [.channels] : []
        let isDM = clanId == 0
        if isDM {
            hiddenTabs.insert(.members)
            hiddenTabs.insert(.channels)
        }
        displayNode = SearchContainerNode(hiddenTabs: hiddenTabs, channelBadge: scopedChannelLabel, showFilterButton: isChannelScoped && !isDM)
        if isDM {
            searchNode.tabBar.isHidden = true
            switchTab(.messages)
        }
        searchNode.searchBar.textField.delegate = self
        searchNode.tabBar.onTabSelected = { [weak self] tab in
            self?.switchTab(tab)
        }
        searchNode.tableNode.dataSource = self
        searchNode.tableNode.delegate = self
        searchNode.onBackTapped = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        searchNode.searchBar.onFilterTapped = { [weak self] in
            self?.showFilterTooltip()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        searchNode.applyTheme()
        loadInitialData()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.searchNode.searchBar.textField.becomeFirstResponder()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        searchNode.tableNode.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private var channelMemberIds: Set<Int64>?

    private func loadInitialData() {
        let clanUsersCache = context.engine.clanData.getClanUsers(clanId: clanId)
        let allUsersCache = context.engine.clanData.getAllUserClans()
        let allChCache = context.engine.clanData.getAllChannelsByUser()

        if isChannelScoped {
            if let clanUsers = clanUsersCache {
                allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks)
            }
        } else {
            if let allUsers = allUsersCache {
                allMembers = Self.uniqueUsers(allUsers.users)
            } else if let clanUsers = clanUsersCache {
                allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
            }
        }

        if let allCh = allChCache {
            allChannels = allCh.channeldesc
        } else {
            allChannels = initialChannels
        }

        if needsChannelMemberFilter, let channelId = scopedChannelId {
            let cachedRecord = context.account.postbox.read { tx in
                tx.getChannelMeta(channelId: channelId)
            }
            if let record = cachedRecord, !record.members.isEmpty {
                channelMemberIds = Set(record.members.map { $0.userId })
            }
        }

        filterMembersByChannel()
        filteredChannels = allChannels.filter { $0.parentID == 0 }
        updateTabCounts()
        searchNode.tableNode.reloadData()

        if needsChannelMemberFilter {
            fetchChannelMembersAndUsers()
        } else if allMembers.isEmpty || (!isChannelScoped && allChannels.isEmpty) {
            fetchFromAPI()
        }
    }

    private func fetchFromAPI() {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                if allMembers.isEmpty {
                    if isChannelScoped {
                        let clanUsers = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                        allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                        Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks)
                    } else {
                        let users = try await context.account.network.listUserClansByUserId(token: token)
                        allMembers = Self.uniqueUsers(users.users)
                    }
                    filterMembersByChannel()
                }
                if allChannels.isEmpty || allChannels.count == initialChannels.count {
                    let channels = try await context.account.network.listChannelByUserId(token: token)
                    allChannels = channels.channeldesc
                    filteredChannels = allChannels.filter { $0.parentID == 0 }
                }
                performSearch()
                updateTabCounts()
                await searchNode.tableNode.reloadData()
            } catch {
                AppLogger.network.warning("[Search] fetchFromAPI failed: \(error)")
            }
        }
    }

    private func fetchChannelMembersAndUsers() {
        guard let channelId = scopedChannelId else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                if allMembers.isEmpty {
                    let clanUsers = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                    allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                    Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks)
                }

                let response = try await context.account.network.listChannelUsers(
                    clanId: clanId,
                    channelId: channelId,
                    channelType: scopedChannelType,
                    token: token
                )

                let members = response.channelUsers.map { ChannelMemberRecord(from: $0) }
                context.account.postbox.write { tx in
                    tx.updateChannelMembers(members, channelId: channelId)
                }

                channelMemberIds = Set(response.channelUsers.map { $0.userID })
                filterMembersByChannel()
                performSearch()
                updateTabCounts()
                await searchNode.tableNode.reloadData()
            } catch {
                AppLogger.network.warning("[Search] fetchChannelMembersAndUsers failed: \(error)")
            }
        }
    }

    private func filterMembersByChannel() {
        if let memberIds = channelMemberIds {
            filteredMembers = allMembers.filter { memberIds.contains($0.id) }
        } else {
            filteredMembers = allMembers
        }
    }

    private static func buildClanNicks(from clanUsers: [Mezon_Api_ClanUserList.ClanUser], into map: inout [Int64: String]) {
        for cu in clanUsers {
            if !cu.clanNick.isEmpty {
                map[cu.user.id] = cu.clanNick
            }
        }
    }

    private func displayName(for user: Mezon_Api_User) -> String {
        if let nick = clanNicks[user.id], !nick.isEmpty { return nick }
        if !user.displayName.isEmpty { return user.displayName }
        return user.username
    }

    private static func uniqueUsers(_ users: [Mezon_Api_User]) -> [Mezon_Api_User] {
        var seen = Set<Int64>()
        return users.filter { seen.insert($0.id).inserted }
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let baseMemberList: [Mezon_Api_User]
        if let memberIds = channelMemberIds {
            baseMemberList = allMembers.filter { memberIds.contains($0.id) }
        } else {
            baseMemberList = allMembers
        }

        if query.isEmpty {
            filteredMembers = baseMemberList
        } else {
            filteredMembers = baseMemberList.filter { user in
                let nick = (clanNicks[user.id] ?? "").lowercased()
                let displayName = user.displayName.lowercased()
                let username = user.username.lowercased()
                return nick.contains(query) || displayName.contains(query) || username.contains(query)
            }.sorted { a, b in
                scoreMember(a, query: query) > scoreMember(b, query: query)
            }
        }

        if query.isEmpty {
            filteredChannels = allChannels.filter { $0.parentID == 0 }
        } else {
            filteredChannels = allChannels.filter { ch in
                ch.channelLabel.lowercased().contains(query)
            }
        }

        if !query.isEmpty || filterUser != nil {
            messageCurrentPage = 0
            searchMessages = []
            fetchMessages()
        } else {
            searchMessages = []
            groupedMessages = []
            messageTotalCount = 0
        }

        updateTabCounts()
        searchNode.tableNode.reloadData()
    }

    private func scoreMember(_ user: Mezon_Api_User, query: String) -> Int {
        let nick = (clanNicks[user.id] ?? "").lowercased()
        let displayName = user.displayName.lowercased()
        let username = user.username.lowercased()
        var score = 0
        if nick == query { score = 1050 }
        else if nick.hasPrefix(query) { score = 950 }
        else if nick.contains(query) { score = 550 }
        if displayName == query { score = max(score, 1000) }
        else if displayName.hasPrefix(query) { score = max(score, 900) }
        else if displayName.contains(query) { score = max(score, 500) }
        if username == query { score = max(score, 950) }
        else if username.hasPrefix(query) { score = max(score, 850) }
        else if username.contains(query) { score = max(score, 450) }
        return score
    }

    private func rebuildGroupedMessages() {
        var groups: [(channelId: String, channelLabel: String, messages: [Mezon_Api_SearchMessageDocument])] = []
        for msg in searchMessages {
            if let idx = groups.firstIndex(where: { $0.channelId == msg.channelID }) {
                groups[idx].messages.append(msg)
            } else {
                groups.append((channelId: msg.channelID, channelLabel: msg.channelLabel, messages: [msg]))
            }
        }
        groupedMessages = groups
    }

    private func fetchMessages() {
        guard !isLoadingMessages else { return }
        isLoadingMessages = true

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty || filterUser != nil else {
            isLoadingMessages = false
            return
        }

        Task { @MainActor in
            do {
                guard let token = await context.getToken() else {
                    isLoadingMessages = false
                    return
                }

                var filters: [Mezon_Api_FilterParam] = []

                var channelFilter = Mezon_Api_FilterParam()
                channelFilter.fieldName = "channel_id"
                channelFilter.fieldValue = scopedChannelId.map { "\($0)" } ?? "0"
                filters.append(channelFilter)

                var clanFilter = Mezon_Api_FilterParam()
                clanFilter.fieldName = "clan_id"
                clanFilter.fieldValue = "\(clanId)"
                filters.append(clanFilter)

                if !query.isEmpty {
                    var contentFilter = Mezon_Api_FilterParam()
                    contentFilter.fieldName = "content"
                    contentFilter.fieldValue = query
                    filters.append(contentFilter)
                }

                if let filterUser = filterUser, let option = activeFilterOption {
                    var userFilter = Mezon_Api_FilterParam()
                    userFilter.fieldName = option == .from ? "username" : "mention"
                    userFilter.fieldValue = option == .from ? displayName(for: filterUser) : "\(filterUser.id)"
                    filters.append(userFilter)
                }

                let response = try await context.account.network.searchMessage(
                    filters: filters,
                    from: messageCurrentPage,
                    size: pageSize,
                    token: token
                )

                if messageCurrentPage == 0 {
                    searchMessages = response.messages
                } else {
                    searchMessages.append(contentsOf: response.messages)
                }
                messageTotalCount = response.total
                rebuildGroupedMessages()
                isLoadingMessages = false

                updateTabCounts()
                if activeTab == .messages {
                    await searchNode.tableNode.reloadData()
                }
            } catch {
                isLoadingMessages = false
                AppLogger.network.warning("[Search] searchMessage failed: \(error)")
            }
        }
    }

    private func loadMoreMessages() {
        guard hasMoreMessages, !isLoadingMessages else { return }
        messageCurrentPage += 1
        fetchMessages()
    }

    private func switchTab(_ tab: SearchTab) {
        activeTab = tab
        searchNode.tableNode.reloadData()
        searchNode.tableNode.setContentOffset(.zero, animated: false)

        if activeTab == .messages && searchMessages.isEmpty && !searchQuery.isEmpty {
            fetchMessages()
        }
    }

    private func updateTabCounts() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchNode.tabBar.updateCounts(
            members: filteredMembers.count,
            channels: filteredChannels.count,
            messages: query.isEmpty ? nil : Int(messageTotalCount)
        )
    }

    private func showFilterTooltip() {
        let tooltip = SearchFilterTooltipView(options: [.from, .mentions]) { [weak self] option in
            self?.selectFilterOption(option)
        }
        tooltip.showBelow(anchorView: searchNode.searchBar.view, in: view)
    }

    private func selectFilterOption(_ option: SearchFilterOption) {
        activeFilterOption = option
        filterUser = nil
        isPickingFilterUser = true

        switchTab(.members)
        searchNode.tabBar.isHidden = true
        searchNode.setNeedsLayout()

        searchNode.searchBar.setFilterBadge("\(option.label)")
        searchNode.searchBar.textField.text = ""
        searchQuery = ""
        performSearch()
        searchNode.searchBar.textField.becomeFirstResponder()
    }

    private func selectFilterUser(_ user: Mezon_Api_User) {
        filterUser = user
        isPickingFilterUser = false
        searchNode.setNeedsLayout()

        let badgeText = "\(activeFilterOption?.label ?? "") \(displayName(for: user))"
        searchNode.searchBar.setFilterBadge(badgeText)

        activeTab = .messages
        searchNode.searchBar.textField.text = " "
        searchQuery = ""
        messageCurrentPage = 0
        searchMessages = []
        fetchMessages()
        searchNode.tableNode.reloadData()
        searchNode.searchBar.textField.becomeFirstResponder()
    }

    private func clearFilter() {
        activeFilterOption = nil
        filterUser = nil
        isPickingFilterUser = false
        searchNode.tabBar.isHidden = false
        searchNode.searchBar.clearFilterBadge()
        searchNode.setNeedsLayout()
    }

    private func navigateToMember(_ user: Mezon_Api_User) {
        let isCurrentUser = "\(user.id)" == context.currentUser?.id
        guard !isCurrentUser else { return }

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            }
        )
        self.presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func navigateToChannel(_ channel: Mezon_Api_ChannelDescription) {
        let targetClanId = channel.clanID
        context.currentClanId = targetClanId
        var parentName: String?
        if channel.type == MezonConstants.ChannelType.thread.rawValue && channel.parentID != 0 {
            parentName =
                allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: targetClanId, channel: channel, context: context, parentName: parentName)
        navigationController?.pushViewController(chatVC, animated: true)
    }

    private func navigateToMessage(_ doc: Mezon_Api_SearchMessageDocument) {
        guard let channelId = Int64(doc.channelID) else { return }
        let targetClanId = Int64(doc.clanID) ?? clanId

        var channel = Mezon_Api_ChannelDescription()
        channel.channelID = channelId
        channel.channelLabel = doc.channelLabel
        channel.type = doc.channelType
        channel.clanID = targetClanId

        context.currentClanId = targetClanId
        var parentName: String?
        if channel.type == MezonConstants.ChannelType.thread.rawValue && channel.parentID != 0 {
            parentName =
                allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: targetClanId, channel: channel, context: context, parentName: parentName)
        chatVC.pendingJumpToMessageId = doc.messageID
        navigationController?.pushViewController(chatVC, animated: true)
    }
}

extension SearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = (textField.text ?? "") as NSString
        let newText = current.replacingCharacters(in: range, with: string)

        if activeFilterOption != nil && string.isEmpty && newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearFilter()
            if let label = scopedChannelLabel {
                searchNode.searchBar.setChannelBadge(label)
            }
            textField.text = ""
            searchQuery = ""
            performSearch()
            return false
        }

        searchQuery = newText

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedSearch), object: nil)
        perform(#selector(debouncedSearch), with: nil, afterDelay: 0.3)
        return true
    }

    @objc private func debouncedSearch() {
        performSearch()
    }
}

extension SearchViewController: ASTableDataSource, ASTableDelegate {

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        switch activeTab {
        case .members, .channels:
            return 1
        case .messages:
            return groupedMessages.isEmpty ? 1 : groupedMessages.count
        }
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        switch activeTab {
        case .members:  return filteredMembers.isEmpty ? 1 : filteredMembers.count
        case .channels: return filteredChannels.isEmpty ? 1 : filteredChannels.count
        case .messages:
            if groupedMessages.isEmpty { return 1 }
            guard section < groupedMessages.count else { return 0 }
            return groupedMessages[section].messages.count
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard activeTab == .messages, !groupedMessages.isEmpty, section < groupedMessages.count else { return nil }
        let label = groupedMessages[section].channelLabel
        let header = UIView()
        header.backgroundColor = UIColor.theme.primary
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: "# \(label)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24.sf),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard activeTab == .messages, !groupedMessages.isEmpty else { return 0 }
        return 36.sh
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let tab = activeTab
        let row = indexPath.row

        switch tab {
        case .members:
            if filteredMembers.isEmpty {
                return { SearchEmptyCellNode(text: "No members found") }
            }
            let user = filteredMembers[row]
            let nick = clanNicks[user.id]
            let count = filteredMembers.count
            let isFirst = row == 0
            let isLast = row == count - 1
            return { MemberSearchCellNode(user: user, clanNick: nick, isFirst: isFirst, isLast: isLast) }

        case .channels:
            if filteredChannels.isEmpty {
                return { SearchEmptyCellNode(text: "No channels found") }
            }
            let channel = filteredChannels[row]
            let count = filteredChannels.count
            let isFirst = row == 0
            let isLast = row == count - 1
            return { ChannelSearchCellNode(channel: channel, isFirst: isFirst, isLast: isLast) }

        case .messages:
            if groupedMessages.isEmpty {
                let text = searchQuery.isEmpty ? "Type to search messages" : "No messages found"
                return { SearchEmptyCellNode(text: text) }
            }
            let section = indexPath.section
            guard section < groupedMessages.count else {
                return { SearchEmptyCellNode(text: "") }
            }
            let group = groupedMessages[section]
            guard row < group.messages.count else {
                return { SearchEmptyCellNode(text: "") }
            }
            let doc = group.messages[row]
            let count = group.messages.count
            let isFirst = row == 0
            let isLast = row == count - 1
            return { MessageSearchCellNode(document: doc, isFirst: isFirst, isLast: isLast) }
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)

        switch activeTab {
        case .members:
            guard indexPath.row < filteredMembers.count else { return }
            if isPickingFilterUser {
                selectFilterUser(filteredMembers[indexPath.row])
                return
            }
            navigateToMember(filteredMembers[indexPath.row])

        case .channels:
            guard indexPath.row < filteredChannels.count else { return }
            navigateToChannel(filteredChannels[indexPath.row])

        case .messages:
            let section = indexPath.section
            guard section < groupedMessages.count, indexPath.row < groupedMessages[section].messages.count else { return }
            navigateToMessage(groupedMessages[section].messages[indexPath.row])
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard activeTab == .messages else { return }
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.height

        if offsetY > contentHeight - frameHeight - 200 {
            loadMoreMessages()
        }
    }
}

final class SearchContainerNode: ASDisplayNode {

    let searchBar: SearchInputNode
    let tabBar: SearchTabBarNode
    let tableNode = ASTableNode(style: .grouped)
    private let backButtonNode = ASButtonNode()
    private let headerNode = ASDisplayNode()
    private let separatorNode = ASDisplayNode()
    var onBackTapped: (() -> Void)?

    init(hiddenTabs: Set<SearchTab> = [], channelBadge: String? = nil, showFilterButton: Bool = false) {
        self.searchBar = SearchInputNode(showFilterButton: showFilterButton)
        self.tabBar = SearchTabBarNode(hiddenTabs: hiddenTabs)
        super.init()
        automaticallyManagesSubnodes = false

        backButtonNode.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        backButtonNode.addTarget(self, action: #selector(backTapped), forControlEvents: .touchUpInside)

        if let channelBadge {
            searchBar.setChannelBadge(channelBadge)
        }

        addSubnode(headerNode)
        headerNode.addSubnode(backButtonNode)
        headerNode.addSubnode(searchBar)
        headerNode.addSubnode(tabBar)
        headerNode.addSubnode(separatorNode)
        addSubnode(tableNode)
    }

    override func didLoad() {
        super.didLoad()
        tableNode.view.separatorStyle = .none
        tableNode.view.keyboardDismissMode = .onDrag
        tableNode.view.sectionFooterHeight = 0
        tableNode.view.estimatedSectionHeaderHeight = 36
        if #available(iOS 15.0, *) {
            tableNode.view.sectionHeaderTopPadding = 0
        }
        tableNode.view.contentInset.top = 8
        searchBar.textField.returnKeyType = .search
        searchBar.textField.autocorrectionType = .no
    }

    @objc private func backTapped() {
        onBackTapped?()
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        headerNode.backgroundColor = t.primary
        backButtonNode.tintColor = t.textStrong
        searchBar.applyTheme()
        tabBar.applyTheme()
        separatorNode.backgroundColor = t.border.withAlphaComponent(0.3)
        tableNode.backgroundColor = t.primary
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let safeTop = self.safeAreaInsets.top

        let backSize: CGFloat = 32
        let searchH: CGFloat = 36
        let tabH: CGFloat = tabBar.isHidden ? 0 : 40
        let tabSpacing: CGFloat = tabBar.isHidden ? 4 : 12
        let headerTop = safeTop + 8
        let separatorH: CGFloat = 0.5

        backButtonNode.frame = CGRect(x: 8, y: headerTop, width: backSize, height: backSize)
        searchBar.frame = CGRect(
            x: backButtonNode.frame.maxX + 4,
            y: headerTop + (backSize - searchH) / 2,
            width: bounds.width - backButtonNode.frame.maxX - 4 - 12,
            height: searchH
        )
        tabBar.frame = CGRect(
            x: 0, y: searchBar.frame.maxY + tabSpacing,
            width: bounds.width, height: tabH
        )

        let headerH = tabBar.frame.maxY + separatorH
        headerNode.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerH)
        separatorNode.frame = CGRect(x: 0, y: headerH - separatorH, width: bounds.width, height: separatorH)
        tableNode.frame = CGRect(x: 0, y: headerH, width: bounds.width, height: bounds.height - headerH)
    }
}

final class SearchInputNode: ASDisplayNode {

    let textField = UITextField()
    private let iconNode = ASImageNode()
    private var badgeLabel: UILabel?
    private var badgeWidth: CGFloat = 0
    private var filterButton: UIButton?
    private let showFilterButton: Bool
    var onFilterTapped: (() -> Void)?

    init(showFilterButton: Bool = false) {
        self.showFilterButton = showFilterButton
        super.init()

        iconNode.image = UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate)
        iconNode.contentMode = .scaleAspectFit
        addSubnode(iconNode)
    }

    override func didLoad() {
        super.didLoad()
        let t = UIColor.theme
        textField.font = .systemFont(ofSize: 14)
        textField.textColor = t.textStrong
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: t.textDisabled]
        )
        view.addSubview(textField)

        if let badge = badgeLabel {
            view.addSubview(badge)
        }

        if showFilterButton {
            let btn = UIButton(type: .system)
            let img = UIImage(systemName: "line.3.horizontal.decrease")?.withRenderingMode(.alwaysTemplate)
            btn.setImage(img, for: .normal)
            btn.tintColor = t.textStrong
            btn.addTarget(self, action: #selector(filterTapped), for: .touchUpInside)
            view.addSubview(btn)
            filterButton = btn
        }
    }

    @objc private func filterTapped() {
        onFilterTapped?()
    }

    func setChannelBadge(_ channelName: String) {
        badgeLabel?.removeFromSuperview()
        let label = UILabel()
        label.text = "in: \(channelName)"
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        let size = label.sizeThatFits(CGSize(width: 200, height: 20))
        badgeWidth = size.width + 16
        badgeLabel = label
        if isNodeLoaded { view.addSubview(label) }
        setNeedsLayout()
    }

    func setFilterBadge(_ text: String) {
        badgeLabel?.removeFromSuperview()
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        let size = label.sizeThatFits(CGSize(width: 200, height: 20))
        badgeWidth = size.width + 16
        badgeLabel = label
        if isNodeLoaded { view.addSubview(label) }
        setNeedsLayout()
    }

    func clearFilterBadge() {
        badgeLabel?.removeFromSuperview()
        badgeLabel = nil
        badgeWidth = 0
        setNeedsLayout()
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.tertiary
        cornerRadius = 18
        clipsToBounds = true
        iconNode.tintColor = t.textDisabled
        textField.textColor = t.textStrong
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: t.textDisabled]
        )
        filterButton?.tintColor = t.textStrong
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let filterW: CGFloat = showFilterButton ? 32 : 0
        iconNode.frame = CGRect(x: 12, y: (h - 18) / 2, width: 18, height: 18)

        if let btn = filterButton {
            btn.frame = CGRect(x: bounds.width - filterW - 4, y: 0, width: filterW, height: h)
        }

        let rightPad: CGFloat = showFilterButton ? filterW + 8 : 12

        if let badge = badgeLabel {
            let badgeH: CGFloat = 20
            let badgeX: CGFloat = 36
            badge.frame = CGRect(x: badgeX, y: (h - badgeH) / 2, width: badgeWidth, height: badgeH)
            textField.frame = CGRect(x: badgeX + badgeWidth + 6, y: 0, width: bounds.width - badgeX - badgeWidth - 6 - rightPad, height: h)
        } else {
            textField.frame = CGRect(x: 36, y: 0, width: bounds.width - 36 - rightPad, height: h)
        }
    }
}

final class SearchTabBarNode: ASDisplayNode {

    var onTabSelected: ((SearchTab) -> Void)?
    private var tabNodes: [(tab: SearchTab, node: SearchTabItemNode)] = []
    private let indicatorNode = ASDisplayNode()
    private(set) var selectedTab: SearchTab = .members
    private var counts: [SearchTab: Int?] = [:]

    init(hiddenTabs: Set<SearchTab> = []) {
        super.init()

        indicatorNode.cornerRadius = 1.5
        addSubnode(indicatorNode)

        let visibleTabs = SearchTab.allCases.filter { !hiddenTabs.contains($0) }
        for tab in visibleTabs {
            let node = SearchTabItemNode(tab: tab)
            node.onTap = { [weak self] in self?.selectTab(tab) }
            tabNodes.append((tab, node))
            addSubnode(node)
        }
        if let first = visibleTabs.first {
            selectedTab = first
        }
    }

    func updateCounts(members: Int, channels: Int, messages: Int?) {
        counts[.members] = members
        counts[.channels] = channels
        counts[.messages] = messages
        updateTabTitles()
    }

    func applyTheme() {
        let accent = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1)
        indicatorNode.backgroundColor = accent
        updateTabAppearance()
    }

    private func selectTab(_ tab: SearchTab) {
        selectedTab = tab
        updateTabAppearance()
        onTabSelected?(tab)
    }

    private func updateTabTitles() {
        for (tab, node) in tabNodes {
            var title = tab.title
            if let count = counts[tab], let c = count {
                title += " (\(c))"
            }
            node.update(title: title)
        }
    }

    private func updateTabAppearance() {
        let t = UIColor.theme
        let accent = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1)
        for (tab, node) in tabNodes {
            node.setSelected(tab == selectedTab, accent: accent, normal: t.textDisabled)
        }
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        guard bounds.height > 3 else { return }
        let tabW = bounds.width / CGFloat(tabNodes.count)
        for (i, (_, node)) in tabNodes.enumerated() {
            node.frame = CGRect(x: tabW * CGFloat(i), y: 0, width: tabW, height: bounds.height - 3)
        }

        guard let selectedEntry = tabNodes.first(where: { $0.tab == selectedTab }) else { return }
        let selected = selectedEntry.node
        let targetFrame = CGRect(
            x: selected.frame.minX + 16,
            y: bounds.height - 3,
            width: selected.frame.width - 32,
            height: 3
        )

        if indicatorNode.frame.width > 0 {
            UIView.animate(withDuration: 0.25) {
                self.indicatorNode.frame = targetFrame
            }
        } else {
            indicatorNode.frame = targetFrame
        }
    }
}

private final class SearchTabItemNode: ASDisplayNode {

    var onTap: (() -> Void)?
    private let titleNode = ASTextNode2()
    private var currentTitle: String

    init(tab: SearchTab) {
        currentTitle = tab.title
        super.init()
        titleNode.attributedText = NSAttributedString(
            string: tab.title,
            attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        addSubnode(titleNode)
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @objc private func handleTap() {
        onTap?()
    }

    func update(title: String) {
        guard title != currentTitle else { return }
        currentTitle = title
        let color = titleNode.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor ?? .gray
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: color,
            ]
        )
    }

    func setSelected(_ selected: Bool, accent: UIColor, normal: UIColor) {
        let color = selected ? accent : normal
        titleNode.attributedText = NSAttributedString(
            string: currentTitle,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: color,
            ]
        )
    }

    override func layout() {
        super.layout()
        let size = titleNode.calculatedSize.width > 0
            ? titleNode.calculatedSize
            : titleNode.measure(bounds.size)
        titleNode.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }
}

final class SearchEmptyCellNode: ASCellNode {
    private let textNode = ASTextNode2()

    init(text: String) {
        super.init()
        backgroundColor = UIColor.theme.primary
        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.theme.textDisabled,
            ]
        )
        addSubnode(textNode)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let insets = UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20)
        let centered = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: textNode)
        return ASInsetLayoutSpec(insets: insets, child: centered)
    }
}

final class MemberSearchCellNode: ASCellNode {
    private let avatarNode = ASNetworkImageNode()
    private let statusDotNode = ASDisplayNode()
    private let nameNode = ASTextNode2()
    private let usernameNode = ASTextNode2()
    private let cardNode = ASDisplayNode()
    private let isFirst: Bool
    private let isLast: Bool
    private let hasUsername: Bool

    private static let avatarSize: CGFloat = 40.sf
    private static let margin: CGFloat = 12.sf
    private static let padding: CGFloat = 16.sf
    private static let cellHeight: CGFloat = 60.sh
    private static let radius: CGFloat = 10.sf

    init(user: Mezon_Api_User, clanNick: String? = nil, isFirst: Bool = false, isLast: Bool = false) {
        self.isFirst = isFirst
        self.isLast = isLast
        self.hasUsername = !user.username.isEmpty
        super.init()
        selectionStyle = .none
        let t = UIColor.theme
        backgroundColor = .clear

        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        addSubnode(cardNode)

        avatarNode.cornerRadius = Self.avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = t.tertiary
        if !user.avatarURL.isEmpty, let url = URL(string: ImgproxyURL.create(from: user.avatarURL)) {
            avatarNode.url = url
        }

        statusDotNode.backgroundColor = user.online
            ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1)
            : UIColor.gray
        statusDotNode.cornerRadius = 6.sf
        statusDotNode.borderWidth = 2.sf
        statusDotNode.borderColor = t.secondary.cgColor

        let displayName: String
        if let nick = clanNick, !nick.isEmpty {
            displayName = nick
        } else if !user.displayName.isEmpty {
            displayName = user.displayName
        } else {
            displayName = user.username
        }
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [.font: UIFont.systemFont(ofSize: 15.sf, weight: .medium), .foregroundColor: t.textStrong]
        )

        if hasUsername {
            usernameNode.maximumNumberOfLines = 1
            usernameNode.truncationMode = .byTruncatingTail
            usernameNode.attributedText = NSAttributedString(
                string: user.username,
                attributes: [.font: UIFont.systemFont(ofSize: 13.sf), .foregroundColor: t.textDisabled]
            )
        }

        addSubnode(avatarNode)
        addSubnode(statusDotNode)
        addSubnode(nameNode)
        if hasUsername { addSubnode(usernameNode) }
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        CGSize(width: constrainedSize.width, height: Self.cellHeight)
    }

    override func layout() {
        super.layout()
        let m = Self.margin
        let p = Self.padding
        let avatarSz = Self.avatarSize
        let cardFrame = CGRect(x: m, y: 0, width: bounds.width - m * 2, height: bounds.height)
        cardNode.frame = cardFrame
        Self.applyCorners(to: cardNode, isFirst: isFirst, isLast: isLast)

        let contentX = m + p
        let avatarY = (bounds.height - avatarSz) / 2
        avatarNode.frame = CGRect(x: contentX, y: avatarY, width: avatarSz, height: avatarSz)

        statusDotNode.frame = CGRect(
            x: contentX + avatarSz - 12.sf,
            y: avatarY + avatarSz - 12.sf,
            width: 12.sf, height: 12.sf
        )

        let textX = contentX + avatarSz + 12.sf
        let textW = bounds.width - textX - m - p
        if hasUsername {
            let nameSize = nameNode.measure(CGSize(width: textW, height: 20))
            let usernameSize = usernameNode.measure(CGSize(width: textW, height: 18))
            let totalH = nameSize.height + 2 + usernameSize.height
            let textY = (bounds.height - totalH) / 2
            nameNode.frame = CGRect(x: textX, y: textY, width: textW, height: nameSize.height)
            usernameNode.frame = CGRect(x: textX, y: textY + nameSize.height + 2, width: textW, height: usernameSize.height)
        } else {
            let nameSize = nameNode.measure(CGSize(width: textW, height: 20))
            nameNode.frame = CGRect(x: textX, y: (bounds.height - nameSize.height) / 2, width: textW, height: nameSize.height)
        }
    }

    static func applyCorners(to node: ASDisplayNode, isFirst: Bool, isLast: Bool) {
        if isFirst && isLast {
            node.cornerRadius = radius
            node.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else if isFirst {
            node.cornerRadius = radius
            node.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else if isLast {
            node.cornerRadius = radius
            node.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            node.cornerRadius = 0
        }
    }
}

final class ChannelSearchCellNode: ASCellNode {
    private let iconImgNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let clanNameNode = ASTextNode2()
    private let cardNode = ASDisplayNode()
    private let isFirst: Bool
    private let isLast: Bool
    private let hasClanName: Bool

    init(channel: Mezon_Api_ChannelDescription, isFirst: Bool = false, isLast: Bool = false) {
        self.isFirst = isFirst
        self.isLast = isLast
        self.hasClanName = !channel.clanName.isEmpty
        super.init()
        selectionStyle = .none
        let t = UIColor.theme
        backgroundColor = .clear

        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        addSubnode(cardNode)

        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        let isThread = channel.parentID != 0

        var iconName: String
        if isThread {
            iconName = channel.channelPrivate == 1
                ? "Channel/channelThreadPrivate"
                : "Channel/channelThread"
        } else {
            iconName = chType.icon
            if chType == .text && channel.channelPrivate == 1 {
                iconName = "Channel/channelPrivate"
            }
        }

        let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
        iconImgNode.image = image?.withRenderingMode(.alwaysTemplate)
        iconImgNode.tintColor = t.channelNormal
        iconImgNode.contentMode = .scaleAspectFit

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: channel.channelLabel,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .medium),
                .foregroundColor: t.textStrong,
            ]
        )

        if hasClanName {
            clanNameNode.attributedText = NSAttributedString(
                string: channel.clanName,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.textDisabled,
                ]
            )
        }

        addSubnode(iconImgNode)
        addSubnode(nameNode)
        if hasClanName { addSubnode(clanNameNode) }
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        CGSize(width: constrainedSize.width, height: hasClanName ? 52.sh : 44.sh)
    }

    override func layout() {
        super.layout()
        let m: CGFloat = 12.sf
        let p: CGFloat = 16.sw
        let iconSz: CGFloat = 16.swh
        let cardFrame = CGRect(x: m, y: 0, width: bounds.width - m * 2, height: bounds.height)
        cardNode.frame = cardFrame
        MemberSearchCellNode.applyCorners(to: cardNode, isFirst: isFirst, isLast: isLast)

        let contentX = m + p
        let iconY = (bounds.height - iconSz) / 2
        iconImgNode.frame = CGRect(x: contentX, y: iconY, width: iconSz, height: iconSz)

        let textX = contentX + iconSz + 10.sw
        let textW = bounds.width - textX - m - p
        if hasClanName {
            let nameSize = nameNode.measure(CGSize(width: textW, height: 20))
            let clanSize = clanNameNode.measure(CGSize(width: textW, height: 16))
            let totalH = nameSize.height + 2 + clanSize.height
            let textY = (bounds.height - totalH) / 2
            nameNode.frame = CGRect(x: textX, y: textY, width: textW, height: nameSize.height)
            clanNameNode.frame = CGRect(x: textX, y: textY + nameSize.height + 2, width: textW, height: clanSize.height)
        } else {
            let nameSize = nameNode.measure(CGSize(width: textW, height: 20))
            nameNode.frame = CGRect(x: textX, y: (bounds.height - nameSize.height) / 2, width: textW, height: nameSize.height)
        }
    }
}

final class MessageSearchCellNode: ASCellNode {
    private let avatarNode = ASNetworkImageNode()
    private let senderNode = ASTextNode2()
    private let contentNode = ASTextNode2()
    private let timeNode = ASTextNode2()
    private let cardNode = ASDisplayNode()
    private let isFirst: Bool
    private let isLast: Bool

    private static let avatarSize: CGFloat = 36.sf
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let relativeFormatter = RelativeDateTimeFormatter()

    init(document: Mezon_Api_SearchMessageDocument, isFirst: Bool = false, isLast: Bool = false) {
        self.isFirst = isFirst
        self.isLast = isLast
        super.init()
        selectionStyle = .none
        let t = UIColor.theme
        backgroundColor = .clear

        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        addSubnode(cardNode)

        avatarNode.cornerRadius = Self.avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = t.tertiary
        if !document.avatarURL.isEmpty, let url = URL(string: ImgproxyURL.create(from: document.avatarURL)) {
            avatarNode.url = url
        }

        let displayName = document.displayName.isEmpty ? document.username : document.displayName
        senderNode.maximumNumberOfLines = 1
        senderNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [.font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold), .foregroundColor: t.textStrong]
        )

        let contentText = Self.parseMessageContent(document.content)
        contentNode.attributedText = NSAttributedString(
            string: contentText,
            attributes: [.font: UIFont.systemFont(ofSize: 13.sf), .foregroundColor: t.textStrong]
        )
        contentNode.maximumNumberOfLines = 2
        contentNode.truncationMode = .byTruncatingTail

        if !document.createTime.isEmpty {
            let formatted = Self.formatSearchTime(document.createTime)
            timeNode.attributedText = NSAttributedString(
                string: formatted,
                attributes: [.font: UIFont.systemFont(ofSize: 11.sf), .foregroundColor: t.textDisabled]
            )
        }

        addSubnode(avatarNode)
        addSubnode(senderNode)
        addSubnode(contentNode)
        addSubnode(timeNode)
    }

    private static func parseMessageContent(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["t"] as? String else {
            return json
        }
        return text
    }

    private static func formatSearchTime(_ timeStr: String) -> String {
        let date = isoFormatter.date(from: timeStr)
            ?? isoFormatterNoFrac.date(from: timeStr)
        guard let date else { return timeStr }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let m: CGFloat = 12.sf
        let p: CGFloat = 16.sf
        let textW = constrainedSize.width - m * 2 - p * 2 - Self.avatarSize - 10.sf
        let senderSize = senderNode.measure(CGSize(width: textW, height: 20))
        let contentSize = contentNode.measure(CGSize(width: textW, height: .greatestFiniteMagnitude))
        let totalH = 10.sh + senderSize.height + 3 + contentSize.height + 10.sh
        return CGSize(width: constrainedSize.width, height: totalH)
    }

    override func layout() {
        super.layout()
        let m: CGFloat = 12.sf
        let p: CGFloat = 16.sf
        let avatarSz = Self.avatarSize
        let cardFrame = CGRect(x: m, y: 0, width: bounds.width - m * 2, height: bounds.height)
        cardNode.frame = cardFrame
        MemberSearchCellNode.applyCorners(to: cardNode, isFirst: isFirst, isLast: isLast)

        let contentX = m + p
        avatarNode.frame = CGRect(x: contentX, y: 10.sh, width: avatarSz, height: avatarSz)

        let textX = contentX + avatarSz + 10.sf
        let textW = bounds.width - textX - m - p
        let senderSize = senderNode.calculatedSize.width > 0 ? senderNode.calculatedSize : senderNode.measure(CGSize(width: textW, height: 20))
        let timeSize = timeNode.measure(CGSize(width: textW, height: 16))
        let senderW = min(senderSize.width, textW - timeSize.width - 6)

        senderNode.frame = CGRect(x: textX, y: 10.sh, width: senderW, height: senderSize.height)
        timeNode.frame = CGRect(x: textX + senderW + 6, y: 10.sh + senderSize.height - timeSize.height, width: timeSize.width, height: timeSize.height)

        let contentY = 10.sh + senderSize.height + 3
        let contentSize = contentNode.calculatedSize.width > 0 ? contentNode.calculatedSize : contentNode.measure(CGSize(width: textW, height: .greatestFiniteMagnitude))
        contentNode.frame = CGRect(x: textX, y: contentY, width: textW, height: contentSize.height)
    }
}

final class SearchFilterTooltipView: UIView {

    private let onSelect: (SearchFilterOption) -> Void
    private var backgroundOverlay: UIView?

    init(options: [SearchFilterOption], onSelect: @escaping (SearchFilterOption) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        setupUI(options: options)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI(options: [SearchFilterOption]) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
        clipsToBounds = false

        let header = UILabel()
        header.text = "Filter results"
        header.font = .systemFont(ofSize: 14, weight: .bold)
        header.textColor = t.textStrong
        header.frame = CGRect(x: 14, y: 10, width: 200, height: 20)
        addSubview(header)

        let separator = UIView()
        separator.backgroundColor = t.border.withAlphaComponent(0.3)
        separator.frame = CGRect(x: 0, y: 36, width: 220, height: 0.5)
        addSubview(separator)

        var y: CGFloat = 36.5
        for option in options {
            let row = createOptionRow(option: option, y: y)
            addSubview(row)
            y += 48

            if option != options.last {
                let div = UIView()
                div.backgroundColor = t.border.withAlphaComponent(0.2)
                div.frame = CGRect(x: 10, y: y, width: 200, height: 0.5)
                addSubview(div)
                y += 0.5
            }
        }

        frame.size = CGSize(width: 220, height: y + 6)
    }

    private func createOptionRow(option: SearchFilterOption, y: CGFloat) -> UIView {
        let t = UIColor.theme
        let container = UIView(frame: CGRect(x: 0, y: y, width: 220, height: 48))

        let icon = UIImageView(image: UIImage(systemName: option.iconName)?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = t.textDisabled
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 190, y: 14, width: 20, height: 20)
        container.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = t.textStrong
        titleLabel.text = option.label
        titleLabel.frame = CGRect(x: 14, y: 8, width: 80, height: 18)
        container.addSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = t.textDisabled
        descLabel.text = option.description
        descLabel.frame = CGRect(x: 14, y: 26, width: 170, height: 16)
        container.addSubview(descLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(optionTapped(_:)))
        container.addGestureRecognizer(tap)
        container.tag = option == .from ? 0 : 1
        container.isUserInteractionEnabled = true

        return container
    }

    @objc private func optionTapped(_ gesture: UITapGestureRecognizer) {
        guard let tag = gesture.view?.tag else { return }
        let option: SearchFilterOption = tag == 0 ? .from : .mentions
        dismiss()
        onSelect(option)
    }

    func showBelow(anchorView: UIView, in parentView: UIView) {
        let overlay = UIView(frame: parentView.bounds)
        overlay.backgroundColor = .clear
        let tapDismiss = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        overlay.addGestureRecognizer(tapDismiss)
        parentView.addSubview(overlay)
        backgroundOverlay = overlay

        let anchorFrame = anchorView.convert(anchorView.bounds, to: parentView)
        let tooltipX = anchorFrame.maxX - frame.width
        let tooltipY = anchorFrame.maxY + 6
        frame.origin = CGPoint(x: max(12, tooltipX), y: tooltipY)

        alpha = 0
        parentView.addSubview(self)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
    }

    @objc private func dismissTapped() {
        dismiss()
    }

    private func dismiss() {
        UIView.animate(withDuration: 0.15, animations: { self.alpha = 0 }) { _ in
            self.backgroundOverlay?.removeFromSuperview()
            self.removeFromSuperview()
        }
    }
}
