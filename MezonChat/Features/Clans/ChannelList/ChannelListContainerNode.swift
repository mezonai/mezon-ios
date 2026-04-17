import AsyncDisplayKit
import UIKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onLongPressChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
    let onRefresh: (() -> Void)?
    let onPresentSettings: (() -> Void)?
    let onSearchTapped: (() -> Void)?
    let onQRTapped: (() -> Void)?
    let onSelectChannelApp: ((Mezon_Api_ChannelAppResponse) -> Void)?
}

final class ChannelListContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    private let headerUIView = ChannelListHeaderView()
    private let bannerView = ChannelBannerView()
    private let headerSpacer = UIView()
    private var stickyTopOffset: CGFloat = 0
    private let headerH: CGFloat = 120.sh
    private var channelApps: [Mezon_Api_ChannelAppResponse] = []
    private var isChannelAppsExpanded = true
    private var hasChannelAppsSection: Bool { !channelApps.isEmpty }
    private let compactViewThreshold = 3
    private var isCompactView: Bool { channelApps.count <= compactViewThreshold }
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0, y: 0)
        gl.endPoint = CGPoint(x: 1, y: 1)
        gl.locations = [0.2, 0.4, 0.7, 0.9] as [NSNumber]
        return gl
    }()

    private var state: ChannelListState = .empty
    private var threadLookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]

    private var cachedRows: [Int: [ChannelListRow]] = [:]

    private var cachedHeaders: [Int: CategorySectionHeaderView] = [:]

    private var committedSectionCount: Int = 0
    private let interaction: ChannelListInteraction
    private let disposables = DisposableSet()
    private var isClanSwitching = false

    private var clanLogoURL: String = ""
    private var isCommunity: Bool = false
    private var memberCount: Int = 0
    private var onlineCount: Int = 0

    private let newUnreadButton: UIButton = {
        let b = UIButton(type: .system)
        let raw = NSLocalizedString("channel_list_new_unread", tableName: nil, bundle: .main, value: "NEW", comment: "")
        b.setTitle("@\(raw)".uppercased(), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor.mezonUnreadBadge
        b.layer.cornerRadius = 8.swh
        b.clipsToBounds = true
        b.contentEdgeInsets = UIEdgeInsets(top: 5.sh, left: 8.sw, bottom: 5.sh, right: 8.sw)
        b.isHidden = true
        return b
    }()

    var voiceMemberResolver: ((String) -> VoiceMemberDisplay?)?

    init(signal: Signal<ChannelListState, NoError>, interaction: ChannelListInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        super.init()
        backgroundColor = UIColor.theme.secondary
        
        headerUIView.onQRTapped = { [weak self] in
            self?.interaction.onQRTapped?()
        }

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prevState = self.state

                if let msg = newState.errorMessage, msg != prevState.errorMessage {

                }

                let wasClanSwitching = self.isClanSwitching
                self.isClanSwitching = false
                self.state = newState
                self.threadLookup = buildThreadLookup(newState.allChannels)
                self.cachedRows = [:]

                let prevCats = prevState.categories
                let newCats = newState.categories
                let loadingPHNow = newState.isLoading && newState.categories.isEmpty
                let loadingPHWas = prevState.isLoading && prevState.categories.isEmpty
                let loadingPlaceholderToggled = loadingPHNow != loadingPHWas
                let structureChanged = loadingPlaceholderToggled
                    || prevCats.count != newCats.count
                    || zip(prevCats, newCats).contains(where: {
                        $0.id != $1.id || $0.isCollapsed != $1.isCollapsed || $0.channels.count != $1.channels.count
                            || ($0.favoriteFlatChannels?.count ?? 0) != ($1.favoriteFlatChannels?.count ?? 0)
                    })

                if wasClanSwitching {
                    self.cachedHeaders = [:]
                    self.applyCrossfadeReload()
                } else if structureChanged {
                    self.cachedHeaders = [:]
                    self.applyBatchStructureUpdate(prev: prevState, new: newState)
                } else if !newCats.isEmpty {
                    self.applyRowDiff(prev: prevState, new: newState)
                }

                if !newState.isLoading,
                   let selectedId = newState.selectedChannelId,
                   selectedId != prevState.selectedChannelId {
                    self.scrollToChannel(channelId: selectedId, animated: !wasClanSwitching)
                }
                self.refreshNewUnreadButton()
            })
        )
    }

    private func safeReloadData() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadData()
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
        committedSectionCount = totalSections
    }

    private func applyCrossfadeReload() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadData()
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        tableNode.view.contentOffset = .zero
        CATransaction.commit()
        committedSectionCount = totalSections
        updateStickyHeaderPosition()
    }

    private func applyBatchStructureUpdate(prev: ChannelListState, new: ChannelListState) {
        let expectedAfter = totalSections

        guard committedSectionCount == tableNode.numberOfSections else {
            safeReloadData()
            return
        }

        let sectionOffset = hasChannelAppsSection ? 1 : 0
        let prevCatSections = committedSectionCount - sectionOffset
        let newCatSections = expectedAfter - sectionOffset
        let canPatch = prevCatSections == newCatSections
            && prevCatSections == prev.categories.count
            && newCatSections == new.categories.count
            && zip(prev.categories, new.categories).allSatisfy({ $0.id == $1.id })

        guard canPatch else {
            safeReloadData()
            return
        }

        var sectionsToReload = IndexSet()
        var rowsToInsert: [IndexPath] = []
        var rowsToDelete: [IndexPath] = []
        var rowsToReload: [IndexPath] = []

        for i in 0..<newCatSections {
            let pc = prev.categories[i]
            let nc = new.categories[i]
            let section = i + sectionOffset


            if pc.isCollapsed != nc.isCollapsed {
                sectionsToReload.insert(section)
                continue
            }

            let oldRows = computeRows(for: prev, categoryIndex: i)
            let newRows = rowsForSection(i)

            let oldKeys = oldRows.map { Self.rowDiffKey($0) }
            let newKeys = newRows.map { Self.rowDiffKey($0) }

            if oldKeys == newKeys {
                for (r, row) in newRows.enumerated() {
                    if channelRowDataChanged(
                        old: oldRows[r], new: row,
                        prevSelected: prev.selectedChannelId,
                        newSelected: new.selectedChannelId,
                        prevVoice: prev.voiceUsersByChannel,
                        newVoice: new.voiceUsersByChannel
                    ) {
                        rowsToReload.append(IndexPath(row: r, section: section))
                    }
                }
                continue
            }

            let oldKeySet = Set(oldKeys)
            let newKeySet = Set(newKeys)

            let commonOld = oldKeys.filter { newKeySet.contains($0) }
            let commonNew = newKeys.filter { oldKeySet.contains($0) }
            if commonOld != commonNew {
                sectionsToReload.insert(section)
                continue
            }

            for (r, key) in oldKeys.enumerated() where !newKeySet.contains(key) {
                rowsToDelete.append(IndexPath(row: r, section: section))
            }
            for (r, key) in newKeys.enumerated() where !oldKeySet.contains(key) {
                rowsToInsert.append(IndexPath(row: r, section: section))
            }

            var oldRowLookup: [String: ChannelListRow] = [:]
            for row in oldRows { oldRowLookup[Self.rowDiffKey(row)] = row }
            for (newR, newRow) in newRows.enumerated() {
                let key = Self.rowDiffKey(newRow)
                guard let oldRow = oldRowLookup[key] else { continue }
                if channelRowDataChanged(
                    old: oldRow, new: newRow,
                    prevSelected: prev.selectedChannelId,
                    newSelected: new.selectedChannelId,
                    prevVoice: prev.voiceUsersByChannel,
                    newVoice: new.voiceUsersByChannel
                ) {
                    rowsToReload.append(IndexPath(row: newR, section: section))
                }
            }
        }

        let filteredInsert = rowsToInsert.filter { !sectionsToReload.contains($0.section) }
        let filteredDelete = rowsToDelete.filter { !sectionsToReload.contains($0.section) }
        var seenReload = Set<IndexPath>()
        let filteredReload = rowsToReload.filter { !sectionsToReload.contains($0.section) && seenReload.insert($0).inserted }

        let hasChanges = !sectionsToReload.isEmpty || !filteredInsert.isEmpty
            || !filteredDelete.isEmpty || !filteredReload.isEmpty
        if hasChanges {
            let rowAnim = UITableView.RowAnimation.none
            let sortedDeletes = filteredDelete.sorted {
                if $0.section != $1.section { return $0.section > $1.section }
                return $0.row > $1.row
            }
            let sortedInserts = filteredInsert.sorted {
                if $0.section != $1.section { return $0.section < $1.section }
                return $0.row < $1.row
            }
            tableNode.performBatch(animated: false) {
                if !sortedDeletes.isEmpty {
                    self.tableNode.deleteRows(at: sortedDeletes, with: rowAnim)
                }
                if !sortedInserts.isEmpty {
                    self.tableNode.insertRows(at: sortedInserts, with: rowAnim)
                }
                if !sectionsToReload.isEmpty {
                    self.tableNode.reloadSections(sectionsToReload, with: rowAnim)
                }
            }
            tableNode.waitUntilAllUpdatesAreProcessed()

            if !filteredReload.isEmpty {
                let validReloads = filteredReload.filter { ip in
                    ip.section < self.tableNode.numberOfSections
                        && ip.row < self.tableNode.numberOfRows(inSection: ip.section)
                }
                if !validReloads.isEmpty {
                    UIView.performWithoutAnimation {
                        self.tableNode.reloadRows(at: validReloads, with: .none)
                    }
                    tableNode.waitUntilAllUpdatesAreProcessed()
                }
            }
        }
        committedSectionCount = expectedAfter
    }

    private static func rowDiffKey(_ row: ChannelListRow) -> String {
        switch row {
        case .channel(let ch, _):
            return "ch_\(ch.channelID)"
        case .thread(let ch, _, _):
            return "th_\(ch.channelID)"
        case .voiceMembersCollapsed(let ch, _):
            return "vc_\(ch.channelID)"
        case .voiceMemberExpanded(let ch, userId: let uid):
            return "ve_\(ch.channelID)_\(uid)"
        }
    }

    private func channelRowDataChanged(
        old: ChannelListRow,
        new: ChannelListRow,
        prevSelected: Int64?,
        newSelected: Int64?,
        prevVoice: [Int64: [String]],
        newVoice: [Int64: [String]]
    ) -> Bool {
        channelListRowVisuallyChanged(
            old: old, new: new,
            prevSelected: prevSelected, newSelected: newSelected,
            prevVoice: prevVoice, newVoice: newVoice
        )
    }

    private func channelListRowVisuallyChanged(
        old: ChannelListRow,
        new: ChannelListRow,
        prevSelected: Int64?,
        newSelected: Int64?,
        prevVoice: [Int64: [String]],
        newVoice: [Int64: [String]]
    ) -> Bool {
        switch (old, new) {
        case let (.channel(o, _), .channel(n, _)):
            guard o.channelID == n.channelID else { return true }
            if Self.voiceChannelTypes.contains(o.type) {
                let oActive = !(prevVoice[o.channelID] ?? []).isEmpty
                let nActive = !(newVoice[n.channelID] ?? []).isEmpty
                if oActive != nActive { return true }
            }
            return channelItemVisuallyChanged(o, n, prevSelected: prevSelected, newSelected: newSelected)
        case let (.thread(o, oLast, _), .thread(n, nLast, _)):
            if oLast != nLast { return true }
            return threadItemVisuallyChanged(o, n, prevSelected: prevSelected, newSelected: newSelected)
        case let (.voiceMembersCollapsed(c1, u1), .voiceMembersCollapsed(c2, u2)):
            guard c1.channelID == c2.channelID else { return true }
            return u1 != u2
        case let (.voiceMemberExpanded(c1, id1), .voiceMemberExpanded(c2, id2)):
            guard c1.channelID == c2.channelID else { return true }
            return id1 != id2
        default:
            return true
        }
    }

    private func channelItemVisuallyChanged(
        _ o: Mezon_Api_ChannelDescription,
        _ n: Mezon_Api_ChannelDescription,
        prevSelected: Int64?,
        newSelected: Int64?
    ) -> Bool {
        guard o.channelID == n.channelID else { return true }
        if (o.channelID == prevSelected) != (n.channelID == newSelected) { return true }
        if o.channelLabel != n.channelLabel { return true }
        if o.type != n.type { return true }
        if o.channelPrivate != n.channelPrivate { return true }
        if o.ageRestricted != n.ageRestricted { return true }
        if o.countMessUnread != n.countMessUnread { return true }
        return Self.appearsUnreadInChannelList(o) != Self.appearsUnreadInChannelList(n)
    }

    private func threadItemVisuallyChanged(
        _ o: Mezon_Api_ChannelDescription,
        _ n: Mezon_Api_ChannelDescription,
        prevSelected: Int64?,
        newSelected: Int64?
    ) -> Bool {
        guard o.channelID == n.channelID else { return true }
        if (o.channelID == prevSelected) != (n.channelID == newSelected) { return true }
        if o.channelLabel != n.channelLabel { return true }
        if o.countMessUnread != n.countMessUnread { return true }
        return Self.appearsUnreadInChannelList(o) != Self.appearsUnreadInChannelList(n)
    }

    private static func appearsUnreadInChannelList(_ ch: Mezon_Api_ChannelDescription) -> Bool {
        ch.countMessUnread > 0
            || (ch.hasLastSentMessage
                && ch.lastSeenMessage.timestampSeconds < ch.lastSentMessage.timestampSeconds)
    }

    private func applyRowDiff(prev: ChannelListState, new: ChannelListState) {
        guard committedSectionCount == tableNode.numberOfSections else {
            safeReloadData()
            return
        }

        let sectionOffset = hasChannelAppsSection ? 1 : 0

        var rowCountChanged = false
        for s in 0..<new.categories.count {
            let section = s + sectionOffset
            guard section < tableNode.numberOfSections else {
                safeReloadData()
                return
            }
            let committedRows = tableNode.numberOfRows(inSection: section)
            let newRows = rowsForSection(s).count
            if committedRows != newRows {
                rowCountChanged = true
                break
            }
        }

        if rowCountChanged {
            applyBatchStructureUpdate(prev: prev, new: new)
            return
        }

        var paths: [IndexPath] = []
        for s in 0..<new.categories.count {
            let oldRows = computeRows(for: prev, categoryIndex: s)
            let newRows = rowsForSection(s)

            for r in 0..<newRows.count {
                guard r < oldRows.count else {
                    paths.append(IndexPath(row: r, section: s + sectionOffset))
                    continue
                }
                let oldRow = oldRows[r]
                let newRow = newRows[r]
                if Self.rowDiffKey(oldRow) != Self.rowDiffKey(newRow) {
                    paths.append(IndexPath(row: r, section: s + sectionOffset))
                    continue
                }
                if channelListRowVisuallyChanged(
                    old: oldRow,
                    new: newRow,
                    prevSelected: prev.selectedChannelId,
                    newSelected: new.selectedChannelId,
                    prevVoice: prev.voiceUsersByChannel,
                    newVoice: new.voiceUsersByChannel
                ) {
                    paths.append(IndexPath(row: r, section: s + sectionOffset))
                }
            }
        }

        guard !paths.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadRows(at: paths, with: .none)
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
    }

    private func indexPathForListChannel(channelId: Int64) -> IndexPath? {
        let sectionOffset = hasChannelAppsSection ? 1 : 0
        for s in 0..<state.categories.count {
            let rows = rowsForSection(s)
            if let r = rows.firstIndex(where: { row in
                switch row {
                case .voiceMembersCollapsed, .voiceMemberExpanded: return false
                default: return row.channelDesc.channelID == channelId
                }
            }) {
                return IndexPath(row: r, section: s + sectionOffset)
            }
        }
        return nil
    }

    private func rowHasNumericUnreadBadge(_ row: ChannelListRow) -> Bool {
        switch row {
        case .voiceMembersCollapsed, .voiceMemberExpanded:
            return false
        case .channel(let ch, _), .thread(let ch, _, _):
            if Self.voiceChannelTypes.contains(ch.type) { return false }
            return ch.countMessUnread > 0
        }
    }

    private func firstDisplayedChannelIdWithUnreadBadge() -> Int64? {
        for s in 0..<state.categories.count {
            let rows = rowsForSection(s)
            for row in rows where rowHasNumericUnreadBadge(row) {
                return row.channelDesc.channelID
            }
        }
        return nil
    }

    private func refreshNewUnreadButton() {
        newUnreadButton.isHidden = firstDisplayedChannelIdWithUnreadBadge() == nil
    }

    private func layoutNewUnreadButton(containerSize: CGSize, bottomInset: CGFloat) {
        newUnreadButton.titleLabel?.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        let fit = newUnreadButton.systemLayoutSizeFitting(
            CGSize(width: containerSize.width - 24, height: 80),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        let w = max(36, fit.width)
        let h = max(28, fit.height)
        let x = containerSize.width * 0.30
        let y = containerSize.height - bottomInset - 100.sh - h
        newUnreadButton.frame = CGRect(x: x, y: y, width: w, height: h)
    }

    @objc private func newUnreadButtonTapped() {
        guard let id = firstDisplayedChannelIdWithUnreadBadge() else { return }
        scrollToChannel(channelId: id, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.interaction.onRefresh?()
        }
    }

    private func scrollToChannel(channelId: Int64, animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableNode.waitUntilAllUpdatesAreProcessed()
            self.tableNode.view.layoutIfNeeded()
            guard let indexPath = self.indexPathForListChannel(channelId: channelId) else { return }
            guard indexPath.section < self.tableNode.numberOfSections,
                  indexPath.row < self.tableNode.numberOfRows(inSection: indexPath.section) else {
                return
            }
            self.tableNode.scrollToRow(at: indexPath, at: .middle, animated: animated)
        }
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()
        layer.addSublayer(gradientLayer)
        addSubnode(tableNode)
        tableNode.backgroundColor = .clear
        tableNode.view.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            tableNode.view.sectionHeaderTopPadding = 0
        }
        tableNode.view.contentInset.bottom = 80
        tableNode.view.scrollIndicatorInsets.bottom = 80
        tableNode.delegate = self
        tableNode.dataSource = self
        committedSectionCount = totalSections

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.theme.textDisabled
        refreshControl.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl

        headerSpacer.backgroundColor = .clear
        headerSpacer.translatesAutoresizingMaskIntoConstraints = false
        headerSpacer.heightAnchor.constraint(equalToConstant: headerH).isActive = true

        let tableHeader = UIStackView(arrangedSubviews: [bannerView, headerSpacer])
        tableHeader.axis = .vertical
        tableHeader.spacing = 0
        tableNode.view.tableHeaderView = tableHeader
        bannerView.isHidden = true

        headerUIView.applyTheme()
        headerUIView.backgroundColor = UIColor.theme.secondary
        headerUIView.onSearchTapped = interaction.onSearchTapped
        view.addSubview(headerUIView)
        headerUIView.layer.zPosition = 100
        headerUIView.onTap = { [weak self] in
            self?.presentClanActionSheet()
        }

        newUnreadButton.layer.zPosition = 85
        newUnreadButton.addTarget(self, action: #selector(newUnreadButtonTapped), for: .touchUpInside)
        view.addSubview(newUnreadButton)
        refreshNewUnreadButton()
    }

    private func scheduleReload() {
        cachedRows = [:]
        cachedHeaders = [:]
        safeReloadData()
    }

    private func channelAppsUIEqual(_ a: [Mezon_Api_ChannelAppResponse], _ b: [Mezon_Api_ChannelAppResponse]) -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices {
            if a[i].id != b[i].id { return false }
            if a[i].appName != b[i].appName { return false }
            if a[i].appLogo != b[i].appLogo { return false }
        }
        return true
    }

    private static func normalizeChannelAppsList(_ apps: [Mezon_Api_ChannelAppResponse]) -> [Mezon_Api_ChannelAppResponse] {
        let withChannel = apps.filter { $0.channelID != 0 }
        var byChannel: [Int64: Mezon_Api_ChannelAppResponse] = [:]
        for a in withChannel {
            byChannel[a.channelID] = a
        }
        return byChannel.values.sorted { $0.channelID < $1.channelID }
    }

    private func appsSectionRowCount(apps: [Mezon_Api_ChannelAppResponse], expanded: Bool) -> Int {
        guard !apps.isEmpty else { return 0 }
        if apps.count <= compactViewThreshold {
            return expanded ? apps.count : 0
        }
        return 1
    }

    private func reloadChannelAppsSectionOnly() {
        guard hasChannelAppsSection else { return }
        guard tableNode.numberOfSections > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadSections(IndexSet(integer: 0), with: .none)
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
    }

    private func updateTableHeaderLayout() {
        guard let header = tableNode.view.tableHeaderView else { return }
        header.setNeedsLayout()
        header.layoutIfNeeded()
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableNode.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if header.frame.size.height != size.height {
            header.frame.size.height = size.height
            tableNode.view.tableHeaderView = header
        }
        updateStickyHeaderPosition()
    }

    private func categoryIndex(forSection section: Int) -> Int {
        let offset = hasChannelAppsSection ? 1 : 0
        return section - offset
    }

    private var channelListLoadingPlaceholderVisible: Bool {
        state.isLoading && state.categories.isEmpty
    }

    private var loadingPlaceholderTableSection: Int {
        hasChannelAppsSection ? 1 : 0
    }

    private func isLoadingPlaceholderTableSection(_ section: Int) -> Bool {
        channelListLoadingPlaceholderVisible && section == loadingPlaceholderTableSection
    }

    private var totalSections: Int {
        let appsSections = hasChannelAppsSection ? 1 : 0
        if channelListLoadingPlaceholderVisible {
            return appsSections + 1
        }
        let catSections = state.categories.count
        return appsSections + catSections
    }

    var hasDisplayedChannelApps: Bool { !channelApps.isEmpty }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        if layer.maskedCorners != [.layerMinXMinYCorner] {
            layer.cornerRadius = 20.swh
            layer.maskedCorners = [.layerMinXMinYCorner]
            clipsToBounds = true
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()

        let topInset: CGFloat = 0
        stickyTopOffset = topInset
        let tableFrame = CGRect(x: 0, y: topInset, width: layout.size.width, height: layout.size.height - topInset - layout.intrinsicInsets.bottom)
        transition.updateFrame(node: tableNode, frame: tableFrame)
        updateTableHeaderLayout()
        layoutNewUnreadButton(containerSize: layout.size, bottomInset: layout.intrinsicInsets.bottom)
    }

    private static let bannerKnownHeight: CGFloat = 140.sh

    private func updateStickyHeaderPosition() {
        let bannerHeight = bannerView.isHidden ? 0 : Self.bannerKnownHeight
        let contentOffsetY = tableNode.view.contentOffset.y
        let headerY = max(0, bannerHeight - contentOffsetY)
        headerUIView.frame = CGRect(x: 0, y: stickyTopOffset + headerY, width: tableNode.bounds.width, height: headerH)
    }

    func markClanSwitching() {
        isClanSwitching = true
    }

    func clearChannelApps() {
        let hadSection = !channelApps.isEmpty
        channelApps = []
        cachedRows = [:]
        cachedHeaders = [:]
        guard hadSection else {
            committedSectionCount = totalSections
            return
        }
        guard tableNode.numberOfSections > 0 else {
            committedSectionCount = totalSections
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.deleteSections(IndexSet(integer: 0), with: .none)
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
        committedSectionCount = totalSections
    }

    func configure(clanName: String, logoURL: String? = nil, bannerURL: String? = nil, memberCount: Int = 0, onlineCount: Int = 0, isCommunity: Bool = false) {
        self.clanLogoURL = logoURL ?? ""
        self.isCommunity = isCommunity
        self.memberCount = memberCount
        self.onlineCount = onlineCount
        headerUIView.configure(title: clanName, memberCount: memberCount, isCommunity: isCommunity)
        isChannelAppsExpanded = true

        UIView.performWithoutAnimation {
            if let url = bannerURL, !url.isEmpty {
                bannerView.isHidden = false
                bannerView.loadBanner(urlString: url)
            } else {
                bannerView.isHidden = true
                bannerView.clearBanner()
            }
            if let header = tableNode.view.tableHeaderView {
                header.setNeedsLayout()
                header.layoutIfNeeded()
                let size = header.systemLayoutSizeFitting(
                    CGSize(width: tableNode.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                if header.frame.size.height != size.height {
                    header.frame.size.height = size.height
                    tableNode.view.tableHeaderView = header
                }
            }
        }
        if !isClanSwitching {
            tableNode.view.contentOffset = .zero
        }
        updateStickyHeaderPosition()
        DispatchQueue.main.async { [weak self] in
            self?.updateTableHeaderLayout()
            self?.updateStickyHeaderPosition()
            self?.refreshNewUnreadButton()
        }
    }

    func updateChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) {
        let filtered = Self.normalizeChannelAppsList(apps.filter { $0.hasListableChannelAppContent })
        if channelAppsUIEqual(channelApps, filtered) { return }

        let beforeHad = hasChannelAppsSection
        channelApps = filtered
        let afterHad = hasChannelAppsSection

        cachedRows = [:]
        cachedHeaders = [:]

        if !beforeHad && afterHad {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tableNode.performBatch(animated: false) {
                self.tableNode.insertSections(IndexSet(integer: 0), with: .none)
            }
            tableNode.waitUntilAllUpdatesAreProcessed()
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && !afterHad {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tableNode.performBatch(animated: false) {
                self.tableNode.deleteSections(IndexSet(integer: 0), with: .none)
            }
            tableNode.waitUntilAllUpdatesAreProcessed()
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && afterHad {
            reloadChannelAppsSectionOnly()
        }
    }

    func updateMemberCount(_ count: Int) {
        self.memberCount = count
        headerUIView.updateMemberCount(count)
    }

    private func presentClanActionSheet() {
        guard let window = self.view.window as? WindowHost else { return }
        let actionSheet = ClanActionSheetController(
            clanName: headerUIView.title,
            avatarURL: clanLogoURL,
            memberCount: memberCount,
            onlineCount: onlineCount,
            isCommunity: isCommunity,
            onAction: { [weak self] action in
                guard let self else { return }
                if action == .settings {
                    self.interaction.onPresentSettings?()
                } else {
                }
            }
        )
        window.present(actionSheet, on: .root, blockInteraction: false, completion: {})
        actionSheet.animateIn()
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        interaction.onRefresh?()
    }

    func endRefreshing() {
        tableNode.view.refreshControl?.endRefreshing()
    }

    private func toggleChannelAppsExpand() {
        isChannelAppsExpanded.toggle()
        scheduleReload()
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [
            t.primaryGradient.cgColor,
            t.secondary.cgColor,
            t.secondary.cgColor,
            t.primaryGradient.cgColor
        ]
        backgroundColor = .clear
        tableNode.backgroundColor = .clear
        tableNode.view.backgroundColor = .clear
        headerUIView.applyTheme()
        headerUIView.backgroundColor = t.primaryGradient
        newUnreadButton.backgroundColor = UIColor.mezonUnreadBadge
        newUnreadButton.setTitleColor(.white, for: .normal)
        newUnreadButton.titleLabel?.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        scheduleReload()
    }

    private func reloadSelectionRows(previous: Int64?, current: Int64?) {
        var paths: [IndexPath] = []
        let sectionOffset = hasChannelAppsSection ? 1 : 0
        for s in 0..<state.categories.count {
            let rows = rowsForSection(s)
            for (r, row) in rows.enumerated() {
                let chId = row.channelDesc.channelID
                if chId == previous || chId == current {
                    paths.append(IndexPath(row: r, section: s + sectionOffset))
                }
            }
        }
        guard !paths.isEmpty else { return }
        tableNode.reloadRows(at: paths, with: .none)
    }


    private static let voiceChannelTypes: Set<Int32> = [
        MezonConstants.ChannelType.mezonVoice.rawValue,
        MezonConstants.ChannelType.streaming.rawValue,
        MezonConstants.ChannelType.app.rawValue,
    ]

    private func computeRows(
        for category: ChannelCategory,
        allChannels: [Mezon_Api_ChannelDescription],
        selectedChannelId: Int64?,
        voiceUsersByChannel: [Int64: [String]]
    ) -> [ChannelListRow] {
        let lookup = buildThreadLookup(allChannels)
        let baseRows = flattenCategoryToRows(category, threadLookup: lookup)
        let isExpanded = !category.isCollapsed

        var allRows: [ChannelListRow] = []
        for row in baseRows {
            allRows.append(row)
            if case .channel(let ch, _) = row,
               Self.voiceChannelTypes.contains(ch.type) {
                let userIds = (voiceUsersByChannel[ch.channelID] ?? [])
                    .filter { voiceMemberResolver?($0) != nil }
                if !userIds.isEmpty {
                    if isExpanded {
                        for uid in userIds {
                            allRows.append(.voiceMemberExpanded(ch, userId: uid))
                        }
                    } else {
                        allRows.append(.voiceMembersCollapsed(ch, userIds: userIds))
                    }
                }
            }
        }

        guard category.isCollapsed else { return allRows }
        return allRows.filter { row in
            switch row {
            case .voiceMembersCollapsed, .voiceMemberExpanded: return true
            default: break
            }
            let ch = row.channelDesc
            if Self.voiceChannelTypes.contains(ch.type) {
                let hasMembers = !(voiceUsersByChannel[ch.channelID] ?? []).isEmpty
                return hasMembers
            }
            if ch.countMessUnread > 0 { return true }
            if ch.lastSentMessage.timestampSeconds > ch.lastSeenMessage.timestampSeconds { return true }
            if ch.channelID == selectedChannelId { return true }
            if let threads = lookup[ch.channelID] {
                let hasUnreadOrActiveThread = threads.contains {
                    $0.countMessUnread > 0
                    || $0.lastSentMessage.timestampSeconds > $0.lastSeenMessage.timestampSeconds
                    || $0.channelID == selectedChannelId
                }
                if hasUnreadOrActiveThread { return true }
            }
            if case .thread = row {
                if ch.countMessUnread > 0 { return true }
                if ch.lastSentMessage.timestampSeconds > ch.lastSeenMessage.timestampSeconds { return true }
                if ch.channelID == selectedChannelId { return true }
            }
            return false
        }
    }

    private func computeRows(for state: ChannelListState, categoryIndex: Int) -> [ChannelListRow] {
        guard categoryIndex < state.categories.count else { return [] }
        return computeRows(
            for: state.categories[categoryIndex],
            allChannels: state.allChannels,
            selectedChannelId: state.selectedChannelId,
            voiceUsersByChannel: state.voiceUsersByChannel
        )
    }

    private func rowsForSection(_ section: Int) -> [ChannelListRow] {
        if let cached = cachedRows[section] { return cached }
        let rows = computeRows(for: state, categoryIndex: section)
        cachedRows[section] = rows
        return rows
    }
}

extension ChannelListContainerNode: ASTableDataSource {

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        totalSections
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if hasChannelAppsSection && section == 0 {
            if isCompactView {
                return isChannelAppsExpanded ? channelApps.count : 0
            } else {
                return 1
            }
        }
        if isLoadingPlaceholderTableSection(section) {
            return 1
        }
        let catIdx = categoryIndex(forSection: section)
        return rowsForSection(catIdx).count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if hasChannelAppsSection && indexPath.section == 0 {
            if isCompactView {
                guard indexPath.row < channelApps.count else { return { ASCellNode() } }
                let app = channelApps[indexPath.row]
                return { ChannelAppCellNode(app: app) }
            } else {
                let apps = channelApps
                return {
                    ChannelAppHorizontalCellNode(apps: apps) { [weak self] app in
                        self?.interaction.onSelectChannelApp?(app)
                    }
                }
            }
        }
        if isLoadingPlaceholderTableSection(indexPath.section) {
            return { ChannelListSkeletonCellNode() }
        }
        let catIdx = categoryIndex(forSection: indexPath.section)

        let rows = rowsForSection(catIdx)
        guard indexPath.row < rows.count else { return { ASCellNode() } }
        let row = rows[indexPath.row]
        let isSelected = row.channelDesc.channelID == state.selectedChannelId
        switch row {
        case .channel(let ch, let inFav):
            let hasVoiceMembers = Self.voiceChannelTypes.contains(ch.type)
                && !(state.voiceUsersByChannel[ch.channelID] ?? []).isEmpty
            return {
                let node = ChannelItemCellNode(channel: ch, isSelected: isSelected, isVoiceActive: hasVoiceMembers)
                if !inFav {
                    node.onLongPress = { [weak self] in
                        self?.interaction.onLongPressChannel(ch)
                    }
                }
                return node
            }
        case .thread(let ch, let isLast, let inFav):
            return {
                let node = ThreadItemCellNode(channel: ch, isSelected: isSelected, isLast: isLast)
                if !inFav {
                    node.onLongPress = { [weak self] in
                        self?.interaction.onLongPressChannel(ch)
                    }
                }
                return node
            }
        case .voiceMembersCollapsed(_, let userIds):
            let totalCount = userIds.count
            let visible = Array(userIds.prefix(6))
            let resolver = voiceMemberResolver
            let members: [VoiceMemberDisplay] = visible.compactMap { resolver?($0) }
            return {
                VoiceChannelMembersCollapsedCellNode(members: members, totalCount: totalCount)
            }
        case .voiceMemberExpanded(_, let userId):
            guard let member = voiceMemberResolver?(userId) else {
                return { ASCellNode() }
            }
            return {
                VoiceMemberExpandedCellNode(member: member)
            }
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if hasChannelAppsSection && section == 0 {
            if isCompactView {
                let header = cachedHeaders[section] ?? CategorySectionHeaderView()
                header.configureAppsHeader(isCollapsed: !isChannelAppsExpanded)
                header.onTap = { [weak self] in self?.toggleChannelAppsExpand() }
                cachedHeaders[section] = header
                return header
            } else {
                return nil
            }
        }
        if isLoadingPlaceholderTableSection(section) {
            return nil
        }
        let catIdx = categoryIndex(forSection: section)
        guard catIdx < state.categories.count else { return nil }
        let cat = state.categories[catIdx]
        let header = cachedHeaders[section] ?? CategorySectionHeaderView()
        header.configure(category: cat)
        header.onTap = { [weak self] in self?.interaction.onToggleCollapse(cat.id) }
        cachedHeaders[section] = header
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if hasChannelAppsSection && section == 0 {
            return isCompactView ? 32.sh : 0
        }
        if isLoadingPlaceholderTableSection(section) {
            return 0
        }
        let catIdx = categoryIndex(forSection: section)
        return catIdx < state.categories.count ? 32.sh : 0
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }
}

extension ChannelListContainerNode: ASTableDelegate {

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: false)
        if hasChannelAppsSection && indexPath.section == 0 {
            if isCompactView, indexPath.row < channelApps.count {
                interaction.onSelectChannelApp?(channelApps[indexPath.row])
            }
            return
        }
        if isLoadingPlaceholderTableSection(indexPath.section) {
            return
        }
        let catIdx = categoryIndex(forSection: indexPath.section)
        let rows = rowsForSection(catIdx)
        guard indexPath.row < rows.count else { return }
        let row = rows[indexPath.row]
        switch row {
        case .voiceMembersCollapsed, .voiceMemberExpanded: return
        default: break
        }
        interaction.onSelectChannel(row.channelDesc)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateStickyHeaderPosition()
    }
}

private final class ChannelListSkeletonCellNode: ASCellNode {

    private let numberSkeleton: Int
    private let bars: [ASDisplayNode]
    private var barFrames: [CGRect] = []
    private var shimmerLayers: [CAGradientLayer] = []

    init(numberSkeleton: Int = 6) {
        self.numberSkeleton = numberSkeleton
        let count = 1 + (0..<numberSkeleton).reduce(0) { $0 + 1 + ($1 % 2 == 0 ? 3 : 2) }
        var nodes: [ASDisplayNode] = []
        nodes.reserveCapacity(count)
        for _ in 0..<count {
            let n = ASDisplayNode()
            n.isLayerBacked = true
            n.clipsToBounds = true
            n.cornerRadius = 8.swh
            nodes.append(n)
        }
        self.bars = nodes
        super.init()
        selectionStyle = .none
        clipsToBounds = true
        isOpaque = false
        backgroundColor = .clear
        for n in bars {
            addSubnode(n)
        }
    }

    override func didLoad() {
        super.didLoad()
        view.backgroundColor = .clear
        applyBarColors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.attachShimmers()
        }
    }

    private func applyBarColors() {
        let c = UIColor.theme.secondaryLight
        for n in bars {
            n.backgroundColor = c
        }
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let w = constrainedSize.width
        let frames = Self.computeBarFrames(width: w, numberSkeleton: numberSkeleton)
        let h = frames.last.map { $0.maxY } ?? 0
        return CGSize(width: w, height: h + 10.sh)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        guard w > 0 else { return }
        barFrames = Self.computeBarFrames(width: w, numberSkeleton: numberSkeleton)
        guard barFrames.count == bars.count else { return }
        for (n, r) in zip(bars, barFrames) {
            n.frame = r
        }
        for (i, n) in bars.enumerated() where i < shimmerLayers.count {
            shimmerLayers[i].frame = n.layer.bounds
            shimmerLayers[i].cornerRadius = n.cornerRadius
        }
    }

    override func didExitVisibleState() {
        super.didExitVisibleState()
        for layer in shimmerLayers {
            layer.removeAllAnimations()
        }
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        for layer in shimmerLayers {
            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = [-1.0, -0.5, 0.0]
            animation.toValue = [1.0, 1.5, 2.0]
            animation.duration = 1.5
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "shimmer")
        }
    }

    private func attachShimmers() {
        guard shimmerLayers.isEmpty else { return }
        let base = UIColor.theme.secondaryLight
        let highlight = UIColor.theme.tertiary
        for n in bars {
            let layer = n.layer
            let shimmer = CAGradientLayer()
            shimmer.frame = layer.bounds
            shimmer.cornerRadius = layer.cornerRadius
            shimmer.startPoint = CGPoint(x: 0, y: 0.5)
            shimmer.endPoint = CGPoint(x: 1, y: 0.5)
            shimmer.colors = [base.cgColor, highlight.cgColor, base.cgColor]
            shimmer.locations = [0, 0.5, 1]
            layer.addSublayer(shimmer)
            shimmerLayers.append(shimmer)
            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = [-1.0, -0.5, 0.0]
            animation.toValue = [1.0, 1.5, 2.0]
            animation.duration = 1.5
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            shimmer.add(animation, forKey: "shimmer")
        }
    }

    private static func computeBarFrames(width: CGFloat, numberSkeleton: Int) -> [CGRect] {
        let pad: CGFloat = 10.sw
        let innerW = max(0, width - pad * 2)
        let x = pad
        var y: CGFloat = 10.sh
        var frames: [CGRect] = []

        frames.append(CGRect(x: x, y: y, width: innerW, height: 30.sh))
        y += 30.sh + 10.sh

        let indent: CGFloat = 20.sw
        let wNormal = min(200.sw, innerW)
        let wSmall = min(100.sw, max(0, innerW - indent))
        let wMed = min(150.sw, max(0, innerW - indent))

        for i in 0..<numberSkeleton {
            y += 6.sh
            frames.append(CGRect(x: x, y: y, width: wNormal, height: 24.sh))
            y += 24.sh + 10.sh
            if i % 2 == 1 {
                frames.append(CGRect(x: x + indent, y: y, width: wMed, height: 16.sh))
                y += 16.sh + 10.sh
                frames.append(CGRect(x: x + indent, y: y, width: wSmall, height: 16.sh))
                y += 16.sh + 10.sh
            } else {
                frames.append(CGRect(x: x + indent, y: y, width: wSmall, height: 16.sh))
                y += 16.sh + 10.sh
                frames.append(CGRect(x: x + indent, y: y, width: wSmall, height: 16.sh))
                y += 16.sh + 10.sh
                frames.append(CGRect(x: x + indent, y: y, width: wMed, height: 16.sh))
                y += 16.sh + 10.sh
            }
        }
        return frames
    }
}


