import UIKit
import SwiftProtobuf

struct ClanListState {
    var clans: [Mezon_Api_ClanDesc]
    var selectedClanId: Int64?
    var isLoading: Bool
    var unreadDMs: [Mezon_Api_ChannelDescription]
    var accountLogoURL: String?

    static let empty = ClanListState(clans: [], selectedClanId: nil, isLoading: false, unreadDMs: [], accountLogoURL: nil)
}

final class ClanListViewController: ViewController {

    private let context: AccountContext
    private let disposables = DisposableSet()

    private let clansPipe = ValuePipe<[Mezon_Api_ClanDesc]>()
    private let selectedClanIdPipe = ValuePipe<Int64?>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let needsReloadPipe = ValuePipe<Void>()
    private let unreadDMsPipe = ValuePipe<[Mezon_Api_ChannelDescription]>()

    private let clansLoadedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var clansLoadedSignal: Signal<Bool, NoError> { clansLoadedPromise.get() }

    private var completedRemoteClanListFetch = false
    private let showDiscoverEmptyOverlayPipe = ValuePipe<Bool>()
    var showDiscoverEmptyOverlaySignal: Signal<Bool, NoError> { showDiscoverEmptyOverlayPipe.signal() }

    var discoverEmptyOverlayShouldShow: Bool {
        completedRemoteClanListFetch && !isLoading && clans.isEmpty
    }

    var selectedClanIdSignal: Signal<Int64?, NoError> { selectedClanIdPipe.signal() }
    var clansSignal: Signal<[Mezon_Api_ClanDesc], NoError> { clansPipe.signal() }

    private(set) var clans: [Mezon_Api_ClanDesc] = []
    private(set) var selectedClanId: Int64?
    private(set) var isLoading: Bool = false
    private(set) var error: String?
    private(set) var unreadDMs: [Mezon_Api_ChannelDescription] = []
    private var processedMentionIds = Set<String>()

    private var debouncedUnreadDmFetchWorkItem: DispatchWorkItem?
    private var clanSidebarLastLayoutSize: CGSize = .zero

    var onLogoTapped: (() -> Void)?
    var onClanSelected: (() -> Void)?
    var onJoinClanTapped: (() -> Void)?
    var onCreateClanTapped: (() -> Void)?

