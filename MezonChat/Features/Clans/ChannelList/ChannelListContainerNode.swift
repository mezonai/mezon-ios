import UIKit
import AsyncDisplayKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
}

final class ChannelListContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    private let headerUIView = ChannelListHeaderView()

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
                let prevErrorMessage = self.state.errorMessage
                let prevSelectedId = self.state.selectedChannelId
                self.state = newState

                if let msg = newState.errorMessage, msg != prevErrorMessage {
                    Toast.error(msg)
                }

                self.tableNode.reloadData()

                if prevSelectedId != newState.selectedChannelId {
                    self.reloadSelectionRows(previous: prevSelectedId, current: newState.selectedChannelId)
                }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()
        addSubnode(tableNode)
        tableNode.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = false
        tableNode.delegate = self
        tableNode.dataSource = self

        view.addSubview(headerUIView)
        headerUIView.applyTheme()
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        if layer.maskedCorners != [.layerMinXMinYCorner] {
            layer.cornerRadius = 20.swh
            layer.maskedCorners = [.layerMinXMinYCorner]
            clipsToBounds = true
        }

        let topOffset = layout.safeInsets.top + 10.sh
        let headerH: CGFloat = 90.sh
        let headerFrame = CGRect(x: 0, y: topOffset, width: layout.size.width, height: headerH)
        let tableFrame = CGRect(x: 0, y: headerFrame.maxY, width: layout.size.width, height: layout.size.height - headerFrame.maxY - layout.intrinsicInsets.bottom)
        transition.updateFrame(view: headerUIView, frame: headerFrame)
        transition.updateFrame(node: tableNode, frame: tableFrame)
    }

    func configure(clanName: String) {
        headerUIView.configure(title: clanName)
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        tableNode.backgroundColor = .clear
        headerUIView.applyTheme()
        tableNode.reloadData()
    }

    private func reloadSelectionRows(previous: Int64?, current: Int64?) {
        var paths: [IndexPath] = []
        for s in 0..<state.categories.count {
            let rows = rowsForSection(s)
            for (r, row) in rows.enumerated() {
                let chId = row.channelDesc.channelID
                if chId == previous || chId == current {
                    paths.append(IndexPath(row: r, section: s))
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
        state.isLoading && state.categories.isEmpty ? 1 : state.categories.count
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if state.isLoading && state.categories.isEmpty { return 1 }
        return rowsForSection(section).count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if state.isLoading && state.categories.isEmpty { return { ChannelLoadingCellNode() } }
        let rows = rowsForSection(indexPath.section)
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
        guard section < state.categories.count else { return nil }
        let cat = state.categories[section]
        let header = CategorySectionHeaderView()
        header.configure(category: cat)
        header.onTap = { [weak self] in self?.interaction.onToggleCollapse(cat.id) }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        state.categories.isEmpty ? 0 : 32.sh
    }
}

extension ChannelListContainerNode: ASTableDelegate {

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: false)
        let rows = rowsForSection(indexPath.section)
        guard indexPath.row < rows.count else { return }
        interaction.onSelectChannel(rows[indexPath.row].channelDesc)
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
        let unread = channel.countMessUnread

        let iconColor = cellSelected ? t.channelUnread : (unread > 0 ? t.channelUnread : t.channelNormal)
        if chType.isSystemImage {
            iconImgNode.image = UIImage(systemName: chType.icon)
            iconImgNode.tintColor = iconColor
            iconImgNode.isHidden = false
            iconNode.isHidden = true
        } else {
            iconNode.attributedText = NSAttributedString(string: chType.icon, attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                .foregroundColor: iconColor,
            ])
            iconNode.isHidden = false
            iconImgNode.isHidden = true
        }

        let nameStr = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        let nameColor = cellSelected ? t.channelUnread : (unread > 0 ? t.channelUnread : t.channelNormal)
        let nameWeight: UIFont.Weight = unread > 0 ? .semibold : .medium
        nameNode.attributedText = NSAttributedString(string: nameStr, attributes: [
            .font: UIFont.systemFont(ofSize: 14.sf, weight: nameWeight),
            .foregroundColor: nameColor,
        ])

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            badgeNode.attributedText = NSAttributedString(string: text, attributes: [
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

        let row = ASStackLayoutSpec(direction: .horizontal, spacing: 10.sw, justifyContent: .start, alignItems: .center, children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 12.sw, bottom: 8.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(36.sh)
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw), child: inset)
    }
}