private final class CategorySectionHeaderView: UIView {

    var onTap: (() -> Void)?

    private let arrowIcon: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(arrowIcon)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            arrowIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8.sw),
            arrowIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowIcon.widthAnchor.constraint(equalToConstant: 18.sw),
            arrowIcon.heightAnchor.constraint(equalToConstant: 18.sw),

            titleLabel.leadingAnchor.constraint(equalTo: arrowIcon.trailingAnchor, constant: 2.sw),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.sw),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(category: ChannelCategory) {
        let t = UIColor.theme
        backgroundColor = .clear
        titleLabel.textColor = t.textDisabled
        let iconName = category.isCollapsed ? "Channel/ChevronRight" : "Channel/ChevronBottom"
        arrowIcon.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        arrowIcon.tintColor = t.textDisabled
        titleLabel.text = category.name.uppercased()
    }

    func configureAppsHeader(isCollapsed: Bool) {
        let t = UIColor.theme
        backgroundColor = .clear
        titleLabel.textColor = t.textDisabled
        let iconName = isCollapsed ? "Channel/ChevronRight" : "Channel/ChevronBottom"
        arrowIcon.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        arrowIcon.tintColor = t.textDisabled
        titleLabel.text = "CHANNEL APPS"
    }

    @objc private func handleTap() { onTap?() }
}

