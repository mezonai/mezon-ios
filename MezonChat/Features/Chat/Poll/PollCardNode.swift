import AsyncDisplayKit

final class PollCardNode: ASDisplayNode {

    private let cardNode = ASDisplayNode()
    private let questionNode = ASTextNode2()
    private let instructionNode = ASTextNode2()
    private var optionRowNodes: [PollOptionRowNode] = []
    private let footerSeparator = ASDisplayNode()
    private let statsNode = ASTextNode2()
    private let actionButton = ASDisplayNode()
    private let actionButtonLabel = ASTextNode2()
    private let loadMoreNode = ASTextNode2()

    private var pollData: PollData?
    private var selection: [Int] = []
    private var hasVoted: Bool = false
    private var showResults: Bool = false
    private var isExpandedOptions: Bool = false
    private var displayOptions: [PollOptionDisplay] = []

    private var messageId: String = ""
    private var channelId: String = ""
    var onVotePoll: ((_ messageId: String, _ channelId: String, _ answerIndices: [Int32], _ completion: @escaping ([Int32]?) -> Void) -> Void)?
    var onOpenPollDetail: ((_ messageId: String, _ channelId: String) -> Void)?
    var onLongPress: (() -> Void)?
    var onNeedsRelayout: (() -> Void)?

    private var cachedWidth: CGFloat = 0
    private var cachedQuestionSize: CGSize = .zero
    private var cachedInstructionSize: CGSize = .zero
    private var cachedStatsSize: CGSize = .zero
    private var cachedActionSize: CGSize = .zero
    private var cachedLoadMoreSize: CGSize = .zero
    private var cachedOptionSizes: [CGSize] = []

