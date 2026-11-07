import AsyncDisplayKit
import UIKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onLongPressChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
    let onRefresh: (() -> Void)?
    let onPresentSettings: (() -> Void)?
    let onPresentClanNotifications: (() -> Void)?
    let onInviteClan: (() -> Void)?
    let onCreateCategory: (() -> Void)?
    let onCreateEvent: (() -> Void)?
    let canCreateCategory: (() -> Bool)?
    let isClanOwner: (() -> Bool)?
    let onLeaveClan: (() -> Void)?
    let onDeleteClan: (() -> Void)?
    let onMarkClanAsRead: (() -> Void)?
    let onSearchTapped: (() -> Void)?
    let onQRTapped: (() -> Void)?
    let onEventTapped: (() -> Void)?
    let onSelectChannelApp: ((Mezon_Api_ChannelAppResponse) -> Void)?
    let onClearCurrentChannelSelection: (() -> Void)?
    let isShowEmptyCategoriesEnabled: (() -> Bool)?
    let onToggleShowEmptyCategories: ((Bool) -> Void)?
    let onLongPressCategory: ((ChannelCategory) -> Void)?
    let onBecameVisible: (() -> Void)?
    let onOnboardingBannerTapped: (() -> Void)?
    let onClanSwitchChannelListApplied: (() -> Void)?
}

final class ChannelListContainerNode: ASDisplayNode {

    private(set) var tableNode: ASTableNode
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
    private let gradientLayer = CAGradientLayer()
    private let headerGradientLayer = CAGradientLayer()

