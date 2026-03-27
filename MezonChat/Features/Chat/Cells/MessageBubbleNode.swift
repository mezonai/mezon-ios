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
    private var fileAttachmentNode: MessageFileAttachmentNode?
    private var embedNode: MessageEmbedNode?
    private var reactionsNode: MessageReactionsNode?
    private var errorTextNode: ASTextNode2?

    private(set) var display: ChatMessageDisplay
    private let interaction: ChatInteraction
    private let isCombine: Bool
    private let hasCallLog: Bool
    private let hasTopic: Bool
    private let hasContent: Bool
    private let hasMedia: Bool
    private let hasFiles: Bool
    private let hasEmbeds: Bool
    private let hasReactions: Bool
    private let hasReply: Bool
    private let hasDeletedReply: Bool
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
    private var cachedFileSize: CGSize = .zero
    private var cachedEmbedSize: CGSize = .zero
    private var cachedReactionsSize: CGSize = .zero
    private var cachedErrorSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

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
        let fileAttachments = display.attachments.filter { !$0.isMedia && !$0.url.isEmpty }

        if display.isCallLog {
            self.hasContent = false
            self.hasMedia = false
            self.hasFiles = false
            self.hasEmbeds = false
        } else {
            if display.checkOneLinkImage {
                self.hasContent = false
            } else {
                self.hasContent = !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            self.hasMedia = !mediaAttachments.isEmpty
            self.hasFiles = !fileAttachments.isEmpty
            self.hasEmbeds = !parsed.embeds.isEmpty
        }
        self.hasReactions = !display.reactions.isEmpty

        super.init()
        backgroundColor = .clear

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
            tcn.configure(parsedContent: parsed)
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

        if hasReactions {
            let rn = MessageReactionsNode()
            rn.configure(reactions: display.reactions)
            rn.onReactionTapped = { [weak self] reaction in
                guard let self else { return }
                interaction.onReactionTapped(reaction, self.display)
            }
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

        if newDisplay.reactions.isEmpty {
            reactionsNode?.removeFromSupernode()
            reactionsNode = nil
        } else if let existing = reactionsNode {
            existing.updateReactions(newDisplay.reactions)
        } else {
            let rn = MessageReactionsNode()
            rn.configure(reactions: newDisplay.reactions)
            rn.onReactionTapped = { [weak self] reaction in
                guard let self else { return }
                self.interaction.onReactionTapped(reaction, self.display)
            }
            reactionsNode = rn
            addSubnode(rn)
        }

        let _ = measureSize(width: cachedTotalSize.width)
        setNeedsLayout()
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
            avatarImageNode.setSignal(remoteImageSignal(url: proxyURL, resizeMode: .fill), attemptSynchronously: false)
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

    override func didLoad() {
        super.didLoad()
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
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
            guard !hasCallLog else { return }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            interaction.onMessageLongPressed(display)
        case .ended, .cancelled, .failed:
            break
        default:
            break
        }
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
        let vertSpacing: CGFloat = 4.sh

        var totalH: CGFloat = 0

        if isCombine {
            totalH += 1.sh
        } else {
            totalH += 6.sh
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

        if let callLogNode {
            cachedCallLogSize = callLogNode.measureSize(maxWidth: contentWidth)
            totalH += cachedCallLogSize.height + vertSpacing
        } else {
            cachedCallLogSize = .zero
        }

        if let textContentNode {
            cachedTextSize = textContentNode.measureSize(maxWidth: contentWidth)
            totalH += cachedTextSize.height + vertSpacing
        } else {
            cachedTextSize = .zero
        }

        if let mediaContentNode {
            cachedMediaSize = mediaContentNode.measureSize(maxWidth: contentWidth)
            totalH += cachedMediaSize.height + vertSpacing
        } else {
            cachedMediaSize = .zero
        }

        if let fileAttachmentNode {
            cachedFileSize = fileAttachmentNode.measureSize(maxWidth: contentWidth)
            totalH += cachedFileSize.height + vertSpacing
        } else {
            cachedFileSize = .zero
        }

        if let embedNode {
            cachedEmbedSize = embedNode.measureSize(maxWidth: contentWidth)
            totalH += cachedEmbedSize.height + vertSpacing
        } else {
            cachedEmbedSize = .zero
        }

        if let reactionsNode {
            cachedReactionsSize = reactionsNode.measureSize(maxWidth: contentWidth)
            totalH += cachedReactionsSize.height + vertSpacing
        } else {
            cachedReactionsSize = .zero
        }

        if let topicNode {
            cachedTopicSize = topicNode.measureSize(maxWidth: contentWidth)
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
        let vertSpacing: CGFloat = 4.sh

        let contentX = isCombine ? combineLeading : contentLeadingTotal
        var y: CGFloat = isCombine ? 1.sh : 6.sh

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

        if let callLogNode {
            callLogNode.frame = CGRect(x: contentX, y: y, width: contentWidth, height: cachedCallLogSize.height)
            y += cachedCallLogSize.height + vertSpacing
        }

        if let textContentNode {
            textContentNode.frame = CGRect(x: contentX, y: y, width: contentWidth, height: cachedTextSize.height)
            y += cachedTextSize.height + vertSpacing
        }

        if let mediaContentNode {
            mediaContentNode.frame = CGRect(x: contentX, y: y, width: cachedMediaSize.width, height: cachedMediaSize.height)
            y += cachedMediaSize.height + vertSpacing
        }

        if let fileAttachmentNode {
            fileAttachmentNode.frame = CGRect(x: contentX, y: y, width: cachedFileSize.width, height: cachedFileSize.height)
            y += cachedFileSize.height + vertSpacing
        }

        if let embedNode {
            embedNode.frame = CGRect(x: contentX, y: y, width: cachedEmbedSize.width, height: cachedEmbedSize.height)
            y += cachedEmbedSize.height + vertSpacing
        }

        if let reactionsNode {
            reactionsNode.frame = CGRect(x: contentX, y: y, width: cachedReactionsSize.width, height: cachedReactionsSize.height)
            y += cachedReactionsSize.height + vertSpacing
        }

        if let topicNode {
            y += 8.sh
            topicNode.frame = CGRect(x: contentX, y: y, width: cachedTopicSize.width, height: cachedTopicSize.height)
            y += cachedTopicSize.height + vertSpacing
        }

        if let errorTextNode {
            errorTextNode.frame = CGRect(x: contentX, y: y, width: cachedErrorSize.width, height: cachedErrorSize.height)
            y += cachedErrorSize.height + vertSpacing
        }

        highlightNode.frame = bounds
        highlightBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)

        let contentAlpha: CGFloat = isFailed ? 0.6 : 1.0
        callLogNode?.alpha = contentAlpha
        topicNode?.alpha = contentAlpha
        textContentNode?.alpha = contentAlpha
        mediaContentNode?.alpha = contentAlpha
        fileAttachmentNode?.alpha = contentAlpha
        embedNode?.alpha = contentAlpha
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
}