    private static let maxVisibleOptions = 5
    private static let blurpleColor = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 1)
    private static let cardPadding: CGFloat = 16
    private static let optionGap: CGFloat = 8
    private static let footerTopPadding: CGFloat = 12
    private static let actionBtnVPad: CGFloat = 6
    private static let actionBtnHPad: CGFloat = 12
    private static let actionBtnCorner: CGFloat = 8

    override init() {
        super.init()
        automaticallyManagesSubnodes = false
        backgroundColor = .clear
    }

    func configure(pollData: PollData, messageId: String, channelId: String, myVoteIndices: [Int]) {
        self.pollData = pollData
        self.messageId = messageId
        self.channelId = channelId

        restoreVoteStateFromCache(fallback: myVoteIndices)
        self.showResults = false
        self.isExpandedOptions = false

        buildDisplayOptions()
        buildUI()
    }

    func updatePollData(_ newPollData: PollData) {
        self.pollData = newPollData
        restoreVoteStateFromCache(fallback: [])
        refreshUI()
    }

    private func restoreVoteStateFromCache(fallback: [Int]) {
        let cached = PollVoteCache.shared.getVotes(for: messageId)
        let effective = cached ?? fallback
        self.selection = effective
        self.hasVoted = !effective.isEmpty
    }

    private var visibleOptions: [PollOptionDisplay] {
        if isExpandedOptions { return displayOptions }
        return Array(displayOptions.prefix(Self.maxVisibleOptions))
    }

    private var hiddenCount: Int {
        max(displayOptions.count - Self.maxVisibleOptions, 0)
    }

    private var shouldShowToggle: Bool {
        displayOptions.count > Self.maxVisibleOptions
    }

    private var shouldShowResults: Bool {
        showResults || hasVoted || (pollData?.isClosed ?? false)
    }

    private var isMultiple: Bool {
        pollData?.type == .multiple
    }

    private var shouldVote: Bool {
        !hasVoted && !selection.isEmpty
    }

    private func buildDisplayOptions() {
        guard let pollData else {
            displayOptions = []
            return
        }
        displayOptions = pollData.answers.map { answer in
            let voteCount = pollData.answerCounts[answer.index] ?? 0
            let percentage = pollData.totalVotes > 0
                ? Int(round(Double(voteCount) / Double(pollData.totalVotes) * 100))
                : 0
            return PollOptionDisplay(
                index: answer.index,
                label: answer.label,
                voteCount: voteCount,
                percentage: percentage,
                isSelected: selection.contains(answer.index)
            )
        }
    }

    private func buildUI() {
        optionRowNodes.forEach { $0.removeFromSupernode() }
        optionRowNodes.removeAll()

        let t = UIColor.theme

        cardNode.backgroundColor = t.primary
        cardNode.cornerRadius = 12
        cardNode.borderWidth = 1
        cardNode.borderColor = UIColor.mezonBorder.cgColor
        if cardNode.supernode == nil { addSubnode(cardNode) }

        questionNode.attributedText = NSAttributedString(
            string: pollData?.question ?? "",
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        questionNode.maximumNumberOfLines = 2
        if questionNode.supernode == nil { cardNode.addSubnode(questionNode) }

        let instructionText = isMultiple
            ? L(L10n.Poll.selectOneOrMore)
            : L(L10n.Poll.selectOne)
        instructionNode.attributedText = NSAttributedString(
            string: instructionText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        instructionNode.maximumNumberOfLines = 1
        if instructionNode.supernode == nil { cardNode.addSubnode(instructionNode) }

        for opt in visibleOptions {
            let row = PollOptionRowNode(
                option: opt,
                shouldShowResults: shouldShowResults,
                allowMultiple: isMultiple,
                hasVoted: hasVoted
            )
            row.onTapped = { [weak self] in
                self?.handleOptionPress(index: opt.index)
            }
            optionRowNodes.append(row)
            cardNode.addSubnode(row)
        }

        footerSeparator.backgroundColor = UIColor.mezonBorder
        if footerSeparator.supernode == nil { cardNode.addSubnode(footerSeparator) }

        if statsNode.supernode == nil { cardNode.addSubnode(statsNode) }
        updateStatsText()
        updateActionButton()
        updateLoadMoreText()
    }

    private func refreshUI() {
        buildDisplayOptions()

        let visible = visibleOptions
        for (i, row) in optionRowNodes.enumerated() {
            if i < visible.count {
                row.update(
                    option: visible[i],
                    shouldShowResults: shouldShowResults,
                    hasVoted: hasVoted
                )
            }
        }

        updateStatsText()
        updateActionButton()
        updateLoadMoreText()
        let _ = measureSize(maxWidth: cachedWidth)
        setNeedsLayout()
        onNeedsRelayout?()
    }

    private func updateStatsText() {
        guard let pollData else { return }
        let t = UIColor.theme

        let voteCount = pollData.totalVotes
        let voteWord = voteCount > 1 ? L(L10n.Poll.votes) : L(L10n.Poll.vote)
        let votePart = "\(voteCount) \(voteWord)"
        let timePart: String
        if pollData.isClosed {
            timePart = " • \(L(L10n.Poll.ended))"
        } else {
            let remaining = Self.timeRemainingString(expireAt: pollData.expireAt)
            timePart = " • \(remaining) \(L(L10n.Poll.left))"
        }

        let full = votePart + timePart
        let attr = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: pollData.isClosed ? UIColor.systemRed : t.textStrong,
            ]
        )
        statsNode.attributedText = attr
        statsNode.maximumNumberOfLines = 1
    }

    private func updateActionButton() {
        guard let pollData, !pollData.isClosed else {
            actionButton.removeFromSupernode()
            actionButtonLabel.removeFromSupernode()
            return
        }

        let title: String
        if showResults {
            title = L(L10n.Poll.backToVote)
        } else if shouldVote {
            title = L(L10n.Poll.voteButton)
        } else if hasVoted {
            title = L(L10n.Poll.removeVote)
        } else {
            title = L(L10n.Poll.showResults)
        }

        actionButton.backgroundColor = Self.blurpleColor
        actionButton.cornerRadius = Self.actionBtnCorner
        if actionButton.supernode == nil { cardNode.addSubnode(actionButton) }

        actionButtonLabel.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )
        actionButtonLabel.maximumNumberOfLines = 1
        if actionButtonLabel.supernode == nil { actionButton.addSubnode(actionButtonLabel) }
    }

    private func updateLoadMoreText() {
        guard shouldShowToggle else {
            loadMoreNode.removeFromSupernode()
            return
        }
        let t = UIColor.theme
        let text: String
        if isExpandedOptions {
            text = L(L10n.Poll.showLess)
        } else if hiddenCount == 1 {
            text = L(L10n.Poll.loadMore1Option)
        } else {
            text = String(format: L(L10n.Poll.loadMore), hiddenCount)
        }
        loadMoreNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        loadMoreNode.maximumNumberOfLines = 1
        if loadMoreNode.supernode == nil { cardNode.addSubnode(loadMoreNode) }
    }

    private func handleOptionPress(index: Int) {
        guard !hasVoted, !(pollData?.isClosed ?? false) else { return }

        if let existing = selection.firstIndex(of: index) {
            selection.remove(at: existing)
        } else {
            if isMultiple {
                selection.append(index)
            } else {
                selection = [index]
            }
        }

        refreshUI()
    }

    override func didLoad() {
        super.didLoad()

        let btnTap = UITapGestureRecognizer(target: self, action: #selector(handleActionTap))
        actionButton.view.addGestureRecognizer(btnTap)

        let statsTap = UITapGestureRecognizer(target: self, action: #selector(handleStatsTap))
        statsNode.view.addGestureRecognizer(statsTap)
        statsNode.isUserInteractionEnabled = true

        let loadMoreTap = UITapGestureRecognizer(target: self, action: #selector(handleLoadMoreTap))
        loadMoreNode.view.addGestureRecognizer(loadMoreTap)
        loadMoreNode.isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        view.addGestureRecognizer(longPress)
    }

    @objc private func handleActionTap() {
        guard let pollData else { return }
        if pollData.isClosed {
            showResults = true
            refreshUI()
            return
        }

        if showResults {
            showResults = false
            refreshUI()
            return
        }

        if hasVoted || !selection.isEmpty {
            let indices = hasVoted ? [] : selection.map { Int32($0) }
            onVotePoll?(messageId, channelId, indices) { [weak self] myVotes in
                guard let self else { return }
                if let myVotes {
                    let intVotes = myVotes.map { Int($0) }
                    self.hasVoted = !intVotes.isEmpty
                    self.selection = intVotes
                    self.showResults = false
                    PollVoteCache.shared.setVotes(for: self.messageId, indices: intVotes)
                    self.refreshUI()
                }
            }
        } else {
            showResults = true
            refreshUI()
        }
    }

    @objc private func handleStatsTap() {
        onOpenPollDetail?(messageId, channelId)
    }

    @objc private func handleLoadMoreTap() {
        isExpandedOptions.toggle()
        buildDisplayOptions()
        buildUI()
        let _ = measureSize(maxWidth: cachedWidth)
        setNeedsLayout()
        onNeedsRelayout?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onLongPress?()
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard pollData != nil else { return .zero }
        cachedWidth = maxWidth
        let pad = Self.cardPadding
        let contentWidth = max(maxWidth - pad * 2, 1)
        var totalH: CGFloat = pad

        cachedQuestionSize = questionNode.measure(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        totalH += cachedQuestionSize.height + 4

        cachedInstructionSize = instructionNode.measure(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        totalH += cachedInstructionSize.height + Self.cardPadding

        cachedOptionSizes = optionRowNodes.map { row in
            row.measureSize(maxWidth: contentWidth)
        }
        for (i, size) in cachedOptionSizes.enumerated() {
            totalH += size.height
            if i < cachedOptionSizes.count - 1 {
                totalH += Self.optionGap
            }
        }

        totalH += Self.footerTopPadding + 1 + Self.footerTopPadding

        cachedStatsSize = statsNode.measure(CGSize(width: contentWidth * 0.6, height: .greatestFiniteMagnitude))

        if actionButton.supernode != nil {
            cachedActionSize = actionButtonLabel.measure(CGSize(width: contentWidth * 0.4, height: .greatestFiniteMagnitude))
            cachedActionSize = CGSize(
                width: cachedActionSize.width + Self.actionBtnHPad * 2,
                height: cachedActionSize.height + Self.actionBtnVPad * 2
            )
        } else {
            cachedActionSize = .zero
        }

        totalH += max(cachedStatsSize.height, cachedActionSize.height)

        if shouldShowToggle {
            cachedLoadMoreSize = loadMoreNode.measure(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
            totalH += Self.optionGap + cachedLoadMoreSize.height
        } else {
            cachedLoadMoreSize = .zero
        }

        totalH += pad

        return CGSize(width: maxWidth, height: totalH)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let pad = Self.cardPadding
        let contentWidth = max(w - pad * 2, 1)

        cardNode.frame = bounds

        var y: CGFloat = pad

        questionNode.frame = CGRect(x: pad, y: y, width: cachedQuestionSize.width, height: cachedQuestionSize.height)
        y += cachedQuestionSize.height + 4

        instructionNode.frame = CGRect(x: pad, y: y, width: cachedInstructionSize.width, height: cachedInstructionSize.height)
        y += cachedInstructionSize.height + Self.cardPadding

        for (i, row) in optionRowNodes.enumerated() {
            let size = i < cachedOptionSizes.count ? cachedOptionSizes[i] : CGSize(width: contentWidth, height: 40)
            row.frame = CGRect(x: pad, y: y, width: contentWidth, height: size.height)
            y += size.height
            if i < optionRowNodes.count - 1 {
                y += Self.optionGap
            }
        }

        y += Self.footerTopPadding
        footerSeparator.frame = CGRect(x: pad, y: y, width: contentWidth, height: 1)
        y += 1 + Self.footerTopPadding
        let rowH = max(cachedStatsSize.height, cachedActionSize.height)
        let statsY = y + (rowH - cachedStatsSize.height) / 2
        statsNode.frame = CGRect(x: pad, y: statsY, width: cachedStatsSize.width, height: cachedStatsSize.height)

        if actionButton.supernode != nil {
            let btnX = w - pad - cachedActionSize.width
            let btnY = y + (rowH - cachedActionSize.height) / 2
            actionButton.frame = CGRect(x: btnX, y: btnY, width: cachedActionSize.width, height: cachedActionSize.height)
            let lblSize = actionButtonLabel.measure(CGSize(width: cachedActionSize.width, height: cachedActionSize.height))
            actionButtonLabel.frame = CGRect(
                x: (cachedActionSize.width - lblSize.width) / 2,
                y: (cachedActionSize.height - lblSize.height) / 2,
                width: lblSize.width,
                height: lblSize.height
            )
        }

        y += rowH

        if shouldShowToggle {
            y += Self.optionGap
            loadMoreNode.frame = CGRect(x: pad, y: y, width: cachedLoadMoreSize.width, height: cachedLoadMoreSize.height)
        }
    }

    private static func timeRemainingString(expireAt: TimeInterval) -> String {
        guard expireAt > 0 else { return "" }
        let now = Date().timeIntervalSince1970
        let remaining = expireAt - now
        if remaining <= 0 { return L(L10n.Poll.ended) }

        let hours = Int(remaining / 3600)
        let minutes = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)

        if hours >= 24 {
            let days = hours / 24
            return "\(days) \(L(L10n.Poll.days))"
        } else if hours > 0 {
            return "\(hours) \(L(L10n.Poll.hours))"
        } else {
            return "\(minutes) \(L(L10n.Poll.minutes))"
        }
    }
}