    private var state: ChannelListState = .empty
    private var threadLookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]

    private var cachedRows: [Int: [ChannelListRow]] = [:]

    private static let categoryHeaderRowCount = 1

    private func channelIndexPath(row: Int, section: Int) -> IndexPath {
        IndexPath(row: row + Self.categoryHeaderRowCount, section: section)
    }

    private func channelRowIndex(for indexPath: IndexPath) -> Int {
        indexPath.row - Self.categoryHeaderRowCount
    }

    private var committedSectionCount: Int = 0
    private let interaction: ChannelListInteraction
    private let disposables = DisposableSet()
    private var isClanSwitching = false
    private var deferOnboardingTableUpdates = false
    private var clanSwitchTableRefreshDone = false
    private var animateNextContentReplace = false

    private var shouldDeferLeadingSectionTableMutations: Bool {
        isClanSwitching || deferOnboardingTableUpdates || !tableIsInWindow
    }
    private var nodeIsVisible = false
    private var pendingVisibleReconcile = false
    private var pendingVisibleReconcileShouldResetScroll = false
    private var ghostRowCheckWorkItems: [DispatchWorkItem] = []
    private var ghostRowHealStage = 0
    private var ghostRowHealStarts: [Date] = []
    private var ghostRowPendingReport: [String: Any]?
    private var ghostRowReportsSent = 0

    private var latestCoalescedChannelListState: ChannelListState?
    private var channelListStateApplyScheduled = false

    private var clanLogoURL: String = ""
    private var headerClanId: Int64 = 0
    private var hasConfiguredClan = false
    private var clanSwitchGeneration: UInt64 = 0
    private var appliedClanSwitchGeneration: UInt64 = 0
    private var hasCurrentClanState: Bool {
        !hasConfiguredClan || state.clanId == headerClanId
    }

    @discardableResult
    private func updateClanIdentity(_ clanId: Int64) -> Bool {
        let clanChanged = !hasConfiguredClan || headerClanId != clanId
        hasConfiguredClan = true
        guard clanChanged else { return false }
        headerClanId = clanId
        clanSwitchGeneration &+= 1
        if state.clanId == clanId, latestCoalescedChannelListState?.clanId != clanId {
            enqueueChannelListState(state)
        }
        return true
    }

    private var isCommunity: Bool = false
    private var memberCount: Int = 0
    private var onboardingState: ClanOnboardingViewState = .hidden
    private var memberOnboardingState: MemberOnboardingViewState = .hidden
    private var onboardingBannerVisible: Bool { onboardingState.isVisible || memberOnboardingState.isVisible }
    private var showsCreatorOnboardingBanner: Bool { onboardingState.isVisible }

    private var leadingTableSectionsCount: Int {
        (onboardingBannerVisible ? 1 : 0) + (channelAppsStripeVisible ? 1 : 0)
    }

    private var onboardingTableSection: Int { 0 }

    private var channelAppsTableSection: Int {
        onboardingBannerVisible ? 1 : 0
    }

    private func isOnboardingTableSection(_ section: Int) -> Bool {
        onboardingBannerVisible && section == onboardingTableSection
    }

    private func isChannelAppsTableSection(_ section: Int) -> Bool {
        guard channelAppsStripeVisible else { return false }
        return section == channelAppsTableSection
    }

    private var pendingChannelAppsTableSync = false
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
        tableNode.backgroundColor = UIColor.theme.secondary

        headerUIView.onQRTapped = { [weak self] in
            self?.interaction.onQRTapped?()
        }

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                self?.enqueueChannelListState(newState)
            })
        )
    }

    private func enqueueChannelListState(_ newState: ChannelListState) {
        guard !hasConfiguredClan || newState.clanId == headerClanId else { return }
        latestCoalescedChannelListState = newState
        scheduleApplyCoalescedChannelListState()
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
        guard !hasConfiguredClan || newState.clanId == headerClanId else { return }
        let prevState = state
        if let msg = newState.errorMessage, msg != prevState.errorMessage {

        }

        let wasClanSwitching = isClanSwitching
        let clanChanged = prevState.clanId != newState.clanId
            || appliedClanSwitchGeneration != clanSwitchGeneration
        appliedClanSwitchGeneration = clanSwitchGeneration
        state = newState
        threadLookup = buildThreadLookup(newState.allChannels)
        cachedRows = [:]

        let prevCats = prevState.categories
        let newCats = newState.categories
        let loadingPHNow = newState.isLoading && newState.categories.isEmpty
        let loadingPHWas = prevState.isLoading && prevState.categories.isEmpty
        let loadingPlaceholderToggled = loadingPHNow != loadingPHWas
        let treeStructureChanged = loadingPlaceholderToggled
            || prevCats.count != newCats.count
            || !categoriesChannelTreeEqual(prevCats, newCats)
        let revealingFromLoadingPlaceholder = loadingPHWas && !loadingPHNow && !newCats.isEmpty

        isClanSwitching = (wasClanSwitching || clanChanged) && newState.isLoading

        let shouldAnimateReplace = animateNextContentReplace
        animateNextContentReplace = false

        if !tableIsInWindow {
            if wasClanSwitching || clanChanged {
                interaction.onClanSwitchChannelListApplied?()
                clanSwitchTableRefreshDone = true
                deferOnboardingTableUpdates = false
            }
            if clanChanged || treeStructureChanged || revealingFromLoadingPlaceholder || !newCats.isEmpty {
                pendingVisibleReconcile = true
                pendingVisibleReconcileShouldResetScroll =
                    pendingVisibleReconcileShouldResetScroll || wasClanSwitching || clanChanged
            }
            safeReloadData()
        } else if shouldAnimateReplace && !wasClanSwitching && !clanChanged && nodeIsVisible && tableIsInWindow && treeStructureChanged {
            crossfadeReloadAnimated()
        } else if wasClanSwitching || clanChanged {
            interaction.onClanSwitchChannelListApplied?()
            if clanChanged || !clanSwitchTableRefreshDone {
                if nodeIsVisible {
                    applyCrossfadeReload()
                } else {
                    pendingVisibleReconcile = true
                    pendingVisibleReconcileShouldResetScroll = true
                    safeReloadData()
                }
                clanSwitchTableRefreshDone = true
                deferOnboardingTableUpdates = false
            } else if revealingFromLoadingPlaceholder && tableIsInWindow {
                crossfadeReloadAnimated(duration: 0.15)
            } else if treeStructureChanged {
                applyBatchStructureUpdate(prev: prevState, new: newState)
            } else if !newCats.isEmpty {
                applyRowDiff(prev: prevState, new: newState)
            }
            reconcileChannelAppsTableIfNeeded()
        } else if !nodeIsVisible && treeStructureChanged {
            pendingVisibleReconcile = true
            pendingVisibleReconcileShouldResetScroll = false
            safeReloadData()
        } else if revealingFromLoadingPlaceholder && tableIsInWindow {
            crossfadeReloadAnimated(duration: 0.15)
        } else if treeStructureChanged {
            applyBatchStructureUpdate(prev: prevState, new: newState)
        } else if !newCats.isEmpty {
            applyRowDiff(prev: prevState, new: newState)
        }

        maybeRevealSelectedChannel(prevState: prevState, newState: newState, wasClanSwitching: wasClanSwitching || clanChanged)
        refreshNewUnreadButton()
        if !isClanSwitching {
            reconcileChannelAppsTableIfNeeded()
        }
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
        let selectedIsVoiceChannel = newState.allChannels.contains {
            $0.channelID == selectedId && Self.voiceChannelTypes.contains($0.type)
        }
        let prevSelectedVoiceEmpty = (prevState.voiceUsersByChannel[selectedId] ?? []).isEmpty
        let newSelectedVoiceActive = !(newState.voiceUsersByChannel[selectedId] ?? []).isEmpty
        let selectedVoiceBecameActive = prevSelectedVoiceEmpty && newSelectedVoiceActive
        if loadingJustFinished && skipNextLoadingFinishedReveal {
            skipNextLoadingFinishedReveal = false
            if !(wasClanSwitching || selectionChanged || (selectedIsVoiceChannel && selectedVoiceBecameActive)) {
                return
            }
        }
        guard wasClanSwitching || selectionChanged || loadingJustFinished || (selectedIsVoiceChannel && selectedVoiceBecameActive) else { return }
        scrollToChannel(channelId: selectedId, animated: !wasClanSwitching, onlyIfStillSelected: true)
    }

    func suppressNextLoadingFinishedReveal() {
        skipNextLoadingFinishedReveal = true
    }

    private func scheduleGhostRowChecks() {
        cancelGhostRowChecks()
        for delay in [0.8, 3.0] {
            let item = DispatchWorkItem { [weak self] in self?.runGhostRowCheck() }
            ghostRowCheckWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func cancelGhostRowChecks() {
        ghostRowCheckWorkItems.forEach { $0.cancel() }
        ghostRowCheckWorkItems = []
    }

    private func visibleGhostRowSamples() -> [(IndexPath, UITableViewCell, String)] {
        let tv = tableNode.view
        var samples: [(IndexPath, UITableViewCell, String)] = []
        for cell in tv.visibleCells {
            guard let indexPath = tv.indexPath(for: cell), let node = tableNode.nodeForRow(at: indexPath) else { continue }
            switch node {
            case is ChannelItemCellNode: samples.append((indexPath, cell, "channel"))
            case is ThreadItemCellNode: samples.append((indexPath, cell, "thread"))
            default: continue
            }
        }
        return samples
    }

    private func runGhostRowCheck() {
        guard isNodeLoaded, nodeIsVisible, tableIsInWindow else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        let tv = tableNode.view
        guard !tv.isDragging, !tv.isDecelerating, !tv.isTracking else { return }
        let samples = visibleGhostRowSamples()
        guard !samples.isEmpty else { return }
        var exclusions = [headerUIView.frame]
        if !newUnreadButton.isHidden { exclusions.append(newUnreadButton.frame) }
        let rows = samples.map {
            ChannelListGhostRowProbe.RowSample(indexPath: $0.0, kind: $0.2, rect: $0.1.convert($0.1.bounds, to: view))
        }
        let t = UIColor.theme
        guard let probe = ChannelListGhostRowProbe.measure(
            container: view,
            rows: rows,
            referenceRects: [headerUIView.frame],
            exclusionRects: exclusions,
            backgroundColor: t.secondary,
            rowTextColor: t.channelNormal
        ), probe.isTrusted else { return }
        if probe.dimRows.count < 2 {
            if ghostRowHealStage > 0 {
                finishGhostRowHeal(healed: true, probe: probe)
            }
            return
        }
        handleGhostRows(probe: probe, samples: samples)
    }

    private func handleGhostRows(probe: ChannelListGhostRowProbe.Result, samples: [(IndexPath, UITableViewCell, String)]) {
        switch ghostRowHealStage {
        case 0:
            let now = Date()
            ghostRowHealStarts = ghostRowHealStarts.filter { now.timeIntervalSince($0) < 600 }
            guard ghostRowHealStarts.count < 3 else { return }
            ghostRowHealStarts.append(now)
            let dimPaths = Set(probe.dimRows.map { $0.indexPath })
            let dimCells = samples.filter { dimPaths.contains($0.0) }.map { ($0.0, $0.1) }
            ghostRowPendingReport = [
                "ios": UIDevice.current.systemVersion,
                "theme": ThemeManager.shared.current.rawValue,
                "rows": probe.summary,
                "expectedContrast": Int(probe.expectedRowContrast),
                "referenceContrast": Int(probe.referenceContrast),
                "dump": ChannelListGhostRowProbe.dump(table: tableNode.view, cells: dimCells),
            ]
            SentryLogger.addBreadcrumb(
                category: "channel_list.ghost_rows",
                message: "detected dim=\(dimPaths.count)/\(probe.rows.count)"
            )
            ghostRowHealStage = 1
            cachedRows = [:]
            safeReloadData()
            scheduleGhostRowChecks()
        case 1:
            ghostRowHealStage = 2
            ghostRowPendingReport?["afterReload"] = probe.summary
            rebuildTableNode()
            scheduleGhostRowChecks()
        default:
            finishGhostRowHeal(healed: false, probe: probe)
        }
    }

    private func finishGhostRowHeal(healed: Bool, probe: ChannelListGhostRowProbe.Result) {
        let stage = ghostRowHealStage
        ghostRowHealStage = 0
        guard var report = ghostRowPendingReport else { return }
        ghostRowPendingReport = nil
        let healedBy = healed ? (stage == 1 ? "reload" : "rebuild") : "none"
        report["healedBy"] = healedBy
        report["final"] = probe.summary
        if ghostRowReportsSent < 2 {
            ghostRowReportsSent += 1
            SentryLogger.capture(message: "channel_list.ghost_rows", extras: report)
        } else {
            SentryLogger.addBreadcrumb(category: "channel_list.ghost_rows", message: "healedBy=\(healedBy)")
        }
    }

    private func rebuildTableNode() {
        let old = tableNode
        let frame = old.frame
        let offset = old.view.contentOffset
        let backgroundColor = old.backgroundColor
        let viewBackgroundColor = old.view.backgroundColor
        let tableHeader = old.view.tableHeaderView
        old.delegate = nil
        old.dataSource = nil
        old.view.tableHeaderView = nil
        old.removeFromSupernode()

        let fresh = ASTableNode(style: .plain)
        fresh.frame = frame
        tableNode = fresh
        addSubnode(fresh)
        configureTableNodeView(fresh)
        fresh.backgroundColor = backgroundColor
        fresh.view.backgroundColor = viewBackgroundColor
        fresh.view.tableHeaderView = tableHeader
        view.bringSubviewToFront(headerUIView)
        view.bringSubviewToFront(newUnreadButton)
        cachedRows = [:]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            fresh.reloadData()
            fresh.waitUntilAllUpdatesAreProcessed()
            fresh.view.layoutIfNeeded()
        }
        CATransaction.commit()
        committedSectionCount = totalSections
        restoreContentOffset(offset)
        updateTableHeaderLayout()
        updateStickyHeaderPosition()
    }

    private var tableIsInWindow: Bool {
        tableNode.isNodeLoaded && tableNode.view.window != nil
    }

    private func safeReloadData(preserving scrollAnchor: ScrollAnchor? = nil, preserveContentOffset: Bool = true) {
        pendingChannelAppsTableSync = false
        guard tableIsInWindow else {
            if tableNode.isNodeLoaded {
                UIView.performWithoutAnimation { self.tableNode.reloadData() }
            }
            committedSectionCount = totalSections
            return
        }
        let previousOffset = tableNode.view.contentOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadData()
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
        committedSectionCount = totalSections
        if let scrollAnchor {
            restoreScrollPositionAfterUpdate(anchor: scrollAnchor)
        } else if preserveContentOffset {
            if isPinnedNearListTop() {
                pinListToTopIfNeeded()
            } else {
                restoreContentOffset(previousOffset)
            }
        }
    }

    private func applyCrossfadeReload(resetScroll: Bool = true) {
        pendingChannelAppsTableSync = false
        guard tableIsInWindow else {
            if tableNode.isNodeLoaded {
                UIView.performWithoutAnimation { self.tableNode.reloadData() }
            }
            committedSectionCount = totalSections
            return
        }
        let previousOffset = tableNode.view.contentOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadData()
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        if resetScroll {
            tableNode.view.contentOffset = .zero
        }
        CATransaction.commit()
        committedSectionCount = totalSections
        if !resetScroll {
            restoreContentOffset(previousOffset)
        }
        updateStickyHeaderPosition()
    }

    func animateNextDataReplace() {
        animateNextContentReplace = true
    }

    private func crossfadeReloadAnimated(duration _: TimeInterval = 0.1) {
        pendingChannelAppsTableSync = false
        guard tableIsInWindow else {
            if tableNode.isNodeLoaded {
                UIView.performWithoutAnimation { self.tableNode.reloadData() }
            }
            committedSectionCount = totalSections
            return
        }
        let previousOffset = tableNode.view.contentOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadData()
            self.tableNode.waitUntilAllUpdatesAreProcessed()
            self.restoreContentOffset(previousOffset)
        }
        CATransaction.commit()
        committedSectionCount = totalSections
        updateStickyHeaderPosition()
    }

    private func categorySectionOffset(for prev: ChannelListState) -> Int {
        guard !(prev.isLoading && prev.categories.isEmpty) else {
            return leadingTableSectionsCount
        }
        let fromCommitted = committedSectionCount - prev.categories.count
        return fromCommitted >= 0 ? fromCommitted : leadingTableSectionsCount
    }

    private func channelListLoadingPlaceholderVisible(for state: ChannelListState) -> Bool {
        state.isLoading && state.categories.isEmpty
    }

    private func applyCategorySectionCountDelta(prev: ChannelListState, new: ChannelListState) -> Bool {
        if channelListLoadingPlaceholderVisible(for: prev)
            || channelListLoadingPlaceholderVisible(for: new) {
            return false
        }
        let sectionOffset = categorySectionOffset(for: prev)
        guard sectionOffset == leadingTableSectionsCount else { return false }
        let prevIds = prev.categories.map(\.id)
        let newIds = new.categories.map(\.id)
        guard prevIds != newIds else { return false }

        let scrollAnchor = isPinnedNearListTop() ? nil : captureScrollAnchor(prev: prev)

        if newIds.count == prevIds.count + 1 {
            for insertAt in 0..<newIds.count {
                var trial = newIds
                trial.remove(at: insertAt)
                guard trial == prevIds else { continue }
                var survivingRowsConsistent = true
                for prevIdx in 0..<prevIds.count {
                    let committedSection = prevIdx + sectionOffset
                    guard committedSection < tableNode.numberOfSections else { survivingRowsConsistent = false; break }
                    let mappedNewIdx = prevIdx < insertAt ? prevIdx : prevIdx + 1
                    if tableNode.numberOfRows(inSection: committedSection) != computeRows(for: new, categoryIndex: mappedNewIdx, threadLookup: threadLookup).count + Self.categoryHeaderRowCount {
                        survivingRowsConsistent = false
                        break
                    }
                }
                guard survivingRowsConsistent else {
                    safeReloadData(preserving: scrollAnchor)
                    return true
                }
                let section = insertAt + sectionOffset
                guard section <= tableNode.numberOfSections else {
                    safeReloadData(preserving: scrollAnchor)
                    return true
                }
                var adjustedPrev = prev
                var adjustedCategories = prev.categories
                adjustedCategories.insert(new.categories[insertAt], at: insertAt)
                adjustedPrev.categories = adjustedCategories
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    self.tableNode.insertSections(IndexSet(integer: section), with: .none)
                    self.tableNode.waitUntilAllUpdatesAreProcessed()
                }
                CATransaction.commit()
                committedSectionCount = tableNode.numberOfSections
                applyBatchStructureUpdate(prev: adjustedPrev, new: new)
                restoreScrollPositionAfterUpdate(anchor: scrollAnchor)
                return true
            }
        }

        if prevIds.count == newIds.count + 1 {
            for deleteAt in 0..<prevIds.count {
                var trial = prevIds
                trial.remove(at: deleteAt)
                guard trial == newIds else { continue }
                var survivingRowsConsistent = true
                for prevIdx in 0..<prevIds.count where prevIdx != deleteAt {
                    let committedSection = prevIdx + sectionOffset
                    guard committedSection < tableNode.numberOfSections else { survivingRowsConsistent = false; break }
                    let mappedNewIdx = prevIdx < deleteAt ? prevIdx : prevIdx - 1
                    if tableNode.numberOfRows(inSection: committedSection) != computeRows(for: new, categoryIndex: mappedNewIdx, threadLookup: threadLookup).count + Self.categoryHeaderRowCount {
                        survivingRowsConsistent = false
                        break
                    }
                }
                guard survivingRowsConsistent else {
                    safeReloadData(preserving: scrollAnchor)
                    return true
                }
                let section = deleteAt + sectionOffset
                guard section < tableNode.numberOfSections else {
                    safeReloadData(preserving: scrollAnchor)
                    return true
                }
                var adjustedPrev = prev
                var adjustedCategories = prev.categories
                adjustedCategories.remove(at: deleteAt)
                adjustedPrev.categories = adjustedCategories
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    self.tableNode.deleteSections(IndexSet(integer: section), with: .none)
                    self.tableNode.waitUntilAllUpdatesAreProcessed()
                }
                CATransaction.commit()
                committedSectionCount = tableNode.numberOfSections
                applyBatchStructureUpdate(prev: adjustedPrev, new: new)
                restoreScrollPositionAfterUpdate(anchor: scrollAnchor)
                return true
            }
        }

        return false
    }

    private func applyBatchStructureUpdate(prev: ChannelListState, new: ChannelListState) {
        let expectedAfter = totalSections
        let prevThreadLookup = buildThreadLookup(prev.allChannels)
        let fallbackScrollAnchor = isPinnedNearListTop() ? nil : captureScrollAnchor(prev: prev)

        if channelListLoadingPlaceholderVisible(for: prev)
            != channelListLoadingPlaceholderVisible(for: new) {
            safeReloadData(preserving: fallbackScrollAnchor)
            return
        }

        guard committedSectionCount == tableNode.numberOfSections else {
            safeReloadData(preserving: fallbackScrollAnchor)
            return
        }

        let sectionOffset = leadingTableSectionsCount
        let prevCatSections = committedSectionCount - sectionOffset
        let newCatSections = expectedAfter - sectionOffset
        let canPatch = prevCatSections == newCatSections
            && prevCatSections == prev.categories.count
            && newCatSections == new.categories.count
            && zip(prev.categories, new.categories).allSatisfy({ $0.id == $1.id })

        guard canPatch else {
            if applyCategorySectionCountDelta(prev: prev, new: new) {
                committedSectionCount = expectedAfter
                return
            }
            safeReloadData(preserving: fallbackScrollAnchor)
            return
        }

        var sectionsToReload = IndexSet()
        var rowsToInsert: [IndexPath] = []
        var rowsToDelete: [IndexPath] = []
        var rowsToReload: [IndexPath] = []
        var newRowCountBySection: [Int: Int] = [:]

        for i in 0..<newCatSections {
            let pc = prev.categories[i]
            let nc = new.categories[i]
            let section = i + sectionOffset

            let oldRows = computeRows(for: prev, categoryIndex: i, threadLookup: prevThreadLookup)

            if isNodeLoaded,
               section < tableNode.numberOfSections,
               tableNode.numberOfRows(inSection: section) != oldRows.count + Self.categoryHeaderRowCount {
                sectionsToReload.insert(section)
                continue
            }

            if pc.isCollapsed != nc.isCollapsed || pc.name != nc.name {
                rowsToReload.append(IndexPath(row: 0, section: section))
            }

            let newRows = rowsForSection(i)
            newRowCountBySection[section] = newRows.count + Self.categoryHeaderRowCount

            let oldKeys = oldRows.map { Self.rowDiffKey($0) }
            let newKeys = newRows.map { Self.rowDiffKey($0) }

            if oldKeys == newKeys {
                for (r, row) in newRows.enumerated() {
                    if channelRowDataChanged(
                        old: oldRows[r], new: row,
                        prevSelected: prev.selectedChannelId,
                        newSelected: new.selectedChannelId,
                        prevVoice: prev.voiceUsersByChannel,
                        newVoice: new.voiceUsersByChannel,
                        prevStreamCounts: prev.streamViewerCounts,
                        newStreamCounts: new.streamViewerCounts,
                        prevBuzz: prev.buzzChannelIds,
                        newBuzz: new.buzzChannelIds
                    ) {
                        rowsToReload.append(channelIndexPath(row: r, section: section))
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
                rowsToDelete.append(channelIndexPath(row: r, section: section))
            }
            for (r, key) in newKeys.enumerated() where !oldKeySet.contains(key) {
                rowsToInsert.append(channelIndexPath(row: r, section: section))
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
                    newVoice: new.voiceUsersByChannel,
                    prevStreamCounts: prev.streamViewerCounts,
                    newStreamCounts: new.streamViewerCounts,
                    prevBuzz: prev.buzzChannelIds,
                    newBuzz: new.buzzChannelIds
                ) {
                    rowsToReload.append(channelIndexPath(row: newR, section: section))
                }
            }
        }

        var insertsBySection: [Int: Int] = [:]
        var deletesBySection: [Int: Int] = [:]
        for ip in rowsToInsert { insertsBySection[ip.section, default: 0] += 1 }
        for ip in rowsToDelete { deletesBySection[ip.section, default: 0] += 1 }
        for section in Set(insertsBySection.keys).union(deletesBySection.keys) {
            guard !sectionsToReload.contains(section) else { continue }
            guard isNodeLoaded, section < tableNode.numberOfSections else {
                sectionsToReload.insert(section)
                continue
            }
            let committed = tableNode.numberOfRows(inSection: section)
            let expected = committed + (insertsBySection[section] ?? 0) - (deletesBySection[section] ?? 0)
            if expected != (newRowCountBySection[section] ?? committed) {
                sectionsToReload.insert(section)
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

            let scrollAnchor = isPinnedNearListTop() ? nil : captureScrollAnchor(prev: prev)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
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
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()

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

            restoreScrollPositionAfterUpdate(anchor: scrollAnchor)
        }
        committedSectionCount = expectedAfter
    }

    private var listTopContentOffsetY: CGFloat {
        -tableNode.view.adjustedContentInset.top
    }

    private func isPinnedNearListTop(threshold: CGFloat = 12) -> Bool {
        abs(tableNode.view.contentOffset.y - listTopContentOffsetY) <= threshold
    }

    private func pinListToTopIfNeeded() {
        guard isPinnedNearListTop() else { return }
        restoreContentOffset(CGPoint(x: tableNode.view.contentOffset.x, y: listTopContentOffsetY))
    }

    private func restoreScrollPositionAfterUpdate(anchor: ScrollAnchor?) {
        if isPinnedNearListTop() {
            pinListToTopIfNeeded()
        } else if let anchor {
            restoreScrollAnchor(anchor)
        }
    }

    private struct ScrollAnchor {
        let key: String
        let section: Int
        let distanceFromTop: CGFloat
    }

    private func captureScrollAnchor(prev: ChannelListState) -> ScrollAnchor? {
        let tv = tableNode.view
        guard tv.bounds.height > 0 else { return nil }
        guard let visible = tv.indexPathsForVisibleRows, !visible.isEmpty else { return nil }
        let offsetY = tv.contentOffset.y
        let sectionOffset = leadingTableSectionsCount
        let sorted = visible.sorted {
            $0.section != $1.section ? $0.section < $1.section : $0.row < $1.row
        }

        func makeAnchor(_ ip: IndexPath, _ row: ChannelListRow) -> ScrollAnchor? {
            let rect = tv.rectForRow(at: ip)
            guard rect.height > 0 else { return nil }
            return ScrollAnchor(
                key: Self.rowDiffKey(row),
                section: ip.section,
                distanceFromTop: rect.minY - offsetY
            )
        }

        let prevThreadLookup = buildThreadLookup(prev.allChannels)
        var oldRowsByCat: [Int: [ChannelListRow]] = [:]
        var firstVisibleAnchor: ScrollAnchor?
        for ip in sorted {
            guard ip.section >= sectionOffset else { continue }
            let catIdx = ip.section - sectionOffset
            guard catIdx >= 0, catIdx < prev.categories.count else { continue }
            let oldRows: [ChannelListRow]
            if let cached = oldRowsByCat[catIdx] {
                oldRows = cached
            } else {
                oldRows = computeRows(for: prev, categoryIndex: catIdx, threadLookup: prevThreadLookup)
                oldRowsByCat[catIdx] = oldRows
            }
            let rowIndex = channelRowIndex(for: ip)
            guard oldRows.indices.contains(rowIndex) else { continue }
            let row = oldRows[rowIndex]
            guard let anchor = makeAnchor(ip, row) else { continue }
            if firstVisibleAnchor == nil { firstVisibleAnchor = anchor }
            switch row {
            case .voiceMembersCollapsed, .voiceMemberExpanded:
                continue
            default:
                return anchor
            }
        }
        return firstVisibleAnchor
    }

    private func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        let tv = tableNode.view
        let sectionOffset = leadingTableSectionsCount
        let preferredSection = anchor.section >= sectionOffset ? anchor.section : nil
        guard let indexPath = indexPathForRowDiffKey(anchor.key, preferredSection: preferredSection) else { return }
        let rect = tv.rectForRow(at: indexPath)
        guard rect.height > 0 else { return }
        let targetY = rect.minY - anchor.distanceFromTop
        restoreContentOffset(CGPoint(x: tv.contentOffset.x, y: targetY))
    }

    private func indexPathForRowDiffKey(_ key: String, preferredSection: Int?) -> IndexPath? {
        let sectionOffset = leadingTableSectionsCount
        func lookup(in section: Int) -> IndexPath? {
            guard section >= sectionOffset, section < tableNode.numberOfSections else { return nil }
            let catIdx = section - sectionOffset
            guard catIdx >= 0, catIdx < state.categories.count else { return nil }
            let rows = rowsForSection(catIdx)
            guard let row = rows.firstIndex(where: { Self.rowDiffKey($0) == key }) else { return nil }
            let indexPath = channelIndexPath(row: row, section: section)
            guard indexPath.row < tableNode.numberOfRows(inSection: section) else { return nil }
            return indexPath
        }
        if let preferredSection, let indexPath = lookup(in: preferredSection) {
            return indexPath
        }
        guard sectionOffset < tableNode.numberOfSections else { return nil }
        for section in sectionOffset..<tableNode.numberOfSections {
            if let indexPath = lookup(in: section) {
                return indexPath
            }
        }
        return nil
    }

    private func restoreContentOffset(_ offset: CGPoint) {
        let tv = tableNode.view
        let minY = -tv.adjustedContentInset.top
        let maxY = max(minY, tv.contentSize.height - tv.bounds.height + tv.adjustedContentInset.bottom)
        let clamped = min(max(offset.y, minY), maxY)
        guard abs(clamped - tv.contentOffset.y) > 0.5 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tv.setContentOffset(CGPoint(x: offset.x, y: clamped), animated: false)
        CATransaction.commit()
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
        newVoice: [Int64: [String]],
        prevStreamCounts: [Int64: Int],
        newStreamCounts: [Int64: Int],
        prevBuzz: Set<Int64>,
        newBuzz: Set<Int64>
    ) -> Bool {
        channelListRowVisuallyChanged(
            old: old, new: new,
            prevSelected: prevSelected, newSelected: newSelected,
            prevVoice: prevVoice, newVoice: newVoice,
            prevStreamCounts: prevStreamCounts, newStreamCounts: newStreamCounts,
            prevBuzz: prevBuzz, newBuzz: newBuzz
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
        if o.topic != n.topic { return false }
        if o.categoryID != n.categoryID { return false }
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
        if o.topic != n.topic { return false }
        if o.categoryID != n.categoryID { return false }
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
        newVoice: [Int64: [String]],
        prevStreamCounts: [Int64: Int],
        newStreamCounts: [Int64: Int],
        prevBuzz: Set<Int64>,
        newBuzz: Set<Int64>
    ) -> Bool {
        if rowBuzzChanged(old: old, new: new, prevBuzz: prevBuzz, newBuzz: newBuzz) { return false }
        switch (old, new) {
        case let (.channel(o, _), .channel(n, _)):
            guard o.channelID == n.channelID else { return false }
            if o.type == MezonConstants.ChannelType.streaming.rawValue,
               prevStreamCounts[o.channelID] != newStreamCounts[n.channelID] { return false }
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
        let sectionOffset = leadingTableSectionsCount
        let prevThreadLookup = buildThreadLookup(prev.allChannels)
        var oldRowsByCat: [Int: [ChannelListRow]] = [:]
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
            let oldRows: [ChannelListRow]
            if let cached = oldRowsByCat[catIdx] {
                oldRows = cached
            } else {
                oldRows = computeRows(for: prev, categoryIndex: catIdx, threadLookup: prevThreadLookup)
                oldRowsByCat[catIdx] = oldRows
            }
            let newRows = rowsForSection(catIdx)
            let rowIndex = channelRowIndex(for: ip)
            guard oldRows.indices.contains(rowIndex), newRows.indices.contains(rowIndex) else {
                fullPaths.append(ip)
                continue
            }
            let oldRow = oldRows[rowIndex]
            let newRow = newRows[rowIndex]
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
                newVoice: new.voiceUsersByChannel,
                prevStreamCounts: prev.streamViewerCounts,
                newStreamCounts: new.streamViewerCounts,
                prevBuzz: prev.buzzChannelIds,
                newBuzz: new.buzzChannelIds
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
        let sectionOffset = leadingTableSectionsCount
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for ip in paths {
            guard ip.section >= sectionOffset else { continue }
            let catIdx = ip.section - sectionOffset
            guard catIdx >= 0, catIdx < new.categories.count else { continue }
            let newRows = rowsForSection(catIdx)
            let rowIndex = channelRowIndex(for: ip)
            guard newRows.indices.contains(rowIndex) else { continue }
            guard let cellNode = tableNode.nodeForRow(at: ip) else { continue }
            switch newRows[rowIndex] {
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

    private func rowBuzzChanged(
        old: ChannelListRow,
        new: ChannelListRow,
        prevBuzz: Set<Int64>,
        newBuzz: Set<Int64>
    ) -> Bool {
        switch (old, new) {
        case (.channel, .channel), (.thread, .thread):
            return prevBuzz.contains(old.channelDesc.channelID) != newBuzz.contains(new.channelDesc.channelID)
        default:
            return false
        }
    }

    private func channelListRowVisuallyChanged(
        old: ChannelListRow,
        new: ChannelListRow,
        prevSelected: Int64?,
        newSelected: Int64?,
        prevVoice: [Int64: [String]],
        newVoice: [Int64: [String]],
        prevStreamCounts: [Int64: Int],
        newStreamCounts: [Int64: Int],
        prevBuzz: Set<Int64>,
        newBuzz: Set<Int64>
    ) -> Bool {
        if rowBuzzChanged(old: old, new: new, prevBuzz: prevBuzz, newBuzz: newBuzz) { return true }
        switch (old, new) {
        case let (.channel(o, _), .channel(n, _)):
            guard o.channelID == n.channelID else { return true }
            if o.type == MezonConstants.ChannelType.streaming.rawValue,
               prevStreamCounts[o.channelID] != newStreamCounts[n.channelID] { return true }
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
            if c1.type == MezonConstants.ChannelType.streaming.rawValue,
               prevStreamCounts[c1.channelID] != newStreamCounts[c2.channelID] { return true }
            return u1 != u2
        case let (.voiceMemberExpanded(c1, id1), .voiceMemberExpanded(c2, id2)):
            return c1.channelID != c2.channelID || id1 != id2
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
        if o.topic != n.topic { return true }
        if o.categoryID != n.categoryID { return true }
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
        if o.topic != n.topic { return true }
        if o.categoryID != n.categoryID { return true }
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
            safeReloadData(preserving: isPinnedNearListTop() ? nil : captureScrollAnchor(prev: prev))
            return
        }

        let sectionOffset = leadingTableSectionsCount

        var rowCountChanged = false
        for s in 0..<new.categories.count {
            let section = s + sectionOffset
            guard section < tableNode.numberOfSections else {
                safeReloadData(preserving: isPinnedNearListTop() ? nil : captureScrollAnchor(prev: prev))
                return
            }
            let committedRows = tableNode.numberOfRows(inSection: section)
            let newRows = rowsForSection(s).count + Self.categoryHeaderRowCount
            if committedRows != newRows {
                rowCountChanged = true
                break
            }
        }

        if rowCountChanged {
            applyBatchStructureUpdate(prev: prev, new: new)
            return
        }

        let prevThreadLookup = buildThreadLookup(prev.allChannels)
        var selectionPaths: [IndexPath] = []
        var reloadPaths: [IndexPath] = []
        for s in 0..<new.categories.count {
            let oldRows = computeRows(for: prev, categoryIndex: s, threadLookup: prevThreadLookup)
            let newRows = rowsForSection(s)
            if prev.categories[s].name != new.categories[s].name {
                reloadPaths.append(IndexPath(row: 0, section: s + sectionOffset))
            }

            for r in 0..<newRows.count {
                guard r < oldRows.count else {
                    reloadPaths.append(channelIndexPath(row: r, section: s + sectionOffset))
                    continue
                }
                let oldRow = oldRows[r]
                let newRow = newRows[r]
                if Self.rowDiffKey(oldRow) != Self.rowDiffKey(newRow) {
                    reloadPaths.append(channelIndexPath(row: r, section: s + sectionOffset))
                    continue
                }
                if channelListRowVisuallyChanged(
                    old: oldRow,
                    new: newRow,
                    prevSelected: prev.selectedChannelId,
                    newSelected: new.selectedChannelId,
                    prevVoice: prev.voiceUsersByChannel,
                    newVoice: new.voiceUsersByChannel,
                    prevStreamCounts: prev.streamViewerCounts,
                    newStreamCounts: new.streamViewerCounts,
                    prevBuzz: prev.buzzChannelIds,
                    newBuzz: new.buzzChannelIds
                ) {
                    let ip = channelIndexPath(row: r, section: s + sectionOffset)
                    if listRowChangeIsSelectionOnly(
                        old: oldRow,
                        new: newRow,
                        prevSelected: prev.selectedChannelId,
                        newSelected: new.selectedChannelId,
                        prevVoice: prev.voiceUsersByChannel,
                        newVoice: new.voiceUsersByChannel,
                        prevStreamCounts: prev.streamViewerCounts,
                        newStreamCounts: new.streamViewerCounts,
                        prevBuzz: prev.buzzChannelIds,
                        newBuzz: new.buzzChannelIds
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
        let sectionOffset = leadingTableSectionsCount
        guard let s = firstCategoryIndexContainingListChannel(channelId) else { return nil }
        let rows = rowsForSection(s)
        guard let r = rows.firstIndex(where: { row in
            switch row {
            case .voiceMembersCollapsed, .voiceMemberExpanded: return false
            default: return row.channelDesc.channelID == channelId
            }
        }) else { return nil }
        return channelIndexPath(row: r, section: s + sectionOffset)
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
        guard hasCurrentClanState else { return }
        guard let id = firstDisplayedChannelIdWithUnreadBadge() else { return }
        let generation = clanSwitchGeneration
        skipNextLoadingFinishedReveal = true
        scrollToChannel(channelId: id, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.clanSwitchGeneration == generation, self.hasCurrentClanState else { return }
            self.interaction.onClearCurrentChannelSelection?()
            self.interaction.onRefresh?()
        }
    }

    private func scrollToChannel(channelId: Int64, animated: Bool = true, onlyIfStillSelected: Bool = false) {
        let generation = clanSwitchGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.clanSwitchGeneration == generation, self.hasCurrentClanState else { return }
            let latestState = self.latestCoalescedChannelListState ?? self.state
            guard !onlyIfStillSelected || latestState.selectedChannelId == channelId else { return }
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
        configureTableNodeView(tableNode)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActiveForListSanitize),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        headerSpacer.backgroundColor = .clear
        headerSpacer.translatesAutoresizingMaskIntoConstraints = false
        let headerHConstraint = headerSpacer.heightAnchor.constraint(equalToConstant: currentHeaderH)
        headerHConstraint.priority = .defaultHigh
        headerHConstraint.isActive = true
        headerSpacerHeightConstraint = headerHConstraint

        let tableHeader = UIStackView(arrangedSubviews: [bannerView, headerSpacer])
        tableHeader.axis = .vertical
        tableHeader.spacing = 0
        tableNode.view.tableHeaderView = tableHeader
        bannerView.isHidden = true
        applyClanHeaderMetrics(hasBanner: false)

        headerUIView.applyTheme()
        headerUIView.onSearchTapped = interaction.onSearchTapped
        headerUIView.onEventTapped = interaction.onEventTapped
        headerUIView.onClanTitleTap = { [weak self] in
            self?.presentClanActionSheetIfNeeded()
        }
        headerUIView.frame = CGRect(
            x: 0, y: 0,
            width: max(view.bounds.width, UIScreen.main.bounds.width),
            height: currentHeaderH)
        view.addSubview(headerUIView)
        headerUIView.layer.zPosition = 100
        headerUIView.clipsToBounds = true
        headerUIView.layer.insertSublayer(headerGradientLayer, at: 0)
        applyHeaderBackground()

        newUnreadButton.layer.zPosition = 85
        newUnreadButton.addTarget(self, action: #selector(newUnreadButtonTapped), for: .touchUpInside)
        view.addSubview(newUnreadButton)
        refreshNewUnreadButton()
        #if DEBUG
        installGhostRowSimulationForTestOnly()
        #endif
    }

    private func configureTableNodeView(_ table: ASTableNode) {
        table.backgroundColor = .clear
        table.view.backgroundColor = .clear
        table.view.separatorStyle = .none
        table.view.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            table.view.sectionHeaderTopPadding = 0
        }
        table.view.contentInset.bottom = 80
        table.view.scrollIndicatorInsets.bottom = 80
        table.delegate = self
        table.dataSource = self
        committedSectionCount = totalSections

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.theme.textDisabled
        refreshControl.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        table.view.refreshControl = refreshControl
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        nodeIsVisible = true
        interaction.onBecameVisible?()
        sanitizeListPresentationArtifacts()
        drainPendingVisibleReconcile()
        reloadVoiceMemberRows()
        scheduleGhostRowChecks()
    }

    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIColor.theme.desktop.conversationGradient?.updateDirection(on: gradientLayer, in: isNodeLoaded ? view.window : nil)
        updateHeaderGradientLayout()
        CATransaction.commit()
        drainPendingVisibleReconcile()
    }

    @objc private func handleAppDidBecomeActiveForListSanitize() {
        sanitizeListPresentationArtifacts()
        scheduleGhostRowChecks()
    }

    @discardableResult
    private func normalizeListElementPresentation(_ view: UIView) -> Bool {
        var changed = false
        let viewLayer = view.layer
        if viewLayer.animationKeys()?.isEmpty == false {
            viewLayer.removeAllAnimations()
            changed = true
        }
        if viewLayer.speed != 1 || viewLayer.timeOffset != 0 {
            viewLayer.speed = 1
            viewLayer.timeOffset = 0
            changed = true
        }
        if view.alpha != 1 {
            view.alpha = 1
            changed = true
        }
        if viewLayer.opacity != 1 {
            viewLayer.opacity = 1
            changed = true
        }
        if view.transform != .identity {
            view.transform = .identity
            changed = true
        }
        if !CATransform3DIsIdentity(viewLayer.transform) {
            viewLayer.transform = CATransform3DIdentity
            changed = true
        }
        return changed
    }

    @discardableResult
    private func normalizeListElementTree(_ view: UIView) -> Bool {
        var changed = normalizeListElementPresentation(view)
        for sub in view.subviews {
            if normalizeListElementTree(sub) { changed = true }
        }
        return changed
    }

    @discardableResult
    func sanitizeListPresentationArtifacts(attempt: Int = 0) -> Bool {
        guard tableIsInWindow else {
            if attempt < 8 {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.nodeIsVisible else { return }
                    self.sanitizeListPresentationArtifacts(attempt: attempt + 1)
                }
            }
            return false
        }
        var changed = false
        let tableLayer = tableNode.view.layer
        if tableLayer.animationKeys()?.isEmpty == false {
            tableLayer.removeAllAnimations()
            changed = true
        }
        if tableLayer.speed != 1 || tableLayer.timeOffset != 0 {
            tableLayer.speed = 1
            tableLayer.timeOffset = 0
            changed = true
        }
        if tableLayer.opacity != 1 {
            tableLayer.opacity = 1
            changed = true
        }
        let visibleCells = Set(tableNode.view.visibleCells.map { ObjectIdentifier($0) })
        for sub in tableNode.view.subviews {
            if let cell = sub as? UITableViewCell {
                var surfaceChanged = normalizeListElementPresentation(cell)
                if normalizeListElementPresentation(cell.contentView) { surfaceChanged = true }
                normalizeListElementTree(cell)
                if surfaceChanged { changed = true }
                if cell.isHidden, visibleCells.contains(ObjectIdentifier(cell)) {
                    cell.isHidden = false
                    changed = true
                }
            }
        }
        if tableNode.numberOfSections != totalSections {
            changed = true
        }
        if changed {
            cachedRows = [:]
            safeReloadData()
        }
        return changed
    }

    private func drainPendingVisibleReconcile(attempt: Int = 0) {
        guard nodeIsVisible, pendingVisibleReconcile else { return }
        if !tableIsInWindow, attempt < 8 {
            DispatchQueue.main.async { [weak self] in
                self?.drainPendingVisibleReconcile(attempt: attempt + 1)
            }
            return
        }
        let shouldResetScroll = pendingVisibleReconcileShouldResetScroll
        pendingVisibleReconcile = false
        pendingVisibleReconcileShouldResetScroll = false
        cachedRows = [:]
        applyCrossfadeReload(resetScroll: shouldResetScroll)
    }

    override func didExitVisibleState() {
        super.didExitVisibleState()
        nodeIsVisible = false
        cancelGhostRowChecks()
    }

    private func scheduleReload() {
        cachedRows = [:]
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

    private func leadingSectionSurgeryIsSafe(committedLeadingSections: Int) -> Bool {
        guard !pendingVisibleReconcile else { return false }
        let trailingCount = channelListLoadingPlaceholderVisible ? 1 : state.categories.count
        guard tableNode.numberOfSections == committedLeadingSections + trailingCount else { return false }
        if channelListLoadingPlaceholderVisible {
            return tableNode.numberOfRows(inSection: committedLeadingSections) == 1
        }
        for i in 0..<trailingCount {
            if tableNode.numberOfRows(inSection: committedLeadingSections + i) != rowsForSection(i).count + Self.categoryHeaderRowCount {
                return false
            }
        }
        return true
    }

    private func reloadChannelAppsSectionOnly() {
        guard channelAppsStripeVisible else { return }
        guard tableNode.numberOfSections > 0 else { return }
        guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount) else {
            scheduleReload()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.performBatch(animated: false) {
                self.tableNode.reloadSections(IndexSet(integer: self.channelAppsTableSection), with: .none)
            }
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
    }

    private func updateTableHeaderLayout() {
        guard tableNode.bounds.width > 0 else { return }
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
        section - leadingTableSectionsCount
    }

    private var channelListLoadingPlaceholderVisible: Bool {
        channelListLoadingPlaceholderVisible(for: state)
    }

    private var loadingPlaceholderTableSection: Int {
        leadingTableSectionsCount
    }

    private func isLoadingPlaceholderTableSection(_ section: Int) -> Bool {
        channelListLoadingPlaceholderVisible && section == loadingPlaceholderTableSection
    }

    private var totalSections: Int {
        let leadingSections = leadingTableSectionsCount
        if channelListLoadingPlaceholderVisible {
            return leadingSections + 1
        }
        let catSections = state.categories.count
        return leadingSections + catSections
    }

    var hasDisplayedChannelApps: Bool { !channelApps.isEmpty }

    func setChannelAppsLoadingIndicator(_ loading: Bool) {
        guard channelAppsLoading != loading else { return }
        let beforeHad = channelAppsStripeVisible
        channelAppsLoading = loading
        let afterHad = channelAppsStripeVisible
        cachedRows = [:]
        guard !shouldDeferLeadingSectionTableMutations else {
            if beforeHad != afterHad {
                scheduleReload()
            }
            return
        }
        if !beforeHad && afterHad {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount - 1) else {
                scheduleReload()
                return
            }
            let section = self.channelAppsTableSection
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.insertSections(IndexSet(integer: section), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && !afterHad {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount + 1) else {
                scheduleReload()
                return
            }
            let section = channelAppsTableSection
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.deleteSections(IndexSet(integer: section), with: .none)
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
        UIColor.theme.desktop.conversationGradient?.updateDirection(on: gradientLayer, in: isNodeLoaded ? view.window : nil)
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
        guard tableNode.bounds.width > 0 else { return }
        recomputeClanHeaderHeight()
        let bannerHeight = hasClanBanner ? Self.bannerKnownHeight : 0
        let contentOffsetY = tableNode.view.contentOffset.y
        let headerY = max(0, bannerHeight - contentOffsetY)
        headerUIView.frame = CGRect(x: 0, y: stickyTopOffset + headerY, width: tableNode.bounds.width, height: currentHeaderH)
        updateHeaderGradientLayout()
    }

    private func applyHeaderBackground() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headerUIView.backgroundColor = UIColor.theme.secondary
        headerGradientLayer.isHidden = gradientLayer.isHidden
        headerGradientLayer.colors = gradientLayer.colors
        headerGradientLayer.locations = gradientLayer.locations
        updateHeaderGradientLayout()
        CATransaction.commit()
    }

    private func updateHeaderGradientLayout() {
        guard isNodeLoaded, !headerGradientLayer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headerGradientLayer.frame = headerUIView.layer.convert(gradientLayer.bounds, from: gradientLayer)
        headerGradientLayer.startPoint = gradientLayer.startPoint
        headerGradientLayer.endPoint = gradientLayer.endPoint
        CATransaction.commit()
    }

    func markClanSwitching() {
        isClanSwitching = true
        deferOnboardingTableUpdates = true
        clanSwitchTableRefreshDone = false
        resolvedVoiceMemberSnapshot = [:]
        memberCount = 0
        onboardingState = .hidden
        memberOnboardingState = .hidden
        headerUIView.clearMemberSubtitleStaleText()
    }

    func clearChannelApps() {
        let hadStripe = channelAppsStripeVisible
        channelApps = []
        channelAppsLoading = false
        cachedRows = [:]
        guard hadStripe else {
            committedSectionCount = totalSections
            return
        }
        guard !shouldDeferLeadingSectionTableMutations else {
            committedSectionCount = totalSections
            scheduleReload()
            return
        }
        guard tableNode.numberOfSections > 0 else {
            committedSectionCount = totalSections
            return
        }
        guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount + 1) else {
            scheduleReload()
            return
        }
        let section = channelAppsTableSection
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.deleteSections(IndexSet(integer: section), with: .none)
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
        committedSectionCount = totalSections
    }

    func updateOnboardingState(_ state: ClanOnboardingViewState) {
        guard state != onboardingState else { return }
        let beforeVisible = onboardingBannerVisible
        onboardingState = state
        if state.isVisible, memberOnboardingState.isVisible {
            memberOnboardingState = .hidden
        }
        let afterVisible = onboardingBannerVisible

        guard !deferOnboardingTableUpdates, tableIsInWindow else {
            if beforeVisible != afterVisible {
                scheduleReload()
            }
            return
        }

        cachedRows = [:]

        if !beforeVisible && afterVisible {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount - 1) else {
                scheduleReload()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.insertSections(IndexSet(integer: self.onboardingTableSection), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
        } else if beforeVisible && !afterVisible {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount + 1) else {
                scheduleReload()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.deleteSections(IndexSet(integer: self.onboardingTableSection), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
        } else if beforeVisible && afterVisible {
            let section = onboardingTableSection
            if section < tableNode.numberOfSections, tableNode.numberOfRows(inSection: section) > 0,
               leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    self.tableNode.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
                    self.tableNode.waitUntilAllUpdatesAreProcessed()
                }
                CATransaction.commit()
            } else {
                scheduleReload()
            }
        }
        committedSectionCount = totalSections
    }

    func updateMemberOnboardingState(_ state: MemberOnboardingViewState) {
        guard onboardingState.isVisible == false else {
            if memberOnboardingState.isVisible {
                memberOnboardingState = .hidden
            }
            return
        }
        guard state != memberOnboardingState else { return }
        let beforeVisible = onboardingBannerVisible
        memberOnboardingState = state
        let afterVisible = onboardingBannerVisible

        guard !deferOnboardingTableUpdates, tableIsInWindow else {
            if beforeVisible != afterVisible {
                scheduleReload()
            }
            return
        }

        cachedRows = [:]

        if !beforeVisible && afterVisible {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount - 1) else {
                scheduleReload()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.insertSections(IndexSet(integer: self.onboardingTableSection), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
        } else if beforeVisible && !afterVisible {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount + 1) else {
                scheduleReload()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.deleteSections(IndexSet(integer: self.onboardingTableSection), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
        } else if beforeVisible && afterVisible {
            let section = onboardingTableSection
            if section < tableNode.numberOfSections, tableNode.numberOfRows(inSection: section) > 0,
               leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    self.tableNode.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
                    self.tableNode.waitUntilAllUpdatesAreProcessed()
                }
                CATransaction.commit()
            } else {
                scheduleReload()
            }
        }
        committedSectionCount = totalSections
    }

    func configure(clanName: String, clanId: Int64 = 0, logoURL: String? = nil, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        let clanChanged = updateClanIdentity(clanId)
        self.clanLogoURL = logoURL ?? ""
        self.isCommunity = isCommunity
        self.memberCount = memberCount
        headerUIView.configure(title: clanName, memberCount: memberCount, isCommunity: isCommunity)
        if clanChanged {
            isChannelAppsExpanded = true
        }

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
            if tableNode.bounds.width > 0, let header = tableNode.view.tableHeaderView {
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
        if clanChanged && !isClanSwitching {
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
        let clanScoped = apps.filter { app in
            guard headerClanId != 0 else { return true }
            return app.clanID == 0 || app.clanID == headerClanId
        }
        let filtered = Self.normalizeChannelAppsList(clanScoped.filter { $0.hasListableChannelAppContent })
        let beforeHadStripe = channelAppsStripeVisible
        channelAppsLoading = false
        if channelAppsUIEqual(channelApps, filtered), beforeHadStripe == (!filtered.isEmpty) {
            reconcileChannelAppsTableIfNeeded()
            return
        }

        let beforeHad = beforeHadStripe
        channelApps = filtered
        applyChannelAppsTableMutation(beforeHad: beforeHad)
    }

    private func applyChannelAppsTableMutation(beforeHad: Bool) {
        let afterHad = channelAppsStripeVisible
        cachedRows = [:]

        if shouldDeferLeadingSectionTableMutations {
            if beforeHad != afterHad {
                scheduleReload()
            } else {
                pendingChannelAppsTableSync = true
            }
            return
        }
        pendingChannelAppsTableSync = false

        if !beforeHad && afterHad {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount - 1) else {
                scheduleReload()
                return
            }
            let section = self.channelAppsTableSection
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.insertSections(IndexSet(integer: section), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && !afterHad {
            guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount + 1) else {
                scheduleReload()
                return
            }
            let section = channelAppsTableSection
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    self.tableNode.deleteSections(IndexSet(integer: section), with: .none)
                }
                self.tableNode.waitUntilAllUpdatesAreProcessed()
            }
            CATransaction.commit()
            committedSectionCount = totalSections
        } else if beforeHad && afterHad {
            reloadChannelAppsSectionOnly()
        }
    }

    private func reconcileChannelAppsTableIfNeeded() {
        guard pendingChannelAppsTableSync || channelAppsStripeVisible != tableShowsChannelAppsStripe else { return }
        pendingChannelAppsTableSync = false
        let beforeHad = tableShowsChannelAppsStripe
        applyChannelAppsTableMutation(beforeHad: beforeHad)
    }

    private var tableShowsChannelAppsStripe: Bool {
        guard channelAppsStripeVisible else { return false }
        guard tableNode.numberOfSections > channelAppsTableSection else { return false }
        return isChannelAppsTableSection(channelAppsTableSection)
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
            initialShowEmptyCategories: interaction.isShowEmptyCategoriesEnabled?() ?? false,
            canCreateCategory: interaction.canCreateCategory?() ?? false,
            isClanOwner: interaction.isClanOwner?() ?? false,
            onAction: { [weak self] action in
                guard let self else { return }
                switch action {
                case .settings, .editClanProfile:
                    self.interaction.onPresentSettings?()
                case .notifications:
                    self.interaction.onPresentClanNotifications?()
                case .invite:
                    self.interaction.onInviteClan?()
                case .createCategory:
                    self.interaction.onCreateCategory?()
                case .createEvent:
                    self.interaction.onCreateEvent?()
                case .leaveClan:
                    self.interaction.onLeaveClan?()
                case .deleteClan:
                    self.interaction.onDeleteClan?()
                case .markAsRead:
                    self.interaction.onMarkClanAsRead?()
                default:
                    break
                }
            },
            onToggleShowEmptyCategories: { [weak self] value in
                self?.interaction.onToggleShowEmptyCategories?(value)
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
        return 1
    }

    private var channelAppsHeaderRowCount: Int { isCompactView ? 1 : 0 }

    private func toggleChannelAppsExpand() {
        guard channelAppsStripeVisible else { return }
        let oldCount = channelAppsSectionRowCount()
        isChannelAppsExpanded.toggle()
        let newCount = channelAppsSectionRowCount()
        guard oldCount != newCount else { return }
        guard tableNode.numberOfSections > 0,
            tableNode.numberOfRows(inSection: channelAppsTableSection) == oldCount + channelAppsHeaderRowCount,
            leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount)
        else {
            scheduleReload()
            return
        }
        let appsSection = channelAppsTableSection
        let contentRowOffset = channelAppsHeaderRowCount
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.performBatch(animated: false) {
                if contentRowOffset > 0 {
                    self.tableNode.reloadRows(at: [IndexPath(row: 0, section: appsSection)], with: .none)
                }
                if newCount == 0 && oldCount > 0 {
                    let paths = (0..<oldCount).map { IndexPath(row: $0 + contentRowOffset, section: appsSection) }
                        .sorted { $0.row > $1.row }
                    self.tableNode.deleteRows(at: paths, with: .none)
                } else if oldCount == 0 && newCount > 0 {
                    let paths = (0..<newCount).map { IndexPath(row: $0 + contentRowOffset, section: appsSection) }
                    self.tableNode.insertRows(at: paths, with: .none)
                } else {
                    let del = (0..<oldCount).map { IndexPath(row: $0 + contentRowOffset, section: appsSection) }
                        .sorted { $0.row > $1.row }
                    let ins = (0..<newCount).map { IndexPath(row: $0 + contentRowOffset, section: appsSection) }
                    self.tableNode.deleteRows(at: del, with: .none)
                    self.tableNode.insertRows(at: ins, with: .none)
                }
            }
            self.tableNode.waitUntilAllUpdatesAreProcessed()
        }
        CATransaction.commit()
    }

    func applyTheme() {
        let t = UIColor.theme
        let gradient = t.desktop.conversationGradient
        headerUIView.applyTheme()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.isHidden = gradient == nil
        gradient?.apply(to: gradientLayer, in: isNodeLoaded ? view.window : nil)
        applyHeaderBackground()
        CATransaction.commit()
        let listBackground = gradient == nil ? t.secondary : UIColor.clear
        backgroundColor = listBackground
        tableNode.backgroundColor = listBackground
        tableNode.view.backgroundColor = listBackground
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
        threadLookup lookup: [Int64: [Mezon_Api_ChannelDescription]],
        selectedChannelId: Int64?,
        voiceUsersByChannel: [Int64: [String]],
        buzzChannelIds: Set<Int64>
    ) -> [ChannelListRow] {
        let baseRows = flattenCategoryToRows(category, threadLookup: lookup)
        let isExpanded = !category.isCollapsed

        var allRows: [ChannelListRow] = []
        for row in baseRows {
            allRows.append(row)
            if case .channel(let ch, _) = row,
               Self.voiceChannelTypes.contains(ch.type) {
                let userIds = voiceUsersByChannel[ch.channelID] ?? []
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
            if buzzChannelIds.contains(ch.channelID) { return true }
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
                    || buzzChannelIds.contains($0.channelID)
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

    private func computeRows(
        for state: ChannelListState,
        categoryIndex: Int,
        threadLookup lookup: [Int64: [Mezon_Api_ChannelDescription]]
    ) -> [ChannelListRow] {
        guard categoryIndex >= 0, categoryIndex < state.categories.count else { return [] }
        return computeRows(
            for: state.categories[categoryIndex],
            threadLookup: lookup,
            selectedChannelId: state.selectedChannelId,
            voiceUsersByChannel: state.voiceUsersByChannel,
            buzzChannelIds: state.buzzChannelIds
        )
    }

    private func rowsForSection(_ section: Int) -> [ChannelListRow] {
        if let cached = cachedRows[section] { return cached }
        let rows = computeRows(for: state, categoryIndex: section, threadLookup: threadLookup)
        cachedRows[section] = rows
        return rows
    }

    private static func isVoiceMemberRow(_ row: ChannelListRow) -> Bool {
        switch row {
        case .voiceMembersCollapsed, .voiceMemberExpanded:
            return true
        default:
            return false
        }
    }

    private var voiceMemberReloadScheduled = false
    private var resolvedVoiceMemberSnapshot: [String: [VoiceMemberDisplay]] = [:]

    private func voiceMemberSnapshotKey(for row: ChannelListRow, categoryIndex: Int) -> String {
        "\(state.categories[categoryIndex].id):\(Self.rowDiffKey(row))"
    }

    private func resolvedVoiceMember(_ uid: String, in channel: Mezon_Api_ChannelDescription) -> VoiceMemberDisplay? {
        guard var member = voiceMemberResolver?(uid) else { return nil }
        if channel.type == MezonConstants.ChannelType.streaming.rawValue {
            member.isSharingScreen = false
        }
        return member
    }

    private func resolvedVoiceDisplays(for row: ChannelListRow) -> [VoiceMemberDisplay] {
        guard let resolver = voiceMemberResolver else { return [] }
        switch row {
        case .voiceMemberExpanded(let ch, let uid):
            return [resolvedVoiceMember(uid, in: ch)].compactMap { $0 }
        case .voiceMembersCollapsed(_, let uids):
            return uids.prefix(5).compactMap { resolver($0) }
        default:
            return []
        }
    }

    func reloadVoiceMemberRows() {
        guard !voiceMemberReloadScheduled else { return }
        voiceMemberReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.voiceMemberReloadScheduled = false
            self.performVoiceMemberRowsReload()
        }
    }

    private func streamViewerCount(for channel: Mezon_Api_ChannelDescription) -> Int? {
        guard channel.type == MezonConstants.ChannelType.streaming.rawValue else { return nil }
        let members = state.voiceUsersByChannel[channel.channelID] ?? []
        return members.isEmpty ? nil : state.streamViewerCounts[channel.channelID] ?? max(0, members.count - 1)
    }

    private func performVoiceMemberRowsReload() {
        guard tableIsInWindow, !pendingVisibleReconcile else { return }
        guard leadingSectionSurgeryIsSafe(committedLeadingSections: leadingTableSectionsCount) else {
            scheduleReload()
            return
        }
        let leading = leadingTableSectionsCount
        var paths: [IndexPath] = []
        for section in leading..<totalSections {
            guard !isLoadingPlaceholderTableSection(section) else { continue }
            let catIdx = categoryIndex(forSection: section)
            let rows = rowsForSection(catIdx)
            for (r, row) in rows.enumerated() where Self.isVoiceMemberRow(row) {
                let key = voiceMemberSnapshotKey(for: row, categoryIndex: catIdx)
                let displays = resolvedVoiceDisplays(for: row)
                if resolvedVoiceMemberSnapshot[key] == displays { continue }
                resolvedVoiceMemberSnapshot[key] = displays
                let path = channelIndexPath(row: r, section: section)
                if let node = tableNode.nodeForRow(at: path) as? VoiceMemberExpandedCellNode,
                   let member = displays.first {
                    node.update(member: member)
                } else {
                    paths.append(path)
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
}

extension ChannelListContainerNode: ASTableDataSource {

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        totalSections
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if isOnboardingTableSection(section) {
            return 1
        }
        if isChannelAppsTableSection(section) {
            return channelAppsHeaderRowCount + channelAppsSectionRowCount()
        }
        if isLoadingPlaceholderTableSection(section) {
            return 1
        }
        let catIdx = categoryIndex(forSection: section)
        return rowsForSection(catIdx).count + Self.categoryHeaderRowCount
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let generation = clanSwitchGeneration
        if isOnboardingTableSection(indexPath.section) {
            let title: String
            let subtitle: String
            if showsCreatorOnboardingBanner {
                title = L(L10n.OnboardingClan.title)
                subtitle = L(
                    L10n.OnboardingClan.description,
                    onboardingState.currentDisplayStep,
                    ClanOnboardingViewState.totalSteps
                )
            } else {
                title = L(L10n.OnboardingMember.title)
                subtitle = L(
                    L10n.OnboardingMember.description,
                    memberOnboardingState.currentDisplayStep,
                    max(memberOnboardingState.missions.count, 1)
                )
            }
            return { [weak self] in
                let node = ChannelOnboardingBannerCellNode(title: title, subtitle: subtitle)
                node.onTap = { [weak self] in
                    self?.interaction.onOnboardingBannerTapped?()
                }
                return node
            }
        }
        if isChannelAppsTableSection(indexPath.section) {
            if isCompactView, indexPath.row == 0 {
                let isCollapsed = !isChannelAppsExpanded
                return { CategoryHeaderCellNode(title: "CHANNEL APPS", isCollapsed: isCollapsed) }
            }
            if channelAppsLoading && channelApps.isEmpty {
                return { ChannelAppSkeletonCellNode() }
            }
            if isCompactView {
                let appIndex = indexPath.row - channelAppsHeaderRowCount
                guard channelApps.indices.contains(appIndex) else { return { ASCellNode() } }
                let app = channelApps[appIndex]
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
        guard state.categories.indices.contains(catIdx) else { return { ASCellNode() } }
        if indexPath.row == 0 {
            let category = state.categories[catIdx]
            return { [weak self] in
                let node = CategoryHeaderCellNode(title: category.name, isCollapsed: category.isCollapsed)
                node.onLongPress = { [weak self] in
                    guard let self, self.clanSwitchGeneration == generation, self.hasCurrentClanState,
                          let current = self.state.categories.first(where: { $0.id == category.id }) else { return }
                    self.interaction.onLongPressCategory?(current)
                }
                return node
            }
        }

        let rows = rowsForSection(catIdx)
        let rowIndex = channelRowIndex(for: indexPath)
        guard rows.indices.contains(rowIndex) else { return { ASCellNode() } }
        let row = rows[rowIndex]
        let isSelected = row.channelDesc.channelID == state.selectedChannelId
        let hasBuzz = state.buzzChannelIds.contains(row.channelDesc.channelID)
        switch row {
        case .channel(let ch, let inFav):
            let hasVoiceMembers = Self.voiceChannelTypes.contains(ch.type)
                && !(state.voiceUsersByChannel[ch.channelID] ?? []).isEmpty
            let viewerCount = streamViewerCount(for: ch)
            return {
                let node = ChannelItemCellNode(channel: ch, isSelected: isSelected, isVoiceActive: hasVoiceMembers, hasBuzz: hasBuzz, viewerCount: viewerCount)
                node.onLongPress = { [weak self] in
                    guard let self, self.clanSwitchGeneration == generation, self.hasCurrentClanState,
                          let current = self.state.allChannels.first(where: { $0.channelID == ch.channelID }) else { return }
                    self.interaction.onLongPressChannel(current)
                }
                return node
            }
        case .thread(let ch, let isLast, let inFav):
            return {
                let node = ThreadItemCellNode(channel: ch, isSelected: isSelected, isLast: isLast, hasBuzz: hasBuzz)
                node.onLongPress = { [weak self] in
                    guard let self, self.clanSwitchGeneration == generation, self.hasCurrentClanState,
                          let current = self.state.allChannels.first(where: { $0.channelID == ch.channelID }) else { return }
                    self.interaction.onLongPressChannel(current)
                }
                return node
            }
        case .voiceMembersCollapsed(let ch, let userIds):
            let totalCount = ch.type == MezonConstants.ChannelType.streaming.rawValue && !userIds.isEmpty
                ? (state.streamViewerCounts[ch.channelID] ?? max(0, userIds.count - 1)) + 1
                : userIds.count
            let visible = Array(userIds.prefix(5))
            let resolver = voiceMemberResolver
            let members: [VoiceMemberDisplay] = visible.compactMap { resolver?($0) }
            resolvedVoiceMemberSnapshot[voiceMemberSnapshotKey(for: row, categoryIndex: catIdx)] = members
            return {
                VoiceChannelMembersCollapsedCellNode(members: members, totalCount: totalCount)
            }
        case .voiceMemberExpanded(let ch, let userId):
            guard let member = resolvedVoiceMember(userId, in: ch) else {
                return { ASCellNode() }
            }
            resolvedVoiceMemberSnapshot[voiceMemberSnapshotKey(for: row, categoryIndex: catIdx)] = [member]
            return {
                VoiceMemberExpandedCellNode(member: member)
            }
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        0
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }
}

extension ChannelListContainerNode: ASTableDelegate {

    func tableNode(_ tableNode: ASTableNode, willDisplayRowWith node: ASCellNode) {
        scheduleGhostRowChecks()
        guard node.isNodeLoaded else { return }
        var current: UIView? = node.view
        while let v = current, !(v is UITableViewCell) {
            current = v.superview
        }
        if let cell = current as? UITableViewCell {
            normalizeListElementTree(cell)
        } else {
            normalizeListElementTree(node.view)
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: false)
        guard hasCurrentClanState else { return }
        if isOnboardingTableSection(indexPath.section) {
            interaction.onOnboardingBannerTapped?()
            return
        }
        if isChannelAppsTableSection(indexPath.section) {
            if isCompactView, indexPath.row == 0 {
                toggleChannelAppsExpand()
                return
            }
            guard !channelAppsLoading else { return }
            let appIndex = indexPath.row - channelAppsHeaderRowCount
            if isCompactView, channelApps.indices.contains(appIndex) {
                interaction.onSelectChannelApp?(channelApps[appIndex])
            }
            return
        }
        if isLoadingPlaceholderTableSection(indexPath.section) {
            return
        }
        let catIdx = categoryIndex(forSection: indexPath.section)
        guard state.categories.indices.contains(catIdx) else { return }
        if indexPath.row == 0 {
            interaction.onToggleCollapse(state.categories[catIdx].id)
            return
        }
        let rows = rowsForSection(catIdx)
        let rowIndex = channelRowIndex(for: indexPath)
        guard rows.indices.contains(rowIndex) else { return }
        let row = rows[rowIndex]
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
        let highlight = UIColor.theme.shimmerHighlight(over: base)
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


private final class CategoryHeaderCellNode: ASCellNode {

    var onLongPress: (() -> Void)?

    private let arrowNode = ASImageNode()
    private let titleNode = ASTextNode2()

    init(title: String, isCollapsed: Bool) {
        super.init()
        automaticallyManagesSubnodes = true
        neverShowPlaceholders = true
        selectionStyle = .none
        clipsToBounds = true
        backgroundColor = .clear
        style.height = ASDimensionMake(32.sh)
        let t = UIColor.theme
        let iconName = isCollapsed ? "Channel/ChevronRight" : "Channel/ChevronBottom"
        arrowNode.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        arrowNode.tintColor = t.textDisabled
        arrowNode.contentMode = .scaleAspectFit
        arrowNode.style.preferredSize = CGSize(width: 18.sw, height: 18.sw)
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.style.flexShrink = 1
        titleNode.attributedText = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .bold),
                .foregroundColor: t.textDisabled,
            ])
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:))))
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: 2.sw, justifyContent: .start, alignItems: .center,
            children: [arrowNode, titleNode])
        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 8.sw, bottom: 0, right: 16.sw), child: row)
        return ASCenterLayoutSpec(centeringOptions: .Y, sizingOptions: .minimumY, child: inset)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onLongPress?()
        }
    }
}

final class ChannelListHeaderView: UIView {

    var onTap: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onQRTapped: (() -> Void)?
    var onEventTapped: (() -> Void)?
    var onClanTitleTap: (() -> Void)?

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
        btn.setImage(UIImage(named: "Profile/ScanQR")?.withRenderingMode(.alwaysTemplate), for: .normal)
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
    private let mainStackTopBase: CGFloat = 12
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
        eventButton.addTarget(self, action: #selector(eventTapped), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [searchBar, qrButton, eventButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.alignment = .center
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let clanTitleBlock = UIStackView(arrangedSubviews: [titleStack, infoRow])
        clanTitleBlock.axis = .vertical
        clanTitleBlock.spacing = 0
        clanTitleBlock.setCustomSpacing(0, after: titleStack)
        clanTitleBlock.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = UIStackView(arrangedSubviews: [clanTitleBlock, actionRow])
        mainStack.axis = .vertical
        mainStack.spacing = 4
        mainStack.setCustomSpacing(10, after: clanTitleBlock)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let mainTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleHeaderTap))
        mainStack.addGestureRecognizer(mainTapGesture)
        let clanTitleTap = UITapGestureRecognizer(target: self, action: #selector(handleClanTitleTap))
        clanTitleTap.cancelsTouchesInView = false
        clanTitleBlock.addGestureRecognizer(clanTitleTap)
        mainStack.isUserInteractionEnabled = true
        clanTitleBlock.isUserInteractionEnabled = true

        addSubview(mainStack)
        addSubview(separator)

        mainStackTopConstraint = mainStack.topAnchor.constraint(
            equalTo: topAnchor, constant: mainStackTopBase)
        mainStackTopConstraint.isActive = true

        let mainStackTrailing = mainStack.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -12)
        let mainStackBottom = mainStack.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: -16)
        mainStackTrailing.priority = UILayoutPriority(999)
        mainStackBottom.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStackTrailing,
            mainStackBottom,

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

    @objc private func eventTapped() {
        onEventTapped?()
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
        qrButton.setImage(UIImage(named: "Profile/ScanQR")?.withRenderingMode(.alwaysTemplate), for: .normal)
        if ThemeManager.shared.current.effectiveInterfaceStyle == .light {
            qrButton.tintColor = UIColor(hexString: "#ff6b6f76")
        } else {
            qrButton.tintColor = UIColor(hexString: "#fefefe")
        }
        
        qrButton.backgroundColor = t.raisedSurface
        qrButton.layer.borderColor = t.border.withAlphaComponent(0.4).cgColor
        eventButton.backgroundColor = t.raisedSurface
        eventButton.layer.borderColor = t.border.withAlphaComponent(0.4).cgColor
        separator.backgroundColor = t.borderDim
    }

    @objc private func handleHeaderTap() {
        onTap?()
    }

    @objc private func handleClanTitleTap() {
        onClanTitleTap?()
    }
}

#if DEBUG
extension ChannelListContainerNode {

    private static var ghostRowSimulationCount = 0

    fileprivate func installGhostRowSimulationForTestOnly() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(simulateGhostRowsForTestOnly(_:)))
        press.numberOfTouchesRequired = 3
        press.minimumPressDuration = 0.8
        view.addGestureRecognizer(press)
    }

    @objc fileprivate func simulateGhostRowsForTestOnly(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        Self.ghostRowSimulationCount += 1
        let useMask = Self.ghostRowSimulationCount % 2 == 1
        for (index, cell) in tableNode.view.visibleCells.enumerated() where index % 2 == 0 {
            if useMask {
                let mask = CALayer()
                mask.frame = cell.layer.bounds
                mask.backgroundColor = UIColor.white.cgColor
                mask.opacity = 0.1
                cell.layer.mask = mask
            } else {
                cell.contentView.subviews.first?.layer.opacity = 0.1
            }
        }
    }
}
#endif
