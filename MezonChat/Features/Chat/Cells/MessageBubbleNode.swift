import UIKit
import AsyncDisplayKit

final class MessageBubbleNode: ASDisplayNode {

    private let avatarContainerNode = ASDisplayNode()
    private let avatarImageNode = TransformImageNode()
    private let avatarPlaceholderNode = ASTextNode2()

    private let nameNode = ASTextNode2()
    private let timeNode = ASTextNode2()

    private var replyNode: MessageReplyNode?
    private var deletedReplyNode: MessageDeletedReplyNode?
    private var callLogNode: MessageCallLogNode?
    private var topicNode: MessageTopicNode?
    private var textContentNode: MessageTextContentNode?
    private var mediaContentNode: MessageMediaContentNode?
    private var audioAttachmentNode: MessageAudioAttachmentNode?
    private var fileAttachmentNode: MessageFileAttachmentNode?
    private var embedNode: MessageEmbedNode?
    private var reactionsNode: MessageReactionsNode?
    private var locationNode: MessageLocationNode?
    private var errorTextNode: ASTextNode2?

    private(set) var display: ChatMessageDisplay
    private let interaction: ChatInteraction
    private let isCombine: Bool
    private let hasCallLog: Bool
    private let hasTopic: Bool
    private let hasContent: Bool
    private let hasMedia: Bool
    private let hasAudio: Bool
    private let hasFiles: Bool
    private let hasEmbeds: Bool
    private let showsReactionStrip: Bool
    private let hasReply: Bool
    private let hasDeletedReply: Bool
    private let hasLocation: Bool
    private var isFailed: Bool = false

    private static let avatarSize: CGFloat = 40
    private static let contentLeading: CGFloat = 40 + 12.sw

    private var cachedNameSize: CGSize = .zero
    private var cachedTimeSize: CGSize = .zero
    private var cachedReplySize: CGSize = .zero
    private var cachedCallLogSize: CGSize = .zero
    private var cachedTopicSize: CGSize = .zero
    private var cachedTextSize: CGSize = .zero
    private var cachedMediaSize: CGSize = .zero
    private var cachedAudioSize: CGSize = .zero
    private var cachedFileSize: CGSize = .zero
    private var cachedEmbedSize: CGSize = .zero
    private var cachedReactionsSize: CGSize = .zero
    private var cachedLocationSize: CGSize = .zero
    private var cachedErrorSize: CGSize = .zero
    private var cachedForwardHeaderSize: CGSize = .zero
    private var cachedForwardLabelSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

    private let forwardLeftBarNode: ASDisplayNode?
    private let forwardHeaderIconNode: ASImageNode?
    private let forwardHeaderLabelNode: ASTextNode2?

    private static let forwardHeaderIconSide: CGFloat = 15
    private static let forwardHeaderIconGap: CGFloat = 4

