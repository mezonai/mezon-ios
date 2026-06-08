import AsyncDisplayKit
import UIKit

final class ThreadListViewController: ViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let parentChannelId: Int64
    private let parentCategoryId: Int64
    private let parentChannelLabel: String
    private let composerParentChannel: Mezon_Api_ChannelDescription

    private let headerBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let addButton = UIButton(type: .system)

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBarContainer = UIView()
    private let searchField = UITextField()
    private let searchClearButton = UIButton(type: .system)
    private var refreshControl = UIRefreshControl()

    private var allThreads: [Mezon_Api_ChannelDescription] = []
    private var searchResults: [Mezon_Api_ChannelDescription] = []
    private var searchText: String = ""
    private var isLoading = false
    private var searchWorkItem: DispatchWorkItem?

    private var displaySections: [(title: String, threads: [Mezon_Api_ChannelDescription])] = []

    private var cachedClanMembersList: [ClanMemberRecord]?

    private static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
    private static let joinedStatus: Int32 = 1
    private static let activePublicStatus: Int32 = 2
    private static let activePrivateStatus: Int32 = 3
    private static let threadsPageLimit: Int32 = 50
    private static let threadsMaxPages: Int32 = 40

    init(
        context: AccountContext,
        clanId: Int64,
        parentChannelId: Int64,
        parentCategoryId: Int64,
        parentChannelLabel: String,
        composerParentChannel: Mezon_Api_ChannelDescription
    ) {
        self.context = context
        self.clanId = clanId
        self.parentChannelId = parentChannelId
        self.parentCategoryId = parentCategoryId
        self.parentChannelLabel = parentChannelLabel
        self.composerParentChannel = composerParentChannel
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ASDisplayNode()
        displayNode.backgroundColor = UIColor.theme.primary
        displayNodeDidLoad()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavHeader()
        configureSearchHeader()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.backgroundColor = UIColor.theme.primary
        tableView.separatorStyle = .none
        tableView.separatorColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.tableFooterView = UIView(frame: .zero)
        if #available(iOS 15.0, *) { tableView.sectionHeaderTopPadding = 0 }
        tableView.estimatedRowHeight = 76
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(ThreadListItemCell.self, forCellReuseIdentifier: ThreadListItemCell.reuseId)
        tableView.register(ThreadListEmptyCell.self, forCellReuseIdentifier: ThreadListEmptyCell.reuseId)
        refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 56),

            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleChannelDescriptionDidUpdate(_:)),
            name: .mezonChannelDescriptionDidUpdate, object: nil)

        applyCachedThreadsIfAny()
        rebuildSections()
        tableView.reloadData()
        fetchThreadsFromNetwork(showSpinner: allThreads.isEmpty)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleThemeChange() {
        displayNode.backgroundColor = UIColor.theme.primary
        tableView.backgroundColor = UIColor.theme.primary
        applyNavHeaderTheme()
        applySearchBarTheme()
        tableView.reloadData()
    }

    private static func int64UserInfo(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        guard let updatedClanId = Self.int64UserInfo(notification.userInfo?["clanId"]),
              updatedClanId == clanId,
              let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]),
              channelId != 0 else {
            return
        }

        let candidates = cachedThreadChannelsFromChannelCaches()
        guard var updated = candidates.first(where: { $0.channelID == channelId })
                ?? context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channelId) else {
            return
        }

        let existing = allThreads.first(where: { $0.channelID == channelId })
        if updated.parentID == 0, let existing {
            updated.parentID = existing.parentID
        }
        guard updated.parentID == parentChannelId || existing != nil else { return }

        allThreads = Self.filterPrivateThreads(Self.mergeThreads([updated], withFallback: allThreads))
        if !searchText.isEmpty {
            searchResults = Self.sortedByLastActivity(
                allThreads.filter {
                    $0.channelLabel.lowercased().contains(searchText)
                }
            )
        }
        cachedClanMembersList = nil
        persistThreadsCache()
        rebuildSections()
        tableView.reloadData()
    }

    private func setupNavHeader() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBar)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.accessibilityLabel = "Back"
        headerBar.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = L(L10n.Channel.thread)
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        headerBar.addSubview(titleLabel)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(createThreadTapped), for: .touchUpInside)
        addButton.accessibilityLabel = "Add thread"
        headerBar.addSubview(addButton)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            addButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -4),
            addButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 44),
            addButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -8),
        ])

        applyNavHeaderTheme()
    }

    private func applyNavHeaderTheme() {
        let t = UIColor.theme
        headerBar.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        addButton.tintColor = t.textStrong
        backButton.setImage(
            UIImage(systemName: "chevron.left")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal)
        addButton.setImage(
            UIImage(systemName: "plus")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal)
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let w = tableView.bounds.width
        guard w > 0, header.frame.width != w else { return }
        var f = header.frame
        f.size.width = w
        header.frame = f
        tableView.tableHeaderView = header
    }

    private func configureSearchHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 78))
        header.backgroundColor = .clear

        searchBarContainer.translatesAutoresizingMaskIntoConstraints = false
        searchBarContainer.layer.cornerRadius = 12
        searchBarContainer.clipsToBounds = true
        header.addSubview(searchBarContainer)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = L(L10n.ThreadList.searchPlaceholder)
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .search
        searchField.font = .systemFont(ofSize: 16)
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchBarContainer.addSubview(searchField)

        searchClearButton.translatesAutoresizingMaskIntoConstraints = false
        searchClearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        searchClearButton.isHidden = true
        searchClearButton.setImage(
            UIImage(systemName: "xmark.circle.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)),
            for: .normal)
        searchBarContainer.addSubview(searchClearButton)

        NSLayoutConstraint.activate([
            searchBarContainer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            searchBarContainer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            searchBarContainer.topAnchor.constraint(equalTo: header.topAnchor, constant: 18),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 50),

            searchField.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: searchClearButton.leadingAnchor, constant: -4),
            searchField.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor),

            searchClearButton.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor, constant: -10),
            searchClearButton.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchClearButton.widthAnchor.constraint(equalToConstant: 32),
            searchClearButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        header.frame.size.height = 78
        tableView.tableHeaderView = header
        applySearchBarTheme()
    }

    private func applySearchBarTheme() {
        let t = UIColor.theme
        searchBarContainer.backgroundColor = t.secondary
        searchField.textColor = t.text
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ThreadList.searchPlaceholder),
            attributes: [.foregroundColor: t.textDisabled]
        )
        searchClearButton.tintColor = t.text
    }

    @objc private func clearSearchTapped() {
        searchField.text = ""
        searchClearButton.isHidden = true
        searchText = ""
        searchResults = []
        rebuildSections()
        tableView.reloadData()
    }

    @objc private func createThreadTapped() {
        let form = CreateThreadFormViewController(
            context: context,
            clanId: clanId,
            parentChannelId: parentChannelId,
            parentCategoryId: parentCategoryId,
            parentChannelLabel: parentChannelLabel,
            composerParentChannel: composerParentChannel,
            onComplete: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let channel):
                    Toast.success(L(L10n.ThreadList.createThreadSuccess))
                    fetchThreadsFromNetwork(showSpinner: false)
                    context.currentClanId = clanId
                    let vc = ChatViewController(clanId: clanId, channel: channel, context: context)
                    navigationController?.pushViewController(vc, animated: true)
                case .failure:
                    break
                }
            }
        )
        let nav = UINavigationController(rootViewController: form)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    @objc private func pulledToRefresh() {
        fetchThreadsFromNetwork(showSpinner: false)
    }

    @objc private func searchTextChanged() {
        let text = searchField.text ?? ""
        searchClearButton.isHidden = text.isEmpty
        searchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.searchText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if self.searchText.isEmpty {
                    self.searchResults = []
                    self.rebuildSections()
                    self.tableView.reloadData()
                } else {
                    await self.runThreadSearch()
                }
            }
        }
        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @MainActor
    private func runThreadSearch() async {
        guard !searchText.isEmpty else { return }
        guard let token = await context.getToken() else { return }
        do {
            let list = try await context.account.network.searchThread(
                clanId: clanId,
                parentChannelId: parentChannelId,
                label: searchText,
                token: token
            )
            searchResults = Self.sortedByLastActivity(Self.filterPrivateThreads(list.channeldesc))
            rebuildSections()
            tableView.reloadData()
        } catch {
        }
    }

    private func applyCachedThreadsIfAny() {
        var cachedThreads: [Mezon_Api_ChannelDescription] = []
        guard let data = context.account.postbox.getPreferenceData(
            key: PreferencesKeys.threadList(clanId: clanId, parentChannelId: parentChannelId)
        ) else {
            cachedThreads = cachedThreadChannelsFromChannelCaches()
            if !cachedThreads.isEmpty {
                allThreads = Self.sortedByLastActivity(Self.filterPrivateThreads(cachedThreads))
                cachedClanMembersList = nil
            }
            return
        }
        if let decoded = Self.decodeThreadListCache(data) {
            cachedThreads = decoded.channels
        }
        let merged = Self.mergeThreads(
            cachedThreadChannelsFromChannelCaches(),
            withFallback: cachedThreads
        )
        if !merged.isEmpty {
            allThreads = Self.filterPrivateThreads(merged)
            cachedClanMembersList = nil
        }
    }

    private func persistThreadsCache() {
        let data = Self.encodeThreadListCache(allThreads)
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.threadList(clanId: clanId, parentChannelId: parentChannelId),
            value: data
        )
    }

    private func fetchThreadsFromNetwork(showSpinner: Bool) {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            defer {
                self.isLoading = false
                self.refreshControl.endRefreshing()
            }
            guard let token = await self.context.getToken() else { return }
            do {
                var accumulated: [Mezon_Api_ChannelDescription] = []
                var seenChannelIds = Set<Int64>()
                var page: Int32 = 1
                while page <= Self.threadsMaxPages {
                    let list = try await self.context.account.network.listThreadDescs(
                        parentChannelId: self.parentChannelId,
                        clanId: self.clanId,
                        page: page,
                        limit: Self.threadsPageLimit,
                        token: token
                    )
                    let seenBeforePage = seenChannelIds.count
                    for ch in list.channeldesc where seenChannelIds.insert(ch.channelID).inserted {
                        accumulated.append(ch)
                    }
                    if list.channeldesc.count < Int(Self.threadsPageLimit) { break }
                    if seenChannelIds.count == seenBeforePage { break }
                    page += 1
                }
                let merged = Self.mergeThreads(
                    accumulated,
                    withFallback: self.cachedThreadChannelsFromChannelCaches()
                )
                self.allThreads = Self.filterPrivateThreads(merged)
                self.cachedClanMembersList = nil
                self.persistThreadsCache()
                self.rebuildSections()
                self.tableView.reloadData()
            } catch {
            }
        }
    }

    private func rebuildSections() {
        if !searchText.isEmpty {
            let title = sectionTitle(
                count: searchResults.count,
                singular: L(L10n.ThreadList.searchThread),
                plural: L(L10n.ThreadList.searchThreads)
            )
            displaySections = searchResults.isEmpty ? [] : [(title, searchResults)]
            return
        }

        let grouped = Self.groupThreads(allThreads)
        let joined = grouped.joined
        let active = grouped.active
        let older = grouped.older

        var sections: [(String, [Mezon_Api_ChannelDescription])] = []
        if !joined.isEmpty {
            sections.append((
                sectionTitle(
                    count: joined.count,
                    singular: L(L10n.ThreadList.joinedThread),
                    plural: L(L10n.ThreadList.joinedThreads)
                ),
                joined
            ))
        }
        if !active.isEmpty {
            sections.append((
                sectionTitle(
                    count: active.count,
                    singular: L(L10n.ThreadList.otherActiveThread),
                    plural: L(L10n.ThreadList.otherActiveThreads)
                ),
                active
            ))
        }
        if !older.isEmpty {
            sections.append((
                sectionTitle(
                    count: older.count,
                    singular: L(L10n.ThreadList.olderThread),
                    plural: L(L10n.ThreadList.olderThreads)
                ),
                older
            ))
        }
        displaySections = sections
    }

    private func sectionTitle(count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private static func filterPrivateThreads(_ threads: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
        threads.filter { ch in
            if ch.channelPrivate != 0 {
                return ch.active == joinedStatus || ch.active == activePrivateStatus
            }
            return true
        }
    }

    private static func sortedByLastActivity(_ threads: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
        threads.sorted { a, b in
            let ta = Int64(activityTimestamp(a) ?? 0)
            let tb = Int64(activityTimestamp(b) ?? 0)
            if ta == tb {
                return String(a.channelID) < String(b.channelID)
            }
            return ta > tb
        }
    }

    private static func groupThreads(_ threads: [Mezon_Api_ChannelDescription])
        -> (joined: [Mezon_Api_ChannelDescription], active: [Mezon_Api_ChannelDescription], older: [Mezon_Api_ChannelDescription])
    {
        let now = Date().timeIntervalSince1970
        var joined: [Mezon_Api_ChannelDescription] = []
        var active: [Mezon_Api_ChannelDescription] = []
        var older: [Mezon_Api_ChannelDescription] = []

        for ch in sortedByLastActivity(threads) {
            if isJoinedThread(ch), isRecentThread(ch, now: now) {
                joined.append(ch)
            } else if ch.channelPrivate == 0, ch.active == activePublicStatus, isRecentThread(ch, now: now) {
                active.append(ch)
            } else {
                older.append(ch)
            }
        }

        return (joined, active, older)
    }

    private static func isJoinedThread(_ ch: Mezon_Api_ChannelDescription) -> Bool {
        ch.active == joinedStatus || (ch.channelPrivate != 0 && ch.active == activePrivateStatus)
    }

    private static func isRecentThread(_ ch: Mezon_Api_ChannelDescription, now: TimeInterval) -> Bool {
        guard let ts = activityTimestamp(ch) else { return false }
        return now - TimeInterval(ts) < thirtyDays
    }

    private static func activityTimestamp(_ ch: Mezon_Api_ChannelDescription) -> UInt32? {
        if ch.hasLastSentMessage, ch.lastSentMessage.timestampSeconds > 0 {
            return ch.lastSentMessage.timestampSeconds
        }
        if ch.createTimeSeconds > 0 { return ch.createTimeSeconds }
        if ch.updateTimeSeconds > 0 { return ch.updateTimeSeconds }
        return nil
    }

    private static func mergeThreads(
        _ primary: [Mezon_Api_ChannelDescription],
        withFallback fallback: [Mezon_Api_ChannelDescription]
    ) -> [Mezon_Api_ChannelDescription] {
        var byId: [Int64: Mezon_Api_ChannelDescription] = [:]

        func upsert(_ incoming: Mezon_Api_ChannelDescription) {
            guard incoming.channelID != 0 else { return }
            if let existing = byId[incoming.channelID] {
                byId[incoming.channelID] = mergeThread(existing, with: incoming)
            } else {
                byId[incoming.channelID] = incoming
            }
        }

        fallback.forEach(upsert)
        primary.forEach(upsert)
        return sortedByLastActivity(Array(byId.values))
    }

    private static func mergeThread(
        _ existing: Mezon_Api_ChannelDescription,
        with incoming: Mezon_Api_ChannelDescription
    ) -> Mezon_Api_ChannelDescription {
        var result = incoming
        if result.clanID == 0 { result.clanID = existing.clanID }
        if result.parentID == 0 { result.parentID = existing.parentID }
        if result.categoryID == 0 { result.categoryID = existing.categoryID }
        if result.type == 0 { result.type = existing.type }
        if result.channelLabel.isEmpty { result.channelLabel = existing.channelLabel }
        if result.active == 0 { result.active = existing.active }
        if result.channelPrivate == 0,
           existing.channelPrivate != 0,
           result.active == activePrivateStatus {
            result.channelPrivate = existing.channelPrivate
        }
        if result.createTimeSeconds == 0 { result.createTimeSeconds = existing.createTimeSeconds }
        if result.updateTimeSeconds == 0 { result.updateTimeSeconds = existing.updateTimeSeconds }

        if shouldUseFallbackLastMessage(result, fallback: existing) {
            result.lastSentMessage = existing.lastSentMessage
        }
        if !result.hasLastSeenMessage, existing.hasLastSeenMessage {
            result.lastSeenMessage = existing.lastSeenMessage
        }
        return result
    }

    private static func shouldUseFallbackLastMessage(
        _ result: Mezon_Api_ChannelDescription,
        fallback: Mezon_Api_ChannelDescription
    ) -> Bool {
        guard fallback.hasLastSentMessage else { return false }
        if !result.hasLastSentMessage { return true }
        return fallback.lastSentMessage.timestampSeconds > result.lastSentMessage.timestampSeconds
    }

    private func cachedThreadChannelsFromChannelCaches() -> [Mezon_Api_ChannelDescription] {
        var candidates: [Mezon_Api_ChannelDescription] = []
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) {
            candidates.append(contentsOf: ChannelPreferenceListCodec.decode(data))
        }
        if let allChannelsByUser = context.engine.clanData.getAllChannelsByUser()?.channeldesc {
            candidates.append(contentsOf: allChannelsByUser)
        }
        return Self.mergeThreads(
            Self.threadChildren(candidates, parentChannelId: parentChannelId, clanId: clanId),
            withFallback: []
        )
    }

    private static func threadChildren(
        _ channels: [Mezon_Api_ChannelDescription],
        parentChannelId: Int64,
        clanId: Int64
    ) -> [Mezon_Api_ChannelDescription] {
        channels.filter { ch in
            ch.parentID == parentChannelId
                && ch.channelID != 0
                && (ch.clanID == 0 || ch.clanID == clanId)
        }
    }

    private static func encodeThreadListCache(_ channels: [Mezon_Api_ChannelDescription]) -> Data {
        var result = Data()
        var ts = Date().timeIntervalSince1970
        result.append(contentsOf: withUnsafeBytes(of: &ts) { Array($0) })
        var count = UInt32(channels.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for ch in channels {
            if let d = try? ch.serializedData() {
                var len = UInt32(d.count)
                result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                result.append(d)
            }
        }
        return result
    }

    private static func decodeThreadListCache(_ data: Data) -> (channels: [Mezon_Api_ChannelDescription], fetchedAt: TimeInterval)? {
        guard data.count >= 8 + 4 else { return nil }
        let fetchedAt = data.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: TimeInterval.self) }
        let count = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 12
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return (result, fetchedAt)
    }

    private static func previewText(from header: Mezon_Api_ChannelMessageHeader) -> String {
        let raw = header.content
        guard let d = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = obj["t"] as? String
        else {
            return raw.isEmpty ? " " : raw
        }
        return t
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func formatTime(_ header: Mezon_Api_ChannelMessageHeader) -> String {
        guard header.timestampSeconds > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(header.timestampSeconds))
        return relativeTimeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func clanMembersListCached() -> [ClanMemberRecord] {
        if let c = cachedClanMembersList { return c }
        let list = context.account.postbox.read { $0.getClanMembers(clanId: clanId) }
        cachedClanMembersList = list
        return list
    }

    private func senderDisplayNameForPreview(senderId: Int64) -> String {
        guard senderId != 0 else { return "" }
        if let m = clanMembersListCached().first(where: { $0.userId == senderId }) {
            if !m.clanNick.isEmpty { return m.clanNick }
            if !m.displayName.isEmpty { return m.displayName }
            if !m.username.isEmpty { return m.username }
        }
        if let cur = context.currentUser, cur.id == String(senderId) {
            if !cur.displayName.isEmpty { return cur.displayName }
            if !cur.username.isEmpty { return cur.username }
        }
        let uid = String(senderId)
        if let p = context.account.postbox.read({ $0.getProfile(userId: uid) }) {
            if let dn = p.displayName, !dn.isEmpty { return dn }
            if !p.username.isEmpty { return p.username }
        }
        return ""
    }
}

