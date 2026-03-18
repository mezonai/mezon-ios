import UIKit
import AsyncDisplayKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
    let onRefresh: (() -> Void)?
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
    private let interaction: ChannelListInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<ChannelListState, NoError>, interaction: ChannelListInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        super.init()
        backgroundColor = UIColor.theme.secondary

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prevState = self.state
                self.state = newState

                if let msg = newState.errorMessage, msg != prevState.errorMessage {
                    Toast.error(msg)
                }

                let structureChanged = prevState.categories.count != newState.categories.count
                    || prevState.isLoading != newState.isLoading
                    || zip(prevState.categories, newState.categories).contains(where: { $0.id != $1.id || $0.isCollapsed != $1.isCollapsed || $0.channels.count != $1.channels.count })

                if structureChanged || prevState.categories.isEmpty {
                    self.tableNode.reloadData()
                } else {
                    var paths: [IndexPath] = []
                    let sectionOffset = self.hasChannelAppsSection ? 1 : 0
                    for s in 0..<newState.categories.count {
                        let oldCh = prevState.categories[s].channels
                        let newCh = newState.categories[s].channels
                        let rows = self.rowsForSection(s)
                        for (r, row) in rows.enumerated() {
                            let chId = row.channelDesc.channelID
                            let oldDesc = oldCh.first(where: { $0.channelID == chId })
                            let newDesc = newCh.first(where: { $0.channelID == chId })
                            let changed = oldDesc?.countMessUnread != newDesc?.countMessUnread
                                || (oldDesc?.hasLastSentMessage != newDesc?.hasLastSentMessage)
                                || (oldDesc?.lastSentMessage.timestampSeconds != newDesc?.lastSentMessage.timestampSeconds)
                                || (oldDesc?.lastSeenMessage.timestampSeconds != newDesc?.lastSeenMessage.timestampSeconds)
                                || (chId == prevState.selectedChannelId) != (chId == newState.selectedChannelId)
                            if changed {
                                paths.append(IndexPath(row: r, section: s + sectionOffset))
                            }
                        }
                    }
                    if paths.isEmpty {
                        return
                    }
                    self.tableNode.reloadRows(at: paths, with: .none)
                }
            })
        )
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
        view.addSubview(headerUIView)
        headerUIView.layer.zPosition = 100
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
        let catSections = state.isLoading && state.categories.isEmpty ? 1 : state.categories.count
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

    func configure(clanName: String, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        headerUIView.configure(title: clanName, memberCount: memberCount, isCommunity: isCommunity)
        channelApps = []
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
        tableNode.view.contentOffset = .zero
        updateStickyHeaderPosition()
        DispatchQueue.main.async { [weak self] in
            self?.updateTableHeaderLayout()
            self?.updateStickyHeaderPosition()
        }
    }

    func updateChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) {
        channelApps = apps
        tableNode.reloadData()
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
        tableNode.reloadData()
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
        tableNode.reloadData()
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
        guard section < state.categories.count else { return [] }
        let cat = state.categories[section]
        if cat.isCollapsed { return [] }
        return flattenCategoryToRows(cat, allChannels: state.allChannels)
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
        if state.isLoading && state.categories.isEmpty { return 1 }
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
        if state.isLoading && state.categories.isEmpty { return { ChannelLoadingCellNode() } }
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
                let header = CategorySectionHeaderView()
                header.configureAppsHeader(isCollapsed: !isChannelAppsExpanded)
                header.onTap = { [weak self] in self?.toggleChannelAppsExpand() }
                return header
            } else {
                return nil // no header for horizontal mode
            }
        }
        let catIdx = categoryIndex(forSection: section)
        guard catIdx < state.categories.count else { return nil }
        let cat = state.categories[catIdx]
        let header = CategorySectionHeaderView()
        header.configure(category: cat)
        header.onTap = { [weak self] in self?.interaction.onToggleCollapse(cat.id) }
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

private final class ChannelItemCellNode: ASCellNode {