final class ChannelListHeaderView: UIView {

    var onTap: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onQRTapped: (() -> Void)?

    var title: String {
        return titleLabel.text ?? ""
    }

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let memberCountLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let communityDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 2
        v.backgroundColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let communityLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.text = "Community"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let searchBar: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 16
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let searchIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(named: "Channel/Search"))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let searchLabel: UILabel = {
        let l = UILabel()
        l.text = "Search"
        l.font = .systemFont(ofSize: 14)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let qrButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "Channel/QR")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.layer.cornerRadius = 16
        btn.layer.borderWidth = 1
        btn.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let eventButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(
            UIImage(named: "Channel/Event")?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.layer.cornerRadius = 16
        btn.layer.borderWidth = 1
        btn.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let separator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel])
        titleStack.axis = .horizontal
        titleStack.spacing = 4
        titleStack.alignment = .center
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let communityStack = UIStackView(arrangedSubviews: [communityDot, communityLabel])
        communityStack.axis = .horizontal
        communityStack.spacing = 6
        communityStack.alignment = .center
        communityStack.translatesAutoresizingMaskIntoConstraints = false

        let infoSpacer = UIView()
        infoSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let infoRow = UIStackView(arrangedSubviews: [
            memberCountLabel, communityStack, infoSpacer,
        ])
        infoRow.axis = .horizontal
        infoRow.spacing = 14
        infoRow.alignment = .center
        infoRow.translatesAutoresizingMaskIntoConstraints = false

        searchBar.addSubview(searchIcon)
        searchBar.addSubview(searchLabel)
        let searchTap = UITapGestureRecognizer(target: self, action: #selector(searchBarTapped))
        searchBar.addGestureRecognizer(searchTap)

        qrButton.addTarget(self, action: #selector(qrTapped), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [searchBar, qrButton, eventButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.alignment = .center
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = UIStackView(arrangedSubviews: [titleStack, infoRow, actionRow])
        mainStack.axis = .vertical
        mainStack.spacing = 4
        mainStack.setCustomSpacing(8, after: titleStack)
        mainStack.setCustomSpacing(10, after: infoRow)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let mainTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleHeaderTap))
        mainStack.addGestureRecognizer(mainTapGesture)
        mainStack.isUserInteractionEnabled = true

        addSubview(mainStack)
        addSubview(separator)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            communityDot.widthAnchor.constraint(equalToConstant: 4),
            communityDot.heightAnchor.constraint(equalToConstant: 4),

            searchBar.heightAnchor.constraint(equalToConstant: 32),
            searchIcon.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),
            searchLabel.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchLabel.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),

            qrButton.widthAnchor.constraint(equalToConstant: 32),
            qrButton.heightAnchor.constraint(equalToConstant: 32),
            eventButton.widthAnchor.constraint(equalToConstant: 32),
            eventButton.heightAnchor.constraint(equalToConstant: 32),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func searchBarTapped() {
        onSearchTapped?()
    }

    @objc private func qrTapped() {
        onQRTapped?()
    }

    func configure(title: String, memberCount: Int = 0, isCommunity: Bool = false) {
        titleLabel.text = title
        if memberCount > 0 {
            memberCountLabel.text = memberCount == 1 ? "\(memberCount) Member" : "\(memberCount) Members"
            memberCountLabel.isHidden = false
        } else {
            memberCountLabel.isHidden = true
        }
        communityDot.isHidden = !isCommunity || memberCount <= 0
        communityLabel.isHidden = !isCommunity
        communityLabel.text = "Community"
    }

    func updateMemberCount(_ count: Int) {
        if count > 0 {
            memberCountLabel.text = count == 1 ? "\(count) Member" : "\(count) Members"
            memberCountLabel.isHidden = false
            communityDot.isHidden = communityLabel.isHidden
        } else {
            memberCountLabel.isHidden = true
            communityDot.isHidden = true
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = .clear
        titleLabel.textColor = t.textStrong
        memberCountLabel.textColor = t.textStrong
        communityLabel.textColor = t.textStrong
        searchBar.backgroundColor = t.tertiary
        searchIcon.tintColor = t.textDisabled
        searchLabel.textColor = t.textDisabled
        qrButton.backgroundColor = t.tertiary
        qrButton.layer.borderColor = t.border.withAlphaComponent(0.4).cgColor
        eventButton.backgroundColor = t.tertiary
        eventButton.layer.borderColor = t.border.withAlphaComponent(0.4).cgColor
        separator.backgroundColor = t.borderDim
    }

    @objc private func handleHeaderTap() {
        onTap?()
    }
}
