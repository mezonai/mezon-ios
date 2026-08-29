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

final class DirectMessagesContainerNode: ASDisplayNode {

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
    private let interaction: DirectMessagesInteraction
    private let disposables = DisposableSet()
    private var needsReloadOnLayout = false

    private let refreshControl = UIRefreshControl()
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?
    private var appliedActivityHeaderSize: CGSize?

    init(signal: Signal<DirectMessagesState, NoError>, interaction: DirectMessagesInteraction) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        super.init()
        let t0 = UIColor.theme
        backgroundColor = t0.secondary

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let previousState = self.state
                let directMessagesChanged = previousState.directMessages != newState.directMessages
                let activityRowsChanged = previousState.messageActivityRows != newState.messageActivityRows
                let avatarURLCacheChanged = previousState.resolvedAvatarURLByChannelId != newState.resolvedAvatarURLByChannelId
                let activityHeaderVisibilityChanged = previousState.messageActivityRows.isEmpty != newState.messageActivityRows.isEmpty
                let incomingCountChanged = previousState.incomingFriendRequestCount != newState.incomingFriendRequestCount
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
                    self.prefetchAvatarImages(for: Array(newState.directMessages.prefix(16)))
                    self.applyDirectMessageUpdates(
                        previous: previousState.directMessages,
                        new: newState.directMessages
                    )
                }
            })
        )
    }

    deinit { disposables.dispose() }

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
        
        badgeLabel.backgroundColor = UIColor(red: 236/255.0, green: 56/255.0, blue: 50/255.0, alpha: 1.0)
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
            searchCfg.image = UIImage.mezonSystemImage("magnifyingglass", withConfiguration: MezonSymbolConfiguration(pointSize: 14.sf))
            searchCfg.baseForegroundColor = UIColor.theme.textStrong
            searchCfg.baseBackgroundColor = UIColor.theme.primary
            searchCfg.cornerStyle = .capsule
            searchButton.configuration = searchCfg
        } else {
            searchButton.setImage(UIImage.mezonSystemImage("magnifyingglass", withConfiguration: MezonSymbolConfiguration(pointSize: 14.sf)), for: .normal)
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
            UIImage.mezonSystemImage("plus", withConfiguration: MezonSymbolConfiguration(pointSize: 18.sf, weight: .semibold)),
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

        if #available(iOS 13.0, *) {
            applyTheme()
        }
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

    @available(iOS 13.0, *)
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
            searchCfg.image = UIImage.mezonSystemImage("magnifyingglass", withConfiguration: MezonSymbolConfiguration(pointSize: 14.sf))
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
            UIImage.mezonSystemImage("plus", withConfiguration: MezonSymbolConfiguration(pointSize: 18.sf, weight: .semibold)),
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
              indexPath.row >= 0,
              indexPath.row < state.directMessages.count else { return }
        let channel = state.directMessages[indexPath.row]
        interaction.onLongPressDirectMessage(channel)
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
        let hasRawDiskCache = ImageCache.shared.hasOptimizedAvatarDiskCache(
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
        ) ?? ImageCache.shared.memoryOptimizedAvatar(
            forURL: avatarURL,
            targetPixelSize: targetPixelSize
        )
        guard cached == nil else { return }
        let loadURL = hasRawDiskCache ? avatarURL : proxied
        ImageCache.shared.loadOptimizedAvatar(
            urlString: loadURL,
            targetPixelSize: targetPixelSize
        ) { image in
            guard image == nil, loadURL != avatarURL else { return }
            ImageCache.shared.loadOptimizedAvatar(
                urlString: avatarURL,
                targetPixelSize: targetPixelSize
            ) { _ in }
        }
    }

    private static func channelIdOrder(_ channels: [Mezon_Api_ChannelDescription]) -> [Int64] {
        channels.map(\.channelID)
    }

    private func applyDirectMessageUpdates(
        previous: [Mezon_Api_ChannelDescription],
        new: [Mezon_Api_ChannelDescription]
    ) {
        guard tableView.frame.width > 0 else {
            needsReloadOnLayout = true
            return
        }

        let oldOrder = Self.channelIdOrder(previous)
        let newOrder = Self.channelIdOrder(new)

        if oldOrder == newOrder {
            reconfigureVisibleCells()
            return
        }

        if oldOrder.count == newOrder.count, Set(oldOrder) == Set(newOrder) {
            var oldIndexById: [Int64: Int] = [:]
            oldIndexById.reserveCapacity(oldOrder.count)
            for (index, id) in oldOrder.enumerated() {
                oldIndexById[id] = index
            }
            UIView.performWithoutAnimation {
                tableView.performBatchUpdates({
                    for (newIndex, id) in newOrder.enumerated() {
                        guard let oldIndex = oldIndexById[id], oldIndex != newIndex else { continue }
                        tableView.moveRow(
                            at: IndexPath(row: oldIndex, section: 0),
                            to: IndexPath(row: newIndex, section: 0)
                        )
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
            guard indexPath.row >= 0,
                  indexPath.row < state.directMessages.count,
                  let cell = tableView.cellForRow(at: indexPath) as? DmListItemCell else {
                continue
            }
            let channel = state.directMessages[indexPath.row]
            cell.configure(channel: channel, resolvedAvatarURL: state.resolvedAvatarURLByChannelId[channel.channelID])
        }
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.directMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DmListItemCell.reuseId, for: indexPath) as! DmListItemCell
        let channel = state.directMessages[indexPath.row]
        cell.configure(channel: channel, resolvedAvatarURL: state.resolvedAvatarURLByChannelId[channel.channelID])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        interaction.onSelectDirectMessage(state.directMessages[indexPath.row])
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let channels = indexPaths.compactMap { indexPath -> Mezon_Api_ChannelDescription? in
            guard indexPath.row >= 0, indexPath.row < state.directMessages.count else { return nil }
            return state.directMessages[indexPath.row]
        }
        prefetchAvatarImages(for: channels)
    }
}
