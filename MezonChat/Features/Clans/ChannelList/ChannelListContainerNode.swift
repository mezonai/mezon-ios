import UIKit
import AsyncDisplayKit

struct ChannelListInteraction {
    let onSelectChannel: (Mezon_Api_ChannelDescription) -> Void
    let onToggleCollapse: (Int64) -> Void
}

final class ChannelListContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    private let headerUIView = ChannelListHeaderView()
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
                                paths.append(IndexPath(row: r, section: s))
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()

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
        l.font = .systemFont(ofSize: 11.sf, weight: .bold)
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
            arrowIcon.widthAnchor.constraint(equalToConstant: 12.sw),
            arrowIcon.heightAnchor.constraint(equalToConstant: 12.sw),

            titleLabel.leadingAnchor.constraint(equalTo: arrowIcon.trailingAnchor, constant: 4.sw),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8.sw),
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

        let infoRow = UIStackView(arrangedSubviews: [
            memberCountLabel, communityDot, communityLabel,
        ])
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
