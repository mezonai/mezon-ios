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
    private var friendMembers: [Mezon_Api_User] = []
    private var filteredMembers: [Mezon_Api_User] = []
    private var clanNicks: [Int64: String] = [:]
    private var clanAvatars: [Int64: String] = [:]

    private var allChannels: [Mezon_Api_ChannelDescription] = []
    private var filteredChannels: [Mezon_Api_ChannelDescription] = []
    private var filteredDMGroups: [Mezon_Api_ChannelDescription] = []

    private var searchMessages: [Mezon_Api_SearchMessageDocument] = []
    private var groupedMessages: [(channelId: String, channelLabel: String, messages: [Mezon_Api_SearchMessageDocument])] = []
    private var messageTotalCount: Int32 = 0
    private var messageCurrentPage: Int32 = 1
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

    private var memberAvatarPrefetchWorkItem: DispatchWorkItem?

    private func reloadSearchTable() {
        UIView.performWithoutAnimation {
            self.searchNode.tableNode.reloadData()
        }
    }

    private func appendMessageRowsIncrementally(oldSectionCounts: [Int]) {
        let tableNode = searchNode.tableNode
        let oldSectionCount = oldSectionCounts.count
        let newSectionCount = groupedMessages.count

        guard newSectionCount >= oldSectionCount else {
            reloadSearchTable()
            return
        }

        var rowInserts: [IndexPath] = []
        for section in 0..<oldSectionCount {
            let oldCount = oldSectionCounts[section]
            let newCount = groupedMessages[section].messages.count
            guard newCount >= oldCount else {
                reloadSearchTable()
                return
            }
            for row in oldCount..<newCount {
                rowInserts.append(IndexPath(row: row, section: section))
            }
        }

        var sectionInserts = IndexSet()
        if newSectionCount > oldSectionCount {
            sectionInserts.insert(integersIn: oldSectionCount..<newSectionCount)
        }

        guard !rowInserts.isEmpty || !sectionInserts.isEmpty else { return }

        UIView.performWithoutAnimation {
            tableNode.performBatchUpdates({
                if !sectionInserts.isEmpty {
                    tableNode.insertSections(sectionInserts, with: .none)
                }
                if !rowInserts.isEmpty {
                    tableNode.insertRows(at: rowInserts, with: .none)
                }
            }, completion: nil)
        }
    }

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
        var hiddenTabs: Set<SearchTab> = isChannelScoped ? [.channels] : [.messages]
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
        searchNode.searchBar.textField.addTarget(self, action: #selector(searchTextChanged(_:)), for: .editingChanged)
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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private var channelMemberIds: Set<Int64>?

    private func loadInitialData() {
        friendMembers = context.engine.friendsData.allFriends()
            .filter { $0.state == EStateFriend.friend.rawValue && $0.hasUser && $0.user.id != 0 }
            .map { $0.user }
        let clanUsersCache = context.engine.clanData.getClanUsers(clanId: clanId)
        let allUsersCache = context.engine.clanData.getAllUserClans()
        let allChCache = context.engine.clanData.getAllChannelsByUser()

        if let clanUsers = clanUsersCache {
            Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks, avatars: &clanAvatars)
        }

        if isChannelScoped {
            if let clanUsers = clanUsersCache {
                allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
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
            mergeInitialChannelsIntoAllChannels()
        } else {
            allChannels = initialChannels
        }
        mergeCachedClanChannelListsIntoAllChannels()
        mergeDMChannelsIntoAllChannels()

        if needsChannelMemberFilter, let channelId = scopedChannelId {
            let cachedRecord = context.account.postbox.read { tx in
                tx.getChannelMeta(channelId: channelId)
            }
            if let record = cachedRecord, !record.members.isEmpty {
                channelMemberIds = Set(record.members.map { $0.userId })
            }
        }

        filterMembersByChannel()
        filteredChannels = allChannels.filter { $0.parentID == 0 && Self.isServerChannelInChannelsTab($0) }
        updateTabCounts()
        reloadSearchTable()
        schedulePrefetchMemberAvatars(filteredMembers)

        if needsChannelMemberFilter {
            fetchChannelMembersAndUsers()
        } else {
            fetchFromAPI()
        }
    }

    private func mergeInitialChannelsIntoAllChannels() {
        guard !initialChannels.isEmpty else { return }
        var existingIds = Set(allChannels.map { $0.channelID })
        for ch in initialChannels where !existingIds.contains(ch.channelID) {
            allChannels.append(ch)
            existingIds.insert(ch.channelID)
        }
    }

    private func mergeCachedClanChannelListsIntoAllChannels() {
        let cached = context.account.postbox.getAllCachedClanChannelDescriptions()
        guard !cached.isEmpty else { return }
        var existingIds = Set(allChannels.map { $0.channelID })
        for ch in cached where !existingIds.contains(ch.channelID) {
            allChannels.append(ch)
            existingIds.insert(ch.channelID)
        }
    }

    private func mergeDMChannelsIntoAllChannels() {
        let cachedDMs = context.account.postbox.getCachedDMChannelList()
        guard !cachedDMs.isEmpty else { return }
        var existingIds = Set(allChannels.map { $0.channelID })
        for dm in cachedDMs where !existingIds.contains(dm.channelID) {
            allChannels.append(dm)
            existingIds.insert(dm.channelID)
        }
    }

    deinit {
        memberAvatarPrefetchWorkItem?.cancel()
    }

    private func fetchFromAPI() {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let needsClanProfileHydration =
                    clanId > 0
                    && (clanAvatars.isEmpty || clanNicks.isEmpty || (isChannelScoped && allMembers.isEmpty))
                if needsClanProfileHydration {
                    if let clanUsers = try? await context.account.network.listClanUsers(clanId: clanId, token: token) {
                        Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks, avatars: &clanAvatars)
                        if isChannelScoped && allMembers.isEmpty {
                            allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                        }
                    }
                }
                if allMembers.isEmpty {
                    if isChannelScoped {
                        let clanUsers = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                        allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                        Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks, avatars: &clanAvatars)
                    } else {
                        let users = try await context.account.network.listUserClansByUserId(token: token)
                        allMembers = Self.uniqueUsers(users.users)
                    }
                    filterMembersByChannel()
                }
            } catch {}
            do {
                let channels = try await context.account.network.listChannelByUserId(token: token)
                if !channels.channeldesc.isEmpty {
                    allChannels = channels.channeldesc
                    mergeInitialChannelsIntoAllChannels()
                    mergeCachedClanChannelListsIntoAllChannels()
                    mergeDMChannelsIntoAllChannels()
                    var persistList = channels
                    if let existing = context.engine.clanData.getAllChannelsByUser() {
                        var ids = Set(persistList.channeldesc.map { $0.channelID })
                        for ch in existing.channeldesc where !ids.contains(ch.channelID) {
                            persistList.channeldesc.append(ch)
                            ids.insert(ch.channelID)
                        }
                    }
                    if let data = try? persistList.serializedData() {
                        context.account.postbox.setPreferenceData(
                            key: PreferencesKeys.allChannelsByUser, value: data)
                    }
                }
            } catch {}
            await fetchDMAndGroupChannels()
            performSearch()
        }
    }

    private func fetchDMAndGroupChannels() async {
        guard let token = await context.getToken() else { return }
        var existingIds = Set(allChannels.map { $0.channelID })
        do {
            let dmChannels = try await context.account.network.listDirectMessageChannels(token: token)
            for dm in dmChannels where !existingIds.contains(dm.channelID) {
                allChannels.append(dm)
                existingIds.insert(dm.channelID)
            }
        } catch {
        }
        do {
            let groupChannels = try await context.account.network.listGroupMessageChannels(token: token)
            for g in groupChannels where !existingIds.contains(g.channelID) {
                allChannels.append(g)
                existingIds.insert(g.channelID)
            }
        } catch {
        }
    }

    private func fetchChannelMembersAndUsers() {
        guard let channelId = scopedChannelId else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let needsClanProfileHydration =
                    clanId > 0
                    && (allMembers.isEmpty || clanAvatars.isEmpty || clanNicks.isEmpty)
                if needsClanProfileHydration {
                    if let clanUsers = try? await context.account.network.listClanUsers(clanId: clanId, token: token) {
                        Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks, avatars: &clanAvatars)
                        if allMembers.isEmpty {
                            allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                        }
                    }
                }
                if allMembers.isEmpty {
                    let clanUsers = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                    allMembers = Self.uniqueUsers(clanUsers.clanUsers.map { $0.user })
                    Self.buildClanNicks(from: clanUsers.clanUsers, into: &clanNicks, avatars: &clanAvatars)
                }

                let response = try await context.account.network.listChannelUsers(
                    clanId: clanId,
                    channelId: channelId,
                    channelType: scopedChannelType,
                    token: token
                )

                let members = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                    response.channelUsers, postbox: context.account.postbox)
                context.account.postbox.write { tx in
                    tx.updateChannelMembers(members, channelId: channelId)
                }

                channelMemberIds = Set(response.channelUsers.map { $0.userID })
                filterMembersByChannel()
                performSearch()
            } catch {
            }
        }
    }

    private func searchableMembers() -> [Mezon_Api_User] {
        if let memberIds = channelMemberIds {
            return allMembers.filter { memberIds.contains($0.id) }
        }
        if isChannelScoped {
            return allMembers
        }
        return Self.uniqueUsers(allMembers + friendMembers)
    }

    private func filterMembersByChannel() {
        filteredMembers = searchableMembers()
    }

    private static func buildClanNicks(from clanUsers: [Mezon_Api_ClanUserList.ClanUser], into map: inout [Int64: String], avatars: inout [Int64: String]) {
        for cu in clanUsers {
            if !cu.clanNick.isEmpty {
                map[cu.user.id] = cu.clanNick
            }
            if !cu.clanAvatar.isEmpty {
                avatars[cu.user.id] = cu.clanAvatar
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

    static func dmGroupDisplayName(for ch: Mezon_Api_ChannelDescription) -> String {
        if !ch.channelLabel.isEmpty { return ch.channelLabel }
        if let first = ch.displayNames.first, !first.isEmpty {
            return ch.displayNames.joined(separator: ", ")
        }
        if let first = ch.usernames.first, !first.isEmpty {
            return ch.usernames.joined(separator: ", ")
        }
        if !ch.creatorName.isEmpty { return "\(ch.creatorName)'s Group" }
        return "Chat"
    }

    private static func isServerChannelInChannelsTab(_ ch: Mezon_Api_ChannelDescription) -> Bool {
        ch.type != MezonConstants.ChannelType.dm.rawValue
        && ch.type != MezonConstants.ChannelType.group.rawValue
    }

    private func parentChannelLabel(forParentId parentId: Int64) -> String {
        allChannels.first(where: { $0.channelID == parentId })?.channelLabel ?? ""
    }

    private func nonEmptyChannelLabel(_ label: String?) -> String {
        label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func displayLabel(for channel: Mezon_Api_ChannelDescription) -> String {
        let label = nonEmptyChannelLabel(channel.channelLabel)
        let isDMOrGroup =
            channel.type == MezonConstants.ChannelType.dm.rawValue
            || channel.type == MezonConstants.ChannelType.group.rawValue
        if isDMOrGroup {
            let displayName = Self.dmGroupDisplayName(for: channel)
            return nonEmptyChannelLabel(displayName)
        }
        if !label.isEmpty { return label }
        let topic = nonEmptyChannelLabel(channel.topic)
        if !topic.isEmpty { return topic }
        return ""
    }

    private func resolvedChannelDescriptionForSearchMessage(
        channelId: Int64,
        clanId docClanId: Int64
    ) -> Mezon_Api_ChannelDescription? {
        if let channel = allChannels.first(where: { $0.channelID == channelId }) {
            return channel
        }
        let resolvedClanId = docClanId != 0 ? docClanId : clanId
        if let channel = context.account.postbox.resolvedChannelDescription(
            clanId: resolvedClanId,
            channelId: channelId
        ) {
            return channel
        }
        if resolvedClanId != clanId,
            let channel = context.account.postbox.resolvedChannelDescription(
                clanId: clanId,
                channelId: channelId
            )
        {
            return channel
        }
        return nil
    }

    private func resolvedChannelLabel(for document: Mezon_Api_SearchMessageDocument) -> String {
        let documentLabel = nonEmptyChannelLabel(document.channelLabel)
        if !documentLabel.isEmpty { return documentLabel }

        guard let channelId = Int64(document.channelID) else {
            return "Channel"
        }

        if scopedChannelId == channelId {
            let scopedLabel = nonEmptyChannelLabel(scopedChannelLabel)
            if !scopedLabel.isEmpty { return scopedLabel }
        }

        let docClanId = Int64(document.clanID) ?? 0
        if let channel = resolvedChannelDescriptionForSearchMessage(
            channelId: channelId,
            clanId: docClanId
        ) {
            let label = displayLabel(for: channel)
            if !label.isEmpty { return label }
        }

        return "Channel \(channelId)"
    }

    private func channelTabRowMatchesQuery(_ ch: Mezon_Api_ChannelDescription, query: String) -> Bool {
        if ch.channelLabel.lowercased().contains(query) { return true }
        if ch.clanName.lowercased().contains(query) { return true }
        if ch.type == MezonConstants.ChannelType.thread.rawValue, ch.parentID != 0 {
            let parentLabel = parentChannelLabel(forParentId: ch.parentID).lowercased()
            if parentLabel.contains(query) { return true }
        }
        return false
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let baseMemberList: [Mezon_Api_User] = searchableMembers()

        if query.isEmpty {
            filteredMembers = baseMemberList
            filteredDMGroups = []
        } else {
            filteredMembers = baseMemberList.filter { user in
                let nick = (clanNicks[user.id] ?? "").lowercased()
                let displayName = user.displayName.lowercased()
                let username = user.username.lowercased()
                return nick.contains(query) || displayName.contains(query) || username.contains(query)
            }.sorted { a, b in
                scoreMember(a, query: query) > scoreMember(b, query: query)
            }
            if activeFilterOption != nil {
                filteredDMGroups = []
            } else {
                filteredDMGroups = allChannels.filter { ch in
                    guard ch.type == MezonConstants.ChannelType.group.rawValue else { return false }
                    let label = Self.dmGroupDisplayName(for: ch).lowercased()
                    return label.contains(query)
                }
            }
        }

        if query.isEmpty {
            filteredChannels = allChannels.filter { $0.parentID == 0 && Self.isServerChannelInChannelsTab($0) }
        } else {
            filteredChannels = allChannels.filter { ch in
                guard Self.isServerChannelInChannelsTab(ch) else { return false }
                if ch.parentID == 0 {
                    return channelTabRowMatchesQuery(ch, query: query)
                }
                guard ch.type == MezonConstants.ChannelType.thread.rawValue else { return false }
                return channelTabRowMatchesQuery(ch, query: query)
            }
        }

        if !query.isEmpty || filterUser != nil {
            messageCurrentPage = 1
            searchMessages = []
            fetchMessages()
        } else {
            searchMessages = []
            groupedMessages = []
            messageTotalCount = 0
        }

        updateTabCounts()
        reloadSearchTable()
        schedulePrefetchMemberAvatars(filteredMembers)
    }

    private func schedulePrefetchMemberAvatars(_ users: [Mezon_Api_User]) {
        memberAvatarPrefetchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.prefetchMemberAvatarURLs(users)
        }
        memberAvatarPrefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func prefetchMemberAvatarURLs(_ users: [Mezon_Api_User]) {
        for user in users.prefix(56) {
            guard let raw = resolvedMemberAvatarURL(for: user) else { continue }
            let absolute = ImgproxyURL.absoluteResourceURL(from: raw)
            guard !absolute.isEmpty else { continue }
            let proxied = ImgproxyURL.avatarProxyURL(from: absolute, width: 120, height: 120)
            guard let url = URL(string: proxied) else { continue }
            URLSession.shared.dataTask(with: url).resume()
        }
    }

    private func resolvedMemberAvatarURLs(for user: Mezon_Api_User) -> [String] {
        var values: [String] = []
        if let clanAvatar = clanAvatars[user.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !clanAvatar.isEmpty
        {
            values.append(clanAvatar)
        }
        let userAvatar = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userAvatar.isEmpty {
            values.append(userAvatar)
        }
        context.account.postbox.read { tx in
            if let profileAvatar = tx.getProfile(userId: String(user.id))?.avatarUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !profileAvatar.isEmpty
            {
                values.append(profileAvatar)
            }
            if let clanMember = tx.getClanMembers(clanId: clanId).first(where: { $0.userId == user.id }) {
                let memberAvatar = clanMember.userAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !memberAvatar.isEmpty {
                    values.append(memberAvatar)
                }
            }
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func resolvedMemberAvatarURL(for user: Mezon_Api_User) -> String? {
        resolvedMemberAvatarURLs(for: user).first
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
            let resolvedLabel = resolvedChannelLabel(for: msg)
            if let idx = groups.firstIndex(where: { $0.channelId == msg.channelID }) {
                let currentLabel = nonEmptyChannelLabel(groups[idx].channelLabel)
                if currentLabel.isEmpty || currentLabel == "Channel" || currentLabel == "Channel \(msg.channelID)" {
                    groups[idx].channelLabel = resolvedLabel
                }
                groups[idx].messages.append(msg)
            } else {
                groups.append((channelId: msg.channelID, channelLabel: resolvedLabel, messages: [msg]))
            }
        }
        groupedMessages = groups
    }

    private func fetchMessages() {
        guard !isLoadingMessages else { return }
        guard let searchableChannelId = scopedChannelId, searchableChannelId != 0 else {
            searchMessages = []
            groupedMessages = []
            messageTotalCount = 0
            setLoadMoreIndicator(false)
            updateTabCounts()
            if activeTab == .messages {
                reloadSearchTable()
            }
            return
        }
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
                channelFilter.fieldValue = "\(searchableChannelId)"
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

                let isAppend = messageCurrentPage > 1
                let oldSectionCounts = isAppend ? groupedMessages.map { $0.messages.count } : []
                if messageCurrentPage == 1 {
                    searchMessages = response.messages
                } else {
                    searchMessages.append(contentsOf: response.messages)
                }
                messageTotalCount = response.total
                rebuildGroupedMessages()
                isLoadingMessages = false
                setLoadMoreIndicator(false)

                updateTabCounts()
                if activeTab == .messages {
                    if isAppend, !oldSectionCounts.isEmpty {
                        appendMessageRowsIncrementally(oldSectionCounts: oldSectionCounts)
                    } else {
                        self.reloadSearchTable()
                    }
                }
            } catch {
                isLoadingMessages = false
                setLoadMoreIndicator(false)
            }
        }
    }

    private func loadMoreMessages() {
        guard hasMoreMessages, !isLoadingMessages else { return }
        messageCurrentPage += 1
        setLoadMoreIndicator(true)
        fetchMessages()
    }

    private func setLoadMoreIndicator(_ visible: Bool) {
        let tableView = searchNode.tableNode.view
        guard visible else {
            tableView.tableFooterView = nil
            return
        }
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44.sh))
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = UIColor.theme.iconSecondary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        footer.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        tableView.tableFooterView = footer
    }

    private func switchTab(_ tab: SearchTab) {
        activeTab = tab
        searchNode.tabBar.setSelectedTab(tab)
        reloadSearchTable()
        searchNode.tableNode.setContentOffset(.zero, animated: false)

        if activeTab == .messages && searchMessages.isEmpty && !searchQuery.isEmpty {
            fetchMessages()
        }
    }

    private func updateTabCounts() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchNode.tabBar.updateCounts(
            members: filteredMembers.count + filteredDMGroups.count,
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
        messageCurrentPage = 1
        searchMessages = []
        fetchMessages()
        reloadSearchTable()
        searchNode.searchBar.textField.becomeFirstResponder()
    }

    private func clearFilter() {
        activeFilterOption = nil
        filterUser = nil
        isPickingFilterUser = false
        searchNode.tabBar.isHidden = false
        searchNode.searchBar.clearFilterBadge()
        searchNode.setNeedsLayout()
        switchTab(.members)
    }

    private func navigateToMember(_ user: Mezon_Api_User) {
        var sheetUser = user
        if let avatarURL = resolvedMemberAvatarURL(for: user) {
            sheetUser.avatarURL = avatarURL
        }
        let isCurrentUser = "\(sheetUser.id)" == context.currentUser?.id

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: sheetUser,
            context: context,
            isCurrentUser: isCurrentUser,
            clanId: clanId,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            },
            onTransferFunds: { [weak self] payload in
                guard let self else { return }
                let vc = WalletTransferViewController(context: self.context, payload: payload)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        self.presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func navigateToChannel(_ channel: Mezon_Api_ChannelDescription) {
        let targetClanId = effectiveClanId(for: channel)
        context.currentClanId = targetClanId
        persistSelectedChannelForSearchJump(channel)
        context.currentChannel = channel
        ActiveChannelTracker.currentChannelId = channel.channelID
        var parentName: String?
        if channel.type == MezonConstants.ChannelType.thread.rawValue && channel.parentID != 0 {
            parentName =
                allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: targetClanId, channel: channel, context: context, parentName: parentName)
        navigationController?.pushViewController(chatVC, animated: true)
        alignChannelListSidebarAfterSearchJump(clanId: targetClanId, channelId: channel.channelID)
    }

    private func navigateToMessage(_ doc: Mezon_Api_SearchMessageDocument) {
        guard let channelId = Int64(doc.channelID) else { return }
        let docClanId = Int64(doc.clanID) ?? clanId
        let resolvedLabel = resolvedChannelLabel(for: doc)

        let channel: Mezon_Api_ChannelDescription
        if let full = resolvedChannelDescriptionForSearchMessage(channelId: channelId, clanId: docClanId) {
            var resolved = full
            if nonEmptyChannelLabel(resolved.channelLabel).isEmpty {
                resolved.channelLabel = resolvedLabel
            }
            channel = resolved
        } else {
            var minimal = Mezon_Api_ChannelDescription()
            minimal.channelID = channelId
            minimal.channelLabel = resolvedLabel
            minimal.type = doc.channelType
            minimal.clanID = docClanId
            channel = minimal
        }

        let targetClanId = effectiveClanId(for: channel)
        let messageId = doc.messageID

        if let nav = navigationController {
            for vc in nav.viewControllers.reversed() {
                guard let chat = vc as? ChatViewController else { continue }
                if chat.channel.channelID == channelId && chat.clanId == targetClanId {
                    context.currentClanId = targetClanId
                    persistSelectedChannelForSearchJump(channel)
                    context.currentChannel = channel
                    ActiveChannelTracker.currentChannelId = channelId
                    nav.popToViewController(chat, animated: true)
                    DispatchQueue.main.async {
                        chat.jumpToMessageFromChannelDetail(messageId: messageId)
                    }
                    alignChannelListSidebarAfterSearchJump(clanId: targetClanId, channelId: channelId)
                    return
                }
            }
        }

        context.currentClanId = targetClanId
        persistSelectedChannelForSearchJump(channel)
        context.currentChannel = channel
        ActiveChannelTracker.currentChannelId = channelId
        var parentName: String?
        if channel.type == MezonConstants.ChannelType.thread.rawValue && channel.parentID != 0 {
            parentName =
                allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: targetClanId, channel: channel, context: context, parentName: parentName)
        chatVC.pendingJumpToMessageId = messageId
        navigationController?.pushViewController(chatVC, animated: true)
        alignChannelListSidebarAfterSearchJump(clanId: targetClanId, channelId: channelId)
    }

    private func persistSelectedChannelForSearchJump(_ channel: Mezon_Api_ChannelDescription) {
        let cid = effectiveClanId(for: channel)
        guard cid != 0 else { return }
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.selectedChannelId(clanId: cid),
            value: encodeChannelIdPreference(channel.channelID))
    }

    private func alignChannelListSidebarAfterSearchJump(clanId: Int64, channelId: Int64) {
        guard clanId != 0, channelId != 0 else { return }
        NotificationCenter.default.post(
            name: .mezonAlignChannelListAfterSearchJump,
            object: nil,
            userInfo: ["clanId": NSNumber(value: clanId), "channelId": NSNumber(value: channelId)])
    }

    private func effectiveClanId(for channel: Mezon_Api_ChannelDescription) -> Int64 {
        if channel.type == MezonConstants.ChannelType.dm.rawValue || channel.type == MezonConstants.ChannelType.group.rawValue {
            return 0
        }
        return channel.clanID != 0 ? channel.clanID : clanId
    }

    private func encodeChannelIdPreference(_ id: Int64) -> Data {
        var le = id.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    private func persistSelectedChannelForVoice(_ channel: Mezon_Api_ChannelDescription) {
        let cid = effectiveClanId(for: channel)
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.selectedChannelId(clanId: cid),
            value: encodeChannelIdPreference(channel.channelID))
    }

    private func parentChannelName(for channel: Mezon_Api_ChannelDescription) -> String? {
        guard channel.parentID != 0 else { return nil }
        return allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
    }

    private func resolveVoiceMember(uid: String, clanIdForChannel: Int64) -> VoiceMemberDisplay? {
        guard let uidInt = Int64(uid) else { return nil }

        let profile = context.account.postbox.read { $0.getProfile(userId: uid) }

        let member = context.account.postbox.read {
            $0.getClanMembers(clanId: clanIdForChannel)
        }.first(where: { $0.userId == uidInt })

        let name: String
        let username: String
        if let m = member {
            if !m.clanNick.isEmpty {
                name = m.clanNick
            } else if !m.displayName.isEmpty {
                name = m.displayName
            } else if !m.username.isEmpty {
                name = m.username
            } else {
                return nil
            }
            username = m.username
        } else if let profile {
            name = (profile.displayName?.isEmpty == false ? profile.displayName : nil) ?? profile.username
            username = profile.username
        } else {
            return nil
        }

        let avatar: String?
        if let m = member {
            avatar = m.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl)
        } else {
            avatar = profile?.avatarUrl.flatMap { $0.isEmpty ? nil : $0 }
        }

        return VoiceMemberDisplay(name: name, username: username, avatarURL: avatar)
    }

    private func presentJoinVoiceSheet(for channel: Mezon_Api_ChannelDescription) {
        let clanIdForChannel = effectiveClanId(for: channel)
        let title = channel.channelLabel.isEmpty
            ? NSLocalizedString("voiceChannel.defaultName", tableName: nil, bundle: .main, value: "Voice", comment: "")
            : channel.channelLabel

        var voiceUserIds: [String] = []
        let sources: [Mezon_Api_VoiceChannelUserList?] = [
            context.engine.clanData.getVoiceUsers(clanId: clanIdForChannel),
            context.engine.clanData.getStreamUsers(clanId: clanIdForChannel),
        ]
        for list in sources.compactMap({ $0 }) {
            for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !voiceUserIds.contains(uid) {
                    voiceUserIds.append(uid)
                }
            }
        }
        let resolvedMembers = voiceUserIds.compactMap { resolveVoiceMember(uid: $0, clanIdForChannel: clanIdForChannel) }

        let sheet = JoinVoiceChannelSheetViewController(
            channelTitle: title,
            chatUnreadCount: Int(channel.countMessUnread),
            members: resolvedMembers,
            onChat: { [weak self] in self?.pushChatFromVoiceSheet(for: channel) },
            onJoinVoice: { [weak self] role in self?.pushVoiceChannelRoom(for: channel, role: role) },
            onInvite: {}
        )
        sheet.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        if #available(iOS 15.0, *) {
            sheet.sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = JoinVoiceChannelSheetViewController.preferredSheetHeight(
                    safeAreaBottomInset: bottomInset, hasMembers: !resolvedMembers.isEmpty)
                let detentId = JoinVoiceChannelSheetViewController.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { context in
                    min(targetHeight, context.maximumDetentValue)
                }
                sheet.sheetPresentationController?.detents = [contentDetent]
                sheet.sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheet.sheetPresentationController?.detents = [
                    UISheetPresentationController.Detent.medium(),
                    UISheetPresentationController.Detent.large(),
                ]
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        present(sheet, animated: true)
        CATransaction.commit()
    }

    private func pushChatFromVoiceSheet(for channel: Mezon_Api_ChannelDescription) {
        let targetClanId = effectiveClanId(for: channel)
        persistSelectedChannelForVoice(channel)
        context.currentClanId = targetClanId
        var parentName: String?
        if channel.parentID != 0 {
            parentName = allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: targetClanId, channel: channel, context: context, parentName: parentName)
        navigationController?.pushViewController(chatVC, animated: true)
    }

    private func presentJoinStreamSheet(for channel: Mezon_Api_ChannelDescription) {
        let clanIdForChannel = effectiveClanId(for: channel)
        let title = channel.channelLabel.isEmpty
            ? NSLocalizedString("streamingRoom.defaultName", tableName: nil, bundle: .main, value: "Stream", comment: "")
            : channel.channelLabel

        var streamUserIds: [String] = []
        if let list = context.engine.clanData.getStreamUsers(clanId: clanIdForChannel) {
            for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !streamUserIds.contains(uid) {
                    streamUserIds.append(uid)
                }
            }
        }
        let resolvedMembers = streamUserIds.compactMap { resolveVoiceMember(uid: $0, clanIdForChannel: clanIdForChannel) }

        let sheet = JoinVoiceChannelSheetViewController(
            channelTitle: title,
            chatUnreadCount: Int(channel.countMessUnread),
            members: resolvedMembers,
            kind: .streaming,
            onChat: { [weak self] in self?.pushChatFromVoiceSheet(for: channel) },
            onJoinVoice: { [weak self] _ in self?.pushStreamingRoom(for: channel) },
            onInvite: {}
        )
        sheet.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        if #available(iOS 15.0, *) {
            sheet.sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = JoinVoiceChannelSheetViewController.preferredSheetHeight(
                    safeAreaBottomInset: bottomInset, hasMembers: !resolvedMembers.isEmpty)
                let detentId = JoinVoiceChannelSheetViewController.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { context in
                    min(targetHeight, context.maximumDetentValue)
                }
                sheet.sheetPresentationController?.detents = [contentDetent]
                sheet.sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheet.sheetPresentationController?.detents = [
                    UISheetPresentationController.Detent.medium(),
                    UISheetPresentationController.Detent.large(),
                ]
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        present(sheet, animated: true)
        CATransaction.commit()
    }

    private func pushStreamingRoom(for channel: Mezon_Api_ChannelDescription) {
        persistSelectedChannelForVoice(channel)
        context.currentClanId = effectiveClanId(for: channel)
        guard let nav = navigationController else { return }

        let clanId = effectiveClanId(for: channel)
        let pip = StreamingPiPOverlay.shared
        if pip.isActive, pip.channel?.channelID == channel.channelID {
            pip.restoreFullScreen(animated: true)
            return
        }

        if let existing = nav.viewControllers.last(where: {
            ($0 as? StreamingRoomViewController)?.streamChannelId == channel.channelID
        }) {
            StreamingRoomViewController.prepareJoiningStream(
                targetChannelId: channel.channelID,
                clanId: clanId,
                context: context,
                navigationController: nav
            )
            if nav.topViewController !== existing {
                nav.popToViewController(existing, animated: false)
            }
            return
        }

        StreamingRoomViewController.prepareJoiningStream(
            targetChannelId: channel.channelID,
            clanId: clanId,
            context: context,
            navigationController: nav
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken(),
                  let userId = self.context.currentUser?.id,
                  let username = self.context.currentUser?.username else { return }

            await StreamingWebRTCSession.shared.join(
                clanId: self.effectiveClanId(for: channel),
                channelId: channel.channelID,
                streamId: channel.channelID,
                userId: userId,
                username: username,
                token: token
            )

            if let uid = Int64(userId) {
                self.context.engine.clanData.applyStreamJoined(
                    clanId: self.effectiveClanId(for: channel),
                    channelId: channel.channelID,
                    userId: uid
                )
            }

            let vc = StreamingRoomViewController(
                context: self.context,
                channel: channel,
                parentChannelName: self.parentChannelName(for: channel)
            )
            nav.pushViewController(vc, animated: true)
        }
    }

    private func pushVoiceChannelRoom(for channel: Mezon_Api_ChannelDescription, role: SfuRole = .speaker) {
        persistSelectedChannelForVoice(channel)
        context.currentClanId = effectiveClanId(for: channel)
        guard let nav = navigationController else { return }

        let pip = VoiceChannelPiPOverlay.shared
        if pip.isActive {
            if pip.channel?.channelID == channel.channelID {
                let vc = VoiceChannelRoomViewController(
                    context: context, channel: channel,
                    parentChannelName: parentChannelName(for: channel),
                    voiceChannelCrossClanExitAlignClanId: pip.crossClanVoiceExitAlignClanId,
                    existingPiPOverlay: pip)
                nav.pushViewController(vc, animated: true)
                return
            } else {
                pip.dismiss()
            }
        }

        let vc = VoiceChannelRoomViewController(
            context: context, channel: channel,
            parentChannelName: parentChannelName(for: channel),
            joinRole: role)
        nav.pushViewController(vc, animated: true)
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

        return true
    }

    @objc private func searchTextChanged(_ textField: UITextField) {
        if textField.markedTextRange != nil { return }
        searchQuery = textField.text ?? ""

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedSearch), object: nil)
        perform(#selector(debouncedSearch), with: nil, afterDelay: 0.3)
    }

    @objc private func debouncedSearch() {
        performSearch()
    }
}