    private let iconNode = ASTextNode2()
    private let iconImgNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let unreadDot = ASDisplayNode()

    private let channel: Mezon_Api_ChannelDescription
    private let cellSelected: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool) {
        self.channel = channel
        self.cellSelected = isSelected
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        setupContent()
    }

    private func setupContent() {
        let t = UIColor.theme
        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        let isUnread =
            channel.countMessUnread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds
                    < channel.lastSentMessage.timestampSeconds)
        let unread = channel.countMessUnread

        let iconColor =
            cellSelected ? t.channelUnread : (isUnread ? t.channelUnread : t.channelNormal)
        if chType.isSystemImage {
            var iconName = chType.icon
            if chType == .text && channel.channelPrivate == 1 {
                iconName = "Channel/channelPrivate"
            }
            if chType == .text && channel.ageRestricted == 1 {
                iconName = "Channel/channelWarning"
            }
            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            iconImgNode.image = image?.withRenderingMode(.alwaysTemplate)
            iconImgNode.tintColor = iconColor
            iconImgNode.isHidden = false
            iconNode.isHidden = true
        } else {
            iconNode.attributedText = NSAttributedString(
                string: chType.icon,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: iconColor,
                ])
            iconNode.isHidden = false
            iconImgNode.isHidden = true
        }

        let nameStr = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        let nameColor =
            cellSelected ? t.channelUnread : (isUnread ? t.channelUnread : t.channelNormal)
        let nameWeight: UIFont.Weight = isUnread ? .semibold : .medium
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: nameStr,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: nameWeight),
                .foregroundColor: nameColor,
            ])

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            badgeNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10.sf, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: para,
                ])
            badgeNode.backgroundColor = .systemRed
            badgeNode.cornerRadius = 10.swh
            badgeNode.clipsToBounds = true
            badgeNode.isHidden = false
        } else {
            badgeNode.isHidden = true
        }

        unreadDot.backgroundColor = .white
        unreadDot.cornerRadius = 3.swh
        unreadDot.isHidden = !(unread > 0 && !cellSelected)

        if cellSelected {
            cornerRadius = 20.swh
            backgroundColor = t.colorActiveClan
        } else {
            cornerRadius = 0
            backgroundColor = .clear
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        iconNode.style.preferredSize = CGSize(width: 14.swh, height: 14.swh)
        iconImgNode.style.preferredSize = CGSize(width: 12.swh, height: 12.swh)
        let iconChild: ASLayoutElement = iconNode.isHidden ? iconImgNode : iconNode

        badgeNode.style.minWidth = ASDimensionMake(20.swh)
        badgeNode.style.height = ASDimensionMake(20.swh)

        unreadDot.style.preferredSize = CGSize(width: 6.swh, height: 6.swh)

        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1
        nameNode.style.flexShrink = 1
        nameNode.style.flexGrow = 0

        var children: [ASLayoutElement] = [iconChild, nameNode]
        if !badgeNode.isHidden {
            children.append(contentsOf: [spacer, badgeNode])
        }

        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: 10.sw, justifyContent: .start, alignItems: .center,
            children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 12.sw, bottom: 8.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(36.sh)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw), child: inset)
    }
}

private final class ThreadItemCellNode: ASCellNode {