    init(display: ChatMessageDisplay, interaction: ChatInteraction) {
        self.display = display
        self.interaction = interaction
        self.isCombine = display.isCombine
        self.hasReply = display.replyRef != nil
        self.hasDeletedReply = display.isDeletedReply
        self.hasCallLog = display.isCallLog
        self.hasTopic = display.isTopic

        let parsed = display.parsedContent
        let mediaAttachments = display.attachments.filter { $0.isMedia }
        let audioAttachments = display.attachments.filter { $0.isAudio && !$0.url.isEmpty }
        let fileAttachments = display.attachments.filter {
            !$0.isMedia && !$0.isAudio && (!$0.url.isEmpty || $0.isUploading)
        }

        if display.isCallLog {
            self.hasContent = false
            self.hasMedia = false
            self.hasAudio = false
            self.hasFiles = false
            self.hasEmbeds = false
            self.hasLocation = false
        } else if display.isLocation {
            self.hasContent = false
            self.hasMedia = false
            self.hasAudio = false
            self.hasFiles = false
            self.hasEmbeds = false
            self.hasLocation = true
        } else {
            if display.checkOneLinkImage {
                self.hasContent = false
            } else {
                self.hasContent = !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            self.hasMedia = !mediaAttachments.isEmpty
            self.hasAudio = !audioAttachments.isEmpty
            self.hasFiles = !fileAttachments.isEmpty
            self.hasEmbeds = !parsed.embeds.isEmpty
            self.hasLocation = false
        }
        self.showsReactionStrip = Self.shouldShowReactionStrip(for: display)

        if display.isForward {
            let b = ASDisplayNode()
            b.backgroundColor = UIColor.mezonBorder
            self.forwardLeftBarNode = b
        } else {
            self.forwardLeftBarNode = nil
        }
        if display.showForwardHeader {
            let icon = ASImageNode()
            let sym = UIImage(systemName: "arrowshape.turn.up.right")
                ?? UIImage(systemName: "arrow.turn.up.right")
            icon.image = sym?.withRenderingMode(.alwaysTemplate)
            icon.tintColor = UIColor.theme.textDisabled
            icon.contentMode = .scaleAspectFit
            let lbl = ASTextNode2()
            lbl.attributedText = Self.forwardHeaderLabelAttributedString()
            lbl.maximumNumberOfLines = 1
            self.forwardHeaderIconNode = icon
            self.forwardHeaderLabelNode = lbl
        } else {
            self.forwardHeaderIconNode = nil
            self.forwardHeaderLabelNode = nil
        }

        super.init()
        automaticallyManagesSubnodes = false
        backgroundColor = .clear

        if display.hasIncludeMention {
            mentionHighlightNode.backgroundColor = UIColor(red: 201.0/255, green: 157.0/255, blue: 7.0/255, alpha: 0.1)
            mentionHighlightNode.isUserInteractionEnabled = false
            addSubnode(mentionHighlightNode)

            mentionBorderNode.backgroundColor = UIColor(red: 240.0/255, green: 177.0/255, blue: 50.0/255, alpha: 1.0)
            mentionHighlightNode.addSubnode(mentionBorderNode)
        }

        let t = UIColor.theme

        avatarContainerNode.backgroundColor = .colorAvatarDefault
        avatarContainerNode.cornerRadius = Self.avatarSize / 2
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.addSubnode(avatarPlaceholderNode)
        avatarContainerNode.addSubnode(avatarImageNode)

        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: String(display.senderDisplayName.prefix(1)).uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )

        nameNode.attributedText = NSAttributedString(
            string: display.senderDisplayName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                .foregroundColor: t.textRoleLink,
            ]
        )
        nameNode.maximumNumberOfLines = 1