extension SearchViewController: ASTableDataSource, ASTableDelegate {

    private var membersSectionCount: Int {
        var count = 0
        if !filteredDMGroups.isEmpty { count += 1 }
        count += 1
        return count
    }

    private var dmGroupSection: Int? {
        filteredDMGroups.isEmpty ? nil : 0
    }

    private var membersSection: Int {
        filteredDMGroups.isEmpty ? 0 : 1
    }

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        switch activeTab {
        case .members:
            return membersSectionCount
        case .channels:
            return 1
        case .messages:
            return groupedMessages.isEmpty ? 1 : groupedMessages.count
        }
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        switch activeTab {
        case .members:
            if section == dmGroupSection {
                return filteredDMGroups.count
            }
            let totalItems = filteredMembers.count
            return totalItems == 0 && filteredDMGroups.isEmpty ? 1 : totalItems
        case .channels: return filteredChannels.isEmpty ? 1 : filteredChannels.count
        case .messages:
            if groupedMessages.isEmpty { return 1 }
            guard section < groupedMessages.count else { return 0 }
            return groupedMessages[section].messages.count
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard activeTab == .messages, !groupedMessages.isEmpty, section < groupedMessages.count else { return nil }
        let label = nonEmptyChannelLabel(groupedMessages[section].channelLabel)
        let title = label.isEmpty ? "Channel" : label
        let header = UIView()
        header.backgroundColor = UIColor.theme.primary
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(
            string: "# \(title)",
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
            if indexPath.section == dmGroupSection {
                let ch = filteredDMGroups[row]
                let count = filteredDMGroups.count
                let isFirst = row == 0
                let isLast = row == count - 1
                return { DMGroupSearchCellNode(channel: ch, isFirst: isFirst, isLast: isLast) }
            }
            if filteredMembers.isEmpty {
                return { SearchEmptyCellNode(text: "No members found") }
            }
            let user = filteredMembers[row]
            let nick = clanNicks[user.id]
            let avatarURLs = self.resolvedMemberAvatarURLs(for: user)
            let count = filteredMembers.count
            let isFirst = row == 0
            let isLast = row == count - 1
            return { MemberSearchCellNode(user: user, clanNick: nick, avatarURLs: avatarURLs, isFirst: isFirst, isLast: isLast) }

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
            let senderId = Int64(doc.senderID) ?? 0
            let clanNick = clanNicks[senderId]
            let clanAvatar = clanAvatars[senderId]
            return { MessageSearchCellNode(document: doc, clanNick: clanNick, clanAvatar: clanAvatar, isFirst: isFirst, isLast: isLast) }
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)

        switch activeTab {
        case .members:
            if indexPath.section == dmGroupSection {
                guard indexPath.row < filteredDMGroups.count else { return }
                navigateToChannel(filteredDMGroups[indexPath.row])
                return
            }
            guard indexPath.row < filteredMembers.count else { return }
            if isPickingFilterUser {
                selectFilterUser(filteredMembers[indexPath.row])
                return
            }
            navigateToMember(filteredMembers[indexPath.row])

        case .channels:
            guard indexPath.row < filteredChannels.count else { return }
            let channel = filteredChannels[indexPath.row]
            if channel.type == MezonConstants.ChannelType.mezonVoice.rawValue {
                presentJoinVoiceSheet(for: channel)
                return
            }
            if channel.type == MezonConstants.ChannelType.streaming.rawValue {
                presentJoinStreamSheet(for: channel)
                return
            }
            navigateToChannel(channel)

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
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        let textSize = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 20))
        badgeWidth = textSize.width + 16
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
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        let textSize = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 20))
        badgeWidth = textSize.width + 32
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
            let minTextFieldWidth: CGFloat = 48
            let inner = bounds.width - badgeX - rightPad
            let maxQuarter = bounds.width * 0.25
            let maxBySpace = max(0, inner - 6 - minTextFieldWidth)
            let maxBadgeW = min(maxQuarter, maxBySpace)
            let badgeW = min(badgeWidth, maxBadgeW)
            badge.frame = CGRect(x: badgeX, y: (h - badgeH) / 2, width: badgeW, height: badgeH)
            textField.frame = CGRect(
                x: badgeX + badgeW + 6, y: 0,
                width: bounds.width - badgeX - badgeW - 6 - rightPad, height: h)
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
        setSelectedTab(tab)
        onTabSelected?(tab)
    }

    func setSelectedTab(_ tab: SearchTab) {
        guard tabNodes.contains(where: { $0.tab == tab }) else { return }
        selectedTab = tab
        updateTabAppearance()
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

final class MemberSearchCellNode: ASCellNode, ASNetworkImageNodeDelegate {
    private let avatarBackplate = ASDisplayNode()
    private let avatarPlaceholderNode = ASTextNode2()
    private let avatarNode = ASNetworkImageNode()
    private let statusDotNode = ASDisplayNode()
    private let nameNode = ASTextNode2()
    private let usernameNode = ASTextNode2()
    private let cardNode = ASDisplayNode()
    private let isFirst: Bool
    private let isLast: Bool
    private let hasUsername: Bool
    private let avatarColorSeed: String
    private var avatarURLCandidates: [URL] = []
    private var avatarURLCandidateIndex: Int = 0
    private var avatarURLLoadKey: String = ""

    private static let avatarSize: CGFloat = 40.sf
    private static let margin: CGFloat = 12.sf
    private static let padding: CGFloat = 16.sf
    private static let cellHeight: CGFloat = 60.sh
    private static let radius: CGFloat = 10.sf

    init(
        user: Mezon_Api_User,
        clanNick: String? = nil,
        avatarURLs: [String] = [],
        isFirst: Bool = false,
        isLast: Bool = false
    ) {
        self.isFirst = isFirst
        self.isLast = isLast
        self.hasUsername = !user.username.isEmpty
        self.avatarColorSeed = user.username
        super.init()
        selectionStyle = .none
        let t = UIColor.theme
        backgroundColor = .clear

        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        addSubnode(cardNode)

        let displayName: String
        if let nick = clanNick, !nick.isEmpty {
            displayName = nick
        } else if !user.displayName.isEmpty {
            displayName = user.displayName
        } else {
            displayName = user.username
        }

        avatarBackplate.cornerRadius = Self.avatarSize / 2
        avatarBackplate.clipsToBounds = true
        avatarBackplate.backgroundColor = UIColor.avatarColor(for: avatarColorSeed)

        avatarPlaceholderNode.maximumNumberOfLines = 1

        avatarNode.cornerRadius = Self.avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = .clear
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.shouldRenderProgressImages = false
        avatarNode.delegate = self

        statusDotNode.backgroundColor = user.online
            ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1)
            : UIColor.gray
        statusDotNode.cornerRadius = 6.sf
        statusDotNode.borderWidth = 2.sf
        statusDotNode.borderColor = t.secondary.cgColor

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

        let initialSource = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialChar = initialSource.isEmpty ? "" : String(initialSource.prefix(1)).uppercased()
        let side = Self.avatarSize
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.minimumLineHeight = side
        para.maximumLineHeight = side
        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: initialChar,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
            ]
        )

        var seen = Set<String>()
        avatarURLCandidates = avatarURLs.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            let absolute = ImgproxyURL.absoluteResourceURL(from: trimmed)
            guard !absolute.isEmpty else { return nil }
            let proxied = ImgproxyURL.avatarProxyURL(from: absolute, width: 120, height: 120)
            return URL(string: proxied)
        }
        loadAvatarCandidate(at: 0)

        addSubnode(avatarBackplate)
        addSubnode(avatarPlaceholderNode)
        addSubnode(avatarNode)
        addSubnode(statusDotNode)
        addSubnode(nameNode)
        if hasUsername { addSubnode(usernameNode) }
    }

    private func loadAvatarCandidate(at index: Int) {
        guard index < avatarURLCandidates.count else {
            showAvatarPlaceholder()
            return
        }
        let url = avatarURLCandidates[index]
        avatarURLCandidateIndex = index
        avatarURLLoadKey = url.absoluteString
        avatarNode.url = url
        avatarNode.isHidden = false
        avatarPlaceholderNode.isHidden = true
        avatarBackplate.backgroundColor = .clear
    }

    private func showAvatarPlaceholder() {
        avatarURLLoadKey = ""
        avatarNode.url = nil
        avatarNode.isHidden = true
        avatarPlaceholderNode.isHidden = false
        avatarBackplate.backgroundColor = UIColor.avatarColor(for: avatarColorSeed)
    }

    private func loadNextAvatarCandidateIfKeyMatches(_ key: String) {
        guard !key.isEmpty, key == avatarURLLoadKey else { return }
        let nextIndex = avatarURLCandidateIndex + 1
        if nextIndex < avatarURLCandidates.count {
            loadAvatarCandidate(at: nextIndex)
        } else {
            showAvatarPlaceholder()
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didLoad image: UIImage) {
        guard imageNode === avatarNode else { return }
        if image.size.width < 0.5 || image.size.height < 0.5, let url = imageNode.url {
            loadNextAvatarCandidateIfKeyMatches(url.absoluteString)
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didFailWithError error: Error) {
        guard imageNode === avatarNode, let url = imageNode.url else { return }
        loadNextAvatarCandidateIfKeyMatches(url.absoluteString)
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
        let avatarFrame = CGRect(x: contentX, y: avatarY, width: avatarSz, height: avatarSz)
        avatarBackplate.frame = avatarFrame
        avatarPlaceholderNode.frame = avatarFrame
        avatarNode.frame = avatarFrame

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
        let isDMOrGroup = channel.type == MezonConstants.ChannelType.dm.rawValue
            || channel.type == MezonConstants.ChannelType.group.rawValue
        self.isFirst = isFirst
        self.isLast = isLast
        self.hasClanName = !channel.clanName.isEmpty && !isDMOrGroup
        super.init()
        selectionStyle = .none
        let t = UIColor.theme
        backgroundColor = .clear

        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        addSubnode(cardNode)

        if isDMOrGroup {
            let dmIcon = UIImage(systemName: channel.type == MezonConstants.ChannelType.group.rawValue ? "person.2.fill" : "person.fill")
            iconImgNode.image = dmIcon?.withRenderingMode(.alwaysTemplate)
            iconImgNode.tintColor = t.channelNormal
            iconImgNode.contentMode = .scaleAspectFit
        } else {
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
                } else if chType == .text && channel.ageRestricted == 1 {
                    iconName = "Channel/channelWarning"
                }
            }

            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            iconImgNode.image = image?.withRenderingMode(.alwaysTemplate)
            iconImgNode.tintColor = t.channelNormal
            iconImgNode.contentMode = .scaleAspectFit
        }

        let displayLabel: String
        if isDMOrGroup {
            if !channel.channelLabel.isEmpty {
                displayLabel = channel.channelLabel
            } else if let first = channel.displayNames.first, !first.isEmpty {
                displayLabel = channel.displayNames.joined(separator: ", ")
            } else if let first = channel.usernames.first, !first.isEmpty {
                displayLabel = channel.usernames.joined(separator: ", ")
            } else if !channel.creatorName.isEmpty {
                displayLabel = "\(channel.creatorName)'s Group"
            } else {
                displayLabel = "Chat"
            }
        } else {
            displayLabel = channel.channelLabel
        }

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: displayLabel,
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

    init(document: Mezon_Api_SearchMessageDocument, clanNick: String? = nil, clanAvatar: String? = nil, isFirst: Bool = false, isLast: Bool = false) {
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
        if document.senderID == "\(MezonConstants.anonymousUserId)" {
            avatarNode.contentMode = .scaleAspectFit
            avatarNode.image = Self.anonymousAvatarImage(size: Self.avatarSize)
        } else {
            avatarNode.contentMode = .scaleAspectFill
            let resolvedAvatar = (clanAvatar?.isEmpty == false ? clanAvatar : nil) ?? (document.avatarURL.isEmpty ? nil : document.avatarURL)
            if let resolvedAvatar, let url = URL(string: ImgproxyURL.create(from: resolvedAvatar, width: 150, height: 150)) {
                avatarNode.url = url
            }
        }

        let displayName: String = {
            if let clanNick, !clanNick.isEmpty { return clanNick }
            if !document.displayName.isEmpty { return document.displayName }
            return document.username
        }()
        senderNode.maximumNumberOfLines = 1
        senderNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [.font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold), .foregroundColor: t.textStrong]
        )

        let contentText = MessageContentParser.previewText(fromRawContent: document.content)
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

    private static func anonymousAvatarImage(size: CGFloat) -> UIImage? {
        guard let raw = UIImage(named: "Chat/AnonymousIcon") else { return nil }
        let canvas = CGSize(width: size, height: size)
        let iconSz = CGSize(width: size * 0.55, height: size * 0.55)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let tinted = raw.withRenderingMode(.alwaysTemplate)
                .withTintColor(UIColor.theme.textStrong, renderingMode: .alwaysOriginal)
            let origin = CGPoint(
                x: (canvas.width - iconSz.width) / 2,
                y: (canvas.height - iconSz.height) / 2
            )
            tinted.draw(in: CGRect(origin: origin, size: iconSz))
        }
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

