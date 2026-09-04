import SwiftProtobuf
import UIKit
import CoreLocation
import QuartzCore
import Photos

enum ActiveChannelTracker {
    private static let lock = NSLock()
    private static var _channelId: Int64 = 0

    static var currentChannelId: Int64 {
        get { lock.lock(); defer { lock.unlock() }; return _channelId }
        set { lock.lock(); defer { lock.unlock() }; _channelId = newValue }
    }
}

struct ParsedAttachment: Equatable {
    let url: String
    let filename: String
    let filetype: String
    let width: Int?
    let height: Int?
    let durationSeconds: Int?
    var thumbnail: String = ""
    var localImage: UIImage?
    var isUploading: Bool = false
    var uploadFailed: Bool = false
    var isPresignPending: Bool = false
    var uploadProgress: Double = 0
    var uploadProgressKey: String = ""
    var uploadShowsPercent: Bool = false

    var isImage: Bool {
        AttachmentTypeClassifier.isImage(filetype) || AttachmentTypeClassifier.isSticker(filetype)
            || ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(fileExtension)
            || ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(urlExtension)
    }

    var isVideo: Bool {
        AttachmentTypeClassifier.isVideo(filetype)
            || ["mp4", "mov", "m4v", "webm", "mkv", "avi", "flv", "wmv", "ogv", "ogg", "3gp", "3g2", "mpg", "mpeg", "ts", "vob"].contains(fileExtension)
            || ["mp4", "mov", "m4v", "webm", "mkv", "avi", "flv", "wmv", "ogv", "ogg", "3gp", "3g2", "mpg", "mpeg", "ts", "vob"].contains(urlExtension)
    }

    var isSticker: Bool { AttachmentTypeClassifier.isSticker(filetype) }

    var isMedia: Bool { isImage || isVideo }

    var isAudio: Bool {
        if AttachmentTypeClassifier.isAudio(filetype) { return true }
        return ["mp3", "m4a", "aac", "wav", "ogg", "flac", "opus"].contains(fileExtension)
            || ["mp3", "m4a", "aac", "wav", "ogg", "flac", "opus"].contains(urlExtension)
    }

    var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }

    var urlExtension: String {
        guard let urlPath = URL(string: url)?.pathExtension else { return "" }
        return urlPath.lowercased()
    }

    static func ==(lhs: ParsedAttachment, rhs: ParsedAttachment) -> Bool {
        lhs.url == rhs.url && lhs.filename == rhs.filename && lhs.filetype == rhs.filetype
            && lhs.width == rhs.width && lhs.height == rhs.height && lhs.durationSeconds == rhs.durationSeconds
            && lhs.thumbnail == rhs.thumbnail
            && lhs.isUploading == rhs.isUploading && lhs.uploadFailed == rhs.uploadFailed
            && lhs.isPresignPending == rhs.isPresignPending
            && lhs.uploadProgress == rhs.uploadProgress
    }

    static func attachmentsStructurallyEqual(_ lhs: [ParsedAttachment], _ rhs: [ParsedAttachment]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if l.url != r.url || l.filename != r.filename || l.filetype != r.filetype
                || l.width != r.width || l.height != r.height || l.durationSeconds != r.durationSeconds
                || l.thumbnail != r.thumbnail
                || l.isUploading != r.isUploading || l.uploadFailed != r.uploadFailed
                || l.isPresignPending != r.isPresignPending {
                return false
            }
        }
        return true
    }

    static func attachmentsRequireBubbleRebuild(_ lhs: [ParsedAttachment], _ rhs: [ParsedAttachment]) -> Bool {
        guard lhs.count == rhs.count else { return true }
        for (l, r) in zip(lhs, rhs) {
            if l.width != r.width || l.height != r.height || l.durationSeconds != r.durationSeconds {
                return true
            }
        }
        return false
    }

    static func attachmentsUploadStateEqual(_ lhs: [ParsedAttachment], _ rhs: [ParsedAttachment]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if l.isUploading != r.isUploading || l.uploadFailed != r.uploadFailed
                || l.isPresignPending != r.isPresignPending {
                return false
            }
        }
        return true
    }

    static func attachmentsIdentityEqual(_ lhs: [ParsedAttachment], _ rhs: [ParsedAttachment]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if l.url != r.url || l.filename != r.filename || l.filetype != r.filetype || l.thumbnail != r.thumbnail {
                return false
            }
        }
        return true
    }

    static func attachmentsDimensionsEqual(_ lhs: [ParsedAttachment], _ rhs: [ParsedAttachment]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if l.width != r.width || l.height != r.height || l.durationSeconds != r.durationSeconds {
                return false
            }
        }
        return true
    }

    static func slotPresentationEqual(_ lhs: ParsedAttachment, _ rhs: ParsedAttachment) -> Bool {
        lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.isPresignPending == rhs.isPresignPending
            && lhs.isUploading == rhs.isUploading
            && lhs.uploadFailed == rhs.uploadFailed
            && (lhs.localImage == nil) == (rhs.localImage == nil)
            && (!lhs.isUploading || !rhs.isUploading || lhs.uploadProgress == rhs.uploadProgress)
    }

    private static let maxPendingCacheEntries = 50
    private static let pendingCacheLock = NSLock()

    private static var _pendingImageCache: [String: [UIImage]] = [:]
    static var pendingImageCache: [String: [UIImage]] {
        get {
            pendingCacheLock.lock()
            defer { pendingCacheLock.unlock() }
            return _pendingImageCache
        }
        set {
            pendingCacheLock.lock()
            defer { pendingCacheLock.unlock() }
            _pendingImageCache = newValue
            if _pendingImageCache.count > maxPendingCacheEntries {
                let keysToRemove = _pendingImageCache.keys.prefix(_pendingImageCache.count - maxPendingCacheEntries)
                keysToRemove.forEach { _pendingImageCache.removeValue(forKey: $0) }
            }
        }
    }

    private static var _pendingDocumentPlaceholders: [String: [ParsedAttachment]] = [:]
    static var pendingDocumentPlaceholders: [String: [ParsedAttachment]] {
        get {
            pendingCacheLock.lock()
            defer { pendingCacheLock.unlock() }
            return _pendingDocumentPlaceholders
        }
        set {
            pendingCacheLock.lock()
            defer { pendingCacheLock.unlock() }
            _pendingDocumentPlaceholders = newValue
            if _pendingDocumentPlaceholders.count > maxPendingCacheEntries {
                let keysToRemove = _pendingDocumentPlaceholders.keys.prefix(_pendingDocumentPlaceholders.count - maxPendingCacheEntries)
                keysToRemove.forEach { _pendingDocumentPlaceholders.removeValue(forKey: $0) }
            }
        }
    }
}

struct ParsedReactionSender: Equatable {
    let userId: String
    let count: Int
    let nameHint: String?
}

struct ParsedReaction: Equatable {
    let emojiId: String
    let emoji: String
    let count: Int
    let senders: [ParsedReactionSender]
    let isMe: Bool

    var senderIds: [String] { senders.map(\.userId) }
}

enum CallLogType: Int {
    case startCall = 1
    case timeoutCall = 2
    case finishCall = 3
    case rejectCall = 4
    case cancelCall = 5
}

struct CallLogData {
    let callLogType: CallLogType
    let isVideo: Bool
}

struct TopicData: Equatable {
    let topicId: String
    let creatorId: String
    let replyCount: Int
}

struct ShareContactData: Equatable {
    let userId: String
    let username: String
    let displayName: String
    let avatar: String

