import AsyncDisplayKit

final class PollOptionRowNode: ASDisplayNode {

    private let backgroundNode = ASDisplayNode()
    private let fillNode = ASDisplayNode()
    private let labelNode = ASTextNode2()
    private let metaNode = ASTextNode2()
    private let checkmarkNode = ASDisplayNode()
    private let checkIconNode = ASImageNode()

    private var option: PollOptionDisplay
    private var shouldShowResults: Bool
    private var allowMultiple: Bool
    private var hasVoted: Bool

    private var cachedSize: CGSize = .zero

    private static let rowHeight: CGFloat = 40
    private static let cornerRadius: CGFloat = 8
    private static let fillAnimationDuration: CFTimeInterval = 0.6
    private static let activeTextWhiteThreshold = 0
    private static let blurpleColor = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 1)
    private static let blurpleFillResult = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 0.35)

    var onTapped: (() -> Void)?

    init(option: PollOptionDisplay, shouldShowResults: Bool, allowMultiple: Bool, hasVoted: Bool) {
        self.option = option
        self.shouldShowResults = shouldShowResults
        self.allowMultiple = allowMultiple
        self.hasVoted = hasVoted
        super.init()
        automaticallyManagesSubnodes = false
        backgroundColor = .clear

        let t = UIColor.theme

        backgroundNode.backgroundColor = t.secondaryWeight
        backgroundNode.cornerRadius = Self.cornerRadius
        backgroundNode.clipsToBounds = true
        addSubnode(backgroundNode)

        fillNode.cornerRadius = Self.cornerRadius
        fillNode.clipsToBounds = true
        updateFillNodeAppearance()
        backgroundNode.addSubnode(fillNode)

        labelNode.maximumNumberOfLines = 1
        updateLabelText()
        addSubnode(labelNode)

        metaNode.maximumNumberOfLines = 1
        updateMetaText()
        if shouldShowResults {
            addSubnode(metaNode)
        }

        configureCheckmark()
        if option.isSelected {
            addSubnode(checkmarkNode)
        }
    }

    private func configureCheckmark() {
        let size: CGFloat = 20
        checkmarkNode.backgroundColor = hasVoted ? Self.blurpleColor : UIColor.theme.textStrong
        checkmarkNode.cornerRadius = allowMultiple ? 4 : size / 2
        checkmarkNode.clipsToBounds = true

        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        checkIconNode.image = UIImage(systemName: "checkmark", withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        checkIconNode.tintColor = hasVoted ? .white : UIColor.theme.primary
        checkIconNode.contentMode = .scaleAspectFit
        checkmarkNode.addSubnode(checkIconNode)
    }

    private func updateFillNodeAppearance() {
        if option.isSelected {
            fillNode.backgroundColor = Self.blurpleColor
        } else if shouldShowResults {
            fillNode.backgroundColor = Self.blurpleFillResult
        } else {
            fillNode.backgroundColor = .clear
        }
    }

    private func updateLabelText() {
        let t = UIColor.theme
        let shouldUseActiveColor = hasVoted && option.isSelected && shouldShowResults
            && option.percentage >= 0
        labelNode.attributedText = NSAttributedString(
            string: option.label,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf),
                .foregroundColor: shouldUseActiveColor ? UIColor.white : t.textStrong,
            ]
        )
    }

    private func updateMetaText() {
        let t = UIColor.theme
        let shouldUseActiveColor = hasVoted && option.isSelected && shouldShowResults
            && option.percentage >= Self.activeTextWhiteThreshold
        let voteWord = option.voteCount > 1
            ? L(L10n.Poll.votes)
            : L(L10n.Poll.vote)
        metaNode.attributedText = NSAttributedString(
            string: "\(option.percentage)% \(option.voteCount) \(voteWord)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: shouldUseActiveColor ? UIColor.white : t.textDisabled,
            ]
        )
    }

    func update(option: PollOptionDisplay, shouldShowResults: Bool, hasVoted: Bool) {
        self.option = option
        self.shouldShowResults = shouldShowResults
        self.hasVoted = hasVoted

        updateFillNodeAppearance()
        updateLabelText()
        updateMetaText()

        if shouldShowResults && metaNode.supernode == nil {
            addSubnode(metaNode)
        } else if !shouldShowResults && metaNode.supernode != nil {
            metaNode.removeFromSupernode()
        }

        if option.isSelected && checkmarkNode.supernode == nil {
            configureCheckmark()
            addSubnode(checkmarkNode)
        } else if !option.isSelected && checkmarkNode.supernode != nil {
            checkmarkNode.removeFromSupernode()
        }

        let _ = measureSize(maxWidth: cachedSize.width > 0 ? cachedSize.width : 300)
        setNeedsLayout()
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        guard !shouldShowResults else { return }
        onTapped?()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let hPad: CGFloat = 12
        let vPad: CGFloat = 10
        let checkSize: CGFloat = 20
        let gap: CGFloat = 8

        var contentWidth = maxWidth - hPad * 2

        if option.isSelected {
            contentWidth -= (checkSize + gap)
        }

        let labelSize = labelNode.measure(CGSize(width: contentWidth * 0.6, height: .greatestFiniteMagnitude))
        var rowHeight = max(Self.rowHeight, labelSize.height + vPad * 2)

        if shouldShowResults {
            let metaSize = metaNode.measure(CGSize(width: contentWidth * 0.4, height: .greatestFiniteMagnitude))
            _ = metaSize
        }

        cachedSize = CGSize(width: maxWidth, height: rowHeight)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let hPad: CGFloat = 12
        let checkSize: CGFloat = 20
        let gap: CGFloat = 8

        backgroundNode.frame = bounds

        let targetFillWidth: CGFloat = shouldShowResults
            ? w * CGFloat(option.percentage) / 100.0
            : 0
        let fillFrame = CGRect(x: 0, y: 0, width: targetFillWidth, height: h)

        if fillNode.frame.width != targetFillWidth && shouldShowResults {
            UIView.animate(withDuration: Self.fillAnimationDuration, delay: 0, options: .curveEaseOut) {
                self.fillNode.frame = fillFrame
            }
        } else {
            fillNode.frame = fillFrame
        }

        var contentX = hPad
        let labelMeasured = labelNode.measure(CGSize(width: w - hPad * 2 - (option.isSelected ? checkSize + gap : 0), height: h))
        let labelY = (h - labelMeasured.height) / 2
        labelNode.frame = CGRect(x: contentX, y: labelY, width: labelMeasured.width, height: labelMeasured.height)

        if shouldShowResults {
            let metaMeasured = metaNode.measure(CGSize(width: w * 0.4, height: h))
            let metaX = contentX + labelMeasured.width + gap
            let metaY = (h - metaMeasured.height) / 2
            metaNode.frame = CGRect(x: metaX, y: metaY, width: metaMeasured.width, height: metaMeasured.height)
        }

        if option.isSelected {
            let checkX = w - hPad - checkSize
            let checkY = (h - checkSize) / 2
            checkmarkNode.frame = CGRect(x: checkX, y: checkY, width: checkSize, height: checkSize)
            let iconSize: CGFloat = 14
            checkIconNode.frame = CGRect(
                x: (checkSize - iconSize) / 2,
                y: (checkSize - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
        }
    }
}