final class DMGroupSearchCellNode: ASCellNode {

    private static let avatarSize: CGFloat = 40.sf
    private static let margin: CGFloat = 12.sf
    private static let padding: CGFloat = 16.sf
    private static let cellHeight: CGFloat = 60.sh
    private static let radius: CGFloat = 10.sf

    private let avatarNode = ASNetworkImageNode()
    private let groupIconNode = ASImageNode()
    private let avatarBackplate = ASDisplayNode()
    private let nameNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()
    private let cardNode = ASDisplayNode()
    private let isFirst: Bool
    private let isLast: Bool
    private let hasCustomAvatar: Bool

    init(channel: Mezon_Api_ChannelDescription, isFirst: Bool = false, isLast: Bool = false) {
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let avatarRaw = channel.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAvatar = !avatarRaw.isEmpty && !avatarRaw.contains("avatar-group.png")
        self.hasCustomAvatar = hasAvatar
        self.isFirst = isFirst
        self.isLast = isLast
        super.init()
        selectionStyle = .none
        let t = UIColor.theme
        backgroundColor = .clear

        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        addSubnode(cardNode)

        avatarBackplate.cornerRadius = Self.avatarSize / 2
        avatarBackplate.clipsToBounds = true

        if hasAvatar {
            avatarBackplate.backgroundColor = .clear
            avatarNode.cornerRadius = Self.avatarSize / 2
            avatarNode.clipsToBounds = true
            avatarNode.contentMode = .scaleAspectFill
            if let url = URL(string: ImgproxyURL.create(from: avatarRaw, width: 150, height: 150)) {
                avatarNode.url = url
            }
            groupIconNode.isHidden = true
        } else {
            avatarBackplate.backgroundColor = .groupDMDefaultAvatar
            groupIconNode.image = UIImage(systemName: "person.2.fill")?.withRenderingMode(.alwaysTemplate)
            groupIconNode.tintColor = .white
            groupIconNode.contentMode = .scaleAspectFit
            avatarNode.isHidden = true
        }

        let displayName = SearchViewController.dmGroupDisplayName(for: channel)
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [.font: UIFont.systemFont(ofSize: 15.sf, weight: .medium), .foregroundColor: t.textStrong]
        )