private final class ThreadItemCellNode: ASCellNode {

    private let connectorNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool, isLast: Bool) {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none

        let t = UIColor.theme
        let unread = channel.countMessUnread

        let connectorName = isLast ? "arrow.turn.down.right" : "arrow.turn.down.right"
        connectorNode.image = UIImage(systemName: connectorName)
        connectorNode.tintColor = t.channelNormal.withAlphaComponent(0.4)
        connectorNode.contentMode = .scaleAspectFit

        let nameColor = isSelected ? t.channelUnread : (unread > 0 ? t.channelUnread : t.channelNormal)
        let nameWeight: UIFont.Weight = unread > 0 ? .semibold : .regular
        nameNode.attributedText = NSAttributedString(string: channel.channelLabel, attributes: [
            .font: UIFont.systemFont(ofSize: 13.sf, weight: nameWeight),
            .foregroundColor: nameColor,
        ])

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            badgeNode.attributedText = NSAttributedString(string: text, attributes: [
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

        if isSelected {
            cornerRadius = 16.swh
            backgroundColor = t.colorActiveClan
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        connectorNode.style.preferredSize = CGSize(width: 14.swh, height: 14.swh)
        badgeNode.style.minWidth = ASDimensionMake(20.swh)
        badgeNode.style.height = ASDimensionMake(20.swh)

        nameNode.style.flexShrink = 1
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        var children: [ASLayoutElement] = [connectorNode, nameNode]
        if !badgeNode.isHidden {
            children.append(contentsOf: [spacer, badgeNode])
        }

        let row = ASStackLayoutSpec(direction: .horizontal, spacing: 8.sw, justifyContent: .start, alignItems: .center, children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 6.sh, left: 38.sw, bottom: 6.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(30.sh)
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw), child: inset)
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

    private let arrowLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(arrowLabel)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            arrowLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8.sw),
            arrowLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowLabel.widthAnchor.constraint(equalToConstant: 14.sw),

            titleLabel.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: 4.sw),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8.sw)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(category: ChannelCategory) {
        let t = UIColor.theme
        backgroundColor      = t.secondary
        titleLabel.textColor = t.textDisabled
        arrowLabel.textColor = t.textDisabled
        titleLabel.text      = category.name.uppercased()
        arrowLabel.text      = category.isCollapsed ? "▶" : "▾"
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
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
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
        btn.setImage(UIImage(systemName: "qrcode"), for: .normal)
        btn.layer.cornerRadius = 16
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let eventButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "person.badge.plus"), for: .normal)
        btn.layer.cornerRadius = 16
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

        let infoRow = UIStackView(arrangedSubviews: [memberCountLabel, communityDot, communityLabel])
        infoRow.axis = .horizontal
        infoRow.spacing = 6
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

    func configure(title: String, memberCount: Int = 0) {
        titleLabel.text = title
        if memberCount > 0 {
            memberCountLabel.text = "\(memberCount) Members"
            memberCountLabel.isHidden = false
            communityDot.isHidden = false
            communityLabel.isHidden = false
        } else {
            memberCountLabel.isHidden = true
            communityDot.isHidden = true
            communityLabel.isHidden = true
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        titleLabel.textColor = t.textStrong
        memberCountLabel.textColor = t.textStrong
        communityLabel.textColor = t.textStrong
        searchBar.backgroundColor = t.tertiary
        searchIcon.tintColor = t.textDisabled
        searchLabel.textColor = t.textDisabled
        qrButton.backgroundColor = t.tertiary
        qrButton.tintColor = t.textDisabled
        eventButton.backgroundColor = t.tertiary
        eventButton.tintColor = t.textDisabled
        separator.backgroundColor = t.border.withAlphaComponent(0.3)
    }
}