        let timeText: String = {
            var str = Self.formatDate(display.message.createdAt)
            if display.message.editedAt != nil {
                str += " (edited)"
            }
            return str
        }()
        timeNode.attributedText = NSAttributedString(
            string: timeText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.textDisabled,
            ]
        )

        if !isCombine {
            addSubnode(avatarContainerNode)
            addSubnode(nameNode)
            addSubnode(timeNode)
            loadAvatar()
        }

        if let ref = display.replyRef {
            let rn = MessageReplyNode()
            rn.configure(ref: ref)
            let refId = "\(ref.messageRefID)"
            rn.onTapped = { interaction.onReplyTapped(refId) }
            replyNode = rn
            addSubnode(rn)
        } else if display.isDeletedReply {
            let drn = MessageDeletedReplyNode()
            deletedReplyNode = drn
            addSubnode(drn)
        }

        if let forwardLeftBarNode {
            addSubnode(forwardLeftBarNode)
        }
        if let forwardHeaderIconNode {
            addSubnode(forwardHeaderIconNode)
        }
        if let forwardHeaderLabelNode {
            addSubnode(forwardHeaderLabelNode)
        }

        if let callLog = display.callLog {
            let cln = MessageCallLogNode()
            cln.configure(callLog: callLog, isMe: display.isMe, senderName: display.senderDisplayName, contentText: parsed.text)
            callLogNode = cln
            addSubnode(cln)
        }

        if let topic = display.topicData {
            let tn = MessageTopicNode()
            tn.configure(topicData: topic)
            tn.onTapped = { interaction.onTopicTapped(topic) }
            topicNode = tn
            addSubnode(tn)
        }

        if hasContent {
            let tcn = MessageTextContentNode()
            tcn.configure(parsedContent: parsed, buzzStyled: display.isBuzzMessage)
            tcn.onMentionTapped = { interaction.onMentionTapped($0) }
            tcn.onHashtagTapped = { interaction.onHashtagTapped($0) }
            tcn.onLinkTapped = { UIApplication.shared.open($0) }
            textContentNode = tcn
            addSubnode(tcn)
        }

        if hasMedia {
            let mcn = MessageMediaContentNode()
            mcn.configure(media: mediaAttachments)
            mcn.onImageTapped = { [weak self] index in
                self?.handleImageTap(index: index, media: mediaAttachments, interaction: interaction)
            }
            mediaContentNode = mcn
            addSubnode(mcn)
        }

        if hasAudio {
            let an = MessageAudioAttachmentNode()
            an.configure(audio: audioAttachments, messageId: display.message.id)
            audioAttachmentNode = an
            addSubnode(an)
        }

        if hasFiles {
            let fan = MessageFileAttachmentNode()
            fan.configure(files: fileAttachments)
            fan.onFileTapped = { url in
                guard let fileURL = URL(string: url) else { return }
                UIApplication.shared.open(fileURL)
            }
            fileAttachmentNode = fan
            addSubnode(fan)
        }

        if hasEmbeds {
            let en = MessageEmbedNode()
            en.configure(embeds: parsed.embeds)
            embedNode = en
            addSubnode(en)
        }

        if hasLocation, let locData = display.locationData {
            let ln = MessageLocationNode()
            ln.configure(locationData: locData)
            locationNode = ln
            addSubnode(ln)
        }

        if showsReactionStrip {
            let rn = MessageReactionsNode()
            rn.configure(reactions: display.reactions, showAddButton: true)
            wireReactionNodeCallbacks(rn)
            reactionsNode = rn
            addSubnode(rn)
        }

        if display.isFailed {
            let etn = ASTextNode2()
            etn.attributedText = NSAttributedString(
                string: "Unable to send message",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                    .foregroundColor: UIColor.systemRed,
                ]
            )
            etn.maximumNumberOfLines = 1
            errorTextNode = etn
            addSubnode(etn)
        }

        self.isFailed = display.isFailed
    }

    func updateReactions(newDisplay: ChatMessageDisplay) {
        self.display = newDisplay

        let strip = Self.shouldShowReactionStrip(for: newDisplay)
        if !strip {
            reactionsNode?.removeFromSupernode()
            reactionsNode = nil
        } else if let existing = reactionsNode {
            existing.updateReactions(newDisplay.reactions, showAddButton: true)
            wireReactionNodeCallbacks(existing)
        } else {
            let rn = MessageReactionsNode()
            rn.configure(reactions: newDisplay.reactions, showAddButton: true)
            wireReactionNodeCallbacks(rn)
            reactionsNode = rn
            addSubnode(rn)
        }

        let _ = measureSize(width: cachedTotalSize.width)
        setNeedsLayout()
    }

    func updateDisplay(_ newDisplay: ChatMessageDisplay) {
        let oldFailed = self.isFailed
        self.display = newDisplay
        self.isFailed = newDisplay.isFailed

        syncReactionStripWithDisplay(newDisplay)

        if oldFailed && !newDisplay.isFailed {
            errorTextNode?.removeFromSupernode()
            errorTextNode = nil
        } else if !oldFailed && newDisplay.isFailed {
            let etn = ASTextNode2()
            etn.attributedText = NSAttributedString(
                string: "Unable to send message",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                    .foregroundColor: UIColor.systemRed,
                ]
            )
            etn.maximumNumberOfLines = 1
            errorTextNode = etn
            addSubnode(etn)
        }

        let contentAlpha: CGFloat = isFailed ? 0.6 : 1.0
        callLogNode?.alpha = contentAlpha
        topicNode?.alpha = contentAlpha
        textContentNode?.alpha = contentAlpha
        mediaContentNode?.alpha = contentAlpha
        audioAttachmentNode?.alpha = contentAlpha
        fileAttachmentNode?.alpha = contentAlpha
        embedNode?.alpha = contentAlpha
        locationNode?.alpha = contentAlpha
        forwardHeaderIconNode?.alpha = contentAlpha
        forwardHeaderLabelNode?.alpha = contentAlpha
        forwardLeftBarNode?.alpha = contentAlpha

        let _ = measureSize(width: cachedTotalSize.width)
        setNeedsLayout()
    }

    private func syncReactionStripWithDisplay(_ newDisplay: ChatMessageDisplay) {
        let strip = Self.shouldShowReactionStrip(for: newDisplay)
        if !strip {
            reactionsNode?.removeFromSupernode()
            reactionsNode = nil
            return
        }
        if let existing = reactionsNode {
            existing.updateReactions(newDisplay.reactions, showAddButton: true)
            wireReactionNodeCallbacks(existing)
        } else {
            let rn = MessageReactionsNode()
            rn.configure(reactions: newDisplay.reactions, showAddButton: true)
            wireReactionNodeCallbacks(rn)
            reactionsNode = rn
            addSubnode(rn)
        }
    }

    private func wireReactionNodeCallbacks(_ rn: MessageReactionsNode) {
        rn.onReactionTapped = { [weak self] reaction in
            guard let self else { return }
            interaction.onReactionTapped(reaction, self.display)
        }
        rn.onReactionLongPressed = { [weak self] reaction in
            guard let self else { return }
            interaction.onReactionDetailRequested(reaction, self.display)
        }
        rn.onAddReactionTapped = { [weak self] in
            guard let self else { return }
            interaction.onAddReactionTapped(self.display)
        }
        rn.onStripBackgroundLongPressed = { [weak self] in
            self?.handleLongPressOnReactionStripBackground()
        }
    }

    private func handleLongPressOnReactionStripBackground() {
        guard !hasCallLog, !hasLocation else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        interaction.onMessageLongPressed(display)
    }

    private func loadAvatar() {
        if let urlString = display.avatarURL, !urlString.isEmpty {
            avatarPlaceholderNode.isHidden = true
            let size = Self.avatarSize
            let args = TransformImageArguments(
                corners: ImageCorners(radius: size / 2),
                imageSize: CGSize(width: size, height: size),
                boundingSize: CGSize(width: size, height: size),
                intrinsicInsets: .zero
            )
            let proxyURL = ImgproxyURL.create(from: urlString, width: Int(size * UIScreen.main.scale), height: Int(size * UIScreen.main.scale))
            let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
            avatarImageNode.setSignal(remoteAvatarSignal(url: proxyURL), attemptSynchronously: hasMem)
            let avatarLayout = avatarImageNode.asyncLayout()
            let apply = avatarLayout(args)
            apply()
        } else {
            avatarPlaceholderNode.isHidden = false
        }
    }

    private func handleImageTap(index: Int, media: [ParsedAttachment], interaction: ChatInteraction) {
        let galleryItems: [GalleryItemInfo] = media.enumerated().map { (_, att) in
            GalleryItemInfo(
                url: att.url,
                image: nil,
                senderName: display.senderDisplayName,
                senderAvatarURL: display.avatarURL,
                timestamp: display.message.createdAt,
                isVideo: att.isVideo
            )
        }
        let gallery = GalleryController(items: galleryItems, initialIndex: index)
        if let vc = findViewController() {
            vc.present(gallery, animated: true)
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }

    private let highlightNode = ASDisplayNode()
    private let highlightBorderNode = ASDisplayNode()
    private let mentionHighlightNode = ASDisplayNode()
    private let mentionBorderNode = ASDisplayNode()

    override func didLoad() {
        super.didLoad()
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        longPress.delegate = self
        view.addGestureRecognizer(longPress)

        highlightNode.backgroundColor = UIColor.mezonBorder.withAlphaComponent(0.3)
        highlightNode.alpha = 0
        highlightNode.isUserInteractionEnabled = false
        addSubnode(highlightNode)

        highlightBorderNode.backgroundColor = .mezonLink
        highlightNode.addSubnode(highlightBorderNode)

        if !isCombine {
            avatarContainerNode.view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
            )
            nameNode.view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
            )
            nameNode.isUserInteractionEnabled = true
        }
    }

    @objc private func avatarTapped() {
        interaction.onAvatarTapped(display)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, !touchIsOnReactionsStrip(touch) else { return }
        showHighlight(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showHighlight(false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        showHighlight(false)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard !hasCallLog, !hasLocation else { return }
            if touchIsInsideReactions(gesture) { return }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            interaction.onMessageLongPressed(display)
        case .ended, .cancelled, .failed:
            break
        default:
            break
        }
    }

    private func touchIsInsideReactions(_ gesture: UIGestureRecognizer) -> Bool {
        guard let rn = reactionsNode, rn.isNodeLoaded else { return false }
        let p = gesture.location(in: rn.view)
        return rn.view.bounds.contains(p)
    }

    private func touchIsOnReactionsStrip(_ touch: UITouch) -> Bool {
        guard let rn = reactionsNode, rn.isNodeLoaded else { return false }
        let p = touch.location(in: view)
        let frameInBubble = rn.view.convert(rn.view.bounds, to: view)
        return frameInBubble.contains(p)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view === view, gestureRecognizer is UILongPressGestureRecognizer, touchIsInsideReactions(gestureRecognizer) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func showHighlight(_ show: Bool) {
        highlightNode.frame = bounds
        highlightBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)
        UIView.animate(withDuration: show ? 0.15 : 0.3) {
            self.highlightNode.alpha = show ? 1 : 0
        }
    }

    func dismissHighlight() {
        showHighlight(false)
    }

    func flashHighlight() {
        highlightNode.frame = bounds
        highlightBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)
        highlightNode.alpha = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showHighlight(false)
        }
    }


    func measureSize(width: CGFloat) -> CGSize {
        let contentLeadingTotal: CGFloat = 6.sw + Self.avatarSize + 10.sw
        let trailingInset: CGFloat = 12.sw
        let contentWidth = max(width - contentLeadingTotal - trailingInset, 1)
        let forwardInset: CGFloat = display.isForward ? (2 + 10.sw) : 0
        let bodyContentWidth = max(contentWidth - forwardInset, 1)
        let vertSpacing: CGFloat = 4.sh

        var totalH: CGFloat = 0

        if isCombine {
            totalH += 1.sh
        } else {
            totalH += 4.sh
        }

        if let replyNode {
            cachedReplySize = replyNode.measureSize(maxWidth: width)
            totalH += cachedReplySize.height
        } else if let deletedReplyNode {
            cachedReplySize = deletedReplyNode.measureSize(maxWidth: width)
            totalH += cachedReplySize.height + 2.sh
        } else {
            cachedReplySize = .zero
        }

        if !isCombine {
            cachedTimeSize = timeNode.measure(CGSize(width: contentWidth, height: 30))
            let nameMaxW = contentWidth - cachedTimeSize.width - 4.sw
            cachedNameSize = nameNode.measure(CGSize(width: max(nameMaxW, 50), height: 30))
            totalH += max(cachedNameSize.height, cachedTimeSize.height) + vertSpacing
        }

        if let lbl = forwardHeaderLabelNode {
            let iconW = Self.forwardHeaderIconSide + Self.forwardHeaderIconGap
            let labelMaxW = max(bodyContentWidth - iconW, 1)
            cachedForwardLabelSize = lbl.measure(CGSize(width: labelMaxW, height: .greatestFiniteMagnitude))
            let rowH = max(Self.forwardHeaderIconSide, cachedForwardLabelSize.height)
            cachedForwardHeaderSize = CGSize(
                width: min(iconW + cachedForwardLabelSize.width, bodyContentWidth),
                height: rowH
            )
            totalH += cachedForwardHeaderSize.height + vertSpacing
        } else {
            cachedForwardHeaderSize = .zero
            cachedForwardLabelSize = .zero
        }

        if let callLogNode {
            cachedCallLogSize = callLogNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedCallLogSize.height + vertSpacing
        } else {
            cachedCallLogSize = .zero
        }

        if let textContentNode {
            cachedTextSize = textContentNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedTextSize.height + vertSpacing
        } else {
            cachedTextSize = .zero
        }

        if let mediaContentNode {
            cachedMediaSize = mediaContentNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedMediaSize.height + vertSpacing
        } else {
            cachedMediaSize = .zero
        }

        if let audioAttachmentNode {
            cachedAudioSize = audioAttachmentNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedAudioSize.height + vertSpacing
        } else {
            cachedAudioSize = .zero
        }

        if let fileAttachmentNode {
            cachedFileSize = fileAttachmentNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedFileSize.height + vertSpacing
        } else {
            cachedFileSize = .zero
        }

        if let embedNode {
            cachedEmbedSize = embedNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedEmbedSize.height + vertSpacing
        } else {
            cachedEmbedSize = .zero
        }

        if let locationNode {
            cachedLocationSize = locationNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedLocationSize.height + vertSpacing
        } else {
            cachedLocationSize = .zero
        }

        if let reactionsNode {
            cachedReactionsSize = reactionsNode.measureSize(maxWidth: contentWidth)
            totalH += cachedReactionsSize.height + vertSpacing
        } else {
            cachedReactionsSize = .zero
        }

        if let topicNode {
            cachedTopicSize = topicNode.measureSize(maxWidth: bodyContentWidth)
            totalH += 8.sh + cachedTopicSize.height + vertSpacing
        } else {
            cachedTopicSize = .zero
        }

        if let errorTextNode {
            cachedErrorSize = errorTextNode.measure(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
            totalH += cachedErrorSize.height + vertSpacing
        } else {
            cachedErrorSize = .zero
        }

        totalH += 4.sh

        cachedTotalSize = CGSize(width: width, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let contentLeadingTotal: CGFloat = 6.sw + Self.avatarSize + 10.sw
        let combineLeading: CGFloat = 6.sw + Self.avatarSize + 10.sw
        let trailingInset: CGFloat = 12.sw
        let contentWidth = max(width - contentLeadingTotal - trailingInset, 1)
        let forwardInset: CGFloat = display.isForward ? (2 + 10.sw) : 0
        let bodyContentWidth = max(contentWidth - forwardInset, 1)
        let vertSpacing: CGFloat = 4.sh

        let contentX = isCombine ? combineLeading : contentLeadingTotal
        let contentInnerX = contentX + forwardInset
        var y: CGFloat = isCombine ? 1.sh : 4.sh
        var forwardBarMinY: CGFloat?
        var forwardBarMaxY: CGFloat?
        func noteForwardBlock(topY: CGFloat, height: CGFloat) {
            guard display.isForward, height > 0 else { return }
            let bottom = topY + height
            if forwardBarMinY == nil { forwardBarMinY = topY }
            forwardBarMaxY = max(forwardBarMaxY ?? bottom, bottom)
        }

        if let replyNode {
            replyNode.frame = CGRect(x: 6.sw, y: y, width: width - 6.sw - 12.sw, height: cachedReplySize.height)
            y += cachedReplySize.height
        } else if let deletedReplyNode {
            deletedReplyNode.frame = CGRect(x: 6.sw, y: y, width: width - 6.sw - 12.sw, height: cachedReplySize.height)
            y += cachedReplySize.height + 2.sh
        }

        if !isCombine {
            let avatarX: CGFloat = 6.sw
            let avatarSz = Self.avatarSize
            avatarContainerNode.frame = CGRect(x: avatarX, y: y, width: avatarSz, height: avatarSz)
            avatarImageNode.frame = CGRect(origin: .zero, size: CGSize(width: avatarSz, height: avatarSz))
            let phSize = avatarPlaceholderNode.measure(CGSize(width: avatarSz, height: avatarSz))
            avatarPlaceholderNode.frame = CGRect(
                x: (avatarSz - phSize.width) / 2,
                y: (avatarSz - phSize.height) / 2,
                width: phSize.width, height: phSize.height
            )

            nameNode.frame = CGRect(x: contentX, y: y, width: cachedNameSize.width, height: cachedNameSize.height)
            let timeX = contentX + cachedNameSize.width + 4.sw
            let nameRowH = max(cachedNameSize.height, cachedTimeSize.height)
            timeNode.frame = CGRect(x: timeX, y: y + nameRowH - cachedTimeSize.height, width: cachedTimeSize.width, height: cachedTimeSize.height)
            y += nameRowH + vertSpacing
        }

        if let icon = forwardHeaderIconNode, let lbl = forwardHeaderLabelNode {
            let rowH = cachedForwardHeaderSize.height
            let iconSide = Self.forwardHeaderIconSide
            let gap = Self.forwardHeaderIconGap
            let iconY = y + (rowH - iconSide) / 2
            icon.frame = CGRect(x: contentInnerX, y: iconY, width: iconSide, height: iconSide)
            let labelY = y + (rowH - cachedForwardLabelSize.height) / 2
            lbl.frame = CGRect(
                x: contentInnerX + iconSide + gap,
                y: labelY,
                width: cachedForwardLabelSize.width,
                height: cachedForwardLabelSize.height
            )
            noteForwardBlock(topY: y, height: rowH)
            y += rowH + vertSpacing
        }

        if let callLogNode {
            callLogNode.frame = CGRect(x: contentInnerX, y: y, width: bodyContentWidth, height: cachedCallLogSize.height)
            noteForwardBlock(topY: y, height: cachedCallLogSize.height)
            y += cachedCallLogSize.height + vertSpacing
        }

        if let textContentNode {
            textContentNode.frame = CGRect(x: contentInnerX, y: y, width: bodyContentWidth, height: cachedTextSize.height)
            noteForwardBlock(topY: y, height: cachedTextSize.height)
            y += cachedTextSize.height + vertSpacing
        }

        if let mediaContentNode {
            mediaContentNode.frame = CGRect(x: contentInnerX, y: y, width: cachedMediaSize.width, height: cachedMediaSize.height)
            noteForwardBlock(topY: y, height: cachedMediaSize.height)
            y += cachedMediaSize.height + vertSpacing
        }

        if let audioAttachmentNode {
            audioAttachmentNode.frame = CGRect(x: contentInnerX, y: y, width: cachedAudioSize.width, height: cachedAudioSize.height)
            noteForwardBlock(topY: y, height: cachedAudioSize.height)
            y += cachedAudioSize.height + vertSpacing
        }

        if let fileAttachmentNode {
            fileAttachmentNode.frame = CGRect(x: contentInnerX, y: y, width: cachedFileSize.width, height: cachedFileSize.height)
            noteForwardBlock(topY: y, height: cachedFileSize.height)
            y += cachedFileSize.height + vertSpacing
        }

        if let embedNode {
            embedNode.frame = CGRect(x: contentInnerX, y: y, width: cachedEmbedSize.width, height: cachedEmbedSize.height)
            noteForwardBlock(topY: y, height: cachedEmbedSize.height)
            y += cachedEmbedSize.height + vertSpacing
        }

        if let locationNode {
            locationNode.frame = CGRect(x: contentInnerX, y: y, width: cachedLocationSize.width, height: cachedLocationSize.height)
            noteForwardBlock(topY: y, height: cachedLocationSize.height)
            y += cachedLocationSize.height + vertSpacing
        }

        if let reactionsNode {
            reactionsNode.frame = CGRect(x: contentX, y: y, width: cachedReactionsSize.width, height: cachedReactionsSize.height)
            y += cachedReactionsSize.height + vertSpacing
        }

        if let topicNode {
            y += 8.sh
            topicNode.frame = CGRect(x: contentInnerX, y: y, width: cachedTopicSize.width, height: cachedTopicSize.height)
            noteForwardBlock(topY: y, height: cachedTopicSize.height)
            y += cachedTopicSize.height + vertSpacing
        }

        if let errorTextNode {
            errorTextNode.frame = CGRect(x: contentX, y: y, width: cachedErrorSize.width, height: cachedErrorSize.height)
            y += cachedErrorSize.height + vertSpacing
        }

        highlightNode.frame = bounds
        highlightBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)

        if display.hasIncludeMention {
            mentionHighlightNode.frame = bounds
            mentionBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)
        }

        if let bar = forwardLeftBarNode, let top = forwardBarMinY, let bottom = forwardBarMaxY, bottom > top {
            bar.frame = CGRect(x: contentX, y: top, width: 2, height: bottom - top)
            bar.isHidden = false
        } else {
            forwardLeftBarNode?.isHidden = true
        }

        let contentAlpha: CGFloat = isFailed ? 0.6 : 1.0
        callLogNode?.alpha = contentAlpha
        topicNode?.alpha = contentAlpha
        textContentNode?.alpha = contentAlpha
        mediaContentNode?.alpha = contentAlpha
        audioAttachmentNode?.alpha = contentAlpha
        fileAttachmentNode?.alpha = contentAlpha
        embedNode?.alpha = contentAlpha
        locationNode?.alpha = contentAlpha
        forwardHeaderIconNode?.alpha = contentAlpha
        forwardHeaderLabelNode?.alpha = contentAlpha
        forwardLeftBarNode?.alpha = contentAlpha
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy, HH:mm"
        return f
    }()

    private static func forwardHeaderLabelAttributedString() -> NSAttributedString {
        let t = UIColor.theme
        let fontSize: CGFloat = 12.sf
        let baseFont = UIFont.systemFont(ofSize: fontSize)
        let italicFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor, size: fontSize)
        return NSAttributedString(string: L(L10n.Common.forwarded), attributes: [
            .font: italicFont,
            .foregroundColor: t.textDisabled,
        ])
    }

    private static func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeStr = timeFormatter.string(from: date)
        if cal.isDateInToday(date) {
            return String(format: L(L10n.ChannelMessages.todayAt), timeStr)
        }
        if cal.isDateInYesterday(date) {
            return String(format: L(L10n.ChannelMessages.yesterdayAt), timeStr)
        }
        return fullFormatter.string(from: date)
    }

    private static func reactionStripAllowed(for display: ChatMessageDisplay) -> Bool {
        if display.isFailed { return false }
        if display.isSystemMessage { return false }
        if display.isCallLog { return false }
        if display.isTopic { return false }
        if display.message.isDeleted { return false }
        return true
    }

    private static func shouldShowReactionStrip(for display: ChatMessageDisplay) -> Bool {
        reactionStripAllowed(for: display) && !display.reactions.isEmpty
    }
}

extension MessageBubbleNode: UIGestureRecognizerDelegate {}
