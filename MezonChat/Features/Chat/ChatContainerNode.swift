import AVFoundation
import AsyncDisplayKit
import UIKit

struct ChatInteraction {
    let onBackTapped: () -> Void
    let onSearchTapped: () -> Void
    let onHistoryTapped: () -> Void
    let onMenuTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledNearBottom: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    let onJumpToPresent: () -> Void
    let onMentionTapped: (String) -> Void
    let onHashtagTapped: (String) -> Void
    let onMessageLongPressed: (ChatMessageDisplay) -> Void
    let onReplyTapped: (String) -> Void
    var onMessagesReloaded: (() -> Void)?
}

final class ChatContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    var tableView: UITableView { tableNode.view }

    private let headerNode = ChatHeaderNode()
    private let skeletonNode = MessageSkeletonContainerNode(count: 8)
    private let loadingOlderNode = ASDisplayNode()
    private let loadingNewerNode = ASDisplayNode()
    private let jumpToPresentNode = ASButtonNode()

    private let emptyNode = ASTextNode2()

    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private(set) var state: ChatState = .empty
    private var committedMessageIds: [String] = []
    private let interaction: ChatInteraction
    private let disposables = DisposableSet()
    var pendingJumpMessageId: String?

    // MARK: - Init

    init(signal: Signal<ChatState, NoError>, interaction: ChatInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction

        let t = UIColor.theme
        loadingOlderNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.hidesWhenStopped = true
            indicator.color = t.textDisabled
            return indicator
        }
        loadingOlderNode.isHidden = true

        loadingNewerNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.hidesWhenStopped = true
            indicator.color = t.textDisabled
            return indicator
        }
        loadingNewerNode.isHidden = true

        super.init()
        addSubnode(headerNode)
        addSubnode(tableNode)
        addSubnode(skeletonNode)
        addSubnode(loadingOlderNode)
        addSubnode(loadingNewerNode)
        addSubnode(emptyNode)
        addSubnode(jumpToPresentNode)

        tableNode.dataSource = self
        tableNode.delegate = self

        headerNode.onBackTapped = { [weak self] in self?.interaction.onBackTapped() }

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let oldState = self.state
                self.state = newState
                self.updateHeader(state: newState)
                self.updateLoadingState(newState)
                if let msg = newState.errorMessage { Toast.error(msg) }

                let isEmpty = newState.messages.isEmpty
                self.emptyNode.isHidden = !(!newState.isLoading && isEmpty)

                if self.tableNode.bounds.width > 0 {
                    self.applyDiff(old: oldState, new: newState)
                } else {
                    self.needsReloadAfterLayout = true
                }
                if !isEmpty {
                    self.interaction.onMessagesReloaded?()
                }
                if self.pendingJumpMessageId != nil {
                    self.triggerPendingJump()
                }
            })
        )
    }

    deinit { disposables.dispose() }

    // MARK: - Lifecycle

    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        layer.insertSublayer(gradientLayer, at: 0)

        tableNode.backgroundColor = .clear
        tableNode.view.transform = CGAffineTransform(scaleX: 1, y: -1)
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = false
        tableNode.contentInset = UIEdgeInsets(top: 14, left: 0, bottom: 0, right: 0)

        // Jump to present button
        let btnSize: CGFloat = 40
        jumpToPresentNode.setImage(
            UIImage(systemName: "chevron.down")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            ).withTintColor(.white, renderingMode: .alwaysOriginal),
            for: .normal
        )
        jumpToPresentNode.backgroundColor = UIColor.theme.textDisabled.withAlphaComponent(0.85)
        jumpToPresentNode.cornerRadius = btnSize / 2
        jumpToPresentNode.clipsToBounds = true
        jumpToPresentNode.style.preferredSize = CGSize(width: btnSize, height: btnSize)
        jumpToPresentNode.isHidden = true
        jumpToPresentNode.alpha = 0
        jumpToPresentNode.addTarget(self, action: #selector(jumpToPresentTapped), forControlEvents: .touchUpInside)
    }

    @objc private func jumpToPresentTapped() {
        interaction.onJumpToPresent()
        setJumpButtonVisible(false)
    }

    private func setJumpButtonVisible(_ visible: Bool) {
        guard jumpToPresentNode.isHidden == visible else { return }
        if visible {
            jumpToPresentNode.isHidden = false
            UIView.animate(withDuration: 0.2) { self.jumpToPresentNode.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.2, animations: { self.jumpToPresentNode.alpha = 0 }) { _ in
                self.jumpToPresentNode.isHidden = true
            }
        }
    }

    // MARK: - Theme

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        headerNode.applyTheme()
        emptyNode.attributedText = NSAttributedString(
            string: L(L10n.ChannelMessages.emptyMessages),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        safeReloadData()
    }

    // MARK: - State helpers

    private func updateHeader(state: ChatState) {
        headerNode.configure(
            title: state.channelLabel,
            channelType: state.channelType,
            isPrivate: state.isPrivate,
            isAgeRestricted: state.isAgeRestricted
        )
    }

    private func updateLoadingState(_ state: ChatState) {
        let showSkeleton = state.isLoading && state.messages.isEmpty
        skeletonNode.isHidden = !showSkeleton
        skeletonNode.alpha = showSkeleton ? 1 : 0

        let showOlderLoading = state.isLoadingMore && state.hasMoreOlder
        loadingOlderNode.isHidden = !showOlderLoading
        if let indicator = loadingOlderNode.view as? UIActivityIndicatorView {
            showOlderLoading ? indicator.startAnimating() : indicator.stopAnimating()
        }

        let showNewerLoading = state.isLoadingNewer && state.hasMoreNewer
        loadingNewerNode.isHidden = !showNewerLoading
        if let indicator = loadingNewerNode.view as? UIActivityIndicatorView {
            showNewerLoading ? indicator.startAnimating() : indicator.stopAnimating()
        }
    }

    private var lastLayout: ContainerViewLayout?
    private var lastInputBarHeight: CGFloat = 0
    private var needsReloadAfterLayout = false

    func updateLayout(layout: ContainerViewLayout, inputBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let hadZeroFrame = tableNode.bounds.width == 0
        lastLayout = layout
        lastInputBarHeight = inputBarHeight
        applyFrameLayout(transition: transition)
        if hadZeroFrame && tableNode.bounds.width > 0 || needsReloadAfterLayout {
            needsReloadAfterLayout = false
            safeReloadData()
        }
    }

    func triggerPendingJump() {
        guard let jumpId = pendingJumpMessageId,
              state.messages.contains(where: { $0.id == jumpId }) else { return }
        pendingJumpMessageId = nil
        tableNode.waitUntilAllUpdatesAreProcessed()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.scrollToMessage(id: jumpId)
        }
    }

    func scrollToMessage(id: String) {
        guard let messageIndex = state.messages.firstIndex(where: { $0.id == id }) else { return }
        let row = state.messages.count - 1 - messageIndex
        let indexPath = IndexPath(row: row, section: 0)
        guard row >= 0, row < tableNode.numberOfRows(inSection: 0) else { return }
        tableNode.scrollToRow(at: indexPath, at: .middle, animated: true)

        // Wait for scroll animation to complete before highlighting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            // Re-check row index since table may have updated
            guard let idx = self.state.messages.firstIndex(where: { $0.id == id }) else { return }
            let currentRow = self.state.messages.count - 1 - idx
            let currentPath = IndexPath(row: currentRow, section: 0)
            guard let node = self.tableNode.nodeForRow(at: currentPath) as? MessageBubbleNode else { return }
            node.flashHighlight()
        }
    }

    // MARK: - Differential updates

    private func safeReloadData() {
        committedMessageIds = state.messages.map { $0.id }
        tableNode.reloadData()
    }

    private func applyDiff(old: ChatState, new: ChatState) {
        let oldIds = committedMessageIds
        let newIds = new.messages.map { $0.id }

        guard oldIds != newIds else { return }

        // Empty → populated or vice versa: full reload
        if oldIds.isEmpty || newIds.isEmpty {
            safeReloadData()
            return
        }

        // Case 1: New messages appended at end of array (newest messages)
        // Inverted table: inserting at row 0 pushes existing content up
        if newIds.count > oldIds.count && newIds.hasPrefix(oldIds) {
            let insertCount = newIds.count - oldIds.count
            let insertPaths = (0..<insertCount).map { IndexPath(row: $0, section: 0) }
            let reloadPath = IndexPath(row: 0, section: 0)

            // Save content state before insert to preserve scroll position
            let tableView = tableNode.view
            let oldContentHeight = tableView.contentSize.height
            let oldOffset = tableView.contentOffset

            committedMessageIds = newIds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tableNode.performBatch(animated: false) {
                self.tableNode.insertRows(at: insertPaths, with: .none)
                self.tableNode.reloadRows(at: [reloadPath], with: .none)
            } completion: { [weak self] _ in
                guard let self else { return }
                // Always adjust offset so visible messages stay in place
                let newContentHeight = self.tableNode.view.contentSize.height
                let heightDiff = newContentHeight - oldContentHeight
                if heightDiff > 0 {
                    self.tableNode.view.contentOffset = CGPoint(
                        x: oldOffset.x,
                        y: oldOffset.y + heightDiff
                    )
                }
            }
            CATransaction.commit()
            return
        }

        // Case 2: Older messages prepended at start of array
        // Inverted table: these appear at the top (high row indices)
        if newIds.count > oldIds.count && newIds.hasSuffix(oldIds) {
            let insertCount = newIds.count - oldIds.count
            let baseRow = oldIds.count
            // Insert rows use AFTER-state indices → at the top of inverted table
            let insertPaths = (0..<insertCount).map { IndexPath(row: baseRow + $0, section: 0) }

            // Save content state before insert to restore scroll position
            let tableView = tableNode.view
            let oldContentHeight = tableView.contentSize.height
            let oldOffset = tableView.contentOffset

            committedMessageIds = newIds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tableNode.performBatch(animated: false) {
                self.tableNode.insertRows(at: insertPaths, with: .none)
            } completion: { [weak self] _ in
                guard let self else { return }
                // Adjust content offset to keep visible messages in place
                let newContentHeight = self.tableNode.view.contentSize.height
                let heightDiff = newContentHeight - oldContentHeight
                if heightDiff > 0 {
                    self.tableNode.view.contentOffset = CGPoint(
                        x: oldOffset.x,
                        y: oldOffset.y + heightDiff
                    )
                }
            }
            CATransaction.commit()
            return
        }

        // Case 3: Same count — some IDs replaced (e.g. pending → real message)
        // Only reload the changed rows instead of full reloadData
        if newIds.count == oldIds.count {
            let msgCount = newIds.count
            var changedRows: [IndexPath] = []
            for i in 0..<msgCount {
                if oldIds[i] != newIds[i] {
                    // Inverted table: array index i → row (msgCount - 1 - i)
                    changedRows.append(IndexPath(row: msgCount - 1 - i, section: 0))
                }
            }
            if !changedRows.isEmpty && changedRows.count <= 5 {
                committedMessageIds = newIds
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tableNode.performBatch(animated: false) {
                    self.tableNode.reloadRows(at: changedRows, with: .none)
                } completion: { _ in }
                CATransaction.commit()
                return
            }
        }

        // All other cases: full reload
        safeReloadData()
    }

    private func applyFrameLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }
        let inputBarHeight = lastInputBarHeight
        let realSafeTop = view.safeAreaInsets.top
        let safeTop = realSafeTop > 20 ? realSafeTop : max(layout.safeInsets.top, 54)

        let fullWidth = view.bounds.width > 0 ? view.bounds.width : layout.size.width
        let headerH: CGFloat = 44
        let headerFrame = CGRect(x: 0, y: safeTop, width: fullWidth, height: headerH)
        transition.updateFrame(node: headerNode, frame: headerFrame)

        let tvFrame = CGRect(
            x: 0,
            y: headerFrame.maxY,
            width: fullWidth,
            height: max(layout.size.height - headerFrame.maxY - inputBarHeight - layout.intrinsicInsets.bottom, 0)
        )
        transition.updateFrame(node: tableNode, frame: tvFrame)

        transition.updateFrame(node: skeletonNode, frame: tvFrame)

        let liS: CGFloat = 24
        transition.updateFrame(node: loadingOlderNode, frame: CGRect(
            x: (fullWidth - liS) / 2,
            y: headerFrame.maxY + 12,
            width: liS,
            height: liS
        ))
        transition.updateFrame(node: loadingNewerNode, frame: CGRect(
            x: (fullWidth - liS) / 2,
            y: tvFrame.maxY - liS - 12,
            width: liS,
            height: liS
        ))
        let tableY = tvFrame.minY
        let tableH = tvFrame.height
        transition.updateFrame(node: emptyNode, frame: CGRect(
                x: 0,
                y: tableY + (tableH - 44) / 2,
                width: fullWidth,
                height: 44
            ))

        // Jump to present button — bottom-right, 10pt from right, 28pt from bottom of table
        let btnS: CGFloat = 40
        transition.updateFrame(node: jumpToPresentNode, frame: CGRect(
            x: fullWidth - btnS - 10,
            y: tvFrame.maxY - btnS - 28,
            width: btnS,
            height: btnS
        ))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        applyFrameLayout(transition: .immediate)
    }
}