    var resolvedDisplayName: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? userId : user
    }

    var resolvedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var userIdInt: Int64? {
        Int64(userId.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct ChatMessageDisplay: Identifiable {
    let message: Message
    let senderDisplayName: String
    let senderUsername: String
    let avatarURL: String?
    let isCombine: Bool
    let attachments: [ParsedAttachment]
    let reactions: [ParsedReaction]
    let parsedContent: ParsedContent
    let replyRef: Mezon_Api_MessageRef?
    let isDeletedReply: Bool
    let isWelcome: Bool
    let callLog: CallLogData?
    let topicData: TopicData?
    let locationData: LocationData?
    let isMe: Bool
    let sendingState: SendingState
    let showsSendingFeedback: Bool
    let hasIncludeMention: Bool
    let isForward: Bool
    let showForwardHeader: Bool
    let messageCode: Int32
    let clanInviteLinkCode: String?
    let replyRefSourceContent: String
    let pollData: PollData?
    let rawContentData: Data?
    var isFailed: Bool { sendingState == .failed }
    var isSending: Bool { sendingState == .pending && showsSendingFeedback }
    var isBuzzMessage: Bool { messageCode == MezonConstants.MessageCode.buzz.rawValue }
    var isSendTokenLog: Bool { messageCode == MezonConstants.MessageCode.sendToken.rawValue }
    var isPollMessage: Bool { pollData != nil }
    var isEphemeral: Bool { messageCode == MezonConstants.MessageCode.ephemeral.rawValue }
    var id: String { message.id }
    var isCallLog: Bool { callLog != nil }
    var isTopic: Bool { topicData != nil }
    var isLocation: Bool { locationData != nil }
    var singleImageMediaAttachment: ParsedAttachment? {
        guard attachments.count == 1,
              let attachment = attachments.first,
              attachment.isImage,
              !attachment.isVideo else { return nil }
        if attachment.localImage != nil { return attachment }
        return attachment.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : attachment
    }
    var shareContactData: ShareContactData? {
        guard let embed = parsedContent.embeds.first else { return nil }
        let isShareContact = messageCode == MezonConstants.MessageCode.shareContact.rawValue
            || embed.fields.first?.value == MezonConstants.shareContactKey
            || embed.fields.contains { $0.name == "key" && $0.value == MezonConstants.shareContactKey }
        guard isShareContact else { return nil }

        func value(named name: String, fallbackIndex: Int) -> String {
            if let byName = embed.fields.first(where: { $0.name == name })?.value {
                return byName
            }
            guard fallbackIndex >= 0, fallbackIndex < embed.fields.count else { return "" }
            return embed.fields[fallbackIndex].value
        }

        let data = ShareContactData(
            userId: value(named: "user_id", fallbackIndex: 1),
            username: value(named: "username", fallbackIndex: 2),
            displayName: value(named: "display_name", fallbackIndex: 3),
            avatar: value(named: "avatar", fallbackIndex: 4)
        )
        guard data.userIdInt != nil || !data.resolvedUsername.isEmpty || !data.resolvedDisplayName.isEmpty else {
            return nil
        }
        return data
    }

    var isAnonymousSender: Bool {
        message.senderId == "\(MezonConstants.anonymousUserId)"
    }

    var isSystemMessage: Bool {
        let code = MezonConstants.MessageCode(rawValue: messageCode)
        switch code {
        case .welcome, .createThread, .deleteThread, .createPin, .auditLog, .upcomingEvent:
            return true
        default:
            return false
        }
    }

    var checkOneLinkImage: Bool {
        guard attachments.count == 1,
            let att = attachments.first,
              att.isImage else { return false }
        let trimmedText = parsedContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty && trimmedText == att.url
    }

    static func isCombineWithPrevious(current: Message, previous: Message?) -> Bool {
        guard let prev = previous else { return false }
        guard sameSenderId(current.senderId, prev.senderId) else { return false }
        let diff = abs(current.createdAt.timeIntervalSince(prev.createdAt))
        return diff < 120
    }

    static func sameSenderId(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let ta = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if ta == tb { return true }
        if let ia = Int64(ta), let ib = Int64(tb) { return ia == ib }
        return false
    }

    static let mentionHereUserId: String = "1775731111020111321"
    private static let forwardCombineGapSeconds: TimeInterval = 120

    static func shouldShowForwardHeader(isForward: Bool, current: Message, previous: Message?, previousWasForward: Bool) -> Bool {
        guard isForward else { return false }
        guard let prev = previous else { return true }
        if !previousWasForward { return true }
        let diff = current.createdAt.timeIntervalSince(prev.createdAt)
        if diff > Self.forwardCombineGapSeconds || diff < 0 { return true }
        if current.senderId != prev.senderId { return true }
        return false
    }
}

struct ChatState {
    var messages: [ChatMessageDisplay]
    var channelLabel: String
    var channelType: Int32
    var isPrivate: Bool
    var isAgeRestricted: Bool
    var isDM: Bool
    var isPeerBlocked: Bool
    var dmPeerUsername: String
    var dmPeerDisplayName: String
    var dmAvatarURL: String
    var dmGroupAvatarURL: String
    var threadCreatorName: String
    var hasMoreOlder: Bool
    var hasMoreNewer: Bool
    var isLoadingMore: Bool
    var isLoadingNewer: Bool
    var isLoadingMessageContext: Bool
    var isLoading: Bool
    var errorMessage: String?
    var lastSeenMessageId: String?
    var currentUserId: String?
    var parentName: String?

    static let empty = ChatState(
        messages: [], channelLabel: "", channelType: 0, isPrivate: false, isAgeRestricted: false,
        isDM: false, isPeerBlocked: false, dmPeerUsername: "", dmPeerDisplayName: "", dmAvatarURL: "", dmGroupAvatarURL: "",
        threadCreatorName: "",
        hasMoreOlder: false, hasMoreNewer: false, isLoadingMore: false, isLoadingNewer: false,
        isLoadingMessageContext: false,
        isLoading: false, errorMessage: nil, lastSeenMessageId: nil, currentUserId: nil,
        parentName: nil)
}

final class ChatViewController: ViewController {

    private static var isLicenseAgreementPresentationScheduled = false
    private static let pendingSendFeedbackDelay: TimeInterval = 1.0

    let clanId: Int64
    private(set) var channel: Mezon_Api_ChannelDescription
    let context: AccountContext
    var topicId: Int64 = 0 {
        didSet {
            guard topicId != oldValue else { return }
            if isViewLoaded {
                syncChannelToComposer()
            }
        }
    }
    private var skipRemoteFetchWhileTopicIsEmpty = false
    private var pendingTopicCreationMessageId: Int64?
    private var messageHistoryDisposable: Disposable?
    private var storageChannelId: String {
        if let messageId = pendingTopicCreationMessageId {
            return "pending-topic-\(messageId)"
        }
        return topicId != 0 ? "topic-\(topicId)" : "\(channel.channelID)"
    }

    func configureAsPendingTopicCreation(sourceMessageId: Int64) {
        pendingTopicCreationMessageId = sourceMessageId
        skipRemoteFetchWhileTopicIsEmpty = true
    }

    private let needsReloadPipe = ValuePipe<Void>()
    private let metadataOnlyPipe = ValuePipe<Void>()
    var needsReloadSignal: Signal<Void, NoError> { needsReloadPipe.signal() }
    private let stateDisposables = DisposableSet()

    private(set) var messages: [ChatMessageDisplay] = []
    private var persistentMessages: [ChatMessageDisplay] = []  
    private var ephemeralMessages: [ChatMessageDisplay] = []
    private var channelLabel: String = ""
    private(set) var hasMoreOlder: Bool = true
    private(set) var hasMoreNewer: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var isLoadingNewer: Bool = false
    private(set) var isLoadingMessageContext: Bool = false
    private var lastFetchedOlderMessageId: Int64?
    private var lastFetchedNewerMessageId: Int64?
    private var isJumping: Bool = false
    private(set) var pinnedMessageIds: Set<String> = []
    private var pinServerIdByMessageId: [String: Int64] = [:]
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var channelMeta: ChannelRecord?
    private(set) var parentChannelMeta: ChannelRecord?
    private var initialParentName: String?
    private(set) var lastSeenMessageId: String?
    private var didStartParentChannelMetaView = false

    private let locationManager = CLLocationManager()
    private var locationCompletion: ((CLLocationCoordinate2D?) -> Void)?
    private var isWaitingForLocationAuthorization = false
    private var locationFetchTimeoutWorkItem: DispatchWorkItem?
    private static let cachedLocationMaxAge: TimeInterval = 120
    private static let locationFetchTimeout: TimeInterval = 8

    private lazy var sendInputViewController: SendMessageInputViewController = {
        let vc = SendMessageInputViewController(
            placeholder: L(L10n.ChannelMessages.writeMessage),
            channel: channel,
            clanId: clanId,
            context: context
        )
        vc.onSent = { [weak self] in self?.shouldScrollToBottom = true }
        vc.onHeightChanged = { [weak self] newHeight in
            self?.updateInputBarHeight(newHeight)
        }
        vc.onToggleEmojiPicker = { [weak self] visible, collapsedH in
            guard let self else { return }
            if visible {
                self.isKeyboardVisible = false
                self.trackedKeyboardHeight = 0
            }
            self.emojiPicker.setVisible(visible, collapsedHeight: collapsedH)
        }
        vc.onToggleAdvancePanel = { [weak self] visible, collapsedH in
            self?.handleAdvancePanelToggle(visible: visible, collapsedHeight: collapsedH)
        }
        vc.onAnonymousModeChanged = { [weak self] in
            self?.rebuildAdvancePanelActions()
        }
        vc.topicId = self.topicId
        return vc
    }()


    private lazy var emojiPicker: ChatEmojiPickerPresenter = {
        let p = ChatEmojiPickerPresenter(sendInput: sendInputViewController)
        p.onRequestRelayout = { [weak self] transition in
            guard let self, let layout = self.lastLayout else { return }
            self.containerLayoutUpdated(layout, transition: transition)
        }
        p.onSetSuppressNextScrollToBottom = { [weak self] value in
            self?.suppressScrollToBottomForNextKeyboardInset = value
        }
        return p
    }()

    private lazy var advancePanelView: AdvancedFunctionPanelView = {
        let v = AdvancedFunctionPanelView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onRequestDismiss = { [weak self] in
            guard let self else { return }
            self.sendInputViewController.markAdvancePanelDismissedByHost()
            self.handleAdvancePanelToggle(visible: false, collapsedHeight: 0)
            self.sendInputViewController.focusTextInput()
        }
        v.onActionTapped = { [weak self] item in
            self?.handleAdvanceAction(item)
        }
        v.onHeightChanged = { [weak self] newHeight in
            self?.updateAdvancePanelOverlayHeight(newHeight)
        }
        return v
    }()

    private var advancePanelHeightConstraint: NSLayoutConstraint?
    private var advancePanelBottomConstraint: NSLayoutConstraint?
    private var advancePanelCollapsedHeight: CGFloat = 0

    private var inputBarHeight: CGFloat = 56
    private var lastNotifiedComposerHeight: CGFloat = -1
    private let channelAppHotbar: ChannelAppHotbarBarView = {
        let v = ChannelAppHotbarBarView()
        v.isHidden = true
        return v
    }()
    private var currentKeyboardOffset: CGFloat = 0
    private var isKeyboardVisible = false
    private var trackedKeyboardHeight: CGFloat = 0
    private var suppressScrollToBottomForNextKeyboardInset = false
    private var shouldReconcileKeyboardAfterNotificationNavigation = false
    private var notificationKeyboardReconcileWorkItem: DispatchWorkItem?
    private lazy var shouldScrollToBottom: Bool = lastSeenMessageId == nil
    private var pendingScrollToBottom = false
    private var lastMarkedAsReadMessageId: Int64?
    private var pendingMarkAsRead = false
    private var didMarkChannelAsReadForCurrentAppearance = false
    private var nextFetchPrefersHTTPFirst = false
    private var isCatchingUpAfterReconnect = false
    private var reconnectCatchUpTask: Task<Void, Never>?
    private var readyToLoadMore = false
    private var hasPerformedInitialUnreadScroll = false
    private var pendingSendingFeedbackBeganAtByMessageId: [String: Date] = [:]
    private var sendingFeedbackRefreshWorkItem: DispatchWorkItem?
    private var pendingUploadRefreshMessageIds = Set<String>()
    private var uploadRefreshFlushScheduled = false

    private struct RemoteTyperState {
        var displayName: String
        var expires: Date
    }

    private var remoteTypers: [Int64: RemoteTyperState] = [:]
    private var typingPruneTimer: Foundation.Timer?

    private static let remoteTypingStripMaxHeight: CGFloat = 22
    private static let remoteTypingStripBottomPadding: CGFloat = 2
    private static let chatFrameBottomGap: CGFloat = 6.sh

    private lazy var memberOnboardingMissionBarView: MemberOnboardingChatMissionBarView = {
        let bar = MemberOnboardingChatMissionBarView()
        bar.isHidden = true
        bar.onTap = { [weak self] in self?.handleMemberOnboardingMissionBarTap() }
        return bar
    }()
    private var memberOnboardingMissionBarDidInitialLayout = false
    private var memberOnboardingMissionBarVisible = false {
        didSet {
            guard isViewLoaded, oldValue != memberOnboardingMissionBarVisible, let layout = lastLayout else { return }
            let transition: ContainedViewLayoutTransition
            if memberOnboardingMissionBarVisible, !memberOnboardingMissionBarDidInitialLayout {
                memberOnboardingMissionBarDidInitialLayout = true
                transition = .immediate
            } else {
                transition = .animated(duration: 0.15, curve: .easeInOut)
            }
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    private lazy var remoteTypingStripView: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.clipsToBounds = true
        return v
    }()

    private let remoteTypingLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 13))
        lbl.adjustsFontForContentSizeCategory = true
        lbl.numberOfLines = 1
        lbl.lineBreakMode = .byTruncatingTail
        lbl.isHidden = true
        return lbl
    }()

    private var messagesNode: ChatContainerNode { displayNode as! ChatContainerNode }

    private var initialMessageJumpTargetId: String?
    private var startupJumpTargetForInitialFetch: String?
    var pendingJumpToMessageId: String? {
        didSet {
            if let target = pendingJumpToMessageId, !target.isEmpty {
                initialMessageJumpTargetId = target
            }
        }
    }

    private func finishMessageJump(messageId: String) {
        if let initialTarget = initialMessageJumpTargetId {
            guard initialTarget == messageId else { return }
            initialMessageJumpTargetId = nil
            setIsLoading(false)
        }
        isJumping = false
        readyToLoadMore = true
    }

    init(
        clanId: Int64, channel: Mezon_Api_ChannelDescription, context: AccountContext,
        parentName: String? = nil
    ) {
        self.clanId = clanId
        self.channel = channel
        self.context = context
        self.initialParentName = parentName
        if !channel.channelLabel.isEmpty {
            self.channelLabel = channel.channelLabel
        } else {
            self.channelLabel = "channel"
        }
        if channel.hasLastSeenMessage && channel.lastSeenMessage.id != 0 {
            self.lastSeenMessageId = "\(channel.lastSeenMessage.id)"
        }
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        var interaction = ChatInteraction(
            onBackTapped: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onHeaderTapped: { [weak self] in
                self?.openChannelDetail()
            },
            onSearchTapped: { [weak self] in
                guard let self else { return }
                let isPrivateOrThread = self.channel.channelPrivate != 0 || self.channel.parentID != 0
                let searchVC = SearchViewController(
                    clanId: self.clanId,
                    context: self.context,
                    channelId: self.channel.channelID,
                    channelLabel: self.channel.channelLabel,
                    channelType: self.channel.type != 0 ? self.channel.type : MezonConstants.ChannelType.channel.rawValue,
                    needsChannelMemberFilter: isPrivateOrThread
                )
                self.navigationController?.pushViewController(searchVC, animated: true)
            },
            onCallTapped: { [weak self] in
                self?.startCall()
            },
            onVideoCallTapped: { [weak self] in
                self?.startVideoCall()
            },
            onHistoryTapped: { },
            onMenuTapped: { },
            onScrolledNearTop: { [weak self] in
                guard let self, !self.isJumping, self.readyToLoadMore, self.hasMoreOlder, !self.isLoadingMore else { return }
                self.fetchOlderMessages()
            },
            onScrolledNearBottom: { [weak self] in
                guard let self, !self.isJumping, self.readyToLoadMore, self.hasMoreNewer, !self.isLoadingNewer else { return }
                self.fetchNewerMessages()
            },
            onScrolledToBottom: { [weak self] atBottom in
                guard let self else { return }
                self.shouldScrollToBottom = atBottom
                if atBottom,
                   self.viewIfLoaded?.window != nil,
                   UIApplication.shared.applicationState == .active,
                   self.hasPerformedInitialUnreadScroll || self.lastSeenMessageId == nil {
                    self.clearLastSeenMessageId()
                    self.markChannelAsRead()
                }
            },
            onJumpToPresent: { [weak self] in self?.jumpToPresent() },
            onMentionTapped: { [weak self] mentionId in
                self?.showMemberProfileById(mentionId)
            },
            onHashtagTapped: { [weak self] info in
                guard let self else { return }
                guard !info.channelId.isEmpty else { return }
                guard info.channelId != "\(self.channel.channelID)" else { return }
                let resolvedClan = info.clanId.flatMap { Int64($0) } ?? self.clanId
                guard let idInt = Int64(info.channelId) else { return }
                let channels = self.context.engine.clanData.getAllChannelsByUser()?.channeldesc ?? []
                let ch0 = channels.first(where: { $0.channelID == idInt && (resolvedClan == 0 || $0.clanID == resolvedClan || $0.clanID == 0) })
            if var ch = ch0, ch.type == MezonConstants.ChannelType.mezonVoice.rawValue {
                if ch.clanID == 0, resolvedClan != 0 {
                    ch.clanID = resolvedClan
                }
                self.view.endEditing(true)
                self.presentJoinVoiceSheet(for: ch)
                return
            }
            if var ch = ch0, ch.type == MezonConstants.ChannelType.streaming.rawValue {
                if ch.clanID == 0, resolvedClan != 0 {
                    ch.clanID = resolvedClan
                }
                self.view.endEditing(true)
                self.presentJoinStreamSheet(for: ch)
                return
            }
            AppDelegate.navigateToChannel(channelId: info.channelId, clanId: "\(resolvedClan)")
            },
            hashtagChannelIsAccessible: { [weak self] channelId, clanIdOpt in
                guard let self else { return false }
                guard let idInt = Int64(channelId) else { return false }
                let resolvedClan = clanIdOpt.flatMap { Int64($0) } ?? self.clanId
                let channels = self.context.engine.clanData.getAllChannelsByUser()?.channeldesc ?? []
                if channels.contains(where: { $0.channelID == idInt && (resolvedClan == 0 || $0.clanID == resolvedClan || $0.clanID == 0) }) {
                    return true
                }
                if let desc = self.context.account.postbox.getChannelDescription(channelId: idInt)?.channel {
                    return desc.channelPrivate == 0
                }
                return false
            },
            onMessageLongPressed: { [weak self] display in
                self?.showMessageActions(display)
            },
            onReplyTapped: { [weak self] messageId in
                self?.jumpToMessage(id: messageId)
            },
            onTopicTapped: { [weak self] topicData in
                self?.openTopicDiscussion(topicData: topicData)
            },
            onReactionTapped: { [weak self] reaction, display in
                self?.handleEmojiReaction(emojiId: reaction.emojiId, shortname: reaction.emoji, display: display)
            },
            onReactionDetailRequested: { [weak self] reaction, display in
                self?.presentReactionDetailSheet(initialReaction: reaction, display: display)
            },
            onAddReactionTapped: { [weak self] display in
                self?.presentReactionEmojiPicker(for: display)
            },
            onAvatarTapped: { [weak self] display in
                self?.showMemberProfile(display)
            },
            onShareContactProfileTapped: { [weak self] data in
                self?.showShareContactProfile(data)
            },
            onShareContactMessageTapped: { [weak self] data in
                self?.openShareContactDirectMessage(data)
            },
            onShareContactCallTapped: { [weak self] data in
                self?.startShareContactCall(data)
            },
            isShareContactCallBlocked: { [weak self] data in
                self?.isShareContactCallBlocked(data) ?? false
            },
            onSwipeReply: { [weak self] display in
                self?.sendInputViewController.setReply(display)
            },
            loadClanInviteInfo: { [weak self] code, completion in
                guard let self else {
                    completion(nil)
                    return
                }
                let token = self.context.session?.token ?? ""
                guard !token.isEmpty else {
                    completion(nil)
                    return
                }
                Task {
                    do {
                        let info = try await self.context.engine.clanData.getInviteInfo(code: code, token: token)
                        await MainActor.run { completion(info) }
                    } catch {
                        await MainActor.run { completion(nil) }
                    }
                }
            },
            onClanInvitePrimaryAction: { [weak self] code, info in
                guard let self else { return }
                let token = self.context.session?.token ?? ""
                guard !token.isEmpty else {
                    Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                    return
                }
                if info.user_joined == true, let cid = info.clan_id, !cid.isEmpty {
                    NotificationCenter.default.post(
                        name: .mezonQRSelectClan,
                        object: nil,
                        userInfo: ["clanId": cid]
                    )
                    return
                }
                if ClanCreationLimit.showLimitToastIfNeeded(context: self.context) { return }
                Task {
                    let clanId = await ClanInviteJoiner.join(context: self.context, code: code, clanId: info.clan_id.flatMap(Int64.init))
                    await MainActor.run {
                        guard let clanId else {
                            Toast.error(L(L10n.Error.somethingWentWrong))
                            return
                        }
                        NotificationCenter.default.post(
                            name: .mezonQRSelectClan,
                            object: nil,
                            userInfo: ["clanId": "\(clanId)"]
                        )
                    }
                }
            },
            onSendTokenLogTapped: { [weak self] in
                guard let self else { return }
                let vc = QRScannerViewController(context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onSystemPinMessageTapped: { [weak self] display in
                guard let self else { return }
                guard let ref = display.replyRef, ref.messageRefID != 0 else { return }
                self.jumpToMessage(id: "\(ref.messageRefID)")
            },
            onSystemThreadTapped: { [weak self] threadChannelId, threadLabel in
                self?.openThreadFromSystemMessage(threadChannelId: threadChannelId, threadLabel: threadLabel)
            },
            onSystemAllThreadsTapped: { [weak self] in
                self?.openThreadListFromChat()
            },
            onSystemWaveWelcomeTapped: { [weak self] display in
                self?.sendInputViewController.sendWaveWelcome(replyingTo: display)
            },
            isSystemThreadDeleted: { [weak self] threadId in
                guard let self, !threadId.isEmpty else { return false }
                return self.currentState.messages.contains { display in
                    display.messageCode == MezonConstants.MessageCode.deleteThread.rawValue
                        && MessageSystemNode.parseThreadParenLabelId(display.parsedContent.text)?.id == threadId
                }
            },
            onVotePoll: { [weak self] messageId, channelId, answerIndices, completion in
                guard let self else { completion(nil); return }
                let token = self.context.session?.token ?? ""
                guard !token.isEmpty else { completion(nil); return }
                guard let pollData = self.currentState.messages.first(where: { $0.id == messageId })?.pollData else {
                    completion(nil)
                    return
                }
                Task {
                    do {
                        let response = try await self.context.account.network.votePoll(
                            pollId: pollData.id,
                            messageId: Int64(messageId) ?? 0,
                            channelId: Int64(channelId) ?? 0,
                            answerIndices: answerIndices,
                            token: token
                        )
                        await MainActor.run {
                            completion(response.myAnswerIndices)
                        }
                    } catch {
                        await MainActor.run {
                            Toast.error(error.localizedDescription)
                            completion(nil)
                        }
                    }
                }
            },
            onOpenPollDetail: { [weak self] messageId, channelId in
                guard let self else { return }
                let token = self.context.session?.token ?? ""
                guard !token.isEmpty else { return }
                guard let display = self.currentState.messages.first(where: { $0.id == messageId }),
                      let pollData = display.pollData else { return }

                let options: [PollOptionDisplay] = pollData.answers.map { answer in
                    let voteCount = pollData.answerCounts[answer.index] ?? 0
                    let percentage = pollData.totalVotes > 0
                        ? Int(round(Double(voteCount) / Double(pollData.totalVotes) * 100))
                        : 0
                    return PollOptionDisplay(
                        index: answer.index,
                        label: answer.label,
                        voteCount: voteCount,
                        percentage: percentage,
                        isSelected: false
                    )
                }

                let detailVC = PollDetailViewController(
                    question: pollData.question,
                    totalVotes: pollData.totalVotes,
                    options: options,
                    votersByOption: [:],
                    isLoading: true
                )
                self.present(detailVC, animated: false)

                Task {
                    do {
                        let response = try await self.context.account.network.getPoll(
                            pollId: pollData.id,
                            messageId: Int64(messageId) ?? 0,
                            channelId: Int64(channelId) ?? 0,
                            token: token
                        )
                        let allClanMembers: [ClanMemberRecord] = self.clanId != 0
                            ? self.context.account.postbox.read { $0.getClanMembers(clanId: self.clanId) }
                            : []
                        let clanMembersMap = Dictionary(allClanMembers.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
                        
                        var votersByOption: [Int: [PollVoter]] = [:]
                        for detail in response.voterDetails {
                            let voters = detail.userIds.map { userId in
                                let profile = self.context.account.postbox.read { $0.getProfile(userId: "\(userId)") }
                                let clanMember = clanMembersMap[userId]
                                
                                let displayName: String
                                if let clanNick = clanMember?.clanNick, !clanNick.isEmpty {
                                    displayName = clanNick
                                } else {
                                    displayName = profile?.displayName ?? profile?.username ?? "User"
                                }
                                
                                let avatar = clanMember?.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl) ?? profile?.avatarUrl ?? ""
                                
                                return PollVoter(
                                    id: "\(userId)",
                                    displayName: displayName,
                                    username: profile?.username ?? clanMember?.username ?? "",
                                    avatar: avatar
                                )
                            }
                            votersByOption[Int(detail.answerIndex)] = voters
                        }
                        await MainActor.run {
                            detailVC.updateVoters(votersByOption)
                        }
                    } catch {
                        await MainActor.run {
                            Toast.error(error.localizedDescription)
                        }
                    }
                }
            },
            onCallLogCallBackTapped: { [weak self] callLog in
                guard let self else { return }
                if callLog.isVideo {
                    self.startVideoCall()
                } else {
                    self.startCall()
                }
            },
            isGroupDMChat: { [weak self] in
                guard let self else { return false }
                return self.channel.type == MezonConstants.ChannelType.group.rawValue
            },
            resolveSenderRoleColor: { [weak self] senderId, fallback in
                guard let self else { return fallback }
                return self.context.rolePermissions.messageSenderNameColor(
                    senderId: senderId,
                    clanId: self.clanId,
                    isClanChannel: self.isClanChannelForRoleDisplay,
                    fallback: fallback
                )
            },
            resolveSenderRoleIconURL: { [weak self] senderId in
                guard let self else { return nil }
                return self.context.rolePermissions.messageSenderRoleIconURL(
                    senderId: senderId,
                    clanId: self.clanId,
                    isClanChannel: self.isClanChannelForRoleDisplay
                )
            },
            onMessagesReloaded: nil,
            onMessageNeedsRelayout: nil,
            onEmbedButtonClicked: nil
        )
        interaction.onMediaTapped = { [weak self] index, media, display, previewImage in
            self?.presentMessageMediaGallery(
                index: index,
                media: media,
                display: display,
                previewImage: previewImage
            )
        }
        interaction.onMediaRetryTapped = { [weak self] index, display in
            guard let self else { return }
            AttachmentUploadCoordinator.shared.retry(
                context: self.context, messageId: display.message.id, itemIndex: index)
        }
        interaction.onMessagesReloaded = { [weak self] in
            guard let self else { return }
            if let seenId = self.lastSeenMessageId {
                self.scrollToUnreadLine(lastSeenId: seenId)
                self.hasPerformedInitialUnreadScroll = true
            } else {
                self.hasPerformedInitialUnreadScroll = true
                self.scrollToBottomIfNeeded()
            }
        }
        interaction.onMessageNeedsRelayout = { [weak self] (messageId: String) in
            guard let self else { return }
            self.messagesNode.forceUpdateItem(id: messageId)
        }
        interaction.onEmbedButtonClicked = { [weak self] (button: ParsedEmbedButton, messageId: String, display: ChatMessageDisplay) in
            guard let self else { return }
            self.handleEmbedButtonClicked(button: button, messageId: messageId, display: display)
        }
        
        let containerNode = ChatContainerNode(
            signal: stateSignal(),
            interaction: interaction,
            isDM: channel.type == MezonConstants.ChannelType.dm.rawValue
        )
        containerNode.onPendingJumpCompleted = { [weak self] messageId in
            self?.finishMessageJump(messageId: messageId)
        }
        displayNode = containerNode
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        messagesNode.applyTheme()
        setupInputBar()
        configureAnonymousComposerAndAdvancePanel()
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        start()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEphemeralMessageReceived(_:)),
            name: Notification.Name("MezonNewMessageReceived"),
            object: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.readyToLoadMore = true
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSocketReconnected(_:)), name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMessageTypingReceived(_:)), name: .mezonMessageTypingReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNetworkStatusChanged(_:)), name: NetworkMonitor.statusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelPinsNeedRefresh(_:)), name: .mezonChannelPinsNeedRefresh, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAttachmentUploadProgress(_:)), name: .mezonAttachmentUploadProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAttachmentUploadSlotStateChanged(_:)), name: .mezonAttachmentUploadSlotStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMetadataChanged(_:)), name: .mezonChannelDescriptionDidUpdate, object: nil)
    }

    private static func userInfoInt64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    @objc private func handleChannelMetadataChanged(_ notification: Notification) {
        guard let cid = Self.userInfoInt64(notification.userInfo?["channelId"]), cid == channel.channelID else { return }
        let typeWasUnknown = channel.type == 0
        var updatedChannel: Mezon_Api_ChannelDescription?
        if clanId != 0 {
            if let notifyClan = Self.userInfoInt64(notification.userInfo?["clanId"]), notifyClan != clanId {
                return
            }
            if let cached = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID) {
                updatedChannel = cached
            }
        } else if let cached = context.account.postbox.getDMChannelDescription(channelId: channel.channelID) {
            updatedChannel = cached
        }

        if let updatedChannel {
            channel = updatedChannel
            if !updatedChannel.channelLabel.isEmpty {
                setChannelLabel(updatedChannel.channelLabel)
            }
            sendInputViewController.channel = updatedChannel
            syncChannelToComposer()
            if typeWasUnknown && updatedChannel.type != 0 {
                rejoinChatIfChannelMetadataChanged()
            }
        }
        metadataOnlyPipe.putNext(())
    }

    @objc private func handleNetworkStatusChanged(_ notification: Notification) {
        let connected = (notification.userInfo?["isConnected"] as? Bool) ?? NetworkMonitor.shared.isConnected
        guard connected else { return }
        guard !hasCompletedInitialFetch else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var token = await self.context.getTokenPreferringCachedSkipSessionReadyWait()
            if token == nil {
                await self.context.waitForSessionReady()
                token = await self.context.getToken()
            }
            guard let token else {
                self.setIsLoading(false)
                return
            }
            self.performInitialMessageFetchIfNeeded(token: token)
        }
    }
    
    @objc private func handleEphemeralMessageReceived(_ notification: Notification) {
        guard let messageCode = notification.userInfo?["messageCode"] as? Int64 else { return }
        guard let channelId = notification.userInfo?["channelId"] as? Int64 else { return }
        guard channelId == channel.channelID else { return }
        let userInfo = notification.userInfo

        let work = { [weak self] in
            guard let self else { return }
            self.processMessageNotification(messageCode: messageCode, userInfo: userInfo)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func processMessageNotification(messageCode: Int64, userInfo: [AnyHashable: Any]?) {

        if messageCode == 1 {
            let channelIdStr = storageChannelId
            let rows = context.account.postbox.read { tx in tx.getMessages(channelId: channelIdStr) }
            setMessages(buildDisplayMessages(from: rows))
            return
        }

        guard let data = userInfo?["serializedChannelMessage"] as? Data,
              let apiMessage = try? Mezon_Api_ChannelMessage(serializedBytes: data) else { return }

        if messageCode == MezonConstants.MessageCode.deleteEphemeral.rawValue {
            let targetId = "\(apiMessage.messageID)"
            ephemeralMessages.removeAll { $0.id == targetId || $0.message.id == targetId }
            updateMessagesWithEphemeral()
            return
        }

        if messageCode == MezonConstants.MessageCode.updateEphemeral.rawValue {
            let targetId = "\(apiMessage.messageID)"
            let record = MessageRecord(from: apiMessage, customId: targetId)
            let parsedRaw = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
            let parsed = enrichParsedContent(parsedRaw, fallbackClanId: record.clanId)
            let msg = Message(
                id: record.id, channelId: record.channelId, clanId: record.clanId,
                senderId: record.senderId, content: .text(parsed.text),
                createdAt: record.createdAt, editedAt: record.editedAt,
                isDeleted: record.isDeleted, reactions: [], replyToId: nil,
                mentionedUserIds: [], isPinned: false
            )
            let display = ChatMessageDisplay(
                message: msg, senderDisplayName: record.senderDisplayName, senderUsername: apiMessage.username, avatarURL: record.senderAvatarURL,
                isCombine: false, attachments: [], reactions: [], parsedContent: parsed,
                replyRef: nil, isDeletedReply: false, isWelcome: false, callLog: nil,
                topicData: nil, locationData: nil, isMe: record.senderId == context.currentUser?.id,
                sendingState: record.sendingState, showsSendingFeedback: false, hasIncludeMention: false,
                isForward: false, showForwardHeader: false, messageCode: record.code,
                clanInviteLinkCode: nil, replyRefSourceContent: "", pollData: nil, rawContentData: record.content
            )
            if let idx = ephemeralMessages.firstIndex(where: { $0.id == targetId || $0.message.id == targetId }) {
                ephemeralMessages[idx] = display
            } else {
                ephemeralMessages.append(display)
            }
            updateMessagesWithEphemeral()
            return
        }

        guard messageCode == MezonConstants.MessageCode.ephemeral.rawValue else { return }

        let targetId = "ephemeral-\(apiMessage.createTimeSeconds)-\(apiMessage.senderID)"
        let record = MessageRecord(from: apiMessage, customId: targetId)
        let parsedRaw = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
        let parsed = enrichParsedContent(parsedRaw, fallbackClanId: record.clanId)
        let msg = Message(
            id: record.id, channelId: record.channelId, clanId: record.clanId,
            senderId: record.senderId, content: .text(parsed.text),
            createdAt: record.createdAt, editedAt: record.editedAt,
            isDeleted: record.isDeleted, reactions: [], replyToId: nil,
            mentionedUserIds: [], isPinned: false
        )
        let display = ChatMessageDisplay(
            message: msg, senderDisplayName: record.senderDisplayName, senderUsername: apiMessage.username, avatarURL: record.senderAvatarURL,
            isCombine: false, attachments: [], reactions: [], parsedContent: parsed,
            replyRef: nil, isDeletedReply: false, isWelcome: false, callLog: nil,
            topicData: nil, locationData: nil, isMe: record.senderId == context.currentUser?.id,
            sendingState: record.sendingState, showsSendingFeedback: false, hasIncludeMention: false,
            isForward: false, showForwardHeader: false, messageCode: record.code,
            clanInviteLinkCode: nil, replyRefSourceContent: "", pollData: nil, rawContentData: record.content
        )
        ephemeralMessages.append(display)
        updateMessagesWithEphemeral()
    }

    
    private func updateMessagesWithEphemeral() {
        messages = normalizedDisplayOrder(persistentMessages + ephemeralMessages)
        needsReloadPipe.putNext(())
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureAnonymousComposerAndAdvancePanel()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            onLeave()
        } else {
            wasCoveredByPushedController = true
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !isMovingFromParent else { return }
        if presentedViewController != nil { return }
        if view.window?.rootViewController?.presentedViewController != nil { return }
        guard topicId == 0 else { return }
        if ActiveChannelTracker.currentChannelId == channel.channelID {
            context.currentChannel = nil
            ActiveChannelTracker.currentChannelId = 0
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let layoutToApply = layout
        let composerHasKeyboardFocus = sendInputViewController.view.findFirstResponder() != nil
        lastLayout = layout

        let bottomInset = max(layoutToApply.intrinsicInsets.bottom, layoutToApply.safeInsets.bottom)
        let layoutInputH = layoutToApply.inputHeight ?? 0
        let shouldIgnoreNotificationKeyboardInset =
            shouldReconcileKeyboardAfterNotificationNavigation
            && layoutInputH > bottomInset + 1
            && !composerHasKeyboardFocus
        let rawInputH: CGFloat
        if shouldIgnoreNotificationKeyboardInset {
            rawInputH = 0
        } else if layoutInputH > 1 {
            rawInputH = layoutInputH
        } else if composerHasKeyboardFocus, isKeyboardVisible, trackedKeyboardHeight > 0.5 {
            rawInputH = trackedKeyboardHeight
        } else {
            rawInputH = layoutInputH
        }
        let rawKeyboardOffset = max(rawInputH - bottomInset, 0)
        var keyboardOffset = rawKeyboardOffset

        if keyboardOffset > 0 {
            let hasComposerFirstResponder = sendInputViewController.view.findFirstResponder() != nil
            if !hasComposerFirstResponder {
                keyboardOffset = 0
            }
        }

        if suppressScrollToBottomForNextKeyboardInset,
           emojiPicker.collapsedHeight == 0,
           advancePanelCollapsedHeight == 0,
           keyboardOffset < 0.5 {
            let hasComposerFirstResponder = sendInputViewController.view.findFirstResponder() != nil
            if hasComposerFirstResponder || isKeyboardVisible || rawKeyboardOffset > 0.5 {
                keyboardOffset = max(
                    keyboardOffset,
                    sendInputViewController.keyboardOverlayHeightEstimate
                )
            } else {
                suppressScrollToBottomForNextKeyboardInset = false
            }
        }

        if emojiPicker.isEmojiPanelSearchConsumingKeyboard {
            keyboardOffset = 0
        }

        if isReactionEmojiPickerSheetHostingFirstResponder {
            keyboardOffset = 0
        }

        let emojiOffset = emojiPicker.composerLayoutEmojiOffset
        let advanceOffset = advancePanelCollapsedHeight
        let bottomOffset = max(keyboardOffset, max(emojiOffset, advanceOffset))

        let sendComposerH = sendInputViewController.totalHeight
        let showAppHotbar = shouldShowChannelAppHotbar
        let appHotbarH: CGFloat = showAppHotbar ? ChannelAppHotbarBarView.prefersFixedHeight : 0
        channelAppHotbar.isHidden = !showAppHotbar
        let missionBarH: CGFloat = memberOnboardingMissionBarVisible ? MemberOnboardingChatMissionBarView.preferredHeight : 0
        memberOnboardingMissionBarView.isHidden = missionBarH == 0
        let totalBottomH = appHotbarH + sendComposerH
        let composerTop = layoutToApply.size.height - bottomInset - bottomOffset - totalBottomH
        let inputFrame = CGRect(
            x: 0,
            y: composerTop + appHotbarH,
            width: layoutToApply.size.width,
            height: sendComposerH + bottomInset
        )
        sendInputViewController.syncComposerBottomSafeInset(bottomInset)
        if missionBarH > 0 {
            let missionFrame = CGRect(
                x: 0,
                y: composerTop - missionBarH,
                width: layoutToApply.size.width,
                height: missionBarH
            )
            transition.updateFrame(view: memberOnboardingMissionBarView, frame: missionFrame, beginWithCurrentState: true)
        }
        if showAppHotbar {
            let hotbarFrame = CGRect(
                x: 0,
                y: composerTop,
                width: layoutToApply.size.width,
                height: appHotbarH
            )
            transition.updateFrame(view: channelAppHotbar, frame: hotbarFrame, beginWithCurrentState: true)
            transition.updateFrame(view: sendInputViewController.view, frame: inputFrame, beginWithCurrentState: true)
        } else {
            transition.updateFrame(view: sendInputViewController.view, frame: inputFrame, beginWithCurrentState: true)
        }

        emojiPicker.updateBottomInset(bottomInset)
        if emojiPicker.isEmojiPanelExpandedOverContent {
            emojiPicker.bringToFront()
        }
        advancePanelBottomConstraint?.constant = -bottomInset

        let stripH = Self.remoteTypingStripMaxHeight + Self.remoteTypingStripBottomPadding
        let typingFrame = CGRect(x: 0, y: composerTop - missionBarH - stripH, width: layoutToApply.size.width, height: stripH)
        transition.updateFrame(view: remoteTypingStripView, frame: typingFrame, beginWithCurrentState: true)
        remoteTypingLabel.frame = CGRect(
            x: 12,
            y: 0,
            width: max(0, layoutToApply.size.width - 24),
            height: Self.remoteTypingStripMaxHeight
        )

        let totalInputArea = totalBottomH + missionBarH + bottomOffset
        if bottomOffset > 0 && currentKeyboardOffset == 0 && !emojiPicker.wasJustDismissed && !suppressScrollToBottomForNextKeyboardInset {
            let previousTotalInputArea = inputBarHeight + currentKeyboardOffset
            if totalInputArea > previousTotalInputArea + 20 {
                let nonKeyboardBottom = max(emojiOffset, advanceOffset)
                if nonKeyboardBottom > 0.5 || keyboardOffset < 0.5 {
                    scrollToBottomIfNeeded()
                }
            }
        }
        emojiPicker.clearJustDismissedFlag()
        if suppressScrollToBottomForNextKeyboardInset, rawKeyboardOffset > 0.5 {
            suppressScrollToBottomForNextKeyboardInset = false
        }
        inputBarHeight = totalBottomH
        currentKeyboardOffset = bottomOffset

        messagesNode.updateLayout(
            layout: layoutToApply,
            inputBarHeight: totalInputArea + Self.chatFrameBottomGap,
            transition: transition
        )
    }

    private var lastLayout: ContainerViewLayout?
    private var wasCoveredByPushedController = false
    private var needsRefreshAfterTopicDiscussion = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didMarkChannelAsReadForCurrentAppearance = false
        if topicId == 0 {
            context.currentClanId = clanId
            context.currentChannel = channel
            ActiveChannelTracker.currentChannelId = channel.channelID
        }
        markChannelAsReadOnEntryIfPossible()
        refreshMemberOnboardingMissionBar()
        if wasCoveredByPushedController {
            wasCoveredByPushedController = false
            reloadDisplaysWithCurrentPins()
            if isViewLoaded {
                messagesNode.forceUpdateAllMessageItems()
            }
            if needsRefreshAfterTopicDiscussion, topicId == 0 {
                needsRefreshAfterTopicDiscussion = false
                markNextFetchPrefersHTTPFirst()
                fetchMessages()
            }
        }
        let hasComposerFR = sendInputViewController.view.findFirstResponder() != nil
        if !hasComposerFR && !isReactionEmojiPickerSheetHostingFirstResponder {
            isKeyboardVisible = false
            trackedKeyboardHeight = 0
        }
        reconcileKeyboardAfterNotificationNavigationIfNeeded()
        if let layout = lastLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
        presentLicenseAgreementIfNeeded()
    }

    private func collapseNotificationNavigationComposerOverlays() {
        guard isViewLoaded else { return }
        sendInputViewController.hideEmojiPickerIfNeeded()
        sendInputViewController.hideAdvancePanelIfNeeded()
        if emojiPicker.panelHeightForChatLayout > 0 {
            emojiPicker.setVisible(false, collapsedHeight: 0)
        }
        if advancePanelCollapsedHeight > 0 {
            handleAdvancePanelToggle(visible: false, collapsedHeight: 0)
        }
    }

    private func reconcileKeyboardAfterNotificationNavigationIfNeeded() {
        guard shouldReconcileKeyboardAfterNotificationNavigation, isViewLoaded else { return }
        collapseNotificationNavigationComposerOverlays()

        let wasTextInputFocused = sendInputViewController.isTextInputFocused
        if !wasTextInputFocused {
            isKeyboardVisible = false
            trackedKeyboardHeight = 0
        }
        if !isKeyboardVisible && trackedKeyboardHeight <= 0.5 {
            currentKeyboardOffset = 0
            suppressScrollToBottomForNextKeyboardInset = false
            if !wasTextInputFocused {
                view.endEditing(true)
            }
            if let layout = lastLayout, (layout.inputHeight ?? 0) > 1 {
                containerLayoutUpdated(layout.withUpdatedInputHeight(nil), transition: .immediate)
            }
        }

        scheduleNotificationKeyboardReconcileRetry(wasTextInputFocused: wasTextInputFocused, attempt: 0)
    }

    private func scheduleNotificationKeyboardReconcileRetry(wasTextInputFocused: Bool, attempt: Int) {
        notificationKeyboardReconcileWorkItem?.cancel()
        let delay: TimeInterval = attempt == 0 ? 0.08 : 0.25
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishNotificationKeyboardReconcile(wasTextInputFocused: wasTextInputFocused, attempt: attempt)
        }
        notificationKeyboardReconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func finishNotificationKeyboardReconcile(wasTextInputFocused: Bool, attempt: Int) {
        guard shouldReconcileKeyboardAfterNotificationNavigation, isViewLoaded else { return }
        if !wasTextInputFocused {
            isKeyboardVisible = false
            trackedKeyboardHeight = 0
        }
        if !isKeyboardVisible && trackedKeyboardHeight <= 0.5 {
            currentKeyboardOffset = 0
            suppressScrollToBottomForNextKeyboardInset = false
            if let layout = lastLayout, (layout.inputHeight ?? 0) > 1 {
                containerLayoutUpdated(layout.withUpdatedInputHeight(nil), transition: .immediate)
            }
            if wasTextInputFocused {
                if UIApplication.shared.applicationState == .active {
                    sendInputViewController.refocusTextInputAfterNavigation()
                } else if attempt < 3 {
                    scheduleNotificationKeyboardReconcileRetry(wasTextInputFocused: wasTextInputFocused, attempt: attempt + 1)
                    return
                }
            }
        }
        shouldReconcileKeyboardAfterNotificationNavigation = false
        notificationKeyboardReconcileWorkItem = nil
    }

    private func presentLicenseAgreementIfNeeded() {
        guard !LicenseAgreementPolicyStore.hasAgreed else { return }
        guard presentedViewController == nil else { return }
        if let nav = navigationController {
            guard nav.topViewController === self else { return }
        }
        guard !Self.isLicenseAgreementPresentationScheduled else { return }
        Self.isLicenseAgreementPresentationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Self.isLicenseAgreementPresentationScheduled = false
            guard let self else { return }
            guard !LicenseAgreementPolicyStore.hasAgreed else { return }
            guard self.presentedViewController == nil else { return }
            if let nav = self.navigationController {
                guard nav.topViewController === self else { return }
            }
            let vc = LicenseAgreementViewController()
            vc.modalPresentationStyle = .overFullScreen
            vc.modalTransitionStyle = .crossDissolve
            if #available(iOS 13.0, *) {
                vc.isModalInPresentation = true
            }
            self.present(vc, animated: true)
        }
    }

    @objc private func handleThemeChange() {
        messagesNode.applyTheme()
        applyRemoteTypingStripTheme()
        channelAppHotbar.applyTheme()
    }

    private func applyRemoteTypingStripTheme() {
        let t = UIColor.theme
        remoteTypingStripView.backgroundColor = t.primaryGradient
        remoteTypingLabel.textColor = t.textDisabled
    }

    @objc private func handleAttachmentUploadProgress(_ notification: Notification) {
        guard let key = notification.userInfo?["key"] as? String, !key.isEmpty else { return }
        let progress = (notification.userInfo?["progress"] as? Double) ?? 0
        let isRelevant = ParsedAttachment.pendingDocumentPlaceholders.values
            .contains { docs in docs.contains { $0.uploadProgressKey == key } }
            || AttachmentUploadCoordinator.shared.hasActiveProgressKey(key)
        guard isRelevant else { return }
        guard isViewLoaded else { return }
        messagesNode.updateUploadProgress(progressKey: key, progress: progress)
    }

    @objc private func handleAttachmentUploadSlotStateChanged(_ notification: Notification) {
        guard let messageId = notification.userInfo?["messageId"] as? String, !messageId.isEmpty else { return }
        pendingUploadRefreshMessageIds.insert(messageId)
        guard !uploadRefreshFlushScheduled else { return }
        uploadRefreshFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.uploadRefreshFlushScheduled = false
            let ids = self.pendingUploadRefreshMessageIds
            self.pendingUploadRefreshMessageIds.removeAll()
            for id in ids {
                self.refreshUploadingMessageDisplay(messageId: id)
            }
        }
    }

    private func refreshUploadingMessageDisplay(messageId: String) {
        let channelIdStr = storageChannelId
        guard let record = context.account.postbox.read({ tx in
            tx.getMessageById(messageId, channelId: channelIdStr) ?? tx.getMessageById(messageId)
        }) else { return }
        let updated = buildDisplayMessages(from: [record]).first(where: { $0.id == messageId })
        guard let updated else { return }
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let old = messages[idx]
        guard !ParsedAttachment.attachmentsStructurallyEqual(old.attachments, updated.attachments) else { return }

        if let pIdx = persistentMessages.firstIndex(where: { $0.id == messageId }) {
            var patched = persistentMessages
            patched[pIdx] = updated
            persistentMessages = patched
        }
        var patchedMessages = messages
        patchedMessages[idx] = updated
        messages = patchedMessages

        guard isViewLoaded else { return }
        messagesNode.applySingleMessagePatch(updated)
    }

    @objc private func handleChannelPinsNeedRefresh(_ notification: Notification) {
        let eventClan = Self.int64FromTypingUserInfo(notification.userInfo?["clanId"]) ?? 0
        let eventChannel = Self.int64FromTypingUserInfo(notification.userInfo?["channelId"]) ?? 0
        guard eventChannel == channel.channelID else { return }
        guard eventClan == clanId || eventClan == pinApiClanId() else { return }

        if let pinnedMid = Self.int64FromTypingUserInfo(notification.userInfo?["pinnedMessageId"]), pinnedMid != 0 {
            pinnedMessageIds.insert("\(pinnedMid)")
            syncPinnedStateToPostbox()
            reloadDisplaysWithCurrentPins()
            return
        }
        if let unpinnedMid = Self.int64FromTypingUserInfo(notification.userInfo?["unpinnedMessageId"]), unpinnedMid != 0 {
            pinnedMessageIds = Set(pinnedMessageIds.filter { k in
                guard let v = Int64(k.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
                return v != unpinnedMid
            })
            for k in Array(pinServerIdByMessageId.keys) {
                if Int64(k.trimmingCharacters(in: .whitespacesAndNewlines)) == unpinnedMid {
                    pinServerIdByMessageId.removeValue(forKey: k)
                }
            }
            syncPinnedStateToPostbox()
            reloadDisplaysWithCurrentPins()
            return
        }

        refreshPinnedMessagesFromServer()
    }

    @objc private func handleSocketReconnected(_ notification: Notification) {
        guard let isConnected = notification.userInfo?["isConnected"] as? Bool, isConnected else { return }
        if pendingMarkAsRead {
            markChannelAsRead()
        }
        let previousCatchUp = reconnectCatchUpTask
        previousCatchUp?.cancel()
        reconnectCatchUpTask = Task { @MainActor [weak self] in
            _ = await previousCatchUp?.value
            guard let self, !Task.isCancelled else { return }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            await self.joinChatAndWaitUntilSent()
            self.refreshPinnedMessagesFromServer()
            if self.newestServerMessageId() == nil {
                self.fetchMessages(token: token)
            } else {
                await self.catchUpMessagesAfterReconnect(token: token)
            }
            if !self.hasCompletedInitialFetch {
                self.hasCompletedInitialFetch = true
                self.fetchNotificationSetting(token: token)
                self.fetchChannelPermissions(token: token)
                self.fetchChannelMembers(token: token)
                self.checkBanStatus(token: token)
            }
        }
    }

    @objc private func handleMessageTypingReceived(_ notification: Notification) {
        guard let eventClanId = Self.int64FromTypingUserInfo(notification.userInfo?["clanId"]),
              let eventChannelId = Self.int64FromTypingUserInfo(notification.userInfo?["channelId"]),
              let senderId = Self.int64FromTypingUserInfo(notification.userInfo?["senderId"]) else { return }
        let eventTopicId = Self.int64FromTypingUserInfo(notification.userInfo?["topicId"]) ?? 0

        if eventClanId != 0 && eventClanId != clanId { return }

        let eventLogicalId = eventTopicId != 0 ? eventTopicId : eventChannelId
        let localLogicalId = topicId != 0 ? topicId : channel.channelID
        guard eventLogicalId == localLogicalId else { return }

        if let myId = context.currentUser?.id, let myInt = Int64(myId), myInt == senderId { return }

        let d = (notification.userInfo?["senderDisplayName"] as? String) ?? ""
        let u = (notification.userInfo?["senderUsername"] as? String) ?? ""
        let label = !d.isEmpty ? d : (!u.isEmpty ? u : "…")

        remoteTypers[senderId] = RemoteTyperState(displayName: label, expires: Date().addingTimeInterval(3))
        restartTypingPruneTimerIfNeeded()
        refreshRemoteTypingIndicator()
    }

    private func restartTypingPruneTimerIfNeeded() {
        guard typingPruneTimer == nil else { return }
        let t = Foundation.Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] (_: Foundation.Timer) in
            self?.pruneExpiredTypersIfNeeded()
        }
        RunLoop.main.add(t, forMode: .common)
        typingPruneTimer = t
    }

    private func pruneExpiredTypersIfNeeded() {
        let now = Date()
        let beforeCount = remoteTypers.count
        remoteTypers = remoteTypers.filter { $0.value.expires > now }
        if remoteTypers.count != beforeCount {
            refreshRemoteTypingIndicator()
        }
        if remoteTypers.isEmpty {
            typingPruneTimer?.invalidate()
            typingPruneTimer = nil
        }
    }

    private func refreshRemoteTypingIndicator() {
        let names = remoteTypers.values.map(\.displayName).sorted()
        let line: String?
        switch names.count {
        case 0:
            line = nil
        case 1:
            line = String(format: L(L10n.ChannelMessages.userIsTyping), names[0])
        default:
            line = L(L10n.ChannelMessages.severalPeopleTyping)
        }
        remoteTypingLabel.text = line
        let shouldShow = line != nil
        remoteTypingLabel.isHidden = !shouldShow
        UIView.animate(withDuration: 0.2) {
            self.remoteTypingStripView.alpha = shouldShow ? 1 : 0
        } completion: { _ in
            self.remoteTypingStripView.isHidden = !shouldShow
        }
    }

    private func clearRemoteTypingState() {
        typingPruneTimer?.invalidate()
        typingPruneTimer = nil
        remoteTypers.removeAll()
        remoteTypingLabel.text = nil
        remoteTypingLabel.isHidden = true
        remoteTypingStripView.alpha = 0
        remoteTypingStripView.isHidden = true
    }

    private static func int64FromTypingUserInfo(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? NSNumber { return v.int64Value }
        if let v = value as? String { return Int64(v) }
        return nil
    }

    deinit {
        reconnectCatchUpTask?.cancel()
        typingPruneTimer?.invalidate()
        sendingFeedbackRefreshWorkItem?.cancel()
        notificationKeyboardReconcileWorkItem?.cancel()
        messageHistoryDisposable?.dispose()
        stateDisposables.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    private func bindMessageHistoryView() {
        messageHistoryDisposable?.dispose()
        let channelIdStr = storageChannelId
        messageHistoryDisposable = (context.account.postbox.messageHistoryView(channelId: channelIdStr)
            |> deliverOnMainQueue)
            .start(next: { [weak self] view in
                guard let self else { return }
                guard view.channelId == channelIdStr else { return }
                guard self.storageChannelId == channelIdStr else { return }
                let rows = view.messages.filter { $0.channelId == channelIdStr }
                let displays = self.buildDisplayMessages(from: rows)
                self.setMessages(displays)
            })
    }

    private func setMessages(_ v: [ChatMessageDisplay]) {
        let oldFirstId = messages.first(where: { !$0.isWelcome })?.id
        let oldLastId = messages.last?.id
        persistentMessages = normalizedDisplayOrder(v)
        messages = normalizedDisplayOrder(persistentMessages + ephemeralMessages)
        if !persistentMessages.isEmpty {
            skipRemoteFetchWhileTopicIsEmpty = false
        }
        let newFirstId = persistentMessages.first(where: { !$0.isWelcome })?.id
        let newLastId = persistentMessages.last?.id
        if newFirstId != oldFirstId { lastFetchedOlderMessageId = nil }
        if newLastId != oldLastId { lastFetchedNewerMessageId = nil }
        schedulePendingSendingFeedbackRefreshIfNeeded()
        needsReloadPipe.putNext(())
        markChannelAsReadOnEntryIfPossible()

        if let jumpId = pendingJumpToMessageId {
            isJumping = true
            pendingJumpToMessageId = nil
            DispatchQueue.main.async { [weak self] in
                self?.jumpToMessage(id: jumpId)
            }
        } else if pendingScrollToBottom && !v.isEmpty {
            pendingScrollToBottom = false
            DispatchQueue.main.async { [weak self] in
                self?.forceScrollToBottom()
            }
        }
    }

    private func pendingSendingFeedbackBeganAt(for record: MessageRecord, now: Date) -> Date {
        guard record.sendingState == .pending else { return record.createdAt }
        if let beganAt = pendingSendingFeedbackBeganAtByMessageId[record.id] {
            return beganAt
        }
        let beganAt = record.id.hasPrefix("pending-") ? record.createdAt : now
        pendingSendingFeedbackBeganAtByMessageId[record.id] = beganAt
        return beganAt
    }

    private func schedulePendingSendingFeedbackRefreshIfNeeded() {
        sendingFeedbackRefreshWorkItem?.cancel()
        sendingFeedbackRefreshWorkItem = nil

        let now = Date()
        let nextDelay = messages.compactMap { display -> TimeInterval? in
            guard display.sendingState == .pending, !display.showsSendingFeedback else { return nil }
            guard let beganAt = pendingSendingFeedbackBeganAtByMessageId[display.id] else { return nil }
            return max(0, Self.pendingSendFeedbackDelay - now.timeIntervalSince(beganAt))
        }.min()

        guard let nextDelay else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sendingFeedbackRefreshWorkItem = nil
            self.reloadDisplaysForPendingSendingFeedback()
        }
        sendingFeedbackRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay + 0.02, execute: workItem)
    }

    private func reloadDisplaysForPendingSendingFeedback() {
        let channelIdStr = storageChannelId
        let rows = context.account.postbox.read { tx in
            tx.getMessages(channelId: channelIdStr).filter { $0.channelId == channelIdStr }
        }
        setMessages(buildDisplayMessages(from: rows))
    }

    private func normalizedDisplayOrder(_ displays: [ChatMessageDisplay]) -> [ChatMessageDisplay] {
        Self.applyCombine(to: Self.sortMessagesLikeChannelStore(displays))
    }
    private func setChannelLabel(_ v: String) {
        if topicId != 0 { return }
        channelLabel = v
        needsReloadPipe.putNext(())
    }
    private func clearLastSeenMessageId() {
        guard lastSeenMessageId != nil else { return }
        lastSeenMessageId = nil
        metadataOnlyPipe.putNext(())
    }
    private func setHasMoreOlder(_ v: Bool) { hasMoreOlder = v; metadataOnlyPipe.putNext(()) }
    private func setHasMoreNewer(_ v: Bool) { hasMoreNewer = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoadingMore(_ v: Bool) { isLoadingMore = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoadingNewer(_ v: Bool) { isLoadingNewer = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoadingMessageContext(_ v: Bool) { isLoadingMessageContext = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; metadataOnlyPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; metadataOnlyPipe.putNext(()) }

    private var hasCompletedInitialFetch = false
    private var didApplyBadgeLastSeen = false
    private static let initialEmptyMessageRetryDelaysNanoseconds: [UInt64] = [
        600_000_000,
        1_200_000_000
    ]

    private static let initialFetchFailureRetryDelaysNanoseconds: [UInt64] = [
        600_000_000,
        1_200_000_000,
        2_400_000_000
    ]

    private func performInitialMessageFetchIfNeeded(token: String) {
        guard !hasCompletedInitialFetch else { return }
        hasCompletedInitialFetch = true
        if startupJumpTargetForInitialFetch != nil {
            startupJumpTargetForInitialFetch = nil
            return
        }
        fetchMessages(token: token)
    }

    func start() {
        if let initialMessageJumpTargetId {
            startupJumpTargetForInitialFetch = initialMessageJumpTargetId
        }
        if topicId == 0 {
            context.currentClanId = clanId
            context.currentChannel = channel
            ActiveChannelTracker.currentChannelId = channel.channelID
            Self.removeDeliveredNotifications(forChannelId: channel.channelID)
        }

        if channel.channelLabel.isEmpty || channel.type == 0 {
            resolveChannelLabelFromCache()
        }

        let channelIdStr = storageChannelId
        let messagesKeyInvalid = topicId == 0 && channel.channelID == 0
        var skipInitialRemoteFetchForEmptyTopic = false

        if messagesKeyInvalid {
            setMessages([])
            setIsLoading(false)
        } else {
            restorePinnedStateFromPostboxIfNeeded()
            let cachedMessages = context.account.postbox.read { tx in
                tx.getMessages(channelId: channelIdStr).filter { $0.channelId == channelIdStr }
            }
            let hasCache = !cachedMessages.isEmpty
            skipInitialRemoteFetchForEmptyTopic = shouldSkipRemoteFetchForEmptyTopic(
                hadCachedMessages: !messages.isEmpty,
                hadCachedInPostbox: hasCache
            )
            if skipInitialRemoteFetchForEmptyTopic {
                hasCompletedInitialFetch = true
                setHasMoreOlder(false)
                setHasMoreNewer(false)
            }
            if !hasCache && NetworkMonitor.shared.isConnected && !skipInitialRemoteFetchForEmptyTopic {
                setIsLoading(true)
            } else {
                setIsLoading(false)
            }

            bindMessageHistoryView()
        }
        stateDisposables.add(
            (self.context.engine.clanData.clanRolesUpdated.signal()
                |> deliverOnMainQueue)
                .start(next: { [weak self] updatedClanId in
                    guard let self, updatedClanId == self.clanId, self.clanId != 0 else { return }
                    self.context.rolePermissions.invalidateRolesCache()
                    if self.isViewLoaded {
                        self.messagesNode.forceUpdateAllMessageItems()
                    }
                })
        )
        stateDisposables.add(
            (self.context.account.postbox.channelMetaView(channelId: channel.channelID) |> deliverOnMainQueue)
                .start(next: { [weak self] view in
                    guard let self else { return }
                    self.channelMeta = view.record
                })
        )
        ensureParentChannelMetaSubscription()

        startBadgeCountLastSeenRefresh()

        let shouldSkipInitialRemoteFetchForEmptyTopic = skipInitialRemoteFetchForEmptyTopic
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.topicId == 0 && self.channel.channelID == 0 {
                self.setIsLoading(false)
                return
            }
            if shouldSkipInitialRemoteFetchForEmptyTopic {
                self.setHasMoreOlder(false)
                self.setHasMoreNewer(false)
                self.setIsLoading(false)
                self.setIsLoadingMessageContext(false)
            }
            if !NetworkMonitor.shared.isConnected {
                self.setIsLoading(false)
                return
            }

            let immediateToken: String? = {
                if let t = self.context.session?.token, !t.isEmpty { return t }
                if let t = SessionStore.load()?.token, !t.isEmpty { return t }
                return nil
            }()
            if let immediateToken, !self.hasCompletedInitialFetch {
                self.performInitialMessageFetchIfNeeded(token: immediateToken)
            }

            var token = await self.context.getTokenPreferringCachedSkipSessionReadyWait()
            if token == nil {
                await self.context.waitForSessionReady()
                token = await self.context.getToken()
            }
            guard let token else {
                self.setIsLoading(false)
                return
            }
            if !self.hasCompletedInitialFetch {
                self.performInitialMessageFetchIfNeeded(token: token)
            }
            await self.waitForSocketConnected()
            self.joinChat()
            self.refreshPinnedMessagesFromServer()
            self.fetchNotificationSetting(token: token)
            self.fetchChannelPermissions(token: token)
            self.fetchChannelMembers(token: token)
            self.checkBanStatus(token: token)
            self.resolveChannelLabelFromNetwork(token: token)
        }
    }

    private func startBadgeCountLastSeenRefresh() {
        guard channel.channelID != 0, !didApplyBadgeLastSeen else { return }

        if let cached = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID),
           cached.hasLastSeenMessage, cached.lastSeenMessage.id != 0 {
            didApplyBadgeLastSeen = true
            applyLastSeen(from: cached)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var token: String? = {
                if let t = self.context.session?.token, !t.isEmpty { return t }
                if let t = SessionStore.load()?.token, !t.isEmpty { return t }
                return nil
            }()
            if token == nil {
                token = await self.context.getTokenPreferringCachedSkipSessionReadyWait()
            }
            guard let token else { return }
            await self.applyLastSeenFromBadgeCountNetwork(token: token)
        }
    }

    @MainActor
    private func applyLastSeenFromBadgeCountNetwork(token: String) async {
        guard !didApplyBadgeLastSeen else { return }
        guard channel.channelID != 0 else { return }
        do {
            let response = try await context.account.network.listChannelBadgeCount(clanId: clanId, token: token)
            guard let desc = response.channeldesc.first(where: { $0.channelID == channel.channelID }) else {
                return
            }
            didApplyBadgeLastSeen = true
            applyLastSeen(from: desc)
        } catch {
        }
    }

    @MainActor
    private func applyLastSeen(from desc: Mezon_Api_ChannelDescription) {
        guard desc.hasLastSeenMessage, desc.lastSeenMessage.id != 0 else { return }
        let newSeenId = "\(desc.lastSeenMessage.id)"
        guard newSeenId != self.lastSeenMessageId else { return }
        self.lastSeenMessageId = newSeenId
        if self.hasPerformedInitialUnreadScroll {
            self.scrollToUnreadLine(lastSeenId: newSeenId)
        } else {
            self.shouldScrollToBottom = false
        }
    }

    private func resolveChannelLabelFromCache() {
        if clanId == 0 {
            if let cached = context.account.postbox.getDMChannelDescription(channelId: channel.channelID) {
                channel = cached
                if !cached.channelLabel.isEmpty {
                    setChannelLabel(cached.channelLabel)
                }
                syncChannelToComposer()
            }
        } else {
            if let (_, cached) = context.account.postbox.getChannelDescription(channelId: channel.channelID) {
                channel = cached
                if !cached.channelLabel.isEmpty {
                    setChannelLabel(cached.channelLabel)
                }
                syncChannelToComposer()
            }
        }
        ensureParentChannelMetaSubscription()
    }

    private func ensureParentChannelMetaSubscription() {
        guard !didStartParentChannelMetaView else { return }
        guard channel.type == MezonConstants.ChannelType.thread.rawValue, channel.parentID != 0 else { return }
        didStartParentChannelMetaView = true
        stateDisposables.add(
            (self.context.account.postbox.channelMetaView(channelId: channel.parentID)
                |> deliverOnMainQueue)
                .start(next: { [weak self] view in
                    guard let self else { return }
                    self.parentChannelMeta = view.record
                    self.metadataOnlyPipe.putNext(())
                })
        )
    }

    private func completeChannelHydrationAfterMetadataUpgrade() {
        ensureParentChannelMetaSubscription()
        fetchChannelMembers()
        metadataOnlyPipe.putNext(())
    }

    private func resolveChannelLabelFromNetwork(token: String) {
        guard channel.channelLabel.isEmpty || channel.type == 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 500_000_000)
            let fullyResolved = self.tryResolveLabelFromPostbox()
            self.ensureParentChannelMetaSubscription()
            self.fetchChannelMembers()
            self.metadataOnlyPipe.putNext(())
            if fullyResolved { return }

            let typeWasUnknown = self.channel.type == 0
            do {
                if self.clanId == 0 {
                    let channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                    if let found = channels.first(where: { $0.channelID == self.channel.channelID }) {
                        self.channel = found
                        self.setChannelLabel(found.channelLabel)
                        self.syncChannelToComposer()
                        self.completeChannelHydrationAfterMetadataUpgrade()
                        if typeWasUnknown { self.rejoinChatIfChannelMetadataChanged() }
                        return
                    }
                }
                if self.clanId != 0 {
                    let descs = try await self.context.account.network.listChannelDescs(clanId: self.clanId, token: token)
                    if let found = descs.first(where: { $0.channelID == self.channel.channelID }) {
                        self.channel = found
                        if !found.channelLabel.isEmpty {
                            self.setChannelLabel(found.channelLabel)
                        }
                        self.syncChannelToComposer()
                        self.completeChannelHydrationAfterMetadataUpgrade()
                        if typeWasUnknown { self.rejoinChatIfChannelMetadataChanged() }
                        return
                    }
                    if self.channel.parentID != 0,
                       let thread = try await self.context.account.network.fetchThreadDesc(
                           threadId: self.channel.channelID,
                           parentChannelId: self.channel.parentID,
                           clanId: self.clanId,
                           token: token
                       ) {
                        let resolved = self.normalizeThreadDescription(
                            thread,
                            threadChannelId: self.channel.channelID,
                            parentChannelId: self.channel.parentID,
                            threadLabel: nil
                        )
                        self.channel = resolved
                        if !resolved.channelLabel.isEmpty {
                            self.setChannelLabel(resolved.channelLabel)
                        }
                        self.syncChannelToComposer()
                        self.completeChannelHydrationAfterMetadataUpgrade()
                        if typeWasUnknown { self.rejoinChatIfChannelMetadataChanged() }
                        return
                    }
                }
                let channels = try await self.context.account.network.listChannelByUserId(token: token)
                if let found = channels.channeldesc.first(where: { $0.channelID == self.channel.channelID }) {
                    self.channel = found
                    if !found.channelLabel.isEmpty {
                        self.setChannelLabel(found.channelLabel)
                    }
                    self.syncChannelToComposer()
                    self.completeChannelHydrationAfterMetadataUpgrade()
                    if typeWasUnknown { self.rejoinChatIfChannelMetadataChanged() }
                }
            } catch {
            }
        }
    }

    private func tryResolveLabelFromPostbox() -> Bool {
        let typeWasUnknown = channel.type == 0
        if clanId == 0 {
            if let cached = context.account.postbox.getDMChannelDescription(channelId: channel.channelID) {
                channel = cached
                if !cached.channelLabel.isEmpty {
                    setChannelLabel(cached.channelLabel)
                }
                syncChannelToComposer()
                if typeWasUnknown && cached.type != 0 { rejoinChatIfChannelMetadataChanged() }
                return !cached.channelLabel.isEmpty && cached.type != 0
            }
        } else {
            if let (_, cached) = context.account.postbox.getChannelDescription(channelId: channel.channelID) {
                channel = cached
                if !cached.channelLabel.isEmpty {
                    setChannelLabel(cached.channelLabel)
                }
                syncChannelToComposer()
                if typeWasUnknown && cached.type != 0 { rejoinChatIfChannelMetadataChanged() }
                return !cached.channelLabel.isEmpty && cached.type != 0
            }
        }
        return false
    }

    private func rejoinChatIfChannelMetadataChanged() {
        guard context.account.socket.isConnected else { return }
        joinChat()
    }

    private func syncChannelToComposer() {
        sendInputViewController.syncStoredDraftIdentity(channel: channel, topicId: topicId)
    }

    static func removeDeliveredNotifications(forChannelId channelId: Int64) {
        let center = UNUserNotificationCenter.current()
        let channelIdStr = "\(channelId)"

        center.getDeliveredNotifications { notifications in
            let matchingIds = notifications
                .filter { notification in
                    let userInfo = notification.request.content.userInfo
                    if let ch = userInfo["channel"] as? String { return ch == channelIdStr }
                    if let ch = userInfo["channel"] { return "\(ch)" == channelIdStr }
                    return false
                }
                .map { $0.request.identifier }

            guard !matchingIds.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: matchingIds)

            let shared = UserDefaults(suiteName: "group.mezon.mobile")
            let current = shared?.integer(forKey: "badgeCount") ?? 0
            let newCount = max(0, current - matchingIds.count)
            shared?.set(newCount, forKey: "badgeCount")

            DispatchQueue.main.async {
                if #available(iOS 16.0, *) {
                    UNUserNotificationCenter.current().setBadgeCount(newCount)
                } else {
                    UIApplication.shared.applicationIconBadgeNumber = newCount
                }
            }
        }
    }

    func onLeave() {
        reconnectCatchUpTask?.cancel()
        reconnectCatchUpTask = nil
        clearRemoteTypingState()
        context.currentChannel = nil
        ActiveChannelTracker.currentChannelId = 0
        messageHistoryDisposable?.dispose()
        stateDisposables.dispose()
    }

    func handleBroughtForwardFromNotificationDeepLink() {
        prepareForNotificationNavigation()
        lastMarkedAsReadMessageId = nil
        if !messages.isEmpty {
            markChannelAsRead()
        }
        let previousCatchUp = reconnectCatchUpTask
        previousCatchUp?.cancel()
        reconnectCatchUpTask = Task { @MainActor [weak self] in
            _ = await previousCatchUp?.value
            guard let self, !Task.isCancelled else { return }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            await self.joinChatAndWaitUntilSent()
            if self.newestServerMessageId() == nil {
                self.fetchMessages(token: token)
            } else {
                await self.catchUpMessagesAfterReconnect(token: token)
            }
        }
    }

    func prepareForNotificationNavigation() {
        shouldReconcileKeyboardAfterNotificationNavigation = true
        collapseNotificationNavigationComposerOverlays()
        markNextFetchPrefersHTTPFirst()
        reconcileKeyboardAfterNotificationNavigationIfNeeded()
    }

    func markNextFetchPrefersHTTPFirst() {
        nextFetchPrefersHTTPFirst = true
    }

    func applyMergedChannelDescriptionFromChannelListLoadIfNeeded(
        _ full: Mezon_Api_ChannelDescription?,
        parentChannelName: String? = nil
    ) {
        guard let full, full.channelID == channel.channelID else {
            _ = tryResolveLabelFromPostbox()
            ensureParentChannelMetaSubscription()
            metadataOnlyPipe.putNext(())
            return
        }
        let typeWasUnknown = channel.type == 0
        channel = full
        if !full.channelLabel.isEmpty {
            setChannelLabel(full.channelLabel)
        }
        if let parentChannelName, !parentChannelName.isEmpty {
            initialParentName = parentChannelName
        }
        sendInputViewController.channel = channel
        syncChannelToComposer()
        completeChannelHydrationAfterMetadataUpgrade()
        if typeWasUnknown { rejoinChatIfChannelMetadataChanged() }
        metadataOnlyPipe.putNext(())
    }

    private func markChannelAsReadOnEntryIfPossible() {
        guard !didMarkChannelAsReadForCurrentAppearance else { return }
        guard topicId == 0, pendingJumpToMessageId == nil else { return }
        guard viewIfLoaded?.window != nil,
              UIApplication.shared.applicationState == .active else { return }
        guard newestServerMessageId() != nil
            || channel.hasLastSentMessage && channel.lastSentMessage.id != 0 else { return }
        didMarkChannelAsReadForCurrentAppearance = true
        markChannelAsRead()
    }

    private func markChannelAsRead() {
        var latestServerMessageId: Int64?
        for display in messages.reversed() where !display.isWelcome {
            if let id = Int64(display.message.id), id != 0 {
                latestServerMessageId = id
                break
            }
        }
        if latestServerMessageId == nil,
           channel.hasLastSentMessage,
           channel.lastSentMessage.id != 0 {
            latestServerMessageId = channel.lastSentMessage.id
        }
        guard let messageId = latestServerMessageId else { return }

        if let already = lastMarkedAsReadMessageId, messageId <= already { return }

        guard context.account.socket.isConnected else {
            pendingMarkAsRead = true
            return
        }
        lastMarkedAsReadMessageId = messageId
        pendingMarkAsRead = false

        let channelUnreadCount = channel.countMessUnread

        let mode: Int32
        if clanId != 0 {
            mode = MezonConstants.ChannelStreamMode.channel.rawValue
        } else if channel.type == MezonConstants.ChannelType.dm.rawValue {
            mode = MezonConstants.ChannelStreamMode.dm.rawValue
        } else {
            mode = MezonConstants.ChannelStreamMode.group.rawValue
        }

        let now = UInt32(Date().timeIntervalSince1970)
        context.account.socket.writeLastSeenMessage(
            clanId: clanId,
            channelId: channel.channelID,
            mode: mode,
            messageId: messageId,
            timestampSeconds: now,
            badgeCount: 0
        )

        NotificationCenter.default.post(
            name: Notification.Name("MezonChannelMarkedAsRead"),
            object: nil,
            userInfo: [
                "channelId": channel.channelID,
                "clanId": clanId,
                "channelUnreadCount": channelUnreadCount,
                "mode": mode,
                "messageId": String(messageId),
                "timestampSeconds": now
            ]
        )
    }

    private func hasCachedMessagesInPostbox() -> Bool {
        let channelIdStr = storageChannelId
        return context.account.postbox.read { tx in
            !tx.getMessages(channelId: channelIdStr).isEmpty
        }
    }

    private func shouldSkipRemoteFetchForEmptyTopic(hadCachedMessages: Bool, hadCachedInPostbox: Bool) -> Bool {
        skipRemoteFetchWhileTopicIsEmpty
            && !hadCachedMessages
            && !hadCachedInPostbox
            && (topicId != 0 || pendingTopicCreationMessageId != nil)
    }

    private func newestServerMessageId() -> Int64? {
        persistentMessages.reversed().lazy.compactMap { display -> Int64? in
            guard !display.isWelcome,
                  !display.message.id.hasPrefix("pending-"),
                  let id = Int64(display.message.id),
                  id != 0 else {
                return nil
            }
            return id
        }.first
    }

    private func catchUpMessagesAfterReconnect(token: String) async {
        guard !isCatchingUpAfterReconnect else { return }
        guard pendingJumpToMessageId == nil else { return }
        guard var cursor = newestServerMessageId() else {
            fetchMessages(token: token)
            return
        }

        isCatchingUpAfterReconnect = true
        let wasAtBottom = messagesNode.isAtBottom
        let visibleMessageAnchor = wasAtBottom ? nil : messagesNode.captureVisibleMessageAnchor()
        let initialUserScrollGeneration = messagesNode.userScrollGeneration
        if !wasAtBottom {
            shouldScrollToBottom = false
        }
        setIsLoadingNewer(true)

        var reachedPresent = false
        defer {
            isCatchingUpAfterReconnect = false
            setIsLoadingNewer(false)

            let canRestorePosition = !Task.isCancelled
                && viewIfLoaded?.window != nil
                && UIApplication.shared.applicationState != .background
                && messagesNode.userScrollGeneration == initialUserScrollGeneration

            if canRestorePosition, let visibleMessageAnchor {
                messagesNode.listView.addAfterTransactionsCompleted { [weak self] in
                    guard let self,
                          self.messagesNode.userScrollGeneration == initialUserScrollGeneration else {
                        return
                    }
                    self.messagesNode.restoreVisibleMessageAnchor(visibleMessageAnchor)
                }
            } else if reachedPresent, wasAtBottom, canRestorePosition {
                messagesNode.listView.addAfterTransactionsCompleted { [weak self] in
                    guard let self,
                          self.messagesNode.userScrollGeneration == initialUserScrollGeneration else {
                        return
                    }
                    self.forceScrollToBottom {
                        self.markChannelAsRead()
                    }
                }
            }
        }

        let pageSize: Int32 = 30
        let maxCatchUpPages = 20
        // The channel join has no acknowledgement. Require two quiet HTTP passes so a
        // message created while the realtime subscription is being restored is covered.
        var consecutiveNoAdvancePasses = 0
        var pagesFetched = 0
        var hitPageCap = false
        do {
            while !Task.isCancelled {
                guard UIApplication.shared.applicationState != .background else { break }
                guard pagesFetched < maxCatchUpPages else {
                    hitPageCap = true
                    break
                }
                let response = try await context.account.network.listChannelMessages(
                    clanId: clanId,
                    channelId: channel.channelID,
                    messageId: cursor,
                    direction: 1,
                    limit: pageSize,
                    topicId: topicId,
                    token: token,
                    preferHTTPFirst: true
                )
                pagesFetched += 1

                let validMessages = response.messages.filter { $0.messageID != 0 }
                if !validMessages.isEmpty {
                    context.account.postbox.write { tx in
                        tx.addMessages(validMessages.map { self.messageRecord(from: $0) })
                    }
                }

                let newerMessages = validMessages.filter {
                    $0.messageID > cursor
                }
                guard let nextCursor = newerMessages.map(\.messageID).max(),
                      nextCursor > cursor else {
                    consecutiveNoAdvancePasses += 1
                    if consecutiveNoAdvancePasses >= 2 {
                        reachedPresent = true
                        break
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }

                consecutiveNoAdvancePasses = 0
                cursor = nextCursor
            }

            guard !Task.isCancelled else { return }
            if reachedPresent {
                setHasMoreNewer(false)
            } else if hitPageCap {
                setHasMoreNewer(true)
                lastFetchedNewerMessageId = nil
            }
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            setHasMoreNewer(true)
            lastFetchedNewerMessageId = nil
            SentryLogger.capture(error, extras: [
                "where": "ChatViewController.catchUpMessagesAfterReconnect",
                "channelId": channel.channelID,
                "clanId": clanId,
                "anchorMessageId": cursor,
            ])
        }
    }

    func fetchMessages(token: String? = nil) {
        if initialMessageJumpTargetId != nil || pendingJumpToMessageId != nil { return }
        let hadCachedMessages = !messages.isEmpty
        let hadCachedInPostbox = hasCachedMessagesInPostbox()
        if shouldSkipRemoteFetchForEmptyTopic(
            hadCachedMessages: hadCachedMessages,
            hadCachedInPostbox: hadCachedInPostbox
        ) {
            setHasMoreOlder(false)
            setHasMoreNewer(false)
            setIsLoading(false)
            setIsLoadingMessageContext(false)
            setErrorMessage(nil)
            return
        }
        if !NetworkMonitor.shared.isConnected {
            setIsLoading(false)
            return
        }
        let showsCacheRefreshLoader = hadCachedMessages || hadCachedInPostbox
        if !showsCacheRefreshLoader {
            setIsLoading(true)
        } else {
            setIsLoadingMessageContext(true)
        }
        setErrorMessage(nil)
        let preferHTTPFirst = true
        nextFetchPrefersHTTPFirst = false

        Task { @MainActor in
            defer {
                self.setIsLoading(false)
                if showsCacheRefreshLoader {
                    self.setIsLoadingMessageContext(false)
                }
            }
            let resolvedToken: String?
            if let token { resolvedToken = token } else { resolvedToken = await self.context.getTokenPreferringCachedSkipSessionReadyWait() }
            guard let token = resolvedToken else { return }
            var fetchAttempt = 0
            while true {
                do {
                    func loadInitialMessages() async throws -> Mezon_Api_ChannelMessageList {
                        var response = try await self.context.account.network.listChannelMessages(
                            clanId: clanId,
                            channelId: channel.channelID,
                            messageId: 0,
                            direction: 2,
                            limit: 30,
                            topicId: self.topicId,
                            token: token,
                            preferHTTPFirst: preferHTTPFirst
                        )
                        if response.messages.isEmpty {
                            response = try await self.context.account.network.listChannelMessages(
                                clanId: clanId,
                                channelId: channel.channelID,
                                messageId: 0,
                                direction: 3,
                                limit: 30,
                                topicId: self.topicId,
                                token: token,
                                preferHTTPFirst: preferHTTPFirst
                            )
                        }
                        return response
                    }

                    var response = try await loadInitialMessages()
                    if response.messages.isEmpty && !hadCachedMessages && !hadCachedInPostbox {
                        for delay in Self.initialEmptyMessageRetryDelaysNanoseconds {
                            guard response.messages.isEmpty,
                                  NetworkMonitor.shared.isConnected,
                                  !Task.isCancelled else {
                                break
                            }
                            try await Task.sleep(nanoseconds: delay)
                            response = try await loadInitialMessages()
                        }
                    }
                    self.setHasMoreOlder(response.messages.count > 1)
                    let records = response.messages.map { self.messageRecord(from: $0) }
                    if records.isEmpty && (hadCachedMessages || hadCachedInPostbox) {
                        return
                    }
                    self.context.account.postbox.write { tx in
                        tx.replaceAllMessages(records, channelId: self.storageChannelId)
                    }
                    return
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        return
                    }
                    if fetchAttempt < Self.initialFetchFailureRetryDelaysNanoseconds.count,
                       NetworkMonitor.shared.isConnected,
                       !hadCachedMessages, !hadCachedInPostbox {
                        let delay = Self.initialFetchFailureRetryDelaysNanoseconds[fetchAttempt]
                        fetchAttempt += 1
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    SentryLogger.capture(error, extras: [
                        "where": "ChatViewController.fetchMessages",
                        "channelId": channel.channelID,
                        "clanId": clanId,
                        "topicId": self.topicId,
                    ])
                    self.setErrorMessage(error.localizedDescription)
                    return
                }
            }
        }
    }

    private static func oldestServerMessageId(in messages: [ChatMessageDisplay]) -> Int64? {
        for item in messages where !item.isWelcome {
            if let id = Int64(item.message.id), id != 0 { return id }
        }
        return nil
    }

    private static func newestServerMessageId(in messages: [ChatMessageDisplay]) -> Int64? {
        for item in messages.reversed() where !item.isWelcome {
            if let id = Int64(item.message.id), id != 0 { return id }
        }
        return nil
    }

    func fetchOlderMessages() {
        guard hasMoreOlder, !isLoadingMore else { return }
        guard messages.count >= 10 else { return }

        guard let msgId = Self.oldestServerMessageId(in: messages) else {
            setHasMoreOlder(false)
            return
        }

        guard msgId != lastFetchedOlderMessageId else { return }
        lastFetchedOlderMessageId = msgId

        setIsLoadingMore(true)
        Task { @MainActor in
            defer { self.setIsLoadingMore(false) }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: clanId, channelId: channel.channelID,
                    messageId: msgId, direction: 3, limit: 30, topicId: self.topicId, token: token
                )
                self.setHasMoreOlder(!response.messages.isEmpty)
                if !response.messages.isEmpty {
                    self.context.account.postbox.write { tx in
                        tx.addMessages(response.messages.map { self.messageRecord(from: $0) })
                    }
                }
            } catch {
                self.lastFetchedOlderMessageId = nil
                if error is CancellationError || Task.isCancelled { return }
                SentryLogger.capture(error, extras: [
                    "where": "ChatViewController.fetchOlderMessages",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                    "anchorMessageId": msgId,
                ])
            }
        }
    }

    func fetchNewerMessages() {
        guard hasMoreNewer, !isLoadingNewer else { return }
        guard messages.count >= 10 else { return }
        guard let msgId = Self.newestServerMessageId(in: messages) else { return }

        guard msgId != lastFetchedNewerMessageId else { return }
        lastFetchedNewerMessageId = msgId

        shouldScrollToBottom = false
        setIsLoadingNewer(true)
        Task { @MainActor in
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else {
                self.lastFetchedNewerMessageId = nil
                self.setIsLoadingNewer(false)
                return
            }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: clanId, channelId: channel.channelID,
                    messageId: msgId, direction: 1, limit: 30, topicId: self.topicId, token: token
                )
                self.setHasMoreNewer(!response.messages.isEmpty)
                if !response.messages.isEmpty {
                    self.context.account.postbox.write { tx in
                        tx.addMessages(response.messages.map { self.messageRecord(from: $0) })
                    }
                }
                self.setIsLoadingNewer(false)
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "ChatViewController.fetchNewerMessages",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                    "anchorMessageId": msgId,
                ])
                self.lastFetchedNewerMessageId = nil
                self.setHasMoreNewer(true)
                self.setIsLoadingNewer(false)
            }
        }
    }

    private func jumpToPresent() {
        shouldScrollToBottom = true
        pendingScrollToBottom = true
        setHasMoreNewer(false)

        let hadCachedMessages = !messages.isEmpty
        let hadCachedInPostbox = hasCachedMessagesInPostbox()
        Task { @MainActor in
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else {
                self.pendingScrollToBottom = false
                return
            }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: clanId, channelId: channel.channelID,
                    messageId: 0, direction: 2, limit: 30, topicId: self.topicId, token: token
                )
                self.setHasMoreOlder(response.messages.count > 1)
                if response.messages.isEmpty && (hadCachedMessages || hadCachedInPostbox) {
                    return
                }
                self.context.account.postbox.write { tx in
                    tx.replaceAllMessages(
                        response.messages.map { self.messageRecord(from: $0) },
                        channelId: self.storageChannelId
                    )
                }
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "ChatViewController.jumpToPresent",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                ])
                self.pendingScrollToBottom = false
                self.setErrorMessage(error.localizedDescription)
            }
        }
    }


    private func fetchNotificationSetting(token: String? = nil) {
        let channelId = channel.channelID
        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getTokenPreferringCachedSkipSessionReadyWait() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                let response = try await self.context.account.network.getNotificationChannel(channelId: channelId, token: token)
                let record = NotificationSettingRecord(from: response)
                self.context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }
            } catch {
            }
        }
    }

    private func fetchChannelPermissions(token: String? = nil) {
        guard clanId != 0 else { return }
        let parentId = createThreadParentChannelId()
        if parentId != 0 {
            context.rolePermissions.ensureChannelPermissions(clanId: clanId, channelId: parentId)
        }
        if channel.channelID != parentId, channel.channelID != 0 {
            context.rolePermissions.ensureChannelPermissions(clanId: clanId, channelId: channel.channelID)
        }
    }

    private func fetchChannelMembers(token: String? = nil) {
        let channelId = channel.channelID
        let channelType: Int32 = clanId == 0
            ? (channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue)
            : (channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue)

        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getTokenPreferringCachedSkipSessionReadyWait() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                if channel.parentID != 0 {
                    let parentChannelType = self.context.engine.clanData.resolvedListChannelUsersType(channelId: channel.parentID)
                    let parentResponse = try await self.context.account.network.listChannelUsers(
                        clanId: clanId,
                        channelId: channel.parentID,
                        channelType: parentChannelType,
                        token: token
                    )
                    let parentMembers = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                        parentResponse.channelUsers, postbox: self.context.account.postbox)
                    let parentHasCached = !(self.context.account.postbox.read { tx in
                        tx.getChannelMeta(channelId: self.channel.parentID)?.members ?? []
                    }).isEmpty
                    if !(parentMembers.isEmpty && parentHasCached) {
                        self.context.account.postbox.write { tx in
                            tx.updateChannelMembers(parentMembers, channelId: self.channel.parentID)
                        }
                    }
                }

                if channel.channelPrivate != 0 || channel.parentID != 0 {
                    let isDmOrGroup = clanId == 0 && (
                        channelType == MezonConstants.ChannelType.dm.rawValue
                            || channelType == MezonConstants.ChannelType.group.rawValue
                    )
                    if isDmOrGroup {
                        var synced = false
                        do {
                            let uc = try await self.context.account.network.listChannelUsersUC(
                                channelId: channelId, limit: 500, token: token)
                            if !uc.userIds.isEmpty {
                                let labels = channel.dmMemberLabelsForChannelList()
                                self.context.account.postbox.write { tx in
                                    tx.applyAllUsersAddChannelResponse(
                                        uc, channelId: channelId, dmMemberLabelByUserId: labels)
                                }
                                synced = true
                            }
                        } catch {
                        }
                        if !synced {
                            do {
                                let response = try await self.context.account.network.listChannelUsers(
                                    clanId: clanId,
                                    channelId: channelId,
                                    channelType: channelType,
                                    token: token
                                )
                                let members = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                                    response.channelUsers, postbox: self.context.account.postbox)
                                let hasCached = !(self.context.account.postbox.read { tx in
                                    tx.getChannelMeta(channelId: channelId)?.members ?? []
                                }).isEmpty
                                if !(members.isEmpty && hasCached) {
                                    self.context.account.postbox.write { tx in
                                        tx.updateChannelMembers(members, channelId: channelId)
                                    }
                                }
                            } catch {
                            }
                        }
                    } else {
                        let response = try await self.context.account.network.listChannelUsers(
                            clanId: clanId,
                            channelId: channelId,
                            channelType: channelType,
                            token: token
                        )
                        let members = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                            response.channelUsers, postbox: self.context.account.postbox)
                        let hasCached = !(self.context.account.postbox.read { tx in
                            tx.getChannelMeta(channelId: channelId)?.members ?? []
                        }).isEmpty
                        if !(members.isEmpty && hasCached) {
                            self.context.account.postbox.write { tx in
                                tx.updateChannelMembers(members, channelId: channelId)
                            }
                        }
                    }
                }
            } catch {
            }
        }
    }

    private func checkBanStatus(token: String? = nil) {
        let channelId = channel.channelID
        let isPublic = clanId != 0 && channel.parentID == 0 && channel.channelPrivate == 0
        guard isPublic else { return }

        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getTokenPreferringCachedSkipSessionReadyWait() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                let response = try await self.context.account.network.isBanned(channelId: channelId, token: token)
                self.context.account.postbox.write { tx in
                    tx.updateBanStatus(isBanned: response.isBanned, expiredBanTime: response.expiredBanTime, channelId: channelId)
                }
            } catch {
            }
        }
    }

    private var isDirectMessagePeerBlocked: Bool {
        guard channel.type == MezonConstants.ChannelType.dm.rawValue else { return false }
        guard let peerId = channel.userIds.first, peerId != 0 else { return false }
        return context.engine.friendsData.blockedUserIds().contains(peerId)
    }

    private func resolvedThreadCreatorName() -> String {
        guard channel.type == MezonConstants.ChannelType.thread.rawValue else { return "" }
        let creatorId = channel.creatorID
        if creatorId != 0 {
            let userId = String(creatorId)
            if let member = context.account.postbox.read({ tx in
                tx.getClanMembers(clanId: clanId).first(where: { $0.userId == creatorId })
            }) {
                let clanNick = member.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clanNick.isEmpty { return clanNick }
                let displayName = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !displayName.isEmpty { return displayName }
                let username = member.username.trimmingCharacters(in: .whitespacesAndNewlines)
                if !username.isEmpty { return username }
            }
            if let currentUser = context.currentUser, currentUser.id == userId {
                let displayName = currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !displayName.isEmpty { return displayName }
                let username = currentUser.username.trimmingCharacters(in: .whitespacesAndNewlines)
                if !username.isEmpty { return username }
            }
            if let profile = context.account.postbox.read({ $0.getProfile(userId: userId) }) {
                if let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
                    return displayName
                }
                let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
                if !username.isEmpty { return username }
            }
        }
        return channel.creatorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentState: ChatState {
        let labelFromMeta = parentChannelMeta?.label
        let resolvedParentName =
            (labelFromMeta?.isEmpty == false) ? labelFromMeta : initialParentName

        return ChatState(
            messages: messages,
            channelLabel: channelLabel,
            channelType: channel.type,
            isPrivate: channel.channelPrivate != 0,
            isAgeRestricted: channel.ageRestricted != 0,
            isDM: clanId == 0,
            isPeerBlocked: isDirectMessagePeerBlocked,
            dmPeerUsername: channel.usernames.first ?? "",
            dmPeerDisplayName: channel.displayNames.first ?? "",
            dmAvatarURL: channel.avatars.first ?? "",
            dmGroupAvatarURL: channel.channelAvatar,
            threadCreatorName: resolvedThreadCreatorName(),
            hasMoreOlder: hasMoreOlder,
            hasMoreNewer: hasMoreNewer,
            isLoadingMore: isLoadingMore,
            isLoadingNewer: isLoadingNewer,
            isLoadingMessageContext: isLoadingMessageContext,
            isLoading: isLoading,
            errorMessage: errorMessage,
            lastSeenMessageId: lastSeenMessageId,
            currentUserId: context.currentUser?.id,
            parentName: resolvedParentName
        )
    }

    private static func messageUpdateToken(_ m: ChatMessageDisplay) -> String {
        let edited = m.message.editedAt.map { String($0.timeIntervalSince1970) } ?? ""
        let presignHash = PresignFinishContent.parseKeys(from: m.rawContentData ?? Data())?.joined(separator: ",") ?? ""
        let att = m.attachments
            .map {
                "\($0.url)|\($0.filename)|\($0.filetype)|\($0.isUploading)|\($0.uploadFailed)|\($0.isPresignPending)"
            }
            .joined(separator: ";")
        let pin = m.message.isPinned ? "1" : "0"
        let pollHash: String
        if let pd = m.pollData {
            let sortedCounts = pd.answerCounts.sorted(by: { $0.key < $1.key })
            let countStrings = sortedCounts.map { "\($0.key):\($0.value)" }
            let countJoined = countStrings.joined(separator: ",")
            pollHash = "\(pd.totalVotes)|\(countJoined)"
        } else {
            pollHash = ""
        }

        let embedHash: String = {
            let embeds = m.parsedContent.embeds
            guard !embeds.isEmpty else { return "" }
            return embeds.map { embed in
                let fields = embed.fields.map { "\($0.name):\($0.value)" }.joined(separator: ",")
                let buttons = embed.actionRows.flatMap { $0.buttons }.map { "\($0.id):\($0.label):\($0.style):\($0.disabled)" }.joined(separator: ";")
                return "\(embed.title ?? "")|\(embed.description ?? "")|\(fields)|\(embed.actionRows.count)|\(buttons)"
            }.joined(separator: "§")
        }()
        let ogpHash = m.parsedContent.ogpPreviews.map {
            "\($0.url)|\($0.title)|\($0.description)|\($0.imageURL)"
        }.joined(separator: "§")
        let topicHash: String = {
            guard let topic = m.topicData else { return "" }
            return "\(topic.topicId)|\(topic.creatorId)|\(topic.replyCount)"
        }()

        let sendFeedback = m.showsSendingFeedback ? "1" : "0"
        return "\(m.id)|\(edited)|\(m.messageCode)|\(m.parsedContent.text)|\(att)|\(presignHash)|\(pin)|\(pollHash)|\(embedHash)|\(ogpHash)|\(topicHash)|\(sendFeedback)|\(m.sendingState.rawValue)"
    }

    func stateSignal() -> Signal<ChatState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var lastIds = self.messages.map { $0.id }
            var lastSendingStates = self.messages.map { $0.sendingState }
            var lastReactions = self.messages.map { $0.reactions }
            var lastMessageTokens = self.messages.map { Self.messageUpdateToken($0) }
            var lastLoading = self.isLoading
            var lastLoadingMore = self.isLoadingMore
            var lastLoadingNewer = self.isLoadingNewer
            var lastLoadingMessageContext = self.isLoadingMessageContext
            var lastError = self.errorMessage
            var lastHasMoreOlder = self.hasMoreOlder
            var lastHasMoreNewer = self.hasMoreNewer
            var lastLastSeenMessageId = self.lastSeenMessageId
            var lastParentName = self.currentState.parentName
            var lastIsPrivate = self.currentState.isPrivate
            var lastIsAgeRestricted = self.currentState.isAgeRestricted
            var lastIsPeerBlocked = self.currentState.isPeerBlocked
            var lastChannelLabel = self.currentState.channelLabel
            var lastChannelType = self.currentState.channelType
            var lastDmPeerUsername = self.currentState.dmPeerUsername
            var lastDmPeerDisplayName = self.currentState.dmPeerDisplayName
            var lastDmAvatarURL = self.currentState.dmAvatarURL
            var lastDmGroupAvatarURL = self.currentState.dmGroupAvatarURL
            subscriber.putNext(self.currentState)
            let merged = Signal<Void, NoError> { subscriber in
                let d1 = self.needsReloadPipe.signal().start(next: { subscriber.putNext(()) })
                let d2 = self.metadataOnlyPipe.signal().start(next: { subscriber.putNext(()) })
                let d3 = self.context.engine.friendsData.friendsUpdated.signal().start(next: { subscriber.putNext(()) })
                return ActionDisposable { d1.dispose(); d2.dispose(); d3.dispose() }
                }
            return (merged
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { newState in
                    let newIds = newState.messages.map { $0.id }
                    let newSendingStates = newState.messages.map { $0.sendingState }
                    let newReactions = newState.messages.map { $0.reactions }
                    let newMessageTokens = newState.messages.map { Self.messageUpdateToken($0) }
                let changed = newIds != lastIds
                        || newSendingStates != lastSendingStates
                        || newReactions != lastReactions
                        || newMessageTokens != lastMessageTokens
                        || newState.isLoading != lastLoading
                        || newState.isLoadingMore != lastLoadingMore
                        || newState.isLoadingNewer != lastLoadingNewer
                        || newState.isLoadingMessageContext != lastLoadingMessageContext
                        || newState.errorMessage != lastError
                        || newState.hasMoreOlder != lastHasMoreOlder
                        || newState.hasMoreNewer != lastHasMoreNewer
                        || newState.lastSeenMessageId != lastLastSeenMessageId
                        || newState.parentName != lastParentName
                        || newState.isPrivate != lastIsPrivate
                        || newState.isAgeRestricted != lastIsAgeRestricted
                        || newState.isPeerBlocked != lastIsPeerBlocked
                        || newState.channelLabel != lastChannelLabel
                        || newState.channelType != lastChannelType
                        || newState.dmPeerUsername != lastDmPeerUsername
                        || newState.dmPeerDisplayName != lastDmPeerDisplayName
                        || newState.dmAvatarURL != lastDmAvatarURL
                        || newState.dmGroupAvatarURL != lastDmGroupAvatarURL
                    guard changed else { return }
                    lastIds = newIds
                    lastSendingStates = newSendingStates
                    lastReactions = newReactions
                    lastMessageTokens = newMessageTokens
                    lastLoading = newState.isLoading
                    lastLoadingMore = newState.isLoadingMore
                    lastLoadingNewer = newState.isLoadingNewer
                    lastLoadingMessageContext = newState.isLoadingMessageContext
                    lastError = newState.errorMessage
                    lastHasMoreOlder = newState.hasMoreOlder
                    lastHasMoreNewer = newState.hasMoreNewer
                    lastLastSeenMessageId = newState.lastSeenMessageId
                    lastParentName = newState.parentName
                    lastIsPrivate = newState.isPrivate
                    lastIsAgeRestricted = newState.isAgeRestricted
                    lastIsPeerBlocked = newState.isPeerBlocked
                    lastChannelLabel = newState.channelLabel
                    lastChannelType = newState.channelType
                    lastDmPeerUsername = newState.dmPeerUsername
                    lastDmPeerDisplayName = newState.dmPeerDisplayName
                    lastDmAvatarURL = newState.dmAvatarURL
                    lastDmGroupAvatarURL = newState.dmGroupAvatarURL
                    subscriber.putNext(newState)
                })
        }
    }

    private func isSenderCurrentUser(senderId: String, currentUserId: String?) -> Bool {
        guard let currentUserId, !currentUserId.isEmpty else { return false }
        let s = senderId.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == c { return true }
        if let a = Int64(s), let b = Int64(c), a == b { return true }
        return false
    }

    private func cachedSenderProfilesBySenderId(senderIds: Set<String>) -> [String: (avatar: String?, username: String)] {
        var out: [String: (avatar: String?, username: String)] = [:]
        let clan = clanId
        context.account.postbox.read { tx in
            let memberByUserId: [Int64: ClanMemberRecord] = {
                guard clan != 0 else { return [:] }
                var d: [Int64: ClanMemberRecord] = [:]
                for m in tx.getClanMembers(clanId: clan) {
                    d[m.userId] = m
                }
                return d
            }()
            for sid in senderIds {
                guard let uidInt = Int64(sid), uidInt != 0 else { continue }
                let profile = tx.getProfile(userId: sid)
                let username = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                if clan != 0 {
                    if let m = memberByUserId[uidInt],
                       let r = m.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl),
                       !r.isEmpty {
                        out[sid] = (r, username)
                    } else if let av = profile?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !av.isEmpty {
                        out[sid] = (av, username)
                    } else {
                        out[sid] = (nil, username)
                    }
                } else {
                    let av = profile?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
                    out[sid] = (av?.isEmpty == false ? av : nil, username)
                }
            }
        }
        guard clanId != 0 else { return out }
        for sid in senderIds {
            if let existing = out[sid], !existing.username.isEmpty, existing.avatar != nil { continue }
            guard let uidInt = Int64(sid), uidInt != 0 else { continue }
            
            var foundAvatar: String?
            var foundUsername: String = ""
            
            if let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
               let found = clanUsers.clanUsers.first(where: { $0.user.id == uidInt }) {
                let u = Self.apiUserForMemberProfile(from: found)
                let av = u.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                foundAvatar = av.isEmpty ? nil : av
                foundUsername = u.username
            } else if let allUsers = context.engine.clanData.getAllUserClans(),
                      let found = allUsers.users.first(where: { $0.id == uidInt }) {
                let av = found.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                foundAvatar = av.isEmpty ? nil : av
                foundUsername = found.username
            }
            
            let current = out[sid]
            let resolvedAvatar = current?.avatar ?? foundAvatar
            let resolvedUsername = (current?.username.isEmpty == false) ? current!.username : foundUsername
            out[sid] = (resolvedAvatar, resolvedUsername)
        }
        return out
    }

    private func enrichReplyRefsFromPostbox(
        _ refsByMessageId: [String: Mezon_Api_MessageRef]
    ) -> [String: Mezon_Api_MessageRef] {
        let refsToEnrich = refsByMessageId.filter { _, ref in
            guard ref.messageSenderID != 0,
                  ref.messageSenderID != MezonConstants.anonymousUserId else { return false }
            let hasName = !ref.messageSenderClanNick.isEmpty
                || !ref.messageSenderDisplayName.isEmpty
                || !ref.messageSenderUsername.isEmpty
            return !hasName || ref.messageSenderAvatar.isEmpty
        }
        guard !refsToEnrich.isEmpty else { return refsByMessageId }

        var result = refsByMessageId
        let senderIds = Set(refsToEnrich.values.map(\.messageSenderID))
        context.account.postbox.read { tx in
            var membersByUserId: [Int64: ClanMemberRecord] = [:]
            if clanId != 0 {
                for member in tx.getClanMembers(clanId: clanId) where senderIds.contains(member.userId) {
                    membersByUserId[member.userId] = member
                    if membersByUserId.count == senderIds.count { break }
                }
            }
            for (messageId, ref) in refsToEnrich {
                let senderId = ref.messageSenderID
                let member = membersByUserId[senderId]
                let profile = tx.getProfile(userId: "\(senderId)")
                var enriched = ref

                if ref.messageSenderClanNick.isEmpty,
                   ref.messageSenderDisplayName.isEmpty,
                   ref.messageSenderUsername.isEmpty {
                    let memberDisplayName = member?.displayName ?? ""
                    let memberUsername = member?.username ?? ""
                    enriched.messageSenderClanNick = member?.clanNick ?? ""
                    enriched.messageSenderDisplayName = memberDisplayName.isEmpty
                        ? profile?.displayName ?? ""
                        : memberDisplayName
                    enriched.messageSenderUsername = memberUsername.isEmpty
                        ? profile?.username ?? ""
                        : memberUsername
                }

                let avatar = member?.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl)
                    ?? profile?.avatarUrl
                if ref.messageSenderAvatar.isEmpty, let avatar, !avatar.isEmpty {
                    enriched.messageSenderAvatar = avatar
                }
                result[messageId] = enriched
            }
        }
        return result
    }

    private func buildDisplayMessages(from records: [MessageRecord]) -> [ChatMessageDisplay] {
        let currentUserId = context.currentUser?.id
        let validRecords = records.filter { !$0.id.isEmpty && !$0.channelId.isEmpty }
        let now = Date()

        let senderIds = Set(validRecords.map(\.senderId))
        let profilesBySenderId = cachedSenderProfilesBySenderId(senderIds: senderIds)
        var replyInfoByMessageId: [String: (ref: Mezon_Api_MessageRef?, isDeletedReply: Bool)] = [:]
        for record in validRecords {
            replyInfoByMessageId[record.id] = Self.firstReplyRef(from: record.referencesData)
        }
        let enrichedReplyRefsByMessageId = enrichReplyRefsFromPostbox(
            replyInfoByMessageId.compactMapValues { $0.ref }
        )

        let currentUserRoleIds: Set<Int64> = {
            guard let roleList = context.engine.clanData.getUserPermissions(clanId: clanId) else { return [] }
            return Set(roleList.roles.map { $0.id })
        }()

        let currentPendingIds = Set(validRecords.filter { $0.sendingState == .pending }.map(\.id))
        pendingSendingFeedbackBeganAtByMessageId = pendingSendingFeedbackBeganAtByMessageId.filter {
            currentPendingIds.contains($0.key)
        }
        for cachedId in ParsedAttachment.pendingImageCache.keys where !currentPendingIds.contains(cachedId) {
            ParsedAttachment.pendingImageCache.removeValue(forKey: cachedId)
        }
        for cachedId in ParsedAttachment.pendingDocumentPlaceholders.keys where !currentPendingIds.contains(cachedId) {
            ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: cachedId)
        }

        let displays = validRecords.map { record -> ChatMessageDisplay in
            let parsedRaw = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
            let parsed = enrichParsedContent(parsedRaw, fallbackClanId: record.clanId)
            let content = parsed.text
            let msg = Message(id: record.id, channelId: record.channelId, clanId: record.clanId, senderId: record.senderId, content: .text(content), createdAt: record.createdAt, editedAt: record.editedAt, isDeleted: record.isDeleted, reactions: [], replyToId: nil, mentionedUserIds: [], isPinned: pinnedMessageIds.contains(record.id))
            let sendingFeedbackBeganAt = pendingSendingFeedbackBeganAt(for: record, now: now)
            let showsSendingFeedback = record.sendingState == .pending
                && now.timeIntervalSince(sendingFeedbackBeganAt) >= Self.pendingSendFeedbackDelay

            var attachments = Self.applyPresignFinishState(
                to: Self.parseAttachments(record.attachmentsJSON),
                contentData: record.content
            )
            let overlayMedia = AttachmentUploadCoordinator.shared.imageOverlay(for: record.id)
            let overlayFiles = AttachmentUploadCoordinator.shared.fileOverlay(for: record.id)
            if overlayMedia != nil || overlayFiles != nil {
                let audio = attachments.filter(\.isAudio)
                var media = attachments.filter(\.isMedia)
                if let overlayMedia {
                    media = overlayMedia
                }
                let files = overlayFiles ?? attachments.filter { !$0.isMedia && !$0.isAudio }
                attachments = media + audio + files
            } else if record.sendingState == .pending {
                let stillUploading = true
                let localImages = ParsedAttachment.pendingImageCache[record.id] ?? []
                let localDocs = ParsedAttachment.pendingDocumentPlaceholders[record.id] ?? []
                if !localImages.isEmpty || !localDocs.isEmpty {
                    var combined: [ParsedAttachment] = attachments
                    if !localImages.isEmpty {
                        combined.append(contentsOf: localImages.map { image in
                            ParsedAttachment(
                                url: "",
                                filename: "uploading.jpg",
                                filetype: "image/jpeg",
                                width: Int(image.size.width),
                                height: Int(image.size.height),
                                durationSeconds: nil,
                                localImage: image,
                                isUploading: stillUploading
                            )
                        })
                    }
                    if !localDocs.isEmpty {
                        combined.append(contentsOf: localDocs.map { doc in
                            ParsedAttachment(
                                url: doc.url,
                                filename: doc.filename,
                                filetype: doc.filetype,
                                width: doc.width,
                                height: doc.height,
                                durationSeconds: doc.durationSeconds,
                                localImage: doc.localImage,
                                isUploading: stillUploading,
                                uploadProgress: doc.uploadProgressKey.isEmpty
                                    ? doc.uploadProgress
                                    : AttachmentUploadProgressStore.shared.progress(forKey: doc.uploadProgressKey),
                                uploadProgressKey: doc.uploadProgressKey,
                                uploadShowsPercent: doc.uploadShowsPercent
                            )
                        })
                    }
                    attachments = combined
                }
            }

            let reactions = Self.parseReactions(record.reactionsJSON, currentUserId: currentUserId)
            let replyInfo = replyInfoByMessageId[record.id] ?? (ref: nil, isDeletedReply: false)
            let replyRef = enrichedReplyRefsByMessageId[record.id] ?? replyInfo.ref
            let isDeletedReply = replyInfo.isDeletedReply
            let bodyEmpty = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let senderLabel = record.senderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isWelcome = record.senderId == "0" && bodyEmpty && senderLabel == "system"
            let replyRefSourceContent: String = {
                if let s = String(data: record.content, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
                return "{}"
            }()
            let callLog = Self.parseCallLog(from: record.content)
            let topicData = topicId != 0 ? nil : Self.parseTopicData(from: record.content, code: record.code)
            let isMe = isSenderCurrentUser(senderId: record.senderId, currentUserId: currentUserId)
            let profileInfo = profilesBySenderId[record.senderId]
            let trimmedStoredAvatar = record.senderAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mergedAvatar: String? = {
                if !trimmedStoredAvatar.isEmpty { return trimmedStoredAvatar }
                if isMe {
                    let cur = context.currentUser?.avatarURL?.absoluteString
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !cur.isEmpty { return cur }
                }
                return profileInfo?.avatar
            }()
            
            let senderUsername: String = {
                if isMe {
                    return context.currentUser?.username ?? profileInfo?.username ?? ""
                }
                return profileInfo?.username ?? ""
            }()
            let hasMention = Self.checkIncludeMention(
                mentionsData: record.mentionsJSON,
                referencesData: record.referencesData,
                currentUserId: currentUserId,
                currentUserRoleIds: currentUserRoleIds
            )
            let isForward = Self.parseContentIsForward(from: record.content)
            let locationData = LocationData.parse(
                from: record.content, code: record.code,
                avatarURL: mergedAvatar, senderName: record.senderDisplayName, senderUsername: senderUsername, isMe: isMe
            )
            let clanInviteLinkCode = ClanInviteLinkParser.firstInviteCode(in: content)
            let parsedPollData = PollData.parse(from: record.content)
            let pollData: PollData? = (record.code == MezonConstants.MessageCode.poll.rawValue || parsedPollData != nil)
                ? parsedPollData
                : nil
            return ChatMessageDisplay(
                message: msg, senderDisplayName: record.senderDisplayName, senderUsername: senderUsername, avatarURL: mergedAvatar,
                isCombine: false, attachments: attachments, reactions: reactions, parsedContent: parsed,
                replyRef: replyRef, isDeletedReply: isDeletedReply, isWelcome: isWelcome, callLog: callLog,
                topicData: topicData, locationData: locationData, isMe: isMe, sendingState: record.sendingState,
                showsSendingFeedback: showsSendingFeedback, hasIncludeMention: hasMention,
                isForward: isForward, showForwardHeader: false, messageCode: record.code,
                clanInviteLinkCode: clanInviteLinkCode,
                replyRefSourceContent: replyRefSourceContent,
                pollData: pollData,
                rawContentData: record.content
            )
        }
        return Self.applyCombine(to: Self.sortMessagesLikeChannelStore(displays))
    }

    private static func sortMessagesLikeChannelStore(_ displays: [ChatMessageDisplay]) -> [ChatMessageDisplay] {
        let messageAsc: (ChatMessageDisplay, ChatMessageDisplay) -> Bool = {
            messageDisplayLessThan($0, $1)
        }
        let pinsFirst: (ChatMessageDisplay) -> Bool = {
            $0.isWelcome || $0.messageCode == MezonConstants.MessageCode.firstMessage.rawValue
        }
        let head = displays.filter(pinsFirst).sorted(by: messageAsc)
        let tail = displays.filter { !pinsFirst($0) }.sorted(by: messageAsc)
        return head + tail
    }

    private static func messageDisplayLessThan(_ a: ChatMessageDisplay, _ b: ChatMessageDisplay) -> Bool {
        MessageRecord.compareAscending(
            id: a.id,
            createdAt: a.message.createdAt,
            id: b.id,
            createdAt: b.message.createdAt
        )
    }

    private static func parseContentIsForward(from data: Data) -> Bool {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return jsonForwardTruth(json["fwd"])
    }

    private static func jsonForwardTruth(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber:
            return n.boolValue || n.intValue != 0
        case let i as Int: return i != 0
        case let i64 as Int64: return i64 != 0
        case let d as Double: return d != 0
        case is [String: Any]: return true
        case let arr as [Any]: return !arr.isEmpty
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.isEmpty { return false }
            if t == "0" || t == "false" { return false }
            return true
        default:
            return false
        }
    }

    private static func firstReplyRef(from data: Data) -> (ref: Mezon_Api_MessageRef?, isDeletedReply: Bool) {
        guard !data.isEmpty,
            let list = try? Mezon_Api_MessageRefList(serializedBytes: data),
              !list.refs.isEmpty else { return (nil, false) }
        if let validRef = list.refs.first(where: { $0.messageRefID != 0 }) {
            return (validRef, false)
        }
        if list.refs.first(where: { $0.messageRefID == 0 }) != nil {
            return (nil, true)
        }
        return (nil, false)
    }

    private func messageRecord(from api: Mezon_Api_ChannelMessage) -> MessageRecord {
        let mid = "\(api.messageID)"
        let existing = context.account.postbox.read { tx in tx.getMessageById(mid, channelId: storageChannelId) }
        var record = MessageRecord.fromApi(api, merging: existing)
        if record.channelId != storageChannelId {
            record = MessageRecord(
                id: record.id, channelId: storageChannelId, clanId: record.clanId,
                senderId: record.senderId, content: record.content,
                createdAt: record.createdAt, editedAt: record.editedAt,
                isDeleted: record.isDeleted, code: record.code,
                senderDisplayName: record.senderDisplayName,
                senderAvatarURL: record.senderAvatarURL, sendingState: record.sendingState,
                attachmentsJSON: record.attachmentsJSON, reactionsJSON: record.reactionsJSON,
                referencesData: record.referencesData, mentionsJSON: record.mentionsJSON
            )
        }
        return record
    }

    private static let messageCodeTopic: Int32 = 9

    private static func parseTopicData(from data: Data, code: Int32) -> TopicData? {
        guard code == messageCodeTopic else { return nil }
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let topicId: String
        if let tp = json["tp"] as? String, !tp.isEmpty { topicId = tp }
        else if let tp = json["tp"] as? Int, tp != 0 { topicId = "\(tp)" }
        else if let tp = json["tp"] as? Double, tp != 0 { topicId = "\(Int64(tp))" }
        else { return nil } 
        let creatorId: String
        if let cid = json["cid"] as? String { creatorId = cid }
        else if let cid = json["cid"] as? Int { creatorId = "\(cid)" }
        else if let cid = json["cid"] as? Double { creatorId = "\(Int64(cid))" }
        else { creatorId = "" }
        let replyCount: Int
        if let rpl = json["rpl"] as? Int { replyCount = rpl }
        else if let rpl = json["rpl"] as? Double { replyCount = Int(rpl) }
        else { replyCount = 0 }
        return TopicData(topicId: topicId, creatorId: creatorId, replyCount: replyCount)
    }

    private static func parseCallLog(from data: Data) -> CallLogData? {
        guard !data.isEmpty,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callLogDict = json["callLog"] as? [String: Any] else { return nil }
        let typeRaw = callLogDict["callLogType"] as? Int ?? 0
        let callLogType = CallLogType(rawValue: typeRaw) ?? .timeoutCall
        let isVideo = callLogDict["isVideo"] as? Bool ?? false
        return CallLogData(callLogType: callLogType, isVideo: isVideo)
    }

    private static func applyCombine(to displays: [ChatMessageDisplay]) -> [ChatMessageDisplay] {
        displays.enumerated().map { i, d in
            let prevDisplay = i > 0 ? displays[i - 1] : nil
            let prev = prevDisplay?.message
            let hasReply = d.replyRef != nil || d.isDeletedReply
            let combine = hasReply ? false : ChatMessageDisplay.isCombineWithPrevious(current: d.message, previous: prev)
            let showForwardHeader = ChatMessageDisplay.shouldShowForwardHeader(
                isForward: d.isForward,
                current: d.message,
                previous: prev,
                previousWasForward: prevDisplay?.isForward ?? false
            )
            return ChatMessageDisplay(
                message: d.message, senderDisplayName: d.senderDisplayName, senderUsername: d.senderUsername, avatarURL: d.avatarURL, isCombine: combine,
                attachments: d.attachments, reactions: d.reactions, parsedContent: d.parsedContent,
                replyRef: d.replyRef, isDeletedReply: d.isDeletedReply, isWelcome: d.isWelcome, callLog: d.callLog,
                topicData: d.topicData, locationData: d.locationData, isMe: d.isMe, sendingState: d.sendingState,
                showsSendingFeedback: d.showsSendingFeedback, hasIncludeMention: d.hasIncludeMention,
                isForward: d.isForward, showForwardHeader: showForwardHeader, messageCode: d.messageCode,
                clanInviteLinkCode: d.clanInviteLinkCode,
                replyRefSourceContent: d.replyRefSourceContent,
                pollData: d.pollData,
                rawContentData: d.rawContentData
            )
        }
    }

    private static func checkIncludeMention(
        mentionsData: Data,
        referencesData: Data,
        currentUserId: String?,
        currentUserRoleIds: Set<Int64>
    ) -> Bool {
        guard let currentUserId, !currentUserId.isEmpty else { return false }

        let mentions = parseMentionList(from: mentionsData)
        for mention in mentions {

            if mention.userID != 0, "\(mention.userID)" == ChatMessageDisplay.mentionHereUserId {
                return true
            }

            if mention.userID != 0, "\(mention.userID)" == currentUserId {
                return true
            }

            if mention.roleID != 0, currentUserRoleIds.contains(mention.roleID) {
                return true
            }
        }


        if !referencesData.isEmpty,
           let list = try? Mezon_Api_MessageRefList(serializedBytes: referencesData),
           let firstRef = list.refs.first,
           firstRef.messageSenderID != 0,
           "\(firstRef.messageSenderID)" == currentUserId {
            return true
        }

        return false
    }

    private static func parseMentionList(from data: Data) -> [Mezon_Api_MessageMention] {
        guard !data.isEmpty else { return [] }
        if let list = try? Mezon_Api_MessageMentionList(serializedBytes: data), !list.mentions.isEmpty {
            return list.mentions
        }
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { item -> Mezon_Api_MessageMention? in
                var m = Mezon_Api_MessageMention()
                if let uid = item["user_id"] as? String, let v = Int64(uid) { m.userID = v }
                else if let uid = item["user_id"] as? Int64 { m.userID = uid }
                else if let uid = item["user_id"] as? Double { m.userID = Int64(uid) }
                if let rid = item["role_id"] as? String, let v = Int64(rid) { m.roleID = v }
                else if let rid = item["role_id"] as? Int64 { m.roleID = rid }
                else if let rid = item["role_id"] as? Double { m.roleID = Int64(rid) }
                return m
            }
        }
        return []
    }

    private static func applyPresignFinishState(
        to attachments: [ParsedAttachment],
        contentData: Data
    ) -> [ParsedAttachment] {
        guard let keys = PresignFinishContent.parseKeys(from: contentData) else { return attachments }
        return attachments.map { att in
            guard !att.url.isEmpty, !att.isUploading, att.localImage == nil, !att.uploadFailed else { return att }
            var copy = att
            copy.isPresignPending = !PresignFinishContent.isAttachmentReady(url: att.url, presignFinish: keys)
            return copy
        }
    }

    private static func parseAttachments(_ data: Data) -> [ParsedAttachment] {
        guard !data.isEmpty else { return [] }

        let isLikelyJson = data.first == UInt8(ascii: "[") || data.first == UInt8(ascii: "{")
        var fromProto: [ParsedAttachment]?
        var fromJson: [ParsedAttachment]?

        if !isLikelyJson,
            let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: data),
           !list.attachments.isEmpty {
            fromProto = list.attachments.compactMap { att -> ParsedAttachment? in
                guard !att.url.isEmpty else { return nil }
                return ParsedAttachment(
                    url: att.url,
                    filename: att.filename,
                    filetype: att.filetype,
                    width: att.width != 0 ? Int(att.width) : nil,
                    height: att.height != 0 ? Int(att.height) : nil,
                    durationSeconds: att.duration > 0 ? Int(att.duration) : nil,
                    thumbnail: att.thumbnail
                )
            }
        }

        if fromProto == nil || fromProto?.isEmpty == true {
            var jsonArray: [[String: Any]]?
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                jsonArray = arr
            } else if let str = String(data: data, encoding: .utf8),
                let strData = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: strData) as? [[String: Any]] {
                jsonArray = arr
            }
            if let json = jsonArray {
                fromJson = json.compactMap { item in
                    guard let url = item["url"] as? String, !url.isEmpty else { return nil }
                    let w = item["width"] as? Int ?? (item["width"] as? String).flatMap { Int($0) }
                    let h = item["height"] as? Int ?? (item["height"] as? String).flatMap { Int($0) }
                    let d: Int? = {
                        if let n = item["duration"] as? Int { return n > 0 ? n : nil }
                        if let n = item["duration"] as? Int64 { return n > 0 ? Int(n) : nil }
                        if let s = item["duration"] as? String, let n = Int(s) { return n > 0 ? n : nil }
                        return nil
                    }()
                    return ParsedAttachment(
                        url: url,
                        filename: item["filename"] as? String ?? "",
                        filetype: item["filetype"] as? String ?? "",
                        width: w,
                        height: h,
                        durationSeconds: d,
                        thumbnail: item["thumbnail"] as? String ?? ""
                    )
                }
            }
        }

        return (fromProto?.isEmpty == false ? fromProto : fromJson) ?? []
    }

    private static func parseReactions(_ data: Data, currentUserId: String?) -> [ParsedReaction] {
        guard !data.isEmpty else { return [] }

        let isLikelyJson = data.first == UInt8(ascii: "[") || data.first == UInt8(ascii: "{")
        var fromProto: [ParsedReaction]?
        var fromJson: [ParsedReaction]?

        if !isLikelyJson, let list = try? Mezon_Api_MessageReactionList(serializedBytes: data), !list.reactions.isEmpty {
            fromProto = parseReactionsFromProtobuf(list.reactions, currentUserId: currentUserId)
        }

        if fromProto == nil || fromProto?.isEmpty == true {
            if let anyJson = try? JSONSerialization.jsonObject(with: data) {
                let json: [[String: Any]]
                if let arr = anyJson as? [[String: Any]] {
                    json = arr
                } else if let dict = anyJson as? [String: Any], let arr = dict["reactions"] as? [[String: Any]] {
                    json = arr
                } else {
                    json = []
                }
                fromJson = parseReactionsFromJSON(json, currentUserId: currentUserId)
            }
        }

        let result = (fromProto?.isEmpty == false ? fromProto : fromJson) ?? []
        return result
    }

    private static func parseReactionsFromJSON(_ items: [[String: Any]], currentUserId: String?) -> [ParsedReaction] {
        var emojiMeta: [String: (emoji: String, countFromApi: Int)] = [:]
        var insertionOrder: [String] = []
        for item in items {
            guard let key = reactionEmojiKeyJSON(item) else { continue }
            let emoji = item["emoji"] as? String ?? ""
            let countFromApi = reactionTotalCountJSON(item) ?? 0
            if emojiMeta[key] == nil {
                insertionOrder.append(key)
            }
            var meta = emojiMeta[key] ?? (emoji: "", countFromApi: 0)
            if countFromApi > meta.countFromApi { meta.countFromApi = countFromApi }
            if !emoji.isEmpty { meta.emoji = emoji }
            emojiMeta[key] = meta
        }
        return insertionOrder.compactMap { key in
            let meta = emojiMeta[key]!
            let senderTuples = orderedActiveSendersWithStackCountsJSON(items: items, emojiKey: key)
            if senderTuples.isEmpty {
                guard meta.countFromApi > 0 else { return nil }
            }
            let senders: [ParsedReactionSender] = senderTuples.map { tuple in
                let hint = lastSenderNameJSON(items: items, emojiKey: key, senderId: tuple.userId)
                return ParsedReactionSender(userId: tuple.userId, count: tuple.count, nameHint: hint)
            }
            let sumSender = senders.reduce(0) { $0 + $1.count }
            let count = max(sumSender, meta.countFromApi)
            let isMe = currentUserId.map { uid in senders.contains { $0.userId == uid } } ?? false
            return ParsedReaction(
                emojiId: key,
                emoji: meta.emoji,
                count: count,
                senders: senders,
                isMe: isMe
            )
        }
    }

    private static func reactionEmojiKeyJSON(_ item: [String: Any]) -> String? {
        let emojiId = reactionStringIdJSON(
            item,
            keys: ["emoji_id", "emojiId", "emojiID", "emojiid"]
        )
        let emoji = (item["emoji"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = emojiId.isEmpty ? emoji : emojiId
        return key.isEmpty ? nil : key
    }

    private static func reactionSenderIdJSON(_ item: [String: Any]) -> String {
        reactionStringIdJSON(
            item,
            keys: ["sender_id", "senderId", "senderID", "user_id", "userId", "userID"]
        )
    }

    private static func reactionStringIdJSON(_ item: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let s = item[key] as? String {
                let value = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, value != "0" { return value }
            }
            if let n = item[key] as? Int, n != 0 { return "\(n)" }
            if let n = item[key] as? Int32, n != 0 { return "\(n)" }
            if let n = item[key] as? Int64, n != 0 { return "\(n)" }
            if let n = item[key] as? NSNumber, n.int64Value != 0 { return "\(n.int64Value)" }
            if let n = item[key] as? Double, n != 0 { return "\(Int64(n))" }
        }
        return ""
    }

    private static func reactionIntJSON(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? Int32 { return Int(n) }
        if let n = value as? Int64 { return Int(n) }
        if let n = value as? NSNumber { return n.intValue }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        return 0
    }

    private static func reactionBoolJSON(_ value: Any?, default defaultValue: Bool) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" || t == "1" { return true }
            if t == "false" || t == "0" { return false }
        }
        return defaultValue
    }

    private static func reactionTotalCountJSON(_ item: [String: Any]) -> Int? {
        let explicitTotal = max(
            reactionIntJSON(item["total_count"]),
            reactionIntJSON(item["totalCount"])
        )
        if explicitTotal > 0 { return explicitTotal }
        if reactionBoolJSON(item["count_is_total"], default: false)
            || reactionBoolJSON(item["countIsTotal"], default: false)
        {
            return reactionIntJSON(item["count"])
        }
        if reactionSenderIdJSON(item).isEmpty {
            let count = reactionIntJSON(item["count"])
            return count > 0 ? count : nil
        }
        return nil
    }

    private static func isReactionTotalCountRowJSON(_ item: [String: Any]) -> Bool {
        reactionTotalCountJSON(item) != nil
    }

    private static func reactionSenderRowCountJSON(_ item: [String: Any]) -> Int {
        if isReactionTotalCountRowJSON(item) { return 0 }
        return reactionIntJSON(item["count"])
    }

    private static func orderedActiveSendersWithStackCountsJSON(items: [[String: Any]], emojiKey: String) -> [(userId: String, count: Int)] {
        var balance: [String: Int] = [:]
        var order: [String] = []
        func parseRowCount(_ item: [String: Any]) -> Int {
            reactionSenderRowCountJSON(item)
        }
        for item in items {
            guard reactionEmojiKeyJSON(item) == emojiKey else { continue }
            let sid = reactionSenderIdJSON(item)
            guard !sid.isEmpty else { continue }
            let actionAdd = reactionBoolJSON(item["action"], default: true)
            let rowCount = parseRowCount(item)
            if actionAdd {
                let prev = balance[sid] ?? 0
                if rowCount > 0 {
                    balance[sid] = rowCount
                } else {
                    balance[sid] = prev + 1
                }
                let newVal = balance[sid] ?? 0
                if newVal > 0, prev == 0, !order.contains(sid) {
                    order.append(sid)
                }
            } else {
                let prev = balance[sid] ?? 0
                if rowCount > 0 {
                    balance[sid] = max(0, prev - rowCount)
                } else {
                    balance[sid] = max(0, prev - 1)
                }
                if (balance[sid] ?? 0) == 0 {
                    order.removeAll { $0 == sid }
                }
            }
        }
        return order.compactMap { sid in
            let c = balance[sid] ?? 0
            return c > 0 ? (sid, c) : nil
        }
    }

    private static func lastSenderNameJSON(items: [[String: Any]], emojiKey: String, senderId: String) -> String? {
        for item in items.reversed() {
            guard reactionEmojiKeyJSON(item) == emojiKey else { continue }
            guard reactionSenderIdJSON(item) == senderId else { continue }
            let action = reactionBoolJSON(item["action"], default: true)
            guard action else { continue }
            if let name = item["sender_name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return nil
    }

    private static func parseReactionsFromProtobuf(_ reactions: [Mezon_Api_MessageReaction], currentUserId: String?) -> [ParsedReaction] {
        var emojiMeta: [String: (emoji: String, countFromApi: Int)] = [:]
        var insertionOrder: [String] = []
        for r in reactions {
            guard let key = protoEmojiKey(r) else { continue }
            let c = Int(r.count)
            if emojiMeta[key] == nil {
                insertionOrder.append(key)
            }
            var meta = emojiMeta[key] ?? (emoji: "", countFromApi: 0)
            if c > meta.countFromApi { meta.countFromApi = c }
            if !r.emoji.isEmpty { meta.emoji = r.emoji }
            emojiMeta[key] = meta
        }
        return insertionOrder.compactMap { key in
            let meta = emojiMeta[key]!
            let senderTuples = orderedActiveSendersWithStackCountsProtobuf(reactions: reactions, emojiKey: key)
            let hadPerSenderRows = reactions.contains { r in
                guard protoEmojiKey(r) == key else { return false }
                return r.senderID != 0
            }
            if senderTuples.isEmpty {
                if hadPerSenderRows { return nil }
                guard meta.countFromApi > 0 else { return nil }
            }
            let senders: [ParsedReactionSender] = senderTuples.map { ParsedReactionSender(userId: $0.userId, count: $0.count, nameHint: nil) }
            let sumSender = senders.reduce(0) { $0 + $1.count }
            let count = max(sumSender, meta.countFromApi)
            let isMe = currentUserId.map { uid in senders.contains { $0.userId == uid } } ?? false
            return ParsedReaction(
                emojiId: key,
                emoji: meta.emoji,
                count: count,
                senders: senders,
                isMe: isMe
            )
        }
    }

    private static func protoEmojiKey(_ r: Mezon_Api_MessageReaction) -> String? {
        let emojiKey = r.emojiID != 0 ? "\(r.emojiID)" : (r.emoji.isEmpty ? "?" : r.emoji)
        guard emojiKey != "?" || !r.emoji.isEmpty else { return nil }
        return emojiKey
    }

    private static func orderedActiveSendersWithStackCountsProtobuf(reactions: [Mezon_Api_MessageReaction], emojiKey: String) -> [(userId: String, count: Int)] {
        var balance: [String: Int] = [:]
        var order: [String] = []
        for r in reactions {
            guard protoEmojiKey(r) == emojiKey else { continue }
            guard r.senderID != 0 else { continue }
            let sid = "\(r.senderID)"
            let isRemove = r.action
            let rowCount = Int(r.count)
            if !isRemove {
                let prev = balance[sid] ?? 0
                if rowCount > 0 {
                    balance[sid] = rowCount
                } else {
                    balance[sid] = prev + 1
                }
                let newVal = balance[sid] ?? 0
                if newVal > 0, prev == 0, !order.contains(sid) {
                    order.append(sid)
                }
            } else {
                let prev = balance[sid] ?? 0
                if rowCount > 0 {
                    balance[sid] = max(0, prev - rowCount)
                } else {
                    balance[sid] = max(0, prev - 1)
                }
                if (balance[sid] ?? 0) == 0 {
                    order.removeAll { $0 == sid }
                }
            }
        }
        return order.compactMap { sid in
            let c = balance[sid] ?? 0
            return c > 0 ? (sid, c) : nil
        }
    }

    private func waitForSocketConnected() async {
        if context.account.socket.isConnected { return }
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if context.account.socket.isConnected {
                return
            }
        }
    }

    private func pinApiClanId() -> Int64 {
        let channelType = channel.type != 0 ? channel.type : (clanId == 0 ? MezonConstants.ChannelType.group.rawValue : MezonConstants.ChannelType.channel.rawValue)
        if channelType == MezonConstants.ChannelType.dm.rawValue || channelType == MezonConstants.ChannelType.group.rawValue {
            return 0
        }
        return clanId
    }

    private func applyPinList(_ list: Mezon_Api_PinMessagesList) {
        var ids = Set<String>()
        var byMsg: [String: Int64] = [:]
        for p in list.pinMessagesList {
            let mid = "\(p.messageID)"
            ids.insert(mid)
            byMsg[mid] = p.id
        }
        pinnedMessageIds = ids
        pinServerIdByMessageId = byMsg
        syncPinnedStateToPostbox()
    }

    private func restorePinnedStateFromPostboxIfNeeded() {
        guard channel.channelID != 0 else { return }
        guard let snap = ChannelPinnedStatePersistence.load(
            postbox: context.account.postbox,
            accountId: context.account.id,
            clanId: pinApiClanId(),
            channelId: channel.channelID
        ) else { return }
        pinnedMessageIds = Set(snap.pinnedMessageIds)
        pinServerIdByMessageId = snap.pinServerIdByMessageId
    }

    private func syncPinnedStateToPostbox() {
        guard channel.channelID != 0 else { return }
        ChannelPinnedStatePersistence.save(
            postbox: context.account.postbox,
            accountId: context.account.id,
            clanId: pinApiClanId(),
            channelId: channel.channelID,
            pinnedMessageIds: pinnedMessageIds,
            pinServerIdByMessageId: pinServerIdByMessageId
        )
    }

    private func mergePinListEntries(_ list: Mezon_Api_PinMessagesList) {
        for p in list.pinMessagesList {
            let mid = "\(p.messageID)"
            pinnedMessageIds.insert(mid)
            if p.id != 0 {
                pinServerIdByMessageId[mid] = p.id
            }
        }
    }

    private func reloadDisplaysWithCurrentPins() {
        let channelIdStr = storageChannelId
        let rows = context.account.postbox.read { tx in
            tx.getMessages(channelId: channelIdStr)
        }
        setMessages(buildDisplayMessages(from: rows))
    }

    private func fetchPinListFromServerAndApply() async {
        guard channel.channelID != 0 else { return }
        guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
        do {
            let res = try await context.account.network.listPinMessages(
                clanId: pinApiClanId(),
                channelId: channel.channelID,
                token: token
            )
            applyPinList(res)
        } catch {
        }
    }

    private func refreshPinnedMessagesFromServer() {
        guard channel.channelID != 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchPinListFromServerAndApply()
            self.reloadDisplaysWithCurrentPins()
        }
    }

    private func joinChat() {
        Task { @MainActor [weak self] in
            await self?.joinChatAndWaitUntilSent()
        }
    }

    private func joinChatAndWaitUntilSent() async {
        guard context.account.socket.isConnected else { return }
        let targetClanId = clanId
        let targetChannel = channel
        await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: context, clanId: targetClanId)
        guard context.account.socket.isConnected else { return }
        context.account.socket.joinClanChat(clanId: targetClanId)
        let channelType: Int32 = targetClanId == 0
            ? (targetChannel.type != 0 ? targetChannel.type : MezonConstants.ChannelType.group.rawValue)
            : (targetChannel.type != 0 ? targetChannel.type : MezonConstants.ChannelType.channel.rawValue)
        let isPublic = targetClanId == 0 ? false : (targetChannel.parentID != 0 ? false : (targetChannel.channelPrivate == 0))
        context.account.socket.joinChannel(
            clanId: targetClanId,
            channelId: targetChannel.channelID,
            channelType: channelType,
            isPublic: isPublic
        )
        if targetClanId != 0 {
            NotificationCenter.default.post(
                name: Notification.Name("MezonJoinedClanChatForBadges"),
                object: nil,
                userInfo: ["clanId": targetClanId]
            )
        }
    }

    private func setupInputBar() {
        remoteTypingStripView.addSubview(remoteTypingLabel)
        view.addSubview(remoteTypingStripView)
        view.addSubview(memberOnboardingMissionBarView)
        channelAppHotbar.onLaunch = { [weak self] in self?.openChannelAppFromHotbar() }
        channelAppHotbar.onHelp = { [weak self] in self?.openChannelAppHelpFromHotbar() }
        view.addSubview(channelAppHotbar)
        addChild(sendInputViewController)
        view.addSubview(sendInputViewController.view)
        sendInputViewController.didMove(toParent: self)


        emojiPicker.install(in: view, engine: context.engine)

        view.addSubview(advancePanelView)
        let advH = advancePanelView.heightAnchor.constraint(equalToConstant: 0)
        advancePanelHeightConstraint = advH
        let advBottom = advancePanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        advancePanelBottomConstraint = advBottom
        NSLayoutConstraint.activate([
            advancePanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            advancePanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            advH,
            advBottom,
        ])

        applyRemoteTypingStripTheme()
        channelAppHotbar.applyTheme()
        inputBarHeight = sendInputViewController.totalHeight
        remoteTypingStripView.alpha = 0
        remoteTypingStripView.isHidden = true
        memberOnboardingMissionBarView.isHidden = true
        view.bringSubviewToFront(remoteTypingStripView)
        view.bringSubviewToFront(memberOnboardingMissionBarView)
        view.bringSubviewToFront(channelAppHotbar)
        view.bringSubviewToFront(sendInputViewController.view)
        emojiPicker.bringToFront()
        view.bringSubviewToFront(advancePanelView)
        configurePendingTopicCreationIfNeeded()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        messagesNode.listView.view.addGestureRecognizer(tap)
        messagesNode.listView.scroller.keyboardDismissMode = .onDrag

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemberOnboardingDidUpdate(_:)),
            name: .mezonMemberOnboardingDidUpdate,
            object: nil
        )
    }

    @objc private func handleMemberOnboardingDidUpdate(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64, gid == clanId else { return }
        refreshMemberOnboardingMissionBar()
    }

    private func cachedClanChannelsForOnboarding() -> [Mezon_Api_ChannelDescription] {
        var channels = [channel]
        if let mission = MemberOnboardingProgress.currentMission(context: context, clanId: clanId),
           mission.channelId != channel.channelID,
           let resolved = context.account.postbox.resolvedChannelDescription(
               clanId: clanId,
               channelId: mission.channelId
           ) {
            channels.append(resolved)
        }
        return channels
    }

    private func refreshMemberOnboardingMissionBar() {
        guard isViewLoaded, clanId != 0, topicId == 0 else {
            if memberOnboardingMissionBarVisible {
                memberOnboardingMissionBarVisible = false
            }
            return
        }

        let state = MemberOnboardingProgress.compute(context: context, clanId: clanId)
        guard state.isVisible, state.completedSteps < state.missions.count else {
            if memberOnboardingMissionBarVisible {
                memberOnboardingMissionBarVisible = false
            }
            return
        }

        let mission = state.missions[state.completedSteps]
        let channelLabel = MemberOnboardingProgress.resolveChannelLabel(
            channelId: mission.channelId,
            context: context,
            clanId: clanId,
            channels: cachedClanChannelsForOnboarding()
        )
        memberOnboardingMissionBarView.configure(
            title: mission.title,
            subtitle: MemberOnboardingProgress.missionActionSubtitle(
                taskType: mission.taskType,
                channelLabel: channelLabel
            )
        )
        memberOnboardingMissionBarView.applyTheme()
        memberOnboardingMissionBarVisible = true
    }

    private func handleMemberOnboardingMissionBarTap() {
        guard clanId != 0 else { return }
        let state = MemberOnboardingProgress.compute(context: context, clanId: clanId)
        guard state.isVisible, state.completedSteps < state.missions.count else { return }
        let mission = state.missions[state.completedSteps]
        MemberOnboardingProgress.performMission(
            mission,
            at: state.completedSteps,
            completedSteps: state.completedSteps,
            context: context,
            clanId: clanId,
            channels: cachedClanChannelsForOnboarding(),
            navigation: MemberOnboardingChannelNavigation(
                openChat: { [weak self] target in
                    self?.selectChannelForMemberOnboarding(target)
                },
                presentVoice: { [weak self] target in
                    self?.presentJoinVoiceSheet(for: target)
                },
                presentStream: { [weak self] target in
                    self?.presentJoinStreamSheet(for: target)
                }
            )
        )
    }

    private func selectChannelForMemberOnboarding(_ target: Mezon_Api_ChannelDescription) {
        guard target.channelID != channel.channelID else { return }
        if let home = (navigationController as? MezonRootController)?.homeController {
            home.openChannelForOnboarding(target)
            return
        }
        var parentName: String?
        if target.parentID != 0 {
            parentName = context.account.postbox.resolvedChannelDescription(
                clanId: clanId,
                channelId: target.parentID
            )?.channelLabel
        }
        let chatVC = ChatViewController(
            clanId: clanId,
            channel: target,
            context: context,
            parentName: parentName
        )
        guard let nav = navigationController else { return }
        if let existing = nav.viewControllers
            .compactMap({ $0 as? ChatViewController })
            .first(where: { $0.channel.channelID == target.channelID }) {
            nav.popToViewController(existing, animated: true)
            return
        }
        var stack = nav.viewControllers
        stack.removeAll { $0 is ChatViewController }
        stack.append(chatVC)
        nav.setViewControllers(stack, animated: true)
    }

    private func runUIViewAnimationMatchingKeyboard(
        _ notification: Notification,
        animations: @escaping () -> Void
    ) {
        let rawDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let duration = rawDuration > 0.01 ? rawDuration : 0.25
        let c = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? 0
        let options: UIView.AnimationOptions
        if c == 7 {
            options = .curveEaseInOut
        } else if let ac = UIView.AnimationCurve(rawValue: c) {
            switch ac {
            case .easeIn: options = .curveEaseIn
            case .easeOut: options = .curveEaseOut
            case .linear: options = .curveLinear
            case .easeInOut: options = .curveEaseInOut
            @unknown default: options = .curveEaseInOut
            }
        } else {
            options = .curveEaseInOut
        }
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options.union([.beginFromCurrentState, .allowUserInteraction]),
            animations: animations
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        let isInputFocused = sendInputViewController.view.findFirstResponder() != nil
        let isEmojiSearchFocused = emojiPicker.isEmojiPanelSearchConsumingKeyboard
        guard isInputFocused || isEmojiSearchFocused else { return }
        isKeyboardVisible = true
        if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            trackedKeyboardHeight = frame.height
        }

        _ = emojiPicker.handleKeyboardWillShow()

        if advancePanelCollapsedHeight > 0 {
            advancePanelCollapsedHeight = 0
            advancePanelHeightConstraint?.constant = 0
            advancePanelView.isHidden = true
            advancePanelView.resetToCollapsed()
        }

        runUIViewAnimationMatchingKeyboard(notification) { [weak self] in
            guard let self, let layout = self.lastLayout else { return }
            self.containerLayoutUpdated(layout, transition: .immediate)
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        let isInputFocused = sendInputViewController.view.findFirstResponder() != nil
        let isEmojiSearchFocused = emojiPicker.isEmojiPanelSearchConsumingKeyboard
        guard isInputFocused || isEmojiSearchFocused else { return }
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let screen = view.window?.screen.bounds ?? UIScreen.main.bounds
        guard frame.minY < screen.maxY - 2 else { return }
        trackedKeyboardHeight = frame.height
        isKeyboardVisible = true
        runUIViewAnimationMatchingKeyboard(notification) { [weak self] in
            guard let self, let layout = self.lastLayout else { return }
            self.containerLayoutUpdated(layout, transition: .immediate)
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
        trackedKeyboardHeight = 0

        emojiPicker.handleKeyboardWillHide()
        if advancePanelCollapsedHeight > 0 && !advancePanelView.isHidden {
            advancePanelView.applySnapCollapsed()
        }
        runUIViewAnimationMatchingKeyboard(notification) { [weak self] in
            guard let self, let layout = self.lastLayout else { return }
            self.containerLayoutUpdated(layout, transition: .immediate)
            self.view.layoutIfNeeded()
        }
    }

    private func updateInputBarHeight(_ newHeight: CGFloat) {
        guard let layout = lastLayout else { return }
        guard abs(newHeight - lastNotifiedComposerHeight) > 0.5 else { return }
        lastNotifiedComposerHeight = newHeight
        let transition: ContainedViewLayoutTransition =
            isKeyboardVisible || currentKeyboardOffset > 0.5
            ? .immediate
            : .animated(duration: 0.25, curve: .easeInOut)
        containerLayoutUpdated(layout, transition: transition)
    }

    private func clanPreventsAnonymous() -> Bool {
        guard clanId != 0 else { return true }
        let rec = context.account.postbox.read { tx in tx.getClan(id: clanId) }
        return rec?.preventsAnonymousMessages ?? false
    }

    private func rebuildAdvancePanelActions() {
        let prevent = clanPreventsAnonymous()
        let on = AnonymousMessageStore.isEnabled(clanId: clanId)
        let items = AdvancedFunctionPanelView.defaultActionItems(
            anonymousOn: on,
            includeAnonymous: clanId != 0 && !prevent
        )
        advancePanelView.setActions(items)
    }

    private func configureAnonymousComposerAndAdvancePanel() {
        sendInputViewController.setClanAnonymousPolicy(preventAnonymous: clanPreventsAnonymous())
        sendInputViewController.refreshAnonymousUI()
        rebuildAdvancePanelActions()
    }

    private func handleAdvancePanelToggle(visible: Bool, collapsedHeight: CGFloat) {
        if visible {
            rebuildAdvancePanelActions()
            emojiPicker.dismissSilently(markAsJustDismissed: false)

            suppressScrollToBottomForNextKeyboardInset = false
            let screenH = UIScreen.main.bounds.height
            let expandedH = min(max(screenH * 0.80, collapsedHeight + 200), screenH * 0.80)
            advancePanelView.collapsedHeight = collapsedHeight
            advancePanelView.expandedHeight = expandedH
            advancePanelView.resetToCollapsed()

            advancePanelCollapsedHeight = collapsedHeight
            advancePanelHeightConstraint?.constant = collapsedHeight
            advancePanelView.isHidden = false
            advancePanelView.applyTheme()
        } else {
            suppressScrollToBottomForNextKeyboardInset = true
            advancePanelCollapsedHeight = 0
            advancePanelHeightConstraint?.constant = 0
            advancePanelView.isHidden = true
            advancePanelView.resetToCollapsed()
        }

        if let layout = lastLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }

        if visible {
            advancePanelView.transform = CGAffineTransform(translationX: 0, y: 30)
            advancePanelView.alpha = 0
            view.layoutIfNeeded()
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.8, options: .curveEaseOut) {
                self.advancePanelView.transform = .identity
                self.advancePanelView.alpha = 1
            }
        } else {
            advancePanelView.transform = .identity
            advancePanelView.alpha = 1
            view.layoutIfNeeded()
        }
    }

    private func updateAdvancePanelOverlayHeight(_ newHeight: CGFloat) {
        advancePanelHeightConstraint?.constant = newHeight
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private func dismissAdvancePanel() {
        sendInputViewController.hideAdvancePanelIfNeeded()
        handleAdvancePanelToggle(visible: false, collapsedHeight: 0)
    }

    private func dismissComposerOverlaysForNavigation() {
        view.endEditing(true)
        isKeyboardVisible = false
        trackedKeyboardHeight = 0
        currentKeyboardOffset = 0
        sendInputViewController.hideAdvancePanelIfNeeded()
        suppressScrollToBottomForNextKeyboardInset = false
        if let layout = lastLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    private func handleAdvanceAction(_ item: AdvancedFunctionItem) {
        switch item.id {
        case "pickFiles":
            sendInputViewController.openFilePicker()
        case "location":
            guard !AnonymousMessageStore.isEnabled(clanId: clanId) else { return }
            handleSendLocation()
        case "buzz":
            handleBuzzMessage()
        case "anonymous":
            guard clanId != 0, !clanPreventsAnonymous() else { return }
            _ = AnonymousMessageStore.toggle(clanId: clanId)
            sendInputViewController.refreshAnonymousUI()
            rebuildAdvancePanelActions()
            DispatchQueue.main.async { [weak self] in
                self?.sendInputViewController.focusTextInput()
            }
        case "transfer_funds":
            navigateToTransferFunds()
        case "create_poll":
            navigateToCreatePoll()
        case "share_contact":
            navigateToShareContact()
        default:
            let toast = UILabel()
            toast.text = "  \(item.label.replacingOccurrences(of: "\n", with: " ")) — Coming soon  "
            toast.font = .systemFont(ofSize: 14, weight: .medium)
            toast.textColor = .white
            toast.backgroundColor = UIColor(white: 0.2, alpha: 0.9)
            toast.layer.cornerRadius = 20
            toast.clipsToBounds = true
            toast.textAlignment = .center
            toast.sizeToFit()
            toast.frame.size.height = 40
            toast.frame.size.width += 32
            toast.center = CGPoint(x: view.bounds.midX, y: view.bounds.height - 120)
            toast.alpha = 0
            view.addSubview(toast)

            UIView.animate(withDuration: 0.3, animations: {
                toast.alpha = 1
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 1.5, options: [], animations: {
                    toast.alpha = 0
                }) { _ in
                    toast.removeFromSuperview()
                }
            }
        }
    }

    private func navigateToShareContact() {
        dismissComposerOverlaysForNavigation()

        let vc = ShareContactPickerViewController(context: context)
        vc.onSelectFriend = { [weak self, weak vc] friend in
            guard let self else { return }
            self.sendInputViewController.sendShareContact(friend: friend)
            vc?.navigationController?.popViewController(animated: true)
            DispatchQueue.main.async {
                self.sendInputViewController.focusTextInput()
            }
        }

        if let nav = navigationController {
            nav.pushViewController(vc, animated: true)
        } else {
            present(UINavigationController(rootViewController: vc), animated: true)
        }
    }

    private func navigateToCreatePoll() {
        dismissComposerOverlaysForNavigation()
        let createVC = CreatePollViewController(context: self.context, channelId: self.channel.channelID, clanId: self.clanId)
        navigationController?.pushViewController(createVC, animated: true)
    }


    private func navigateToTransferFunds() {
        dismissComposerOverlaysForNavigation()
        let payload = TransferQRPayload(
            receiverUserId: nil,
            walletAddress: nil,
            suggestedAmount: nil,
            note: nil,
            extraAttribute: nil,
            receiverDisplayName: nil
        )
        let vc = WalletTransferViewController(context: context, payload: payload)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func handleSendLocation() {
        dismissComposerOverlaysForNavigation()
        DispatchQueue.main.async { [weak self] in
            self?.beginLocationAuthorizationFlow()
        }
    }

    private func beginLocationAuthorizationFlow() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .notDetermined:
            locationManager.delegate = self
            isWaitingForLocationAuthorization = true
            locationCompletion = { [weak self] coord in
                guard let self, let coord else { return }
                self.showLocationConfirm(coordinate: coord)
            }
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            fetchLocationAndShowConfirm()
        case .denied, .restricted:
            showLocationPermissionDeniedAlert()
        @unknown default:
            break
        }
    }

    private func recentCachedCoordinate(from manager: CLLocationManager) -> CLLocationCoordinate2D? {
        guard let location = manager.location else { return nil }
        guard location.horizontalAccuracy >= 0 else { return nil }
        guard abs(location.timestamp.timeIntervalSinceNow) <= Self.cachedLocationMaxAge else { return nil }
        return location.coordinate
    }

    private func cancelLocationFetchTimeout() {
        locationFetchTimeoutWorkItem?.cancel()
        locationFetchTimeoutWorkItem = nil
    }

    private func scheduleLocationFetchTimeout(for manager: CLLocationManager) {
        cancelLocationFetchTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.locationCompletion != nil else { return }
            manager.delegate = nil
            self.isWaitingForLocationAuthorization = false
            let completion = self.locationCompletion
            self.locationCompletion = nil
            if let cached = self.recentCachedCoordinate(from: manager) {
                completion?(cached)
            } else {
                completion?(nil)
            }
        }
        locationFetchTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.locationFetchTimeout, execute: work)
    }

    private func fetchLocationAndShowConfirm() {
        if let cached = recentCachedCoordinate(from: locationManager) {
            showLocationConfirm(coordinate: cached)
            return
        }

        locationManager.delegate = self
        isWaitingForLocationAuthorization = false
        locationCompletion = { [weak self] coord in
            guard let self, let coord else { return }
            self.showLocationConfirm(coordinate: coord)
        }
        scheduleLocationFetchTimeout(for: locationManager)
        locationManager.requestLocation()
    }

    private func handleLocationAuthorizationStatus(_ status: CLAuthorizationStatus, manager: CLLocationManager) {
        guard isWaitingForLocationAuthorization else { return }
        guard status != .notDetermined else { return }

        isWaitingForLocationAuthorization = false
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            fetchLocationAndShowConfirm()
        case .denied, .restricted:
            cancelLocationFetchTimeout()
            manager.delegate = nil
            let completion = locationCompletion
            locationCompletion = nil
            completion?(nil)
            showLocationPermissionDeniedAlert()
        case .notDetermined:
            break
        @unknown default:
            cancelLocationFetchTimeout()
            manager.delegate = nil
            locationCompletion = nil
        }
    }

    private func showLocationConfirm(coordinate: CLLocationCoordinate2D) {
        let label = channelLabel.isEmpty ? "this channel" : channelLabel
        let confirmVC = ShareLocationConfirmViewController(coordinate: coordinate, channelLabel: label)
        confirmVC.onSend = { [weak self] lat, lng in
            guard let self else { return }
            self.sendInputViewController.sendLocation(latitude: lat, longitude: lng)
            DispatchQueue.main.async {
                self.sendInputViewController.focusTextInput()
            }
        }

        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(confirmVC, animated: true)
    }

    private func showLocationPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Location Permission",
            message: "Mezon needs access to your location to share it. Please enable location access in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })

        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    }

    private func handleBuzzMessage() {
        let buzzVC = BuzzMessageViewController()
        buzzVC.onSend = { [weak self] text in
            guard let self else { return }
            self.sendInputViewController.sendBuzzMessage(text: text)
            DispatchQueue.main.async {
                self.sendInputViewController.focusTextInput()
            }
        }

        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(buzzVC, animated: true)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    func jumpToMessageFromChannelDetail(messageId: String) {
        jumpToMessage(id: messageId)
    }

    private func jumpToMessage(id messageId: String) {
        shouldScrollToBottom = false
        isJumping = true

        if messages.contains(where: { $0.id == messageId }) {
            messagesNode.pendingJumpMessageId = messageId
            messagesNode.triggerPendingJump()
            return
        }

        guard let msgId = Int64(messageId) else {
            finishMessageJump(messageId: messageId)
            return
        }

        readyToLoadMore = false
        messagesNode.pendingJumpMessageId = messageId
        lastFetchedOlderMessageId = nil
        lastFetchedNewerMessageId = nil

        setIsLoadingMessageContext(true)
        Task { @MainActor in
            defer {
                self.setIsLoadingMessageContext(false)
            }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else {
                self.messagesNode.pendingJumpMessageId = nil
                self.finishMessageJump(messageId: messageId)
                return
            }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: self.clanId,
                    channelId: self.channel.channelID,
                    messageId: msgId,
                    direction: 2,
                    limit: 30,
                    topicId: self.topicId,
                    token: token
                )
                guard response.messages.contains(where: { $0.messageID == msgId }) else {
                    self.messagesNode.pendingJumpMessageId = nil
                    self.finishMessageJump(messageId: messageId)
                    return
                }
                self.setHasMoreOlder(response.messages.count > 1)
                self.setHasMoreNewer(true)
                self.context.account.postbox.write { tx in
                    tx.replaceAllMessages(
                        response.messages.map { self.messageRecord(from: $0) },
                        channelId: self.storageChannelId
                    )
                }
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "ChatViewController.jumpToMessage",
                    "channelId": self.channel.channelID,
                    "clanId": self.clanId,
                    "anchorMessageId": msgId,
                ])
                self.messagesNode.pendingJumpMessageId = nil
                self.finishMessageJump(messageId: messageId)
            }
        }
    }

    private func forceScrollToBottom(completion: (() -> Void)? = nil) {
        guard !messages.isEmpty else { return }
        messagesNode.listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: ListViewScrollToItem(index: 0, position: .top(0), animated: false, curve: .Default(duration: nil), directionHint: .Up),
            updateOpaqueState: nil,
            completion: { _ in completion?() }
        )
    }

    private func scrollToBottomIfNeeded() {
        guard messagesNode.pendingJumpMessageId == nil else { return }
        guard !messagesNode.didAutoScrollForNewMessages else { return }
        guard shouldScrollToBottom, !messages.isEmpty else { return }
        messagesNode.listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: ListViewScrollToItem(index: 0, position: .top(0), animated: true, curve: .Spring(duration: 0.3), directionHint: .Up),
            updateOpaqueState: nil,
            completion: { _ in }
        )
    }

    private func scrollToUnreadLine(lastSeenId: String) {
        guard messagesNode.pendingJumpMessageId == nil else { return }
        guard !messages.isEmpty else { return }
        if let lineIndex = messagesNode.committedMessageIds.firstIndex(of: ChatContainerNode.unreadLineId) {
            messagesNode.listView.transaction(
                deleteIndices: [],
                insertIndicesAndItems: [],
                updateIndicesAndItems: [],
                options: [.Synchronous],
                scrollToItem: ListViewScrollToItem(index: lineIndex, position: .center(.bottom), animated: false, curve: .Default(duration: nil), directionHint: .Down),
                updateOpaqueState: nil,
                completion: { _ in }
            )
        }
    }

    private func openTopicDiscussion(topicData: TopicData) {
        guard let topicIdInt = Int64(topicData.topicId), topicIdInt != 0 else { return }
        var topicChannel = channel
        topicChannel.channelLabel = L(L10n.MessageAction.topicDiscussion)
        let topicVC = ChatViewController(
            clanId: clanId, channel: topicChannel, context: context, parentName: nil)
        topicVC.topicId = topicIdInt
        topicVC.skipRemoteFetchWhileTopicIsEmpty = topicData.replyCount <= 0
        needsRefreshAfterTopicDiscussion = true
        navigationController?.pushViewController(topicVC, animated: true)
    }

    private func createTopicDiscussion(from display: ChatMessageDisplay) {
        guard canCreateTopicDiscussion(for: display),
              let messageId = Int64(display.message.id) else { return }

        var topicChannel = channel
        topicChannel.channelLabel = L(L10n.MessageAction.topicDiscussion)
        let topicVC = ChatViewController(
            clanId: clanId, channel: topicChannel, context: context, parentName: nil
        )
        topicVC.configureAsPendingTopicCreation(sourceMessageId: messageId)
        needsRefreshAfterTopicDiscussion = true
        navigationController?.pushViewController(topicVC, animated: true)
    }

    private func configurePendingTopicCreationIfNeeded() {
        guard pendingTopicCreationMessageId != nil else { return }
        sendInputViewController.primarySendActionOverride = { [weak self] in
            self?.performPendingTopicCreationAndSend()
        }
    }

    private func performPendingTopicCreationAndSend() {
        guard let messageId = pendingTopicCreationMessageId else {
            sendInputViewController.send()
            return
        }
        guard !isCreatingTopicDiscussion else { return }
        guard sendInputViewController.hasComposerSendPayload() else { return }
        isCreatingTopicDiscussion = true

        Task { @MainActor in
            defer { self.isCreatingTopicDiscussion = false }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }

            do {
                let topic = try await self.context.engine.topicDiscussion.createTopic(
                    clanId: self.clanId,
                    channelId: self.channel.channelID,
                    messageId: messageId,
                    token: token
                )
                guard topic.id != 0 else {
                    Toast.error(MezonError.invalidResponse.localizedDescription)
                    return
                }
                let creatorIdValue = topic.creatorID != 0
                    ? topic.creatorID
                    : (Int64(self.context.currentUser?.id ?? "") ?? 0)
                let parentChannelIdStr = "\(self.channel.channelID)"
                self.context.account.postbox.write { tx in
                    tx.updateMessageTopicMetadata(
                        messageId: "\(messageId)",
                        channelId: parentChannelIdStr,
                        topicId: topic.id,
                        creatorId: creatorIdValue
                    )
                }

                self.pendingTopicCreationMessageId = nil
                self.sendInputViewController.primarySendActionOverride = nil
                self.skipRemoteFetchWhileTopicIsEmpty = false
                self.sendInputViewController.syncStoredDraftIdentity(
                    channel: channel,
                    topicId: topic.id,
                    migrateDraftToNewChannelIdentity: true,
                    preserveComposerContentsDuringMigration: true
                )
                self.topicId = topic.id
                self.bindMessageHistoryView()
                self.sendInputViewController.send()
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private static let threadListFetchPageLimit: Int32 = 50
    private static let threadListFetchMaxPages: Int32 = 40

    private func openThreadFromSystemMessage(threadChannelId: Int64, threadLabel: String?) {
        guard clanId != 0, threadChannelId != 0 else { return }
        let parentChannelId = systemThreadParentChannelId()
        guard parentChannelId != 0 else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error("No session")
                return
            }
            do {
                let resolved = try await self.resolveThreadChannelForSystemNavigation(
                    threadChannelId: threadChannelId,
                    parentChannelId: parentChannelId,
                    threadLabel: threadLabel,
                    token: token
                )
                self.context.engine.clanData.applyLocallyCreatedChannel(resolved)

                let parentLabel: String? = {
                    if self.channel.type == MezonConstants.ChannelType.thread.rawValue {
                        return self.initialParentName
                    }
                    let label = self.channel.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    return label.isEmpty ? self.initialParentName : label
                }()

                let chatVC = ChatViewController(
                    clanId: self.clanId,
                    channel: resolved,
                    context: self.context,
                    parentName: parentLabel
                )
                self.navigationController?.pushViewController(chatVC, animated: true)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func systemThreadParentChannelId() -> Int64 {
        if channel.type == MezonConstants.ChannelType.thread.rawValue, channel.parentID != 0 {
            return channel.parentID
        }
        return channel.channelID
    }

    private func resolveThreadChannelForSystemNavigation(
        threadChannelId: Int64,
        parentChannelId: Int64,
        threadLabel: String?,
        token: String
    ) async throws -> Mezon_Api_ChannelDescription {
        if let cached = cachedThreadDescription(threadChannelId: threadChannelId, parentChannelId: parentChannelId) {
            return cached
        }
        if let fetched = try await context.account.network.fetchThreadDesc(
            threadId: threadChannelId,
            parentChannelId: parentChannelId,
            clanId: clanId,
            token: token
        ) {
            return normalizeThreadDescription(fetched, threadChannelId: threadChannelId, parentChannelId: parentChannelId, threadLabel: threadLabel)
        }
        if let label = threadLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
           let searched = try await context.account.network.searchThread(
               clanId: clanId,
               parentChannelId: parentChannelId,
               label: label,
               token: token
           ).channeldesc.first(where: { $0.channelID == threadChannelId || $0.channelLabel == label }) {
            return normalizeThreadDescription(searched, threadChannelId: threadChannelId, parentChannelId: parentChannelId, threadLabel: label)
        }
        if let listed = try await findThreadInPaginatedList(
            threadChannelId: threadChannelId,
            parentChannelId: parentChannelId,
            token: token
        ) {
            return normalizeThreadDescription(listed, threadChannelId: threadChannelId, parentChannelId: parentChannelId, threadLabel: threadLabel)
        }

        var fallback = Mezon_Api_ChannelDescription()
        fallback.channelID = threadChannelId
        fallback.parentID = parentChannelId
        fallback.clanID = clanId
        fallback.type = MezonConstants.ChannelType.thread.rawValue
        if let label = threadLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            fallback.channelLabel = label
        }
        return fallback
    }

    private func cachedThreadDescription(threadChannelId: Int64, parentChannelId: Int64) -> Mezon_Api_ChannelDescription? {
        if let found = context.engine.clanData.getAllChannelsByUser()?.channeldesc.first(where: {
            $0.channelID == threadChannelId && ($0.parentID == parentChannelId || $0.parentID == 0)
        }) {
            return found
        }
        if let data = context.account.postbox.getPreferenceData(
            key: PreferencesKeys.threadList(clanId: clanId, parentChannelId: parentChannelId)
        ), let threads = Self.decodeThreadListPreference(data) {
            if let found = threads.first(where: { $0.channelID == threadChannelId }) {
                return found
            }
        }
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) {
            let channels = ChannelPreferenceListCodec.decode(data)
            if let found = channels.first(where: { $0.channelID == threadChannelId && $0.parentID == parentChannelId }) {
                return found
            }
        }
        return nil
    }

    private func findThreadInPaginatedList(
        threadChannelId: Int64,
        parentChannelId: Int64,
        token: String
    ) async throws -> Mezon_Api_ChannelDescription? {
        var page: Int32 = 1
        while page <= Self.threadListFetchMaxPages {
            let list = try await context.account.network.listThreadDescs(
                parentChannelId: parentChannelId,
                clanId: clanId,
                page: page,
                limit: Self.threadListFetchPageLimit,
                token: token
            )
            if let found = list.channeldesc.first(where: { $0.channelID == threadChannelId }) {
                return found
            }
            if list.channeldesc.count < Int(Self.threadListFetchPageLimit) { break }
            page += 1
        }
        return nil
    }

    private func normalizeThreadDescription(
        _ thread: Mezon_Api_ChannelDescription,
        threadChannelId: Int64,
        parentChannelId: Int64,
        threadLabel: String?
    ) -> Mezon_Api_ChannelDescription {
        var resolved = thread
        if resolved.channelID == 0 { resolved.channelID = threadChannelId }
        if resolved.parentID == 0 { resolved.parentID = parentChannelId }
        if resolved.clanID == 0 { resolved.clanID = clanId }
        if resolved.type == 0 { resolved.type = MezonConstants.ChannelType.thread.rawValue }
        if resolved.channelLabel.isEmpty,
           let label = threadLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            resolved.channelLabel = label
        }
        return resolved
    }

    private static func decodeThreadListPreference(_ data: Data) -> [Mezon_Api_ChannelDescription]? {
        guard data.count >= 12 else { return nil }
        let count = data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 12
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result.isEmpty ? nil : result
    }

    private func openThreadListFromChat() {
        let parentId: Int64 =
            channel.type == MezonConstants.ChannelType.thread.rawValue
            ? channel.parentID
            : channel.channelID
        let composerSurface: Mezon_Api_ChannelDescription = {
            guard channel.type == MezonConstants.ChannelType.thread.rawValue else { return channel }
            var d = channel
            d.channelID = channel.parentID
            d.parentID = 0
            d.type = MezonConstants.ChannelType.forum.rawValue
            return d
        }()
        let vc = ThreadListViewController(
            context: context,
            clanId: clanId,
            parentChannelId: parentId,
            parentCategoryId: channel.categoryID,
            parentChannelLabel: channel.channelLabel,
            composerParentChannel: composerSurface
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private static let createThreadUnsupportedChannelTypes: Set<Int32> = [
        MezonConstants.ChannelType.dm.rawValue,
        MezonConstants.ChannelType.group.rawValue,
        MezonConstants.ChannelType.thread.rawValue,
        MezonConstants.ChannelType.app.rawValue,
        MezonConstants.ChannelType.mezonVoice.rawValue,
        MezonConstants.ChannelType.streaming.rawValue,
    ]

    private func createThreadParentChannelId() -> Int64 {
        channel.type == MezonConstants.ChannelType.thread.rawValue
            ? channel.parentID
            : channel.channelID
    }

    private func canCreateThreadFromMessage(for display: ChatMessageDisplay) -> Bool {
        if clanId == 0 { return false }
        if topicId != 0 { return false }
        if display.isFailed { return false }
        if display.message.id.hasPrefix("pending-") { return false }
        if display.message.isDeleted { return false }
        if display.isSystemMessage { return false }
        if display.isBuzzMessage { return false }
        if display.isTopic { return false }
        if AnonymousMessageStore.isEnabled(clanId: clanId) { return false }
        if Self.createThreadUnsupportedChannelTypes.contains(channel.type) { return false }

        let parentId = createThreadParentChannelId()
        guard parentId != 0 else { return false }
        return context.rolePermissions.canManageThread(clanId: clanId, channelId: parentId)
    }

    private func resolvedParentCategoryId(parentId: Int64) -> Int64 {
        if let parent = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: parentId),
           parent.categoryID != 0 {
            return parent.categoryID
        }
        return channel.categoryID
    }

    private func createThreadFormParentContext() -> (
        parentId: Int64,
        parentCategoryId: Int64,
        parentLabel: String,
        composerSurface: Mezon_Api_ChannelDescription
    ) {
        let parentId = createThreadParentChannelId()
        let parentLabel: String = {
            if channel.type == MezonConstants.ChannelType.thread.rawValue {
                let label = parentChannelMeta?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !label.isEmpty { return label }
            }
            let label = channel.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { return label }
            return channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        let composerSurface: Mezon_Api_ChannelDescription = {
            guard channel.type == MezonConstants.ChannelType.thread.rawValue else { return channel }
            var d = channel
            d.channelID = channel.parentID
            d.parentID = 0
            d.type = MezonConstants.ChannelType.forum.rawValue
            return d
        }()
        return (parentId, resolvedParentCategoryId(parentId: parentId), parentLabel, composerSurface)
    }

    private func presentCreateThreadForm(from display: ChatMessageDisplay) {
        guard canCreateThreadFromMessage(for: display) else {
            Toast.error(L(L10n.ThreadList.createThreadForbidden))
            return
        }
        let ctx = createThreadFormParentContext()
        let form = CreateThreadFormViewController(
            context: context,
            clanId: clanId,
            parentChannelId: ctx.parentId,
            parentCategoryId: ctx.parentCategoryId,
            parentChannelLabel: ctx.parentLabel,
            composerParentChannel: ctx.composerSurface,
            seedMessageDisplay: display,
            onComplete: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let createdChannel):
                    Toast.success(L(L10n.ThreadList.createThreadSuccess))
                    self.context.currentClanId = self.clanId
                    let vc = ChatViewController(clanId: self.clanId, channel: createdChannel, context: self.context)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
                case .failure:
                    break
                }
            }
        )
        let nav = UINavigationController(rootViewController: form)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.present(nav, animated: true)
        }
    }

    private func openChannelDetail() {
        var ch = channel
        let protoLabel = ch.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if protoLabel.isEmpty {
            let fb = channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fb.isEmpty { ch.channelLabel = fb }
        }
        let vc = ChannelDetailViewController(
            context: self.context,
            clanId: self.clanId,
            channel: ch
        )
        self.navigationController?.pushViewController(vc, animated: true)
    }

    private func enrichParsedContent(_ parsed: ParsedContent, fallbackClanId: String?) -> ParsedContent {
        let channels = context.engine.clanData.getAllChannelsByUser()?.channeldesc ?? []
        let fallbackClan = fallbackClanId.flatMap { Int64($0) } ?? 0
        let newTokens: [ContentToken] = parsed.tokens.map { token in
            switch token.kind {
            case .mezonChannelLink(let isVk, let cid, let gid):
                return enrichMezonChannelLinkToken(
                    token: token, isVk: isVk, channelId: cid, clanId: gid,
                    channels: channels, fallbackClan: fallbackClan, fallbackClanId: fallbackClanId
                )
            case .hashtag(let cid, let clanIdOpt, let parentIdOpt, let label, let ctype, _, _):
                if ctype != nil { return token }
                guard let cid, !cid.isEmpty, let idInt = Int64(cid) else { return token }
                let clanInt = clanIdOpt.flatMap { Int64($0) } ?? fallbackClan
                if let ch = channels.first(where: { $0.channelID == idInt && (clanInt == 0 || $0.clanID == clanInt) }) {
                    return ContentToken(
                        start: token.start,
                        end: token.end,
                        kind: .hashtag(
                            channelId: cid,
                            clanId: clanIdOpt,
                            parentId: parentIdOpt ?? (ch.parentID != 0 ? "\(ch.parentID)" : nil),
                            channelLabel: label,
                            channelType: ch.type,
                            channelPrivate: ch.channelPrivate,
                            ageRestricted: ch.ageRestricted
                        )
                    )
                }
                return token
            default:
                return token
            }
        }
        return ParsedContent(text: parsed.text, tokens: newTokens, embeds: parsed.embeds, ogpPreviews: parsed.ogpPreviews)
    }

    private func enrichMezonChannelLinkToken(
        token: ContentToken,
        isVk: Bool,
        channelId: String,
        clanId: String,
        channels: [Mezon_Api_ChannelDescription],
        fallbackClan: Int64,
        fallbackClanId: String?
    ) -> ContentToken {
        guard !channelId.isEmpty, let idInt = Int64(channelId) else { return token }
        let clanInt: Int64 = {
            if let g = Int64(clanId), g > 0 { return g }
            return fallbackClan
        }()
        let clanOut: String? = {
            if !clanId.isEmpty { return clanId }
            if fallbackClan > 0 { return "\(fallbackClan)" }
            return fallbackClanId
        }()
        if let ch = channels.first(where: { $0.channelID == idInt && (clanInt == 0 || $0.clanID == clanInt) }) {
            return ContentToken(
                start: token.start,
                end: token.end,
                kind: .hashtag(
                    channelId: channelId,
                    clanId: clanOut,
                    parentId: ch.parentID != 0 ? "\(ch.parentID)" : nil,
                    channelLabel: ch.channelLabel,
                    channelType: ch.type,
                    channelPrivate: ch.channelPrivate,
                    ageRestricted: ch.ageRestricted
                )
            )
        }
        let defaultType: Int32 = isVk ? MezonConstants.ChannelType.mezonVoice.rawValue : MezonConstants.ChannelType.channel.rawValue
        let defaultLabel = isVk
            ? NSLocalizedString("voiceChannel.defaultName", tableName: nil, bundle: .main, value: "Voice", comment: "")
            : "Channel"
        return ContentToken(
            start: token.start,
            end: token.end,
            kind: .hashtag(
                channelId: channelId,
                clanId: clanOut,
                parentId: nil,
                channelLabel: defaultLabel,
                channelType: defaultType,
                channelPrivate: 0,
                ageRestricted: 0
            )
        )
    }

    private func resolveVoiceMemberForJoinVoice(userId: String, clanIdForMembers: Int64) -> VoiceMemberDisplay? {
        guard let uidInt = Int64(userId) else { return nil }
        let profile = context.account.postbox.read { $0.getProfile(userId: userId) }
        let member = context.account.postbox.read {
            $0.getClanMembers(clanId: clanIdForMembers)
        }.first(where: { $0.userId == uidInt })
        let name: String
        let username: String
        if let m = member {
            if !m.clanNick.isEmpty {
                name = m.clanNick
            } else if !m.displayName.isEmpty {
                name = m.displayName
            } else if !m.username.isEmpty {
                name = m.username
            } else {
                return nil
            }
            username = m.username
        } else if let profile {
            name = (profile.displayName?.isEmpty == false ? profile.displayName : nil) ?? profile.username
            username = profile.username
        } else {
            return nil
        }
        let avatar: String?
        if let m = member {
            avatar = m.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl)
        } else {
            avatar = profile?.avatarUrl.flatMap { $0.isEmpty ? nil : $0 }
        }
        return VoiceMemberDisplay(name: name, username: username, avatarURL: avatar)
    }

    private func parentChannelNameForVoice(channel: Mezon_Api_ChannelDescription) -> String? {
        guard channel.parentID != 0 else { return nil }
        let channels = context.engine.clanData.getAllChannelsByUser()?.channeldesc ?? []
        return channels.first(where: { $0.channelID == channel.parentID })?.channelLabel
    }

    private func effectiveClanIdForVoiceChannel(_ channel: Mezon_Api_ChannelDescription) -> Int64 {
        channel.clanID != 0 ? channel.clanID : clanId
    }

    private func encodeChannelIdPreference(_ id: Int64) -> Data {
        var le = id.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    private func persistSelectedChannelForVoice(_ channel: Mezon_Api_ChannelDescription) {
        let cid = effectiveClanIdForVoiceChannel(channel)
        context.account.postbox.setPreferenceData(
            key: PreferencesKeys.selectedChannelId(clanId: cid),
            value: encodeChannelIdPreference(channel.channelID))
    }

    private func alignContextWithVoiceChannelClan(for channel: Mezon_Api_ChannelDescription) {
        let targetClan = effectiveClanIdForVoiceChannel(channel)
        persistSelectedChannelForVoice(channel)
        guard targetClan != 0, targetClan != context.currentClanId else { return }
        context.currentClanId = targetClan
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.context.account.socket.isConnected {
                await self.waitForSocketConnected()
            }
            await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: self.context, clanId: targetClan, force: true)
            if self.context.account.socket.isConnected {
                self.context.account.socket.joinClanChat(clanId: targetClan)
            }
        }
        NotificationCenter.default.post(
            name: Notification.Name("MezonJoinedClanChatForBadges"),
            object: nil,
            userInfo: ["clanId": targetClan]
        )
        Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            self.context.engine.clanData.fetchAllClanData(clanId: targetClan, token: token)
        }
    }

    private func pushVoiceChannelRoomFromChat(channel: Mezon_Api_ChannelDescription) {
        guard let nav = navigationController else { return }
        let ch = channel
        let ctx = context
        let parentName = parentChannelNameForVoice(channel: ch)
        let voiceClan = effectiveClanIdForVoiceChannel(ch)
        let crossClanVoiceJoin = ch.type == MezonConstants.ChannelType.mezonVoice.rawValue
            && voiceClan != 0 && voiceClan != clanId
        let rootNav = nav as? MezonRootController
        let home = rootNav?.homeController
        if crossClanVoiceJoin {
            home?.alignHomeForCrossClanVoice(clanId: voiceClan, voiceChannelId: ch.channelID)
        } else {
            alignContextWithVoiceChannelClan(for: ch)
            home?.focusClansTabAndSelectVoiceChannelOnly(ch.channelID)
        }
        if let mezonNav = nav as? NavigationController {
            mezonNav.popToRoot(animated: false)
        } else {
            nav.popToRootViewController(animated: false)
        }
        let pushNav = rootNav ?? nav
        let pip = VoiceChannelPiPOverlay.shared
        if pip.isActive {
            if pip.channel?.channelID == ch.channelID {
                let vc = VoiceChannelRoomViewController(
                    context: ctx,
                    channel: ch,
                    parentChannelName: parentName,
                    voiceChannelCrossClanExitAlignClanId: crossClanVoiceJoin ? nil : pip.crossClanVoiceExitAlignClanId,
                    existingPiPOverlay: pip
                )
                pushNav.pushViewController(vc, animated: true)
                return
            } else {
                pip.dismiss()
            }
        }
        let vc = VoiceChannelRoomViewController(
            context: ctx,
            channel: ch,
            parentChannelName: parentName,
            voiceChannelCrossClanExitAlignClanId: nil
        )
        pushNav.pushViewController(vc, animated: true)
    }

    private func presentJoinVoiceSheet(for channel: Mezon_Api_ChannelDescription) {
        view.endEditing(true)
        let title = channel.channelLabel.isEmpty
            ? NSLocalizedString("voiceChannel.defaultName", tableName: nil, bundle: .main, value: "Voice", comment: "")
            : channel.channelLabel
        let clanForMembers = channel.clanID != 0 ? channel.clanID : clanId
        var voiceUserIds: [String] = []
        let sources: [Mezon_Api_VoiceChannelUserList?] = [
            context.engine.clanData.getVoiceUsers(clanId: clanForMembers),
            context.engine.clanData.getStreamUsers(clanId: clanForMembers),
        ]
        for list in sources.compactMap({ $0 }) {
            for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !voiceUserIds.contains(uid) {
                    voiceUserIds.append(uid)
                }
            }
        }
        let resolvedMembers = voiceUserIds.compactMap { resolveVoiceMemberForJoinVoice(userId: $0, clanIdForMembers: clanForMembers) }
        let targetClan = channel.clanID != 0 ? channel.clanID : clanId
        let sheet = JoinVoiceChannelSheetViewController(
            channelTitle: title,
            chatUnreadCount: Int(channel.countMessUnread),
            members: resolvedMembers,
            onChat: { [weak self] in
                guard let self, let nav = self.navigationController else { return }
                self.alignContextWithVoiceChannelClan(for: channel)
                let parentName = self.parentChannelNameForVoice(channel: channel)
                let chatVC = ChatViewController(
                    clanId: targetClan,
                    channel: channel,
                    context: self.context,
                    parentName: parentName
                )
                nav.pushViewController(chatVC, animated: true)
            },
            onJoinVoice: { [weak self] in
                guard let self else { return }
                self.pushVoiceChannelRoomFromChat(channel: channel)
            },
            onInvite: {}
        )
        sheet.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            sheet.sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = JoinVoiceChannelSheetViewController.preferredSheetHeight(
                    safeAreaBottomInset: bottomInset, hasMembers: !resolvedMembers.isEmpty)
                let detentId = JoinVoiceChannelSheetViewController.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { ctx in
                    min(targetHeight, ctx.maximumDetentValue)
                }
                sheet.sheetPresentationController?.detents = [contentDetent]
                sheet.sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheet.sheetPresentationController?.detents = [.medium(), .large()]
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        present(sheet, animated: true)
        CATransaction.commit()
    }

    private func presentJoinStreamSheet(for channel: Mezon_Api_ChannelDescription) {
        view.endEditing(true)
        let title = channel.channelLabel.isEmpty
            ? NSLocalizedString("streamingRoom.defaultName", tableName: nil, bundle: .main, value: "Stream", comment: "")
            : channel.channelLabel
        let clanForMembers = channel.clanID != 0 ? channel.clanID : clanId
        var streamUserIds: [String] = []
        if let list = context.engine.clanData.getStreamUsers(clanId: clanForMembers) {
            for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !streamUserIds.contains(uid) {
                    streamUserIds.append(uid)
                }
            }
        }
        let resolvedMembers = streamUserIds.compactMap {
            resolveVoiceMemberForJoinVoice(userId: $0, clanIdForMembers: clanForMembers)
        }
        let targetClan = channel.clanID != 0 ? channel.clanID : clanId
        let sheet = JoinVoiceChannelSheetViewController(
            channelTitle: title,
            chatUnreadCount: Int(channel.countMessUnread),
            members: resolvedMembers,
            kind: .streaming,
            onChat: { [weak self] in
                guard let self, let nav = self.navigationController else { return }
                self.alignContextWithVoiceChannelClan(for: channel)
                let parentName = self.parentChannelNameForVoice(channel: channel)
                let chatVC = ChatViewController(
                    clanId: targetClan,
                    channel: channel,
                    context: self.context,
                    parentName: parentName
                )
                nav.pushViewController(chatVC, animated: true)
            },
            onJoinVoice: { [weak self] in
                guard let self else { return }
                self.pushStreamingRoomFromChat(channel: channel)
            },
            onInvite: {}
        )
        sheet.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            sheet.sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = JoinVoiceChannelSheetViewController.preferredSheetHeight(
                    safeAreaBottomInset: bottomInset, hasMembers: !resolvedMembers.isEmpty)
                let detentId = JoinVoiceChannelSheetViewController.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { ctx in
                    min(targetHeight, ctx.maximumDetentValue)
                }
                sheet.sheetPresentationController?.detents = [contentDetent]
                sheet.sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheet.sheetPresentationController?.detents = [.medium(), .large()]
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        present(sheet, animated: true)
        CATransaction.commit()
    }

    private func pushStreamingRoomFromChat(channel: Mezon_Api_ChannelDescription) {
        alignContextWithVoiceChannelClan(for: channel)
        guard let nav = navigationController else { return }

        let clanId = channel.clanID != 0 ? channel.clanID : self.clanId
        let pip = StreamingPiPOverlay.shared
        if pip.isActive, pip.channel?.channelID == channel.channelID {
            pip.restoreFullScreen(animated: true)
            return
        }

        if let existing = nav.viewControllers.last(where: {
            ($0 as? StreamingRoomViewController)?.streamChannelId == channel.channelID
        }) {
            StreamingRoomViewController.prepareJoiningStream(
                targetChannelId: channel.channelID,
                clanId: clanId,
                context: context,
                navigationController: nav
            )
            if nav.topViewController !== existing {
                nav.popToViewController(existing, animated: false)
            }
            return
        }

        StreamingRoomViewController.prepareJoiningStream(
            targetChannelId: channel.channelID,
            clanId: clanId,
            context: context,
            navigationController: nav
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken(),
                  let userId = self.context.currentUser?.id,
                  let username = self.context.currentUser?.username else { return }

            await StreamingWebRTCSession.shared.join(
                clanId: channel.clanID != 0 ? channel.clanID : self.clanId,
                channelId: channel.channelID,
                streamId: channel.channelID,
                userId: userId,
                username: username,
                token: token
            )

            if let uid = Int64(userId) {
                self.context.engine.clanData.applyStreamJoined(
                    clanId: channel.clanID != 0 ? channel.clanID : self.clanId,
                    channelId: channel.channelID,
                    userId: uid
                )
            }

            let vc = StreamingRoomViewController(
                context: self.context,
                channel: channel,
                parentChannelName: self.parentChannelNameForVoice(channel: channel)
            )
            nav.pushViewController(vc, animated: true)
        }
    }


    private func handleEmbedButtonClicked(button: ParsedEmbedButton, messageId: String, display: ChatMessageDisplay) {
        
        if let urlStr = button.url, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
            return
        }

        let extraData = EmbedFormState.shared.getJSONString(for: messageId)
        let currentUserId = Int64(context.currentUser?.id ?? "") ?? 0
        let senderId = Int64(display.message.senderId) ?? 0
        let realMessageId = Int64(messageId) ?? 0

        let channelId = channel.channelID
        let token = context.session?.token ?? ""

        Task {
            do {
                try await MezonHTTPClient.shared.messageButtonClick(
                    messageId: realMessageId,
                    channelId: channelId,
                    buttonId: button.id,
                    senderId: senderId,
                    userId: currentUserId,
                    extraData: extraData,
                    token: token
                )
            } catch {
            }
        }
        
        EmbedFormState.shared.clear(messageId: messageId)
        ephemeralMessages.removeAll { $0.id == messageId }
        updateMessagesWithEphemeral()
    }

    private func showMemberProfile(_ display: ChatMessageDisplay) {
        guard !display.isAnonymousSender else { return }
        let senderId = display.message.senderId
        guard let senderIdInt = Int64(senderId) else { return }
        let isCurrentUser = senderId == context.currentUser?.id

        var user = Mezon_Api_User()
        user.id = senderIdInt
        user.displayName = display.senderDisplayName
        if let urlStr = display.avatarURL, !urlStr.isEmpty {
            user.avatarURL = urlStr
        }

        let profile = context.account.postbox.read { $0.getProfile(userId: senderId) }
        
        if user.avatarURL.isEmpty {
            if let av = profile?.avatarUrl, !av.isEmpty {
                user.avatarURL = av
            } else if clanId != 0,
                      let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
                      let found = clanUsers.clanUsers.first(where: { $0.user.id == senderIdInt }) {
                user.avatarURL = found.user.avatarURL
            } else if let allUsers = context.engine.clanData.getAllUserClans(),
                      let found = allUsers.users.first(where: { $0.id == senderIdInt }) {
                user.avatarURL = found.avatarURL
            }
        }

        if let un = profile?.username, !un.isEmpty {
            user.username = un
        } else if clanId != 0,
                  let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
                  let found = clanUsers.clanUsers.first(where: { $0.user.id == senderIdInt }) {
            user.username = found.user.username
        } else if let allUsers = context.engine.clanData.getAllUserClans(),
                  let found = allUsers.users.first(where: { $0.id == senderIdInt }) {
            user.username = found.username
        }

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            isCurrentUser: isCurrentUser,
            clanId: clanId,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            },
            onStartCall: { [weak self] dmChannel in
                self?.startDirectMessageCall(channel: dmChannel, user: user)
            },
            onTransferFunds: { [weak self] payload in
                guard let self else { return }
                let vc = WalletTransferViewController(context: self.context, payload: payload)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func showMemberProfileById(_ userId: String) {
        guard let userIdInt = Int64(userId) else { return }
        let isCurrentUser = userId == context.currentUser?.id

        var user = Mezon_Api_User()
        user.id = userIdInt
        if clanId != 0, let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
           let found = clanUsers.clanUsers.first(where: { $0.user.id == userIdInt }) {
            user = Self.apiUserForMemberProfile(from: found)
        } else if let allUsers = context.engine.clanData.getAllUserClans(),
                  let found = allUsers.users.first(where: { $0.id == userIdInt }) {
            user = found
        }

        let profile = context.account.postbox.read { $0.getProfile(userId: userId) }

        if user.avatarURL.isEmpty, let av = profile?.avatarUrl, !av.isEmpty {
            user.avatarURL = av
        }
        if user.username.isEmpty, let un = profile?.username, !un.isEmpty {
            user.username = un
        }
        if user.displayName.isEmpty, let dn = profile?.displayName, !dn.isEmpty {
            user.displayName = dn
        }

        if user.username.isEmpty || user.displayName.isEmpty {
            let channelMembers = context.account.postbox.read { tx in
                tx.getChannelMeta(channelId: channel.channelID)?.members ?? []
            }
            if let member = channelMembers.first(where: { $0.userId == userIdInt }) {
                if user.username.isEmpty, !member.username.isEmpty {
                    user.username = member.username
                }
                if user.displayName.isEmpty {
                    let memberName = !member.clanNick.isEmpty ? member.clanNick : member.displayName
                    if !memberName.isEmpty {
                        user.displayName = memberName
                    }
                }
                if user.avatarURL.isEmpty, !member.clanAvatar.isEmpty {
                    user.avatarURL = member.clanAvatar
                }
            }
        }

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            isCurrentUser: isCurrentUser,
            clanId: clanId,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            },
            onStartCall: { [weak self] dmChannel in
                self?.startDirectMessageCall(channel: dmChannel, user: user)
            },
            onTransferFunds: { [weak self] payload in
                guard let self else { return }
                let vc = WalletTransferViewController(context: self.context, payload: payload)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func showShareContactProfile(_ data: ShareContactData) {
        guard let userId = data.userIdInt else { return }
        let isCurrentUser = "\(userId)" == context.currentUser?.id
        let user = apiUserForShareContact(data)

        view.endEditing(true)
        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            isCurrentUser: isCurrentUser,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            },
            onTransferFunds: { [weak self] payload in
                guard let self else { return }
                let vc = WalletTransferViewController(context: self.context, payload: payload)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func apiUserForShareContact(_ data: ShareContactData) -> Mezon_Api_User {
        let userId = data.userIdInt ?? 0
        var user = Mezon_Api_User()
        user.id = userId
        user.username = data.resolvedUsername
        user.displayName = data.resolvedDisplayName
        user.avatarURL = data.avatar.trimmingCharacters(in: .whitespacesAndNewlines)

        if let friend = context.engine.friendsData.allFriends().first(where: { $0.hasUser && $0.user.id == userId }) {
            if user.username.isEmpty { user.username = friend.user.username }
            if user.displayName.isEmpty || user.displayName == "\(userId)" { user.displayName = friend.user.displayName }
            if user.avatarURL.isEmpty { user.avatarURL = friend.user.avatarURL }
        } else if clanId != 0,
                  let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
                  let found = clanUsers.clanUsers.first(where: { $0.user.id == userId }) {
            let clanUser = Self.apiUserForMemberProfile(from: found)
            if user.username.isEmpty { user.username = clanUser.username }
            if user.displayName.isEmpty || user.displayName == "\(userId)" { user.displayName = clanUser.displayName }
            if user.avatarURL.isEmpty { user.avatarURL = clanUser.avatarURL }
        } else if let allUsers = context.engine.clanData.getAllUserClans(),
                  let found = allUsers.users.first(where: { $0.id == userId }) {
            if user.username.isEmpty { user.username = found.username }
            if user.displayName.isEmpty || user.displayName == "\(userId)" { user.displayName = found.displayName }
            if user.avatarURL.isEmpty { user.avatarURL = found.avatarURL }
        }
        return user
    }

    private func openShareContactDirectMessage(_ data: ShareContactData) {
        loadOrCreateShareContactDirectMessage(data) { [weak self] channel in
            guard let self else { return }
            self.context.currentClanId = 0
            let chatVC = ChatViewController(clanId: 0, channel: channel, context: self.context, parentName: nil)
            self.navigationController?.pushViewController(chatVC, animated: true)
        }
    }

    private func startDirectMessageCall(channel: Mezon_Api_ChannelDescription, user: Mezon_Api_User) {
        guard user.id != (Int64(context.currentUser?.id ?? "") ?? 0) else {
            Toast.error("Cannot call yourself")
            return
        }

        PeerCallLogMessage.sendStartCallLog(
            context: context,
            channel: channel,
            isVideoCall: false
        )

        let displayName = user.displayName.isEmpty ? (channel.channelLabel.isEmpty ? user.username : channel.channelLabel) : user.displayName
        let avatarURL = user.avatarURL.isEmpty ? channel.avatars.first : user.avatarURL
        let callVC = PeerCallViewController(
            context: context,
            remoteUserName: displayName,
            remoteAvatarURL: avatarURL,
            remoteUserId: user.id,
            channelId: channel.channelID,
            isVideo: false
        )
        pushPeerCallScreen(callVC)
    }

    private func startShareContactCall(_ data: ShareContactData) {
        guard data.userId != context.currentUser?.id else {
            Toast.error("Cannot call yourself")
            return
        }
        guard !isShareContactCallBlocked(data) else {
            Toast.error(L(L10n.Forward.blockedByYou))
            return
        }
        loadOrCreateShareContactDirectMessage(data) { [weak self] channel in
            guard let self, let remoteUserId = data.userIdInt else { return }
            PeerCallLogMessage.sendStartCallLog(
                context: self.context,
                channel: channel,
                isVideoCall: false
            )
            let callVC = PeerCallViewController(
                context: self.context,
                remoteUserName: data.resolvedDisplayName,
                remoteAvatarURL: data.avatar.trimmingCharacters(in: .whitespacesAndNewlines),
                remoteUserId: remoteUserId,
                channelId: channel.channelID,
                isVideo: false
            )
            self.pushPeerCallScreen(callVC)
        }
    }

    private func isShareContactCallBlocked(_ data: ShareContactData) -> Bool {
        guard let userId = data.userIdInt else { return false }
        return context.engine.friendsData.blockedUserIds().contains(userId)
    }

    private func loadOrCreateShareContactDirectMessage(
        _ data: ShareContactData,
        completion: @escaping (Mezon_Api_ChannelDescription) -> Void
    ) {
        guard let targetUserId = data.userIdInt, targetUserId != 0 else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }

            let dmChannels = try? await context.account.network.listDirectMessageChannels(token: token)
            if let existing = dmChannels?.first(where: { ch in
                ch.type == MezonConstants.ChannelType.dm.rawValue
                    && ch.userIds.count == 1
                    && ch.userIds.contains(targetUserId)
            }) {
                completion(existing)
                return
            }

            do {
                let channel = try await context.account.network.createDirectMessage(
                    userId: targetUserId,
                    token: token
                )
                completion(channel)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private weak var activeActionSheet: MessageActionSheetController?
    private var isCreatingTopicDiscussion = false
    private weak var reportMessageModal: ReportMessageModalController?

    private var isDirectMessageStreamChannel: Bool {
        channel.type == MezonConstants.ChannelType.dm.rawValue
            || channel.type == MezonConstants.ChannelType.group.rawValue
    }

    var isClanChannelForRoleDisplay: Bool {
        clanId != 0 && !isDirectMessageStreamChannel
    }

    private func userHasDeleteMessagePermissionInClan() -> Bool {
        return context.rolePermissions.canDeleteMessage(clanId: clanId, channelId: channel.channelID)
    }

    private func messageActionCanShowDelete(for display: ChatMessageDisplay, isOwn: Bool) -> Bool {
        if isOwn {
            if display.messageCode == Self.messageCodeTopic { return false }
            return true
        }
        if isDirectMessageStreamChannel { return false }
        if clanId == 0 { return false }
        return userHasDeleteMessagePermissionInClan()
    }

    private func displayWithLivePinState(_ display: ChatMessageDisplay) -> ChatMessageDisplay {
        let liveIsPinned = pinnedMessageIds.contains(display.message.id)
        guard liveIsPinned != display.message.isPinned else { return display }
        var msg = display.message
        msg.isPinned = liveIsPinned
        return ChatMessageDisplay(
            message: msg, senderDisplayName: display.senderDisplayName, senderUsername: display.senderUsername, avatarURL: display.avatarURL,
            isCombine: display.isCombine, attachments: display.attachments, reactions: display.reactions,
            parsedContent: display.parsedContent, replyRef: display.replyRef, isDeletedReply: display.isDeletedReply,
            isWelcome: display.isWelcome, callLog: display.callLog, topicData: display.topicData,
            locationData: display.locationData, isMe: display.isMe, sendingState: display.sendingState,
            showsSendingFeedback: display.showsSendingFeedback, hasIncludeMention: display.hasIncludeMention, isForward: display.isForward,
            showForwardHeader: display.showForwardHeader, messageCode: display.messageCode,
            clanInviteLinkCode: display.clanInviteLinkCode,
            replyRefSourceContent: display.replyRefSourceContent,
            pollData: display.pollData,
            rawContentData: display.rawContentData
        )
    }

    private func showMessageActions(_ display: ChatMessageDisplay) {
        view.endEditing(true)
        let display = displayWithLivePinState(display)
        let isOwn = isSenderCurrentUser(senderId: display.message.senderId, currentUserId: context.currentUser?.id)
        let canDelete = messageActionCanShowDelete(for: display, isOwn: isOwn)
        let fwdCluster = forwardClusterAvailable(for: display)
        let controller = MessageActionSheetController(
            display: display,
            isOwnMessage: isOwn,
            canShowDeleteMessage: canDelete,
            forwardAllAvailable: fwdCluster,
            canCreateTopicDiscussion: canCreateTopicDiscussion(for: display),
            canCreateThreadFromMessage: canCreateThreadFromMessage(for: display)
        ) { [weak self] action in
            self?.handleMessageAction(action, display: display)
        }
        controller.onDismiss = { [weak self] in
            self?.activeActionSheet = nil
            self?.dismissMessageHighlight(for: display.id)
        }
        controller.onEmojiReaction = { [weak self] emojiId, shortname in
            self?.handleEmojiReaction(emojiId: emojiId, shortname: shortname, display: display)
        }
        controller.onPresentFullEmojiPicker = { [weak self] in
            self?.presentReactionEmojiPicker(for: display)
        }
        activeActionSheet = controller
        self.presentInGlobalOverlay(controller)
        controller.animateIn()
    }

    private func canCreateTopicDiscussion(for display: ChatMessageDisplay) -> Bool {
        if topicId != 0 { return false }
        if clanId == 0 { return false }
        if display.isFailed { return false }
        if display.message.id.hasPrefix("pending-") { return false }
        if display.message.isDeleted { return false }
        if display.isSystemMessage { return false }
        if display.isTopic { return false }
        if display.isBuzzMessage { return false }
        if AnonymousMessageStore.isEnabled(clanId: clanId) { return false }
        if display.message.channelId != "\(channel.channelID)" { return false }

        switch channel.type {
        case MezonConstants.ChannelType.dm.rawValue,
             MezonConstants.ChannelType.group.rawValue,
             MezonConstants.ChannelType.app.rawValue,
             MezonConstants.ChannelType.mezonVoice.rawValue,
             MezonConstants.ChannelType.streaming.rawValue:
            return false
        default:
            break
        }

        let channelId = channel.channelID
        if channelId != 0,
           context.rolePermissions.hasResolvedChannelOverriddenPermissionsSnapshot(channelId: channelId),
           !context.rolePermissions.canSendMessage(clanId: clanId, channelId: channelId) {
            return false
        }

        return Int64(display.message.id) != nil
    }

    private func forwardClusterAvailable(for display: ChatMessageDisplay) -> Bool {
        if topicId != 0 { return false }
        if display.isPollMessage { return false }
        guard let idx = messages.firstIndex(where: { $0.id == display.id }) else { return false }
        if idx == 0 { return false }
        if idx >= messages.count - 1 { return false }
        let cur = messages[idx]
        let next = messages[idx + 1]
        guard cur.message.senderId == next.message.senderId else { return false }
        let diff = next.message.createdAt.timeIntervalSince(cur.message.createdAt)
        return diff >= 0 && diff <= 600
    }

    private func forwardDisplaysAdjacentNewer(from display: ChatMessageDisplay) -> [ChatMessageDisplay] {
        guard let idx = messages.firstIndex(where: { $0.id == display.id }) else { return [display] }
        var out: [ChatMessageDisplay] = [display]
        let anchorSender = display.message.senderId
        let gap: TimeInterval = 600
        var i = idx + 1
        while i < messages.count {
            let cur = messages[i]
            let prevBubble = messages[i - 1]
            guard cur.message.senderId == anchorSender else { break }
            let step = cur.message.createdAt.timeIntervalSince(prevBubble.message.createdAt)
            if step > gap || step < 0 { break }
            out.append(cur)
            i += 1
        }
        return out
    }

    private func recordsForForward(selected: ChatMessageDisplay, includeAdjacentNewer: Bool) -> [MessageRecord] {
        let displays: [ChatMessageDisplay] = includeAdjacentNewer
            ? forwardDisplaysAdjacentNewer(from: selected)
            : [selected]
        let ids = displays.map(\.id)
        return context.account.postbox.read { tx in
            ids.compactMap { tx.getMessageById($0) }
        }
    }

    private func presentForwardMessage(for display: ChatMessageDisplay, includeAdjacentNewer: Bool) {
        let displays: [ChatMessageDisplay] = includeAdjacentNewer
            ? forwardDisplaysAdjacentNewer(from: display)
            : [display]
        let records = recordsForForward(selected: display, includeAdjacentNewer: includeAdjacentNewer)
        guard !records.isEmpty else {
            Toast.error(L(L10n.Sharing.errorTitle))
            return
        }
        var attachmentHints: [String: [ParsedAttachment]] = [:]
        for d in displays where !d.attachments.isEmpty {
            attachmentHints[d.id] = d.attachments
        }
        let vc = ForwardMessageViewController(
            context: context,
            messagesToForward: records,
            forwardFromChannelID: channel.channelID,
            attachmentHints: attachmentHints
        )
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(vc, animated: true)
    }

    private func dismissMessageHighlight(for messageId: String) {
        messagesNode.listView.forEachItemNode { node in
            if let itemNode = node as? ChatMessageItemNode {
                for sub in itemNode.subnodes ?? [] {
                    if let bubble = sub as? MessageBubbleNode {
                        bubble.dismissHighlight()
                    }
                }
            }
        }
    }

    private func streamModeForCurrentChannel() -> Int32 {
        switch channel.type {
        case MezonConstants.ChannelType.thread.rawValue:
            return MezonConstants.ChannelStreamMode.thread.rawValue
        case MezonConstants.ChannelType.dm.rawValue:
            return MezonConstants.ChannelStreamMode.dm.rawValue
        case MezonConstants.ChannelType.group.rawValue:
            return MezonConstants.ChannelStreamMode.group.rawValue
        default:
            if clanId != 0 {
                return MezonConstants.ChannelStreamMode.channel.rawValue
            }
            return MezonConstants.ChannelStreamMode.group.rawValue
        }
    }

    private var isCurrentChannelPublicClanRoot: Bool {
        clanId != 0 && channel.parentID == 0 && channel.channelPrivate == 0
    }

    private func makeLocalReactionEvent(
        display: ChatMessageDisplay,
        emojiId: String,
        shortname: String,
        count: Int32,
        actionDelete: Bool
    ) -> Mezon_Api_MessageReaction? {
        guard let messageId = Int64(display.message.id) else { return nil }
        guard let uid = context.currentUser?.id, let senderId = Int64(uid) else { return nil }
        var r = Mezon_Api_MessageReaction()
        r.channelID = Int64(display.message.channelId) ?? channel.channelID
        r.clanID = clanId
        r.messageID = messageId
        r.topicID = topicId
        r.emojiID = Int64(emojiId) ?? 0
        r.emoji = shortname.isEmpty ? emojiId : shortname
        r.senderID = senderId
        if let n = context.currentUser?.displayName, !n.isEmpty {
            r.senderName = n
        }
        r.action = actionDelete
        r.count = count
        return r
    }

    private func applyLocalReactionRemoveForMessage(display: ChatMessageDisplay, emojiId: String, shortname: String, removeCount: Int32) {
        guard removeCount > 0,
              let r = makeLocalReactionEvent(
                display: display,
                emojiId: emojiId,
                shortname: shortname,
                count: removeCount,
                actionDelete: true
              ) else { return }
        context.account.postbox.write { tx in
            tx.updateMessageReactions(messageId: display.message.id, reaction: r)
        }
    }

    private func writeMessageReaction(
        display: ChatMessageDisplay,
        emojiId: String,
        shortname: String,
        count: Int32,
        actionDelete: Bool
    ) {
        guard let msgId = Int64(display.message.id) else { return }
        let emojiIdInt = Int64(emojiId) ?? 0
        let messageSenderId = Int64(display.message.senderId) ?? 0
        let mode = streamModeForCurrentChannel()
        let isPublic = isCurrentChannelPublicClanRoot
        if !actionDelete,
           let optimisticReaction = makeLocalReactionEvent(
            display: display,
            emojiId: emojiId,
            shortname: shortname,
            count: 0,
            actionDelete: false
           ) {
            context.account.postbox.write { tx in
                tx.updateMessageReactions(messageId: display.message.id, reaction: optimisticReaction)
            }
        }

        Task { @MainActor in
            guard let token = await self.context.getToken() else { return }
            do {
                var applied = try await self.context.account.network.writeMessageReaction(
                    clanId: self.clanId,
                    channelId: self.channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    messageId: msgId,
                    emojiId: emojiIdInt,
                    emoji: shortname,
                    count: count,
                    messageSenderId: messageSenderId,
                    actionDelete: actionDelete,
                    topicId: self.topicId,
                    token: token
                )
                let responseCarriesReaction = applied.id != 0
                    || applied.messageID != 0
                    || applied.channelID != 0
                    || applied.topicID != 0
                    || applied.emojiID != 0
                    || !applied.emoji.isEmpty
                    || applied.senderID != 0
                    || applied.count != 0
                guard responseCarriesReaction else { return }
                if applied.messageID == 0 { applied.messageID = msgId }
                if applied.channelID == 0 { applied.channelID = self.channel.channelID }
                if applied.clanID == 0 { applied.clanID = self.clanId }
                if applied.topicID == 0 { applied.topicID = self.topicId }
                if applied.emojiID == 0 { applied.emojiID = emojiIdInt }
                if applied.emoji.isEmpty { applied.emoji = shortname }
                if applied.senderID == 0, let uid = self.context.currentUser?.id {
                    applied.senderID = Int64(uid) ?? 0
                }
                if applied.senderName.isEmpty, let name = self.context.currentUser?.displayName {
                    applied.senderName = name
                }
                applied.action = actionDelete
                if applied.count == 0, actionDelete {
                    applied.count = count
                }
                self.context.account.postbox.write { tx in
                    tx.updateMessageReactions(messageId: "\(applied.messageID)", reaction: applied)
                }
            } catch {
            }
        }
    }

    private func handleEmojiReaction(emojiId: String, shortname: String, display: ChatMessageDisplay) {
        writeMessageReaction(display: display, emojiId: emojiId, shortname: shortname, count: 1, actionDelete: false)
    }

    private weak var reactionEmojiPickerSheet: ReactionEmojiPickerSheetController?

    private var isReactionEmojiPickerSheetHostingFirstResponder: Bool {
        guard let v = reactionEmojiPickerSheet?.viewIfLoaded, v.window != nil else { return false }
        return v.findFirstResponder() != nil
    }

    private func presentReactionEmojiPicker(for display: ChatMessageDisplay) {
        view.endEditing(true)
        let sheet = ReactionEmojiPickerSheetController(engine: context.engine) { [weak self] emojiId, shortname in
            self?.handleEmojiReaction(emojiId: emojiId, shortname: shortname, display: display)
        }
        sheet.onDismiss = { [weak self] in
            self?.reactionEmojiPickerSheet = nil
        }
        reactionEmojiPickerSheet = sheet
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func presentReactionDetailSheet(initialReaction: ParsedReaction, display: ChatMessageDisplay) {
        view.endEditing(true)
        let sheet = MessageReactionDetailSheetController(
            reactions: display.reactions,
            display: display,
            context: context,
            reactionMemberLookupClanId: clanId,
            initialEmojiId: initialReaction.emojiId,
            onRemoveReaction: { [weak self] emojiId, shortname, count, display in
                self?.applyLocalReactionRemoveForMessage(display: display, emojiId: emojiId, shortname: shortname, removeCount: count)
                self?.writeMessageReaction(display: display, emojiId: emojiId, shortname: shortname, count: count, actionDelete: true)
            }
        )
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func presentMessageMediaGallery(
        index: Int,
        media: [ParsedAttachment],
        display: ChatMessageDisplay,
        previewImage: UIImage?
    ) {
        let galleryItems = media.enumerated().map { (itemIndex, attachment) in
            let preview = itemIndex == index ? previewImage : nil
            return makeMessageGalleryItem(
                attachment: attachment,
                display: display,
                previewImage: preview
            )
        }
        guard !galleryItems.isEmpty else { return }
        let initialIndex = max(0, min(index, galleryItems.count - 1))
        let gallery = GalleryController(
            items: galleryItems,
            initialIndex: initialIndex,
            channelItemsLoader: { [weak self] in
                guard let self else { return [] }
                return await self.loadChannelGalleryItems(around: display)
            }
        )
        present(gallery, animated: true)
    }

    private func makeMessageGalleryItem(
        attachment: ParsedAttachment,
        display: ChatMessageDisplay,
        previewImage: UIImage? = nil
    ) -> GalleryItemInfo {
        if attachment.isVideo {
            return GalleryItemInfo(
                url: attachment.url,
                sourceURL: attachment.url,
                image: previewImage ?? attachment.localImage,
                pixelSize: GalleryItemInfo.pixelSize(width: attachment.width, height: attachment.height),
                placeholderURL: nil,
                senderName: display.senderDisplayName,
                senderId: display.message.senderId,
                senderAvatarURL: display.avatarURL,
                timestamp: display.message.createdAt,
                isVideo: true,
                videoShareMetadata: GalleryVideoShareMetadata(
                    filename: attachment.filename,
                    filetype: attachment.filetype,
                    durationSeconds: attachment.durationSeconds ?? 0,
                    thumbnail: attachment.thumbnail
                )
            )
        }
        return GalleryItemInfo.imageItem(
            sourceURL: attachment.url,
            image: GalleryItemInfo.fitCachedPreviewMemory(sourceURL: attachment.url)
                ?? previewImage
                ?? attachment.localImage,
            pixelSize: GalleryItemInfo.pixelSize(width: attachment.width, height: attachment.height),
            senderName: display.senderDisplayName,
            senderId: display.message.senderId,
            senderAvatarURL: display.avatarURL,
            timestamp: display.message.createdAt
        )
    }

    private func loadChannelGalleryItems(around display: ChatMessageDisplay) async -> [GalleryItemInfo] {
        guard let token = await context.getToken() else { return [] }
        let channelType = channel.type != 0
            ? channel.type
            : (clanId == 0 ? MezonConstants.ChannelType.group.rawValue : MezonConstants.ChannelType.channel.rawValue)
        let requestClanId =
            (channelType == MezonConstants.ChannelType.dm.rawValue
                || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId
        let messageTimestamp = display.message.createdAt.timeIntervalSince1970
        let selectedTimestamp = UInt32(max(0, min(messageTimestamp, Double(UInt32.max))))
        let beforeTime = display.message.createdAt.addingTimeInterval(24 * 60 * 60).timeIntervalSince1970
        let beforeTimestamp = UInt32(max(0, min(beforeTime, Double(UInt32.max))))

        let olderAndCurrent = await requestChannelGalleryAttachments(
            clanId: requestClanId,
            token: token,
            before: beforeTimestamp,
            after: 0
        )
        let newer = await requestChannelGalleryAttachments(
            clanId: requestClanId,
            token: token,
            before: 0,
            after: selectedTimestamp
        )

        let visualItems = (newer + olderAndCurrent)
            .filter { Self.isVisualChannelAttachment($0) }
            .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
            .reduce(into: [Mezon_Api_ChannelAttachment]()) { result, attachment in
                let key = attachment.url.isEmpty ? "id:\(attachment.id)" : "url:\(attachment.url)"
                guard !result.contains(where: {
                    ($0.url.isEmpty ? "id:\($0.id)" : "url:\($0.url)") == key
                }) else { return }
                result.append(attachment)
            }
            .map { makeChannelGalleryItem(attachment: $0) }
        return Array(visualItems.reversed())
    }

    private func requestChannelGalleryAttachments(
        clanId: Int64,
        token: String,
        before: UInt32,
        after: UInt32
    ) async -> [Mezon_Api_ChannelAttachment] {
        do {
            let response = try await context.account.network.listChannelAttachments(
                clanId: clanId,
                channelId: channel.channelID,
                fileType: "image",
                limit: 30,
                before: before,
                after: after,
                token: token
            )
            return response.attachments
        } catch {
            return []
        }
    }

    private func makeChannelGalleryItem(attachment: Mezon_Api_ChannelAttachment) -> GalleryItemInfo {
        let isVideo = Self.isVideoChannelAttachment(attachment)
        let uploader = resolvedUploaderInfo(uploaderId: attachment.uploader)
        let timestamp = attachment.createTimeSeconds > 0
            ? Date(timeIntervalSince1970: TimeInterval(attachment.createTimeSeconds))
            : nil
        if isVideo {
            return GalleryItemInfo(
                url: attachment.url,
                sourceURL: attachment.url,
                image: nil,
                pixelSize: GalleryItemInfo.pixelSize(width: attachment.width, height: attachment.height),
                placeholderURL: nil,
                senderName: uploader.name,
                senderId: String(attachment.uploader),
                senderAvatarURL: uploader.avatarURL,
                timestamp: timestamp,
                isVideo: true,
                videoShareMetadata: GalleryVideoShareMetadata(
                    filename: attachment.filename,
                    filetype: attachment.filetype,
                    size: Int64(attachment.filesize) ?? 0
                )
            )
        }
        return GalleryItemInfo.imageItem(
            sourceURL: attachment.url,
            pixelSize: GalleryItemInfo.pixelSize(width: attachment.width, height: attachment.height),
            placeholderProxySize: 150,
            senderName: uploader.name,
            senderId: String(attachment.uploader),
            senderAvatarURL: uploader.avatarURL,
            timestamp: timestamp
        )
    }

    private static func isVisualChannelAttachment(_ attachment: Mezon_Api_ChannelAttachment) -> Bool {
        if AttachmentTypeClassifier.isSticker(attachment.filetype) || attachment.url.contains("/stickers") { return false }
        if AttachmentTypeClassifier.isImage(attachment.filetype)
            || AttachmentTypeClassifier.isVideo(attachment.filetype) { return true }
        let filenameExtension = (attachment.filename as NSString).pathExtension.lowercased()
        let urlExtension = URL(string: attachment.url)?.pathExtension.lowercased() ?? ""
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]
        return imageExtensions.contains(filenameExtension)
            || imageExtensions.contains(urlExtension)
            || videoExtensions.contains(filenameExtension)
            || videoExtensions.contains(urlExtension)
    }

    private static func isVideoChannelAttachment(_ attachment: Mezon_Api_ChannelAttachment) -> Bool {
        if AttachmentTypeClassifier.isVideo(attachment.filetype) { return true }
        let filenameExtension = (attachment.filename as NSString).pathExtension.lowercased()
        let urlExtension = URL(string: attachment.url)?.pathExtension.lowercased() ?? ""
        return ["mp4", "mov", "m4v", "webm"].contains(filenameExtension)
            || ["mp4", "mov", "m4v", "webm"].contains(urlExtension)
    }

    private func resolvedUploaderInfo(uploaderId: Int64) -> (name: String, avatarURL: String?) {
        guard uploaderId != 0 else { return ("", nil) }
        let idString = String(uploaderId)
        var name = ""
        var avatarURL: String?
        context.account.postbox.read { tx in
            guard let profile = tx.getProfile(userId: idString) else { return }
            if let displayName = profile.displayName, !displayName.isEmpty {
                name = displayName
            } else if !profile.username.isEmpty {
                name = profile.username
            }
            if let avatar = profile.avatarUrl, !avatar.isEmpty {
                avatarURL = avatar
            }
        }
        return (name.isEmpty ? idString : name, avatarURL)
    }

    private enum PhotoLibrarySaveAuthorizationResult {
        case authorized
        case denied
        case restricted
    }

    private func shareMessageText(display: ChatMessageDisplay) {
        let text = display.parsedContent.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activity, animated: true)
    }

    private func saveSingleMessageImage(display: ChatMessageDisplay) {
        loadSingleMessageImage(display: display) { [weak self] image in
            guard let self else { return }
            guard let image else {
                Toast.error(L(L10n.Gallery.imageLoadFailed))
                return
            }
            self.saveImageToPhotoLibrary(image)
        }
    }

    private func copySingleMessageImage(display: ChatMessageDisplay) {
        loadSingleMessageImage(display: display) { image in
            guard let image else {
                Toast.error(L(L10n.Gallery.imageLoadFailed))
                return
            }
            UIPasteboard.general.image = image
            Toast.success(L(L10n.MessageAction.copied))
        }
    }

    private func loadSingleMessageImage(display: ChatMessageDisplay, completion: @escaping (UIImage?) -> Void) {
        guard let attachment = display.singleImageMediaAttachment else {
            completion(nil)
            return
        }
        if let localImage = attachment.localImage {
            completion(localImage)
            return
        }

        let url = attachment.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            completion(nil)
            return
        }

        if let cached = ImageCache.shared.cachedImage(forURL: url) {
            completion(cached)
            return
        }

        let proxyWidth = min(max(attachment.width ?? 1200, 1200), 2400)
        let proxyHeight = min(max(attachment.height ?? 1200, 1200), 2400)
        let fallbackProxyURL = ImgproxyURL.attachmentURL(
            from: url,
            width: proxyWidth,
            height: proxyHeight,
            resizeType: "fit"
        )

        ImageCache.shared.loadImage(urlString: url) { image in
            if let image {
                completion(image)
                return
            }
            guard !fallbackProxyURL.isEmpty, fallbackProxyURL != url else {
                completion(nil)
                return
            }
            ImageCache.shared.loadImage(urlString: fallbackProxyURL, completion: completion)
        }
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) {
        requestPhotoLibrarySaveAuthorization { [weak self] result in
            switch result {
            case .authorized:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            Toast.success(L(L10n.Gallery.imageSaved))
                        } else {
                            Toast.error(error?.localizedDescription ?? L(L10n.Gallery.imageSaveFailed))
                        }
                    }
                })
            case .denied:
                DispatchQueue.main.async {
                    self?.presentPhotoPermissionSettingsAlert()
                }
            case .restricted:
                DispatchQueue.main.async {
                    Toast.error(L(L10n.Gallery.photoPermissionDenied))
                }
            }
        }
    }

    private func requestPhotoLibrarySaveAuthorization(completion: @escaping (PhotoLibrarySaveAuthorizationResult) -> Void) {
        if #available(iOS 14.0, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    switch status {
                    case .authorized, .limited:
                        completion(.authorized)
                    case .denied:
                        completion(.denied)
                    case .restricted:
                        completion(.restricted)
                    case .notDetermined:
                        completion(.denied)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .denied:
                completion(.denied)
            case .restricted:
                completion(.restricted)
            @unknown default:
                completion(.denied)
            }
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized, .limited:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    switch status {
                    case .authorized, .limited:
                        completion(.authorized)
                    case .denied:
                        completion(.denied)
                    case .restricted:
                        completion(.restricted)
                    case .notDetermined:
                        completion(.denied)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .denied:
                completion(.denied)
            case .restricted:
                completion(.restricted)
            @unknown default:
                completion(.denied)
            }
        }
    }

    private func presentPhotoPermissionSettingsAlert() {
        let presentAlert = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: L(L10n.Gallery.photoPermissionTitle),
                message: L(L10n.Gallery.photoPermissionMessage),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
            alert.addAction(UIAlertAction(title: L(L10n.Common.settings), style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
            self.present(alert, animated: true)
        }

        if let presentedViewController {
            presentedViewController.dismiss(animated: true, completion: presentAlert)
        } else {
            presentAlert()
        }
    }

    private func showMessageActionComingSoon(_ action: MessageAction) {
        let line = "\(action.title) — \(L(L10n.Common.comingSoon))"
        Toast.comingSoonLine(line)
    }

    private func handleMessageAction(_ action: MessageAction, display: ChatMessageDisplay) {
        switch action {
        case .reply:
            sendInputViewController.setReply(display)
            sendInputViewController.view.becomeFirstResponder()
        case .copyText:
            UIPasteboard.general.string = display.parsedContent.text
            Toast.success(L(L10n.MessageAction.copied))
        case .shareText:
            shareMessageText(display: display)
        case .saveImage:
            saveSingleMessageImage(display: display)
        case .copyImage:
            copySingleMessageImage(display: display)
        case .deleteMessage:
            showDeleteMessageConfirm(display: display)
        case .pinMessage:
            showPinMessageConfirm(display: display)
        case .unpinMessage:
            showUnpinMessageConfirm(display: display)
        case .forward, .forwardMessage:
            presentForwardMessage(for: display, includeAdjacentNewer: false)
        case .forwardAll:
            presentForwardMessage(for: display, includeAdjacentNewer: true)
        case .resend:
            pendingSendingFeedbackBeganAtByMessageId[display.message.id] = Date()
            sendInputViewController.resendFailedMessage(display: display)
        case .giveACoffee:
            runGiveACoffeeIfPossible(display: display)
        case .createThread:
            presentCreateThreadForm(from: display)
        // case .markUnread:
        //     showMessageActionComingSoon(.markUnread)
        case .markUnread: break
        case .topicDiscussion:
            createTopicDiscussion(from: display)
        // case .markMessage:
        //     showMessageActionComingSoon(.markMessage)
        case .markMessage: break
        // case .quickMenu:
        //     showMessageActionComingSoon(.quickMenu)
        case .quickMenu: break
        case .editMessage:
            sendInputViewController.setEditingMessage(display)
            sendInputViewController.view.becomeFirstResponder()
        case .report:
            presentReportMessageModal(messageId: display.message.id)
        }
    }

    private func presentReportMessageModal(messageId: String) {
        let modal = ReportMessageModalController(context: context, messageId: messageId)
        modal.onDismiss = { [weak self] in
            self?.reportMessageModal = nil
        }
        reportMessageModal = modal
        presentInGlobalOverlay(modal)
        modal.animateIn()
    }

    private static let giveCoffeeEmojiId: String = "7280417126303261185"
    private static let giveCoffeeShortname: String = ":coffee:"

    private func runGiveACoffeeIfPossible(display: ChatMessageDisplay) {
        guard isSenderCurrentUser(senderId: display.message.senderId, currentUserId: context.currentUser?.id) == false else { return }
        let mid = display.message.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mid.isEmpty, !mid.hasPrefix("pending-"), Int64(mid) != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGiveACoffeeTransfer(display: display)
        }
    }

    @MainActor
    private func performGiveACoffeeTransfer(display: ChatMessageDisplay) async {
        let ch = display.message.channelId
        let cl = display.message.clanId ?? "0"
        let ref = display.message.id
        let recv = display.message.senderId
        do {
            let r = try await MmnTransferCoordinator.sendGiveCoffee(
                context: context,
                receiverUserId: recv,
                messageChannelId: ch,
                messageClanId: cl,
                messageRefId: ref
            )
            if r.ok == true {
                writeMessageReaction(
                    display: display,
                    emojiId: Self.giveCoffeeEmojiId,
                    shortname: Self.giveCoffeeShortname,
                    count: 1,
                    actionDelete: false
                )
                Toast.success(L(L10n.MessageAction.giveCoffeeSuccess))
            } else {
                let err = (r.error?.isEmpty == false) ? (r.error ?? "") : L(L10n.Profile.sendTokenErrSendFailed)
                Toast.error(err)
            }
        } catch MmnTransferError.giveCoffeeInProgress {
        } catch MmnTransferError.walletNotReady {
            var p: UIViewController = self
            while let n = p.presentedViewController { p = n }
            MezonConfirm.present(
                from: p,
                title: L(L10n.Profile.sendTokenErrSessionExpired),
                content: L(L10n.Profile.sendTokenErrLoginAgain),
                confirmTitle: L(L10n.Common.confirm),
                showsCancelButton: false
            ) { [weak self] in
                self?.context.logout()
            }
        } catch {
            Toast.error(error.localizedDescription)
        }
    }

    private func showDeleteMessageConfirm(display: ChatMessageDisplay) {
        let alert = UIAlertController(
            title: L(L10n.MessageAction.deleteMessage),
            message: L(L10n.MessageAction.deleteMessageConfirm),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: L(L10n.MessageAction.yes), style: .destructive) { [weak self] _ in
            self?.performDeleteMessage(display: display)
        })

        alert.addAction(UIAlertAction(title: L(L10n.MessageAction.no), style: .cancel))

        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    }

    private func performDeleteMessage(display: ChatMessageDisplay) {
        let msgId = display.message.id
        guard let msgIdInt = Int64(msgId) else { return }

        let mode = streamModeForCurrentChannel()
        let isPublic = isCurrentChannelPublicClanRoot
        let hasAttachment = !display.attachments.isEmpty
        let hasMentions = !display.message.mentionedUserIds.isEmpty
        let hasReferences = display.replyRef != nil

        Task { @MainActor in
            guard let token = await self.context.getToken() else { return }
            do {
                try await self.context.account.network.deleteChannelMessage(
                    clanId: self.clanId,
                    channelId: self.channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    messageId: msgIdInt,
                    hasAttachment: hasAttachment,
                    topicId: self.topicId,
                    hasMentions: hasMentions,
                    hasReferences: hasReferences,
                    token: token
                )
                self.context.account.postbox.write { tx in tx.deleteMessage(id: msgId) }
            } catch {
                Toast.error(L(L10n.MessageAction.deleteError))
            }
        }
    }

    private func showPinMessageConfirm(display: ChatMessageDisplay) {
        let alert = UIAlertController(
            title: L(L10n.MessageAction.pinMessage),
            message: L(L10n.MessageAction.pinMessageConfirm),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: L(L10n.MessageAction.yes), style: .default) { [weak self] _ in
            self?.performPinMessage(display: display)
        })

        alert.addAction(UIAlertAction(title: L(L10n.MessageAction.no), style: .cancel))

        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    }

    private func showUnpinMessageConfirm(display: ChatMessageDisplay) {
        let alert = UIAlertController(
            title: L(L10n.MessageAction.unpinMessage),
            message: L(L10n.MessageAction.unpinMessageConfirm),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: L(L10n.MessageAction.yes), style: .default) { [weak self] _ in
            self?.performUnpinMessage(display: display)
        })

        alert.addAction(UIAlertAction(title: L(L10n.MessageAction.no), style: .cancel))

        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    }

    private func performPinMessage(display: ChatMessageDisplay) {
        guard let msgId = Int64(display.message.id) else { return }

        Task { @MainActor in
            guard let token = await self.context.getToken() else { return }
            do {
                let list = try await self.context.account.network.createPinMessage(
                    clanId: self.pinApiClanId(),
                    channelId: self.channel.channelID,
                    messageId: msgId,
                    token: token
                )
                self.mergePinListEntries(list)
                let idStr = "\(msgId)"
                if !self.pinnedMessageIds.contains(idStr) {
                    self.pinnedMessageIds.insert(idStr)
                }
                self.syncPinnedStateToPostbox()
                self.reloadDisplaysWithCurrentPins()
                Toast.success(L(L10n.MessageAction.pinSuccess))
            } catch {
                Toast.error(L(L10n.MessageAction.pinError))
            }
        }
    }

    private func performUnpinMessage(display: ChatMessageDisplay) {
        guard let msgId = Int64(display.message.id) else { return }
        let idNorm = display.message.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinId =
            pinServerIdByMessageId[idNorm] ?? pinServerIdByMessageId[display.message.id] ?? pinServerIdByMessageId["\(msgId)"] ?? 0

        Task { @MainActor in
            guard let token = await self.context.getToken() else { return }
            do {
                try await self.context.account.network.deletePinMessage(
                    clanId: self.pinApiClanId(),
                    channelId: self.channel.channelID,
                    pinId: pinId,
                    messageId: msgId,
                    token: token
                )
                self.pinnedMessageIds.remove(idNorm)
                self.pinnedMessageIds.remove("\(msgId)")
                self.pinServerIdByMessageId.removeValue(forKey: idNorm)
                self.pinServerIdByMessageId.removeValue(forKey: "\(msgId)")
                ChannelPinnedStatePersistence.applyUnpinMessage(
                    postbox: self.context.account.postbox,
                    accountId: self.context.account.id,
                    clanId: self.pinApiClanId(),
                    channelId: self.channel.channelID,
                    messageId: msgId
                )
                self.syncPinnedStateToPostbox()
                self.reloadDisplaysWithCurrentPins()
                Toast.success(L(L10n.MessageAction.unpinSuccess))
            } catch {
                Toast.error(L(L10n.MessageAction.unpinError))
            }
        }
    }

    private var shouldShowChannelAppHotbar: Bool {
        topicId == 0 && clanId != 0
            && channel.type == MezonConstants.ChannelType.app.rawValue
    }

    private func loadChannelAppsFromPostboxCache() -> [Mezon_Api_ChannelAppResponse] {
        guard clanId != 0 else { return [] }
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else { return [] }
        return Mezon_Api_ListChannelAppsResponse.decodeChannelApps(data)
    }

    private func resolvedChannelAppRecord() -> Mezon_Api_ChannelAppResponse? {
        guard shouldShowChannelAppHotbar else { return nil }
        let list = loadChannelAppsFromPostboxCache()
        if let hit = list.first(where: { $0.channelID == channel.channelID }) {
            return hit
        }
        guard channel.appID != 0 else { return nil }
        var syn = Mezon_Api_ChannelAppResponse()
        syn.channelID = channel.channelID
        syn.clanID = clanId
        syn.appID = channel.appID
        syn.appName = channel.channelLabel
        return syn
    }

    private func tryResolveChannelAppViaNetwork(hint: Mezon_Api_ChannelAppResponse) async -> Mezon_Api_ChannelAppResponse? {
        guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return nil }
        do {
            let apps = try await MezonHTTPClient.shared.listChannelApps(clanId: clanId, token: token)
            if let hit = apps.first(where: { $0.channelID == channel.channelID }) { return hit }
            if hint.appID != 0, let hit = apps.first(where: { $0.appID == hint.appID }) { return hit }
            return nil
        } catch {
            return nil
        }
    }

    private func openChannelAppFromHotbar() {
        view.endEditing(true)
        emojiPicker.setVisible(false, collapsedHeight: 0)
        dismissAdvancePanel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard var working = self.resolvedChannelAppRecord() else {
                Toast.error(L(L10n.ChannelApp.unavailable))
                return
            }
            if working.appURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, working.appID != 0 {
                if let fromNet = await self.tryResolveChannelAppViaNetwork(hint: working) {
                    working = fromNet
                }
            }
            guard working.appID != 0 else {
                Toast.error(L(L10n.ChannelApp.unavailable))
                return
            }
            let urlStr = working.appURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlStr.isEmpty else {
                Toast.error(L(L10n.ChannelApp.unavailable))
                return
            }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                let webAppData = try await self.context.account.network.generateChannelAppHash(appId: working.appID, token: token)
                guard !webAppData.isEmpty else {
                    Toast.error(L(L10n.ChannelApp.unavailable))
                    return
                }
                guard let pageURL = working.channelAppWebPageURL(webAppData: webAppData) else {
                    Toast.error(L(L10n.ChannelApp.unavailable))
                    return
                }
                let titleRaw = working.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fromChannel = self.channel.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let pickTitle = titleRaw.isEmpty ? fromChannel : titleRaw
                let title = pickTitle.isEmpty ? "App" : pickTitle
                let vc = ChannelAppWebViewController(pageURL: pageURL, appTitle: title)
                self.presentInGlobalOverlay(vc)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func openChannelAppHelpFromHotbar() {
        guard let url = URL(string: "https://mezon.ai") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

extension ChatViewController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        cancelLocationFetchTimeout()
        manager.delegate = nil
        isWaitingForLocationAuthorization = false
        let completion = locationCompletion
        locationCompletion = nil
        completion?(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        cancelLocationFetchTimeout()
        manager.delegate = nil
        isWaitingForLocationAuthorization = false
        let completion = locationCompletion
        locationCompletion = nil
        if let cached = recentCachedCoordinate(from: manager) {
            completion?(cached)
        } else {
            completion?(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        handleLocationAuthorizationStatus(status, manager: manager)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if #available(iOS 14.0, *) { return }
        handleLocationAuthorizationStatus(status, manager: manager)
    }
}

extension ChatViewController {

    fileprivate static func apiUserForMemberProfile(from clanUser: Mezon_Api_ClanUserList.ClanUser) -> Mezon_Api_User {
        var u = clanUser.user
        if !clanUser.clanNick.isEmpty {
            u.displayName = clanUser.clanNick
        }
        if !clanUser.clanAvatar.isEmpty {
            u.avatarURL = clanUser.clanAvatar
        }
        return u
    }

    func startCall() {
        guard clanId == 0 else { return }
        guard channel.type == MezonConstants.ChannelType.dm.rawValue else { return }
        guard let myUserId = Int64(context.currentUser?.id ?? "") else { return }

        let remoteUserId: Int64 = channel.userIds.first(where: { $0 != myUserId }) ?? 0
        guard remoteUserId != 0 else {
            return
        }

        PeerCallLogMessage.sendStartCallLog(
            context: context,
            channel: channel,
            isVideoCall: false
        )

        let callVC = PeerCallViewController(
            context: context,
            remoteUserName: channel.channelLabel,
            remoteAvatarURL: channel.avatars.first,
            remoteUserId: remoteUserId,
            channelId: channel.channelID,
            isVideo: false
        )
        pushPeerCallScreen(callVC)
    }

    func startVideoCall() {
        guard clanId == 0 else { return }
        guard channel.type == MezonConstants.ChannelType.dm.rawValue else { return }
        guard let myUserId = Int64(context.currentUser?.id ?? "") else { return }

        let remoteUserId: Int64 = channel.userIds.first(where: { $0 != myUserId }) ?? 0
        guard remoteUserId != 0 else {
            return
        }

        PeerCallLogMessage.sendStartCallLog(
            context: context,
            channel: channel,
            isVideoCall: true
        )

        let callVC = PeerCallViewController(
            context: context,
            remoteUserName: channel.channelLabel,
            remoteAvatarURL: channel.avatars.first,
            remoteUserId: remoteUserId,
            channelId: channel.channelID,
            isVideo: true
        )
        pushPeerCallScreen(callVC)
    }

    private func pushPeerCallScreen(_ callVC: PeerCallViewController) {
        if let nav = navigationController {
            nav.pushViewController(callVC, animated: true)
        } else {
            present(callVC, animated: true)
        }
    }
}

private final class ChannelAppHotbarBarView: UIView {

    static let prefersFixedHeight: CGFloat = 40

    var onLaunch: (() -> Void)?
    var onHelp: (() -> Void)?

    private let launchButton = UIButton(type: .custom)
    private let helpButton = UIButton(type: .custom)
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        configureActionButton(launchButton, titleKey: L10n.ChannelApp.launchApp)
        configureActionButton(helpButton, titleKey: L10n.ChannelApp.help)
        stack.addArrangedSubview(launchButton)
        stack.addArrangedSubview(helpButton)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        launchButton.addTarget(self, action: #selector(launchTapped), for: .touchUpInside)
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        backgroundColor = .clear
        applyChrome(to: launchButton, titleKey: L10n.ChannelApp.launchApp)
        applyChrome(to: helpButton, titleKey: L10n.ChannelApp.help)
    }

    private func configureActionButton(_ btn: UIButton, titleKey: String) {
        btn.titleLabel?.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 14, weight: .medium))
        btn.titleLabel?.adjustsFontForContentSizeCategory = true
        btn.titleLabel?.lineBreakMode = .byTruncatingTail
        btn.contentHorizontalAlignment = .center
        applyChrome(to: btn, titleKey: titleKey)
    }

    private func applyChrome(to btn: UIButton, titleKey: String) {
        let t = UIColor.theme
        let title = L(titleKey)
        if #available(iOS 15.0, *) {
            var c = UIButton.Configuration.plain()
            c.title = title
            c.titleLineBreakMode = .byTruncatingTail
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var o = incoming
                o.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 14, weight: .medium))
                return o
            }
            c.baseForegroundColor = t.textStrong
            c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = t.secondary
            bg.cornerRadius = 10
            c.background = bg
            btn.configuration = c
        } else {
            btn.setTitle(title, for: .normal)
            btn.setImage(nil, for: .normal)
            btn.setTitleColor(t.textStrong, for: .normal)
            btn.backgroundColor = t.secondary
            btn.layer.cornerRadius = 10
            btn.layer.masksToBounds = true
            btn.imageEdgeInsets = .zero
            btn.titleEdgeInsets = .zero
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        }
    }

    @objc private func launchTapped() { onLaunch?() }
    @objc private func helpTapped() { onHelp?() }
}
