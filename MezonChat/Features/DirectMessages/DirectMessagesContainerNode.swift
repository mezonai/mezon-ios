import UIKit
import AsyncDisplayKit

struct DirectMessagesInteraction {
    let onSelectDirectMessage: (Mezon_Api_ChannelDescription) -> Void
    let onLongPressDirectMessage: (Mezon_Api_ChannelDescription) -> Void
    let onAddFriendTapped: () -> Void
    let onCreateGroupTapped: () -> Void
    let onSearchTapped: () -> Void
    let onBackTapped: () -> Void
    let onRefresh: () -> Void
    let onSelectMessageActivity: (DmMessageActivityItem) -> Void
}

private struct DmListSection {
    enum Kind {
        case all
        case pinned
        case unpinned
    }

    let kind: Kind
    let channels: [Mezon_Api_ChannelDescription]

    var title: String? {
        switch kind {
        case .all: return nil
        case .pinned: return L(L10n.DmMenu.pinnedSection)
        case .unpinned: return L(L10n.DmMenu.allMessagesSection)
        }
    }

    static func build(from state: DirectMessagesState) -> [DmListSection] {
        let pinnedIds = state.pinnedChannelIds
        let pinned = pinnedIds.isEmpty ? [] : state.directMessages.filter { pinnedIds.contains($0.channelID) }
        guard !pinned.isEmpty else {
            return [DmListSection(kind: .all, channels: state.directMessages)]
        }
        let unpinned = state.directMessages.filter { !pinnedIds.contains($0.channelID) }
        var sections = [DmListSection(kind: .pinned, channels: pinned)]
        if !unpinned.isEmpty {
            sections.append(DmListSection(kind: .unpinned, channels: unpinned))
        }
        return sections
    }
}

final class DirectMessagesContainerNode: ASDisplayNode {
    private let buzz: BuzzController
    private var buzzObserver: NSObjectProtocol?

    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let addFriendButton = UIButton(type: .system)
    private let badgeLabel = UILabel()
    private let searchButton = UIButton(type: .system)
    private let createGroupButton = UIButton(type: .system)
    private let tableView: UITableView
    private let activityStrip = DmMessageActivityStripView()
    private let activityTableHeaderWrapper = UIView()

    private var state: DirectMessagesState = .empty
    private var sections: [DmListSection] = []
    private let interaction: DirectMessagesInteraction
    private let disposables = DisposableSet()
    private var needsReloadOnLayout = false

    private let refreshControl = UIRefreshControl()
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?
    private var appliedActivityHeaderSize: CGSize?

    init(signal: Signal<DirectMessagesState, NoError>, interaction: DirectMessagesInteraction, buzz: BuzzController) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        self.buzz = buzz
        super.init()
        buzzObserver = NotificationCenter.default.addObserver(
            forName: .mezonBuzzStateChanged, object: buzz, queue: .main
        ) { [weak self] _ in self?.reconfigureVisibleCells() }
        let t0 = UIColor.theme
        backgroundColor = t0.secondary

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let previousState = self.state
                let directMessagesChanged = previousState.directMessages != newState.directMessages
                    || previousState.pinnedChannelIds != newState.pinnedChannelIds
                let activityRowsChanged = previousState.messageActivityRows != newState.messageActivityRows
                let avatarURLCacheChanged = previousState.resolvedAvatarURLByChannelId != newState.resolvedAvatarURLByChannelId
                let activityHeaderVisibilityChanged = previousState.messageActivityRows.isEmpty != newState.messageActivityRows.isEmpty
                let incomingCountChanged = previousState.incomingFriendRequestCount != newState.incomingFriendRequestCount
                let inVoiceChanged = previousState.inVoiceUserIds != newState.inVoiceUserIds
                    || previousState.screenSharingUserIds != newState.screenSharingUserIds
                self.state = newState

                if activityRowsChanged {
                    self.activityStrip.setItems(newState.messageActivityRows)
                }