private enum ThreadCardPosition {
    case single, first, middle, last

    static func resolve(row: Int, count: Int) -> ThreadCardPosition {
        if count <= 1 { return .single }
        if row == 0 { return .first }
        if row == count - 1 { return .last }
        return .middle
    }
}

private final class ThreadListEmptyCell: UITableViewCell {

    static let reuseId = "ThreadListEmptyCell"

    private let stackView = UIStackView()
    private let iconCircleView = UIView()
    private let iconImageView = UIImageView()
    private let iconSlashOne = UIView()
    private let iconSlashTwo = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let createButton = UIButton(type: .system)

    var onCreateThread: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)
        layoutMargins = .zero
        preservesSuperviewLayoutMargins = false
        selectionStyle = .none

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        iconCircleView.translatesAutoresizingMaskIntoConstraints = false
        iconCircleView.layer.cornerRadius = 28
        iconCircleView.clipsToBounds = true

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconCircleView.addSubview(iconImageView)

        [iconSlashOne, iconSlashTwo].forEach { slash in
            slash.translatesAutoresizingMaskIntoConstraints = false
            slash.layer.cornerRadius = 1.5
            slash.transform = CGAffineTransform(rotationAngle: -.pi / 7)
            iconCircleView.addSubview(slash)
        }

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.adjustsFontForContentSizeCategory = true

        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.layer.cornerRadius = 26
        createButton.clipsToBounds = true
        createButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)

        stackView.addArrangedSubview(iconCircleView)
        stackView.setCustomSpacing(22, after: iconCircleView)
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(10, after: titleLabel)
        stackView.addArrangedSubview(descriptionLabel)
        stackView.setCustomSpacing(32, after: descriptionLabel)
        stackView.addArrangedSubview(createButton)

        let top = stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 126)
        top.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 32),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -32),
            top,

            iconCircleView.widthAnchor.constraint(equalToConstant: 56),
            iconCircleView.heightAnchor.constraint(equalToConstant: 56),

            iconImageView.centerXAnchor.constraint(equalTo: iconCircleView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconCircleView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            iconSlashOne.centerXAnchor.constraint(equalTo: iconCircleView.centerXAnchor, constant: -4),
            iconSlashOne.centerYAnchor.constraint(equalTo: iconCircleView.centerYAnchor, constant: -1),
            iconSlashOne.widthAnchor.constraint(equalToConstant: 3.5),
            iconSlashOne.heightAnchor.constraint(equalToConstant: 15),

            iconSlashTwo.centerXAnchor.constraint(equalTo: iconCircleView.centerXAnchor, constant: 5),
            iconSlashTwo.centerYAnchor.constraint(equalTo: iconCircleView.centerYAnchor, constant: -1),
            iconSlashTwo.widthAnchor.constraint(equalToConstant: 3.5),
            iconSlashTwo.heightAnchor.constraint(equalToConstant: 15),

            descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 330),

            createButton.widthAnchor.constraint(equalToConstant: 156),
            createButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        onCreateThread = nil
    }

    func configure() {
        let t = UIColor.theme
        iconCircleView.backgroundColor = t.iconPrimary.withAlphaComponent(0.14)
        iconImageView.image = UIImage(systemName: "bubble.left.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        )
        iconImageView.tintColor = t.textDisabled
        iconSlashOne.backgroundColor = .white
        iconSlashTwo.backgroundColor = .white

        titleLabel.text = L(L10n.ThreadList.emptyTitle)
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = t.textStrong

        descriptionLabel.text = L(L10n.ThreadList.emptyDescription)
        descriptionLabel.font = .systemFont(ofSize: 15, weight: .regular)
        descriptionLabel.textColor = t.textDisabled

        createButton.setTitle(L(L10n.ThreadList.createThreadButton), for: .normal)
        createButton.backgroundColor = t.iconPrimary
        createButton.setTitleColor(.white, for: .normal)
    }

    @objc private func createTapped() {
        onCreateThread?()
    }
}

