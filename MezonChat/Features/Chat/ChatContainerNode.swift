import AVFoundation
import AsyncDisplayKit
import UIKit

struct ChatInteraction {
    let onBackTapped: () -> Void
    let onSearchTapped: () -> Void
    let onHistoryTapped: () -> Void
    let onMenuTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    let onMentionTapped: (String) -> Void
    let onHashtagTapped: (String) -> Void
    let onMessageLongPressed: (ChatMessageDisplay) -> Void
    var onMessagesReloaded: (() -> Void)?
}

final class ChatContainerNode: ASDisplayNode {

    let tableNode: ASTableNode
    var tableView: UITableView { tableNode.view }

    private let headerNode = ChatHeaderNode()
    private let skeletonNode = MessageSkeletonContainerNode(count: 8)
    private let loadingMoreNode = ASDisplayNode()
    private let emptyNode = ASTextNode2()

    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private(set) var state: ChatState = .empty
    private var committedMessageIds: [String] = []
    private var committedShowWelcome: Bool = false
    private let interaction: ChatInteraction
    private let disposables = DisposableSet()

    // MARK: - Init

    init(signal: Signal<ChatState, NoError>, interaction: ChatInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction

        let t = UIColor.theme
        loadingMoreNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.hidesWhenStopped = true
            indicator.color = t.textDisabled
            return indicator
        }

        super.init()
        addSubnode(headerNode)
        addSubnode(tableNode)
        addSubnode(skeletonNode)
        addSubnode(loadingMoreNode)
        addSubnode(emptyNode)

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
        tableNode.reloadData()
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
        if let indicator = loadingMoreNode.view as? UIActivityIndicatorView {
            state.isLoadingMore ? indicator.startAnimating() : indicator.stopAnimating()
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

    // MARK: - Differential updates

    private func safeReloadData() {
        tableNode.reloadData()
        committedMessageIds = state.messages.map { $0.id }
        committedShowWelcome = state.showWelcome
    }

    private func applyDiff(old: ChatState, new: ChatState) {
        let oldIds = committedMessageIds
        let newIds = new.messages.map { $0.id }

        if committedShowWelcome != new.showWelcome {
            safeReloadData()
            return
        }

        if oldIds.isEmpty && !newIds.isEmpty {
            safeReloadData()
            return
        }

        if oldIds == newIds {
            return
        }

        if newIds.count > oldIds.count && newIds.hasPrefix(oldIds) {
            let insertCount = newIds.count - oldIds.count
            let paths = (0..<insertCount).map { IndexPath(row: $0, section: 0) }

            let reloadPath: IndexPath? = oldIds.isEmpty ? nil : IndexPath(row: insertCount, section: 0)

            tableNode.performBatch(animated: false) {
                self.tableNode.insertRows(at: paths, with: .none)
                if let rp = reloadPath {
                    self.tableNode.reloadRows(at: [rp], with: .none)
                }
            } completion: { _ in }
            committedMessageIds = newIds
            return
        }

        if newIds.count > oldIds.count && newIds.hasSuffix(oldIds) {
            let insertCount = newIds.count - oldIds.count
            let baseRow = oldIds.count + (new.showWelcome ? 0 : 0)
            let paths = (0..<insertCount).map { IndexPath(row: baseRow + $0, section: 0) }

            tableNode.performBatch(animated: false) {
                self.tableNode.insertRows(at: paths, with: .none)
            } completion: { _ in }
            committedMessageIds = newIds
            return
        }

        let oldSet = Set(oldIds)
        let newSet = Set(newIds)
        let commonOld = oldIds.filter { newSet.contains($0) }
        let commonNew = newIds.filter { oldSet.contains($0) }

        guard commonOld == commonNew else {
            safeReloadData()
            return
        }

        var deletePaths: [IndexPath] = []
        for (i, id) in oldIds.enumerated() where !newSet.contains(id) {
            deletePaths.append(IndexPath(row: oldIds.count - 1 - i, section: 0))
        }

        var insertPaths: [IndexPath] = []
        for (i, id) in newIds.enumerated() where !oldSet.contains(id) {
            insertPaths.append(IndexPath(row: newIds.count - 1 - i, section: 0))
        }

        guard !deletePaths.isEmpty || !insertPaths.isEmpty else { return }

        tableNode.performBatch(animated: false) {
            if !deletePaths.isEmpty {
                self.tableNode.deleteRows(at: deletePaths, with: .none)
            }
            if !insertPaths.isEmpty {
                self.tableNode.insertRows(at: insertPaths, with: .none)
            }
        } completion: { _ in }
        committedMessageIds = newIds
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
        transition.updateFrame(node: loadingMoreNode, frame: CGRect(
                x: (fullWidth - liS) / 2,
                y: headerFrame.maxY + 12,
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
        let welcomeRows = state.showWelcome ? 1 : 0
        return welcomeRows + state.messages.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let msgCount = state.messages.count
        let currentState = state
        let chatInteraction = interaction

        if currentState.showWelcome, indexPath.row == msgCount {
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

        let messageIndex = msgCount - 1 - indexPath.row
        guard messageIndex >= 0, messageIndex < msgCount else {
            return { ASCellNode() }
        }

        let display = currentState.messages[messageIndex]
        return {
            let node = MessageBubbleNode(display: display, interaction: chatInteraction)
            node.transform = CATransform3DMakeScale(1, -1, 1)
            return node
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let distanceFromEnd = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        if distanceFromEnd < 80 || scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 80 {
            interaction.onScrolledNearTop()
        }
        let atBottom = scrollView.contentOffset.y < 100
        interaction.onScrolledToBottom(atBottom)
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