                let previousBadgeHidden = self.badgeLabel.isHidden
                if newState.incomingFriendRequestCount > 0 {
                    self.badgeLabel.text = "\(newState.incomingFriendRequestCount)"
                    self.badgeLabel.isHidden = false
                } else {
                    self.badgeLabel.isHidden = true
                }
                let badgeNeedsLayout = incomingCountChanged || previousBadgeHidden != self.badgeLabel.isHidden

                if self.validLayout != nil, activityHeaderVisibilityChanged || badgeNeedsLayout {
                    self.applyLayout(transition: .immediate)
                }
                
                if directMessagesChanged || avatarURLCacheChanged {
                    let previousSections = self.sections
                    self.sections = DmListSection.build(from: newState)
                    self.prefetchAvatarImages(for: Array(self.sections.flatMap(\.channels).prefix(16)))
                    self.applyDirectMessageUpdates(
                        previous: previousSections,
                        new: self.sections
                    )
                } else if inVoiceChanged {
                    self.reconfigureVisibleCells()
                }
            })
        )
    }

    deinit {
        disposables.dispose()
        if let buzzObserver { NotificationCenter.default.removeObserver(buzzObserver) }
    }

    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        backgroundColor = t.secondary
        view.backgroundColor = t.secondary
        tableView.isOpaque = false
        tableView.backgroundView = nil

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 62.sh
        tableView.estimatedRowHeight = 62.sh
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.register(DmListItemCell.self, forCellReuseIdentifier: DmListItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.prefetchDataSource = self

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        tableView.addGestureRecognizer(longPress)

        refreshControl.tintColor = .mezonTextPrimary
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        badgeLabel.backgroundColor = .mezonUnreadBadge
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 10.sh
        badgeLabel.clipsToBounds = true
        if state.incomingFriendRequestCount > 0 {
            badgeLabel.text = "\(state.incomingFriendRequestCount)"
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }

        titleLabel.text = L(L10n.Tab.messages)
        titleLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong

        let addFriendImage = UIImage(named: "Notifications/AddFriendIcon", in: Bundle.main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
        if let addFriendImage {
            let targetSize = CGSize(width: 12.sf, height: 12.sf)
            let resized = resizedIconImage(addFriendImage, targetSize: targetSize)
            addFriendButton.setImage(resized, for: .normal)
        } else {
            addFriendButton.setImage(nil, for: .normal)
        }
        addFriendButton.setTitle(" \(L(L10n.DirectMessage.addFriend))", for: .normal)
        addFriendButton.titleLabel?.font = .systemFont(ofSize: 12.sf, weight: .medium)
        addFriendButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        addFriendButton.tintColor = nil
        addFriendButton.imageView?.tintColor = nil
        addFriendButton.backgroundColor = UIColor.theme.primary
        addFriendButton.contentHorizontalAlignment = .center
        addFriendButton.contentVerticalAlignment = .center
        addFriendButton.contentEdgeInsets = UIEdgeInsets(top: 6.sh, left: 10.sw, bottom: 6.sh, right: 10.sw)
        addFriendButton.imageView?.contentMode = .scaleAspectFit
        addFriendButton.layer.cornerRadius = 16
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)

        if #available(iOS 15.0, *) {
            var searchCfg = UIButton.Configuration.filled()
            searchCfg.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf))
            searchCfg.baseForegroundColor = UIColor.theme.textStrong
            searchCfg.baseBackgroundColor = UIColor.theme.primary
            searchCfg.cornerStyle = .capsule
            searchButton.configuration = searchCfg
        } else {
            searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf)), for: .normal)
            searchButton.tintColor = UIColor.theme.textStrong
            searchButton.backgroundColor = UIColor.theme.primary
            searchButton.layer.cornerRadius = 16
        }
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)

        createGroupButton.backgroundColor = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 1.0)
        createGroupButton.tintColor = .white
        createGroupButton.layer.cornerRadius = 25.swh
        createGroupButton.layer.shadowColor = UIColor.black.cgColor
        createGroupButton.layer.shadowOpacity = 0.22
        createGroupButton.layer.shadowRadius = 10
        createGroupButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        createGroupButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf, weight: .semibold)),
            for: .normal
        )
        createGroupButton.accessibilityLabel = L(L10n.DirectMessage.newGroup)
        createGroupButton.addTarget(self, action: #selector(createGroupTapped), for: .touchUpInside)

        activityStrip.onSelect = { [weak self] item in
            self?.interaction.onSelectMessageActivity(item)
        }

        view.addSubview(headerView)
        view.addSubview(addFriendButton)
        view.addSubview(badgeLabel)
        view.addSubview(searchButton)
        view.addSubview(tableView)
        view.addSubview(createGroupButton)

        activityTableHeaderWrapper.backgroundColor = .clear
        activityStrip.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        headerView.addSubview(titleLabel)

        if validLayout != nil {
            applyLayout(transition: .immediate)
        }

        applyTheme()
    }

    func updateLayout(size: CGSize, safeTop: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, safeTop, bottomInset)
        applyLayout(transition: transition)
        if needsReloadOnLayout && tableView.frame.width > 0 {
            needsReloadOnLayout = false
            tableView.reloadData()
        }
    }

    private let headerTopPadding: CGFloat = 8.sh

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let (size, safeTop, bottomInset) = validLayout else {
            return
        }

        let topY = safeTop + headerTopPadding
        let sideInset: CGFloat = 18.sw

        let titleH: CGFloat = 44
        transition.updateFrame(view: headerView, frame: CGRect(x: 0, y: topY, width: size.width, height: titleH))
        transition.updateFrame(view: titleLabel, frame: CGRect(x: sideInset, y: 0, width: size.width - sideInset * 2, height: titleH))

        let actionY = topY + titleH + 10.sh
        let actionH: CGFloat = 32.sh
        let searchSize: CGFloat = 32.swh
        let addW = size.width - sideInset * 2 - searchSize - 10.sw
        let addFriendFrame = CGRect(x: sideInset, y: actionY, width: addW, height: actionH)
        transition.updateFrame(view: addFriendButton, frame: addFriendFrame)
        transition.updateFrame(view: searchButton, frame: CGRect(x: size.width - sideInset - searchSize, y: actionY, width: searchSize, height: searchSize))

        if !badgeLabel.isHidden {
            self.badgeLabel.sizeToFit()
            let badgeSize = self.badgeLabel.bounds.size
            let bw = max(20.sh, badgeSize.width + 10.sw)
            let bh: CGFloat = 20.sh
            let bx = addFriendFrame.maxX - bw - 10.sw
            let by = addFriendFrame.midY - bh / 2
            transition.updateFrame(view: badgeLabel, frame: CGRect(x: bx, y: by, width: bw, height: bh))
        }

        let belowActions = actionY + actionH + 8.sh
        let tvTop = belowActions
        let tvHeight = size.height - tvTop - bottomInset

        transition.updateFrame(view: tableView, frame: CGRect(x: 0, y: tvTop, width: size.width, height: tvHeight))
        tableView.contentInset.bottom = 76.sh
        tableView.scrollIndicatorInsets.bottom = 76.sh

        let createButtonSize: CGFloat = 50.swh
        let createButtonX = size.width - sideInset - createButtonSize
        let createButtonY = size.height - bottomInset - createButtonSize - 18.sh
        transition.updateFrame(
            view: createGroupButton,
            frame: CGRect(x: createButtonX, y: createButtonY, width: createButtonSize, height: createButtonSize)
        )
        createGroupButton.layer.cornerRadius = createButtonSize / 2
        syncActivityTableHeader(width: size.width)
    }

    private func syncActivityTableHeader(width: CGFloat) {
        let stripH: CGFloat = state.messageActivityRows.isEmpty ? 0 : (50.sh + 8.sh)
        guard stripH > 0.5, width > 0.5 else {
            if tableView.tableHeaderView != nil {
                tableView.tableHeaderView = nil
            }
            appliedActivityHeaderSize = nil
            return
        }
        if activityStrip.superview !== activityTableHeaderWrapper {
            activityTableHeaderWrapper.addSubview(activityStrip)
        }
        let targetSize = CGSize(width: width, height: stripH)
        if appliedActivityHeaderSize == targetSize,
           tableView.tableHeaderView === activityTableHeaderWrapper {
            return
        }
        activityTableHeaderWrapper.frame = CGRect(x: 0, y: 0, width: width, height: stripH)
        activityStrip.frame = activityTableHeaderWrapper.bounds
        tableView.tableHeaderView = activityTableHeaderWrapper
        appliedActivityHeaderSize = targetSize
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        if isNodeLoaded {
            view.backgroundColor = t.secondary
        }
        titleLabel.textColor = t.textStrong

        guard isNodeLoaded else { return }

        addFriendButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        addFriendButton.backgroundColor = UIColor.theme.primary
        addFriendButton.tintColor = nil
        addFriendButton.imageView?.tintColor = nil
        let addFriendImage = UIImage(named: "Notifications/AddFriendIcon", in: Bundle.main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
        if let addFriendImage {
            let targetSize = CGSize(width: 12.sf, height: 12.sf)
            let resized = resizedIconImage(addFriendImage, targetSize: targetSize)
            addFriendButton.setImage(resized, for: .normal)
        } else {
            addFriendButton.setImage(nil, for: .normal)
        }

        if #available(iOS 15.0, *) {
            var searchCfg = UIButton.Configuration.filled()
            searchCfg.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf))
            searchCfg.baseForegroundColor = UIColor.theme.textStrong
            searchCfg.baseBackgroundColor = UIColor.theme.primary
            searchCfg.cornerStyle = .capsule
            searchButton.configuration = searchCfg
        } else {
            searchButton.tintColor = UIColor.theme.textStrong
            searchButton.backgroundColor = UIColor.theme.primary
        }

        createGroupButton.backgroundColor = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 1.0)
        createGroupButton.tintColor = .white
        createGroupButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf, weight: .semibold)),
            for: .normal
        )
        createGroupButton.accessibilityLabel = L(L10n.DirectMessage.newGroup)

        tableView.reloadData()
        activityStrip.applyTheme()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let channel = directMessage(at: indexPath) else { return }
        interaction.onLongPressDirectMessage(channel)
    }

    private func directMessage(at indexPath: IndexPath) -> Mezon_Api_ChannelDescription? {
        guard sections.indices.contains(indexPath.section) else { return nil }
        let channels = sections[indexPath.section].channels
        guard channels.indices.contains(indexPath.row) else { return nil }
        return channels[indexPath.row]
    }

    @objc private func addFriendTapped() { interaction.onAddFriendTapped() }
    @objc private func createGroupTapped() { interaction.onCreateGroupTapped() }
    @objc private func searchTapped() { interaction.onSearchTapped() }
    @objc private func handleRefresh() { interaction.onRefresh() }

    func endRefreshing() {
        refreshControl.endRefreshing()
    }

    func resetMessageActivityStripScroll(animated: Bool) {
        activityStrip.resetScrollToStart(animated: animated)
    }

    private func prefetchAvatarImages(for channels: [Mezon_Api_ChannelDescription]) {
        guard !channels.isEmpty else { return }
        for channel in channels {
            prefetchAvatarImage(for: channel)
        }
    }

    private func prefetchAvatarImage(for channel: Mezon_Api_ChannelDescription) {
        guard let avatarURL = state.resolvedAvatarURLByChannelId[channel.channelID],
              !avatarURL.isEmpty else {
            return
        }
        let proxied = ImgproxyURL.avatarProxyURL(from: avatarURL, width: 100, height: 100)
        let previewURL = ImgproxyURL.avatarPreviewProxyURL(
            from: avatarURL,
            width: 100,
            height: 100
        )
        let targetPixelSize = 120
        let hasRawDiskCache = proxied == avatarURL && ImageCache.shared.hasOptimizedAvatarDiskCache(
            forURL: avatarURL,
            targetPixelSize: targetPixelSize
        )
        if !hasRawDiskCache,
           previewURL != proxied,
           ImageCache.shared.memoryImage(forKey: previewURL) == nil {
            ImageCache.shared.loadImage(urlString: previewURL) { _ in }
        }
        let cached = ImageCache.shared.memoryOptimizedAvatar(
            forURL: proxied,
            targetPixelSize: targetPixelSize
        )
        guard cached == nil else { return }
        let loadURL = hasRawDiskCache ? avatarURL : proxied
        ImageCache.shared.loadOptimizedAvatar(
            urlString: loadURL,
            targetPixelSize: targetPixelSize
        ) { _ in }
    }

    private func applyDirectMessageUpdates(
        previous: [DmListSection],
        new: [DmListSection]
    ) {
        guard tableView.frame.width > 0 else {
            needsReloadOnLayout = true
            return
        }

        let oldOrder = previous.map { $0.channels.map(\.channelID) }
        let newOrder = new.map { $0.channels.map(\.channelID) }

        if oldOrder == newOrder, previous.map(\.kind) == new.map(\.kind) {
            reconfigureVisibleCells()
            return
        }

        let sameRowsPerSection = previous.map(\.kind) == new.map(\.kind)
            && zip(oldOrder, newOrder).allSatisfy { oldIds, newIds in
                oldIds.count == newIds.count && Set(oldIds) == Set(newIds)
            }

        if sameRowsPerSection {
            UIView.performWithoutAnimation {
                tableView.performBatchUpdates({
                    for (section, (oldIds, newIds)) in zip(oldOrder, newOrder).enumerated() {
                        var oldIndexById: [Int64: Int] = [:]
                        oldIndexById.reserveCapacity(oldIds.count)
                        for (index, id) in oldIds.enumerated() {
                            oldIndexById[id] = index
                        }
                        for (newIndex, id) in newIds.enumerated() {
                            guard let oldIndex = oldIndexById[id], oldIndex != newIndex else { continue }
                            tableView.moveRow(
                                at: IndexPath(row: oldIndex, section: section),
                                to: IndexPath(row: newIndex, section: section)
                            )
                        }
                    }
                }, completion: { [weak self] _ in
                    self?.reconfigureVisibleCells()
                })
            }
            return
        }

        tableView.reloadData()
    }

    private func reconfigureVisibleCells() {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else { return }
        for indexPath in visibleIndexPaths {
            guard let channel = directMessage(at: indexPath),
                  let cell = tableView.cellForRow(at: indexPath) as? DmListItemCell else {
                continue
            }
            cell.configure(
                channel: channel,
                resolvedAvatarURL: state.resolvedAvatarURLByChannelId[channel.channelID],
                voiceActivity: peerVoiceActivity(channel),
                hasBuzz: buzz.state.hasBuzz(channelId: channel.channelID)
            )
        }
    }

    private func peerVoiceActivity(_ channel: Mezon_Api_ChannelDescription) -> DmVoiceActivity? {
        guard channel.type == MezonConstants.ChannelType.dm.rawValue, channel.userIds.count == 1 else { return nil }
        let peerId = channel.userIds[0]
        if state.screenSharingUserIds.contains(peerId) { return .sharingScreen }
        return state.inVoiceUserIds.contains(peerId) ? .inVoice : nil
    }
}

private extension DirectMessagesContainerNode {
    func resizedIconImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return rendered.withRenderingMode(.alwaysOriginal)
    }
}

extension DirectMessagesContainerNode: UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections.indices.contains(section) ? sections[section].channels.count : 0
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sectionTitle(section) == nil ? 0 : 28.sh
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = sectionTitle(section) else { return nil }
        let header = UIView()
        header.backgroundColor = UIColor.theme.secondary
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        label.textColor = UIColor.theme.textDisabled
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18.sw),
            label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -18.sw),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    private func sectionTitle(_ section: Int) -> String? {
        sections.indices.contains(section) ? sections[section].title : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DmListItemCell.reuseId, for: indexPath) as! DmListItemCell
        let channel = sections[indexPath.section].channels[indexPath.row]
        cell.configure(
            channel: channel,
            resolvedAvatarURL: state.resolvedAvatarURLByChannelId[channel.channelID],
            voiceActivity: peerVoiceActivity(channel),
            hasBuzz: buzz.state.hasBuzz(channelId: channel.channelID)
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let channel = directMessage(at: indexPath) else { return }
        interaction.onSelectDirectMessage(channel)
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        prefetchAvatarImages(for: indexPaths.compactMap { directMessage(at: $0) })
    }
}
