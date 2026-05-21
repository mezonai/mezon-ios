import AsyncDisplayKit

final class PollOptionRowNode: ASDisplayNode {

    private let backgroundNode = ASDisplayNode()
    private let fillNode = ASDisplayNode()
    private let labelNode: ASDisplayNode = {
        let node = ASDisplayNode {
            let view = EmojiTextView()
            view.textView.textContainer.maximumNumberOfLines = 1
            view.textView.textContainer.lineBreakMode = .byTruncatingTail
            view.textView.isUserInteractionEnabled = false
            return view
        }
        node.isLayerBacked = false
        node.isUserInteractionEnabled = false
        return node
    }()
    private let metaNode = ASTextNode2()
    private let checkmarkNode = ASDisplayNode()
    private let checkIconNode = ASImageNode()

    private var option: PollOptionDisplay
    private var shouldShowResults: Bool
    private var allowMultiple: Bool
    private var hasVoted: Bool

    private var cachedSize: CGSize = .zero
    private var cachedAttributedLabelText: NSAttributedString? {
        didSet {
            if labelNode.isNodeLoaded {
                DispatchQueue.main.async {
                    (self.labelNode.view as? EmojiTextView)?.attributedText = self.cachedAttributedLabelText
                }
            }
        }
    }

    private static let rowHeight: CGFloat = 40
    private static let cornerRadius: CGFloat = 8
    private static let fillAnimationDuration: CFTimeInterval = 0.6
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

        updateLabelText()
        addSubnode(labelNode)

        metaNode.maximumNumberOfLines = 1
        metaNode.displaysAsynchronously = false
        metaNode.isLayerBacked = true
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
        let color = isLabelWhite == true ? UIColor.white : t.textStrong
        let font = UIFont.systemFont(ofSize: 14.sf)
        
        cachedAttributedLabelText = PollEmojiParser.parse(option.label, font: font, color: color, emojiSize: 20.sf)
    }

    private func updateMetaText() {
        let t = UIColor.theme
        let voteWord = option.voteCount > 1
            ? L(L10n.Poll.votes)
            : L(L10n.Poll.vote)
        metaNode.attributedText = NSAttributedString(
            string: "\(option.percentage)% \(option.voteCount) \(voteWord)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: isMetaWhite == true ? UIColor.white : t.textStrong,
            ]
        )
    }

    func update(option: PollOptionDisplay, shouldShowResults: Bool, hasVoted: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.update(option: option, shouldShowResults: shouldShowResults, hasVoted: hasVoted)
            }
            return
        }
        
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

        if option.isSelected {
            configureCheckmark()
            if checkmarkNode.supernode == nil {
                addSubnode(checkmarkNode)
            }
        } else if checkmarkNode.supernode != nil {
            checkmarkNode.removeFromSupernode()
        }

        let _ = measureSize(maxWidth: cachedSize.width > 0 ? cachedSize.width : 300)
        setNeedsLayout()
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
        if let attr = cachedAttributedLabelText {
            (labelNode.view as? EmojiTextView)?.attributedText = attr
        }
    }

    @objc private func handleTap() {
        guard !shouldShowResults else { return }
        onTapped?()
    }

    private var cachedLabelSize: CGSize = .zero
    private var cachedMetaSize: CGSize = .zero
    
    private var isLabelWhite: Bool?
    private var isMetaWhite: Bool?

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let hPad: CGFloat = 12
        let vPad: CGFloat = 10
        let checkSize: CGFloat = 20
        let gap: CGFloat = 8

        var availableWidth = maxWidth - hPad * 2
        if option.isSelected {
            availableWidth -= (checkSize + gap)
        }

        let labelMaxWidth = shouldShowResults ? availableWidth * 0.6 : availableWidth
        
        let labelAttr = cachedAttributedLabelText ?? NSAttributedString()
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = false
        let textContainer = NSTextContainer(size: CGSize(width: labelMaxWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        let textStorage = NSTextStorage(attributedString: labelAttr)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        
        var emojiMaxH: CGFloat = 0
        labelAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: labelAttr.length)) { value, _, _ in
            if let em = value as? EmojiTextAttachment {
                emojiMaxH = max(emojiMaxH, -em.bounds.origin.y + em.bounds.height)
            }
        }
        
        let textW = min(ceil(rect.width), labelMaxWidth)
        let textH = max(ceil(rect.height), emojiMaxH)
        cachedLabelSize = CGSize(width: textW, height: textH)
        
        let rowHeight = max(Self.rowHeight, cachedLabelSize.height + vPad * 2)

        if shouldShowResults {
            let metaMaxWidth = availableWidth - cachedLabelSize.width - gap
            cachedMetaSize = metaNode.measure(CGSize(width: metaMaxWidth, height: rowHeight))
        } else {
            cachedMetaSize = .zero
        }

        cachedSize = CGSize(width: maxWidth, height: rowHeight)
        
        let targetFillWidth: CGFloat = shouldShowResults ? maxWidth * CGFloat(option.percentage) / 100.0 : 0
        let touchesLabel = targetFillWidth > hPad + (cachedLabelSize.width * 0.4)
        
        let rightReserved: CGFloat = option.isSelected ? (checkSize + gap) : 0
        let metaX = maxWidth - hPad - rightReserved - cachedMetaSize.width
        let coversMeta = targetFillWidth >= (metaX + cachedMetaSize.width - 4)
        
        let shouldLabelBeWhite = hasVoted && option.isSelected && shouldShowResults && touchesLabel
        let shouldMetaBeWhite = hasVoted && option.isSelected && shouldShowResults && coversMeta
        
        if isLabelWhite == nil {
            isLabelWhite = shouldLabelBeWhite
            if shouldLabelBeWhite { updateLabelText() }
        } else if isLabelWhite != shouldLabelBeWhite {
            isLabelWhite = shouldLabelBeWhite
            updateLabelText()
        }
        
        if isMetaWhite == nil {
            isMetaWhite = shouldMetaBeWhite
            if shouldMetaBeWhite { updateMetaText() }
        } else if isMetaWhite != shouldMetaBeWhite {
            isMetaWhite = shouldMetaBeWhite
            updateMetaText()
        }
        
        return cachedSize
    }

    override func layout() {
        super.layout()
        var safeBounds = bounds
        safeBounds.size.width = max(safeBounds.size.width, 0)
        safeBounds.size.height = max(safeBounds.size.height, 0)
        
        let w = safeBounds.width
        let h = safeBounds.height
        let hPad: CGFloat = 12
        let checkSize: CGFloat = 20
        let gap: CGFloat = 8

        backgroundNode.frame = safeBounds

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

        var availableWidth = w - hPad * 2
        let rightReserved: CGFloat = (option.isSelected ? checkSize + gap : 0)
        availableWidth -= rightReserved

        let labelY = (h - cachedLabelSize.height) / 2
        labelNode.frame = CGRect(x: hPad, y: labelY, width: cachedLabelSize.width, height: cachedLabelSize.height)

        if shouldShowResults {
            let metaX = w - hPad - rightReserved - cachedMetaSize.width
            let metaY = (h - cachedMetaSize.height) / 2
            metaNode.frame = CGRect(x: metaX, y: metaY, width: cachedMetaSize.width, height: cachedMetaSize.height)
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