    private var clanListNode: ClanListContainerNode { displayNode as! ClanListContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
        restoreFromPostbox()
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    var selectedClan: Mezon_Api_ClanDesc? {
        clans.first { $0.clanID == selectedClanId }
    }

    override func loadDisplayNode() {
        let interaction = ClanListInteraction(
            onSelectClan: { [weak self] clan in self?.select(clan: clan) },
            onSelectDM: { [weak self] dm in self?.openDirectMessage(dm) },
            onLogoTapped: { [weak self] in self?.onLogoTapped?() },
            onJoinClanTapped: { [weak self] in self?.onJoinClanTapped?() },
            onCreateClanTapped: { [weak self] in self?.onCreateClanTapped?() }
        )
        displayNode = ClanListContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        clanListNode.applyTheme()
        loadClans()
        fetchUnreadDMs()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleChannelMarkedAsRead(_:)),
            name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleNewMessageReceived(_:)),
            name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMentionReceived(_:)),
            name: Notification.Name("MezonMentionReceived"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSocketStatusForClanBadges(_:)),
            name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMezonQRSelectClan(_:)), name: .mezonQRSelectClan,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAccountCurrentUserDidChange),
            name: .mezonAccountCurrentUserDidChange, object: nil)
    }

    @objc private func handleAccountCurrentUserDidChange() {
        needsReloadPipe.putNext(())
    }

    @objc private func handleMezonQRSelectClan(_ notification: Notification) {
        guard let clanIdStr = notification.userInfo?["clanId"] as? String,
            let clanId = Int64(clanIdStr)
        else { return }

        if let clan = clans.first(where: { $0.clanID == clanId }) {
            select(clan: clan)
        } else {
            setSelectedClanId(clanId)
            loadClans()
        }
    }

    @objc private func handleSocketStatusForClanBadges(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool, connected else { return }
        Task { @MainActor in
            await self.refreshClanSidebarBadgesFromSocket()
            self.fetchUnreadDMs()
        }
    }


    @MainActor
    private func refreshClanSidebarBadgesFromSocket() async {
        guard let token = await context.getToken() else {
            return
        }
        do {
            let rows = try await context.account.network.listClanBadgeCount(token: token).listBadge
            guard !rows.isEmpty else {
                return
            }
            var next = clans
            ChannelUnreadBadgeSync.applyClanBadgeRows(to: &next, rows: rows)
            setClans(next)
            persistClanRecordsToPostbox(next)
        } catch {
        }
    }

    private func persistClanRecordsToPostbox(_ sorted: [Mezon_Api_ClanDesc]) {
        let records = sorted.map { api -> ClanRecord in
            let data = (try? api.serializedData()) ?? Data()
            return ClanRecord(id: api.clanID, name: api.clanName, icon: api.logo.isEmpty ? nil : api.logo, ownerId: api.creatorID == 0 ? nil : String(api.creatorID), data: data)
        }
        context.account.postbox.write { tx in tx.updateClans(records) }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        view.layoutIfNeeded()
        clanListNode.updateLayout(layout: layout, transition: transition)
    }

    func focusDiscoverInSidebar() {
        clanListNode.focusDiscoverIfNoClans()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = currentlyAppliedLayout else { return }
        let sz = view.bounds.size
        guard sz != clanSidebarLastLayoutSize else { return }
        clanSidebarLastLayoutSize = sz
        clanListNode.updateLayout(layout: layout, transition: .immediate)
    }

    @objc private func handleThemeChange() { clanListNode.applyTheme() }

    @objc private func handleNewMessageReceived(_ notification: Notification) {
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]),
              let clanId = Self.int64UserInfo(notification.userInfo?["clanId"]) else { return }

        let senderId: String? = {
            let v = notification.userInfo?["senderId"]
            if let s = v as? String { return s }
            if let n = v as? Int64 { return String(n) }
            if let n = v as? Int { return String(n) }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }()
        guard let senderId else { return }

        guard senderId != context.currentUser?.id else { return }

        if clanId != 0 {
            if let data = notification.userInfo?["serializedChannelMessage"] as? Data,
               let m = try? Mezon_Api_ChannelMessage(serializedBytes: data)
            {
                var topicId = Self.int64UserInfo(notification.userInfo?["topicId"]) ?? 0
                if topicId == 0, m.topicID != 0 { topicId = m.topicID }
                if topicId != 0, ActiveChannelTracker.currentChannelId == topicId { return }
                if topicId == 0, ActiveChannelTracker.currentChannelId == channelId { return }
                if topicId != 0,
                   Self.checkMessageMentionsUser(
                    m, currentUserId: context.currentUser?.id,
                    currentUserRoleIds: Self.getCurrentUserRoleIds(context: context))
                {
                    let mid = String(m.messageID)
                    let dedup: String
                    if !mid.isEmpty, mid != "0" { dedup = "\(topicId)_\(mid)" }
                    else { dedup = "\(topicId)_\(m.createTimeSeconds)" }
                    guard !processedMentionIds.contains(dedup) else { return }
                    processedMentionIds.insert(dedup)
                    if processedMentionIds.count > 500 { processedMentionIds.removeAll() }
                    for i in 0..<clans.count {
                        if clans[i].clanID == clanId { clans[i].badgeCount += 1 }
                    }
                    clansPipe.putNext(clans)
                    persistClanRecordsToPostbox(clans)
                    needsReloadPipe.putNext(())
                }
            }
            return
        }

        guard (notification.userInfo?["incrementDmBadge"] as? Bool) == true else { return }

        let ts: UInt32
        if let t = notification.userInfo?["timestampSeconds"] as? UInt32 { ts = t }
        else if let t = notification.userInfo?["timestampSeconds"] as? Int { ts = UInt32(t) }
        else { ts = UInt32(Date().timeIntervalSince1970) }

        if let idx = unreadDMs.firstIndex(where: { $0.channelID == channelId }) {
            unreadDMs[idx].countMessUnread += 1
            var header = unreadDMs[idx].lastSentMessage
            header.timestampSeconds = ts
            unreadDMs[idx].lastSentMessage = header
            unreadDMsPipe.putNext(unreadDMs)
            needsReloadPipe.putNext(())
            return
        }

        if var ch = context.account.postbox.getDMChannelDescription(channelId: channelId) {
            ch.countMessUnread = max(1, ch.countMessUnread + 1)
            var header = ch.lastSentMessage
            header.timestampSeconds = ts
            ch.lastSentMessage = header
            var next = unreadDMs
            next.append(ch)
            next.sort { a, b in
                let ta = a.hasLastSentMessage ? a.lastSentMessage.timestampSeconds : 0
                let tb = b.hasLastSentMessage ? b.lastSentMessage.timestampSeconds : 0
                return ta > tb
            }
            setUnreadDMs(next)
            scheduleFetchUnreadDMsDebounced()
            return
        }

        fetchUnreadDMs()
    }

    private func scheduleFetchUnreadDMsDebounced() {
        debouncedUnreadDmFetchWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.fetchUnreadDMs()
        }
        debouncedUnreadDmFetchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    @objc private func handleMentionReceived(_ notification: Notification) {
        guard let clanId = Self.int64UserInfo(notification.userInfo?["clanId"]) else { return }
        guard clanId != 0 else { return }
        let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]) ?? 0

        if notification.userInfo?["isParentOfTopic"] as? Bool == true { return }

        let messageId = notification.userInfo?["messageId"] as? String ?? ""
        let ts = notification.userInfo?["timestampSeconds"]
        let dedupKey: String
        if !messageId.isEmpty, messageId != "0" {
            dedupKey = "\(channelId)_\(messageId)"
        } else {
            dedupKey = "\(channelId)_\(ts ?? 0)"
        }
        guard !processedMentionIds.contains(dedupKey) else { return }
        processedMentionIds.insert(dedupKey)
        if processedMentionIds.count > 500 {
            processedMentionIds.removeAll()
        }

        for i in 0..<clans.count {
            if clans[i].clanID == clanId {
                clans[i].badgeCount += 1
            }
        }
        clansPipe.putNext(clans)
        persistClanRecordsToPostbox(clans)
        needsReloadPipe.putNext(())
    }

    @objc private func handleChannelMarkedAsRead(_ notification: Notification) {
        guard let clanId = notification.userInfo?["clanId"] as? Int64 else { return }
        let channelId = notification.userInfo?["channelId"] as? Int64

        if clanId != 0 {
            let channelUnread = (notification.userInfo?["channelUnreadCount"] as? Int32) ?? 0
            var changed = false
            for i in 0..<clans.count {
                if clans[i].clanID == clanId {
                    if channelUnread > 0 {
                        clans[i].badgeCount = max(0, clans[i].badgeCount - channelUnread)
                        changed = true
                    }
                }
            }
            if changed {
                clansPipe.putNext(clans)
                persistClanRecordsToPostbox(clans)
            }
        }

        if let channelId = channelId {
            let before = unreadDMs.count
            unreadDMs.removeAll { $0.channelID == channelId }
            if unreadDMs.count != before {
                unreadDMsPipe.putNext(unreadDMs)
            }
        }

        needsReloadPipe.putNext(())
    }

    deinit {
        debouncedUnreadDmFetchWorkItem?.cancel()
        disposables.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    private func setClans(_ v: [Mezon_Api_ClanDesc]) {
        clans = v
        clansPipe.putNext(v)
        needsReloadPipe.putNext(())
        refreshDiscoverEmptyOverlayFlag()
    }
    private func setSelectedClanId(_ v: Int64?) { selectedClanId = v; selectedClanIdPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) {
        isLoading = v
        isLoadingPipe.putNext(v)
        needsReloadPipe.putNext(())
        refreshDiscoverEmptyOverlayFlag()
    }
    private func setUnreadDMs(_ v: [Mezon_Api_ChannelDescription]) { unreadDMs = v; unreadDMsPipe.putNext(v); needsReloadPipe.putNext(()) }

    private func refreshDiscoverEmptyOverlayFlag() {
        let show = completedRemoteClanListFetch && !isLoading && clans.isEmpty
        showDiscoverEmptyOverlayPipe.putNext(show)
    }

    func loadClans() {
        setIsLoading(true)
        error = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                self.completedRemoteClanListFetch = false
                self.setIsLoading(false)
                if !self.clans.isEmpty {
                    self.clansLoadedPromise.set(true)
                }
                return
            }
            defer { self.setIsLoading(false) }
            do {
                let result = try await self.context.account.network.listClanDescs(token: token)
                let sorted = result.sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID }
                let records = sorted.map { api -> ClanRecord in
                    let data = (try? api.serializedData()) ?? Data()
                    return ClanRecord(id: api.clanID, name: api.clanName, icon: api.logo.isEmpty ? nil : api.logo, ownerId: api.creatorID == 0 ? nil : String(api.creatorID), data: data)
                }
                self.context.account.postbox.write { tx in tx.replaceAllClans(records) }
                self.completedRemoteClanListFetch = true
                self.setClans(sorted)
                if sorted.isEmpty {
                    self.setSelectedClanId(nil)
                    self.context.currentClanId = 0
                    UserDefaults.standard.removeObject(forKey: Self.selectedClanIdUserDefaultsKey)
                    self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedClanId, value: Data())
                    self.persistToPostbox()
                } else if let sid = self.selectedClanId, sid != 0, sorted.contains(where: { $0.clanID == sid }) {
                    self.setSelectedClanId(sid)
                    self.context.currentClanId = sid
                    self.persistToPostbox()
                    self.fetchClanData(clanId: sid)
                } else if let first = sorted.first {
                    self.setSelectedClanId(first.clanID)
                    self.context.currentClanId = first.clanID
                    self.persistToPostbox()
                    self.fetchClanData(clanId: first.clanID)
                }
                self.clansLoadedPromise.set(true)
                Task { @MainActor in
                    await self.refreshClanSidebarBadgesFromSocket()
                }
            } catch {
                self.completedRemoteClanListFetch = true
                self.error = error.localizedDescription
                if !self.clans.isEmpty {
                    self.clansLoadedPromise.set(true)
                    if let sid = self.selectedClanId, sid != 0, self.clans.contains(where: { $0.clanID == sid }) {
                        self.fetchClanData(clanId: sid)
                    }
                }
            }
        }
    }

    func select(clan: Mezon_Api_ClanDesc) {
        onClanSelected?()
        context.currentClanId = clan.clanID
        setSelectedClanId(clan.clanID)
        context.account.socket.joinClanChat(clanId: clan.clanID)
        persistToPostbox()
        fetchClanData(clanId: clan.clanID)
    }

    func openDirectMessage(_ dm: Mezon_Api_ChannelDescription) {
        let vc = ChatViewController(clanId: 0, channel: dm, context: context, parentName: nil)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func applyUnreadDMsFromCache() {
        let cached = context.account.postbox.getCachedDMChannelList()
        let unread = cached.filter { $0.countMessUnread > 0 }
        guard !unread.isEmpty else { return }
        let merged = Self.mergeUnreadDmStrip(serverUnread: unread, previousStrip: unreadDMs)
        setUnreadDMs(merged)
    }

    func fetchUnreadDMs() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                self.applyUnreadDMsFromCache()
                return
            }
            do {
                var channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                do {
                    let badgeRows = try await self.context.account.network.listChannelBadgeCount(clanId: 0, token: token)
                        .channeldesc
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &channels, badgeRows: badgeRows)
                } catch {
                }
                let unread = channels.filter { $0.countMessUnread > 0 }

                let merged = Self.mergeUnreadDmStrip(serverUnread: unread, previousStrip: self.unreadDMs)
                self.setUnreadDMs(merged)
            } catch {
                self.applyUnreadDMsFromCache()
            }
        }
    }


    private static func mergeUnreadDmStrip(serverUnread: [Mezon_Api_ChannelDescription], previousStrip: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
        let prevCount = Dictionary(uniqueKeysWithValues: previousStrip.map { ($0.channelID, $0.countMessUnread) })
        guard !prevCount.isEmpty else { return serverUnread }
        var result = serverUnread
        for i in result.indices {
            let id = result[i].channelID
            if let p = prevCount[id] {
                result[i].countMessUnread = max(result[i].countMessUnread, p)
            }
        }
        return result
    }

    private func fetchClanData(clanId: Int64) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            self.context.engine.clanData.fetchAllClanData(clanId: clanId, token: token)
        }
    }

    private static func int64UserInfo(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    static func getCurrentUserRoleIds(context: AccountContext) -> Set<Int64> {
        let clanId = context.currentClanId
        guard clanId != 0 else { return [] }
        guard let roleList = context.engine.clanData.getUserPermissions(clanId: clanId) else { return [] }
        return Set(roleList.roles.map { $0.id })
    }


    static func checkMessageMentionsUser(
        _ message: Mezon_Api_ChannelMessage,
        currentUserId: String?,
        currentUserRoleIds: Set<Int64>
    ) -> Bool {
        guard let currentUserId, !currentUserId.isEmpty else { return false }


        if let mentionList = try? Mezon_Api_MessageMentionList(serializedBytes: message.mentions) {
            for mention in mentionList.mentions {

                if mention.userID != 0, "\(mention.userID)" == ChatMessageDisplay.mentionHereUserId {
                    return true
                }

                if mention.userID != 0, "\(mention.userID)" == currentUserId {
                    return true
                }

                if mention.roleID != 0, currentUserRoleIds.contains(mention.roleID) {
                    return true
                }
            }
        }


        if let refList = try? Mezon_Api_MessageRefList(serializedBytes: message.references) {
            for ref in refList.refs {
                if ref.messageSenderID != 0, "\(ref.messageSenderID)" == currentUserId {
                    return true
                }
            }
        }

        return false
    }

    private static let selectedClanIdUserDefaultsKey = "mezon_selectedClanId"

    private func syncClanDescsToClanTable(_ apiClans: [Mezon_Api_ClanDesc]) {
        guard !apiClans.isEmpty else { return }
        let records = apiClans.map { api -> ClanRecord in
            let data = (try? api.serializedData()) ?? Data()
            return ClanRecord(
                id: api.clanID,
                name: api.clanName,
                icon: api.logo.isEmpty ? nil : api.logo,
                ownerId: api.creatorID == 0 ? nil : String(api.creatorID),
                data: data
            )
        }
        context.account.postbox.writeSync { tx in tx.updateClans(records) }
    }

    private func restoreFromPostbox() {
        let records = self.context.account.postbox.read { tx in tx.getClans() }
        if !records.isEmpty {
            let apiClans = records.compactMap { record -> Mezon_Api_ClanDesc? in
                guard !record.data.isEmpty else {
                    var desc = Mezon_Api_ClanDesc(); desc.clanID = record.id; desc.clanName = record.name; return desc
                }
                return try? Mezon_Api_ClanDesc(serializedBytes: record.data)
            }.sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID }
            setClans(apiClans)
        } else if let data = self.context.account.postbox.getPreferenceData(key: PreferencesKeys.clans) {
            let sorted = decodeProtoArray(data).sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID }
            syncClanDescsToClanTable(sorted)
            setClans(sorted)
        }

        var restoredId: Int64 = 0
        let udValue = UserDefaults.standard.integer(forKey: Self.selectedClanIdUserDefaultsKey)
        if udValue != 0 {
            restoredId = Int64(udValue)
        } else if let selData = self.context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedClanId), selData.count >= 8 {
            restoredId = selData.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
        }

        if restoredId != 0, clans.contains(where: { $0.clanID == restoredId }) {
            setSelectedClanId(restoredId)
            context.currentClanId = restoredId
        }

        if selectedClanId == nil, let first = clans.first?.clanID {
            setSelectedClanId(first)
            context.currentClanId = first
        }

        if !clans.isEmpty {
            clansLoadedPromise.set(true)
        }
    }

    private func persistToPostbox() {
        self.context.account.postbox.setPreferenceData(key: PreferencesKeys.clans, value: encodeProtoArray(clans))
        if let id = selectedClanId, id != 0 {
            UserDefaults.standard.set(Int(id), forKey: Self.selectedClanIdUserDefaultsKey)
            var le = id.littleEndian
            self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedClanId, value: withUnsafeBytes(of: &le) { Data($0) })
        }
    }

    var currentState: ClanListState {
        ClanListState(
            clans: clans,
            selectedClanId: selectedClanId,
            isLoading: isLoading,
            unreadDMs: unreadDMs,
            accountLogoURL: context.currentUser?.accountLogoURL
        )
    }

    func stateSignal() -> Signal<ClanListState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)

            let postboxDisposable = (self.context.account.postbox.clanListView() |> deliverOnMainQueue).start(next: { [weak self] view in
                    guard let self else { return }
                    let mapped = view.clans.compactMap { record -> Mezon_Api_ClanDesc? in
                        guard !record.data.isEmpty else {
                        var desc = Mezon_Api_ClanDesc(); desc.clanID = record.id; desc.clanName = record.name; return desc
                        }
                        return try? Mezon_Api_ClanDesc(serializedBytes: record.data)
                }.sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID }
                    if mapped.isEmpty, !self.clans.isEmpty {
                        subscriber.putNext(self.currentState)
                        return
                    }
                    self.clans = mapped
                    subscriber.putNext(self.currentState)
                })
            let reloadDisposable = (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
            return ActionDisposable { postboxDisposable.dispose(); reloadDisposable.dispose() }
        }
    }

    private func encodeProtoArray(_ items: [Mezon_Api_ClanDesc]) -> Data {
        var result = Data()
        var count = UInt32(items.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for item in items {
            if let d = try? item.serializedData() {
                var len = UInt32(d.count)
                result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                result.append(d)
            }
        }
        return result
    }

    private func decodeProtoArray(_ data: Data) -> [Mezon_Api_ClanDesc] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [Mezon_Api_ClanDesc] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ClanDesc(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) { result.append(m) }
            offset += Int(len)
        }
        return result
    }
}
