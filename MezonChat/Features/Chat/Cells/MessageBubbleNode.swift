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
    private var clanInviteLinkNode: MessageClanInviteLinkNode?
    private var sendTokenLogNode: MessageSendTokenLogNode?
    private var pollCardNode: PollCardNode?
    private var errorTextNode: ASTextNode2?
    private var editedNode: ASTextNode2?
    private let ephemeralHighlightNode = ASDisplayNode()
    private let ephemeralBorderNode = ASDisplayNode()
    private let ephemeralIndicatorNode = ASDisplayNode()
    private let ephemeralIndicatorIconNode = ASImageNode()
    private let ephemeralIndicatorTextNode = ASTextNode2()

    private(set) var display: ChatMessageDisplay
    private let interaction: ChatInteraction
    private let isCombine: Bool
    private let hasCallLog: Bool
    private let hasPoll: Bool
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
    private static let anonymousIconWidth: CGFloat = 22.sf
    private static let anonymousIconHeight: CGFloat = 22.sf
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
    private var cachedClanInviteSize: CGSize = .zero
    private var cachedSendTokenLogSize: CGSize = .zero
    private var cachedPollSize: CGSize = .zero
    private var cachedErrorSize: CGSize = .zero
    private var cachedEditedSize: CGSize = .zero
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
        self.hasPoll = display.isPollMessage
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
        } else if display.isPollMessage {
            self.hasContent = false
            self.hasMedia = false
            self.hasAudio = false
            self.hasFiles = false
            self.hasEmbeds = false
            self.hasLocation = false
        } else if display.isSendTokenLog {
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
        } else if display.isEphemeral {
            ephemeralHighlightNode.backgroundColor = UIColor.theme.bgViolet.withAlphaComponent(0.1)
            ephemeralHighlightNode.isUserInteractionEnabled = false
            addSubnode(ephemeralHighlightNode)

            ephemeralBorderNode.backgroundColor = UIColor.theme.bgViolet
            ephemeralHighlightNode.addSubnode(ephemeralBorderNode)

            ephemeralIndicatorIconNode.image = UIImage(systemName: "eye.slash")?.withRenderingMode(.alwaysTemplate)
            ephemeralIndicatorIconNode.tintColor = UIColor.theme.textDisabled
            ephemeralIndicatorIconNode.contentMode = .scaleAspectFit
            ephemeralIndicatorNode.addSubnode(ephemeralIndicatorIconNode)

            ephemeralIndicatorTextNode.attributedText = NSAttributedString(
                string: L(L10n.Embed.onlyVisibleToRecipient),
                attributes: [
                    .font: UIFont.italicSystemFont(ofSize: 12.sf),
                    .foregroundColor: UIColor.theme.textDisabled
                ]
            )
            ephemeralIndicatorNode.addSubnode(ephemeralIndicatorTextNode)
            addSubnode(ephemeralIndicatorNode)
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

        timeNode.attributedText = NSAttributedString(
            string: Self.timeText(for: display),
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
            cln.configure(
                callLog: callLog,
                isMe: display.isMe,
                senderName: display.senderDisplayName,
                contentText: parsed.text,
                isGroupChat: interaction.isGroupDMChat()
            )
            cln.onCallBackTapped = { [weak self] in
                guard let self,
                      let callLog = self.display.callLog else { return }
                self.interaction.onCallLogCallBackTapped?(callLog)
            }
            callLogNode = cln
            addSubnode(cln)
        }

        if display.isPollMessage, let pollData = display.pollData {
            if let existing = self.pollCardNode {
                existing.updatePollData(pollData)
            } else {
                let pn = PollCardNode()
                pn.configure(pollData: pollData, messageId: display.id, channelId: display.message.channelId, myVoteIndices: [])
                pn.onVotePoll = { messageId, channelId, answerIndices, completion in
                    interaction.onVotePoll(messageId, channelId, answerIndices, completion)
                }
                pn.onOpenPollDetail = { messageId, channelId in
                    interaction.onOpenPollDetail(messageId, channelId)
                }
                pn.onLongPress = { [weak self] in
                    guard let self else { return }
                    interaction.onMessageLongPressed(self.display)
                }
                pn.onNeedsRelayout = { [weak self] in
                    guard let self else { return }
                    let _ = self.measureSize(width: self.cachedTotalSize.width)
                    self.setNeedsLayout()
                    interaction.onMessageNeedsRelayout?(self.display.id)
                }
                pollCardNode = pn
                addSubnode(pn)
            }
        } else {
            pollCardNode?.removeFromSupernode()
            pollCardNode = nil
        }

        if display.isSendTokenLog {
            let stn = MessageSendTokenLogNode()
            stn.configure(messageContent: parsed.text)
            stn.onTransactionTapped = { [weak self] in
                self?.handleSendTokenLogTapped()
            }
            sendTokenLogNode = stn
            addSubnode(stn)
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
            tcn.configure(
                parsedContent: parsed,
                buzzStyled: display.isBuzzMessage,
                hashtagChannelAccess: interaction.hashtagChannelIsAccessible
            )
            tcn.onMentionTapped = { interaction.onMentionTapped($0) }
            tcn.onHashtagTapped = { interaction.onHashtagTapped($0) }
            tcn.onLinkTapped = { url in
                let scheme = url.scheme?.lowercased() ?? ""
                guard scheme == "https" || scheme == "http" else { return }
                UIApplication.shared.open(url)
            }
            textContentNode = tcn
            addSubnode(tcn)
        }

        if Self.hasClanInviteCard(for: display), let code = display.clanInviteLinkCode {
            let n = MessageClanInviteLinkNode(inviteCode: code, interaction: interaction)
            clanInviteLinkNode = n
            addSubnode(n)
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
            fan.onFileTapped = { urlString in
                guard let fileURL = URL(string: urlString),
                      let scheme = fileURL.scheme?.lowercased(),
                      scheme == "https" || scheme == "http"
                else { return }
                UIApplication.shared.open(fileURL)
            }
            fileAttachmentNode = fan
            addSubnode(fan)
        }

        if hasEmbeds {
            let en = MessageEmbedNode()
            en.configure(embeds: parsed.embeds, messageId: display.id, isEphemeral: display.isEphemeral)
            en.isUserInteractionEnabled = true
            en.onEmbedImageTapped = { [weak self] url in
                self?.handleEmbedImageTap(url: url)
            }
            en.onEmbedButtonTapped = { [weak self] button, messageId in
                guard let self else { return }
                self.interaction.onEmbedButtonClicked?(button, messageId, self.display)
            }
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

        applyEditedNode(for: display)

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
        let oldDisplay = self.display
        let oldFailed = self.isFailed
        self.display = newDisplay
        self.isFailed = newDisplay.isFailed
        

        let t = UIColor.theme

        let nameChanged = oldDisplay.senderDisplayName != newDisplay.senderDisplayName
        let oldTimeText = Self.timeText(for: oldDisplay)
        let newTimeText = Self.timeText(for: newDisplay)
        let timeChanged = oldTimeText != newTimeText
        let textChanged = oldDisplay.parsedContent.text != newDisplay.parsedContent.text
            || oldDisplay.isBuzzMessage != newDisplay.isBuzzMessage
        let oldWantInvite = Self.hasClanInviteCard(for: oldDisplay)
        let newWantInvite = Self.hasClanInviteCard(for: newDisplay)
        let inviteChanged = oldDisplay.clanInviteLinkCode != newDisplay.clanInviteLinkCode
        let avatarChanged = oldDisplay.avatarURL != newDisplay.avatarURL
        let editedChanged = Self.shouldShowEditedLabel(for: oldDisplay) != Self.shouldShowEditedLabel(for: newDisplay)
        let mentionHighlightChanged = oldDisplay.hasIncludeMention != newDisplay.hasIncludeMention
        if mentionHighlightChanged {
            if newDisplay.hasIncludeMention {
                mentionHighlightNode.backgroundColor = UIColor(red: 201.0/255, green: 157.0/255, blue: 7.0/255, alpha: 0.1)
                mentionHighlightNode.isUserInteractionEnabled = false
                mentionBorderNode.backgroundColor = UIColor(red: 240.0/255, green: 177.0/255, blue: 50.0/255, alpha: 1.0)
                if mentionBorderNode.supernode !== mentionHighlightNode {
                    mentionHighlightNode.addSubnode(mentionBorderNode)
                }
                if mentionHighlightNode.supernode == nil {
                    insertSubnode(mentionHighlightNode, at: 0)
                }
            } else {
                mentionHighlightNode.removeFromSupernode()
            }
        }
        let callLogIdentityChanged: Bool = {
            switch (oldDisplay.callLog, newDisplay.callLog) {
            case (nil, nil): return false
            case (nil, _), (_, nil): return true
            case let (l?, r?):
                return l.callLogType != r.callLogType || l.isVideo != r.isVideo
            }
        }()
        let callLogChanged = callLogIdentityChanged
            || oldDisplay.isMe != newDisplay.isMe
            || nameChanged
            || textChanged

        if !isCombine {
            if nameChanged {
                avatarPlaceholderNode.attributedText = NSAttributedString(
                    string: String(newDisplay.senderDisplayName.prefix(1)).uppercased(),
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                        .foregroundColor: UIColor.white,
                    ]
                )
                nameNode.attributedText = NSAttributedString(
                    string: newDisplay.senderDisplayName,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                        .foregroundColor: t.textRoleLink,
                    ]
                )
            }
            if timeChanged {
                timeNode.attributedText = NSAttributedString(
                    string: newTimeText,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 12.sf),
                        .foregroundColor: t.textDisabled,
                    ]
                )
            }
        }

        if !newWantInvite {
            clanInviteLinkNode?.removeFromSupernode()
            clanInviteLinkNode = nil
        } else if !oldWantInvite && newWantInvite, let code = newDisplay.clanInviteLinkCode {
            let n = MessageClanInviteLinkNode(inviteCode: code, interaction: interaction)
            clanInviteLinkNode = n
            addSubnode(n)
        } else if newWantInvite && inviteChanged, let code = newDisplay.clanInviteLinkCode {
            clanInviteLinkNode?.removeFromSupernode()
            let n = MessageClanInviteLinkNode(inviteCode: code, interaction: interaction)
            clanInviteLinkNode = n
            addSubnode(n)
        }

        if Self.shouldShowTextContent(for: newDisplay) {
            if let tcn = textContentNode {
                if textChanged || mentionHighlightChanged {
                    tcn.configure(
                        parsedContent: newDisplay.parsedContent,
                        buzzStyled: newDisplay.isBuzzMessage,
                        hashtagChannelAccess: interaction.hashtagChannelIsAccessible
                    )
                }
            } else {
                let tcn = MessageTextContentNode()
                tcn.configure(
                    parsedContent: newDisplay.parsedContent,
                    buzzStyled: newDisplay.isBuzzMessage,
                    hashtagChannelAccess: interaction.hashtagChannelIsAccessible
                )
                tcn.onMentionTapped = { self.interaction.onMentionTapped($0) }
                tcn.onHashtagTapped = { self.interaction.onHashtagTapped($0) }
                tcn.onLinkTapped = { url in
                    let scheme = url.scheme?.lowercased() ?? ""
                    guard scheme == "https" || scheme == "http" else { return }
                    UIApplication.shared.open(url)
                }
                textContentNode = tcn
                if let c = clanInviteLinkNode { insertSubnode(tcn, belowSubnode: c) }
                else if let m = mediaContentNode { insertSubnode(tcn, belowSubnode: m) }
                else { addSubnode(tcn) }
            }
        } else {
            if let tcn = textContentNode {
                tcn.removeFromSupernode()
                textContentNode = nil
            }
        }
        if callLogChanged, let cln = callLogNode, let callLog = newDisplay.callLog {
            cln.configure(
                callLog: callLog,
                isMe: newDisplay.isMe,
                senderName: newDisplay.senderDisplayName,
                contentText: newDisplay.parsedContent.text,
                isGroupChat: interaction.isGroupDMChat()
            )
        }

        if editedChanged {
            applyEditedNode(for: newDisplay)
        }

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

        if newDisplay.isPollMessage, let pn = pollCardNode, let newPollData = newDisplay.pollData {
            let pollChanged = oldDisplay.pollData?.totalVotes != newPollData.totalVotes
                || oldDisplay.pollData?.answerCounts != newPollData.answerCounts
                || oldDisplay.pollData?.isClosed != newPollData.isClosed
            if pollChanged {
                pn.updatePollData(newPollData)
            }
        }

        let embedChanged = oldDisplay.parsedContent.embeds != newDisplay.parsedContent.embeds
        if embedChanged {
            embedNode?.removeFromSupernode()
            embedNode = nil
            let newParsed = newDisplay.parsedContent
            if !newParsed.embeds.isEmpty {
                let en = MessageEmbedNode()
                en.configure(embeds: newParsed.embeds, messageId: newDisplay.id, isEphemeral: newDisplay.isEphemeral)
                en.isUserInteractionEnabled = true
                en.onEmbedImageTapped = { [weak self] url in
                    self?.handleEmbedImageTap(url: url)
                }
                en.onEmbedButtonTapped = { [weak self] button, messageId in
                    guard let self else { return }
                    self.interaction.onEmbedButtonClicked?(button, messageId, self.display)
                }
                embedNode = en
                addSubnode(en)
            }
        }

        let contentAlpha: CGFloat = isFailed ? 0.6 : 1.0
        callLogNode?.alpha = contentAlpha
        pollCardNode?.alpha = contentAlpha
        topicNode?.alpha = contentAlpha
        textContentNode?.alpha = contentAlpha
        mediaContentNode?.alpha = contentAlpha
        audioAttachmentNode?.alpha = contentAlpha
        fileAttachmentNode?.alpha = contentAlpha
        embedNode?.alpha = contentAlpha
        locationNode?.alpha = contentAlpha
        clanInviteLinkNode?.alpha = contentAlpha
        forwardHeaderIconNode?.alpha = contentAlpha
        forwardHeaderLabelNode?.alpha = contentAlpha
        forwardLeftBarNode?.alpha = contentAlpha

        let needsRelayout = nameChanged || timeChanged || textChanged || callLogChanged
            || editedChanged
            || mentionHighlightChanged
            || (oldFailed != newDisplay.isFailed)
            || inviteChanged || (oldWantInvite != newWantInvite)
            || (Self.shouldShowTextContent(for: newDisplay) != (textContentNode != nil))
            || embedChanged
        if needsRelayout {
            let _ = measureSize(width: cachedTotalSize.width)
            setNeedsLayout()
        }
        if !isCombine && avatarChanged {
            loadAvatar()
        }
    }

    private static func shouldShowTextContent(for display: ChatMessageDisplay) -> Bool {
        if display.isCallLog { return false }
        if display.isLocation { return false }
        if display.isPollMessage { return false }
        if display.isSendTokenLog { return false }
        if display.checkOneLinkImage { return false }
        return !display.parsedContent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func timeText(for display: ChatMessageDisplay) -> String {
        return formatDate(display.message.createdAt)
    }

    private static func editedAttributedString() -> NSAttributedString {
        let t = UIColor.theme
        let baseFont = UIFont.systemFont(ofSize: 11.sf)
        let italicFont = UIFont(
            descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor,
            size: 11.sf
        )
        return NSAttributedString(
            string: L(L10n.MessageAction.editedSuffix),
            attributes: [
                .font: italicFont,
                .foregroundColor: t.textDisabled,
            ]
        )
    }

    private static func shouldShowEditedLabel(for display: ChatMessageDisplay) -> Bool {
        guard display.message.editedAt != nil else { return false }
        if display.message.isDeleted { return false }
        if display.isCallLog { return false }
        if display.isPollMessage { return false }
        if display.isSystemMessage { return false }
        return true
    }

    private func applyEditedNode(for display: ChatMessageDisplay) {
        let shouldShow = Self.shouldShowEditedLabel(for: display)
        if shouldShow {
            if editedNode == nil {
                let n = ASTextNode2()
                n.maximumNumberOfLines = 1
                n.attributedText = Self.editedAttributedString()
                editedNode = n
                addSubnode(n)
            } else {
                editedNode?.attributedText = Self.editedAttributedString()
            }
        } else {
            editedNode?.removeFromSupernode()
            editedNode = nil
        }
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

    private static func anonymousAvatarCompositeImage(raw: UIImage, tint: UIColor) -> UIImage {
        let tinted = raw.withRenderingMode(.alwaysTemplate)
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        let iconMax = CGSize(width: anonymousIconWidth, height: anonymousIconHeight)
        let canvas = CGSize(width: avatarSize, height: avatarSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let tw = max(tinted.size.width, 1)
            let th = max(tinted.size.height, 1)
            let scale = min(iconMax.width / tw, iconMax.height / th)
            let drawSize = CGSize(width: tw * scale, height: th * scale)
            let origin = CGPoint(
                x: (canvas.width - drawSize.width) / 2,
                y: (canvas.height - drawSize.height) / 2
            )
            tinted.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private func loadAvatar() {
        let size = Self.avatarSize
        let args = TransformImageArguments(
            corners: ImageCorners(radius: size / 2),
            imageSize: CGSize(width: size, height: size),
            boundingSize: CGSize(width: size, height: size),
            intrinsicInsets: .zero
        )
        if display.isAnonymousSender {
            if let raw = UIImage(named: "Chat/AnonymousIcon") {
                avatarPlaceholderNode.isHidden = true
                let img = Self.anonymousAvatarCompositeImage(
                    raw: raw,
                    tint: UIColor.theme.textStrong
                )
                avatarImageNode.reset()
                avatarImageNode.setSignal(staticImageSignal(image: img, resizeMode: .fill), attemptSynchronously: true)
                let avatarLayout = avatarImageNode.asyncLayout()
                let apply = avatarLayout(args)
                apply()
            } else {
                avatarImageNode.reset()
                avatarPlaceholderNode.isHidden = false
            }
            return
        }
        if let urlString = display.avatarURL, !urlString.isEmpty {
            avatarPlaceholderNode.isHidden = true
            let proxyURL = ImgproxyURL.create(from: urlString, width: 100, height: 100)
            let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
                || ImageCache.shared.memoryImage(forKey: urlString) != nil
            avatarImageNode.reset()
            avatarImageNode.setSignal(remoteAvatarSignal(proxiedURL: proxyURL, originalURL: urlString), attemptSynchronously: hasMem)
            let avatarLayout = avatarImageNode.asyncLayout()
            let apply = avatarLayout(args)
            apply()
        } else {
            avatarImageNode.reset()
            avatarPlaceholderNode.isHidden = false
        }
    }

    private func handleImageTap(index: Int, media: [ParsedAttachment], interaction: ChatInteraction) {
        let galleryItems: [GalleryItemInfo] = media.enumerated().map { (_, att) in
            let placeholderURL: String? = att.isVideo
                ? nil
                : ImgproxyURL.attachmentURL(
                    from: att.url,
                    width: 400,
                    height: 400,
                    resizeType: "fit"
                )
            return GalleryItemInfo(
                url: att.url,
                image: nil,
                placeholderURL: placeholderURL,
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

    private func handleSendTokenLogTapped() {
        interaction.onSendTokenLogTapped()
    }

    private func handleEmbedImageTap(url: String) {
        let placeholderURL = ImgproxyURL.attachmentURL(
            from: url,
            width: EmbedItemNode.embedImageProxyDimension,
            height: EmbedItemNode.embedImageProxyDimension
        )
        let galleryItems: [GalleryItemInfo] = [
            GalleryItemInfo(
                url: url,
                image: nil,
                placeholderURL: placeholderURL,
                senderName: display.senderDisplayName,
                senderAvatarURL: display.avatarURL,
                timestamp: display.message.createdAt,
                isVideo: false
            ),
        ]
        let gallery = GalleryController(items: galleryItems, initialIndex: 0)
        if let vc = findViewController() {
            vc.present(gallery, animated: true)
        }
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
        if touchIsInsidePollCard(touch) { return }
        showHighlight(true)
    }

    private func touchIsInsidePollCard(_ touch: UITouch) -> Bool {
        guard let pn = pollCardNode, pn.isNodeLoaded else { return false }
        let p = touch.location(in: view)
        let frameInBubble = pn.view.convert(pn.view.bounds, to: view)
        return frameInBubble.contains(p)
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

        if let pollCardNode {
            cachedPollSize = pollCardNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedPollSize.height + vertSpacing
        } else {
            cachedPollSize = .zero
        }

        if let sendTokenLogNode {
            cachedSendTokenLogSize = sendTokenLogNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedSendTokenLogSize.height + vertSpacing
        } else {
            cachedSendTokenLogSize = .zero
        }

        if let textContentNode {
            cachedTextSize = textContentNode.measureSize(maxWidth: bodyContentWidth)
            totalH += cachedTextSize.height + vertSpacing
        } else {
            cachedTextSize = .zero
        }

        if Self.hasClanInviteCard(for: display) {
            cachedClanInviteSize = CGSize(
                width: bodyContentWidth,
                height: MessageClanInviteLinkNode.preferredHeight
            )
            totalH += cachedClanInviteSize.height + vertSpacing
        } else {
            cachedClanInviteSize = .zero
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

        if let editedNode {
            cachedEditedSize = editedNode.measure(CGSize(width: bodyContentWidth, height: 30))
            totalH += cachedEditedSize.height + 2.sh
        } else {
            cachedEditedSize = .zero
        }

        if display.isEphemeral {
            let indicatorIconW: CGFloat = 12.sf
            let indicatorGap: CGFloat = 4.sw
            let indicatorMaxW = bodyContentWidth - indicatorIconW - indicatorGap
            let indicatorTextSize = ephemeralIndicatorTextNode.measure(CGSize(width: indicatorMaxW, height: .greatestFiniteMagnitude))
            totalH += max(12.sf, indicatorTextSize.height) + 4.sh
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
        var y: CGFloat = isCombine ? 1.sh : 6.sh
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

        if let pollCardNode {
            pollCardNode.frame = CGRect(x: contentInnerX, y: y, width: bodyContentWidth, height: cachedPollSize.height)
            noteForwardBlock(topY: y, height: cachedPollSize.height)
            y += cachedPollSize.height + vertSpacing
        }

        if let sendTokenLogNode {
            sendTokenLogNode.frame = CGRect(x: contentInnerX, y: y, width: cachedSendTokenLogSize.width, height: cachedSendTokenLogSize.height)
            noteForwardBlock(topY: y, height: cachedSendTokenLogSize.height)
            y += cachedSendTokenLogSize.height + vertSpacing
        }

        if let textContentNode {
            textContentNode.frame = CGRect(x: contentInnerX, y: y, width: bodyContentWidth, height: cachedTextSize.height)
            noteForwardBlock(topY: y, height: cachedTextSize.height)
            y += cachedTextSize.height + vertSpacing
        }

        if let clanInviteLinkNode {
            clanInviteLinkNode.frame = CGRect(
                x: contentInnerX,
                y: y,
                width: bodyContentWidth,
                height: cachedClanInviteSize.height
            )
            noteForwardBlock(topY: y, height: cachedClanInviteSize.height)
            y += cachedClanInviteSize.height + vertSpacing
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

        if let editedNode {
            editedNode.frame = CGRect(
                x: contentInnerX,
                y: y,
                width: cachedEditedSize.width,
                height: cachedEditedSize.height
            )
            y += cachedEditedSize.height + 2.sh
        }

        highlightNode.frame = bounds
        highlightBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)

        if display.hasIncludeMention {
            mentionHighlightNode.frame = bounds
            mentionBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)
        } else if display.isEphemeral {
            ephemeralHighlightNode.frame = bounds
            ephemeralBorderNode.frame = CGRect(x: 0, y: 0, width: 2, height: bounds.height)

            let indicatorIconW: CGFloat = 12.sf
            let indicatorGap: CGFloat = 4.sw
            let indicatorMaxW = bodyContentWidth - indicatorIconW - indicatorGap
            let indicatorTextSize = ephemeralIndicatorTextNode.measure(CGSize(width: indicatorMaxW, height: .greatestFiniteMagnitude))
            let indicatorH = max(12.sf, indicatorTextSize.height)

            ephemeralIndicatorNode.frame = CGRect(x: contentInnerX, y: y, width: bodyContentWidth, height: indicatorH)
            ephemeralIndicatorIconNode.frame = CGRect(x: 0, y: (indicatorH - 12.sf) / 2, width: 12.sf, height: 12.sf)
            ephemeralIndicatorTextNode.frame = CGRect(x: indicatorIconW + indicatorGap, y: (indicatorH - indicatorTextSize.height) / 2, width: indicatorTextSize.width, height: indicatorTextSize.height)
            
            y += indicatorH + 4.sh
        }

        if let bar = forwardLeftBarNode, let top = forwardBarMinY, let bottom = forwardBarMaxY, bottom > top {
            bar.frame = CGRect(x: contentX, y: top, width: 2, height: bottom - top)
            bar.isHidden = false
        } else {
            forwardLeftBarNode?.isHidden = true
        }

        let contentAlpha: CGFloat = isFailed ? 0.6 : 1.0
        callLogNode?.alpha = contentAlpha
        pollCardNode?.alpha = contentAlpha
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
        clanInviteLinkNode?.alpha = contentAlpha
    }

    private static func hasClanInviteCard(for display: ChatMessageDisplay) -> Bool {
        guard let code = display.clanInviteLinkCode, !code.isEmpty else { return false }
        return !display.isCallLog && !display.isLocation && !display.isPollMessage
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

    private static func pollUnsupportedAttributedString() -> NSAttributedString {
        let t = UIColor.theme
        let line1 = L(L10n.ChannelMessages.pollUnsupported)
        let line2 = L(L10n.ChannelMessages.pollComingSoon)
        let full = line1 + "\n" + line2
        let s = NSMutableAttributedString(string: full)
        let fullNS = full as NSString
        s.addAttributes([
            .font: UIFont.systemFont(ofSize: 14.sf),
            .foregroundColor: t.text,
        ], range: NSRange(location: 0, length: fullNS.length))
        let line1NS = line1 as NSString
        let line2NS = line2 as NSString
        let second = NSRange(location: line1NS.length + 1, length: line2NS.length)
        if second.location + second.length <= fullNS.length {
            s.addAttributes([
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .medium),
                .foregroundColor: t.textDisabled,
            ], range: second)
        }
        return s
    }

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
        if display.isPollMessage { return false }
        if display.isTopic { return false }
        if display.message.isDeleted { return false }
        return true
    }

    private static func shouldShowReactionStrip(for display: ChatMessageDisplay) -> Bool {
        reactionStripAllowed(for: display) && !display.reactions.isEmpty
    }
}

extension MessageBubbleNode: UIGestureRecognizerDelegate {}