private final class ThreadListItemCell: UITableViewCell {

    static let reuseId = "ThreadListItemCell"

    private let cardView = UIView()
    private let topHairline = UIView()
    private let nameLabel = UILabel()
    private let senderLabel = UILabel()
    private let messageLabel = UILabel()
    private let bulletLabel = UILabel()
    private let timeLabel = UILabel()
    private let chevronView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        topHairline.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(topHairline)

        nameLabel.numberOfLines = 1

        senderLabel.numberOfLines = 1
        messageLabel.numberOfLines = 1
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bulletLabel.text = "•"
        bulletLabel.textAlignment = .center

        timeLabel.numberOfLines = 1
        timeLabel.textAlignment = .natural
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let leftPreviewStack = UIStackView(arrangedSubviews: [senderLabel, messageLabel])
        leftPreviewStack.axis = .horizontal
        leftPreviewStack.spacing = 0
        leftPreviewStack.alignment = .center

        let rightTimeStack = UIStackView(arrangedSubviews: [bulletLabel, timeLabel])
        rightTimeStack.axis = .horizontal
        rightTimeStack.spacing = 6
        rightTimeStack.alignment = .center
        rightTimeStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let previewRow = UIStackView(arrangedSubviews: [leftPreviewStack, UIView(), rightTimeStack])
        previewRow.axis = .horizontal
        previewRow.spacing = 0
        previewRow.alignment = .center

