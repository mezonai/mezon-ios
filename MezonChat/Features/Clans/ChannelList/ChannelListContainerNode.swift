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
        let headerH: CGFloat = 56.sh
        let headerFrame = CGRect(x: 0, y: layout.safeInsets.top, width: layout.size.width, height: headerH)
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
        for (s, cat) in state.categories.enumerated() {
            for (r, ch) in cat.channels.enumerated() {
                if ch.channelID == previous || ch.channelID == current {
                    paths.append(IndexPath(row: r, section: s))
                }
            }
        }
        guard !paths.isEmpty else { return }
        tableNode.reloadRows(at: paths, with: .none)
    }
}

extension ChannelListContainerNode: ASTableDataSource {

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        state.isLoading && state.categories.isEmpty ? 1 : state.categories.count
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if state.isLoading && state.categories.isEmpty { return 1 }
        guard section < state.categories.count else { return 0 }
        let cat = state.categories[section]
        return cat.isCollapsed ? 0 : cat.channels.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if state.isLoading && state.categories.isEmpty { return { ChannelLoadingCellNode() } }
        guard indexPath.section < state.categories.count else { return { ASCellNode() } }
        let cat = state.categories[indexPath.section]
        guard indexPath.row < cat.channels.count else { return { ASCellNode() } }
        let channel = cat.channels[indexPath.row]
        let isSelected = channel.channelID == state.selectedChannelId
        return { ChannelItemCellNode(channel: channel, isSelected: isSelected) }
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
        guard indexPath.section < state.categories.count,
              indexPath.row < state.categories[indexPath.section].channels.count else { return }
        interaction.onSelectChannel(state.categories[indexPath.section].channels[indexPath.row])
    }
}

private final class ChannelItemCellNode: ASCellNode {

    private let iconNode     = ASTextNode2()
    private let iconImgNode  = ASImageNode()
    private let nameNode     = ASTextNode2()
    private let badgeNode    = ASTextNode2()
    private let indicatorBar = ASDisplayNode()

    private let channel: Mezon_Api_ChannelDescription
    private let cellSelected: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool) {
        self.channel      = channel
        self.cellSelected = isSelected
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        setupContent()
    }

    private func setupContent() {
        let t      = UIColor.theme
        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        let unread = channel.countMessUnread

        if chType.isSystemImage {
            iconImgNode.image     = UIImage(systemName: chType.icon)
            iconImgNode.tintColor = cellSelected ? t.channelUnread : (unread > 0 ? t.channelUnread : t.channelNormal)
            iconImgNode.isHidden  = false
            iconNode.isHidden     = true
        } else {
            iconNode.attributedText = NSAttributedString(
                string: chType.icon,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16.sf, weight: .regular),
                    .foregroundColor: cellSelected ? t.channelUnread : (unread > 0 ? t.channelUnread : t.channelNormal)
                ]
            )
            iconNode.isHidden    = false
            iconImgNode.isHidden = true
        }

        let nameStr   = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        let nameColor = cellSelected ? t.channelUnread : (unread > 0 ? t.channelUnread : t.channelNormal)
        nameNode.attributedText = NSAttributedString(
            string: nameStr,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .medium),
                .foregroundColor: nameColor
            ]
        )

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            badgeNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11.sf, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            )
            badgeNode.backgroundColor = .mezonUnreadBadge
            badgeNode.cornerRadius    = 8.swh
            badgeNode.isHidden        = false
        } else {
            badgeNode.isHidden = true
        }

        indicatorBar.backgroundColor = cellSelected ? t.channelUnread : .clear
        indicatorBar.cornerRadius    = 2
        backgroundColor = cellSelected ? t.colorActiveClan : .clear
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        iconNode.style.preferredSize    = CGSize(width: 20.swh, height: 20.swh)
        iconImgNode.style.preferredSize = CGSize(width: 18.swh, height: 18.swh)

        let iconChild: ASLayoutElement = iconNode.isHidden ? iconImgNode : iconNode

        badgeNode.style.minWidth = ASDimensionMake(16.swh)
        badgeNode.style.height   = ASDimensionMake(16.swh)

        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 6.sw,
            justifyContent: .start,
            alignItems: .center,
            children: badgeNode.isHidden
                ? [iconChild, nameNode]
                : [iconChild, nameNode, spacer, badgeNode]
        )
        nameNode.style.flexShrink = 1
        nameNode.style.flexGrow   = 0

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 16.sw, bottom: 0, right: 12.sw),
            child: row
        )

        indicatorBar.style.preferredSize = CGSize(width: 4.sw, height: 20.sh)
        let overlay = ASOverlayLayoutSpec(child: inset, overlay:
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: .infinity, left: 0, bottom: .infinity, right: .infinity),
                child: indicatorBar
            )
        )
        overlay.style.height = ASDimensionMake(36.sh)
        return overlay
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
        l.font = .systemFont(ofSize: 16.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let memberButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "person.2.fill")
        let btn = UIButton(configuration: config)
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
        addSubview(titleLabel)
        addSubview(memberButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16.sw),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: memberButton.leadingAnchor, constant: -8.sw),

            memberButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12.sw),
            memberButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            memberButton.widthAnchor.constraint(equalToConstant: 36.swh),
            memberButton.heightAnchor.constraint(equalToConstant: 36.swh),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) { titleLabel.text = title }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor           = t.secondary
        titleLabel.textColor      = t.textStrong
        separator.backgroundColor = t.border
        memberButton.tintColor    = t.textDisabled
    }
}