    private let connectorNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let isLast: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool, isLast: Bool) {
        self.isLast = isLast
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        clipsToBounds = false

        let t = UIColor.theme
        let unread = channel.countMessUnread
        let isUnread =
            unread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds
                    < channel.lastSentMessage.timestampSeconds)

        let connectorName = isLast ? "Channel/ShortCorner" : "Channel/LongCorner"
        connectorNode.image = UIImage(named: connectorName)
        connectorNode.tintColor = t.channelNormal.withAlphaComponent(0.6)
        connectorNode.contentMode = .scaleAspectFit

        let nameColor =
            isSelected ? t.channelUnread : (isUnread ? t.channelUnread : t.channelNormal)
        let nameWeight: UIFont.Weight = isUnread ? .semibold : .regular
        nameNode.attributedText = NSAttributedString(
            string: channel.channelLabel,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: nameWeight),
                .foregroundColor: nameColor,
            ])

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            badgeNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10.sf, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: para,
                ])
            badgeNode.backgroundColor = .systemRed
            badgeNode.cornerRadius = 10.swh
            badgeNode.clipsToBounds = true
            badgeNode.isHidden = false
        } else {
            badgeNode.isHidden = true
        }

        backgroundColor = isSelected ? t.colorActiveClan : .clear
        if isSelected {
            cornerRadius = 16.swh
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        connectorNode.style.preferredSize = CGSize(
            width: isLast ? 12.swh : 14.swh, height: isLast ? 14.swh : 26.swh)
        badgeNode.style.minWidth = ASDimensionMake(20.swh)
        badgeNode.style.height = ASDimensionMake(20.swh)

        nameNode.style.flexShrink = 1
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        let topInset: CGFloat = isLast ? -4.sh : -18.sh
        let leftInset: CGFloat = isLast ? 2.sw : 0
        let connectorInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: topInset, left: leftInset, bottom: 0, right: 0),
            child: connectorNode)

        var children: [ASLayoutElement] = [connectorInset, nameNode]
        if !badgeNode.isHidden {
            children.append(contentsOf: [spacer, badgeNode])
        }

        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: 8.sw, justifyContent: .start, alignItems: .start,
            children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4.sh, left: 14.sw, bottom: 4.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(30.sh)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw), child: inset)
    }
}

private final class ChannelLoadingCellNode: ASCellNode {
    private let spinner: ASDisplayNode

    override init() {
        spinner = ASDisplayNode { UIActivityIndicatorView(style: .medium) }
        super.init()
        automaticallyManagesSubnodes = true
        spinner.style.preferredSize = CGSize(width: 24, height: 24)
        DispatchQueue.main.async { [weak spinner] in
            (spinner?.view as? UIActivityIndicatorView)?.startAnimating()
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let center = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: spinner)
        center.style.height = ASDimensionMake(60)
        return center
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

// MARK: - Channel Banner View

private final class ChannelBannerView: UIView {

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var currentURL: String?
    private let heightConstraint: NSLayoutConstraint

    override init(frame: CGRect) {
        heightConstraint = imageView.heightAnchor.constraint(equalToConstant: 140.sh)
        super.init(frame: frame)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func loadBanner(urlString: String) {
        guard urlString != currentURL else { return }
        currentURL = urlString
        imageView.image = nil

        guard let url = URL(string: urlString) else { return }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = UIImage(data: data), self.currentURL == urlString else { return }
            DispatchQueue.main.async {
                self.imageView.image = image
            }
        }
        task.resume()
    }

    func clearBanner() {
        currentURL = nil
        imageView.image = nil
    }
}

// MARK: - Channel App Cell Node (compact card as table row)

private final class ChannelAppCellNode: ASCellNode {

    private let cardNode = ASDisplayNode()
    private let logoNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let statusDot = ASDisplayNode()

    init(app: Mezon_Api_ChannelAppResponse) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none

        let t = UIColor.theme

        cardNode.backgroundColor = t.secondaryLight
        cardNode.cornerRadius = 12.swh
        cardNode.borderWidth = 1
        cardNode.borderColor = t.border.cgColor

        logoNode.style.preferredSize = CGSize(width: 30.swh, height: 30.swh)
        logoNode.cornerRadius = 10.swh
        logoNode.clipsToBounds = true
        logoNode.contentMode = .scaleAspectFit

        if !app.appLogo.isEmpty, let url = URL(string: app.appLogo) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.logoNode.image = image
                }
            }.resume()
        } else {
            logoNode.image = UIImage(named: "Channel/channelApp")?.withRenderingMode(.alwaysTemplate)
            logoNode.tintColor = t.textDisabled
            logoNode.contentMode = .center
        }

        let name = app.appName.isEmpty ? "App" : app.appName
        nameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: t.textStrong
            ]
        )
        nameNode.maximumNumberOfLines = 1
        nameNode.style.flexShrink = 1

        statusDot.style.preferredSize = CGSize(width: 8.swh, height: 8.swh)
        statusDot.cornerRadius = 4.swh
        statusDot.backgroundColor = UIColor(red: 0.24, green: 0.82, blue: 0.44, alpha: 1)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let contentRow = ASStackLayoutSpec.horizontal()
        contentRow.children = [logoNode, nameNode]
        contentRow.spacing = 8.sw  // compactCardLogo marginRight: 8
        contentRow.alignItems = .center
        contentRow.style.flexShrink = 1
        contentRow.style.flexGrow = 1

        let fullRow = ASStackLayoutSpec.horizontal()
        fullRow.children = [contentRow, statusDot]
        fullRow.spacing = 8.sw   // compactCardContent marginRight: 8
        fullRow.alignItems = .center

        let cardInsets = UIEdgeInsets(top: 0, left: 8.sw, bottom: 0, right: 16.sw)
        let insetContent = ASInsetLayoutSpec(insets: cardInsets, child: fullRow)

        cardNode.style.height = ASDimension(unit: .points, value: 42.sh)
        let cardSpec = ASBackgroundLayoutSpec(child: insetContent, background: cardNode)

        let cellInsets = UIEdgeInsets(top: 0, left: 12.sw, bottom: 8.sh, right: 12.sw)
        return ASInsetLayoutSpec(insets: cellInsets, child: cardSpec)
    }
}

