import UIKit
import AsyncDisplayKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
    let onRefresh: (() -> Void)?
    let onSearchTapped: (() -> Void)?
}

final class ChannelListContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    private let headerUIView = ChannelListHeaderView()
    private let bannerView = ChannelBannerView()
    private let headerSpacer = UIView()
    private var stickyTopOffset: CGFloat = 0
    private let headerH: CGFloat = 100.sh
    private var channelApps: [Mezon_Api_ChannelAppResponse] = []
    private var isChannelAppsExpanded = true
    private var hasChannelAppsSection: Bool { !channelApps.isEmpty }
    private let compactViewThreshold = 3
    private var isCompactView: Bool { channelApps.count <= compactViewThreshold }
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0, y: 0)
        gl.endPoint   = CGPoint(x: 1, y: 1)
        gl.locations  = [0.2, 0.4, 0.7, 0.9] as [NSNumber]
        return gl
    }()

    private var state: ChannelListState = .empty
    private var threadLookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    /// Cached rows per category index — rebuilt only when state changes.
    private var cachedRows: [Int: [ChannelListRow]] = [:]
    /// Cached section header views — keyed by section index, avoids re-allocation on scroll.
    private var cachedHeaders: [Int: CategorySectionHeaderView] = [:]
    /// Snapshot of section count at last table update — used for safe batch updates.
    private var committedSectionCount: Int = 0
    private let interaction: ChannelListInteraction
    private let disposables = DisposableSet()
    private var isClanSwitching = false

    init(signal: Signal<ChannelListState, NoError>, interaction: ChannelListInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        super.init()
        backgroundColor = UIColor.theme.secondary

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prevState = self.state

                if let msg = newState.errorMessage, msg != prevState.errorMessage {
                    Toast.error(msg)
                }

                let wasClanSwitching = self.isClanSwitching
                self.isClanSwitching = false
                self.state = newState
                self.threadLookup = buildThreadLookup(newState.allChannels)
                self.cachedRows = [:]
                self.cachedHeaders = [:]

                let prevCats = prevState.categories
                let newCats = newState.categories
                let structureChanged = prevCats.count != newCats.count
                    || zip(prevCats, newCats).contains(where: {
                        $0.id != $1.id || $0.isCollapsed != $1.isCollapsed || $0.channels.count != $1.channels.count
                    })

                if wasClanSwitching {
                    self.applyCrossfadeReload()
                } else if structureChanged {
                    self.applyBatchStructureUpdate(prev: prevState, new: newState)
                } else if !newCats.isEmpty {
                    self.applyRowDiff(prev: prevState, new: newState)
                }
            })
        )
    }

    // MARK: – Table update strategies

    /// Safe full reload that keeps committedSectionCount in sync.
    private func safeReloadData() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadData()
        }
        CATransaction.commit()
        committedSectionCount = totalSections
    }

    private func applyCrossfadeReload() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tableNode.reloadData()
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
        // If the category IDs match 1:1 we can do granular row-level diffs.
        let canPatch = prevCatSections == newCatSections
            && prevCatSections == prev.categories.count
            && newCatSections == new.categories.count
            && zip(prev.categories, new.categories).allSatisfy({ $0.id == $1.id })

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if canPatch {
            let prevThreadLookup = buildThreadLookup(prev.allChannels)
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

                let oldRows = flattenCategoryToRows(pc, threadLookup: prevThreadLookup)
                let newRows = rowsForSection(i)

                let oldIds = oldRows.map { $0.channelDesc.channelID }
                let newIds = newRows.map { $0.channelDesc.channelID }

                if oldIds == newIds {
                    for (r, row) in newRows.enumerated() {
                        if channelRowDataChanged(old: oldRows[r], new: row,
                                                 prevSelected: prev.selectedChannelId,
                                                 newSelected: new.selectedChannelId) {
                            rowsToReload.append(IndexPath(row: r, section: section))
                        }
                    }
                    continue
                }

                let oldSet = Set(oldIds)
                let newSet = Set(newIds)

                let commonOld = oldIds.filter { newSet.contains($0) }
                let commonNew = newIds.filter { oldSet.contains($0) }
                if commonOld != commonNew {
                    sectionsToReload.insert(section)
                    continue
                }

                for (r, id) in oldIds.enumerated() where !newSet.contains(id) {
                    rowsToDelete.append(IndexPath(row: r, section: section))
                }
                for (r, id) in newIds.enumerated() where !oldSet.contains(id) {
                    rowsToInsert.append(IndexPath(row: r, section: section))
                }

                var newRowLookup: [Int64: ChannelListRow] = [:]
                for row in newRows { newRowLookup[row.channelDesc.channelID] = row }
                for (r, oldRow) in oldRows.enumerated() {
                    let chId = oldRow.channelDesc.channelID
                    guard let newRow = newRowLookup[chId] else { continue }
                    if channelRowDataChanged(old: oldRow, new: newRow,
                                             prevSelected: prev.selectedChannelId,
                                             newSelected: new.selectedChannelId) {
                        rowsToReload.append(IndexPath(row: r, section: section))
                    }
                }
            }

            let hasChanges = !sectionsToReload.isEmpty || !rowsToInsert.isEmpty
                || !rowsToDelete.isEmpty || !rowsToReload.isEmpty
            if hasChanges {
                UIView.performWithoutAnimation {
                    self.tableNode.performBatch(animated: false) {
                        if !sectionsToReload.isEmpty {
                            self.tableNode.reloadSections(sectionsToReload, with: .none)
                        }
                        if !rowsToDelete.isEmpty {
                            self.tableNode.deleteRows(at: rowsToDelete, with: .none)
                        }
                        if !rowsToInsert.isEmpty {
                            self.tableNode.insertRows(at: rowsToInsert, with: .none)
                        }
                        if !rowsToReload.isEmpty {
                            self.tableNode.reloadRows(at: rowsToReload, with: .none)
                        }
                    }
                }
            }
            committedSectionCount = expectedAfter
        } else if prevCatSections >= 0 && newCatSections >= 0 {
            let oldRange = IndexSet(integersIn: sectionOffset..<(sectionOffset + prevCatSections))
            let newRange = IndexSet(integersIn: sectionOffset..<(sectionOffset + newCatSections))
            guard !oldRange.isEmpty || !newRange.isEmpty else {
                safeReloadData()
                CATransaction.commit()
                return
            }
            UIView.performWithoutAnimation {
                self.tableNode.performBatch(animated: false) {
                    if !oldRange.isEmpty { self.tableNode.deleteSections(oldRange, with: .none) }
                    if !newRange.isEmpty { self.tableNode.insertSections(newRange, with: .none) }
                }
            }
            committedSectionCount = expectedAfter
        } else {
            safeReloadData()
        }

        CATransaction.commit()
    }

    private func channelRowDataChanged(old: ChannelListRow, new: ChannelListRow,
                                       prevSelected: Int64?, newSelected: Int64?) -> Bool {
        let o = old.channelDesc
        let n = new.channelDesc
        let chId = n.channelID
        return o.countMessUnread != n.countMessUnread
            || o.hasLastSentMessage != n.hasLastSentMessage
            || o.lastSentMessage.timestampSeconds != n.lastSentMessage.timestampSeconds
            || o.lastSeenMessage.timestampSeconds != n.lastSeenMessage.timestampSeconds
            || (chId == prevSelected) != (chId == newSelected)
    }

    private func applyRowDiff(prev: ChannelListState, new: ChannelListState) {
        var paths: [IndexPath] = []
        let sectionOffset = hasChannelAppsSection ? 1 : 0

        for s in 0..<new.categories.count {
            let oldCh = prev.categories[s].channels
            let newCh = new.categories[s].channels
            let rows = rowsForSection(s)

            var oldLookup: [Int64: Mezon_Api_ChannelDescription] = [:]
            for ch in oldCh { oldLookup[ch.channelID] = ch }
            var newLookup: [Int64: Mezon_Api_ChannelDescription] = [:]
            for ch in newCh { newLookup[ch.channelID] = ch }

            for (r, row) in rows.enumerated() {
                let chId = row.channelDesc.channelID
                let oldDesc = oldLookup[chId]
                let newDesc = newLookup[chId]
                let changed = oldDesc?.countMessUnread != newDesc?.countMessUnread
                    || (oldDesc?.hasLastSentMessage != newDesc?.hasLastSentMessage)
                    || (oldDesc?.lastSentMessage.timestampSeconds != newDesc?.lastSentMessage.timestampSeconds)
                    || (oldDesc?.lastSeenMessage.timestampSeconds != newDesc?.lastSeenMessage.timestampSeconds)
                    || (chId == prev.selectedChannelId) != (chId == new.selectedChannelId)
                if changed {
                    paths.append(IndexPath(row: r, section: s + sectionOffset))
                }
            }
        }

        guard !paths.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            self.tableNode.reloadRows(at: paths, with: .none)
        }
        CATransaction.commit()
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()
        layer.addSublayer(gradientLayer)
        addSubnode(tableNode)
        tableNode.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = false
        if #available(iOS 15.0, *) {
            tableNode.view.sectionHeaderTopPadding = 0
        }
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
    }

    private func scheduleReload() {
        cachedRows = [:]
        cachedHeaders = [:]
        safeReloadData()
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
        hasChannelAppsSection ? section - 1 : section
    }

    private var totalSections: Int {
        let appsSections = hasChannelAppsSection ? 1 : 0
        let catSections = state.categories.count
        return appsSections + catSections
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
        updateTableHeaderLayout()
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

    func configure(clanName: String, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        headerUIView.configure(title: clanName, memberCount: memberCount, isCommunity: isCommunity)
        let hadAppsSection = hasChannelAppsSection
        channelApps = []
        isChannelAppsExpanded = true
        if hadAppsSection && !isClanSwitching {
            safeReloadData()
        }

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
        }
    }

    func updateChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) {
        let oldIds = channelApps.map { $0.id }
        let newIds = apps.map { $0.id }
        guard oldIds != newIds else { return }
        channelApps = apps
        if !isClanSwitching {
            scheduleReload()
        }
    }

    func updateMemberCount(_ count: Int) {
        headerUIView.updateMemberCount(count)
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
        headerUIView.applyTheme()
        headerUIView.backgroundColor = t.primaryGradient
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

    private func rowsForSection(_ section: Int) -> [ChannelListRow] {
        if let cached = cachedRows[section] { return cached }
        guard section < state.categories.count else { return [] }
        let cat = state.categories[section]
        if cat.isCollapsed { cachedRows[section] = []; return [] }
        let rows = flattenCategoryToRows(cat, threadLookup: threadLookup)
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
                return 1 // single horizontal scroll row
            }
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
                return { ChannelAppHorizontalCellNode(apps: apps) }
            }
        }
        let catIdx = categoryIndex(forSection: indexPath.section)

        let rows = rowsForSection(catIdx)
        guard indexPath.row < rows.count else { return { ASCellNode() } }
        let row = rows[indexPath.row]
        let isSelected = row.channelDesc.channelID == state.selectedChannelId
        switch row {
        case .channel(let ch):
            return { ChannelItemCellNode(channel: ch, isSelected: isSelected) }
        case .thread(let ch, let isLast):
            return { ThreadItemCellNode(channel: ch, isSelected: isSelected, isLast: isLast) }
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
        if hasChannelAppsSection && indexPath.section == 0 { return }
        let catIdx = categoryIndex(forSection: indexPath.section)
        let rows = rowsForSection(catIdx)
        guard indexPath.row < rows.count else { return }
        interaction.onSelectChannel(rows[indexPath.row].channelDesc)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateStickyHeaderPosition()
    }
}

// ChannelItemCellNode → ChannelItemCellNode.swift
// ThreadItemCellNode  → ThreadItemCellNode.swift



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

    var onSearchTapped: (() -> Void)?

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

        addSubview(mainStack)
        addSubview(separator)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

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
        separator.backgroundColor = t.border.withAlphaComponent(0.3)
    }
}

// ChannelBannerView        → ChannelBannerView.swift
// ChannelAppCellNode       → ChannelAppNodes.swift
// ChannelAppHorizontalCellNode → ChannelAppNodes.swift
// ChannelAppIconItemView   → ChannelAppNodes.swift