        let col = UIStackView(arrangedSubviews: [nameLabel, previewRow])
        col.axis = .vertical
        col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.contentMode = .scaleAspectFit

        let row = UIStackView(arrangedSubviews: [col, chevronView])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(row)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: cardView.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            topHairline.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            topHairline.heightAnchor.constraint(equalToConstant: 1.0 / max(UIScreen.main.scale, 1)),

            row.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),

            chevronView.widthAnchor.constraint(equalToConstant: 24),
            chevronView.heightAnchor.constraint(equalToConstant: 24),

            leftPreviewStack.widthAnchor.constraint(lessThanOrEqualTo: previewRow.widthAnchor, multiplier: 0.65),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        thread: Mezon_Api_ChannelDescription,
        position: ThreadCardPosition,
        senderDisplay: String,
        preview: String,
        time: String
    ) {
        let t = UIColor.theme
        cardView.backgroundColor = t.secondary
        topHairline.backgroundColor = t.borderDim
        topHairline.isHidden = (position == .first || position == .single)

        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.textColor = t.textStrong
        senderLabel.font = .systemFont(ofSize: 14, weight: .medium)
        senderLabel.textColor = t.textDisabled
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = t.textDisabled
        bulletLabel.font = .systemFont(ofSize: 17, weight: .medium)
        bulletLabel.textColor = t.textDisabled
        timeLabel.font = .systemFont(ofSize: 14, weight: .medium)
        timeLabel.textColor = t.textDisabled

        nameLabel.text = thread.channelLabel
        if senderDisplay.isEmpty {
            senderLabel.text = nil
            senderLabel.isHidden = true
        } else {
            senderLabel.isHidden = false
            senderLabel.text = "\(senderDisplay): "
        }
        messageLabel.text = preview
        bulletLabel.isHidden = time.isEmpty
        timeLabel.text = time

        chevronView.image = UIImage(systemName: "chevron.right")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        chevronView.tintColor = t.textDisabled

        cardView.layer.masksToBounds = true
        switch position {
        case .single:
            cardView.layer.cornerRadius = 8
            cardView.layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
            ]
        case .first:
            cardView.layer.cornerRadius = 8
            cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .middle:
            cardView.layer.cornerRadius = 0
            cardView.layer.maskedCorners = []
        case .last:
            cardView.layer.cornerRadius = 8
            cardView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
    }
}

