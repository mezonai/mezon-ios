import UIKit
import SwiftProtobuf

struct ClanListState {
    var clans: [Mezon_Api_ClanDesc]
    var selectedClanId: Int64?
    var isLoading: Bool
    var unreadDMs: [Mezon_Api_ChannelDescription]

    static let empty = ClanListState(clans: [], selectedClanId: nil, isLoading: false, unreadDMs: [])
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

    var selectedClanIdSignal: Signal<Int64?, NoError> { selectedClanIdPipe.signal() }
    var clansSignal: Signal<[Mezon_Api_ClanDesc], NoError> { clansPipe.signal() }

    private(set) var clans: [Mezon_Api_ClanDesc] = []
    private(set) var selectedClanId: Int64?
    private(set) var isLoading: Bool = false
    private(set) var error: String?
    private(set) var unreadDMs: [Mezon_Api_ChannelDescription] = []

    var onLogoTapped: (() -> Void)?

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
            onLogoTapped: { [weak self] in self?.onLogoTapped?() }
        )
        displayNode = ClanListContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        clanListNode.applyTheme()
        loadClans()
        fetchUnreadDMs()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMarkedAsRead(_:)), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewMessageReceived(_:)), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMentionReceived(_:)), name: Notification.Name("MezonMentionReceived"), object: nil)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        clanListNode.updateLayout(layout: layout, transition: transition)
    }

    @objc private func handleThemeChange() { clanListNode.applyTheme() }

    @objc private func handleNewMessageReceived(_ notification: Notification) {
        guard let channelId = notification.userInfo?["channelId"] as? Int64,
              let clanId = notification.userInfo?["clanId"] as? Int64 else { return }

        let senderId: String
        if let s = notification.userInfo?["senderId"] as? String { senderId = s }
        else if let n = notification.userInfo?["senderId"] as? Int64 { senderId = String(n) }
        else { return }

        guard senderId != context.currentUser?.id else { return }
        guard clanId == 0 else { return }

        if let idx = unreadDMs.firstIndex(where: { $0.channelID == channelId }) {
            unreadDMs[idx].countMessUnread += 1
        }
        unreadDMsPipe.putNext(unreadDMs)
        needsReloadPipe.putNext(())
    }

    @objc private func handleMentionReceived(_ notification: Notification) {
        guard let clanId = notification.userInfo?["clanId"] as? Int64 else { return }
        guard clanId != 0 else { return }

        for i in 0..<clans.count {
            if clans[i].clanID == clanId {
                clans[i].badgeCount += 1
            }
        }
        clansPipe.putNext(clans)
        needsReloadPipe.putNext(())
    }

    @objc private func handleChannelMarkedAsRead(_ notification: Notification) {
        guard let clanId = notification.userInfo?["clanId"] as? Int64 else { return }
        let channelId = notification.userInfo?["channelId"] as? Int64

        if clanId != 0 {
            let channelUnread = (notification.userInfo?["channelUnreadCount"] as? Int32) ?? 0
            if channelUnread > 0 {
                for i in 0..<clans.count {
                    if clans[i].clanID == clanId {
                        clans[i].badgeCount = max(0, clans[i].badgeCount - channelUnread)
                    }
                }
                clansPipe.putNext(clans)
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

    deinit { disposables.dispose() }

    private func setClans(_ v: [Mezon_Api_ClanDesc]) { clans = v; clansPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setSelectedClanId(_ v: Int64?) { selectedClanId = v; selectedClanIdPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setUnreadDMs(_ v: [Mezon_Api_ChannelDescription]) { unreadDMs = v; unreadDMsPipe.putNext(v); needsReloadPipe.putNext(()) }

    func loadClans() {
        setIsLoading(true)
        error = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { self.setIsLoading(false); return }
            defer { self.setIsLoading(false) }
            do {
                let result = try await self.context.account.network.listClanDescs(token: token)
                let sorted = result.sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID }
                let records = sorted.map { api -> ClanRecord in
                    let data = (try? api.serializedData()) ?? Data()
                    return ClanRecord(id: api.clanID, name: api.clanName, icon: api.logo.isEmpty ? nil : api.logo, ownerId: api.creatorID == 0 ? nil : String(api.creatorID), data: data)
                }
                self.context.account.postbox.write { tx in tx.updateClans(records) }
                self.setClans(sorted)
                if let sid = self.selectedClanId, sid != 0, sorted.contains(where: { $0.clanID == sid }) {
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
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func select(clan: Mezon_Api_ClanDesc) {
        setSelectedClanId(clan.clanID)
        context.currentClanId = clan.clanID
        persistToPostbox()
        fetchClanData(clanId: clan.clanID)
    }

    func openDirectMessage(_ dm: Mezon_Api_ChannelDescription) {
        let vc = ChatViewController(clanId: 0, channel: dm, context: context, parentName: nil)
        navigationController?.pushViewController(vc, animated: true)
    }

    func fetchUnreadDMs() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            do {
                let channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                let unread = channels.filter { $0.countMessUnread > 0 }
                self.setUnreadDMs(unread)
            } catch {
                AppLogger.network.error("fetchUnreadDMs: \(error)")
            }
        }
    }

    private func fetchClanData(clanId: Int64) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            self.context.engine.clanData.fetchAllClanData(clanId: clanId, token: token)
        }
    }

    private static let selectedClanIdUserDefaultsKey = "mezon_selectedClanId"

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
            setClans(decodeProtoArray(data).sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID })
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
        ClanListState(clans: clans, selectedClanId: selectedClanId, isLoading: isLoading, unreadDMs: unreadDMs)
    }

    func stateSignal() -> Signal<ClanListState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)

            let postboxDisposable = (self.context.account.postbox.clanListView() |> deliverOnMainQueue).start(next: { [weak self] view in
                guard let self else { return }
                self.clans = view.clans.compactMap { record -> Mezon_Api_ClanDesc? in
                    guard !record.data.isEmpty else {
                        var desc = Mezon_Api_ClanDesc(); desc.clanID = record.id; desc.clanName = record.name; return desc
                    }
                    return try? Mezon_Api_ClanDesc(serializedBytes: record.data)
                }.sorted { $0.clanOrder != $1.clanOrder ? $0.clanOrder < $1.clanOrder : $0.clanID < $1.clanID }
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
