import UIKit
import SwiftProtobuf

struct ClanListState {
    var clans: [Mezon_Api_ClanDesc]
    var selectedClanId: Int64?
    var isLoading: Bool

    static let empty = ClanListState(clans: [], selectedClanId: nil, isLoading: false)
}

final class ClanListViewController: ViewController {

    private let context: AccountContext
    private let disposables = DisposableSet()

    private let clansPipe = ValuePipe<[Mezon_Api_ClanDesc]>()
    private let selectedClanIdPipe = ValuePipe<Int64?>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let needsReloadPipe = ValuePipe<Void>()

    var selectedClanIdSignal: Signal<Int64?, NoError> { selectedClanIdPipe.signal() }
    var clansSignal: Signal<[Mezon_Api_ClanDesc], NoError> { clansPipe.signal() }

    private(set) var clans: [Mezon_Api_ClanDesc] = []
    private(set) var selectedClanId: Int64?
    private(set) var isLoading: Bool = false
    private(set) var error: String?

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
            onLogoTapped: { [weak self] in self?.onLogoTapped?() }
        )
        displayNode = ClanListContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        clanListNode.applyTheme()
        loadClans()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        clanListNode.updateLayout(layout: layout, transition: transition)
    }

    @objc private func handleThemeChange() { clanListNode.applyTheme() }

    deinit { disposables.dispose() }

    private func setClans(_ v: [Mezon_Api_ClanDesc]) { clans = v; clansPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setSelectedClanId(_ v: Int64?) { selectedClanId = v; selectedClanIdPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }

    func loadClans() {
        guard let token = context.session?.token else { return }
        setIsLoading(true)
        error = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.setIsLoading(false) }
            do {
                let result = try await self.context.account.network.listClanDescs(token: token)
                let sorted = result.sorted { $0.clanOrder < $1.clanOrder }
                let records = sorted.map { api -> ClanRecord in
                    let data = (try? api.serializedData()) ?? Data()
                    return ClanRecord(id: api.clanID, name: api.clanName, icon: api.logo.isEmpty ? nil : api.logo, ownerId: api.creatorID == 0 ? nil : String(api.creatorID), data: data)
                }
                self.context.account.postbox.write { tx in tx.updateClans(records) }
                if self.selectedClanId == nil { self.setSelectedClanId(sorted.first?.clanID) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func select(clan: Mezon_Api_ClanDesc) {
        setSelectedClanId(clan.clanID)
        persistToPostbox()
    }

    private func restoreFromPostbox() {
        let records = self.context.account.postbox.read { tx in tx.getClans() }
        if !records.isEmpty {
            let apiClans = records.compactMap { record -> Mezon_Api_ClanDesc? in
                guard !record.data.isEmpty else {
                    var desc = Mezon_Api_ClanDesc(); desc.clanID = record.id; desc.clanName = record.name; return desc
                }
                return try? Mezon_Api_ClanDesc(serializedBytes: record.data)
            }.sorted { $0.clanOrder < $1.clanOrder }
            setClans(apiClans)
        } else if let data = self.context.account.postbox.getPreferenceData(key: PreferencesKeys.clans) {
            setClans(decodeProtoArray(data).sorted { $0.clanOrder < $1.clanOrder })
        }
        if let selData = self.context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedClanId), selData.count >= 8 {
            setSelectedClanId(selData.withUnsafeBytes { $0.load(as: Int64.self).littleEndian })
        }
        if selectedClanId == nil { setSelectedClanId(clans.first?.clanID) }
    }

    private func persistToPostbox() {
        self.context.account.postbox.setPreferenceData(key: PreferencesKeys.clans, value: encodeProtoArray(clans))
        if let id = selectedClanId {
            var le = id.littleEndian
            self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedClanId, value: withUnsafeBytes(of: &le) { Data($0) })
        }
    }

    var currentState: ClanListState {
        ClanListState(clans: clans, selectedClanId: selectedClanId, isLoading: isLoading)
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
                }.sorted { $0.clanOrder < $1.clanOrder }
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