// MARK: - Channel App Horizontal Cell Node (>3 apps, horizontal scroll)

private final class ChannelAppHorizontalCellNode: ASCellNode {

    private let displayApps: [Mezon_Api_ChannelAppResponse]

    init(apps: [Mezon_Api_ChannelAppResponse]) {
        let limit = 10
        displayApps = apps.count > limit ? Array(apps.prefix(limit)) : apps
        super.init()
        backgroundColor = .clear
        selectionStyle = .none
    }

    override func didLoad() {
        super.didLoad()

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 20.sw
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        for app in displayApps {
            let item = ChannelAppIconItemView()
            item.configure(app: app)
            stack.addArrangedSubview(item)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8.sh),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8.sh),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 12.sw),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12.sw),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: constrainedSize.width, height: 72.sh)
    }
}

// MARK: - Channel App Icon Item (for horizontal mode)

private final class ChannelAppIconItemView: UIView {

    private let logoContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 20.swh
        v.clipsToBounds = true
        v.layer.borderWidth = 0.5
        v.layer.borderColor = UIColor.clear.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.theme.primary
        return v
    }()

    private let logoView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10.sf, weight: .regular)
        l.textColor = UIColor.theme.text
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 1
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        logoContainer.addSubview(logoView)
        addSubview(logoContainer)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 40.sw),

            logoContainer.topAnchor.constraint(equalTo: topAnchor),
            logoContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoContainer.widthAnchor.constraint(equalToConstant: 40.swh),
            logoContainer.heightAnchor.constraint(equalToConstant: 40.swh),

            logoView.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 24.swh),
            logoView.heightAnchor.constraint(equalToConstant: 24.swh),

            nameLabel.topAnchor.constraint(equalTo: logoContainer.bottomAnchor, constant: 2.sh),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(app: Mezon_Api_ChannelAppResponse) {
        nameLabel.text = app.appName.isEmpty ? "App" : app.appName
        if !app.appLogo.isEmpty, let url = URL(string: app.appLogo) {
            let id = app.appName
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data),
                      self.nameLabel.text == id else { return }
                DispatchQueue.main.async { self.logoView.image = image }
            }.resume()
        } else {
            logoView.image = UIImage(named: "Channel/channelApp")?.withRenderingMode(.alwaysTemplate)
            logoView.tintColor = UIColor.theme.textDisabled
            logoView.contentMode = .center
            logoContainer.layer.borderColor = UIColor.theme.textDisabled.cgColor
        }
    }
}