// MARK: - ASTableDataSource & ASTableDelegate

extension ChatContainerNode: ASTableDataSource, ASTableDelegate {

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return state.messages.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let msgCount = state.messages.count
        let currentState = state
        let chatInteraction = interaction

        let messageIndex = msgCount - 1 - indexPath.row
        guard messageIndex >= 0, messageIndex < msgCount else {
            return { ASCellNode() }
        }

        let display = currentState.messages[messageIndex]

        if display.isWelcome {
            let label = currentState.channelLabel
            let channelType = currentState.channelType
            let isPrivate = currentState.isPrivate
            let isAgeRestricted = currentState.isAgeRestricted
            return {
                let node = WelcomeCellNode(
                    channelLabel: label,
                    channelType: channelType,
                    isPrivate: isPrivate,
                    isAgeRestricted: isAgeRestricted
                )
                node.transform = CATransform3DMakeScale(1, -1, 1)
                return node
            }
        }

        return {
            let node = MessageBubbleNode(display: display, interaction: chatInteraction)
            node.transform = CATransform3DMakeScale(1, -1, 1)
            return node
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let atBottom = scrollView.contentOffset.y < 100
        interaction.onScrolledToBottom(atBottom)

        // Show/hide jump to present button (inverted table: offset > 100 = scrolled away from latest)
        setJumpButtonVisible(scrollView.contentOffset.y >= 100)

        // Use visible index paths for reliable load-more detection in inverted table
        let visiblePaths = tableNode.indexPathsForVisibleRows()
        guard !visiblePaths.isEmpty else { return }

        let maxVisibleRow = visiblePaths.map(\.row).max() ?? 0
        let totalRows = tableNode.numberOfRows(inSection: 0)

        // Near oldest end (high row numbers in inverted table = top of screen)
        if maxVisibleRow >= totalRows - 5 && totalRows > 0 {
            interaction.onScrolledNearTop()
        }

        // Near newest end (low row numbers in inverted table = bottom of screen)
        let minVisibleRow = visiblePaths.map(\.row).min() ?? 0
        if minVisibleRow <= 2 && scrollView.contentOffset.y <= 0 && totalRows > 0 {
            interaction.onScrolledNearBottom()
        }
    }
}

// MARK: - Array diff helpers

extension Array where Element: Equatable {
    /// newIds.hasSuffix(oldIds) → old IDs are at the end of new IDs (new messages appended at end)
    fileprivate func hasSuffix(_ other: [Element]) -> Bool {
        guard other.count <= count else { return false }
        guard !other.isEmpty else { return true }
        let offset = count - other.count
        for i in 0..<other.count {
            if self[offset + i] != other[i] { return false }
        }
        return true
    }
    fileprivate func hasPrefix(_ other: [Element]) -> Bool {
        guard other.count <= count else { return false }
        guard !other.isEmpty else { return true }
        for i in 0..<other.count {
            if self[i] != other[i] { return false }
        }
        return true
    }
}