        let memberCount = max(channel.usernames.count, channel.displayNames.count)
        let subtitle = isGroup && memberCount > 0 ? "\(memberCount) members" : (isGroup ? "Group" : "Direct Message")
        subtitleNode.maximumNumberOfLines = 1
        subtitleNode.attributedText = NSAttributedString(
            string: subtitle,
            attributes: [.font: UIFont.systemFont(ofSize: 13.sf), .foregroundColor: t.textDisabled]
        )

        addSubnode(avatarBackplate)
        addSubnode(avatarNode)
        addSubnode(groupIconNode)
        addSubnode(nameNode)
        addSubnode(subtitleNode)
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
        MemberSearchCellNode.applyCorners(to: cardNode, isFirst: isFirst, isLast: isLast)

        let contentX = m + p
        let avatarY = (bounds.height - avatarSz) / 2
        let avatarFrame = CGRect(x: contentX, y: avatarY, width: avatarSz, height: avatarSz)
        avatarBackplate.frame = avatarFrame
        avatarNode.frame = avatarFrame

        let iconSz: CGFloat = 20.sf
        groupIconNode.frame = CGRect(
            x: avatarFrame.midX - iconSz / 2,
            y: avatarFrame.midY - iconSz / 2,
            width: iconSz, height: iconSz
        )

        let textX = contentX + avatarSz + 12.sf
        let textW = bounds.width - textX - m - p
        let nameSize = nameNode.measure(CGSize(width: textW, height: 20))
        let subSize = subtitleNode.measure(CGSize(width: textW, height: 18))
        let totalH = nameSize.height + 2 + subSize.height
        let textY = (bounds.height - totalH) / 2
        nameNode.frame = CGRect(x: textX, y: textY, width: textW, height: nameSize.height)
        subtitleNode.frame = CGRect(x: textX, y: textY + nameSize.height + 2, width: textW, height: subSize.height)
    }
}