extension ThreadListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        if displaySections.isEmpty { return 1 }
        return displaySections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if displaySections.isEmpty { return 1 }
        return displaySections[section].threads.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !displaySections.isEmpty, section < displaySections.count else { return nil }
        let wrap = UIView()
        wrap.backgroundColor = .clear
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = displaySections[section].title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = UIColor.theme.text
        label.numberOfLines = 0
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -10),
        ])
        return wrap
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        displaySections.isEmpty ? 0.01 : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        40
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard displaySections.isEmpty else { return UITableView.automaticDimension }
        let headerHeight = tableView.tableHeaderView?.bounds.height ?? 0
        return max(420, tableView.bounds.height - headerHeight)
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard !displaySections.isEmpty else { return nil }
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        displaySections.isEmpty ? 0 : 10
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !displaySections.isEmpty, indexPath.section < displaySections.count else {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ThreadListEmptyCell.reuseId,
                for: indexPath
            ) as? ThreadListEmptyCell else {
                return UITableViewCell()
            }
            cell.configure()
            cell.onCreateThread = { [weak self] in
                self?.createThreadTapped()
            }
            return cell
        }

        let threads = displaySections[indexPath.section].threads
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ThreadListItemCell.reuseId, for: indexPath) as? ThreadListItemCell else {
            return UITableViewCell()
        }
        guard indexPath.row < threads.count else { return cell }

        let thread = threads[indexPath.row]
        let pos = ThreadCardPosition.resolve(row: indexPath.row, count: threads.count)
        let preview: String
        let sender: String
        let time: String
        if thread.hasLastSentMessage {
            let h = thread.lastSentMessage
            preview = Self.previewText(from: h)
            sender = senderDisplayNameForPreview(senderId: h.senderID)
            time = Self.formatTime(h)
        } else {
            preview = ""
            sender = ""
            time = ""
        }
        cell.configure(thread: thread, position: pos, senderDisplay: sender, preview: preview, time: time)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !displaySections.isEmpty,
              indexPath.section < displaySections.count,
              indexPath.row < displaySections[indexPath.section].threads.count
        else { return }

        var thread = displaySections[indexPath.section].threads[indexPath.row]
        if thread.clanID == 0 { thread.clanID = clanId }
        context.currentClanId = clanId
        let chat = ChatViewController(
            clanId: clanId,
            channel: thread,
            context: context,
            parentName: parentChannelLabel
        )
        navigationController?.pushViewController(chat, animated: true)
    }
}

extension ThreadListViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
