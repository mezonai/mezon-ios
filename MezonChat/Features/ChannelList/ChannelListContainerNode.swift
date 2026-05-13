import AsyncDisplayKit
import UIKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onLongPressChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
    let onRefresh: (() -> Void)?
    let onPresentSettings: (() -> Void)?
    let onInviteClan: (() -> Void)?
    let onSearchTapped: (() -> Void)?
    let onQRTapped: (() -> Void)?
    let onSelectChannelApp: ((Mezon_Api_ChannelAppResponse) -> Void)?
    let onClearCurrentChannelSelection: (() -> Void)?
}

final class ChannelListContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    private let headerUIView = ChannelListHeaderView()
    private let bannerView = ChannelBannerView()
    private let headerSpacer = UIView()
    private var headerSpacerHeightConstraint: NSLayoutConstraint?
    private var stickyTopOffset: CGFloat = 0
    private let headerHMin: CGFloat = 120
    private var currentHeaderH: CGFloat = 120
    private var hasClanBanner: Bool = false
    private var channelApps: [Mezon_Api_ChannelAppResponse]

    private var channelAppsLoading = false
    private var isChannelAppsExpanded = true
    private var channelAppsStripeVisible: Bool { channelAppsLoading || !channelApps.isEmpty }
    private let compactViewThreshold = 3
    private var isCompactView: Bool { channelApps.count <= compactViewThreshold }
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0, y: 0)
        gl.endPoint = CGPoint(x: 1, y: 1)
        gl.locations = [0.2, 0.4, 0.7, 0.9] as [NSNumber]
        return gl
    }()

    private static var shouldUseFlatBackgroundForCurrentTheme: Bool {
        switch ThemeManager.shared.current {
        case .dark, .light:
            return true
        case .system:
            let effective = UITraitCollection.current.userInterfaceStyle == .dark ? AppTheme.dark : AppTheme.light
            switch effective {
            case .dark, .light:
                return true
            default:
                return false
            }
        case .sunrise, .redDark, .purpleHaze, .abyssDark, .sunset:
            return false
        }
    }

    private var state: ChannelListState = .empty
    private var threadLookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]

    private var cachedRows: [Int: [ChannelListRow]] = [:]

    private var cachedHeaders: [Int: CategorySectionHeaderView] = [:]

    private var committedSectionCount: Int = 0
    private let interaction: ChannelListInteraction
    private let disposables = DisposableSet()
    private var isClanSwitching = false

    private var latestCoalescedChannelListState: ChannelListState?
    private var channelListStateApplyScheduled = false

    private var clanLogoURL: String = ""
    private var headerClanId: Int64 = 0
    private var isCommunity: Bool = false
    private var memberCount: Int = 0

    private var skipNextLoadingFinishedReveal: Bool = false

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

    init(
        signal: Signal<ChannelListState, NoError>,
        interaction: ChannelListInteraction,
        initialChannelApps: [Mezon_Api_ChannelAppResponse] = []
    ) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        self.channelApps = Self.normalizeChannelAppsList(
            initialChannelApps.filter { $0.hasListableChannelAppContent }
        )
        super.init()
        backgroundColor = UIColor.theme.secondary
        
        headerUIView.onQRTapped = { [weak self] in
            self?.interaction.onQRTapped?()
        }

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.latestCoalescedChannelListState = newState
                self.scheduleApplyCoalescedChannelListState()
            })
        )
    }

    private func scheduleApplyCoalescedChannelListState() {
        guard !channelListStateApplyScheduled else { return }
        channelListStateApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.drainOneCoalescedChannelListState()
        }
    }

    private func drainOneCoalescedChannelListState() {
        channelListStateApplyScheduled = false
        guard let newState = latestCoalescedChannelListState else { return }
        latestCoalescedChannelListState = nil
        applyChannelListStateTransition(to: newState)
        if latestCoalescedChannelListState != nil {
            scheduleApplyCoalescedChannelListState()
        }
    }

    private func applyChannelListStateTransition(to newState: ChannelListState) {
        let prevState = state

        if let msg = newState.errorMessage, msg != prevState.errorMessage {

        }

        let wasClanSwitching = isClanSwitching
        isClanSwitching = false
        state = newState
        threadLookup = buildThreadLookup(newState.allChannels)
        cachedRows = [:]

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
            cachedHeaders = [:]
            applyCrossfadeReload()
        } else if structureChanged {
            cachedHeaders = [:]
            applyBatchStructureUpdate(prev: prevState, new: newState)
        } else if !newCats.isEmpty {
            applyRowDiff(prev: prevState, new: newState)
        }

        maybeRevealSelectedChannel(prevState: prevState, newState: newState, wasClanSwitching: wasClanSwitching)
        refreshNewUnreadButton()
    }

    private func maybeRevealSelectedChannel(
        prevState: ChannelListState,
        newState: ChannelListState,
        wasClanSwitching: Bool
    ) {
        guard !newState.isLoading else { return }
        guard let selectedId = newState.selectedChannelId, selectedId != 0 else { return }
        guard firstCategoryIndexContainingListChannel(selectedId) != nil else { return }
        let selectionChanged = prevState.selectedChannelId != newState.selectedChannelId
        let loadingJustFinished = prevState.isLoading && !newState.isLoading
        let voiceMapChanged = prevState.voiceUsersByChannel != newState.voiceUsersByChannel
        let selectedIsVoiceChannel = newState.allChannels.contains {
            $0.channelID == selectedId && Self.voiceChannelTypes.contains($0.type)
        }
        if loadingJustFinished && skipNextLoadingFinishedReveal {
            skipNextLoadingFinishedReveal = false
            if !(wasClanSwitching || selectionChanged || (selectedIsVoiceChannel && voiceMapChanged)) {
                return
            }
        }
        guard wasClanSwitching || selectionChanged || loadingJustFinished || (selectedIsVoiceChannel && voiceMapChanged) else { return }
        scrollToChannel(channelId: selectedId, animated: !wasClanSwitching)
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

        let sectionOffset = channelAppsStripeVisible ? 1 : 0
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
        let (selectionReloadPaths, fullReloadPaths) = splitReloadPathsSelectionVsFull(
            filteredReload, prev: prev, new: new)

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

            if !selectionReloadPaths.isEmpty {
                let validSel = selectionReloadPaths.filter { ip in
                    ip.section < self.tableNode.numberOfSections
                        && ip.row < self.tableNode.numberOfRows(inSection: ip.section)
                }
                if !validSel.isEmpty {
                    applyInPlaceListSelection(paths: validSel, new: new)
                }
            }
            if !fullReloadPaths.isEmpty {
                let validReloads = fullReloadPaths.filter { ip in
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

    private func channelItemChangeIsSelectionOnly(
        _ o: Mezon_Api_ChannelDescription,
        _ n: Mezon_Api_ChannelDescription,
        prevSelected: Int64?,
        newSelected: Int64?
    ) -> Bool {
        guard o.channelID == n.channelID else { return false }
        if o.channelLabel != n.channelLabel { return false }
        if o.type != n.type { return false }
        if o.channelPrivate != n.channelPrivate { return false }
        if o.ageRestricted != n.ageRestricted { return false }
        if o.countMessUnread != n.countMessUnread { return false }
        if Self.appearsUnreadInChannelList(o) != Self.appearsUnreadInChannelList(n) { return false }
        return (o.channelID == prevSelected) != (n.channelID == newSelected)
    }

    private func threadItemChangeIsSelectionOnly(
        _ o: Mezon_Api_ChannelDescription,
        _ n: Mezon_Api_ChannelDescription,
        prevSelected: Int64?,
        newSelected: Int64?
    ) -> Bool {
        guard o.channelID == n.channelID else { return false }
        if o.channelLabel != n.channelLabel { return false }
        if o.countMessUnread != n.countMessUnread { return false }
        if Self.appearsUnreadInChannelList(o) != Self.appearsUnreadInChannelList(n) { return false }
        return (o.channelID == prevSelected) != (n.channelID == newSelected)
    }

    private func listRowChangeIsSelectionOnly(
        old: ChannelListRow,
        new: ChannelListRow,
        prevSelected: Int64?,
        newSelected: Int64?,
        prevVoice: [Int64: [String]],
        newVoice: [Int64: [String]]
    ) -> Bool {
        switch (old, new) {
        case let (.channel(o, _), .channel(n, _)):
            guard o.channelID == n.channelID else { return false }
            if Self.voiceChannelTypes.contains(o.type) {
                let oActive = !(prevVoice[o.channelID] ?? []).isEmpty
                let nActive = !(newVoice[n.channelID] ?? []).isEmpty
                if oActive != nActive { return false }
            }
            return channelItemChangeIsSelectionOnly(
                o, n, prevSelected: prevSelected, newSelected: newSelected)
        case let (.thread(o, oLast, _), .thread(n, nLast, _)):
            guard oLast == nLast else { return false }
            return threadItemChangeIsSelectionOnly(
                o, n, prevSelected: prevSelected, newSelected: newSelected)
        default:
            return false
        }
    }

    private func splitReloadPathsSelectionVsFull(
        _ paths: [IndexPath],
        prev: ChannelListState,
        new: ChannelListState
    ) -> ([IndexPath], [IndexPath]) {
        let sectionOffset = channelAppsStripeVisible ? 1 : 0
        var selectionPaths: [IndexPath] = []
        var fullPaths: [IndexPath] = []
        for ip in paths {
            guard ip.section >= sectionOffset else {
                fullPaths.append(ip)
                continue
            }
            let catIdx = ip.section - sectionOffset
            guard catIdx >= 0,
                catIdx < prev.categories.count,
                catIdx < new.categories.count
            else {
                fullPaths.append(ip)
                continue
            }
            let oldRows = computeRows(for: prev, categoryIndex: catIdx)
            let newRows = rowsForSection(catIdx)
            guard ip.row < oldRows.count, ip.row < newRows.count else {
                fullPaths.append(ip)
                continue
            }
            let oldRow = oldRows[ip.row]
            let newRow = newRows[ip.row]
            if Self.rowDiffKey(oldRow) != Self.rowDiffKey(newRow) {
                fullPaths.append(ip)
                continue
            }
            if listRowChangeIsSelectionOnly(
                old: oldRow,
                new: newRow,
                prevSelected: prev.selectedChannelId,
                newSelected: new.selectedChannelId,
                prevVoice: prev.voiceUsersByChannel,
                newVoice: new.voiceUsersByChannel
            ) {
                selectionPaths.append(ip)
            } else {
                fullPaths.append(ip)
            }
        }
        return (selectionPaths, fullPaths)
    }

    private func applyInPlaceListSelection(paths: [IndexPath], new: ChannelListState) {
        guard !paths.isEmpty else { return }
        let sectionOffset = channelAppsStripeVisible ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for ip in paths {
            guard ip.section >= sectionOffset else { continue }
            let catIdx = ip.section - sectionOffset
            guard catIdx >= 0, catIdx < new.categories.count else { continue }
            let newRows = rowsForSection(catIdx)
            guard ip.row >= 0, ip.row < newRows.count else { continue }
            guard let cellNode = tableNode.nodeForRow(at: ip) else { continue }
            switch newRows[ip.row] {
            case .channel(let ch, _):
                let selected = new.selectedChannelId == ch.channelID
                (cellNode as? ChannelItemCellNode)?.applyListSelectionState(selected: selected)
            case .thread(let ch, _, _):
                let selected = new.selectedChannelId == ch.channelID
                (cellNode as? ThreadItemCellNode)?.applyListSelectionState(selected: selected)
            default:
                break
            }
        }
        CATransaction.commit()
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

        let sectionOffset = channelAppsStripeVisible ? 1 : 0

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

        var selectionPaths: [IndexPath] = []
        var reloadPaths: [IndexPath] = []
        for s in 0..<new.categories.count {
            let oldRows = computeRows(for: prev, categoryIndex: s)
            let newRows = rowsForSection(s)

            for r in 0..<newRows.count {
                guard r < oldRows.count else {
                    reloadPaths.append(IndexPath(row: r, section: s + sectionOffset))
                    continue
                }
                let oldRow = oldRows[r]
                let newRow = newRows[r]
                if Self.rowDiffKey(oldRow) != Self.rowDiffKey(newRow) {
                    reloadPaths.append(IndexPath(row: r, section: s + sectionOffset))
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
                    let ip = IndexPath(row: r, section: s + sectionOffset)
                    if listRowChangeIsSelectionOnly(
                        old: oldRow,
                        new: newRow,
                        prevSelected: prev.selectedChannelId,
                        newSelected: new.selectedChannelId,
                        prevVoice: prev.voiceUsersByChannel,
                        newVoice: new.voiceUsersByChannel
                    ) {
                        selectionPaths.append(ip)
                    } else {
                        reloadPaths.append(ip)
                    }
                }
            }
        }

        if !selectionPaths.isEmpty {
            applyInPlaceListSelection(paths: selectionPaths, new: new)
        }
        guard !reloadPaths.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadRows(at: reloadPaths, with: .none)
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
    }

    private func firstCategoryIndexContainingListChannel(_ channelId: Int64) -> Int? {
        let favIdx = state.categories.firstIndex(where: { $0.id == ChannelCategory.favoritesCategoryId })
        for s in 0..<state.categories.count {
            if s == favIdx { continue }
            let rows = rowsForSection(s)
            if rows.contains(where: { row in
                switch row {
                case .voiceMembersCollapsed, .voiceMemberExpanded: return false
                default: return row.channelDesc.channelID == channelId
                }
            }) {
                return s
            }
        }
        if let favIdx,
           let flat = state.categories[favIdx].favoriteFlatChannels,
           flat.contains(where: { $0.channelID == channelId }) {
            let rows = rowsForSection(favIdx)
            if rows.contains(where: { row in
                switch row {
                case .voiceMembersCollapsed, .voiceMemberExpanded: return false
                default: return row.channelDesc.channelID == channelId
                }
            }) {
                return favIdx
            }
        }
        return nil
    }

    private func indexPathForListChannel(channelId: Int64) -> IndexPath? {
        let sectionOffset = channelAppsStripeVisible ? 1 : 0
        guard let s = firstCategoryIndexContainingListChannel(channelId) else { return nil }
        let rows = rowsForSection(s)
        guard let r = rows.firstIndex(where: { row in
            switch row {
            case .voiceMembersCollapsed, .voiceMemberExpanded: return false
            default: return row.channelDesc.channelID == channelId
            }
        }) else { return nil }
        return IndexPath(row: r, section: s + sectionOffset)
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
        skipNextLoadingFinishedReveal = true
        scrollToChannel(channelId: id, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.interaction.onClearCurrentChannelSelection?()
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
        let headerHConstraint = headerSpacer.heightAnchor.constraint(equalToConstant: currentHeaderH)
        headerHConstraint.isActive = true
        headerSpacerHeightConstraint = headerHConstraint

        let tableHeader = UIStackView(arrangedSubviews: [bannerView, headerSpacer])
        tableHeader.axis = .vertical
        tableHeader.spacing = 0
        tableNode.view.tableHeaderView = tableHeader
        bannerView.isHidden = true
        applyClanHeaderMetrics(hasBanner: false)

        headerUIView.applyTheme()
        headerUIView.backgroundColor = UIColor.theme.secondary
        headerUIView.onSearchTapped = interaction.onSearchTapped
        headerUIView.onClanHeaderLongPress = { [weak self] in
            self?.presentClanActionSheetIfNeeded()
        }
        view.addSubview(headerUIView)
        headerUIView.layer.zPosition = 100

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

    private func reloadChannelAppsSectionOnly() {
        guard channelAppsStripeVisible else { return }
        guard tableNode.numberOfSections > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.performBatch(animated: false) {
                self.tableNode.reloadSections(IndexSet(integer: 0), with: .none)
            }
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
        let offset = channelAppsStripeVisible ? 1 : 0
        return section - offset
    }

    private var channelListLoadingPlaceholderVisible: Bool {
        state.isLoading && state.categories.isEmpty
    }

    private var loadingPlaceholderTableSection: Int {
        channelAppsStripeVisible ? 1 : 0
    }

    private func isLoadingPlaceholderTableSection(_ section: Int) -> Bool {
        channelListLoadingPlaceholderVisible && section == loadingPlaceholderTableSection
    }

    private var totalSections: Int {
        let appsSections = channelAppsStripeVisible ? 1 : 0
        if channelListLoadingPlaceholderVisible {
            return appsSections + 1
        }
        let catSections = state.categories.count
        return appsSections + catSections
    }

    var hasDisplayedChannelApps: Bool { !channelApps.isEmpty }

    func setChannelAppsLoadingIndicator(_ loading: Bool) {
        guard channelAppsLoading != loading else { return }
        let beforeHad = channelAppsStripeVisible
        channelAppsLoading = loading
        let afterHad = channelAppsStripeVisible
        cachedRows = [:]
        cachedHeaders = [:]
        if !beforeHad && afterHad {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.insertSections(IndexSet(integer: 0), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && !afterHad {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.deleteSections(IndexSet(integer: 0), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && afterHad {
            reloadChannelAppsSectionOnly()
        }
    }

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
        recomputeClanHeaderHeight()
        updateTableHeaderLayout()
        layoutNewUnreadButton(containerSize: layout.size, bottomInset: layout.intrinsicInsets.bottom)
    }

    private static let bannerKnownHeight: CGFloat = 140.sh

    private func applyClanHeaderMetrics(hasBanner: Bool) {
        hasClanBanner = hasBanner
        headerUIView.setClanBannerVisible(hasBanner)
        recomputeClanHeaderHeight()
    }

    @discardableResult
    private func recomputeClanHeaderHeight() -> CGFloat {
        let width = max(tableNode.bounds.width, view.bounds.width)
        guard width > 0 else { return currentHeaderH }
        headerUIView.bounds = CGRect(x: 0, y: 0, width: width, height: currentHeaderH)
        let fitting = headerUIView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let computed = max(headerHMin, ceil(fitting.height))
        if abs(currentHeaderH - computed) > 0.5 {
            currentHeaderH = computed
            headerSpacerHeightConstraint?.constant = computed
        }
        return currentHeaderH
    }

    private func updateStickyHeaderPosition() {
        recomputeClanHeaderHeight()
        let bannerHeight = hasClanBanner ? Self.bannerKnownHeight : 0
        let contentOffsetY = tableNode.view.contentOffset.y
        let headerY = max(0, bannerHeight - contentOffsetY)
        headerUIView.frame = CGRect(x: 0, y: stickyTopOffset + headerY, width: tableNode.bounds.width, height: currentHeaderH)
    }

    func markClanSwitching() {
        isClanSwitching = true
        memberCount = 0
        headerUIView.clearMemberSubtitleStaleText()
    }

    func clearChannelApps() {
        let hadStripe = channelAppsStripeVisible
        channelApps = []
        channelAppsLoading = false
        cachedRows = [:]
        cachedHeaders = [:]
        guard hadStripe else {
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

    func configure(clanName: String, clanId: Int64 = 0, logoURL: String? = nil, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        self.headerClanId = clanId
        self.clanLogoURL = logoURL ?? ""
        self.isCommunity = isCommunity
        self.memberCount = memberCount
        headerUIView.configure(title: clanName, memberCount: memberCount, isCommunity: isCommunity)
        isChannelAppsExpanded = true

        UIView.performWithoutAnimation {
            if let url = bannerURL, !url.isEmpty {
                applyClanHeaderMetrics(hasBanner: true)
                bannerView.isHidden = false
                bannerView.loadBanner(urlString: url)
            } else {
                applyClanHeaderMetrics(hasBanner: false)
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
        let beforeHadStripe = channelAppsStripeVisible
        channelAppsLoading = false
        if channelAppsUIEqual(channelApps, filtered), beforeHadStripe == (!filtered.isEmpty) { return }

        let beforeHad = beforeHadStripe
        channelApps = filtered
        let afterHad = channelAppsStripeVisible

        cachedRows = [:]
        cachedHeaders = [:]

        if !beforeHad && afterHad {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.insertSections(IndexSet(integer: 0), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && !afterHad {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.deleteSections(IndexSet(integer: 0), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
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

    private func presentClanActionSheetIfNeeded() {
        guard headerClanId != 0 else { return }
        presentClanActionSheet()
    }

    private func presentClanActionSheet() {
        guard let window = self.view.window as? WindowHost else { return }
        let actionSheet = ClanActionSheetController(
            clanName: headerUIView.title,
            avatarURL: clanLogoURL,
            memberCount: memberCount,
            isCommunity: isCommunity,
            onAction: { [weak self] action in
                guard let self else { return }
                if action == .settings {
                    self.interaction.onPresentSettings?()
                } else if action == .invite {
                    self.interaction.onInviteClan?()
                } else {
                }
            }
        )
        window.present(actionSheet, on: .root, blockInteraction: false, completion: {})
        actionSheet.animateIn()
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        skipNextLoadingFinishedReveal = true
        interaction.onRefresh?()
    }

    func endRefreshing() {
        tableNode.view.refreshControl?.endRefreshing()
    }

    private func channelAppsSectionRowCount() -> Int {
        guard channelAppsStripeVisible else { return 0 }
        if channelAppsLoading && channelApps.isEmpty {
            return isChannelAppsExpanded ? 1 : 0
        }
        if isCompactView {
            return isChannelAppsExpanded ? channelApps.count : 0
        }
        return isChannelAppsExpanded ? 1 : 0
    }

    private func toggleChannelAppsExpand() {
        guard channelAppsStripeVisible else { return }
        let oldCount = channelAppsSectionRowCount()
        isChannelAppsExpanded.toggle()
        let newCount = channelAppsSectionRowCount()
        guard oldCount != newCount else { return }
        guard tableNode.numberOfSections > 0,
            tableNode.numberOfRows(inSection: 0) == oldCount
        else {
            scheduleReload()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.performBatch(animated: false) {
                if newCount == 0 && oldCount > 0 {
                    let paths = (0..<oldCount).map { IndexPath(row: $0, section: 0) }
                        .sorted { $0.row > $1.row }
                    self.tableNode.deleteRows(at: paths, with: .none)
                } else if oldCount == 0 && newCount > 0 {
                    let paths = (0..<newCount).map { IndexPath(row: $0, section: 0) }
                    self.tableNode.insertRows(at: paths, with: .none)
                } else {
                    let del = (0..<oldCount).map { IndexPath(row: $0, section: 0) }
                        .sorted { $0.row > $1.row }
                    let ins = (0..<newCount).map { IndexPath(row: $0, section: 0) }
                    self.tableNode.deleteRows(at: del, with: .none)
                    self.tableNode.insertRows(at: ins, with: .none)
                }
            }
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
        if isCompactView, let header = cachedHeaders[0] {
            header.configureAppsHeader(isCollapsed: !isChannelAppsExpanded)
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        let useFlatBackground = Self.shouldUseFlatBackgroundForCurrentTheme
        gradientLayer.isHidden = useFlatBackground
        gradientLayer.colors = useFlatBackground ? [t.secondary.cgColor, t.secondary.cgColor] : [
            t.primaryGradient.cgColor,
            t.secondary.cgColor,
            t.secondary.cgColor,
            t.primaryGradient.cgColor
        ]
        backgroundColor = useFlatBackground ? t.secondary : .clear
        tableNode.backgroundColor = useFlatBackground ? t.secondary : .clear
        tableNode.view.backgroundColor = useFlatBackground ? t.secondary : .clear
        headerUIView.applyTheme()
        headerUIView.backgroundColor = useFlatBackground ? t.secondary : t.primaryGradient
        newUnreadButton.backgroundColor = UIColor.mezonUnreadBadge
        newUnreadButton.setTitleColor(.white, for: .normal)
        newUnreadButton.titleLabel?.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        scheduleReload()
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
                return hasMembers || ch.channelID == selectedChannelId
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
        if channelAppsStripeVisible && section == 0 {
            if channelAppsLoading && channelApps.isEmpty {
                return isChannelAppsExpanded ? 1 : 0
            }
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
        if channelAppsStripeVisible && indexPath.section == 0 {
            if channelAppsLoading && channelApps.isEmpty {
                return { ChannelAppSkeletonCellNode() }
            }
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
                node.onLongPress = { [weak self] in
                    self?.interaction.onLongPressChannel(ch)
                }
                return node
            }
        case .thread(let ch, let isLast, let inFav):
            return {
                let node = ThreadItemCellNode(channel: ch, isSelected: isSelected, isLast: isLast)
                node.onLongPress = { [weak self] in
                    self?.interaction.onLongPressChannel(ch)
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
        if channelAppsStripeVisible && section == 0 {
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
        if channelAppsStripeVisible && section == 0 {
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
        if channelAppsStripeVisible && indexPath.section == 0 {
            guard !channelAppsLoading else { return }
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
    var onClanHeaderLongPress: (() -> Void)?

    var title: String {
        return titleLabel.text ?? ""
    }

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.adjustsFontForContentSizeCategory = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        l.setContentHuggingPriority(.required, for: .vertical)
        l.lineBreakMode = .byTruncatingTail
        l.numberOfLines = 1
        return l
    }()

    private let memberCountLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.adjustsFontForContentSizeCategory = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        l.setContentHuggingPriority(.required, for: .vertical)
        l.numberOfLines = 1
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
        l.adjustsFontForContentSizeCategory = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        l.setContentHuggingPriority(.required, for: .vertical)
        l.numberOfLines = 1
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
        l.font = .systemFont(ofSize: 13)
        l.textAlignment = .center
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

    private var mainStackTopConstraint: NSLayoutConstraint!
    private let mainStackTopBase: CGFloat = 6
    private let topInsetExtraWhenNoClanBanner: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel])
        titleStack.axis = .horizontal
        titleStack.spacing = 4
        titleStack.alignment = .fill
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

        let clanTitleBlock = UIStackView(arrangedSubviews: [titleStack, infoRow])
        clanTitleBlock.axis = .vertical
        clanTitleBlock.spacing = 4
        clanTitleBlock.setCustomSpacing(2, after: titleStack)
        clanTitleBlock.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = UIStackView(arrangedSubviews: [clanTitleBlock, actionRow])
        mainStack.axis = .vertical
        mainStack.spacing = 4
        mainStack.setCustomSpacing(10, after: clanTitleBlock)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let mainTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleHeaderTap))
        mainStack.addGestureRecognizer(mainTapGesture)
        let clanHeaderLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleClanHeaderLongPress(_:)))
        clanHeaderLongPress.minimumPressDuration = 0.45
        clanHeaderLongPress.cancelsTouchesInView = false
        clanTitleBlock.addGestureRecognizer(clanHeaderLongPress)
        mainTapGesture.require(toFail: clanHeaderLongPress)
        mainStack.isUserInteractionEnabled = true
        clanTitleBlock.isUserInteractionEnabled = true

        addSubview(mainStack)
        addSubview(separator)

        mainStackTopConstraint = mainStack.topAnchor.constraint(
            equalTo: topAnchor, constant: mainStackTopBase)
        mainStackTopConstraint.isActive = true

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            communityDot.widthAnchor.constraint(equalToConstant: 4),
            communityDot.heightAnchor.constraint(equalToConstant: 4),

            searchBar.heightAnchor.constraint(equalToConstant: 32),
            searchIcon.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 22),
            searchIcon.heightAnchor.constraint(equalToConstant: 22),
            searchLabel.centerXAnchor.constraint(equalTo: searchBar.centerXAnchor),
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

    func setClanBannerVisible(_ visible: Bool) {
        mainStackTopConstraint.constant = visible
            ? mainStackTopBase
            : mainStackTopBase + topInsetExtraWhenNoClanBanner
    }

    @objc private func searchBarTapped() {
        onSearchTapped?()
    }

    @objc private func qrTapped() {
        onQRTapped?()
    }

    func clearMemberSubtitleStaleText() {
        memberCountLabel.text = ""
        memberCountLabel.isHidden = true
        communityDot.isHidden = true
    }

    func configure(title: String, memberCount: Int = 0, isCommunity: Bool = false) {
        titleLabel.text = title
        if memberCount > 0 {
            memberCountLabel.text = memberCount == 1 ? "\(memberCount) Member" : "\(memberCount) Members"
            memberCountLabel.isHidden = false
        } else {
            memberCountLabel.text = ""
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
            memberCountLabel.text = ""
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

    @objc private func handleClanHeaderLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onClanHeaderLongPress?()
    }
}
