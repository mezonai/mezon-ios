import UIKit
import AVFoundation

private struct ComposerMention {
    var userId: Int64
    var roleId: Int64
    var rolename: String
    var displayName: String
    var range: NSRange
}

private struct ComposerHashtag {
    var channelId: Int64
    var clanId: Int64
    var parentId: Int64
    var channelLabel: String
    var channelType: Int32
    var channelPrivate: Int32
    var ageRestricted: Int32
    var range: NSRange
}

private struct ComposerMentionSnapshot: Codable {
    var userId: Int64
    var roleId: Int64
    var rolename: String
    var displayName: String
    var location: Int
    var length: Int
}

private struct ComposerHashtagSnapshot: Codable {
    var channelId: Int64
    var clanId: Int64
    var parentId: Int64
    var channelLabel: String
    var channelType: Int32
    var channelPrivate: Int32
    var ageRestricted: Int32
    var location: Int
    var length: Int
}

private struct FileDraftSnapshot: Codable {
    var path: String
    var filename: String
    var filetype: String
    var filesize: Int
}

private struct ComposerDraftSnapshot: Codable {
    var attributedArchive: Data?
    var mentions: [ComposerMentionSnapshot]
    var hashtags: [ComposerHashtagSnapshot]
    var emojiIdByColon: [String: String]
    var fileDrafts: [FileDraftSnapshot]
}

private struct ComposerEditingStateSnapshot {
    var display: ChatMessageDisplay
    var remoteImageAttachments: [ParsedAttachment]
    var remoteFileAttachments: [ParsedAttachment]
}

private struct OgpLinkCandidate {
    let url: String
    let range: NSRange
}

private struct OgpPreviewItem: Equatable {
    let url: String
    let title: String
    let description: String
    let image: String
    let type: String
    let index: Int

    var hasSendableMetadata: Bool {
        !title.isEmpty && !description.isEmpty && !image.isEmpty
    }

    func markdownPayload(textLength: Int) -> [String: Any] {
        [
            "title": title,
            "description": description,
            "image": image,
            "url": url,
            "s": textLength,
            "e": textLength + 1,
            "type": "lk_ogp",
            "index": index,
        ]
    }
}

private struct OgpPreviewResponse: Decodable {
    let title: String?
    let description: String?
    let image: String?
    let key: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case image
        case key
        case type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = Self.stringValue(c, forKey: .title)
        description = Self.stringValue(c, forKey: .description)
        image = Self.stringValue(c, forKey: .image)
        key = Self.stringValue(c, forKey: .key)
        type = Self.stringValue(c, forKey: .type)
    }

    private static func stringValue(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let n = try? c.decode(Int.self, forKey: key) {
            return "\(n)"
        }
        if let n = try? c.decode(Double.self, forKey: key) {
            return "\(n)"
        }
        return nil
    }
}

private enum OgpPreviewService {
    private static let mezonAIRegex = try! NSRegularExpression(
        pattern: #"^https:\/\/mezon\.ai\/(chat|invite)(\/|$)"#,
        options: [.caseInsensitive]
    )
    private static let youtubeRegex = try! NSRegularExpression(
        pattern: #"(?:youtube\.com\/(?:watch\?v=|embed\/|v\/|e\/|shorts\/)|youtu\.be\/)"#,
        options: [.caseInsensitive]
    )
    private static let facebookRegex = try! NSRegularExpression(
        pattern: #"(?:facebook\.com\/(?:reel\/|watch\?v=|[\w.]+\/videos\/(?:[\w.]+\/)?))([\w-]+)"#,
        options: [.caseInsensitive]
    )
    private static let tiktokRegex = try! NSRegularExpression(
        pattern: #"(?:tiktok\.com\/@[^\/]+\/video\/\d+|vm\.tiktok\.com\/[a-zA-Z0-9]+|tiktok\.com\/t\/[a-zA-Z0-9]+)"#,
        options: [.caseInsensitive]
    )

    static func fetchableCandidates(in text: String) -> [OgpLinkCandidate] {
        linkCandidates(in: text).filter { !shouldSkip(link: $0.url) }
    }

    static func fetch(link: OgpLinkCandidate) async throws -> OgpPreviewItem? {
        var request = URLRequest(url: MezonConfig.ogpURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": link.url])

        let (data, response) = try await httpData(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let decoded = try JSONDecoder().decode(OgpPreviewResponse.self, from: data)
        let title = decoded.title ?? ""
        let image = decoded.image ?? ""
        guard !title.isEmpty, !image.isEmpty else { return nil }
        return OgpPreviewItem(
            url: link.url,
            title: title,
            description: decoded.description ?? "",
            image: image,
            type: decoded.type ?? "",
            index: link.range.location
        )
    }

    private static func httpData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, *) {
            return try await URLSession.shared.data(for: request)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private static func linkCandidates(in text: String) -> [OgpLinkCandidate] {
        let ns = text as NSString
        let len = ns.length
        let httpLen = ("http://" as NSString).length
        let httpsLen = ("https://" as NSString).length
        let stop: Set<unichar> = [0x20, 0x0A, 0x0D, 0x09]
        let trailing: Set<unichar> = [0x2C, 0x2E, 0x21, 0x3F, 0x3B, 0x3A]

        var links: [OgpLinkCandidate] = []
        var i = 0
        while i < len {
            let hasHTTPS = i + httpsLen <= len
                && ns.substring(with: NSRange(location: i, length: httpsLen)).lowercased() == "https://"
            let hasHTTP = i + httpLen <= len
                && ns.substring(with: NSRange(location: i, length: httpLen)).lowercased() == "http://"
            guard hasHTTPS || hasHTTP else {
                i += 1
                continue
            }

            let start = i
            var end = i + (hasHTTPS ? httpsLen : httpLen)
            while end < len, !stop.contains(ns.character(at: end)) {
                end += 1
            }
            let minEnd = start + (hasHTTPS ? httpsLen : httpLen)
            var cleanEnd = end
            while cleanEnd > minEnd, trailing.contains(ns.character(at: cleanEnd - 1)) {
                cleanEnd -= 1
            }
            if cleanEnd > minEnd {
                let range = NSRange(location: start, length: cleanEnd - start)
                links.append(OgpLinkCandidate(url: ns.substring(with: range), range: range))
            }
            i = max(end, start + 1)
        }
        return links
    }

    private static func shouldSkip(link: String) -> Bool {
        if regex(mezonAIRegex, matches: link) { return true }
        if regex(youtubeRegex, matches: link) { return true }
        if regex(tiktokRegex, matches: link) { return true }
        if regex(facebookRegex, matches: link) { return true }
        if isGoogleMapLink(link) { return true }
        return false
    }

    private static func regex(_ regex: NSRegularExpression, matches text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func isGoogleMapLink(_ link: String) -> Bool {
        let lower = link.lowercased()
        guard let components = URLComponents(string: lower), let host = components.host else {
            return false
        }
        if host == "maps.app.goo.gl" || host == "goo.gl" && components.path.hasPrefix("/maps") {
            return true
        }
        if host.hasSuffix("google.com") && components.path.hasPrefix("/maps") {
            return true
        }
        return lower.contains("google.com/maps")
    }
}

private final class OgpPreviewView: UIView {
    static let preferredHeight: CGFloat = 70

    var onClose: (() -> Void)?

    private var currentImageURL: String?
    private let gradientLayer = CAGradientLayer()

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14.sf, weight: .bold)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.sf, weight: .regular)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 13.sf, weight: .semibold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isHidden = true
        gradientLayer.startPoint = CGPoint(x: 1, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0, y: 0)
        layer.insertSublayer(gradientLayer, at: 0)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        content.addSubview(imageView)
        content.addSubview(titleLabel)
        content.addSubview(descriptionLabel)
        content.addSubview(closeButton)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10.sw),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10.sw),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: content.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 50),

            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10.sw),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8.sw),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 1),

            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])

        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func configure(_ item: OgpPreviewItem) {
        isHidden = false
        titleLabel.text = item.title
        descriptionLabel.text = item.description
        let imageURL = item.image.trimmingCharacters(in: .whitespacesAndNewlines)
        currentImageURL = imageURL
        imageView.isHidden = imageURL.isEmpty
        imageView.image = nil
        guard !imageURL.isEmpty else { return }
        if let cached = ImageCache.shared.image(forKey: imageURL) {
            imageView.image = cached
            return
        }
        ImageCache.shared.loadImage(urlString: imageURL) { [weak self] image in
            guard let self, self.currentImageURL == imageURL else { return }
            self.imageView.image = image
        }
    }

    func clear() {
        isHidden = true
        currentImageURL = nil
        titleLabel.text = nil
        descriptionLabel.text = nil
        imageView.image = nil
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondaryLight
        gradientLayer.colors = [t.secondary.cgColor, t.secondaryLight.cgColor]
        titleLabel.textColor = t.textLink
        descriptionLabel.textColor = t.text
        closeButton.tintColor = t.text
    }
}

final class SendMessageInputViewController: UIViewController {

    private static let mentionHereUserId: Int64 = 1_775_731_111_020_111_321
    private static let threadArchiveDurationSeconds: Int = 7 * 24 * 60 * 60
    private static let threadJoinedActiveStatus: Int32 = 1
    private static let threadActivePrivateJoinedStatus: Int32 = 3

    private static func composerEmojiFaceIcon(pointSize: CGFloat) -> UIImage? {
        let sym = UIImage.SymbolConfiguration(pointSize: pointSize)
        return UIImage(named: "Chat/FaceIcon")
            ?? UIImage(systemName: "face.smiling", withConfiguration: sym)
    }

    private static func composerEmojiToolbarIcon(showKeyboard: Bool, pointSize: CGFloat) -> UIImage? {
        if showKeyboard {
            return UIImage(systemName: "keyboard", withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize))
        }
        return composerEmojiFaceIcon(pointSize: pointSize)
    }

    private let context: AccountContext
    internal var channel: Mezon_Api_ChannelDescription {
        didSet {
            guard channel.channelID != oldValue.channelID || channel.type != oldValue.type else { return }
            if isViewLoaded {
                if isVoiceRecordingActive {
                    cancelVoiceRecording(deleteFile: true)
                } else {
                    voiceRecordingOverlay.isHidden = true
                }
                refreshSendPermissionAvailability()
            }
        }
    }
    private let clanId: Int64
    var topicId: Int64 = 0
    private var ambiguousDeliveryVerifyTask: Task<Void, Never>?
    private var deliveryConfirmTask: Task<Void, Never>?
    private var pendingDeliveryConfirmations: [String: Date] = [:]
    private var locallyReactivatedThreadIds = Set<Int64>()
    private var locallyJoinedThreadIds = Set<Int64>()
    private var disposables = DisposableSet()
    private var mentionDisposables = DisposableSet()

    private let textPipe = ValuePipe<String>()
    private let placeholderPipe = ValuePipe<String>()

    private(set) var text: String = ""
    var placeholder: String

    var onVoiceTapped: (() -> Void)?
    var onSent: (() -> Void)?
    var onError: ((String) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?
    var onInlineSuggestionVisibilityChanged: ((Bool) -> Void)?
    var onInlineSuggestionHostHeightChanged: ((CGFloat) -> Void)?
    weak var inlineSuggestionHost: UIView?
    var primarySendActionOverride: (() -> Void)?
    var alwaysShowAttachToolbarWhileTyping: Bool = false
    var hidesAdvanceComposerButton: Bool = false
    var suppressStoredComposerDraftRestoreOnLoad: Bool = false
    var skipsPersistingComposerDraftOnLifecycleEnd: Bool = false
    var skipOptimisticPendingMessageOnSend: Bool = false
    var preferChannelScopedMentions: Bool = false

    var inputBarBottomConstraint: NSLayoutConstraint?

    func syncComposerBottomSafeInset(_ inset: CGFloat) {
        let v = max(0, inset)
        guard inputBarBottomConstraint?.constant != -v else { return }
        inputBarBottomConstraint?.constant = -v
    }

    private func layoutSuperviewForComposerChange(
        shouldAnimateSuperview: Bool,
        duration: TimeInterval = 0.2,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let host = view.superview else {
            completion?(true)
            return
        }
        let animateHost = shouldAnimateSuperview && !textView.isFirstResponder && duration > 0
        if animateHost {
            UIView.animate(withDuration: duration, animations: { host.layoutIfNeeded() }, completion: completion)
        } else {
            host.layoutIfNeeded()
            completion?(true)
        }
    }

    private var previewHeightConstraint: NSLayoutConstraint?
    private var ogpPreviewHeightConstraint: NSLayoutConstraint?
    private var replyBannerHeightConstraint: NSLayoutConstraint?

    private(set) var replyDisplay: ChatMessageDisplay?
    private var editingDisplay: ChatMessageDisplay?
    private var isEditingShareContactMessage: Bool {
        editingDisplay?.shareContactData != nil
    }
    private static let replyBannerHeight: CGFloat = 40

    private static var channelAttachmentCache: [String: ([UIImage], [Int: URL])] = [:]
    private static var channelTextDraftCache: [String: ComposerDraftSnapshot] = [:]
    private static var channelEditingStateCache: [String: ComposerEditingStateSnapshot] = [:]

    private var cacheKey: String { "\(clanId)-\(channel.channelID)-\(topicId)" }

    private func draftStorageKey(for ch: Mezon_Api_ChannelDescription, topicId tid: Int64) -> String {
        "\(clanId)-\(ch.channelID)-\(tid)"
    }

    private(set) var pickedImages: [UIImage] = []
    private var pickedFileURLs: [Int: URL] = [:]
    private(set) var pickedFiles: [PickedFileInfo] = []
    private var editingRemoteImageAttachments: [ParsedAttachment] = []
    private var editingRemoteFileAttachments: [ParsedAttachment] = []

    static let maxAttachmentsPerMessage = 20
    static let maxMessageContentBytes = 3700

    private var currentAttachmentCount: Int {
        pickedImages.count + pickedFiles.count
            + editingRemoteImageAttachments.count + editingRemoteFileAttachments.count
    }

    private var remainingAttachmentSlots: Int {
        max(0, Self.maxAttachmentsPerMessage - currentAttachmentCount)
    }

    private func notifyAttachmentLimitReached() {
        Toast.info("You can attach up to \(Self.maxAttachmentsPerMessage) items per message.", title: "")
    }

    private var allMentionMembers: [MentionMember] = []
    private var allMentionSuggestionItems: [MentionSuggestionItem] = []
    private var activeMentions: [ComposerMention] = []
    private var activeHashtags: [ComposerHashtag] = []

    private var emojiIdByColonToken: [String: String] = [:]
    private var lastHandledComposerSelection = NSRange(location: -1, length: -1)
    private var lastHandledComposerSelectionTextLength = -1
    private var isHandlingComposerSelectionChange = false
    private var didAttemptEmojiSuggestionCacheLoad = false
    private var mentionSuggestionView: MentionSuggestionView?
    private var mentionSuggestionHeightConstraint: NSLayoutConstraint?
    private var mentionComposerConstraints: [NSLayoutConstraint] = []
    private var mentionHostConstraints: [NSLayoutConstraint] = []

    private var allSuggestionEmojis: [CachedClanEmojiRecord] = []
    private var emojiSuggestionView: EmojiSuggestionView?
    private var emojiSuggestionHeightConstraint: NSLayoutConstraint?
    private var emojiComposerConstraints: [NSLayoutConstraint] = []
    private var emojiHostConstraints: [NSLayoutConstraint] = []

    private var allHashtagChannelCandidates: [Mezon_Api_ChannelDescription] = []
    private var hashtagSuggestionView: HashtagSuggestionView?
    private var hashtagSuggestionHeightConstraint: NSLayoutConstraint?
    private var hashtagComposerConstraints: [NSLayoutConstraint] = []
    private var hashtagHostConstraints: [NSLayoutConstraint] = []
    private var lastInlineSuggestionHostReportedHeight: CGFloat = -1

    private lazy var replyBannerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = true
        return v
    }()

    private lazy var replyLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14)
        return lbl
    }()

    private lazy var replyCancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        btn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        btn.addTarget(self, action: #selector(clearReplyAction), for: .touchUpInside)
        return btn
    }()

    private lazy var attachmentPreviewView: AttachmentPreviewView = {
        let v = AttachmentPreviewView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = true
        v.onRemove = { [weak self] index in
            self?.removeAttachment(at: index)
        }
        return v
    }()

    private lazy var ogpPreviewView: OgpPreviewView = {
        let v = OgpPreviewView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = true
        v.onClose = { [weak self] in
            self?.clearOgpPreview(userDismissed: true, resetDismissed: false)
        }
        return v
    }()

    private lazy var inputBarView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var topSeparator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var sendPermissionRestrictedChrome: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private lazy var sendPermissionRestrictedTopSep: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var sendPermissionRestrictedInner: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 8.sf
        v.clipsToBounds = true
        return v
    }()

    private lazy var sendPermissionRestrictedLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14.sf, weight: .regular)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.text = L(L10n.ChannelMessages.noSendPermission)
        return l
    }()

    private var composerSendPermissionBlocked = false
    private var isAttachControlCollapsed = false
    private var attachButtonWidthConstraint: NSLayoutConstraint?
    private var advanceButtonWidthConstraint: NSLayoutConstraint?
    private var chevronButtonWidthConstraint: NSLayoutConstraint?

    private let voiceRecordingOverlay = VoiceRecordingOverlayView()
    private var voiceLongPressGesture: UILongPressGestureRecognizer!
    private var voiceAudioRecorder: AVAudioRecorder?
    private var voiceRecordingFileURL: URL?
    private var voiceRecordingStartDate: Date?
    private var isVoiceRecordingActive = false
    private var voiceRecordingCancelled = false
    private var voiceRecordingStartAborted = false
    private var voiceSlideAnchorX: CGFloat?
    private var activeOgpPreviewItem: OgpPreviewItem?
    private var ogpFetchTask: Task<Void, Never>?
    private var ogpRequestedKey: String = ""
    private var dismissedOgpLink: String = ""

    private lazy var chevronButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .semibold)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(expandAttachControlsAction), for: .touchUpInside)
        return btn
    }()

    private lazy var attachButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(openPhotoPickerAction), for: .touchUpInside)
        return btn
    }()

    private lazy var textView: PastableTextView = {
        let tv = PastableTextView()
        tv.isScrollEnabled = false
        let pad = Self.composerVerticalInset
        tv.textContainerInset = UIEdgeInsets(top: pad, left: 12, bottom: pad, right: 36)
        tv.textContainer.lineFragmentPadding = 0
        tv.clipsToBounds = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.returnKeyType = .default
        tv.enablesReturnKeyAutomatically = true
        tv.alwaysBounceVertical = false
        tv.alwaysBounceHorizontal = false
        tv.bounces = true
        tv.scrollsToTop = false
        tv.showsVerticalScrollIndicator = true
        tv.showsHorizontalScrollIndicator = false
        tv.contentInsetAdjustmentBehavior = .never
        tv.keyboardDismissMode = .none
        tv.panGestureRecognizer.cancelsTouchesInView = true
        tv.disablesInteractiveKeyboardGestureRecognizer = true
        tv.disablesInteractiveTransitionGestureRecognizer = true
        tv.disablesInteractiveTransitionGestureRecognizerNow = { true }
        tv.onImagesPasted = { [weak self] images in
            self?.handlePastedImages(images)
        }
        tv.onGIFPasted = { [weak self] data in
            self?.handlePastedGIF(data)
        }
        tv.onLongTextPasted = { [weak self] pasted in
            self?.convertPastedTextToFileIfTooLong(pasted) ?? false
        }
        return tv
    }()

    private lazy var placeholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isUserInteractionEnabled = false
        return lbl
    }()

    private var textViewHeightConstraint: NSLayoutConstraint?
    private var inputBarHeightConstraint: NSLayoutConstraint?
    private static var composerControlHeight: CGFloat { 40.swh }
    private static var textViewMinHeight: CGFloat { composerControlHeight }
    private static var composerVerticalInset: CGFloat {
        let lineH = ceil(UIFont.systemFont(ofSize: 15.sf).lineHeight)
        let pad = floor((composerControlHeight - lineH) / 2)
        return max(2, pad)
    }
    private static let inputBarPadding: CGFloat = 16

    private(set) var isEmojiPickerVisible = false
    private(set) var isAdvancePanelVisible = false
    private var lastKeyboardHeight: CGFloat = 260
    var keyboardOverlayHeightEstimate: CGFloat { lastKeyboardHeight }
    var onToggleEmojiPicker: ((Bool, CGFloat) -> Void)?
    var onToggleAdvancePanel: ((Bool, CGFloat) -> Void)?
    var onAnonymousModeChanged: (() -> Void)?
    private var clanPreventAnonymous = false

    private lazy var advanceButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        btn.addTarget(self, action: #selector(toggleAdvancePanelAction), for: .touchUpInside)
        return btn
    }()

    private lazy var emojiButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(Self.composerEmojiFaceIcon(pointSize: 18.sf), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(toggleEmojiPickerAction), for: .touchUpInside)
        return btn
    }()

    private lazy var anonymousIndicatorButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isHidden = true
        let cfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let image = UIImage(named: "Chat/AnonymousIcon")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: "sunglasses.fill", withConfiguration: cfg)
        b.setImage(image, for: .normal)
        b.imageView?.contentMode = .scaleAspectFit
        b.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 6.0)
        b.layer.cornerRadius = 12
        b.clipsToBounds = true
        b.accessibilityLabel = "Anonymous message"
        b.addTarget(self, action: #selector(anonymousIndicatorTapped), for: .touchUpInside)
        return b
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let sendSide: CGFloat = 40.swh
        btn.layer.cornerRadius = sendSide / 2
        btn.clipsToBounds = true
        let sendCfg = UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)
        let sendImg = UIImage(named: "Chat/SendMessageIcon")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: "paperplane.fill", withConfiguration: sendCfg)
        btn.setImage(sendImg, for: .normal)
        btn.imageView?.contentMode = .scaleAspectFit
        let iconInset: CGFloat = 9.sf
        btn.imageEdgeInsets = UIEdgeInsets(top: iconInset, left: iconInset, bottom: iconInset, right: iconInset)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        btn.addTarget(self, action: #selector(sendAction), for: .touchUpInside)
        btn.alpha = 0
        btn.isHidden = true
        return btn
    }()

    private let voiceMicImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(named: "Chat/MicrophoneIcon")?.withRenderingMode(.alwaysOriginal)
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentHuggingPriority(.required, for: .vertical)
        return iv
    }()

    private lazy var voiceButton: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 20.swh
        v.clipsToBounds = true
        v.isUserInteractionEnabled = true
        v.addSubview(voiceMicImageView)
        NSLayoutConstraint.activate([
            voiceMicImageView.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            voiceMicImageView.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            voiceMicImageView.widthAnchor.constraint(equalToConstant: 22.sf),
            voiceMicImageView.heightAnchor.constraint(equalToConstant: 22.sf),
        ])
        return v
    }()

    private var inputBarCurrentHeight: CGFloat {
        return currentTextViewHeight + Self.inputBarPadding
    }

    var totalHeight: CGFloat {
        if composerSendPermissionBlocked {
            return Self.textViewMinHeight + Self.inputBarPadding
        }
        var h = inputBarCurrentHeight
        let totalImg = pickedImages.count + editingRemoteImageAttachments.count
        let totalFile = pickedFiles.count + editingRemoteFileAttachments.count
        if totalImg > 0 || totalFile > 0 {
            h += AttachmentPreviewView.preferredHeight(
                imageCount: totalImg, fileCount: totalFile)
        }
        if activeOgpPreviewItem != nil {
            h += OgpPreviewView.preferredHeight
        }
        if replyDisplay != nil || editingDisplay != nil {
            h += Self.replyBannerHeight
        }
        return h
    }

    private func notifyComposerHeightChanged() {
        onHeightChanged?(totalHeight)
    }

    private var inlineSuggestionStripVisible: Bool {
        if let m = mentionSuggestionView, !m.isHidden,
           (mentionSuggestionHeightConstraint?.constant ?? 0) > 0.5 { return true }
        if let e = emojiSuggestionView, !e.isHidden,
           (emojiSuggestionHeightConstraint?.constant ?? 0) > 0.5 { return true }
        if let h = hashtagSuggestionView, !h.isHidden,
           (hashtagSuggestionHeightConstraint?.constant ?? 0) > 0.5 { return true }
        return false
    }

    private func notifyInlineSuggestionVisibilityChanged() {
        onInlineSuggestionVisibilityChanged?(inlineSuggestionStripVisible)
    }

    private func promoteInlineSuggestionZOrder(strip: UIView) {
        if let host = inlineSuggestionHost, strip.superview === host {
            host.superview?.bringSubviewToFront(host)
        } else {
            view.bringSubviewToFront(strip)
        }
        view.bringSubviewToFront(inputBarView)
        if !voiceRecordingOverlay.isHidden {
            view.bringSubviewToFront(voiceRecordingOverlay)
        }
        if !sendPermissionRestrictedChrome.isHidden {
            view.bringSubviewToFront(sendPermissionRestrictedChrome)
        }
    }

    private func clearInlineSuggestionHost(except strip: UIView? = nil) {
        guard let host = inlineSuggestionHost else { return }
        for subview in host.subviews where subview !== strip {
            subview.removeFromSuperview()
        }
    }

    private func remountInlineSuggestionStripToComposer(
        _ strip: UIView,
        heightConstraint: NSLayoutConstraint?,
        composerConstraints: [NSLayoutConstraint],
        hostConstraints: inout [NSLayoutConstraint]
    ) {
        if !hostConstraints.isEmpty {
            NSLayoutConstraint.deactivate(hostConstraints)
            hostConstraints = []
        }
        if strip.superview !== view {
            strip.removeFromSuperview()
            view.insertSubview(strip, at: 0)
        }
        if composerConstraints.contains(where: { !$0.isActive }) {
            NSLayoutConstraint.activate(composerConstraints)
        }
        heightConstraint?.isActive = true
    }

    private func mountInlineSuggestionStrip(
        _ strip: UIView,
        heightConstraint: NSLayoutConstraint?,
        composerConstraints: [NSLayoutConstraint],
        hostConstraints: inout [NSLayoutConstraint],
        visibleHeight: CGFloat
    ) {
        if let host = inlineSuggestionHost {
            if visibleHeight < 0.5 {
                guard !host.isHidden || lastInlineSuggestionHostReportedHeight >= 0 else { return }
                remountInlineSuggestionStripToComposer(
                    strip,
                    heightConstraint: heightConstraint,
                    composerConstraints: composerConstraints,
                    hostConstraints: &hostConstraints
                )
                lastInlineSuggestionHostReportedHeight = -1
                host.isHidden = true
                onInlineSuggestionHostHeightChanged?(0)
                return
            }
            if strip.superview === host,
               !hostConstraints.isEmpty,
               hostConstraints.allSatisfy(\.isActive),
               abs(lastInlineSuggestionHostReportedHeight - visibleHeight) < 0.5,
               !host.isHidden {
                return
            }
            clearInlineSuggestionHost(except: strip)
            NSLayoutConstraint.deactivate(composerConstraints)
            if strip.superview !== host {
                strip.removeFromSuperview()
                host.addSubview(strip)
                if !hostConstraints.isEmpty {
                    NSLayoutConstraint.deactivate(hostConstraints)
                    hostConstraints = []
                }
            }
            if hostConstraints.isEmpty {
                hostConstraints = [
                    strip.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    strip.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                    strip.topAnchor.constraint(equalTo: host.topAnchor),
                    strip.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                ]
                NSLayoutConstraint.activate(hostConstraints)
            }
            heightConstraint?.isActive = false
            lastInlineSuggestionHostReportedHeight = visibleHeight
            onInlineSuggestionHostHeightChanged?(visibleHeight)
            host.isHidden = false
            host.superview?.bringSubviewToFront(host)
        } else {
            if strip.superview !== view {
                if !hostConstraints.isEmpty {
                    NSLayoutConstraint.deactivate(hostConstraints)
                    hostConstraints = []
                }
                strip.removeFromSuperview()
                view.insertSubview(strip, at: 0)
                NSLayoutConstraint.activate(composerConstraints)
            }
            heightConstraint?.isActive = true
            onInlineSuggestionHostHeightChanged?(0)
        }
    }

    private var currentTextViewHeight: CGFloat = 40.swh

    init(placeholder: String = "", channel: Mezon_Api_ChannelDescription, clanId: Int64, context: AccountContext) {
        self.placeholder = placeholder
        self.channel = channel
        self.clanId = clanId
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = OverflowHitTestView()
        v.backgroundColor = .clear
        v.clipsToBounds = false
        v.disablesInteractiveTransitionGestureRecognizer = true
        v.disablesInteractiveTransitionGestureRecognizerNow = { true }
        v.overflowTargets = { [weak self] in
            guard let self else { return [] }
            var targets: [UIView] = []
            if let m = self.mentionSuggestionView, !m.isHidden, (self.mentionSuggestionHeightConstraint?.constant ?? 0) > 0.5 {
                targets.append(m)
            }
            if let e = self.emojiSuggestionView, !e.isHidden, (self.emojiSuggestionHeightConstraint?.constant ?? 0) > 0.5 {
                targets.append(e)
            }
            if let h = self.hashtagSuggestionView, !h.isHidden, (self.hashtagSuggestionHeightConstraint?.constant ?? 0) > 0.5 {
                targets.append(h)
            }
            return targets
        }
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMentionSuggestion()
        setupEmojiSuggestion()
        setupHashtagSuggestion()
        setupBindings()
        setupThemeObserver()
        applyTheme()
        if suppressStoredComposerDraftRestoreOnLoad {
            resetComposerVisualDraftState()
            onHeightChanged?(totalHeight)
        } else {
            restoreComposerDraftAndAttachmentsForCurrentKey()
        }
        loadClanMembers()
        bindMentionDataUpdates()
        reloadEmojiSuggestionList()
        reloadHashtagChannelCandidates()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEmojiListDidUpdate),
                                               name: Self.emojiListDidUpdateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSendPermissionContextChanged),
                                               name: .mezonChannelOverriddenPermissionsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSendPermissionContextChanged),
                                               name: .mezonRolesDidChange, object: nil)
        disposables.add(
            (context.engine.friendsData.friendsUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] _ in
                    self?.refreshSendPermissionAvailability()
                })
        )
        refreshSendPermissionAvailability()
        if channelStreamMode == MezonConstants.ChannelStreamMode.dm.rawValue,
           context.engine.friendsData.allFriends().isEmpty {
            Task { [weak self] in
                guard let self, let token = await self.context.getToken() else { return }
                await self.context.engine.friendsData.refreshFromNetwork(token: token)
            }
        }
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let bottomInset = view.safeAreaInsets.bottom
            lastKeyboardHeight = frame.height - bottomInset
        }
        if isEmojiPickerVisible {
            isEmojiPickerVisible = false
            emojiButton.setImage(Self.composerEmojiFaceIcon(pointSize: 18.sf), for: .normal)
        }
        if isAdvancePanelVisible {
            isAdvancePanelVisible = false
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)
            advanceButton.setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: iconConfig), for: .normal)
        }
    }

    private var channelStreamMode: Int32 {
        switch channel.type {
        case MezonConstants.ChannelType.thread.rawValue:
            return MezonConstants.ChannelStreamMode.thread.rawValue
        case MezonConstants.ChannelType.dm.rawValue:
            return MezonConstants.ChannelStreamMode.dm.rawValue
        case MezonConstants.ChannelType.group.rawValue:
            return MezonConstants.ChannelStreamMode.group.rawValue
        default:
            return clanId == 0
                ? MezonConstants.ChannelStreamMode.group.rawValue
                : MezonConstants.ChannelStreamMode.channel.rawValue
        }
    }

    private var includeRoleMentions: Bool {
        let m = channelStreamMode
        return m == MezonConstants.ChannelStreamMode.channel.rawValue
            || m == MezonConstants.ChannelStreamMode.thread.rawValue
    }

    private var includeHereMention: Bool {
        let m = channelStreamMode
        return includeRoleMentions || m == MezonConstants.ChannelStreamMode.group.rawValue
    }


    private var includeHashtagSuggestions: Bool {
        channelStreamMode != MezonConstants.ChannelStreamMode.group.rawValue
    }

    private var isChannelStreamExemptFromSendPermissionGate: Bool {
        let m = channelStreamMode
        return m == MezonConstants.ChannelStreamMode.dm.rawValue
            || m == MezonConstants.ChannelStreamMode.group.rawValue
    }

    private var isDirectMessageWithBlockedPeer: Bool {
        guard channelStreamMode == MezonConstants.ChannelStreamMode.dm.rawValue else { return false }
        guard let peerId = channel.userIds.first, peerId != 0 else { return false }
        return context.engine.friendsData.blockedUserIds().contains(peerId)
    }

    private var isSelfDM: Bool {
        guard channelStreamMode == MezonConstants.ChannelStreamMode.dm.rawValue else { return false }
        let currentUserId = Int64(context.currentUser?.id ?? "") ?? 0
        return channel.userIds.first == currentUserId
    }

    private func refreshSendPermissionAvailability() {
        let exempt = isChannelStreamExemptFromSendPermissionGate
        let chId = channel.channelID
        if !exempt, clanId != 0, chId != 0 {
            context.rolePermissions.ensureChannelPermissions(clanId: clanId, channelId: chId)
        }
        let blocked: Bool
        if isSelfDM {
            blocked = false
        } else if isDirectMessageWithBlockedPeer {
            blocked = true
        } else if exempt || clanId == 0 || chId == 0 {
            blocked = false
        } else if !context.rolePermissions.hasResolvedChannelOverriddenPermissionsSnapshot(channelId: chId) {
            blocked = false
        } else {
            blocked = !context.rolePermissions.canSendMessage(clanId: clanId, channelId: chId)
        }
        guard blocked != composerSendPermissionBlocked else { return }
        composerSendPermissionBlocked = blocked
        if blocked {
            textView.resignFirstResponder()
            hideAdvancePanelIfNeeded()
            if isEmojiPickerVisible {
                isEmojiPickerVisible = false
                emojiButton.setImage(Self.composerEmojiFaceIcon(pointSize: 18.sf), for: .normal)
                onToggleEmojiPicker?(false, 0)
            }
            clearReplyAction()
        }
        applySendPermissionRestrictionLayout()
        onHeightChanged?(totalHeight)
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.2)
    }

    private func applySendPermissionRestrictionLayout() {
        let blocked = composerSendPermissionBlocked
        sendPermissionRestrictedChrome.isHidden = !blocked
        inputBarView.isHidden = blocked
        if blocked {
            if isVoiceRecordingActive {
                cancelVoiceRecording(deleteFile: true)
            } else {
                voiceRecordingOverlay.isHidden = true
            }
        } else {
            voiceRecordingOverlay.isHidden = !isVoiceRecordingActive
        }
        if blocked {
            inputBarHeightConstraint?.constant = 0
            replyBannerHeightConstraint?.constant = 0
            previewHeightConstraint?.constant = 0
            ogpPreviewHeightConstraint?.constant = 0
            ogpPreviewView.isHidden = true
        } else {
            inputBarHeightConstraint?.constant = currentTextViewHeight + Self.inputBarPadding
            updateReplyBannerVisibility()
            updatePreviewVisibility()
            updateOgpPreviewVisibility()
        }
    }

    @objc private func handleSendPermissionContextChanged(_ notification: Notification) {
        if let cid = notification.userInfo?["channelId"] as? Int64, cid != channel.channelID { return }
        refreshSendPermissionAvailability()
    }

    private var mentionLookupChannelIds: [Int64] {
        var result: [Int64] = []
        var seen = Set<Int64>()
        func appendUnique(_ id: Int64) {
            guard id != 0, seen.insert(id).inserted else { return }
            result.append(id)
        }
        if clanId == 0 {
            appendUnique(channel.channelID)
            return result
        }
        if channel.type == MezonConstants.ChannelType.thread.rawValue {
            appendUnique(channel.parentID)
        }
        appendUnique(channel.channelID)
        return result
    }

    private func bindMentionDataUpdates() {
        mentionDisposables.dispose()
        mentionDisposables = DisposableSet()
        for cid in mentionLookupChannelIds {
            mentionDisposables.add(
                (context.account.postbox.channelMetaView(channelId: cid) |> deliverOnMainQueue)
                    .start(next: { [weak self] _ in
                        self?.reloadMentionMembersFromChannelMetaOnly()
                    })
            )
        }
        mentionDisposables.add(
            (context.engine.clanData.clanRolesUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] updatedClanId in
                    guard let self, updatedClanId == self.clanId else { return }
                    self.rebuildMentionSuggestionItems()
                })
        )
    }

    private func rebindMentionForCurrentChannel() {
        bindMentionDataUpdates()
        allMentionMembers = []
        allMentionSuggestionItems = []
        loadClanMembers()
    }

    func syncStoredDraftIdentity(
        channel newChannel: Mezon_Api_ChannelDescription,
        topicId newTopicId: Int64,
        migrateDraftToNewChannelIdentity: Bool = false,
        preserveComposerContentsDuringMigration: Bool = false
    ) {
        guard newChannel.channelID != channel.channelID || newTopicId != topicId else {
            channel = newChannel
            return
        }
        let backupPickedImages = (migrateDraftToNewChannelIdentity && !preserveComposerContentsDuringMigration) ? pickedImages : []
        let oldKey = draftStorageKey(for: channel, topicId: topicId)
        let oldAttachmentCacheKey = cacheKey
        if viewIfLoaded?.window != nil {
            stashCurrentComposerDraftIfNeeded()
        }
        let preservedDraft = migrateDraftToNewChannelIdentity ? Self.channelTextDraftCache[oldKey] : nil
        let preservedAttachmentEntry = migrateDraftToNewChannelIdentity ? Self.channelAttachmentCache[oldAttachmentCacheKey] : nil
        channel = newChannel
        topicId = newTopicId
        if migrateDraftToNewChannelIdentity, let preservedDraft {
            let newKey = draftStorageKey(for: channel, topicId: topicId)
            Self.channelTextDraftCache[newKey] = preservedDraft
        }
        if migrateDraftToNewChannelIdentity, let entry = preservedAttachmentEntry, !entry.0.isEmpty {
            Self.channelAttachmentCache[cacheKey] = entry
        }
        rebindMentionForCurrentChannel()
        if preserveComposerContentsDuringMigration && migrateDraftToNewChannelIdentity {
            saveToCache()
            return
        }
        if viewIfLoaded?.window != nil {
            restoreComposerDraftAndAttachmentsForCurrentKey()
        }
        if migrateDraftToNewChannelIdentity, !backupPickedImages.isEmpty {
            pickedImages = backupPickedImages
            attachmentPreviewView.setImages(backupPickedImages)
            saveToCache()
            updatePreviewVisibility()
        }
    }

    private func stashCurrentComposerDraftIfNeeded() {
        let key = draftStorageKey(for: channel, topicId: topicId)
        if let snap = buildComposerDraftSnapshot() {
            Self.channelTextDraftCache[key] = snap
            while Self.channelTextDraftCache.count > 45 {
                if let k = Self.channelTextDraftCache.keys.first {
                    Self.channelTextDraftCache.removeValue(forKey: k)
                } else { break }
            }
        } else {
            Self.channelTextDraftCache.removeValue(forKey: key)
        }
        if let editing = editingDisplay {
            Self.channelEditingStateCache[key] = ComposerEditingStateSnapshot(
                display: editing,
                remoteImageAttachments: editingRemoteImageAttachments,
                remoteFileAttachments: editingRemoteFileAttachments)
            while Self.channelEditingStateCache.count > 45 {
                if let k = Self.channelEditingStateCache.keys.first {
                    Self.channelEditingStateCache.removeValue(forKey: k)
                } else { break }
            }
        } else {
            Self.channelEditingStateCache.removeValue(forKey: key)
        }
    }

    private func hasMeaningfulDraftContent() -> Bool {
        let trimmed = buildPlainTextFromAttributed().trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return true }
        if !pickedImages.isEmpty || !pickedFiles.isEmpty { return true }
        return false
    }

    private func buildComposerDraftSnapshot() -> ComposerDraftSnapshot? {
        guard hasMeaningfulDraftContent() else { return nil }
        let attr = textView.attributedText ?? NSAttributedString()
        let data = try? NSKeyedArchiver.archivedData(withRootObject: attr, requiringSecureCoding: false)
        let mentions = activeMentions.map {
            ComposerMentionSnapshot(
                userId: $0.userId, roleId: $0.roleId, rolename: $0.rolename, displayName: $0.displayName,
                location: $0.range.location, length: $0.range.length)
        }
        let hashtags = activeHashtags.map {
            ComposerHashtagSnapshot(
                channelId: $0.channelId, clanId: $0.clanId, parentId: $0.parentId, channelLabel: $0.channelLabel,
                channelType: $0.channelType, channelPrivate: $0.channelPrivate, ageRestricted: $0.ageRestricted,
                location: $0.range.location, length: $0.range.length)
        }
        let files = pickedFiles.map {
            FileDraftSnapshot(path: $0.url.path, filename: $0.filename, filetype: $0.filetype, filesize: $0.filesize)
        }
        return ComposerDraftSnapshot(
            attributedArchive: data, mentions: mentions, hashtags: hashtags, emojiIdByColon: emojiIdByColonToken, fileDrafts: files)
    }

    private func applyCurrentThemeToRestoredComposer(_ archived: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: archived)
        let full = NSRange(location: 0, length: m.length)
        let t = UIColor.theme
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 15.sf),
            .foregroundColor: UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        ]
        m.addAttributes(normalAttrs, range: full)
        archived.enumerateAttribute(.link, in: full) { value, range, _ in
            guard let value else { return }
            m.addAttribute(.link, value: value, range: range)
        }
        for cm in activeMentions where NSMaxRange(cm.range) <= m.length {
            m.addAttributes(highlightAttrs, range: cm.range)
        }
        for ht in activeHashtags where NSMaxRange(ht.range) <= m.length {
            m.addAttributes(highlightAttrs, range: ht.range)
        }
        let plain = m.string as NSString
        for token in emojiIdByColonToken.keys where !token.isEmpty {
            let nsToken = token as NSString
            let tokenLen = nsToken.length
            guard tokenLen > 0 else { continue }
            var searchStart = 0
            while searchStart <= plain.length - tokenLen {
                let searchRange = NSRange(location: searchStart, length: plain.length - searchStart)
                let found = plain.range(of: token, options: [], range: searchRange)
                if found.location == NSNotFound { break }
                if NSMaxRange(found) <= m.length {
                    m.addAttributes(highlightAttrs, range: found)
                }
                searchStart = NSMaxRange(found)
            }
        }
        return m
    }

    private func applyComposerDraftSnapshot(_ snap: ComposerDraftSnapshot) {
        replyDisplay = nil
        editingDisplay = nil
        updateReplyBannerVisibility()
        pickedImages.removeAll()
        pickedFileURLs.removeAll()
        pickedFiles.removeAll()
        attachmentPreviewView.removeAll()

        activeMentions = snap.mentions.map {
            ComposerMention(
                userId: $0.userId,
                roleId: $0.roleId,
                rolename: $0.rolename,
                displayName: $0.displayName,
                range: NSRange(location: $0.location, length: $0.length))
        }
        activeHashtags = snap.hashtags.map {
            ComposerHashtag(
                channelId: $0.channelId,
                clanId: $0.clanId,
                parentId: $0.parentId,
                channelLabel: $0.channelLabel,
                channelType: $0.channelType,
                channelPrivate: $0.channelPrivate,
                ageRestricted: $0.ageRestricted,
                range: NSRange(location: $0.location, length: $0.length))
        }
        emojiIdByColonToken = snap.emojiIdByColon

        if let data = snap.attributedArchive {
            let unarchived: NSAttributedString? =
                (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data))
                ?? ((try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSMutableAttributedString.self, from: data)) as NSAttributedString?)
            if let u = unarchived {
                textView.attributedText = applyCurrentThemeToRestoredComposer(u)
            } else {
                textView.attributedText = nil
            }
        } else {
            textView.attributedText = nil
        }
        refreshHashtagIconAttachments()
        text = textView.text ?? ""
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.theme.textStrong
        ]
        placeholderLabel.isHidden = !text.isEmpty
        textView.isScrollEnabled = false
        flushComposerHeightAfterContentMutation()
        textPipe.putNext(text)
        scheduleOgpPreviewUpdate(for: text)

        for f in snap.fileDrafts {
            let url = URL(fileURLWithPath: f.path)
            guard FileManager.default.fileExists(atPath: f.path) else { continue }
            let info = PickedFileInfo(url: url, filename: f.filename, filesize: f.filesize, filetype: f.filetype)
            pickedFiles.append(info)
            attachmentPreviewView.addFile(info)
        }
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        syncAttachControlsWithTypedText()
        updateSendVoiceToggle()
        refreshComposerTypingAttributesForSelection()
    }

    private func resetComposerVisualDraftState() {
        replyDisplay = nil
        editingDisplay = nil
        updateReplyBannerVisibility()
        activeMentions.removeAll()
        activeHashtags.removeAll()
        emojiIdByColonToken.removeAll()
        textView.attributedText = nil
        text = ""
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.theme.textStrong
        ]
        placeholderLabel.isHidden = false
        textView.isScrollEnabled = false
        clearPickedImages()
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        textPipe.putNext("")
        clearOgpPreview(userDismissed: false, resetDismissed: true)
        resetTextViewHeight()
        syncAttachControlsWithTypedText()
        updateSendVoiceToggle()
    }

    private func restoreComposerDraftAndAttachmentsForCurrentKey() {
        let key = draftStorageKey(for: channel, topicId: topicId)
        if let snap = Self.channelTextDraftCache[key] {
            applyComposerDraftSnapshot(snap)
        } else {
            resetComposerVisualDraftState()
        }
        restoreStashedEditingStateIfNeeded(forKey: key)
        restoreFromCache()
        updatePreviewVisibility()
        reloadEmojiSuggestionList()
        onHeightChanged?(totalHeight)
    }

    private func restoreStashedEditingStateIfNeeded(forKey key: String) {
        guard let snap = Self.channelEditingStateCache[key] else { return }
        replyDisplay = nil
        editingDisplay = snap.display
        editingRemoteImageAttachments = snap.remoteImageAttachments
        editingRemoteFileAttachments = snap.remoteFileAttachments
        let remoteImagePreviews = snap.remoteImageAttachments.map {
            RemoteAttachmentPreview(url: $0.url, filename: $0.filename, filetype: $0.filetype, isVideo: $0.isVideo)
        }
        let remoteFilePreviews = snap.remoteFileAttachments.map {
            RemoteAttachmentPreview(url: $0.url, filename: $0.filename, filetype: $0.filetype, isVideo: false)
        }
        attachmentPreviewView.setRemoteAttachments(images: remoteImagePreviews, files: remoteFilePreviews)
        updateReplyBannerVisibility()
        if isEditingShareContactMessage {
            hideAdvancePanelIfNeeded()
            hideEmojiPickerIfNeeded()
            collapseAttachControls()
        }
        syncAttachControlsWithTypedText()
        updateSendVoiceToggle()
    }

    func sendReplicatedThreadSeedMessage(from display: ChatMessageDisplay) async throws {
        let record = context.account.postbox.read { tx in
            tx.getMessageById(display.message.id, channelId: display.message.channelId)
                ?? tx.getMessageById(display.message.id)
        }

        let contentData = record?.content ?? display.rawContentData ?? Data()
        let contentStr: String = {
            if let s = String(data: contentData, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
            let text = display.parsedContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "{}" }
            if let data = try? JSONSerialization.data(withJSONObject: ["t": text]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "{}"
        }()

        let attachments: [Mezon_Api_MessageAttachment] = {
            if let data = record?.attachmentsJSON, !data.isEmpty,
               let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: data),
               !list.attachments.isEmpty {
                return list.attachments
            }
            return Self.mezonApiMessageAttachments(
                from: display.attachments.filter {
                    !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        }()

        let mentions: [Mezon_Api_MessageMention] = {
            guard let data = record?.mentionsJSON, !data.isEmpty,
                  let list = try? Mezon_Api_MessageMentionList(serializedBytes: data) else {
                return []
            }
            return list.mentions
        }()

        guard let token = await context.getToken() else {
            throw MezonError.httpError(statusCode: 0, message: "No session")
        }

        try await prepareThreadBeforeSendIfNeeded(
            mentionList: mentions,
            editTargetSenderId: nil,
            token: token
        )

        let mode = MezonConstants.ChannelStreamMode.thread.rawValue
        let isPublic = channel.channelPrivate == 0
        let avatar = context.currentUser?.avatarURL?.absoluteString ?? ""

        _ = try await context.account.network.sendChannelMessage(
            clanId: clanId,
            channelId: channel.channelID,
            mode: mode,
            isPublic: isPublic,
            content: contentStr,
            mentions: mentions,
            attachments: attachments,
            references: [],
            anonymous: false,
            mentionEveryone: false,
            avatar: avatar,
            topicId: topicId,
            code: display.messageCode,
            token: token
        )
    }

    func send() {
        guard !composerSendPermissionBlocked else { return }
        let plainText = buildPlainTextFromAttributed()
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !pickedImages.isEmpty || !pickedFiles.isEmpty
        ensureChannelMetadataResolvedFromPostboxIfNeeded()
        if let edit = editingDisplay, let mid = Int64(edit.message.id) {
            let hasKeptRemote = !editingRemoteImageAttachments.isEmpty || !editingRemoteFileAttachments.isEmpty
            let canSubmitEmptyTextEdit = edit.shareContactData != nil
            guard !trimmed.isEmpty || hasAttachments || hasKeptRemote || canSubmitEmptyTextEdit else { return }
            sendChannelMessage(text: trimmed, images: pickedImages, clanId: clanId, channel: channel, editingMessageId: mid)
            return
        }
        guard !trimmed.isEmpty || hasAttachments else { return }
        sendChannelMessage(text: trimmed, images: pickedImages, clanId: clanId, channel: channel)
    }

    private func ensureChannelMetadataResolvedFromPostboxIfNeeded() {
        guard channel.type == 0, channel.channelID != 0 else { return }
        if clanId == 0 {
            if let cached = context.account.postbox.getDMChannelDescription(channelId: channel.channelID), cached.type != 0 {
                channel = cached
            }
        } else {
            if let (_, cached) = context.account.postbox.getChannelDescription(channelId: channel.channelID), cached.type != 0 {
                channel = cached
            }
        }
    }

    func hasComposerSendPayload() -> Bool {
        let trimmed = buildPlainTextFromAttributed().trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return true }
        if !pickedImages.isEmpty || !pickedFiles.isEmpty { return true }
        return false
    }

    @objc private func clearReplyAction() {
        if editingDisplay != nil {
            clearEditingMessage()
        } else {
            clearReply()
        }
    }
    @objc private func expandAttachControlsAction() {
        guard !isEditingShareContactMessage else { return }
        expandAttachControls()
    }
    @objc private func openPhotoPickerAction() { openPhotoPicker() }
    @objc private func toggleAdvancePanelAction() { toggleAdvancePanel() }
    @objc private func toggleEmojiPickerAction() { toggleEmojiPicker() }
    @objc private func sendAction() {
        if let primarySendActionOverride {
            primarySendActionOverride()
        } else {
            send()
        }
    }
    @objc private func anonymousIndicatorTapped() {
        guard clanId != 0, !clanPreventAnonymous else { return }
        _ = AnonymousMessageStore.toggle(clanId: clanId)
        refreshAnonymousUI()
        onAnonymousModeChanged?()
    }


    func sendLocation(latitude: Double, longitude: Double) {
        guard !composerSendPermissionBlocked else { return }
        guard !isEditingShareContactMessage else { return }
        if editingDisplay != nil {
            clearEditingMessage()
        }
        let googleMapsLink = "https://www.google.com/maps?q=\(latitude),\(longitude)&z=14&t=m&mapclient=embed"
        let linkLength = googleMapsLink.count

        let contentJSON: [String: Any] = [
            "t": googleMapsLink,
            "lk": [["s": 0, "e": linkLength]],
            "mk": [["s": 0, "e": linkLength, "type": "lk"]]
        ]
        let contentStr: String
        if let data = try? JSONSerialization.data(withJSONObject: contentJSON),
           let str = String(data: data, encoding: .utf8) {
            contentStr = str
        } else {
            contentStr = "{}"
        }

        let mode: Int32 = {
            switch channel.type {
            case MezonConstants.ChannelType.thread.rawValue:
                return MezonConstants.ChannelStreamMode.thread.rawValue
            case MezonConstants.ChannelType.dm.rawValue:
                return MezonConstants.ChannelStreamMode.dm.rawValue
            case MezonConstants.ChannelType.group.rawValue:
                return MezonConstants.ChannelStreamMode.group.rawValue
            default:
                return clanId == 0
                    ? MezonConstants.ChannelStreamMode.group.rawValue
                    : MezonConstants.ChannelStreamMode.channel.rawValue
            }
        }()
        let isPublic = channel.channelPrivate == 0
        let avatar = context.currentUser?.avatarURL?.absoluteString ?? ""
        let replyRef = buildReplyRef()
        let references: [Mezon_Api_MessageRef] = replyRef.map { [$0] } ?? []

        clearReply()
        onSent?()

            Task { @MainActor in
                guard let token = await self.context.getToken() else {
                    self.onError?("No session")
                    return
                }
                do {
                    try await self.activateThreadBeforeSendIfNeeded(token: token)
                    let ack = try await self.context.account.network.sendChannelMessage(
                        clanId: clanId,
                        channelId: channel.channelID,
                        mode: mode,
                        isPublic: isPublic,
                        content: contentStr,
                        mentions: [],
                        attachments: [],
                        references: references,
                        anonymous: self.shouldSendAsAnonymousMessage,
                        mentionEveryone: false,
                        avatar: avatar,
                        topicId: self.topicId,
                        code: 17,
                        token: token
                    )
                    self.markOnboardingWelcomeMessageSentIfNeeded(
                        ack: ack,
                        anonymous: self.shouldSendAsAnonymousMessage
                    )
                } catch {
                    SentryLogger.capture(error, extras: [
                        "where": "sendWaveMessage",
                        "channelId": channel.channelID,
                        "clanId": clanId,
                    ])
                    self.onError?(error.localizedDescription)
            }
        }
    }

    func sendBuzzMessage(text: String) {
        guard !composerSendPermissionBlocked else { return }
        guard !isEditingShareContactMessage else { return }
        if editingDisplay != nil {
            clearEditingMessage()
        }
        let buzzText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !buzzText.isEmpty else { return }

        let contentJSON: [String: Any] = ["t": buzzText]
        let contentStr: String
        if let data = try? JSONSerialization.data(withJSONObject: contentJSON),
           let str = String(data: data, encoding: .utf8) {
            contentStr = str
        } else {
            contentStr = "{}"
        }

        let mode: Int32 = {
            switch channel.type {
            case MezonConstants.ChannelType.thread.rawValue:
                return MezonConstants.ChannelStreamMode.thread.rawValue
            case MezonConstants.ChannelType.dm.rawValue:
                return MezonConstants.ChannelStreamMode.dm.rawValue
            case MezonConstants.ChannelType.group.rawValue:
                return MezonConstants.ChannelStreamMode.group.rawValue
            default:
                return clanId == 0
                    ? MezonConstants.ChannelStreamMode.group.rawValue
                    : MezonConstants.ChannelStreamMode.channel.rawValue
            }
        }()
        let isPublic = channel.channelPrivate == 0
        let avatar = context.currentUser?.avatarURL?.absoluteString ?? ""

            Task { @MainActor in
                guard let token = await self.context.getToken() else {
                    self.onError?("No session")
                    return
                }
                do {
                    try await self.activateThreadBeforeSendIfNeeded(token: token)
                    let ack = try await self.context.account.network.sendChannelMessage(
                        clanId: clanId,
                        channelId: channel.channelID,
                        mode: mode,
                        isPublic: isPublic,
                        content: contentStr,
                        mentions: [],
                        attachments: [],
                        references: [],
                        anonymous: self.shouldSendAsAnonymousMessage,
                        mentionEveryone: false,
                        avatar: avatar,
                        topicId: self.topicId,
                        code: MezonConstants.MessageCode.buzz.rawValue,
                        token: token
                    )
                    self.markOnboardingWelcomeMessageSentIfNeeded(
                        ack: ack,
                        anonymous: self.shouldSendAsAnonymousMessage
                    )
                } catch {
                    SentryLogger.capture(error, extras: [
                        "where": "sendBuzzMessage",
                        "channelId": channel.channelID,
                        "clanId": clanId,
                    ])
                    self.onError?(error.localizedDescription)
            }
        }
    }

    func sendShareContact(friend: Mezon_Api_Friend) {
        guard !composerSendPermissionBlocked else { return }
        guard !shouldSendAsAnonymousMessage else { return }
        guard !isEditingShareContactMessage else { return }
        if editingDisplay != nil {
            clearEditingMessage()
        }
        guard friend.hasUser, friend.user.id != 0 else { return }

        let user = friend.user
        let username = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayNameRaw = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = displayNameRaw.isEmpty ? username : displayNameRaw
        let avatar = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let contentJSON: [String: Any] = [
            "t": "",
            "embed": [[
                "fields": [
                    ["name": "key", "value": MezonConstants.shareContactKey, "inline": true],
                    ["name": "user_id", "value": "\(user.id)", "inline": true],
                    ["name": "username", "value": username, "inline": true],
                    ["name": "display_name", "value": displayName, "inline": true],
                    ["name": "avatar", "value": avatar, "inline": true],
                ],
            ]],
        ]
        let contentStr: String
        if let data = try? JSONSerialization.data(withJSONObject: contentJSON),
           let str = String(data: data, encoding: .utf8) {
            contentStr = str
        } else {
            contentStr = "{}"
        }

        let mode: Int32 = {
            switch channel.type {
            case MezonConstants.ChannelType.thread.rawValue:
                return MezonConstants.ChannelStreamMode.thread.rawValue
            case MezonConstants.ChannelType.dm.rawValue:
                return MezonConstants.ChannelStreamMode.dm.rawValue
            case MezonConstants.ChannelType.group.rawValue:
                return MezonConstants.ChannelStreamMode.group.rawValue
            default:
                return clanId == 0
                    ? MezonConstants.ChannelStreamMode.group.rawValue
                    : MezonConstants.ChannelStreamMode.channel.rawValue
            }
        }()
        let isPublic = channel.channelPrivate == 0
        let senderAvatar = context.currentUser?.avatarURL?.absoluteString ?? ""

        clearReply()
        onSent?()

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.onError?("No session")
                return
            }
            do {
                try await self.activateThreadBeforeSendIfNeeded(token: token)
                let ack = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: [],
                    attachments: [],
                    references: [],
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: senderAvatar,
                    topicId: self.topicId,
                    code: MezonConstants.MessageCode.shareContact.rawValue,
                    token: token
                )
                self.updateCachedDMLastSentMessageIfNeeded(
                    ack: ack,
                    fallbackContent: contentStr
                )
                self.markOnboardingWelcomeMessageSentIfNeeded(ack: ack, anonymous: false)
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "sendShareContact",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                ])
                self.onError?(error.localizedDescription)
            }
        }
    }

    private func updateCachedDMLastSentMessageIfNeeded(
        ack: Mezon_Realtime_ChannelMessageAck,
        fallbackContent: String,
        hasAttachments: Bool = false
    ) {
        guard clanId == 0, topicId == 0 else { return }

        DMListPreviewCache.updateLastSentMessage(
            context: context,
            channelId: channel.channelID,
            fallbackChannel: channel,
            ack: ack,
            content: fallbackContent,
            hasAttachments: hasAttachments
        )
    }

    private func markOnboardingWelcomeMessageSentIfNeeded(
        ack: Mezon_Realtime_ChannelMessageAck,
        anonymous: Bool
    ) {
        ClanOnboardingChannelCache.markSendMessageOnboardingProgressIfNeeded(
            context: context,
            postbox: context.account.postbox,
            clanId: clanId,
            channelId: channel.channelID,
            messageId: ack.messageID,
            messageCode: ack.code,
            anonymous: anonymous
        )
    }

    func sendSticker(_ sticker: CachedClanStickerRecord) {
        guard !isEditingShareContactMessage else { return }
        if editingDisplay != nil {
            clearEditingMessage()
        }
        let src = sticker.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageUrl = !src.isEmpty ? src : "\(MezonConfig.baseImgURL)/stickers/\(sticker.id).webp"

        var att = Mezon_Api_MessageAttachment()
        att.url = imageUrl
        let srcLower = src.lowercased()
        let isAudio = sticker.mediaType == StickerMediaType.audio.rawValue
            || srcLower.hasSuffix(".mp3")
            || srcLower.hasSuffix(".wav")
            || srcLower.hasSuffix(".m4a")
        att.filetype = isAudio ? "audio/mpeg" : "image/gif"
        att.filename = "\(sticker.id)"

        sendChannelMessageWithAttachments(text: "", attachments: [att])
    }


    func sendGif(url: String) {
        guard !isEditingShareContactMessage else { return }
        if editingDisplay != nil {
            clearEditingMessage()
        }
        var att = Mezon_Api_MessageAttachment()
        att.url = url
        att.filetype = "image/gif"
        sendChannelMessageWithAttachments(text: "", attachments: [att])
    }

    func setReply(_ display: ChatMessageDisplay) {
        refreshSendPermissionAvailability()
        guard !composerSendPermissionBlocked else { return }
        editingDisplay = nil
        replyDisplay = display
        updateReplyBannerVisibility()
        textView.becomeFirstResponder()
    }

    func setEditingMessage(_ display: ChatMessageDisplay) {
        refreshSendPermissionAvailability()
        guard !composerSendPermissionBlocked else { return }
        reloadEmojiSuggestionList()
        replyDisplay = nil
        editingDisplay = display
        clearPickedImages()
        populateComposerFromEditDisplay(display)
        updateReplyBannerVisibility()
        if isEditingShareContactMessage {
            hideAdvancePanelIfNeeded()
            hideEmojiPickerIfNeeded()
            collapseAttachControls()
        }
        syncAttachControlsWithTypedText()
        updateSendVoiceToggle()
        textView.becomeFirstResponder()
    }

    func clearEditingMessage() {
        editingDisplay = nil
        clearText()
        clearPickedImages()
        updateReplyBannerVisibility()
    }

    func clearReply() {
        replyDisplay = nil
        updateReplyBannerVisibility()
    }

    private func refreshBannerLabel() {
        if editingDisplay != nil {
            replyLabel.text = L(L10n.MessageAction.editingMessage)
        } else if let r = replyDisplay {
            replyLabel.text = "Replying to \(r.senderDisplayName)"
        }
    }

    private func updateReplyBannerVisibility() {
        if composerSendPermissionBlocked {
            if (replyBannerHeightConstraint?.constant ?? 0) != 0 {
                replyBannerHeightConstraint?.constant = 0
                onHeightChanged?(totalHeight)
            }
            return
        }
        let shouldShow = replyDisplay != nil || editingDisplay != nil
        let targetH: CGFloat = shouldShow ? Self.replyBannerHeight : 0
        let heightChanged = replyBannerHeightConstraint?.constant != targetH
        replyBannerView.isUserInteractionEnabled = shouldShow
        refreshBannerLabel()
        if heightChanged {
            replyBannerHeightConstraint?.constant = targetH
            onHeightChanged?(totalHeight)
        }
        layoutSuperviewForComposerChange(shouldAnimateSuperview: heightChanged, duration: 0.2)
    }

    private static func mapUTF16InDisplayToEditing(_ p: Int, endDeltas: [(end: Int, delta: Int)]) -> Int {
        var t = p
        for d in endDeltas where d.end <= t {
            t += d.delta
        }
        return t
    }

    private static func mapNSRangeFromDisplayToEditing(_ r: NSRange, endDeltas: [(end: Int, delta: Int)]) -> NSRange {
        let s0 = r.location
        let e0 = r.location + r.length
        let s1 = mapUTF16InDisplayToEditing(s0, endDeltas: endDeltas)
        let e1 = mapUTF16InDisplayToEditing(e0, endDeltas: endDeltas)
        return NSRange(location: s1, length: e1 - s1)
    }

    private static func editingComposerRestoredText(from parsed: ParsedContent) -> (String, [(end: Int, delta: Int)]) {
        var text = parsed.text
        var endDeltas: [(end: Int, delta: Int)] = []
        let md = parsed.tokens.filter { t in
            switch t.kind {
            case .inlineCode, .codeBlock, .bold, .strikethrough: return true
            default: return false
            }
        }
        .sorted { $0.start > $1.start }
        for token in md {
            guard token.start >= 0, token.end <= (text as NSString).length, token.start < token.end else { continue }
            let r = NSRange(location: token.start, length: token.end - token.start)
            let inner = (text as NSString).substring(with: r)
            let wrapped: String?
            switch token.kind {
            case .inlineCode:
                wrapped = "`" + inner + "`"
            case .codeBlock:
                wrapped = "```" + inner + "```"
            case .bold:
                wrapped = "**" + inner + "**"
            case .strikethrough:
                wrapped = "~~" + inner + "~~"
            default:
                wrapped = nil
            }
            guard let w = wrapped else { continue }
            let oldLen = r.length
            let newLen = (w as NSString).length
            let ms = NSMutableString(string: text)
            ms.replaceCharacters(in: r, with: w)
            text = ms as String
            endDeltas.append((end: token.end, delta: newLen - oldLen))
        }
        return (text, endDeltas)
    }

    private func populateComposerFromEditDisplay(_ display: ChatMessageDisplay) {
        let parsed = display.parsedContent
        activeMentions.removeAll()
        activeHashtags.removeAll()
        emojiIdByColonToken.removeAll()

        let (reconstructed, displayToEditDeltas) = Self.editingComposerRestoredText(from: parsed)
        let fullText = reconstructed
        let t = UIColor.theme
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 15.sf),
            .foregroundColor: UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        ]

        let attr = NSMutableAttributedString(string: fullText, attributes: normalAttrs)
        let sorted = parsed.tokens.sorted { $0.start < $1.start }
        let displayText = parsed.text
        let displayUTF16Count = displayText.utf16.count

        for token in sorted {
            guard token.start >= 0, token.end <= displayUTF16Count, token.start < token.end else { continue }
            let rDisplay = NSRange(location: token.start, length: token.end - token.start)
            let r = Self.mapNSRangeFromDisplayToEditing(rDisplay, endDeltas: displayToEditDeltas)
            guard r.location >= 0, r.location + r.length <= (fullText as NSString).length else { continue }
            switch token.kind {
            case .mention(let userIdStr, let roleIdStr, let username):
                attr.addAttributes(highlightAttrs, range: r)
                let raw = displayText.mezon_utf16Substring(from: token.start, to: token.end)
                let displayName: String
                if raw.hasPrefix("@") {
                    displayName = String(raw.dropFirst())
                } else {
                    displayName = raw
                }
                let uid = Int64(userIdStr ?? "") ?? 0
                let rid = Int64(roleIdStr ?? "") ?? 0
                let uname = username?.lowercased() ?? ""
                let mention: ComposerMention
                if rid != 0 {
                    mention = ComposerMention(userId: 0, roleId: rid, rolename: displayName, displayName: displayName, range: r)
                } else if uid != 0 {
                    mention = ComposerMention(userId: uid, roleId: 0, rolename: "", displayName: displayName, range: r)
                } else if uname == "here" || displayName.lowercased() == "here" {
                    mention = ComposerMention(userId: Self.mentionHereUserId, roleId: 0, rolename: "", displayName: "here", range: r)
                } else {
                    mention = ComposerMention(userId: uid, roleId: rid, rolename: "", displayName: displayName, range: r)
                }
                activeMentions.append(mention)

            case .hashtag(let channelIdStr, let clanIdStr, let parentIdStr, let channelLabel, let channelType, let channelPrivate, let ageRestricted):
                attr.addAttributes(highlightAttrs, range: r)
                let raw = displayText.mezon_utf16Substring(from: token.start, to: token.end)
                let labelFromText: String
                if raw.hasPrefix("#") {
                    labelFromText = String(raw.dropFirst())
                } else {
                    labelFromText = raw
                }
                let label = (channelLabel?.isEmpty == false ? channelLabel! : labelFromText)
                let cid = Int64(channelIdStr ?? "") ?? 0
                let gid = Int64(clanIdStr ?? "") ?? 0
                var ch: Mezon_Api_ChannelDescription?
                if cid != 0 {
                    let channels = context.engine.clanData.getAllChannelsByUser()?.channeldesc ?? []
                    ch = channels.first(where: { $0.channelID == cid && (gid == 0 || $0.clanID == gid) })
                }
                let ctype = channelType ?? ch?.type ?? MezonConstants.ChannelType.channel.rawValue
                let cpriv = channelPrivate ?? ch?.channelPrivate ?? 0
                let cage = ageRestricted ?? ch?.ageRestricted ?? 0
                let parentId = Int64(parentIdStr ?? "") ?? ch?.parentID ?? 0
                let tag = ComposerHashtag(
                    channelId: cid,
                    clanId: ch?.clanID ?? gid,
                    parentId: parentId,
                    channelLabel: label,
                    channelType: ctype,
                    channelPrivate: cpriv,
                    ageRestricted: cage,
                    range: r
                )
                activeHashtags.append(tag)

            case .emoji(let emojiId):
                attr.addAttributes(highlightAttrs, range: r)
                let raw = displayText.mezon_utf16Substring(from: token.start, to: token.end)
                if raw.count >= 2, raw.first == ":", raw.last == ":" {
                    emojiIdByColonToken[Self.normalizedEmojiToken(from: raw)] = emojiId
                } else if let idInt = Int64(emojiId), let rec = allSuggestionEmojis.first(where: { $0.id == idInt }) {
                    let key = Self.normalizedEmojiToken(from: rec.shortname)
                    emojiIdByColonToken[key] = emojiId
                }

            default:
                break
            }
        }

        textView.attributedText = attr
        refreshHashtagIconAttachments()
        text = fullText
        placeholderLabel.isHidden = !text.isEmpty
        textView.typingAttributes = normalAttrs
        textView.isScrollEnabled = false
        flushComposerHeightAfterContentMutation()
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        loadEditingRemoteAttachments(from: display)
        refreshComposerTypingAttributesForSelection()
        scheduleOgpPreviewUpdate(for: text)
    }

    private func loadEditingRemoteAttachments(from display: ChatMessageDisplay) {
        let nonUploading = display.attachments.filter { !$0.isUploading && !$0.url.isEmpty }
        let imageAttachments = nonUploading.filter { $0.isImage || $0.isVideo }
        let fileAttachments = nonUploading.filter { !$0.isImage && !$0.isVideo }
        editingRemoteImageAttachments = imageAttachments
        editingRemoteFileAttachments = fileAttachments

        let remoteImagePreviews = imageAttachments.map { att -> RemoteAttachmentPreview in
            RemoteAttachmentPreview(
                url: att.url,
                filename: att.filename,
                filetype: att.filetype,
                isVideo: att.isVideo
            )
        }
        let remoteFilePreviews = fileAttachments.map { att -> RemoteAttachmentPreview in
            RemoteAttachmentPreview(
                url: att.url,
                filename: att.filename,
                filetype: att.filetype,
                isVideo: false
            )
        }
        attachmentPreviewView.setRemoteAttachments(images: remoteImagePreviews, files: remoteFilePreviews)
        updatePreviewVisibility()
    }

    func clearText() {
        text = ""
        activeMentions.removeAll()
        activeHashtags.removeAll()
        emojiIdByColonToken.removeAll()
        hideEmojiSuggestions()
        hideMentionSuggestions()
        hideHashtagSuggestions()
        textPipe.putNext("")
        clearOgpPreview(userDismissed: false, resetDismissed: true)
        syncAttachControlsWithTypedText()
        updateSendVoiceToggle()
    }
    func updateText(_ newText: String) {
        text = newText
        textPipe.putNext(newText)
        scheduleOgpPreviewUpdate(for: newText)
    }

    func resendFailedMessage(display: ChatMessageDisplay) {
        guard display.isFailed else { return }
        let localId = display.message.id
        if AttachmentUploadCoordinator.shared.resendFailedSession(context: context, messageId: localId) {
            return
        }
        guard let record = context.account.postbox.read({ tx in tx.getMessageById(localId) }),
              record.sendingState == .failed else { return }

        context.account.postbox.write { tx in
            tx.registerResendDuplicateGuard(senderId: record.senderId, content: record.content)
            tx.markMessagePending(id: localId)
        }

        let contentStr: String = {
            guard let s = String(data: record.content, encoding: .utf8), !s.isEmpty else { return "{}" }
            return s
        }()
        let mentionList: [Mezon_Api_MessageMention] = {
            guard !record.mentionsJSON.isEmpty,
                  let list = try? Mezon_Api_MessageMentionList(serializedBytes: record.mentionsJSON) else { return [] }
            return list.mentions
        }()
        let attachments: [Mezon_Api_MessageAttachment] = {
            guard !record.attachmentsJSON.isEmpty,
                  let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: record.attachmentsJSON) else { return [] }
            return list.attachments
        }()
        let references: [Mezon_Api_MessageRef] = {
            guard !record.referencesData.isEmpty,
                  let list = try? Mezon_Api_MessageRefList(serializedBytes: record.referencesData) else { return [] }
            return list.refs
        }()
        let mode = Self.streamMode(for: channel, clanId: clanId)
        let isPublic = channel.channelPrivate == 0
        let avatar = context.currentUser?.avatarURL?.absoluteString ?? ""
        let channelIdStr = topicId != 0 ? "topic-\(topicId)" : "\(channel.channelID)"
        let fallbackClanId: String? = clanId == 0 ? nil : "\(clanId)"
        let fallbackSenderId = context.currentUser?.id ?? record.senderId

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                return
            }
            do {
                let ack = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: mentionList,
                    attachments: attachments,
                    references: references,
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: avatar,
                    topicId: self.topicId,
                    code: record.code,
                    token: token
                )
                self.context.account.postbox.write { tx in
                    guard ack.messageID != 0 else {
                        if tx.getMessageById(localId) != nil {
                            tx.markMessageFailed(id: localId)
                        }
                        return
                    }
                    let pending = tx.getMessageById(localId)
                    let attachmentsJSON: Data = {
                        guard !attachments.isEmpty else { return pending?.attachmentsJSON ?? record.attachmentsJSON }
                        var list = Mezon_Api_MessageAttachmentList()
                        list.attachments = attachments
                        return (try? list.serializedData()) ?? pending?.attachmentsJSON ?? record.attachmentsJSON
                    }()
                    let createdAt: Date = ack.createTimeSeconds > 0
                        ? Date(timeIntervalSince1970: TimeInterval(ack.createTimeSeconds))
                        : (pending?.createdAt ?? record.createdAt)
                    let editedAt: Date? = ack.updateTimeSeconds > ack.createTimeSeconds && ack.updateTimeSeconds > 0
                        ? Date(timeIntervalSince1970: TimeInterval(ack.updateTimeSeconds))
                        : nil
                    let merged = MessageRecord(
                        id: "\(ack.messageID)",
                        channelId: pending?.channelId ?? channelIdStr,
                        clanId: pending?.clanId ?? fallbackClanId,
                        senderId: pending?.senderId ?? fallbackSenderId,
                        content: pending?.content ?? record.content,
                        createdAt: createdAt,
                        editedAt: editedAt,
                        isDeleted: pending?.isDeleted ?? false,
                        code: ack.code,
                        senderDisplayName: pending?.senderDisplayName ?? record.senderDisplayName,
                        senderAvatarURL: pending?.senderAvatarURL ?? record.senderAvatarURL,
                        sendingState: .sent,
                        attachmentsJSON: attachmentsJSON,
                        reactionsJSON: pending?.reactionsJSON ?? record.reactionsJSON,
                        referencesData: pending?.referencesData ?? record.referencesData,
                        mentionsJSON: pending?.mentionsJSON ?? record.mentionsJSON
                    )
                    tx.replaceMessage(pendingId: localId, with: merged)
                }
                self.markOnboardingWelcomeMessageSentIfNeeded(ack: ack, anonymous: false)
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "resendFailedMessage",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                    "messageId": localId,
                ])
                if Self.isDefinitelyUndelivered(error) {
                    self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                } else {
                    self.scheduleAmbiguousSendFailsafe(localId: localId)
                }
            }
        }
    }

    private static func streamMode(for channel: Mezon_Api_ChannelDescription, clanId: Int64) -> Int32 {
        switch channel.type {
        case MezonConstants.ChannelType.thread.rawValue:
            return MezonConstants.ChannelStreamMode.thread.rawValue
        case MezonConstants.ChannelType.dm.rawValue:
            return MezonConstants.ChannelStreamMode.dm.rawValue
        case MezonConstants.ChannelType.group.rawValue:
            return MezonConstants.ChannelStreamMode.group.rawValue
        default:
            return clanId == 0
                ? MezonConstants.ChannelStreamMode.group.rawValue
                : MezonConstants.ChannelStreamMode.channel.rawValue
        }
    }

    private static let ambiguousSendFailsafeDelay: TimeInterval = 30
    private static let ambiguousDeliveryVerifyDelayNanoseconds: UInt64 = 2_500_000_000

    private static func isDefinitelyUndelivered(_ error: Error) -> Bool {
        if let mezon = error as? MezonError, case let .httpError(code, _) = mezon, (400..<500).contains(code) {
            return true
        }
        return !NetworkMonitor.shared.isConnected
    }

    private func scheduleAmbiguousSendFailsafe(localId: String) {
        let postbox = context.account.postbox
        scheduleAmbiguousDeliveryVerification()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ambiguousSendFailsafeDelay) {
            let record = postbox.read { tx in tx.getMessageById(localId) }
            guard let record, record.id == localId, record.sendingState == .pending else { return }
            postbox.write { tx in
                if tx.reconcilePendingWithServerTwin(pendingId: localId) { return }
                tx.markMessageFailed(id: localId)
            }
        }
    }

    private func scheduleAmbiguousDeliveryVerification() {
        ambiguousDeliveryVerifyTask?.cancel()
        let clanId = self.clanId
        let channelId = self.channel.channelID
        let topicId = self.topicId
        ambiguousDeliveryVerifyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.ambiguousDeliveryVerifyDelayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            await self.verifyAmbiguousPendingDelivery(clanId: clanId, channelId: channelId, topicId: topicId)
        }
    }

    private func verifyAmbiguousPendingDelivery(clanId: Int64, channelId: Int64, topicId: Int64) async {
        let postbox = context.account.postbox
        let storageChannelId = topicId != 0 ? "topic-\(topicId)" : "\(channelId)"
        let hasStuckPending = postbox.read { tx in
            tx.getMessages(channelId: storageChannelId).contains {
                $0.id.hasPrefix("pending-") && $0.sendingState == .pending
            }
        }
        guard hasStuckPending else { return }
        guard let token = await context.getToken() else { return }
        do {
            let response = try await context.account.network.listChannelMessages(
                clanId: clanId,
                channelId: channelId,
                messageId: 0,
                direction: 2,
                limit: 30,
                topicId: topicId,
                token: token
            )
            guard !response.messages.isEmpty else { return }
            postbox.write { tx in
                for api in response.messages {
                    let existing = tx.getMessageById("\(api.messageID)", channelId: storageChannelId)
                    tx.addMessages([MessageRecord.fromApi(api, merging: existing)])
                }
            }
        } catch {
        }
    }

    private static let deliveryConfirmDelayNanoseconds: UInt64 = 5_000_000_000

    private func registerDeliveryConfirmation(serverMessageId: String) {
        guard !serverMessageId.isEmpty, serverMessageId != "0" else { return }
        pendingDeliveryConfirmations[serverMessageId] = Date()
        scheduleDeliveryConfirmation()
    }

    private func scheduleDeliveryConfirmation() {
        deliveryConfirmTask?.cancel()
        let clanId = self.clanId
        let channelId = self.channel.channelID
        let topicId = self.topicId
        deliveryConfirmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.deliveryConfirmDelayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            await self.confirmPendingDeliveries(clanId: clanId, channelId: channelId, topicId: topicId)
        }
    }

    private func confirmPendingDeliveries(clanId: Int64, channelId: Int64, topicId: Int64) async {
        let due = pendingDeliveryConfirmations
        guard !due.isEmpty else { return }
        pendingDeliveryConfirmations.removeAll()

        let unconfirmed = due.keys.filter { !MessageEchoRegistry.shared.hasEcho(messageId: $0) }
        guard !unconfirmed.isEmpty else { return }

        let postbox = context.account.postbox
        let storageChannelId = topicId != 0 ? "topic-\(topicId)" : "\(channelId)"
        guard let token = await context.getToken() else { return }
        do {
            let response = try await context.account.network.listChannelMessages(
                clanId: clanId,
                channelId: channelId,
                messageId: 0,
                direction: 2,
                limit: 50,
                topicId: topicId,
                token: token
            )
            guard !response.messages.isEmpty else { return }
            let serverIds = Set(response.messages.map { "\($0.messageID)" })
            postbox.write { tx in
                for api in response.messages {
                    let existing = tx.getMessageById("\(api.messageID)", channelId: storageChannelId)
                    tx.addMessages([MessageRecord.fromApi(api, merging: existing)])
                }
                for id in unconfirmed where !serverIds.contains(id) {
                    guard let record = tx.getMessageById(id, channelId: storageChannelId),
                          record.sendingState == .sent else { continue }
                    tx.markMessageFailed(id: id)
                }
            }
        } catch {
        }
    }

    func focusTextInput() {
        guard !composerSendPermissionBlocked else { return }
        textView.becomeFirstResponder()
    }

    var isTextInputFocused: Bool {
        textView.isFirstResponder
    }

    func refocusTextInputAfterNavigation() {
        guard !composerSendPermissionBlocked, !isVoiceRecordingActive else { return }
        guard textView.isFirstResponder else { return }
        textView.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            self.textView.becomeFirstResponder()
        }
    }

    private func openPhotoPicker() {
        guard !isEditingShareContactMessage else { return }
        let remaining = remainingAttachmentSlots
        guard remaining > 0 else {
            notifyAttachmentLimitReached()
            return
        }
        MediaPickerViewController.present(
            from: self,
            selectionLimit: remaining,
            onEditedSend: { [weak self] result in
                self?.sendEditedImageImmediately(result)
            }
        ) { [weak self] results in
            guard let self else { return }
            for result in results.prefix(self.remainingAttachmentSlots) {
                let index = self.pickedImages.count
                self.pickedImages.append(result.image)
                if result.isVideo {
                    self.attachmentPreviewView.addVideo(thumbnail: result.image)
                } else {
                    self.attachmentPreviewView.addImage(result.image)
                }
                if let fileURL = result.fileURL {
                    self.pickedFileURLs[index] = fileURL
                }
            }
            self.saveToCache()
            self.updatePreviewVisibility()
        }
    }

    private func sendEditedImageImmediately(_ result: MediaPickerResult) {
        guard !composerSendPermissionBlocked, !result.isVideo else { return }
        ensureChannelMetadataResolvedFromPostboxIfNeeded()
        let text = buildPlainTextFromAttributed().trimmingCharacters(in: .whitespacesAndNewlines)
        let editingId = editingDisplay.flatMap { Int64($0.message.id) } ?? 0
        let urls = result.fileURL.map { [0: $0] } ?? [:]
        sendChannelMessage(
            text: text,
            images: [result.image],
            clanId: clanId,
            channel: channel,
            editingMessageId: editingId,
            fileURLsOverride: urls,
            filesOverride: [],
            preserveComposerAttachmentsOnReset: editingId == 0
        )
    }

    func openFilePicker() {
        guard !isEditingShareContactMessage else { return }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        }
        picker.allowsMultipleSelection = true
        picker.delegate = self

        var presenter: UIViewController = self
        if let parent = self.parent {
            presenter = parent
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(picker, animated: true)
    }

    private func toggleEmojiPicker() {
        isEmojiPickerVisible.toggle()

        if isEmojiPickerVisible {
            if isAdvancePanelVisible {
                isAdvancePanelVisible = false
                onToggleAdvancePanel?(false, 0)
                let advIconConfig = UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)
                advanceButton.setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: advIconConfig), for: .normal)
            }
            hideEmojiSuggestions()
            hideHashtagSuggestions()
            let collapsedH = max(lastKeyboardHeight, 260)
            onToggleEmojiPicker?(true, collapsedH)
            textView.resignFirstResponder()
        } else {
            onToggleEmojiPicker?(false, 0)
            DispatchQueue.main.async { [weak self] in
                self?.textView.becomeFirstResponder()
            }
        }

        emojiButton.setImage(
            Self.composerEmojiToolbarIcon(showKeyboard: isEmojiPickerVisible, pointSize: 18.sf),
            for: .normal
        )
    }

    private func toggleAdvancePanel() {
        guard !isEditingShareContactMessage else { return }
        isAdvancePanelVisible.toggle()

        if isAdvancePanelVisible {
            if isEmojiPickerVisible {
                isEmojiPickerVisible = false
                onToggleEmojiPicker?(false, 0)
                emojiButton.setImage(Self.composerEmojiFaceIcon(pointSize: 18.sf), for: .normal)
            }
            hideEmojiSuggestions()
            hideHashtagSuggestions()
            textView.resignFirstResponder()
            let collapsedH = max(lastKeyboardHeight, 260)
            onToggleAdvancePanel?(true, collapsedH)
        } else {
            onToggleAdvancePanel?(false, 0)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isVoiceRecordingActive else { return }
                self.textView.becomeFirstResponder()
            }
        }

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)
        let iconName = isAdvancePanelVisible ? "xmark" : "line.3.horizontal"
        advanceButton.setImage(UIImage(systemName: iconName, withConfiguration: iconConfig), for: .normal)
    }

    func hideAdvancePanelIfNeeded() {
        guard isAdvancePanelVisible else { return }
        markAdvancePanelDismissedByHost()
        onToggleAdvancePanel?(false, 0)
    }

    func markAdvancePanelDismissedByHost() {
        isAdvancePanelVisible = false
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)
        advanceButton.setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: iconConfig), for: .normal)
    }


    private static func normalizedEmojiToken(from shortname: String) -> String {
        let inner = shortname.split(separator: ":").joined()
        guard !inner.isEmpty else { return "::" }
        return ":\(inner):"
    }

    func insertEmoji(_ emojiId: String, shortname: String) {
        guard !isVoiceRecordingActive else { return }
        applyEmojiInsertion(emojiId: emojiId, shortname: shortname, replaceRange: textView.selectedRange)
    }

    func focusComposerAfterEmojiPanelSelection() {
        guard !isVoiceRecordingActive else { return }
        DispatchQueue.main.async { [weak self] in
            self?.textView.becomeFirstResponder()
        }
    }


    private func applyEmojiInsertion(emojiId: String, shortname: String, replaceRange: NSRange) {
        guard !isVoiceRecordingActive else { return }
        let token = Self.normalizedEmojiToken(from: shortname)
        emojiIdByColonToken[token] = emojiId

        let nsBase = (textView.text ?? "") as NSString
        var leadingSpace = ""
        if replaceRange.length == 0, replaceRange.location > 0 {
            let prev = replaceRange.location - 1
            if prev < nsBase.length {
                let ch = nsBase.substring(with: NSRange(location: prev, length: 1))
                if ch != " " && ch != "\n" && ch != "\r" && ch != "\t" {
                    leadingSpace = " "
                }
            }
        }

        let trailingSpace = " "
        let insertPlain = leadingSpace + token + trailingSpace
        let insertLen = (insertPlain as NSString).length

        let t = UIColor.theme
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
        let emojiAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 15.sf),
            .foregroundColor: UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        ]

        let attrText = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
        let emojiAttrStr = NSMutableAttributedString()
        if !leadingSpace.isEmpty {
            emojiAttrStr.append(NSAttributedString(string: leadingSpace, attributes: normalAttrs))
        }
        emojiAttrStr.append(NSAttributedString(string: token, attributes: emojiAttrs))
        emojiAttrStr.append(NSAttributedString(string: trailingSpace, attributes: normalAttrs))
        attrText.replaceCharacters(in: replaceRange, with: emojiAttrStr)
        textView.attributedText = attrText

        let lengthDelta = insertLen - replaceRange.length
        activeMentions = activeMentions.map { m in
            if m.range.location >= replaceRange.location + replaceRange.length {
                return ComposerMention(
                    userId: m.userId,
                    roleId: m.roleId,
                    rolename: m.rolename,
                    displayName: m.displayName,
                    range: NSRange(location: m.range.location + lengthDelta, length: m.range.length)
                )
            }
            return m
        }
        activeHashtags = activeHashtags.map { h in
            if h.range.location >= replaceRange.location + replaceRange.length {
                return ComposerHashtag(
                    channelId: h.channelId,
                    clanId: h.clanId,
                    parentId: h.parentId,
                    channelLabel: h.channelLabel,
                    channelType: h.channelType,
                    channelPrivate: h.channelPrivate,
                    ageRestricted: h.ageRestricted,
                    range: NSRange(location: h.range.location + lengthDelta, length: h.range.length)
                )
            }
            return h
        }

        let newCursor = replaceRange.location + insertLen
        textView.selectedRange = NSRange(location: newCursor, length: 0)
        textView.typingAttributes = normalAttrs

        text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        updateTextViewHeight()
        updateInlineSuggestions()
        updateSendVoiceToggle()
        syncAttachControlsWithTypedText()
        hideEmojiSuggestions()
        refreshComposerTypingAttributesForSelection()
    }

    private func insertEmojiFromSuggestion(_ emoji: CachedClanEmojiRecord) {
        guard !isVoiceRecordingActive else { return }
        guard let ctx = detectEmojiColonContext() else { return }
        let full = (textView.text ?? "") as NSString
        let len = full.length
        let sel = textView.selectedRange
        let cursor = min(sel.location + sel.length, len)
        guard ctx.colonUTF16 >= 0, cursor >= ctx.colonUTF16 else { return }
        let replaceRange = NSRange(location: ctx.colonUTF16, length: cursor - ctx.colonUTF16)
        applyEmojiInsertion(emojiId: "\(emoji.id)", shortname: emoji.shortname, replaceRange: replaceRange)
    }

    func hideEmojiPickerIfNeeded() {
        guard isEmojiPickerVisible else { return }
        isEmojiPickerVisible = false
        onToggleEmojiPicker?(false, 0)
        emojiButton.setImage(Self.composerEmojiFaceIcon(pointSize: 18.sf), for: .normal)
    }

    private func addPickedImage(_ image: UIImage) {
        guard !isEditingShareContactMessage else { return }
        guard remainingAttachmentSlots > 0 else {
            notifyAttachmentLimitReached()
            return
        }
        pickedImages.append(image)
        attachmentPreviewView.addImage(image)
        saveToCache()
        updatePreviewVisibility()
    }

    private static let pastePreservedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

    private func handlePastedImages(_ pasted: [PastedImage]) {
        guard !isEditingShareContactMessage else { return }
        let tempDir = FileManager.default.temporaryDirectory
        var didHitLimit = false
        for item in pasted {
            guard remainingAttachmentSlots > 0 else { didHitLimit = true; break }
            let resolvedData: Data
            let resolvedExt: String
            if let originalData = item.data,
               let originalExt = item.fileExtension,
               Self.pastePreservedImageExtensions.contains(originalExt.lowercased()) {
                resolvedData = originalData
                resolvedExt = originalExt
            } else if let jpegData = item.image.jpegData(compressionQuality: 0.9) {
                resolvedData = jpegData
                resolvedExt = "jpg"
            } else {
                continue
            }
            let filename = "pasted-\(UUID().uuidString).\(resolvedExt)"
            let fileURL = tempDir.appendingPathComponent(filename)
            do {
                try resolvedData.write(to: fileURL)
            } catch {
                continue
            }
            let index = pickedImages.count
            pickedImages.append(item.image)
            attachmentPreviewView.addImage(item.image)
            pickedFileURLs[index] = fileURL
        }
        if didHitLimit { notifyAttachmentLimitReached() }
        saveToCache()
        updatePreviewVisibility()
    }

    private func handlePastedGIF(_ data: Data) {
        guard !isEditingShareContactMessage else { return }
        guard remainingAttachmentSlots > 0 else {
            notifyAttachmentLimitReached()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "pasted-\(UUID().uuidString).gif"
        let fileURL = tempDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
        } catch {
            return
        }
        guard let image = UIImage(data: data) else { return }
        let index = pickedImages.count
        pickedImages.append(image)
        attachmentPreviewView.addImage(image)
        pickedFileURLs[index] = fileURL
        saveToCache()
        updatePreviewVisibility()
    }

    private func convertPastedTextToFileIfTooLong(_ pasted: String) -> Bool {
        guard !isEditingShareContactMessage, editingDisplay == nil else { return false }

        if Data(pasted.utf8).count > Self.maxMessageContentBytes {
            return convertTextToPlainTextAttachment(pasted)
        }

        let combined = buildPlainTextFromAttributed() + pasted
        guard Data(combined.utf8).count > Self.maxMessageContentBytes else { return false }
        guard convertTextToPlainTextAttachment(combined) else { return false }
        clearComposerTextAfterFileConversion()
        return true
    }

    @discardableResult
    private func convertTextToPlainTextAttachment(_ content: String) -> Bool {
        guard remainingAttachmentSlots > 0 else {
            notifyAttachmentLimitReached()
            return false
        }
        let data = Data(content.utf8)
        let filename = "\(Int(Date().timeIntervalSince1970 * 1000)).txt"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mezon-uploads", isDirectory: true)
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL)
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "SendMessageInputViewController.convertTextToPlainTextAttachment",
                "bytes": "\(data.count)",
            ])
            return false
        }
        let info = PickedFileInfo(url: fileURL, filename: filename, filesize: data.count, filetype: "text/plain")
        pickedFiles.append(info)
        attachmentPreviewView.addFile(info)
        updatePreviewVisibility()
        return true
    }

    private func clearComposerTextAfterFileConversion() {
        activeMentions.removeAll()
        activeHashtags.removeAll()
        emojiIdByColonToken.removeAll()
        textView.attributedText = nil
        textView.text = ""
        text = ""
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.theme.textStrong
        ]
        placeholderLabel.isHidden = false
        textView.isScrollEnabled = false
        resetTextViewHeight()
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        clearOgpPreview(userDismissed: false, resetDismissed: true)
        textPipe.putNext("")
        syncAttachControlsWithTypedText()
        updateSendVoiceToggle()
    }

    private func removeAttachment(at index: Int) {
        let remoteImageCount = editingRemoteImageAttachments.count
        let localImageCount = pickedImages.count
        let remoteFileCount = editingRemoteFileAttachments.count

        var i = index
        if i < remoteImageCount {
            editingRemoteImageAttachments.remove(at: i)
            attachmentPreviewView.removeRemoteImage(at: i)
            updatePreviewVisibility()
            return
        }
        i -= remoteImageCount
        if i < localImageCount {
            removePickedImage(at: i)
            return
        }
        i -= localImageCount
        if i < remoteFileCount {
            editingRemoteFileAttachments.remove(at: i)
            attachmentPreviewView.removeRemoteFile(at: i)
            updatePreviewVisibility()
            return
        }
        i -= remoteFileCount
        removePickedFile(at: i)
    }

    private func removePickedImage(at index: Int) {
        guard index >= 0, index < pickedImages.count else { return }
        pickedImages.remove(at: index)
        attachmentPreviewView.removeImage(at: index)

        if let fileURL = pickedFileURLs[index] {
            try? FileManager.default.removeItem(at: fileURL)
        }
        var newFileURLs: [Int: URL] = [:]
        for (key, url) in pickedFileURLs where key != index {
            newFileURLs[key > index ? key - 1 : key] = url
        }
        pickedFileURLs = newFileURLs

        saveToCache()
        updatePreviewVisibility()
    }

    private func removePickedFile(at index: Int) {
        guard index >= 0, index < pickedFiles.count else { return }
        let file = pickedFiles.remove(at: index)
        attachmentPreviewView.removeFile(at: index)
        try? FileManager.default.removeItem(at: file.url)
        updatePreviewVisibility()
    }

    func clearPickedImages() {
        pickedImages.removeAll()
        pickedFileURLs.removeAll()
        pickedFiles.removeAll()
        editingRemoteImageAttachments.removeAll()
        editingRemoteFileAttachments.removeAll()
        attachmentPreviewView.removeAll()
        Self.channelAttachmentCache.removeValue(forKey: cacheKey)
        updatePreviewVisibility()
    }

    private func saveToCache() {
        if pickedImages.isEmpty {
            Self.channelAttachmentCache.removeValue(forKey: cacheKey)
        } else {
            Self.channelAttachmentCache[cacheKey] = (pickedImages, pickedFileURLs)
        }
    }

    private func restoreFromCache() {
        guard let (images, urls) = Self.channelAttachmentCache[cacheKey], !images.isEmpty else { return }
        pickedImages = images
        pickedFileURLs = urls.filter { FileManager.default.fileExists(atPath: $0.value.path) }
        attachmentPreviewView.setImages(images)
        let targetH = AttachmentPreviewView.preferredHeight(
            imageCount: pickedImages.count, fileCount: pickedFiles.count)
        previewHeightConstraint?.constant = targetH
        onHeightChanged?(totalHeight)
        view.layoutIfNeeded()
        syncAttachControlsWithTypedText()
    }

    private func updatePreviewVisibility() {
        if composerSendPermissionBlocked {
            if (previewHeightConstraint?.constant ?? 0) != 0 {
                previewHeightConstraint?.constant = 0
                onHeightChanged?(totalHeight)
            }
            return
        }
        let shouldShow = attachmentPreviewView.hasAnyAttachment
        attachmentPreviewView.isUserInteractionEnabled = shouldShow
        let targetH = shouldShow ? attachmentPreviewView.preferredPreviewHeight : 0
        let heightChanged = previewHeightConstraint?.constant != targetH
        if heightChanged {
            previewHeightConstraint?.constant = targetH
            onHeightChanged?(totalHeight)
        }
        layoutSuperviewForComposerChange(shouldAnimateSuperview: heightChanged, duration: 0.25) { _ in
            self.attachmentPreviewView.forceReload()
        }
        updateSendVoiceToggle()
        syncAttachControlsWithTypedText()
    }

    private func setOgpPreviewItem(_ item: OgpPreviewItem?) {
        guard activeOgpPreviewItem != item else { return }
        activeOgpPreviewItem = item
        if let item {
            ogpPreviewView.configure(item)
        } else {
            ogpPreviewView.clear()
        }
        updateOgpPreviewVisibility()
    }

    private func updateOgpPreviewVisibility() {
        let shouldShow = !composerSendPermissionBlocked && activeOgpPreviewItem != nil
        let targetH: CGFloat = shouldShow ? OgpPreviewView.preferredHeight : 0
        let heightChanged = ogpPreviewHeightConstraint?.constant != targetH
        ogpPreviewView.isHidden = !shouldShow
        ogpPreviewView.isUserInteractionEnabled = shouldShow
        if heightChanged {
            ogpPreviewHeightConstraint?.constant = targetH
            onHeightChanged?(totalHeight)
        }
        layoutSuperviewForComposerChange(shouldAnimateSuperview: heightChanged, duration: 0.25)
    }

    private func clearOgpPreview(userDismissed: Bool, resetDismissed: Bool) {
        if userDismissed {
            if let item = activeOgpPreviewItem {
                dismissedOgpLink = item.url
            } else if !ogpRequestedKey.isEmpty {
                dismissedOgpLink = ogpRequestedKey.components(separatedBy: "\n").first ?? ""
            }
        } else if resetDismissed {
            dismissedOgpLink = ""
        }
        ogpFetchTask?.cancel()
        ogpFetchTask = nil
        ogpRequestedKey = ""
        setOgpPreviewItem(nil)
    }

    private func scheduleOgpPreviewUpdate(for rawText: String) {
        guard !composerSendPermissionBlocked else {
            clearOgpPreview(userDismissed: false, resetDismissed: false)
            return
        }
        guard !isEditingShareContactMessage else {
            clearOgpPreview(userDismissed: false, resetDismissed: false)
            return
        }
        let candidates = OgpPreviewService.fetchableCandidates(in: rawText)
        guard !candidates.isEmpty else {
            clearOgpPreview(userDismissed: false, resetDismissed: true)
            return
        }
        if let active = activeOgpPreviewItem, rawText.contains(active.url) {
            return
        }
        if !dismissedOgpLink.isEmpty, rawText.contains(dismissedOgpLink) {
            ogpFetchTask?.cancel()
            ogpFetchTask = nil
            ogpRequestedKey = ""
            setOgpPreviewItem(nil)
            return
        }

        let requestKey = candidates.map(\.url).joined(separator: "\n")
        guard requestKey != ogpRequestedKey else { return }
        ogpFetchTask?.cancel()
        ogpRequestedKey = requestKey
        setOgpPreviewItem(nil)

        ogpFetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            for candidate in candidates {
                guard !Task.isCancelled else { return }
                guard let item = try? await OgpPreviewService.fetch(link: candidate) else { continue }
                await MainActor.run { [weak self] in
                    guard let self, self.ogpRequestedKey == requestKey, self.text.contains(item.url) else { return }
                    self.ogpRequestedKey = ""
                    self.setOgpPreviewItem(item)
                }
                return
            }

            await MainActor.run { [weak self] in
                guard let self, self.ogpRequestedKey == requestKey else { return }
                self.ogpRequestedKey = ""
                self.setOgpPreviewItem(nil)
            }
        }
    }

    private func syncAttachControlsWithTypedText() {
        if isEditingShareContactMessage {
            if !isAttachControlCollapsed {
                collapseAttachControls()
            }
            return
        }
        if alwaysShowAttachToolbarWhileTyping {
            if isAttachControlCollapsed {
                expandAttachControls()
            }
            return
        }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            if !isAttachControlCollapsed {
                collapseAttachControls()
            }
        } else {
            expandAttachControls()
        }
    }

    private func setupUI() {
        replyBannerView.addSubview(replyLabel)
        replyBannerView.addSubview(replyCancelButton)
        view.addSubview(replyBannerView)

        attachmentPreviewView.isUserInteractionEnabled = false
        ogpPreviewView.isUserInteractionEnabled = false
        replyBannerView.isUserInteractionEnabled = false
        view.addSubview(attachmentPreviewView)
        view.addSubview(ogpPreviewView)
        view.addSubview(inputBarView)
        inputBarView.addSubview(topSeparator)
        inputBarView.addSubview(chevronButton)
        inputBarView.addSubview(attachButton)
        inputBarView.addSubview(advanceButton)
        inputBarView.addSubview(textView)
        inputBarView.addSubview(placeholderLabel)
        inputBarView.addSubview(emojiButton)
        inputBarView.addSubview(voiceButton)
        inputBarView.addSubview(sendButton)
        inputBarView.addSubview(anonymousIndicatorButton)

        let bottomConstraint = inputBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint

        let btnSize: CGFloat = 40.swh
        let sendBtnSize: CGFloat = 40.swh

        let tvHeight = textView.heightAnchor.constraint(equalToConstant: Self.textViewMinHeight)
        textViewHeightConstraint = tvHeight

        let barHeight = inputBarView.heightAnchor.constraint(equalToConstant: Self.textViewMinHeight + Self.inputBarPadding)
        inputBarHeightConstraint = barHeight

        let replyH = replyBannerView.heightAnchor.constraint(equalToConstant: 0)
        replyBannerHeightConstraint = replyH

        NSLayoutConstraint.activate([
            replyBannerView.topAnchor.constraint(equalTo: view.topAnchor),
            replyBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replyBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyH,

            replyCancelButton.leadingAnchor.constraint(equalTo: replyBannerView.leadingAnchor, constant: 12),
            replyCancelButton.centerYAnchor.constraint(equalTo: replyBannerView.centerYAnchor),
            replyCancelButton.widthAnchor.constraint(equalToConstant: 24),
            replyCancelButton.heightAnchor.constraint(equalToConstant: 24),

            replyLabel.leadingAnchor.constraint(equalTo: replyCancelButton.trailingAnchor, constant: 8),
            replyLabel.trailingAnchor.constraint(equalTo: replyBannerView.trailingAnchor, constant: -12),
            replyLabel.centerYAnchor.constraint(equalTo: replyBannerView.centerYAnchor),


            attachmentPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            attachmentPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            attachmentPreviewView.topAnchor.constraint(equalTo: replyBannerView.bottomAnchor),

            ogpPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ogpPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ogpPreviewView.topAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor),

            inputBarView.topAnchor.constraint(equalTo: ogpPreviewView.bottomAnchor),
            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight,

            topSeparator.topAnchor.constraint(equalTo: inputBarView.topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 0.5),
            bottomConstraint,

            chevronButton.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 4.sw),
            chevronButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            chevronButton.heightAnchor.constraint(equalToConstant: btnSize),

            attachButton.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: 4.sw),
            attachButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            attachButton.heightAnchor.constraint(equalToConstant: btnSize),

            advanceButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4.sw),
            advanceButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            advanceButton.heightAnchor.constraint(equalToConstant: btnSize),

            textView.leadingAnchor.constraint(equalTo: advanceButton.trailingAnchor, constant: 4.sw),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6.sw),
            textView.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            tvHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),

            emojiButton.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -8.sw),
            emojiButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -6),
            emojiButton.widthAnchor.constraint(equalToConstant: 28.swh),
            emojiButton.heightAnchor.constraint(equalToConstant: 28.swh),

            anonymousIndicatorButton.widthAnchor.constraint(equalToConstant: 24),
            anonymousIndicatorButton.heightAnchor.constraint(equalToConstant: 24),
            anonymousIndicatorButton.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 4.sw),
            anonymousIndicatorButton.topAnchor.constraint(equalTo: textView.topAnchor, constant: -15),

            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -4.sw),
            sendButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: sendBtnSize),
            sendButton.heightAnchor.constraint(equalToConstant: sendBtnSize),

            voiceButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -4.sw),
            voiceButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            voiceButton.widthAnchor.constraint(equalToConstant: btnSize),
            voiceButton.heightAnchor.constraint(equalToConstant: btnSize),
        ])

        let phc = attachmentPreviewView.heightAnchor.constraint(equalToConstant: 0)
        phc.isActive = true
        previewHeightConstraint = phc

        let ogpH = ogpPreviewView.heightAnchor.constraint(equalToConstant: 0)
        ogpH.isActive = true
        ogpPreviewHeightConstraint = ogpH

        let chevW = chevronButton.widthAnchor.constraint(equalToConstant: 0)
        chevronButtonWidthConstraint = chevW
        chevW.isActive = true
        chevronButton.alpha = 0

        let attW = attachButton.widthAnchor.constraint(equalToConstant: btnSize)
        attachButtonWidthConstraint = attW
        attW.isActive = true

        let advW = advanceButton.widthAnchor.constraint(equalToConstant: btnSize)
        advanceButtonWidthConstraint = advW
        advW.isActive = true
        if hidesAdvanceComposerButton {
            advanceButtonWidthConstraint?.constant = 0
            advanceButton.alpha = 0
            advanceButton.isHidden = true
            advanceButton.isUserInteractionEnabled = false
        }

        voiceRecordingOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(voiceRecordingOverlay)
        view.insertSubview(voiceRecordingOverlay, aboveSubview: inputBarView)
        NSLayoutConstraint.activate([
            voiceRecordingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            voiceRecordingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            voiceRecordingOverlay.topAnchor.constraint(equalTo: inputBarView.topAnchor),
            voiceRecordingOverlay.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor),
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.allowableMovement = 2000
        longPress.cancelsTouchesInView = false
        voiceButton.addGestureRecognizer(longPress)
        voiceLongPressGesture = longPress

        let tapHint = UITapGestureRecognizer(target: self, action: #selector(handleVoiceTapForHint))
        tapHint.require(toFail: longPress)
        voiceButton.addGestureRecognizer(tapHint)

        inputBarView.bringSubviewToFront(anonymousIndicatorButton)

        view.addSubview(sendPermissionRestrictedChrome)
        sendPermissionRestrictedChrome.addSubview(sendPermissionRestrictedTopSep)
        sendPermissionRestrictedChrome.addSubview(sendPermissionRestrictedInner)
        sendPermissionRestrictedInner.addSubview(sendPermissionRestrictedLabel)
        NSLayoutConstraint.activate([
            sendPermissionRestrictedChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sendPermissionRestrictedChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sendPermissionRestrictedChrome.topAnchor.constraint(equalTo: ogpPreviewView.bottomAnchor),
            sendPermissionRestrictedChrome.heightAnchor.constraint(equalToConstant: Self.textViewMinHeight + Self.inputBarPadding),
            sendPermissionRestrictedChrome.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor),

            sendPermissionRestrictedTopSep.topAnchor.constraint(equalTo: sendPermissionRestrictedChrome.topAnchor),
            sendPermissionRestrictedTopSep.leadingAnchor.constraint(equalTo: sendPermissionRestrictedChrome.leadingAnchor),
            sendPermissionRestrictedTopSep.trailingAnchor.constraint(equalTo: sendPermissionRestrictedChrome.trailingAnchor),
            sendPermissionRestrictedTopSep.heightAnchor.constraint(equalToConstant: 0.5),

            sendPermissionRestrictedInner.topAnchor.constraint(equalTo: sendPermissionRestrictedTopSep.bottomAnchor),
            sendPermissionRestrictedInner.leadingAnchor.constraint(equalTo: sendPermissionRestrictedChrome.leadingAnchor, constant: 12.sw),
            sendPermissionRestrictedInner.trailingAnchor.constraint(equalTo: sendPermissionRestrictedChrome.trailingAnchor, constant: -12.sw),
            sendPermissionRestrictedInner.bottomAnchor.constraint(equalTo: sendPermissionRestrictedChrome.bottomAnchor, constant: -8),

            sendPermissionRestrictedLabel.centerYAnchor.constraint(equalTo: sendPermissionRestrictedInner.centerYAnchor),
            sendPermissionRestrictedLabel.leadingAnchor.constraint(equalTo: sendPermissionRestrictedInner.leadingAnchor, constant: 10),
            sendPermissionRestrictedLabel.trailingAnchor.constraint(equalTo: sendPermissionRestrictedInner.trailingAnchor, constant: -10),
        ])
        view.insertSubview(sendPermissionRestrictedChrome, aboveSubview: inputBarView)
    }

    private func collapseAttachControls() {
        guard !isAttachControlCollapsed else { return }
        isAttachControlCollapsed = true
        let btnSize: CGFloat = 40.swh

        chevronButtonWidthConstraint?.constant = btnSize
        attachButtonWidthConstraint?.constant = 0
        advanceButtonWidthConstraint?.constant = 0

        UIView.performWithoutAnimation {
            self.chevronButton.alpha = 1
            self.chevronButton.transform = .identity
            self.attachButton.alpha = 0
            self.advanceButton.alpha = 0
            self.attachButton.transform = .identity
            self.advanceButton.transform = .identity
            self.inputBarView.layoutIfNeeded()
        }
    }

    private func expandAttachControls() {
        guard isAttachControlCollapsed else { return }
        isAttachControlCollapsed = false
        let btnSize: CGFloat = 40.swh

        chevronButtonWidthConstraint?.constant = 0
        attachButtonWidthConstraint?.constant = btnSize
        advanceButtonWidthConstraint?.constant = hidesAdvanceComposerButton ? 0 : btnSize

        UIView.performWithoutAnimation {
            self.chevronButton.alpha = 0
            self.chevronButton.transform = .identity
            self.attachButton.alpha = 1
            self.attachButton.transform = .identity
            if self.hidesAdvanceComposerButton {
                self.advanceButton.alpha = 0
                self.advanceButton.isHidden = true
                self.advanceButton.transform = .identity
            } else {
                self.advanceButton.alpha = 1
                self.advanceButton.isHidden = false
                self.advanceButton.transform = .identity
            }
            self.inputBarView.layoutIfNeeded()
        }
    }

    private func updateSendVoiceToggle() {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pickedImages.isEmpty || !pickedFiles.isEmpty
        let isEditingHoldingMedia = (editingDisplay != nil) && (!editingRemoteImageAttachments.isEmpty || !editingRemoteFileAttachments.isEmpty)
        let shouldShowSend = hasContent || isEditingHoldingMedia || isEditingShareContactMessage

        guard sendButton.isHidden == shouldShowSend else { return }

        sendButton.layer.removeAllAnimations()
        voiceButton.layer.removeAllAnimations()

        if shouldShowSend {
            sendButton.isHidden = false
            UIView.animate(withDuration: 0.15) {
                self.sendButton.alpha = 1
                self.voiceButton.alpha = 0
            } completion: { finished in
                guard finished else { return }
                self.voiceButton.isHidden = true
            }
        } else {
            voiceButton.isHidden = false
            UIView.animate(withDuration: 0.15) {
                self.sendButton.alpha = 0
                self.voiceButton.alpha = 1
            } completion: { finished in
                guard finished else { return }
                self.sendButton.isHidden = true
            }
        }
    }

    private func setupMentionSuggestion() {
        let sv = MentionSuggestionView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isHidden = true
        sv.onSelectItem = { [weak self] item in
            self?.insertMention(item: item)
        }
        view.insertSubview(sv, at: 0)

        let hc = sv.heightAnchor.constraint(equalToConstant: 0)
        mentionSuggestionHeightConstraint = hc
        let leading = sv.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trailing = sv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let bottom = sv.bottomAnchor.constraint(equalTo: inputBarView.topAnchor)
        mentionComposerConstraints = [leading, trailing, bottom, hc]
        NSLayoutConstraint.activate(mentionComposerConstraints)
        mentionSuggestionView = sv
    }

    private func setupEmojiSuggestion() {
        let ev = EmojiSuggestionView()
        ev.translatesAutoresizingMaskIntoConstraints = false
        ev.isHidden = true
        ev.onSelectEmoji = { [weak self] emoji in
            self?.insertEmojiFromSuggestion(emoji)
        }
        view.insertSubview(ev, at: 0)

        let hc = ev.heightAnchor.constraint(equalToConstant: 0)
        emojiSuggestionHeightConstraint = hc
        let leading = ev.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trailing = ev.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let bottom = ev.bottomAnchor.constraint(equalTo: inputBarView.topAnchor)
        emojiComposerConstraints = [leading, trailing, bottom, hc]
        NSLayoutConstraint.activate(emojiComposerConstraints)
        emojiSuggestionView = ev
    }

    private func setupHashtagSuggestion() {
        let hv = HashtagSuggestionView()
        hv.translatesAutoresizingMaskIntoConstraints = false
        hv.isHidden = true
        hv.onSelectChannel = { [weak self] ch in
            self?.insertHashtag(channel: ch)
        }
        view.insertSubview(hv, at: 0)

        let hc = hv.heightAnchor.constraint(equalToConstant: 0)
        hashtagSuggestionHeightConstraint = hc
        let leading = hv.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trailing = hv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let bottom = hv.bottomAnchor.constraint(equalTo: inputBarView.topAnchor)
        hashtagComposerConstraints = [leading, trailing, bottom, hc]
        NSLayoutConstraint.activate(hashtagComposerConstraints)
        hashtagSuggestionView = hv
    }

    private func reloadHashtagChannelCandidates() {
        guard includeHashtagSuggestions else {
            allHashtagChannelCandidates = []
            return
        }
        if channel.type == MezonConstants.ChannelType.dm.rawValue {
            allHashtagChannelCandidates = context.engine.clanData.getAllChannelsByUser()?.channeldesc ?? []
        } else {
            guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else {
                allHashtagChannelCandidates = []
                return
            }
            allHashtagChannelCandidates = Self.decodeChannelListPref(data)
        }
    }

    private static func decodeChannelListPref(_ data: Data) -> [Mezon_Api_ChannelDescription] {
        guard data.count > 4 else { return [] }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        let end = data.count
        while offset + 4 <= end {
            let lenU = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            offset += 4
            let len = Int(lenU)
            if len < 0 || len > 8_000_000 || len > end - offset { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + len))) {
                result.append(m)
            }
            offset += len
        }
        return result
    }

    private func reloadEmojiSuggestionList() {
        let cache = context.engine.data.cachedEmojiList(clanId: 0)
        let emojis = cache?.emojis ?? []
        var seenIds = Set<Int64>()
        var unique: [CachedClanEmojiRecord] = []
        unique.reserveCapacity(emojis.count)
        for e in emojis {
            guard e.id != 0, !e.shortname.isEmpty else { continue }
            guard seenIds.insert(e.id).inserted else { continue }
            unique.append(e)
        }
        allSuggestionEmojis = unique.sorted {
            $0.shortname.localizedCaseInsensitiveCompare($1.shortname) == .orderedAscending
        }
    }

    @objc private func handleEmojiListDidUpdate(_: Notification) {
        reloadEmojiSuggestionList()
        if detectEmojiColonContext() != nil {
            updateEmojiSuggestions()
        }
    }

    private var isPrivateOrThread: Bool {
        channel.channelPrivate != 0
            || channel.parentID != 0
            || channel.type == MezonConstants.ChannelType.thread.rawValue
    }

    private func loadClanMembers() {
        if clanId == 0 {
            loadDMMembers()
        } else if preferChannelScopedMentions {
            loadComposerChannelMentionMembers()
        } else if isPrivateOrThread {
            loadChannelMembersForPrivate()
        } else {
            loadClanMembersForPublic()
        }
    }

    private func loadComposerChannelMentionMembers() {
        if let records = mergedChannelMemberRecordsForMentions() {
            buildMentionMembers(from: records)
            ensureRolesLoadedIfNeeded()
            rebuildMentionSuggestionItems()
        }
        fetchComposerChannelMentionMembersFromNetwork()
    }

    private func fetchComposerChannelMentionMembersFromNetwork() {
        guard #available(iOS 13.0, *) else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let preferred = channel.type != 0
                    ? channel.type
                    : context.engine.clanData.resolvedListChannelUsersType(channelId: channel.channelID)
                let res = try await context.account.network.listChannelUsers(
                    clanId: clanId, channelId: channel.channelID, channelType: preferred, token: token)
                guard !res.channelUsers.isEmpty else {
                    if allMentionMembers.isEmpty { fetchClanMembersFromNetwork() }
                    return
                }
                let records = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                    res.channelUsers, postbox: context.account.postbox)
                let cid = channel.channelID
                context.account.postbox.write { tx in
                    tx.updateChannelMembers(records, channelId: cid)
                }
                if let merged = mergedChannelMemberRecordsForMentions() {
                    buildMentionMembers(from: merged)
                }
                ensureRolesLoadedIfNeeded()
                rebuildMentionSuggestionItems()
            } catch {
                if allMentionMembers.isEmpty { fetchClanMembersFromNetwork() }
            }
        }
    }

    private func loadDMMembers() {
        if let records = mergedChannelMemberRecordsForMentions() {
            buildMentionMembers(from: records)
            rebuildMentionSuggestionItems()
            return
        }
        fetchDMChannelUsersFromNetwork()
    }

    private func loadChannelMembersForPrivate() {
        let isThreadWithParent =
            channel.type == MezonConstants.ChannelType.thread.rawValue && channel.parentID != 0
        let threadMissingParentMembers = isThreadWithParent
            && context.account.postbox.read { tx in
                (tx.getChannelMeta(channelId: channel.parentID)?.members ?? []).filter { !$0.isBanned }.isEmpty
            }
        if !threadMissingParentMembers, let records = mergedChannelMemberRecordsForMentions() {
            buildMentionMembers(from: records)
            ensureRolesLoadedIfNeeded()
            rebuildMentionSuggestionItems()
            if !isThreadWithParent {
                return
            }
        }
        fetchPrivateChannelUsersFromNetwork()
    }

    private func loadClanMembersForPublic() {
        if let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId) {
            buildMentionMembers(from: clanUsers)
        }
        ensureRolesLoadedIfNeeded()
        rebuildMentionSuggestionItems()
        fetchClanMembersFromNetwork()
        prefetchChannelMembersIntoPostboxForPublicComposer()
    }

    private func mergedChannelMemberRecordsForMentions() -> [ChannelMemberRecord]? {
        var byUserId: [Int64: ChannelMemberRecord] = [:]
        for cid in mentionLookupChannelIds {
            let rows = context.account.postbox.read { tx in
                (tx.getChannelMeta(channelId: cid)?.members ?? []).filter { !$0.isBanned }
            }
            for r in rows where r.userId != 0 {
                if byUserId[r.userId] == nil {
                    byUserId[r.userId] = r
                }
            }
        }
        if byUserId.isEmpty { return nil }
        return Array(byUserId.values)
    }

    private func reloadMentionMembersFromChannelMetaOnly() {
        guard let records = mergedChannelMemberRecordsForMentions() else { return }
        buildMentionMembers(from: records)
        rebuildMentionSuggestionItems()
    }

    private func fetchDMChannelUsersFromNetwork() {
        guard #available(iOS 13.0, *) else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            let channelIdForStore = self.channel.channelID
            let labels = channel.dmMemberLabelsForChannelList()
            var didSync = false
            do {
                let uc = try await context.account.network.listChannelUsersUC(
                    channelId: channelIdForStore, limit: 500, token: token)
                if !uc.userIds.isEmpty {
                    context.account.postbox.write { tx in
                        tx.applyAllUsersAddChannelResponse(
                            uc, channelId: channelIdForStore, dmMemberLabelByUserId: labels)
                    }
                    didSync = true
                }
            } catch {
            }
            if !didSync {
                do {
                    let channelType = channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue
                    let res = try await context.account.network.listChannelUsers(
                        clanId: 0, channelId: channel.channelID, channelType: channelType, token: token)
                    let members = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                        res.channelUsers, postbox: context.account.postbox)
                    context.account.postbox.write { tx in
                        tx.updateChannelMembers(members, channelId: channelIdForStore)
                    }
                } catch {
                }
            }
            if let records = mergedChannelMemberRecordsForMentions() {
                buildMentionMembers(from: records)
            }
            rebuildMentionSuggestionItems()
        }
    }

    private func fetchPrivateChannelUsersFromNetwork() {
        guard #available(iOS 13.0, *) else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else {
                fetchClanMembersFromNetwork()
                return
            }
            do {
                if channel.parentID != 0 {
                    let parentIdForStore = self.channel.parentID
                    let parentType = context.engine.clanData.resolvedListChannelUsersType(channelId: parentIdForStore)
                    let parentHasCached = !(context.account.postbox.read { tx in
                        (tx.getChannelMeta(channelId: parentIdForStore)?.members ?? []).filter { !$0.isBanned }.isEmpty
                    })
                    let parentRes = try await context.account.network.listChannelUsers(
                        clanId: clanId, channelId: parentIdForStore,
                        channelType: parentType, token: token)
                    let skipParentWrite = parentRes.channelUsers.isEmpty && parentHasCached
                    if !skipParentWrite {
                        let parentMembers = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                            parentRes.channelUsers, postbox: context.account.postbox)
                        context.account.postbox.write { [parentIdForStore] tx in
                            tx.updateChannelMembers(parentMembers, channelId: parentIdForStore)
                        }
                    }
                }
                let channelType: Int32 = channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue
                let res = try await context.account.network.listChannelUsers(
                    clanId: clanId, channelId: channel.channelID, channelType: channelType, token: token)
                let members = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                    res.channelUsers, postbox: context.account.postbox)
                let channelIdForStore = self.channel.channelID
                context.account.postbox.write { [channelIdForStore] tx in
                    tx.updateChannelMembers(members, channelId: channelIdForStore)
                }
                if let records = mergedChannelMemberRecordsForMentions() {
                    buildMentionMembers(from: records)
                }
                ensureRolesLoadedIfNeeded()
                rebuildMentionSuggestionItems()
                if channel.type == MezonConstants.ChannelType.thread.rawValue,
                   channel.parentID != 0,
                   context.account.postbox.read({ tx in
                       (tx.getChannelMeta(channelId: channel.parentID)?.members ?? []).filter { !$0.isBanned }.isEmpty
                   }) {
                    await mergeClanUsersIntoAllMentionMembers(token: token)
                }
                if allMentionMembers.isEmpty {
                    fetchClanMembersFromNetwork()
                }
            } catch {
                fetchClanMembersFromNetwork()
            }
        }
    }

    private func prefetchChannelMembersIntoPostboxForPublicComposer() {
        guard clanId > 0, !isPrivateOrThread else { return }
        guard #available(iOS 13.0, *) else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let preferred = channel.type != 0
                    ? channel.type
                    : context.engine.clanData.resolvedListChannelUsersType(channelId: channel.channelID)
                let res = try await context.account.network.listChannelUsers(
                    clanId: clanId, channelId: channel.channelID, channelType: preferred, token: token)
                guard !res.channelUsers.isEmpty else { return }
                let records = ChannelMemberRecord.mergingProfilesFromChannelUsers(
                    res.channelUsers, postbox: context.account.postbox)
                let cid = channel.channelID
                context.account.postbox.write { tx in
                    tx.updateChannelMembers(records, channelId: cid)
                }
            } catch {
            }
        }
    }

    private func clanUserListForMentionFallback(token: String) async throws -> Mezon_Api_ClanUserList {
        if let c = context.engine.clanData.getClanUsers(clanId: clanId), !c.clanUsers.isEmpty {
            return c
        }
        let r = try await context.account.network.listClanUsers(clanId: clanId, token: token)
        if let data = try? r.serializedData() {
            context.account.postbox.setPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
        }
        return r
    }

    private func mergeClanUsersIntoAllMentionMembers(token: String) async {
        guard clanId > 0 else { return }
        do {
            let response = try await clanUserListForMentionFallback(token: token)
            var seen = Set(allMentionMembers.map(\.userId))
            var extra: [MentionMember] = []
            extra.reserveCapacity(response.clanUsers.count)
            for cu in response.clanUsers {
                let user = cu.user
                guard user.id != 0, seen.insert(user.id).inserted else { continue }
                let display = Self.layeredClanVisibleName(
                    clanNick: cu.clanNick,
                    displayName: user.displayName,
                    username: user.username,
                    userId: user.id,
                    profile: nil,
                    sender: nil
                )
                let ca = cu.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
                let av: String?
                if !ca.isEmpty {
                    av = ca
                } else {
                    let ua = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    av = ua.isEmpty ? nil : ua
                }
                extra.append(MentionMember(
                    userId: user.id,
                    displayName: display,
                    username: user.username,
                    avatarURL: av
                ))
            }
            guard !extra.isEmpty else { return }
            allMentionMembers.append(contentsOf: extra)
            allMentionMembers.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            rebuildMentionSuggestionItems()
        } catch {
        }
    }

    private func memberUserIdsForChannel(channelId: Int64, token: String) async throws -> Set<Int64> {
        let cached = context.account.postbox.read { tx -> Set<Int64> in
            let rows = (tx.getChannelMeta(channelId: channelId)?.members ?? []).filter { !$0.isBanned }
            return Set(rows.map(\.userId))
        }
        if !cached.isEmpty { return cached }
        if clanId == 0 {
            do {
                let uc = try await context.account.network.listChannelUsersUC(
                    channelId: channelId, limit: 500, token: token)
                if !uc.userIds.isEmpty {
                    let labels = channelId == channel.channelID ? channel.dmMemberLabelsForChannelList() : [:]
                    context.account.postbox.write { tx in
                        tx.applyAllUsersAddChannelResponse(uc, channelId: channelId, dmMemberLabelByUserId: labels)
                    }
                    return Set(uc.userIds)
                }
            } catch {
            }
        }
        let preferred: Int32 = channelId == channel.channelID && channel.type != 0
            ? channel.type
            : context.engine.clanData.resolvedListChannelUsersType(channelId: channelId)
        let res = try await context.account.network.listChannelUsers(
            clanId: clanId, channelId: channelId, channelType: preferred, token: token)
        guard !res.channelUsers.isEmpty else { return [] }
        let records = ChannelMemberRecord.mergingProfilesFromChannelUsers(
            res.channelUsers, postbox: context.account.postbox)
        context.account.postbox.write { tx in
            tx.updateChannelMembers(records, channelId: channelId)
        }
        return Set(records.map(\.userId))
    }

    private func roleListForMentionExpansion(token: String) async throws -> Mezon_Api_RoleList {
        if let cached = context.engine.clanData.getClanRoles(clanId: clanId) {
            return cached.roles
        }
        let response = try await context.account.network.listRoles(clanId: clanId, token: token)
        if let data = try? response.serializedData() {
            context.account.postbox.setPreferenceData(key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
        }
        return response.roles
    }

    private func candidateUserIdsForThreadAdds(from mentions: [Mezon_Api_MessageMention], roleList: Mezon_Api_RoleList) -> Set<Int64> {
        let roles = roleList.roles
        var result = Set<Int64>()
        for m in mentions {
            if m.roleID != 0 {
                guard let role = roles.first(where: { $0.id == m.roleID }) else { continue }
                for ru in role.roleUserList.roleUsers where ru.id != 0 {
                    result.insert(ru.id)
                }
            } else if m.userID != 0, m.userID != Self.mentionHereUserId {
                result.insert(m.userID)
            }
        }
        return result
    }

    private func hasPotentialThreadMemberAdds(
        mentionList: [Mezon_Api_MessageMention],
        editTargetSenderId: Int64?
    ) -> Bool {
        if let editTargetSenderId, editTargetSenderId != 0 {
            return true
        }
        return mentionList.contains { mention in
            mention.roleID != 0
                || (mention.userID != 0 && mention.userID != Self.mentionHereUserId)
        }
    }

    private func addUsersFromParentMentionsToThreadIfNeeded(
        mentionList: [Mezon_Api_MessageMention],
        editTargetSenderId: Int64?,
        token: String
    ) async throws {
        guard clanId != 0,
              channel.type == MezonConstants.ChannelType.thread.rawValue,
              channel.parentID != 0
        else { return }
        guard hasPotentialThreadMemberAdds(
            mentionList: mentionList,
            editTargetSenderId: editTargetSenderId
        ) else { return }
        let parentId = channel.parentID
        let threadId = channel.channelID
        let hasRoleMentions = mentionList.contains { $0.roleID != 0 }
        var candidates: Set<Int64>
        if hasRoleMentions {
            let roleList = try await roleListForMentionExpansion(token: token)
            candidates = candidateUserIdsForThreadAdds(from: mentionList, roleList: roleList)
        } else {
            candidates = Set(mentionList.compactMap { mention in
                let userId = mention.userID
                return userId != 0 && userId != Self.mentionHereUserId ? userId : nil
            })
        }
        if let editTargetSenderId, editTargetSenderId != 0 {
            candidates.insert(editTargetSenderId)
        }
        let currentUid = Int64(context.currentUser?.id ?? "") ?? 0
        candidates = Set(candidates.filter {
            $0 != 0 && $0 != Self.mentionHereUserId && $0 != currentUid
        })
        guard !candidates.isEmpty else { return }

        async let parentIds = memberUserIdsForChannel(channelId: parentId, token: token)
        async let threadIds = memberUserIdsForChannel(channelId: threadId, token: token)
        var (parentSet, childSet) = try await (parentIds, threadIds)
        if parentSet.isEmpty {
            parentSet = try await clanUserListForMentionFallback(token: token).clanUsers.reduce(into: Set<Int64>()) { acc, cu in
                let id = cu.user.id
                if id != 0 { acc.insert(id) }
            }
        }
        let toAdd = Set(candidates.filter { uid in
            parentSet.contains(uid) && !childSet.contains(uid)
        })
        guard !toAdd.isEmpty else { return }
        try await context.account.network.addChannelUsers(
            channelId: threadId, userIds: Array(toAdd), token: token)
        mergeThreadMemberCache(channelId: threadId, userIds: Array(toAdd))
    }

    private func mergeThreadMemberCache(channelId: Int64, userIds: [Int64]) {
        let sanitized = Array(Set(userIds.filter { $0 != 0 && $0 != Self.mentionHereUserId }))
        guard channelId != 0, !sanitized.isEmpty else { return }
        let currentUser = context.currentUser
        let currentClanId = clanId
        context.account.postbox.write { tx in
            var members = tx.getChannelMeta(channelId: channelId)?.members ?? []
            var knownUserIds = Set(members.map(\.userId))
            var didAppendMember = false
            for userId in sanitized where !knownUserIds.contains(userId) {
                let userIdString = String(userId)
                let profile = tx.getProfile(userId: userIdString)
                let isCurrentUser = currentUser?.id == userIdString
                let username = profile?.username
                    ?? (isCurrentUser ? currentUser?.username : nil)
                    ?? ""
                let displayName = profile?.displayName
                    ?? (isCurrentUser ? currentUser?.displayName : nil)
                    ?? ""
                let avatar = profile?.avatarUrl
                    ?? (isCurrentUser ? currentUser?.avatarURL?.absoluteString : nil)
                    ?? ""
                members.append(ChannelMemberRecord(
                    id: userId,
                    userId: userId,
                    roleIds: [],
                    threadId: channelId,
                    clanNick: displayName,
                    clanAvatar: avatar,
                    clanId: currentClanId,
                    isBanned: false,
                    expiredBanTime: 0,
                    isOnline: profile?.isOnline ?? false,
                    displayName: displayName,
                    username: username
                ))
                knownUserIds.insert(userId)
                didAppendMember = true
            }
            if didAppendMember {
                tx.updateChannelMembers(members, channelId: channelId)
            }
        }
    }

    private var isThreadChannelForSendPrep: Bool {
        channel.type == MezonConstants.ChannelType.thread.rawValue || channel.parentID != 0
    }

    private static func isJoinedThread(_ ch: Mezon_Api_ChannelDescription) -> Bool {
        ch.active == threadJoinedActiveStatus
            || (ch.channelPrivate != 0 && ch.active == threadActivePrivateJoinedStatus)
    }

    private func shouldJoinThreadBeforeSend(threadId: Int64, currentUid: Int64) -> Bool {
        guard threadId != 0, currentUid != 0 else { return false }
        if Self.isJoinedThread(channel) || locallyJoinedThreadIds.contains(threadId) {
            return false
        }

        let cachedMembers = context.account.postbox.read { tx in
            (tx.getChannelMeta(channelId: threadId)?.members ?? []).filter { !$0.isBanned }
        }
        if cachedMembers.isEmpty {
            return true
        }
        return !cachedMembers.contains(where: { $0.userId == currentUid })
    }

    private func applyLocalThreadJoinedState() {
        guard channel.channelID != 0 else { return }
        var ch = channel
        ch.active = Self.threadJoinedActiveStatus
        if ch.parentID != 0 {
            let parentId = ch.parentID
            if ch.categoryID == 0,
               let (_, parent) = context.account.postbox.getChannelDescription(channelId: parentId),
               parent.categoryID != 0 {
                ch.categoryID = parent.categoryID
                if ch.categoryName.isEmpty, !parent.categoryName.isEmpty {
                    ch.categoryName = parent.categoryName
                }
            }
        }
        channel = ch
        context.engine.clanData.applyLocallyCreatedChannel(ch, skipChannelListFetch: true)
    }

    private func activateThreadBeforeSendIfNeeded(token: String) async throws {
        guard clanId != 0, isThreadChannelForSendPrep else { return }

        let threadId = channel.channelID
        let currentUid = Int64(context.currentUser?.id ?? "") ?? 0
        guard currentUid != 0 else { return }

        let needsJoin = shouldJoinThreadBeforeSend(threadId: threadId, currentUid: currentUid)

        let now = Int(Date().timeIntervalSince1970)
        var lastTs: UInt32 = 0
        if channel.hasLastSentMessage, channel.lastSentMessage.timestampSeconds > 0 {
            lastTs = channel.lastSentMessage.timestampSeconds
        }
        let isArchived = lastTs > 0 && now - Int(lastTs) > Self.threadArchiveDurationSeconds
        let needsReactivate = isArchived && !locallyReactivatedThreadIds.contains(threadId)

        if needsReactivate {
            try await context.account.network.activeArchivedThread(
                clanId: clanId, channelId: threadId, token: token)
            locallyReactivatedThreadIds.insert(threadId)
        }

        if needsJoin {
            try await context.account.network.addChannelUsers(
                channelId: threadId, userIds: [currentUid], token: token)
            locallyJoinedThreadIds.insert(threadId)
            mergeThreadMemberCache(channelId: threadId, userIds: [currentUid])
        }

        if needsReactivate || needsJoin {
            applyLocalThreadJoinedState()
        }
    }

    private func prepareThreadBeforeSendIfNeeded(
        mentionList: [Mezon_Api_MessageMention],
        editTargetSenderId: Int64?,
        token: String
    ) async throws {
        try await addUsersFromParentMentionsToThreadIfNeeded(
            mentionList: mentionList,
            editTargetSenderId: editTargetSenderId,
            token: token
        )
        try await activateThreadBeforeSendIfNeeded(token: token)
    }

    private func fetchClanMembersFromNetwork() {
        guard clanId > 0 else { return }
        guard #available(iOS 13.0, *) else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let response = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    context.account.postbox.setPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
                }
                buildMentionMembers(from: response)
                ensureRolesLoadedIfNeeded()
                rebuildMentionSuggestionItems()
            } catch {
            }
        }
    }

    private func filteredRolesFromCache() -> [Mezon_Api_Role] {
        guard let response = context.engine.clanData.getClanRoles(clanId: clanId) else { return [] }
        return response.roles.roles.filter { role in
            guard role.id != 0, !role.title.isEmpty else { return false }
            let everyoneSlug = "everyone-\(role.clanID)"
            return role.slug != everyoneSlug
        }
    }

    private func ensureRolesLoadedIfNeeded() {
        guard includeRoleMentions, clanId != 0 else { return }
        guard context.engine.clanData.getClanRoles(clanId: clanId) == nil else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let response = try await context.account.network.listRoles(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    context.account.postbox.setPreferenceData(key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
                }
                rebuildMentionSuggestionItems()
            } catch {
            }
        }
    }

    private func rebuildMentionSuggestionItems() {
        var items: [MentionSuggestionItem] = allMentionMembers
            .map { MentionSuggestionItem.user($0) }
            .sorted { $0.sortKey < $1.sortKey }

        if includeRoleMentions {
            let roleItems = filteredRolesFromCache()
                .map { role in
                    MentionSuggestionItem.role(
                        id: role.id,
                        title: role.title,
                        colorHex: role.color,
                        iconURL: role.roleIcon.isEmpty ? nil : role.roleIcon
                    )
                }
                .sorted { $0.sortKey < $1.sortKey }
            items.append(contentsOf: roleItems)
        }
        if includeHereMention {
            items.append(.here)
        }
        allMentionSuggestionItems = items

        if case .mention(let keyword) = dominantInlineCompletion() {
            updateMentionSuggestions(keyword: keyword)
        }
    }


    private func detectEmojiColonContext() -> (colonUTF16: Int, keyword: String)? {
        guard !isEmojiPickerVisible else { return nil }
        let full = (textView.text ?? "") as NSString
        let len = full.length
        let sel = textView.selectedRange
        let cursor = min(sel.location + sel.length, len)
        guard cursor <= len else { return nil }
        let textBefore = full.substring(with: NSRange(location: 0, length: cursor)) as NSString
        guard textBefore.length > 0 else { return nil }

        let colonRange = textBefore.range(of: ":", options: .backwards)
        if colonRange.location == NSNotFound { return nil }
        let colonIdx = colonRange.location

        if colonIdx > 0 {
            let prev = textBefore.character(at: colonIdx - 1)
            if Self.isEmojiShortnameContinuationUTF16(prev) { return nil }
        }

        let afterLen = textBefore.length - colonIdx - 1
        guard afterLen >= 0 else { return nil }
        let keywordPart = textBefore.substring(with: NSRange(location: colonIdx + 1, length: afterLen))
        if keywordPart.contains(":") { return nil }
        let ws = CharacterSet.whitespacesAndNewlines
        if keywordPart.unicodeScalars.contains(where: { ws.contains($0) }) { return nil }
        guard !keywordPart.isEmpty else { return nil }

        return (colonIdx, keywordPart)
    }

    private static func memberMatchesSender(_ userId: Int64, senderId: Int64, sender: User) -> Bool {
        userId == senderId || "\(userId)" == sender.id
    }

    private static func layeredClanVisibleName(
        clanNick: String,
        displayName: String,
        username: String,
        userId: Int64,
        profile: ProfileRecord?,
        sender: User?
    ) -> String {
        let cn = clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cn.isEmpty { return cn }
        let dn = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dn.isEmpty { return dn }
        let un = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !un.isEmpty { return un }
        if let p = profile, let pdn = p.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !pdn.isEmpty {
            return pdn
        }
        let pun = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !pun.isEmpty { return pun }
        if let sender {
            let sdn = sender.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sdn.isEmpty { return sdn }
            let sun = sender.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sun.isEmpty { return sun }
            return sender.id
        }
        return "\(userId)"
    }

    private func buildMentionMembers(from records: [ChannelMemberRecord]) {
        let filtered = records.filter { !$0.isBanned }
        let cid = clanId
        allMentionMembers = context.account.postbox.read { tx -> [MentionMember] in
            let clanByUser: [Int64: ClanMemberRecord] = {
                guard cid > 0 else { return [:] }
                var d: [Int64: ClanMemberRecord] = [:]
                for m in tx.getClanMembers(clanId: cid) {
                    d[m.userId] = m
                }
                return d
            }()
            var seen = Set<Int64>()
            var out: [MentionMember] = []
            out.reserveCapacity(filtered.count)
            for r in filtered {
                guard seen.insert(r.userId).inserted else { continue }
                let profile = tx.getProfile(userId: String(r.userId))
                let cm = clanByUser[r.userId]
                let rd = r.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let ru = r.username.trimmingCharacters(in: .whitespacesAndNewlines)
                let cd = cm?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let cu = cm?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let mergedDisplay = rd.isEmpty ? cd : rd
                let mergedUsername = ru.isEmpty ? cu : ru
                let display = Self.layeredClanVisibleName(
                    clanNick: r.clanNick,
                    displayName: mergedDisplay,
                    username: mergedUsername,
                    userId: r.userId,
                    profile: profile,
                    sender: nil
                )
                let un: String = {
                    if !mergedUsername.isEmpty { return mergedUsername }
                    return profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }()
                let av: String?
                if !r.clanAvatar.isEmpty {
                    av = r.clanAvatar
                } else if let u = profile?.avatarUrl, !u.isEmpty {
                    av = u
                } else if let cm {
                    let ca = cm.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ca.isEmpty {
                        av = ca
                    } else {
                        let ua = cm.userAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        av = ua.isEmpty ? nil : ua
                    }
                } else {
                    av = nil
                }
                out.append(MentionMember(userId: r.userId, displayName: display, username: un, avatarURL: av))
            }
            return out
        }
    }

    private func buildMentionMembers(from clanUsers: Mezon_Api_ClanUserList) {
        var seen = Set<Int64>()
        allMentionMembers = clanUsers.clanUsers.compactMap { cu in
            let user = cu.user
            guard seen.insert(user.id).inserted else { return nil }
            let display = Self.layeredClanVisibleName(
                clanNick: cu.clanNick,
                displayName: user.displayName,
                username: user.username,
                userId: user.id,
                profile: nil,
                sender: nil
            )
            let ca = cu.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
            let av: String?
            if !ca.isEmpty {
                av = ca
            } else {
                let ua = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
                av = ua.isEmpty ? nil : ua
            }
            return MentionMember(
                userId: user.id,
                displayName: display,
                username: user.username,
                avatarURL: av
            )
        }
    }

    private enum InlineCompletionDominant {
        case mention(keyword: String)
        case hashtag(hashUTF16: Int, keyword: String)
    }

    private static func isMentionOrHashtagTriggerBoundary(in full: NSString, triggerUTF16 index: Int) -> Bool {
        guard index > 0 else { return true }
        let ch = full.character(at: index - 1)
        return ch == 0x20 || ch == 0x0A || ch == 0x0D || ch == 0x09
    }

    private static func stringContainsWhitespace(_ s: String) -> Bool {
        s.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }


    private func dominantInlineCompletion() -> InlineCompletionDominant? {
        guard let tr = textView.selectedTextRange else { return nil }
        let cursor = textView.offset(from: textView.beginningOfDocument, to: tr.start)
        let full = (textView.text ?? "") as NSString
        let len = full.length
        guard cursor >= 0, cursor <= len else { return nil }

        for m in activeMentions {
            if cursor > m.range.location && cursor <= m.range.location + m.range.length { return nil }
        }
        for h in activeHashtags {
            if cursor > h.range.location && cursor <= h.range.location + h.range.length { return nil }
        }

        let before = full.substring(with: NSRange(location: 0, length: cursor)) as NSString

        let atR = before.range(of: "@", options: .backwards)
        let hashR = before.range(of: "#", options: .backwards)

        var atPos = -1
        var atKeyword = ""
        if atR.location != NSNotFound {
            let ai = atR.location
            if Self.isMentionOrHashtagTriggerBoundary(in: full, triggerUTF16: ai) {
                let kwLen = cursor - (ai + 1)
                if kwLen >= 0 {
                    atKeyword = before.substring(with: NSRange(location: ai + 1, length: kwLen))
                    atPos = ai
                }
            }
        }

        var hashPos = -1
        var hashUTF16 = -1
        var hashKeyword = ""
        if includeHashtagSuggestions, hashR.location != NSNotFound {
            let hi = hashR.location
            if Self.isMentionOrHashtagTriggerBoundary(in: full, triggerUTF16: hi) {
                let kwLen = cursor - (hi + 1)
                if kwLen >= 0 {
                    let kw = before.substring(with: NSRange(location: hi + 1, length: kwLen))
                    if !Self.stringContainsWhitespace(kw) {
                        hashPos = hi
                        hashUTF16 = hi
                        hashKeyword = kw
                    }
                }
            }
        }

        if atPos < 0 && hashPos < 0 { return nil }
        if atPos < 0 { return .hashtag(hashUTF16: hashUTF16, keyword: hashKeyword) }
        if hashPos < 0 { return .mention(keyword: atKeyword) }
        if hashPos > atPos { return .hashtag(hashUTF16: hashUTF16, keyword: hashKeyword) }
        return .mention(keyword: atKeyword)
    }

    private func detectHashtagFragment() -> (hashUTF16: Int, keyword: String)? {
        guard case .hashtag(let u16, let kw) = dominantInlineCompletion() else { return nil }
        return (u16, kw)
    }

    private func detectMentionKeyword() -> String? {
        guard let selectedRange = textView.selectedTextRange else { return nil }
        let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
        let fullNS = (textView.text ?? "") as NSString
        guard cursorOffset > 0, cursorOffset <= fullNS.length else { return nil }

        let textBeforeNS = fullNS.substring(to: cursorOffset) as NSString

        for mention in activeMentions {
            if cursorOffset > mention.range.location && cursorOffset <= mention.range.location + mention.range.length {
                return nil
            }
        }

        let atRange = textBeforeNS.range(of: "@", options: .backwards)
        guard atRange.location != NSNotFound else { return nil }
        let atIntIdx = atRange.location

        if atIntIdx > 0 {
            let charBefore = textBeforeNS.substring(with: NSRange(location: atIntIdx - 1, length: 1))
            guard charBefore == " " || charBefore == "\n" else { return nil }
        }

        let keyword = textBeforeNS.substring(from: atIntIdx + 1)
        return keyword
    }

    private func updateInlineSuggestions() {
        if isEmojiPickerVisible {
            hideMentionSuggestions()
            hideEmojiSuggestions()
            hideHashtagSuggestions()
            return
        }

        if detectEmojiColonContext() != nil {
            hideMentionSuggestions()
            hideHashtagSuggestions()
            updateEmojiSuggestions()
            return
        }
        guard let dominant = dominantInlineCompletion() else {
            hideMentionSuggestions()
            hideHashtagSuggestions()
            hideEmojiSuggestions()
            return
        }
        hideEmojiSuggestions()
        switch dominant {
        case .mention(let keyword):
            hideHashtagSuggestions()
            updateMentionSuggestions(keyword: keyword)
        case .hashtag(_, let keyword):
            hideMentionSuggestions()
            updateHashtagSuggestions(keyword: keyword)
        }
    }

    private func updateMentionSuggestions(keyword: String) {
        let pool = allMentionSuggestionItems
        let filtered: [MentionSuggestionItem]
        if keyword.isEmpty {
            filtered = pool
        } else {
            let lower = keyword.lowercased()
            filtered = pool.filter { item in
                switch item {
                case .user(let m):
                    return m.displayName.lowercased().contains(lower) || m.username.lowercased().contains(lower)
                case .role(_, let title, _, _):
                    return title.lowercased().contains(lower)
                case .here:
                    return "here".contains(lower)
                }
            }.sorted { a, b in
                func rank(_ item: MentionSuggestionItem) -> (Bool, String) {
                    switch item {
                    case .user(let m):
                        let starts = m.displayName.lowercased().hasPrefix(lower) || m.username.lowercased().hasPrefix(lower)
                        return (starts, m.displayName.lowercased())
                    case .role(_, let title, _, _):
                        let starts = title.lowercased().hasPrefix(lower)
                        return (starts, title.lowercased())
                    case .here:
                        let starts = "here".hasPrefix(lower)
                        return (starts, "here")
                    }
                }
                let ra = rank(a), rb = rank(b)
                if ra.0 != rb.0 { return ra.0 && !rb.0 }
                return ra.1 < rb.1
            }
        }

        guard !filtered.isEmpty else {
            hideMentionSuggestions()
            return
        }
        showMentionSuggestions(items: filtered)
    }

    private func showMentionSuggestions(items: [MentionSuggestionItem]) {
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        guard let sv = mentionSuggestionView else { return }
        let wasVisible = !sv.isHidden
        let previousHeight = mentionSuggestionHeightConstraint?.constant ?? 0
        sv.update(items: items)
        sv.applyTheme()
        let h = sv.preferredHeight
        mentionSuggestionHeightConstraint?.constant = h
        sv.isHidden = false
        mountInlineSuggestionStrip(
            sv,
            heightConstraint: mentionSuggestionHeightConstraint,
            composerConstraints: mentionComposerConstraints,
            hostConstraints: &mentionHostConstraints,
            visibleHeight: h
        )
        promoteInlineSuggestionZOrder(strip: sv)
        guard !wasVisible || abs(previousHeight - h) > 0.5 else { return }
        notifyComposerHeightChanged()
        notifyInlineSuggestionVisibilityChanged()
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.15)
    }

    private func hideMentionSuggestions() {
        guard let sv = mentionSuggestionView else { return }
        let wasVisible = !sv.isHidden
            || (inlineSuggestionHost != nil && inlineSuggestionHost?.isHidden == false)
        mentionSuggestionHeightConstraint?.constant = 0
        sv.isHidden = true
        mountInlineSuggestionStrip(
            sv,
            heightConstraint: mentionSuggestionHeightConstraint,
            composerConstraints: mentionComposerConstraints,
            hostConstraints: &mentionHostConstraints,
            visibleHeight: 0
        )
        guard wasVisible else { return }
        notifyComposerHeightChanged()
        notifyInlineSuggestionVisibilityChanged()
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.15)
    }

    private func updateEmojiSuggestions() {
        if allSuggestionEmojis.isEmpty, !didAttemptEmojiSuggestionCacheLoad {
            didAttemptEmojiSuggestionCacheLoad = true
            reloadEmojiSuggestionList()
        }
        guard let ctx = detectEmojiColonContext() else {
            hideEmojiSuggestions()
            return
        }
        let lower = ctx.keyword.lowercased()
        var seenId = Set<Int64>()
        let filtered = allSuggestionEmojis.filter { emoji in
            let sn = emoji.shortname.lowercased()
            let bare = sn.split(separator: ":").joined()
            guard sn.contains(lower) || bare.contains(lower) else { return false }
            return seenId.insert(emoji.id).inserted
        }
        let capped = Array(filtered.prefix(20))
        guard !capped.isEmpty else {
            hideEmojiSuggestions()
            return
        }
        showEmojiSuggestions(items: capped)
    }

    private func showEmojiSuggestions(items: [CachedClanEmojiRecord]) {
        hideMentionSuggestions()
        hideHashtagSuggestions()
        guard let ev = emojiSuggestionView else { return }
        let wasVisible = !ev.isHidden
        let previousHeight = emojiSuggestionHeightConstraint?.constant ?? 0
        ev.update(items: items)
        ev.applyTheme()
        let h = ev.preferredHeight
        emojiSuggestionHeightConstraint?.constant = h
        ev.isHidden = false
        mountInlineSuggestionStrip(
            ev,
            heightConstraint: emojiSuggestionHeightConstraint,
            composerConstraints: emojiComposerConstraints,
            hostConstraints: &emojiHostConstraints,
            visibleHeight: h
        )
        promoteInlineSuggestionZOrder(strip: ev)
        guard !wasVisible || abs(previousHeight - h) > 0.5 else { return }
        notifyComposerHeightChanged()
        notifyInlineSuggestionVisibilityChanged()
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.15)
    }

    private func hideEmojiSuggestions() {
        emojiSuggestionHeightConstraint?.constant = 0
        guard let ev = emojiSuggestionView else { return }
        let wasVisible = !ev.isHidden
        ev.isHidden = true
        mountInlineSuggestionStrip(
            ev,
            heightConstraint: emojiSuggestionHeightConstraint,
            composerConstraints: emojiComposerConstraints,
            hostConstraints: &emojiHostConstraints,
            visibleHeight: 0
        )
        guard wasVisible else { return }
        notifyComposerHeightChanged()
        notifyInlineSuggestionVisibilityChanged()
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.15)
    }

    private func updateHashtagSuggestions(keyword: String) {
        guard includeHashtagSuggestions, !allHashtagChannelCandidates.isEmpty else {
            hideHashtagSuggestions()
            return
        }
        let lower = keyword.lowercased()
        let filtered: [Mezon_Api_ChannelDescription]
        if keyword.isEmpty {
            filtered = allHashtagChannelCandidates
        } else {
            filtered = allHashtagChannelCandidates.filter {
                $0.channelLabel.lowercased().contains(lower)
            }
        }
        let capped = Array(filtered.prefix(20))
        guard !capped.isEmpty else {
            hideHashtagSuggestions()
            return
        }
        showHashtagSuggestions(items: capped)
    }

    private func showHashtagSuggestions(items: [Mezon_Api_ChannelDescription]) {
        hideEmojiSuggestions()
        guard let hv = hashtagSuggestionView else { return }
        let wasVisible = !hv.isHidden
        let previousHeight = hashtagSuggestionHeightConstraint?.constant ?? 0
        hv.update(items: items)
        hv.applyTheme()
        let h = hv.preferredHeight
        hashtagSuggestionHeightConstraint?.constant = h
        hv.isHidden = false
        mountInlineSuggestionStrip(
            hv,
            heightConstraint: hashtagSuggestionHeightConstraint,
            composerConstraints: hashtagComposerConstraints,
            hostConstraints: &hashtagHostConstraints,
            visibleHeight: h
        )
        promoteInlineSuggestionZOrder(strip: hv)
        guard !wasVisible || abs(previousHeight - h) > 0.5 else { return }
        notifyComposerHeightChanged()
        notifyInlineSuggestionVisibilityChanged()
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.15)
    }

    private func hideHashtagSuggestions() {
        hashtagSuggestionHeightConstraint?.constant = 0
        guard let hv = hashtagSuggestionView else { return }
        let wasVisible = !hv.isHidden
        hv.isHidden = true
        mountInlineSuggestionStrip(
            hv,
            heightConstraint: hashtagSuggestionHeightConstraint,
            composerConstraints: hashtagComposerConstraints,
            hostConstraints: &hashtagHostConstraints,
            visibleHeight: 0
        )
        guard wasVisible else { return }
        notifyComposerHeightChanged()
        notifyInlineSuggestionVisibilityChanged()
        layoutSuperviewForComposerChange(shouldAnimateSuperview: true, duration: 0.15)
    }

    private func insertMention(item: MentionSuggestionItem) {
        guard case .mention = dominantInlineCompletion() else { return }
        guard let selectedRange = textView.selectedTextRange else { return }
        let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)

        let fullNS = (textView.text ?? "") as NSString
        guard cursorOffset >= 0, cursorOffset <= fullNS.length else { return }
        let textBeforeNS = fullNS.substring(to: cursorOffset) as NSString
        let atRange = textBeforeNS.range(of: "@", options: .backwards)
        guard atRange.location != NSNotFound else { return }
        let atIntIdx = atRange.location
        let replaceRange = NSRange(location: atIntIdx, length: cursorOffset - atIntIdx)

        let mentionText: String
        let tracked: ComposerMention
        switch item {
        case .user(let member):
            mentionText = "@\(member.displayName)"
            tracked = ComposerMention(userId: member.userId, roleId: 0, rolename: "", displayName: member.displayName, range: NSRange(location: 0, length: 0))
        case .role(let roleId, let title, _, _):
            mentionText = "@\(title)"
            tracked = ComposerMention(userId: 0, roleId: roleId, rolename: title, displayName: title, range: NSRange(location: 0, length: 0))
        case .here:
            mentionText = "@here"
            tracked = ComposerMention(userId: Self.mentionHereUserId, roleId: 0, rolename: "", displayName: "here", range: NSRange(location: 0, length: 0))
        }

        let trailingSpace = " "
        let insertText = mentionText + trailingSpace

        let t = UIColor.theme
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
        let mentionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 15.sf),
            .foregroundColor: UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        ]

        let attrText = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
        let mentionAttrStr = NSMutableAttributedString(string: mentionText, attributes: mentionAttrs)
        let spaceAttrStr = NSAttributedString(string: trailingSpace, attributes: normalAttrs)
        mentionAttrStr.append(spaceAttrStr)

        attrText.replaceCharacters(in: replaceRange, with: mentionAttrStr)
        textView.attributedText = attrText

        let mentionNSRange = NSRange(location: atIntIdx, length: (mentionText as NSString).length)
        let lengthDelta = (insertText as NSString).length - replaceRange.length
        activeMentions = activeMentions.map { m in
            if m.range.location >= replaceRange.location + replaceRange.length {
                return ComposerMention(
                    userId: m.userId,
                    roleId: m.roleId,
                    rolename: m.rolename,
                    displayName: m.displayName,
                    range: NSRange(location: m.range.location + lengthDelta, length: m.range.length)
                )
            }
            return m
        }
        activeHashtags = activeHashtags.map { h in
            if h.range.location >= replaceRange.location + replaceRange.length {
                return ComposerHashtag(
                    channelId: h.channelId,
                    clanId: h.clanId,
                    parentId: h.parentId,
                    channelLabel: h.channelLabel,
                    channelType: h.channelType,
                    channelPrivate: h.channelPrivate,
                    ageRestricted: h.ageRestricted,
                    range: NSRange(location: h.range.location + lengthDelta, length: h.range.length)
                )
            }
            return h
        }
        var appended = tracked
        appended.range = mentionNSRange
        activeMentions.append(appended)

        let newCursorPos = atIntIdx + (insertText as NSString).length
        if let pos = textView.position(from: textView.beginningOfDocument, offset: newCursorPos) {
            textView.selectedTextRange = textView.textRange(from: pos, to: pos)
        }

        textView.typingAttributes = normalAttrs

        text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        updateTextViewHeight()
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
    }

    private func insertHashtag(channel: Mezon_Api_ChannelDescription) {
        guard let selectedRange = textView.selectedTextRange else { return }
        let cursor = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
        guard let ctx = detectHashtagFragment(), ctx.hashUTF16 >= 0, cursor >= ctx.hashUTF16 else { return }

        let label = channel.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        let replaceRange = NSRange(location: ctx.hashUTF16, length: cursor - ctx.hashUTF16)
        let token = "#\(label)"
        let trailingSpace = " "
        let insertText = token + trailingSpace

        let t = UIColor.theme
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
        let tagFont = UIFont.boldSystemFont(ofSize: 15.sf)
        let tagTint = UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: tagFont,
            .foregroundColor: tagTint
        ]

        let attrText = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
        let tagAttrStr = NSMutableAttributedString()
        let iconName = channel.channelListIconAssetName()
        if let att = RichTextBuilder.hashtagIconAttachment(named: iconName, tint: tagTint, font: tagFont) {
            let iconStr = NSMutableAttributedString(attachment: att)
            var iconAttrs = tagAttrs
            iconAttrs[Self.hashtagIconAttrKey] = true
            iconAttrs[.kern] = Self.composerHashtagIconKernAfter
            iconAttrs[.baselineOffset] = Self.composerHashtagIconBaselineOffset
            iconStr.addAttributes(iconAttrs, range: NSRange(location: 0, length: iconStr.length))
            tagAttrStr.append(iconStr)
        } else {
            var hashAttrs = tagAttrs
            hashAttrs[.kern] = Self.composerHashtagIconKernAfter
            hashAttrs[.baselineOffset] = Self.composerHashtagIconBaselineOffset
            tagAttrStr.append(NSAttributedString(string: "#", attributes: hashAttrs))
        }
        tagAttrStr.append(NSAttributedString(string: label, attributes: tagAttrs))
        tagAttrStr.append(NSAttributedString(string: trailingSpace, attributes: normalAttrs))
        attrText.replaceCharacters(in: replaceRange, with: tagAttrStr)
        textView.attributedText = attrText

        let tagNSRange = NSRange(location: ctx.hashUTF16, length: (token as NSString).length)
        let lengthDelta = (insertText as NSString).length - replaceRange.length
        activeMentions = activeMentions.map { m in
            if m.range.location >= replaceRange.location + replaceRange.length {
                return ComposerMention(
                    userId: m.userId,
                    roleId: m.roleId,
                    rolename: m.rolename,
                    displayName: m.displayName,
                    range: NSRange(location: m.range.location + lengthDelta, length: m.range.length)
                )
            }
            return m
        }
        activeHashtags = activeHashtags.map { h in
            if h.range.location >= replaceRange.location + replaceRange.length {
                return ComposerHashtag(
                    channelId: h.channelId,
                    clanId: h.clanId,
                    parentId: h.parentId,
                    channelLabel: h.channelLabel,
                    channelType: h.channelType,
                    channelPrivate: h.channelPrivate,
                    ageRestricted: h.ageRestricted,
                    range: NSRange(location: h.range.location + lengthDelta, length: h.range.length)
                )
            }
            return h
        }
        var appended = ComposerHashtag(
            channelId: channel.channelID,
            clanId: channel.clanID,
            parentId: channel.parentID,
            channelLabel: label,
            channelType: channel.type,
            channelPrivate: channel.channelPrivate,
            ageRestricted: channel.ageRestricted,
            range: NSRange(location: 0, length: 0)
        )
        appended.range = tagNSRange
        activeHashtags.append(appended)

        let newCursorPos = ctx.hashUTF16 + (insertText as NSString).length
        textView.selectedRange = NSRange(location: newCursorPos, length: 0)
        textView.typingAttributes = normalAttrs

        text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        updateTextViewHeight()
        hideHashtagSuggestions()
        hideEmojiSuggestions()
        hideMentionSuggestions()
    }

    private func handleMentionProtection(range: NSRange, replacementText text: String) -> Bool {
        for (index, mention) in activeMentions.enumerated() {
            let mentionEnd = mention.range.location + mention.range.length
            let editEnd = range.location + range.length
            if range.location < mentionEnd && editEnd > mention.range.location {
                let attrText = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
                let deleteRange = mention.range
                let extendedEnd = min(deleteRange.location + deleteRange.length + 1, attrText.length)
                let extendedRange = NSRange(location: deleteRange.location, length: extendedEnd - deleteRange.location)
                attrText.deleteCharacters(in: extendedRange)

                let deletedLength = extendedRange.length
                activeMentions.remove(at: index)
                activeMentions = activeMentions.map { m in
                    if m.range.location > deleteRange.location {
                        return ComposerMention(
                            userId: m.userId,
                            roleId: m.roleId,
                            rolename: m.rolename,
                            displayName: m.displayName,
                            range: NSRange(location: m.range.location - deletedLength, length: m.range.length)
                        )
                    }
                    return m
                }
                activeHashtags = activeHashtags.map { h in
                    if h.range.location > deleteRange.location {
                        return ComposerHashtag(
                            channelId: h.channelId,
                            clanId: h.clanId,
                            parentId: h.parentId,
                            channelLabel: h.channelLabel,
                            channelType: h.channelType,
                            channelPrivate: h.channelPrivate,
                            ageRestricted: h.ageRestricted,
                            range: NSRange(location: h.range.location - deletedLength, length: h.range.length)
                        )
                    }
                    return h
                }

                textView.attributedText = attrText
                if let pos = textView.position(from: textView.beginningOfDocument, offset: deleteRange.location) {
                    textView.selectedTextRange = textView.textRange(from: pos, to: pos)
                }
                self.text = textView.text ?? ""
                placeholderLabel.isHidden = !self.text.isEmpty
                updateTextViewHeight()
                updateInlineSuggestions()
                return false
            }
        }
        return true
    }

    private func handleHashtagProtection(range: NSRange, replacementText text: String) -> Bool {
        for (index, tag) in activeHashtags.enumerated() {
            let tagEnd = tag.range.location + tag.range.length
            let editEnd = range.location + range.length
            if range.location < tagEnd && editEnd > tag.range.location {
                let attrText = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
                let deleteRange = tag.range
                let extendedEnd = min(deleteRange.location + deleteRange.length + 1, attrText.length)
                let extendedRange = NSRange(location: deleteRange.location, length: extendedEnd - deleteRange.location)
                attrText.deleteCharacters(in: extendedRange)

                let deletedLength = extendedRange.length
                activeHashtags.remove(at: index)
                activeHashtags = activeHashtags.map { h in
                    if h.range.location > deleteRange.location {
                        return ComposerHashtag(
                            channelId: h.channelId,
                            clanId: h.clanId,
                            parentId: h.parentId,
                            channelLabel: h.channelLabel,
                            channelType: h.channelType,
                            channelPrivate: h.channelPrivate,
                            ageRestricted: h.ageRestricted,
                            range: NSRange(location: h.range.location - deletedLength, length: h.range.length)
                        )
                    }
                    return h
                }
                activeMentions = activeMentions.map { m in
                    if m.range.location > deleteRange.location {
                        return ComposerMention(
                            userId: m.userId,
                            roleId: m.roleId,
                            rolename: m.rolename,
                            displayName: m.displayName,
                            range: NSRange(location: m.range.location - deletedLength, length: m.range.length)
                        )
                    }
                    return m
                }

                textView.attributedText = attrText
                if let pos = textView.position(from: textView.beginningOfDocument, offset: deleteRange.location) {
                    textView.selectedTextRange = textView.textRange(from: pos, to: pos)
                }
                self.text = textView.text ?? ""
                placeholderLabel.isHidden = !self.text.isEmpty
                updateTextViewHeight()
                updateInlineSuggestions()
                return false
            }
        }
        return true
    }

    private func buildPlainTextFromAttributed() -> String {
        let attr = textView.attributedText ?? NSAttributedString()
        guard attr.length > 0 else { return "" }
        let m = NSMutableString(string: attr.string)
        var replacements: [NSRange] = []
        attr.enumerateAttribute(Self.hashtagIconAttrKey, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            guard value != nil, range.length >= 1, NSMaxRange(range) <= m.length else { return }
            replacements.append(NSRange(location: range.location, length: 1))
        }
        for r in replacements.sorted(by: { $0.location > $1.location }) {
            m.replaceCharacters(in: r, with: "#")
        }
        return m as String
    }

    private static let hashtagIconAttrKey = NSAttributedString.Key("MezonComposerHashtagIcon")
    private static let composerHashtagIconKernAfter: CGFloat = 9
    private static let composerHashtagIconBaselineOffset: CGFloat = 0

    private func refreshHashtagIconAttachments() {
        guard !activeHashtags.isEmpty else { return }
        let attr = textView.attributedText ?? NSAttributedString()
        guard attr.length > 0 else { return }
        let m = NSMutableAttributedString(attributedString: attr)
        let tagFont = UIFont.boldSystemFont(ofSize: 15.sf)
        let tagTint = UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: tagFont,
            .foregroundColor: tagTint
        ]
        var didChange = false
        let sorted = activeHashtags.sorted(by: { $0.range.location > $1.range.location })
        for tag in sorted {
            guard tag.range.length >= 1, NSMaxRange(tag.range) <= m.length else { continue }
            let firstCharRange = NSRange(location: tag.range.location, length: 1)
            let iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                type: tag.channelType, channelPrivate: tag.channelPrivate, ageRestricted: tag.ageRestricted)
            guard let att = RichTextBuilder.hashtagIconAttachment(named: iconName, tint: tagTint, font: tagFont) else { continue }
            let iconStr = NSMutableAttributedString(attachment: att)
            var iconAttrs = tagAttrs
            iconAttrs[Self.hashtagIconAttrKey] = true
            iconAttrs[.kern] = Self.composerHashtagIconKernAfter
            iconAttrs[.baselineOffset] = Self.composerHashtagIconBaselineOffset
            iconStr.addAttributes(iconAttrs, range: NSRange(location: 0, length: iconStr.length))
            m.replaceCharacters(in: firstCharRange, with: iconStr)
            didChange = true
        }
        guard didChange else { return }
        let savedSelection = textView.selectedRange
        textView.attributedText = m
        let clamped = NSRange(
            location: max(0, min(savedSelection.location, m.length)),
            length: max(0, min(savedSelection.length, m.length - max(0, min(savedSelection.location, m.length))))
        )
        textView.selectedRange = clamped
    }

    private static let emojiListDidUpdateNotification = Notification.Name.mezonEmojiListDidUpdate


    private static func isEmojiShortnameContinuationUTF16(_ c: unichar) -> Bool {
        if c == 0x5F { return true }
        if c >= 0x30 && c <= 0x39 { return true }
        if c >= 0x41 && c <= 0x5A { return true }
        if c >= 0x61 && c <= 0x7A { return true }
        return false
    }


    private func buildMentionList(displayPlain: String) -> [Mezon_Api_MessageMention] {
        let plain = displayPlain as NSString
        let len = plain.length
        var searchStart = 0
        return activeMentions.compactMap { m in
            let needle = "@\(m.displayName)"
            let r = plain.range(of: needle, range: NSRange(location: searchStart, length: len - searchStart))
            guard r.location != NSNotFound else { return nil }
            searchStart = NSMaxRange(r)

            var mention = Mezon_Api_MessageMention()
            if m.roleId != 0 {
                mention.roleID = m.roleId
                mention.rolename = m.rolename
            } else {
                mention.userID = m.userId
                if m.userId == Self.mentionHereUserId {
                    mention.username = "here"
                } else if let member = allMentionMembers.first(where: { $0.userId == m.userId }) {
                    mention.username = member.username
                }
            }
            mention.s = Int32(r.location)
            mention.e = Int32(NSMaxRange(r))
            return mention
        }
    }


    private func buildHashtagList(displayPlain: String) -> [[String: Any]] {
        let plain = displayPlain as NSString
        let len = plain.length
        var searchStart = 0
        return activeHashtags.compactMap { h -> [String: Any]? in
            let needle = "#\(h.channelLabel)"
            let r = plain.range(of: needle, range: NSRange(location: searchStart, length: len - searchStart))
            guard r.location != NSNotFound, NSMaxRange(r) <= len else { return nil }
            searchStart = NSMaxRange(r)
            var dict: [String: Any] = [
                "channelId": "\(h.channelId)",
                "s": r.location,
                "e": NSMaxRange(r),
            ]
            if h.clanId != 0 {
                dict["clanId"] = "\(h.clanId)"
            }
            if h.parentId != 0 {
                dict["parentId"] = "\(h.parentId)"
            }
            let isThreadPublish = h.channelType == MezonConstants.ChannelType.thread.rawValue && h.channelPrivate == 0
            if isThreadPublish, !h.channelLabel.isEmpty {
                dict["channelLabel"] = h.channelLabel
            }
            dict["channelType"] = Int(h.channelType)
            dict["channelPrivate"] = Int(h.channelPrivate)
            dict["ageRestricted"] = Int(h.ageRestricted)
            return dict
        }
    }

    private func setupBindings() {
        placeholderLabel.text = placeholder

        disposables.add(
            (textPipe.signal() |> deliverOnMainQueue).start(next: { [weak self] text in
                guard let self else { return }
                guard self.textView.text != text else { return }
                self.textView.text = text
                self.placeholderLabel.isHidden = !text.isEmpty
                self.updateTextViewHeight()
                self.scheduleOgpPreviewUpdate(for: text)
            })
        )
    }

    private func setupThemeObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    @objc private func handleThemeChange() { applyTheme() }

    private func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.secondary
        inputBarView.backgroundColor = t.secondary
        topSeparator.backgroundColor = t.border
        textView.backgroundColor = t.tertiary
        let preservedAttributed = textView.attributedText
        textView.textColor = t.textStrong
        textView.font = .systemFont(ofSize: 15.sf)
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
        if let preserved = preservedAttributed, preserved.length > 0,
           !activeMentions.isEmpty || !activeHashtags.isEmpty || !emojiIdByColonToken.isEmpty {
            textView.attributedText = applyCurrentThemeToRestoredComposer(preserved)
            refreshHashtagIconAttachments()
        }
        placeholderLabel.font = .systemFont(ofSize: 15.sf)
        placeholderLabel.textColor = t.textDisabled
        attachButton.backgroundColor = t.tertiary
        attachButton.tintColor = t.textStrong
        advanceButton.backgroundColor = t.tertiary
        advanceButton.tintColor = t.textStrong
        voiceButton.backgroundColor = t.tertiary
        voiceButton.tintColor = t.textStrong
        voiceRecordingOverlay.applyTheme()
        chevronButton.backgroundColor = t.tertiary
        chevronButton.tintColor = t.textStrong
        emojiButton.tintColor = t.textDisabled
        attachmentPreviewView.applyTheme()
        ogpPreviewView.applyTheme()
        replyBannerView.backgroundColor = t.secondary
        replyLabel.textColor = t.textDisabled
        replyCancelButton.tintColor = t.textDisabled
        sendPermissionRestrictedChrome.backgroundColor = t.secondary
        sendPermissionRestrictedTopSep.backgroundColor = t.border
        sendPermissionRestrictedInner.backgroundColor = .clear
        sendPermissionRestrictedLabel.textColor = t.textDisabled
        sendPermissionRestrictedLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
        sendPermissionRestrictedLabel.text = L(L10n.ChannelMessages.noSendPermission)
        mentionSuggestionView?.applyTheme()
        emojiSuggestionView?.applyTheme()
        hashtagSuggestionView?.applyTheme()
        anonymousIndicatorButton.backgroundColor = t.secondaryWeight
        anonymousIndicatorButton.tintColor = t.textStrong
    }

    func setClanAnonymousPolicy(preventAnonymous: Bool) {
        clanPreventAnonymous = preventAnonymous
        if clanPreventAnonymous {
            AnonymousMessageStore.setEnabled(false, clanId: clanId)
        }
        refreshAnonymousUI()
    }

    func refreshAnonymousUI() {
        let on = clanId != 0 && !clanPreventAnonymous && AnonymousMessageStore.isEnabled(clanId: clanId)
        anonymousIndicatorButton.isHidden = !on
    }

    private var shouldSendAsAnonymousMessage: Bool {
        clanId != 0 && !clanPreventAnonymous && AnonymousMessageStore.isEnabled(clanId: clanId)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyTheme()
        reloadEmojiSuggestionList()
        reloadHashtagChannelCandidates()
        if !(textView.text ?? "").isEmpty {
            flushComposerHeightAfterContentMutation()
            scheduleOgpPreviewUpdate(for: textView.text ?? "")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !skipsPersistingComposerDraftOnLifecycleEnd {
            stashCurrentComposerDraftIfNeeded()
        }
    }

    deinit {
        if !skipsPersistingComposerDraftOnLifecycleEnd {
            stashCurrentComposerDraftIfNeeded()
        }
        voiceAudioRecorder?.stop()
        voiceRecordingOverlay.tearDown()
        if let u = voiceRecordingFileURL {
            try? FileManager.default.removeItem(at: u)
        }
        ogpFetchTask?.cancel()
        disposables.dispose()
        mentionDisposables.dispose()
        NotificationCenter.default.removeObserver(self)
    }


    private static let voiceCancelSwipeThreshold: CGFloat = 80
    private static let voiceMinRecordDuration: TimeInterval = 0.55

    @objc private func handleVoiceTapForHint() {
        onVoiceTapped?()
    }

    @objc private func handleVoiceLongPress(_ g: UILongPressGestureRecognizer) {
        let slideRef = voiceButton.superview ?? view
        switch g.state {
        case .began:
            voiceRecordingCancelled = false
            voiceRecordingStartAborted = false
            voiceSlideAnchorX = g.location(in: slideRef).x
            requestVoiceRecordingPermission { [weak self] granted in
                guard let self else { return }
                if self.voiceRecordingStartAborted { return }
                guard granted else {
                    self.presentMicrophoneDeniedAlert()
                    return
                }
                self.startVoiceRecording()
            }
        case .changed:
            guard let anchorX = voiceSlideAnchorX else { return }
            let x = g.location(in: slideRef).x
            let delta = x - anchorX
            if delta < -Self.voiceCancelSwipeThreshold {
                if !voiceRecordingCancelled {
                    voiceRecordingCancelled = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                if isVoiceRecordingActive { voiceRecordingOverlay.setSlideCancelledHighlight(true) }
            } else {
                if voiceRecordingCancelled {
                    voiceRecordingCancelled = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                if isVoiceRecordingActive { voiceRecordingOverlay.setSlideCancelledHighlight(false) }
            }
        case .ended, .cancelled, .failed:
            voiceRecordingStartAborted = true
            voiceSlideAnchorX = nil
            voiceRecordingOverlay.setSlideCancelledHighlight(false)
            if isVoiceRecordingActive {
                if voiceRecordingCancelled {
                    cancelVoiceRecording(deleteFile: true)
                } else {
                    finishVoiceRecordingAndSend()
                }
            } else {
                cancelVoiceRecording(deleteFile: false)
            }
        default:
            break
        }
    }

    private func requestVoiceRecordingPermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                DispatchQueue.main.async { completion(ok) }
            }
        @unknown default:
            completion(false)
        }
    }

    private func presentMicrophoneDeniedAlert() {
        let ac = UIAlertController(
            title: "Microphone",
            message: "Allow microphone access in Settings to send voice messages.",
            preferredStyle: .alert
        )
        ac.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        ac.addAction(UIAlertAction(title: L(L10n.Common.settings), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(ac, animated: true)
    }

    private func startVoiceRecording() {
        guard !voiceRecordingStartAborted else { return }
        let keyboardWasVisible = textView.isFirstResponder
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            onError?(error.localizedDescription)
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        voiceRecordingFileURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                onError?("Could not record")
                try? FileManager.default.removeItem(at: url)
                voiceRecordingFileURL = nil
                return
            }
            voiceAudioRecorder = recorder
        } catch {
            onError?(error.localizedDescription)
            try? FileManager.default.removeItem(at: url)
            voiceRecordingFileURL = nil
            return
        }

        guard !voiceRecordingStartAborted else {
            cancelVoiceRecording(deleteFile: true)
            return
        }

        voiceRecordingStartDate = Date()
        isVoiceRecordingActive = true
        voiceRecordingOverlay.prepareForRecording()
        voiceRecordingOverlay.markRecordingStarted()
        view.bringSubviewToFront(voiceRecordingOverlay)
        voiceRecordingOverlay.isHidden = false
        voiceRecordingOverlay.runAppearAnimation()
        emojiButton.isUserInteractionEnabled = false
        if keyboardWasVisible {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVoiceRecordingActive, !self.textView.isFirstResponder else { return }
                self.textView.becomeFirstResponder()
            }
        }
    }

    private func cancelVoiceRecording(deleteFile: Bool) {
        voiceAudioRecorder?.stop()
        voiceAudioRecorder = nil
        if deleteFile, let url = voiceRecordingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        voiceRecordingFileURL = nil
        isVoiceRecordingActive = false
        voiceRecordingOverlay.tearDown()
        UIView.performWithoutAnimation {
            self.voiceRecordingOverlay.isHidden = true
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        emojiButton.isUserInteractionEnabled = true
    }

    private func finishVoiceRecordingAndSend() {
        let url = voiceRecordingFileURL
        let start = voiceRecordingStartDate
        voiceRecordingFileURL = nil
        isVoiceRecordingActive = false
        voiceAudioRecorder?.stop()
        voiceAudioRecorder = nil
        voiceRecordingOverlay.tearDown()
        UIView.performWithoutAnimation {
            self.voiceRecordingOverlay.isHidden = true
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        emojiButton.isUserInteractionEnabled = true

        guard let url, let start else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < Self.voiceMinRecordDuration {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let durationSec = max(1, Int(round(elapsed)))
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size < 200 {
            try? FileManager.default.removeItem(at: url)
            return
        }
        sendVoiceAttachment(from: url, durationSeconds: durationSec)
    }

    private func sendVoiceAttachment(from fileURL: URL, durationSeconds: Int) {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let file = PickedFileInfo(url: fileURL, filename: fileURL.lastPathComponent, filesize: size, filetype: "audio/mp4")
        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.onError?("No session")
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            do {
                let uploaded = try await self.uploadFileAttachments([file], token: token)
                guard !uploaded.isEmpty else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                var att = uploaded[0]
                att.duration = Int32(durationSeconds)
                sendChannelMessageWithAttachments(text: "", attachments: [att])
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "sendVoiceAttachment",
                    "channelId": self.channel.channelID,
                    "clanId": self.clanId,
                    "durationSeconds": durationSeconds,
                ])
                self.onError?(error.localizedDescription)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func uploadAttachments(_ images: [UIImage], fileURLs: [Int: URL], token: String) async throws -> [Mezon_Api_MessageAttachment] {
        var attachments: [Mezon_Api_MessageAttachment] = []

        for (index, image) in images.enumerated() {
            guard let fileURL = fileURLs[index] else { continue }

            let originalFilename = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            let filetype = Self.mimeType(for: ext)

            let width = Int(image.size.width)
            let height = Int(image.size.height)

            let sanitizedFilename = originalFilename.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)

            if filetype.hasPrefix("video/") {
                let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size > 0 else { continue }
                let progressKey = fileURL.path
                let uploaded = try await AttachmentUploader.shared.uploadFile(
                    fileURL: fileURL,
                    filename: sanitizedFilename,
                    filetype: filetype,
                    fileSize: size,
                    width: width,
                    height: height,
                    token: token,
                    progressKey: progressKey,
                    network: context.account.network)
                AttachmentUploadProgressStore.shared.clear(forKey: progressKey)

                var att = Mezon_Api_MessageAttachment()
                att.filename = originalFilename
                att.url = uploaded.cdnURL
                att.filetype = filetype
                att.size = Int32(size)
                att.width = Int32(width)
                att.height = Int32(height)
                attachments.append(att)

                try? FileManager.default.removeItem(at: fileURL)
                continue
            }

            guard let fileData = try? Data(contentsOf: fileURL) else { continue }

            let uploadInfo = try await context.account.network.uploadAttachmentFile(
                filename: sanitizedFilename,
                filetype: filetype,
                size: fileData.count,
                width: width,
                height: height,
                token: token
            )

            try await context.account.network.uploadToMinIO(
                url: uploadInfo.url,
                data: fileData,
                contentType: filetype
            )

            let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"

            ImageCache.shared.setImage(image, data: fileData, forKey: cdnURL)

            var att = Mezon_Api_MessageAttachment()
            att.filename = originalFilename
            att.url = cdnURL
            att.filetype = filetype
            att.size = Int32(fileData.count)
            att.width = Int32(width)
            att.height = Int32(height)
            attachments.append(att)

            try? FileManager.default.removeItem(at: fileURL)
        }

        return attachments
    }

    private func uploadFileAttachments(_ files: [PickedFileInfo], token: String) async throws -> [Mezon_Api_MessageAttachment] {
        var attachments: [Mezon_Api_MessageAttachment] = []

        for file in files {
            let size: Int = {
                if file.filesize > 0 { return file.filesize }
                return (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? NSNumber)?.intValue ?? 0
            }()
            guard size > 0 else { continue }

            let sanitizedFilename = file.filename.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            let progressKey = file.url.path

            let uploaded = try await AttachmentUploader.shared.uploadFile(
                fileURL: file.url,
                filename: sanitizedFilename,
                filetype: file.filetype,
                fileSize: size,
                token: token,
                progressKey: progressKey,
                network: context.account.network)
            AttachmentUploadProgressStore.shared.clear(forKey: progressKey)

            var att = Mezon_Api_MessageAttachment()
            att.filename = file.filename
            att.url = uploaded.cdnURL
            att.filetype = file.filetype
            att.size = Int32(size)
            attachments.append(att)

            try? FileManager.default.removeItem(at: file.url)
        }

        return attachments
    }

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "bmp":         return "image/bmp"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        case "m4v":         return "video/x-m4v"
        case "avi":         return "video/avi"
        case "pdf":         return "application/pdf"
        case "doc":         return "application/msword"
        case "docx":        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":         return "application/vnd.ms-excel"
        case "xlsx":        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":         return "application/vnd.ms-powerpoint"
        case "pptx":        return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "zip":         return "application/zip"
        case "rar":         return "application/x-rar-compressed"
        case "7z":          return "application/x-7z-compressed"
        case "tar":         return "application/x-tar"
        case "gz":          return "application/gzip"
        case "txt":         return "text/plain"
        case "rtf":         return "application/rtf"
        case "csv":         return "text/csv"
        case "mp3":         return "audio/mpeg"
        case "wav":         return "audio/wav"
        case "aac":         return "audio/aac"
        case "m4a":         return "audio/mp4"
        case "ogg":         return "audio/ogg"
        default:            return "application/octet-stream"
        }
    }

    private func resolvePendingSenderDisplay(
        clanId: Int64,
        sender: User,
        senderId: Int64,
        isDmOrGroup: Bool
    ) -> (name: String, avatar: String?) {
        if isDmOrGroup {
            let name = Self.layeredClanVisibleName(
                clanNick: "",
                displayName: sender.displayName,
                username: sender.username,
                userId: 0,
                profile: nil,
                sender: sender
            )
            return (name, sender.avatarURL?.absoluteString)
        }
        let channelIds = mentionLookupChannelIds
        let mentionSnapshot = allMentionMembers
        let cachedClanNick: String? = {
            guard clanId != 0,
                  let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
                  let found = clanUsers.clanUsers.first(where: { $0.user.id == senderId }) else { return nil }
            let cn = found.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
            return cn.isEmpty ? nil : cn
        }()
        let cachedClanAvatar: String? = {
            guard clanId != 0,
                  let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId),
                  let found = clanUsers.clanUsers.first(where: { $0.user.id == senderId }) else { return nil }
            let ca = found.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
            return ca.isEmpty ? nil : ca
        }()
        return context.account.postbox.read { tx -> (String, String?) in
            if clanId != 0,
                let m = tx.getClanMembers(clanId: clanId).first(where: {
                    Self.memberMatchesSender($0.userId, senderId: senderId, sender: sender)
                })
            {
                let name = Self.layeredClanVisibleName(
                    clanNick: m.clanNick,
                    displayName: m.displayName,
                    username: m.username,
                    userId: m.userId,
                    profile: tx.getProfile(userId: sender.id),
                    sender: sender
                )
                let av: String?
                let ca = m.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ca.isEmpty {
                    av = ca
                } else if let p = tx.getProfile(userId: sender.id), let u = p.avatarUrl {
                    let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
                    av = t.isEmpty ? sender.avatarURL?.absoluteString : t
                } else {
                    av = sender.avatarURL?.absoluteString
                }
                return (name, av)
            }
            for cid in channelIds {
                let members = (tx.getChannelMeta(channelId: cid)?.members ?? []).filter { !$0.isBanned }
                guard let r = members.first(where: {
                    Self.memberMatchesSender($0.userId, senderId: senderId, sender: sender)
                }) else { continue }
                let resolvedClanNick: String = {
                    let rn = r.clanNick.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rn.isEmpty { return rn }
                    return cachedClanNick ?? ""
                }()
                let name = Self.layeredClanVisibleName(
                    clanNick: resolvedClanNick,
                    displayName: r.displayName,
                    username: r.username,
                    userId: r.userId,
                    profile: tx.getProfile(userId: sender.id),
                    sender: sender
                )
                let av: String?
                let ca = r.clanAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ca.isEmpty {
                    av = ca
                } else if let cca = cachedClanAvatar {
                    av = cca
                } else if let p = tx.getProfile(userId: sender.id), let u = p.avatarUrl {
                    let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
                    av = t.isEmpty ? sender.avatarURL?.absoluteString : t
                } else {
                    av = sender.avatarURL?.absoluteString
                }
                return (name, av)
            }
            if let mm = mentionSnapshot.first(where: {
                Self.memberMatchesSender($0.userId, senderId: senderId, sender: sender)
            }) {
                let name = Self.layeredClanVisibleName(
                    clanNick: cachedClanNick ?? "",
                    displayName: mm.displayName,
                    username: mm.username,
                    userId: mm.userId,
                    profile: tx.getProfile(userId: sender.id),
                    sender: sender
                )
                let mav = mm.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                let av: String?
                if let cca = cachedClanAvatar {
                    av = cca
                } else if let mav, !mav.isEmpty {
                    av = mav
                } else {
                    av = sender.avatarURL?.absoluteString
                }
                return (name, av)
            }
            let name = Self.layeredClanVisibleName(
                clanNick: cachedClanNick ?? "",
                displayName: sender.displayName,
                username: sender.username,
                userId: 0,
                profile: tx.getProfile(userId: sender.id),
                sender: sender
            )
            let av: String? = cachedClanAvatar ?? sender.avatarURL?.absoluteString
            return (name, av)
        }
    }

    private func applyOptimisticSendComposerReset(preserveAttachments: Bool = false) {
        let key = draftStorageKey(for: channel, topicId: topicId)
        Self.channelTextDraftCache.removeValue(forKey: key)
        Self.channelEditingStateCache.removeValue(forKey: key)
        editingDisplay = nil
        text = ""
        activeMentions.removeAll()
        activeHashtags.removeAll()
        emojiIdByColonToken.removeAll()
        textView.attributedText = nil
        textView.text = ""
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.theme.textStrong
        ]
        placeholderLabel.isHidden = false
        textView.isScrollEnabled = false
        resetTextViewHeight()
        if !preserveAttachments {
            clearPickedImages()
        }
        clearReply()
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        clearOgpPreview(userDismissed: false, resetDismissed: true)
        if !skipOptimisticPendingMessageOnSend {
            onSent?()
        }
    }

    private static func mezonApiMessageAttachments(from parsed: [ParsedAttachment]) -> [Mezon_Api_MessageAttachment] {
        parsed.map { p in
            var att = Mezon_Api_MessageAttachment()
            att.url = p.url
            att.filename = p.filename
            att.filetype = p.filetype
            if let w = p.width { att.width = Int32(w) }
            if let h = p.height { att.height = Int32(h) }
            if let d = p.durationSeconds { att.duration = Int32(d) }
            return att
        }
    }

    private static let textPayloadKeys: Set<String> = ["t", "text", "mk", "ej", "hg", "mentions", "lk"]

    private static func jsonContentObject(from data: Data?) -> [String: Any]? {
        guard let data,
              !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else { return nil }
        return json
    }

    private static func shareContactContentObject(from display: ChatMessageDisplay) -> [String: Any] {
        if let json = jsonContentObject(from: display.rawContentData) {
            return json
        }

        guard let contact = display.shareContactData else { return [:] }
        return [
            "embed": [[
                "fields": [
                    ["name": "key", "value": MezonConstants.shareContactKey, "inline": true],
                    ["name": "user_id", "value": contact.userId, "inline": true],
                    ["name": "username", "value": contact.username, "inline": true],
                    ["name": "display_name", "value": contact.displayName, "inline": true],
                    ["name": "avatar", "value": contact.avatar, "inline": true],
                ],
            ]],
        ]
    }

    private func makeOutgoingContentData(
        rawInput: String,
        displayText: String,
        markdownList: [[String: Any]],
        emojiList: [[String: Any]],
        hashtagList: [[String: Any]],
        isEdit: Bool
    ) -> Data {
        let isShareContactEdit = isEdit && editingDisplay?.shareContactData != nil
        var contentJSON: [String: Any] = {
            guard isShareContactEdit, let editingDisplay else { return [:] }
            return Self.shareContactContentObject(from: editingDisplay)
        }()

        for key in Self.textPayloadKeys {
            contentJSON.removeValue(forKey: key)
        }

        if isShareContactEdit || !rawInput.isEmpty {
            contentJSON["t"] = displayText
        }
        if !rawInput.isEmpty {
            if !markdownList.isEmpty {
                contentJSON["mk"] = markdownList
            }
            if !emojiList.isEmpty {
                contentJSON["ej"] = emojiList
            }
            if !hashtagList.isEmpty {
                contentJSON["hg"] = hashtagList
            }
        }

        return (try? JSONSerialization.data(withJSONObject: contentJSON)) ?? Data()
    }

    private func sendChannelMessage(
        text: String,
        images: [UIImage],
        clanId: Int64,
        channel: Mezon_Api_ChannelDescription,
        editingMessageId: Int64 = 0,
        fileURLsOverride: [Int: URL]? = nil,
        filesOverride: [PickedFileInfo]? = nil,
        preserveComposerAttachmentsOnReset: Bool = false
    ) {
        guard !composerSendPermissionBlocked else { return }
        let isEdit = editingMessageId != 0
        let sendAsAnonymous = shouldSendAsAnonymousMessage
        let localId = "pending-\(UUID().uuidString)"
        let channelIdStr = topicId != 0 ? "topic-\(topicId)" : "\(channel.channelID)"
        let imagesToUpload = images
        let fileURLsToUpload = fileURLsOverride ?? pickedFileURLs
        let filesToUpload = filesOverride ?? pickedFiles
        let hasAttachmentsToUpload = !imagesToUpload.isEmpty || !filesToUpload.isEmpty
        let useIncrementalAttachmentPath = !isEdit && !sendAsAnonymous && hasAttachmentsToUpload
        if !skipOptimisticPendingMessageOnSend, !isEdit, !imagesToUpload.isEmpty, !sendAsAnonymous, !useIncrementalAttachmentPath {
            ParsedAttachment.pendingImageCache[localId] = imagesToUpload
        }
        if !skipOptimisticPendingMessageOnSend, !isEdit, !filesToUpload.isEmpty, !sendAsAnonymous {
            ParsedAttachment.pendingDocumentPlaceholders[localId] = filesToUpload.map { file in
                ParsedAttachment(
                    url: "",
                    filename: file.filename,
                    filetype: file.filetype,
                    width: nil,
                    height: nil,
                    durationSeconds: nil,
                    localImage: nil,
                    isUploading: true,
                    uploadProgressKey: file.url.path,
                    uploadShowsPercent: file.filesize >= AttachmentUploader.minMultipartFileSize
                )
            }
        }

        let replyRef: Mezon_Api_MessageRef? = isEdit ? nil : buildReplyRef()
        let built = ComposerContentPayloadBuilder.build(rawInput: text, emojiIdByColon: emojiIdByColonToken)
        let displayText = built.displayText
        let mentionList = buildMentionList(displayPlain: displayText)
        let hashtagListForContent = buildHashtagList(displayPlain: displayText)
        var markdownList = built.mk
        if !isEdit,
           let ogpItem = activeOgpPreviewItem,
           ogpItem.hasSendableMetadata,
           text.contains(ogpItem.url),
           markdownList.contains(where: { ($0["type"] as? String) == "lk" }) {
            markdownList.append(ogpItem.markdownPayload(textLength: displayText.utf16.count))
        }
        let threadEditTargetSenderId: Int64? = {
            guard isEdit,
                  channel.type == MezonConstants.ChannelType.thread.rawValue,
                  channel.parentID != 0,
                  let sid = editingDisplay?.message.senderId,
                  let id = Int64(sid), id != 0 else { return nil }
            return id
        }()

        let outgoingContentData = makeOutgoingContentData(
            rawInput: text,
            displayText: displayText,
            markdownList: markdownList,
            emojiList: built.ej,
            hashtagList: hashtagListForContent,
            isEdit: isEdit
        )

        if !isEdit, outgoingContentData.count > Self.maxMessageContentBytes {
            if convertTextToPlainTextAttachment(text) {
                clearComposerTextAfterFileConversion()
            }
            return
        }

        let mentionsPayload: Data = {
            guard !mentionList.isEmpty else { return Data() }
            var list = Mezon_Api_MessageMentionList()
            list.mentions = mentionList
            return (try? list.serializedData()) ?? Data()
        }()

        let editPendingCacheKey: String? = {
            guard isEdit, !sendAsAnonymous else { return nil }
            guard !imagesToUpload.isEmpty || !filesToUpload.isEmpty else { return nil }
            return "\(editingMessageId)"
        }()

        let textOnlyEditPendingKey: String? = {
            guard isEdit, !sendAsAnonymous else { return nil }
            guard imagesToUpload.isEmpty, filesToUpload.isEmpty, fileURLsToUpload.isEmpty else { return nil }
            return "\(editingMessageId)"
        }()

        if let key = editPendingCacheKey {
            if !imagesToUpload.isEmpty {
                ParsedAttachment.pendingImageCache[key] = imagesToUpload
            }
            if !filesToUpload.isEmpty {
                ParsedAttachment.pendingDocumentPlaceholders[key] = filesToUpload.map { file in
                    ParsedAttachment(
                        url: "",
                        filename: file.filename,
                        filetype: file.filetype,
                        width: nil,
                        height: nil,
                        durationSeconds: nil,
                        localImage: nil,
                        isUploading: true,
                        uploadProgressKey: file.url.path,
                        uploadShowsPercent: file.filesize >= AttachmentUploader.minMultipartFileSize
                    )
                }
            }
            let keptRemoteForPending = editingRemoteImageAttachments + editingRemoteFileAttachments
            self.context.account.postbox.write { tx in
                guard let old = tx.getMessageById(key) else { return }
                let newAttachmentsJSON: Data = {
                    let proto = Self.mezonApiMessageAttachments(from: keptRemoteForPending)
                    var list = Mezon_Api_MessageAttachmentList()
                    list.attachments = proto
                    return (try? list.serializedData()) ?? old.attachmentsJSON
                }()
                let updated = MessageRecord(
                    id: old.id,
                    channelId: old.channelId,
                    clanId: old.clanId,
                    senderId: old.senderId,
                    content: outgoingContentData,
                    createdAt: old.createdAt,
                    editedAt: old.editedAt,
                    isDeleted: old.isDeleted,
                    code: old.code,
                    senderDisplayName: old.senderDisplayName,
                    senderAvatarURL: old.senderAvatarURL,
                    sendingState: .pending,
                    attachmentsJSON: newAttachmentsJSON,
                    reactionsJSON: old.reactionsJSON,
                    referencesData: old.referencesData,
                    mentionsJSON: mentionsPayload
                )
                tx.addMessages([updated])
            }
        } else if let key = textOnlyEditPendingKey {
            self.context.account.postbox.write { tx in
                guard let old = tx.getMessageById(key) else { return }
                let updated = MessageRecord(
                    id: old.id,
                    channelId: old.channelId,
                    clanId: old.clanId,
                    senderId: old.senderId,
                    content: outgoingContentData,
                    createdAt: old.createdAt,
                    editedAt: old.editedAt,
                    isDeleted: old.isDeleted,
                    code: old.code,
                    senderDisplayName: old.senderDisplayName,
                    senderAvatarURL: old.senderAvatarURL,
                    sendingState: .pending,
                    attachmentsJSON: old.attachmentsJSON,
                    reactionsJSON: old.reactionsJSON,
                    referencesData: old.referencesData,
                    mentionsJSON: mentionsPayload
                )
                tx.addMessages([updated])
            }
        }

        let pendingReferencesData: Data = {
            guard let ref = replyRef else { return Data() }
            var list = Mezon_Api_MessageRefList()
            list.refs = [ref]
            return (try? list.serializedData()) ?? Data()
        }()
        let pendingSenderDisplayName: String
        let pendingSenderAvatarURL: String?
        if let sender = context.currentUser {
            let senderIdInt = Int64(sender.id) ?? 0
            let isDmOrGroup = channel.type == MezonConstants.ChannelType.dm.rawValue
                || channel.type == MezonConstants.ChannelType.group.rawValue
            let resolved = resolvePendingSenderDisplay(
                clanId: clanId, sender: sender, senderId: senderIdInt, isDmOrGroup: isDmOrGroup)
            pendingSenderDisplayName = resolved.name
            pendingSenderAvatarURL = resolved.avatar
        } else {
            pendingSenderDisplayName = ""
            pendingSenderAvatarURL = nil
        }
        let pendingCreatedAt = Date()

        if !skipOptimisticPendingMessageOnSend, !isEdit, !sendAsAnonymous, !useIncrementalAttachmentPath, let sender = context.currentUser {
            let pendingRecord = MessageRecord.pending(
                localId: localId,
                text: displayText,
                channelId: channelIdStr,
                clanId: clanId,
                sender: sender,
                displayName: pendingSenderDisplayName,
                avatarURL: pendingSenderAvatarURL,
                referencesData: pendingReferencesData,
                mentionsData: mentionsPayload,
                contentData: outgoingContentData
            )
            self.context.account.postbox.write { tx in
                tx.addMessages([pendingRecord])
            }
        }

        let preservedEditAttachments: [ParsedAttachment] = {
            guard isEdit else { return [] }
            return editingRemoteImageAttachments + editingRemoteFileAttachments
        }()

        let capturedEditCreateTimeSeconds: UInt32? = {
            guard isEdit else { return nil }
            if let createdAt = editingDisplay?.message.createdAt {
                let seconds = UInt32(createdAt.timeIntervalSince1970)
                if seconds > 0 { return seconds }
            }
            if editingMessageId > 0 {
                let seconds = UInt32(truncatingIfNeeded: (editingMessageId >> 22) / 1000)
                if seconds > 0 { return seconds }
            }
            return nil
        }()

        applyOptimisticSendComposerReset(
            preserveAttachments: preserveComposerAttachmentsOnReset
        )

        let contentStr: String = {
            guard let s = String(data: outgoingContentData, encoding: .utf8), !s.isEmpty else { return "{}" }
            return s
        }()

        let mode: Int32 = {
            switch channel.type {
            case MezonConstants.ChannelType.thread.rawValue:
                return MezonConstants.ChannelStreamMode.thread.rawValue
            case MezonConstants.ChannelType.dm.rawValue:
                return MezonConstants.ChannelStreamMode.dm.rawValue
            case MezonConstants.ChannelType.group.rawValue:
                return MezonConstants.ChannelStreamMode.group.rawValue
            default:
                return clanId == 0
                    ? MezonConstants.ChannelStreamMode.group.rawValue
                    : MezonConstants.ChannelStreamMode.channel.rawValue
            }
        }()
        let isPublic = channel.channelPrivate == 0
        let avatar: String = context.currentUser?.avatarURL?.absoluteString ?? ""
        let references: [Mezon_Api_MessageRef] = replyRef.map { [$0] } ?? []

        if useIncrementalAttachmentPath {
            let imageSendParams = ImageSendParams(
                localId: localId,
                channelIdStr: channelIdStr,
                clanId: clanId,
                channelId: channel.channelID,
                mode: mode,
                isPublic: isPublic,
                topicId: self.topicId,
                hasText: !text.isEmpty,
                contentStr: contentStr,
                outgoingContentData: outgoingContentData,
                mentionList: mentionList,
                mentionsPayload: mentionsPayload,
                references: references,
                pendingReferencesData: pendingReferencesData,
                avatar: avatar,
                pendingSenderDisplayName: pendingSenderDisplayName,
                pendingSenderAvatarURL: pendingSenderAvatarURL,
                images: imagesToUpload,
                fileURLs: fileURLsToUpload,
                files: filesToUpload,
                skipOptimisticPending: skipOptimisticPendingMessageOnSend
            )
            AttachmentUploadCoordinator.shared.startImageSend(
                context: context,
                params: imageSendParams,
                prepare: { [weak self] token in
                    guard let self else { return }
                    try await self.prepareThreadBeforeSendIfNeeded(
                        mentionList: mentionList, editTargetSenderId: nil, token: token)
                }
            )
            return
        }

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                if !isEdit, !sendAsAnonymous {
                    self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                    ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                    ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: localId)
                }
                if let key = editPendingCacheKey {
                    self.context.account.postbox.write { tx in tx.markMessageFailed(id: key) }
                    ParsedAttachment.pendingImageCache.removeValue(forKey: key)
                    ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: key)
                }
                if let key = textOnlyEditPendingKey {
                    self.context.account.postbox.write { tx in tx.markMessageFailed(id: key) }
                }
                self.onError?("No session")
                return
            }
            do {
                try await self.prepareThreadBeforeSendIfNeeded(
                    mentionList: mentionList,
                    editTargetSenderId: threadEditTargetSenderId,
                    token: token
                )
                var uploadedAttachments: [Mezon_Api_MessageAttachment] = []
                if !imagesToUpload.isEmpty {
                    uploadedAttachments = try await self.uploadAttachments(imagesToUpload, fileURLs: fileURLsToUpload, token: token)
                }
                if !filesToUpload.isEmpty {
                    let fileAttachments = try await self.uploadFileAttachments(filesToUpload, token: token)
                    uploadedAttachments.append(contentsOf: fileAttachments)
                }

                if isEdit, !preservedEditAttachments.isEmpty {
                    let preservedProto = Self.mezonApiMessageAttachments(from: preservedEditAttachments)
                    uploadedAttachments = preservedProto + uploadedAttachments
                }

                if isEdit {
                    let hideEditted = !imagesToUpload.isEmpty || !filesToUpload.isEmpty
                    let hasNewAttachments = !imagesToUpload.isEmpty || !filesToUpload.isEmpty
                    let isAttachmentFieldUpdate = hasNewAttachments && !uploadedAttachments.isEmpty
                    let hasExistingAttachments = !preservedEditAttachments.isEmpty
                    let editCreateTimeSeconds: UInt32? = capturedEditCreateTimeSeconds
                    let editContentStr: String = {
                        guard hasExistingAttachments, !isAttachmentFieldUpdate,
                              let seconds = capturedEditCreateTimeSeconds else { return contentStr }
                        return PresignFinishContent.withCreateTimeSeconds(contentStr, createTimeSeconds: seconds)
                    }()
                    let ack = try await self.context.account.network.updateChannelMessage(
                        clanId: clanId,
                        channelId: self.topicId != 0 ? self.topicId : channel.channelID,
                        mode: mode,
                        isPublic: isPublic,
                        messageId: editingMessageId,
                        content: editContentStr,
                        mentions: mentionList,
                        attachments: isAttachmentFieldUpdate ? uploadedAttachments : nil,
                        hideEditted: hideEditted,
                        topicId: self.topicId != 0 ? self.topicId : nil,
                        isUpdateMsgTopic: self.topicId != 0,
                        createTimeSeconds: editCreateTimeSeconds,
                        token: token
                    )
                    self.context.account.postbox.write { tx in
                        let lookup = "\(editingMessageId)"
                        guard let old = tx.getMessageById(lookup) else {
                            return
                        }
                        let editedAt: Date? = {
                            if hideEditted { return old.editedAt }
                            if ack.updateTimeSeconds > 0 {
                                return Date(timeIntervalSince1970: TimeInterval(ack.updateTimeSeconds))
                            }
                            return Date()
                        }()
                        let newAttachmentsJSON: Data = {
                            guard !uploadedAttachments.isEmpty else { return old.attachmentsJSON }
                            var list = Mezon_Api_MessageAttachmentList()
                            list.attachments = uploadedAttachments
                            return (try? list.serializedData()) ?? old.attachmentsJSON
                        }()
                        let updated = MessageRecord(
                            id: old.id,
                            channelId: old.channelId,
                            clanId: old.clanId,
                            senderId: old.senderId,
                            content: outgoingContentData,
                            createdAt: old.createdAt,
                            editedAt: editedAt,
                            isDeleted: old.isDeleted,
                            code: old.code,
                            senderDisplayName: old.senderDisplayName,
                            senderAvatarURL: old.senderAvatarURL,
                            sendingState: .sent,
                            attachmentsJSON: newAttachmentsJSON,
                            reactionsJSON: old.reactionsJSON,
                            referencesData: old.referencesData,
                            mentionsJSON: mentionsPayload
                        )
                        tx.addMessages([updated])
                    }
                    if let key = editPendingCacheKey {
                        ParsedAttachment.pendingImageCache.removeValue(forKey: key)
                        ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: key)
                    }
                } else {
                    let ack = try await self.context.account.network.sendChannelMessage(
                        clanId: clanId,
                        channelId: channel.channelID,
                        mode: mode,
                        isPublic: isPublic,
                        content: contentStr,
                        mentions: mentionList,
                        attachments: uploadedAttachments,
                        references: references,
                        anonymous: sendAsAnonymous,
                        mentionEveryone: false,
                        avatar: avatar,
                        topicId: self.topicId,
                        token: token
                    )
                    self.updateCachedDMLastSentMessageIfNeeded(
                        ack: ack,
                        fallbackContent: contentStr,
                        hasAttachments: !uploadedAttachments.isEmpty
                    )
                    if !sendAsAnonymous {
                        let fallbackSenderId = self.context.currentUser?.id ?? ""
                        let fallbackClanId: String? = clanId == 0 ? nil : "\(clanId)"
                        self.context.account.postbox.write { tx in
                            guard ack.messageID != 0 else {
                                let msgs = tx.getMessages(channelId: channelIdStr)
                                if msgs.contains(where: { $0.id == localId }) {
                                    tx.markMessageFailed(id: localId)
                                }
                                return
                            }
                            let pending = tx.getMessageById(localId)
                            let baseAttachmentsJSON = pending?.attachmentsJSON ?? Data()
                            let attachmentsJSON: Data = {
                                guard !uploadedAttachments.isEmpty else { return baseAttachmentsJSON }
                                var list = Mezon_Api_MessageAttachmentList()
                                list.attachments = uploadedAttachments
                                return (try? list.serializedData()) ?? baseAttachmentsJSON
                            }()
                            let createdAt: Date = ack.createTimeSeconds > 0
                                ? Date(timeIntervalSince1970: TimeInterval(ack.createTimeSeconds))
                                : (pending?.createdAt ?? pendingCreatedAt)
                            let editedAt: Date? = ack.updateTimeSeconds > ack.createTimeSeconds && ack.updateTimeSeconds > 0
                                ? Date(timeIntervalSince1970: TimeInterval(ack.updateTimeSeconds))
                                : nil
                            let merged = MessageRecord(
                                id: "\(ack.messageID)",
                                channelId: pending?.channelId ?? channelIdStr,
                                clanId: pending?.clanId ?? fallbackClanId,
                                senderId: pending?.senderId ?? fallbackSenderId,
                                content: pending?.content ?? outgoingContentData,
                                createdAt: createdAt,
                                editedAt: editedAt,
                                isDeleted: pending?.isDeleted ?? false,
                                code: ack.code,
                                senderDisplayName: pending?.senderDisplayName ?? pendingSenderDisplayName,
                                senderAvatarURL: pending?.senderAvatarURL ?? pendingSenderAvatarURL,
                                sendingState: .sent,
                                attachmentsJSON: attachmentsJSON,
                                reactionsJSON: pending?.reactionsJSON ?? Data(),
                                referencesData: pending?.referencesData ?? pendingReferencesData,
                                mentionsJSON: pending?.mentionsJSON ?? mentionsPayload
                            )
                            tx.replaceMessage(pendingId: localId, with: merged)
                            if !ClanOnboardingChannelCache.isEphemeralMessageCode(ack.code) {
                                ClanOnboardingChannelCache.markCreatorSentWelcomeMessageIfNeeded(
                                    transaction: tx,
                                    clanId: self.clanId,
                                    channelId: channel.channelID
                                )
                            }
                        }
                        if ack.messageID != 0 {
                            self.markOnboardingWelcomeMessageSentIfNeeded(
                                ack: ack,
                                anonymous: sendAsAnonymous
                            )
                            ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                            ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: localId)
                            self.registerDeliveryConfirmation(serverMessageId: "\(ack.messageID)")
                        }
                    }
                }
                if self.skipOptimisticPendingMessageOnSend {
                    self.skipOptimisticPendingMessageOnSend = false
                    self.onSent?()
                }
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "sendChannelMessage",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                    "isEdit": isEdit,
                    "imageCount": imagesToUpload.count,
                    "fileCount": filesToUpload.count,
                ])
                var suppressErrorToast = false
                if !isEdit, !sendAsAnonymous {
                    if Self.isDefinitelyUndelivered(error) {
                        self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                        ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                        ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: localId)
                    } else {
                        self.scheduleAmbiguousSendFailsafe(localId: localId)
                        suppressErrorToast = true
                    }
                }
                if let key = editPendingCacheKey {
                    self.context.account.postbox.write { tx in tx.markMessageFailed(id: key) }
                    ParsedAttachment.pendingImageCache.removeValue(forKey: key)
                    ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: key)
                }
                if let key = textOnlyEditPendingKey {
                    self.context.account.postbox.write { tx in tx.markMessageFailed(id: key) }
                }
                if self.skipOptimisticPendingMessageOnSend {
                    self.skipOptimisticPendingMessageOnSend = false
                }
                if !suppressErrorToast {
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }


    func sendWaveWelcome(replyingTo display: ChatMessageDisplay) {
        if editingDisplay != nil {
            clearEditingMessage()
        }
        let urls = MezonConstants.waveStickerURLs
        guard !urls.isEmpty else { return }
        let ts = Int64(display.message.createdAt.timeIntervalSince1970)
        let idx = Int(abs(ts) % Int64(urls.count))
        var att = Mezon_Api_MessageAttachment()
        att.url = urls[idx]
        att.filetype = "image/gif"
        att.filename = MezonConstants.waveStickerFilename
        att.size = MezonConstants.waveStickerAttachmentSize
        att.width = MezonConstants.waveStickerWidth
        att.height = MezonConstants.waveStickerHeight
        let refs: [Mezon_Api_MessageRef]
        if channel.type == MezonConstants.ChannelType.dm.rawValue {
            refs = []
        } else {
            refs = [Self.buildWaveReplyRef(for: display)]
        }
        sendChannelMessageWithAttachments(text: "", attachments: [att], explicitReferences: refs)
    }

    private static func buildWaveReplyRef(for display: ChatMessageDisplay) -> Mezon_Api_MessageRef {
        var ref = Mezon_Api_MessageRef()
        ref.messageID = 0
        ref.messageRefID = Int64(display.message.id) ?? 0
        ref.refType = 0
        ref.messageSenderID = Int64(display.message.senderId) ?? 0
        ref.messageSenderUsername = MezonConstants.waveSenderDisplayName
        ref.messageSenderClanNick = MezonConstants.waveSenderDisplayName
        ref.messageSenderDisplayName = MezonConstants.waveSenderDisplayName
        ref.messageSenderAvatar = MezonConstants.waveSenderAvatarURL
        ref.hasAttachment_p = !display.attachments.isEmpty
        ref.content = display.replyRefSourceContent
        return ref
    }

    private func sendChannelMessageWithAttachments(
        text: String,
        attachments: [Mezon_Api_MessageAttachment],
        explicitReferences: [Mezon_Api_MessageRef]? = nil
    ) {
        guard !composerSendPermissionBlocked else { return }
        if editingDisplay != nil {
            clearEditingMessage()
        }
        let references: [Mezon_Api_MessageRef]
        if let explicitReferences {
            references = explicitReferences
        } else {
            let replyRef = buildReplyRef()
            references = replyRef.map { [$0] } ?? []
            clearReply()
        }
        let contentStr: String
        if text.isEmpty {
            contentStr = "{}"
        } else if let data = try? JSONSerialization.data(withJSONObject: ["t": text]),
                  let str = String(data: data, encoding: .utf8) {
            contentStr = str
        } else {
            contentStr = "{}"
        }

        let mode: Int32 = {
            switch channel.type {
            case MezonConstants.ChannelType.thread.rawValue:
                return MezonConstants.ChannelStreamMode.thread.rawValue
            case MezonConstants.ChannelType.dm.rawValue:
                return MezonConstants.ChannelStreamMode.dm.rawValue
            case MezonConstants.ChannelType.group.rawValue:
                return MezonConstants.ChannelStreamMode.group.rawValue
            default:
                return clanId == 0
                    ? MezonConstants.ChannelStreamMode.group.rawValue
                    : MezonConstants.ChannelStreamMode.channel.rawValue
            }
        }()
        let isPublic = channel.channelPrivate == 0
        let avatar = context.currentUser?.avatarURL?.absoluteString ?? ""

        onSent?()

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.onError?("No session")
                return
            }
            do {
                try await self.activateThreadBeforeSendIfNeeded(token: token)
                let ack = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: [],
                    attachments: attachments,
                    references: references,
                    anonymous: self.shouldSendAsAnonymousMessage,
                    mentionEveryone: false,
                    avatar: avatar,
                    topicId: self.topicId,
                    token: token
                )
                self.updateCachedDMLastSentMessageIfNeeded(
                    ack: ack,
                    fallbackContent: contentStr,
                    hasAttachments: !attachments.isEmpty
                )
                self.markOnboardingWelcomeMessageSentIfNeeded(
                    ack: ack,
                    anonymous: self.shouldSendAsAnonymousMessage
                )
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "sendChannelMessageWithAttachments",
                    "channelId": channel.channelID,
                    "clanId": clanId,
                    "attachmentCount": attachments.count,
                ])
                self.onError?(error.localizedDescription)
            }
        }
    }

    private func buildReplyRef() -> Mezon_Api_MessageRef? {
        guard let display = replyDisplay else { return nil }
        var ref = Mezon_Api_MessageRef()
        ref.messageID = 0
        ref.messageRefID = Int64(display.message.id) ?? 0
        ref.refType = 0
        ref.messageSenderID = Int64(display.message.senderId) ?? 0
        ref.messageSenderUsername = display.senderUsername
        ref.messageSenderDisplayName = display.senderDisplayName
        ref.messageSenderAvatar = display.isSystemMessage
            ? MezonConstants.waveSenderAvatarURL
            : (display.avatarURL ?? "")
        ref.hasAttachment_p = !display.attachments.isEmpty
        if display.shareContactData != nil {
            ref.content = display.replyRefSourceContent
        } else {
            let contentJSON: [String: Any] = ["t": display.parsedContent.text]
            if let jsonData = try? JSONSerialization.data(withJSONObject: contentJSON),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                ref.content = jsonStr
            }
        }
        return ref
    }

    private func composerNormalTypingAttributes() -> [NSAttributedString.Key: Any] {
        let t = UIColor.theme
        return [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: t.textStrong
        ]
    }

    private func composerHighlightTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.boldSystemFont(ofSize: 15.sf),
            .foregroundColor: UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        ]
    }

    private func utf16RangeOfKnownEmojiTokenContainingLocation(_ loc: Int, in plain: String) -> NSRange? {
        let ns = plain as NSString
        guard loc >= 0, loc < ns.length else { return nil }
        let keys = emojiIdByColonToken.keys.sorted { a, b in
            a.utf16.count > b.utf16.count
        }
        for token in keys {
            guard !token.isEmpty else { continue }
            var s = 0
            while s < ns.length {
                let search = NSRange(location: s, length: ns.length - s)
                let r = ns.range(of: token, range: search)
                if r.location == NSNotFound { break }
                if loc >= r.location && loc < r.location + r.length {
                    return r
                }
                s = r.location + max(r.length, 1)
            }
        }
        return nil
    }

    private func refreshComposerTypingAttributesForSelection() {
        let normal = composerNormalTypingAttributes()
        let highlight = composerHighlightTypingAttributes()
        let sel = textView.selectedRange
        if sel.length > 0 {
            textView.typingAttributes = normal
            return
        }
        let loc = sel.location
        let plain = textView.text ?? ""
        let ns = plain as NSString
        if plain.isEmpty {
            textView.typingAttributes = normal
            return
        }
        if loc == 0 {
            textView.typingAttributes = normal
            return
        }
        if loc == ns.length {
            textView.typingAttributes = normal
            return
        }
        for m in activeMentions {
            if loc >= m.range.location, loc < m.range.location + m.range.length {
                textView.typingAttributes = highlight
                return
            }
        }
        for h in activeHashtags {
            if loc >= h.range.location, loc < h.range.location + h.range.length {
                textView.typingAttributes = highlight
                return
            }
        }
        if let er = utf16RangeOfKnownEmojiTokenContainingLocation(loc, in: plain) {
            textView.typingAttributes = (loc == er.location) ? normal : highlight
            return
        }
        textView.typingAttributes = normal
    }
}

extension SendMessageInputViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        lastHandledComposerSelection = NSRange(location: -1, length: -1)
        text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        updateTextViewHeight()
        updateInlineSuggestions()
        updateSendVoiceToggle()
        syncAttachControlsWithTypedText()
        refreshComposerTypingAttributesForSelection()
        scheduleOgpPreviewUpdate(for: text)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        syncAttachControlsWithTypedText()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isHandlingComposerSelectionChange else { return }
        guard textView.markedTextRange == nil else { return }
        let sel = textView.selectedRange
        let textLength = ((textView.text ?? "") as NSString).length
        guard !NSEqualRanges(sel, lastHandledComposerSelection)
            || textLength != lastHandledComposerSelectionTextLength else { return }
        isHandlingComposerSelectionChange = true
        defer { isHandlingComposerSelectionChange = false }
        lastHandledComposerSelection = sel
        lastHandledComposerSelectionTextLength = textLength
        updateInlineSuggestions()
        refreshComposerTypingAttributesForSelection()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if isVoiceRecordingActive {
            return false
        }
        if !handleHashtagProtection(range: range, replacementText: text) {
            return false
        }
        if !handleMentionProtection(range: range, replacementText: text) {
            return false
        }
        if !text.isEmpty && range.length == 0 {
            let insertLen = (text as NSString).length
            activeMentions = activeMentions.map { m in
                if m.range.location >= range.location {
                    return ComposerMention(
                        userId: m.userId,
                        roleId: m.roleId,
                        rolename: m.rolename,
                        displayName: m.displayName,
                        range: NSRange(location: m.range.location + insertLen, length: m.range.length)
                    )
                }
                return m
            }
            activeHashtags = activeHashtags.map { h in
                if h.range.location >= range.location {
                    return ComposerHashtag(
                        channelId: h.channelId,
                        clanId: h.clanId,
                        parentId: h.parentId,
                        channelLabel: h.channelLabel,
                        channelType: h.channelType,
                        channelPrivate: h.channelPrivate,
                        ageRestricted: h.ageRestricted,
                        range: NSRange(location: h.range.location + insertLen, length: h.range.length)
                    )
                }
                return h
            }
        } else if text.isEmpty && range.length > 0 {
            activeMentions = activeMentions.map { m in
                if m.range.location >= range.location + range.length {
                    return ComposerMention(
                        userId: m.userId,
                        roleId: m.roleId,
                        rolename: m.rolename,
                        displayName: m.displayName,
                        range: NSRange(location: m.range.location - range.length, length: m.range.length)
                    )
                }
                return m
            }
            activeHashtags = activeHashtags.map { h in
                if h.range.location >= range.location + range.length {
                    return ComposerHashtag(
                        channelId: h.channelId,
                        clanId: h.clanId,
                        parentId: h.parentId,
                        channelLabel: h.channelLabel,
                        channelType: h.channelType,
                        channelPrivate: h.channelPrivate,
                        ageRestricted: h.ageRestricted,
                        range: NSRange(location: h.range.location - range.length, length: h.range.length)
                    )
                }
                return h
            }
        } else if !text.isEmpty && range.length > 0 {
            let delta = (text as NSString).length - range.length
            activeMentions = activeMentions.map { m in
                if m.range.location >= range.location + range.length {
                    return ComposerMention(
                        userId: m.userId,
                        roleId: m.roleId,
                        rolename: m.rolename,
                        displayName: m.displayName,
                        range: NSRange(location: m.range.location + delta, length: m.range.length)
                    )
                }
                return m
            }
            activeHashtags = activeHashtags.map { h in
                if h.range.location >= range.location + range.length {
                    return ComposerHashtag(
                        channelId: h.channelId,
                        clanId: h.clanId,
                        parentId: h.parentId,
                        channelLabel: h.channelLabel,
                        channelType: h.channelType,
                        channelPrivate: h.channelPrivate,
                        ageRestricted: h.ageRestricted,
                        range: NSRange(location: h.range.location + delta, length: h.range.length)
                    )
                }
                return h
            }
        }
        if !text.isEmpty, range.length == 0 {
            let tlen = (self.textView.text as NSString).length
            if range.location == 0 || range.location == tlen {
                self.textView.typingAttributes = composerNormalTypingAttributes()
            }
        }
        return true
    }

    private func resetTextViewHeight() {
        guard !composerSendPermissionBlocked else { return }
        currentTextViewHeight = Self.textViewMinHeight
        textViewHeightConstraint?.constant = Self.textViewMinHeight
        inputBarHeightConstraint?.constant = Self.textViewMinHeight + Self.inputBarPadding
        onHeightChanged?(totalHeight)
        layoutSuperviewForComposerChange(shouldAnimateSuperview: false, duration: 0)
    }

    private func resolvedComposerFittingContentWidth() -> CGFloat {
        view.layoutIfNeeded()
        inputBarView.layoutIfNeeded()
        let insetL = textView.textContainerInset.left
        let insetR = textView.textContainerInset.right
        var outer = textView.bounds.width
        if outer < 2 {
            outer = textView.frame.width
        }
        if outer < 2, inputBarView.bounds.width > 2 {
            outer = inputBarView.bounds.width
        }
        if outer < 2 {
            let w = view.window?.bounds.width ?? view.bounds.width
            if w > 2 {
                outer = w
            }
        }
        var inner = max(0, outer - insetL - insetR)
        if inner < 40 {
            let host = max(view.window?.bounds.width ?? 0, view.bounds.width)
            if host > 2 {
                inner = max(inner, max(0, host - 140) - insetL - insetR)
            }
        }
        return max(1, inner)
    }

    private func flushComposerHeightAfterContentMutation() {
        updateTextViewHeight()
        DispatchQueue.main.async { [weak self] in
            self?.updateTextViewHeight()
        }
    }

    private func updateTextViewHeight() {
        guard !composerSendPermissionBlocked else { return }
        let font = textView.font ?? .systemFont(ofSize: 15.sf)
        let lineHeight = font.lineHeight
        let maxLines: CGFloat = 6
        let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let maxHeight = lineHeight * maxLines + verticalInsets
        let minHeight = Self.textViewMinHeight
        let availableWidth = resolvedComposerFittingContentWidth()
        let fittingSize = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        let measuredTotal = textView.sizeThatFits(fittingSize).height
        let empty = (textView.text ?? "").isEmpty
        let rawHeight = empty ? minHeight : measuredTotal
        let newHeight = min(max(rawHeight, minHeight), maxHeight)

        let shouldScroll = measuredTotal > maxHeight + 0.5
        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
            if shouldScroll {
                textView.layoutManager.ensureLayout(for: textView.textContainer)
            }
        }

        guard abs(newHeight - currentTextViewHeight) > 0.5 else { return }
        currentTextViewHeight = newHeight
        textViewHeightConstraint?.constant = newHeight
        inputBarHeightConstraint?.constant = newHeight + Self.inputBarPadding
        onHeightChanged?(totalHeight)
        layoutSuperviewForComposerChange(shouldAnimateSuperview: false, duration: 0)
    }
}


struct PastedImage {
    let image: UIImage
    let data: Data?
    let fileExtension: String?
}

final class PastableTextView: UITextView {

    var onImagesPasted: (([PastedImage]) -> Void)?
    var onGIFPasted: ((Data) -> Void)?
    var onLongTextPasted: ((String) -> Bool)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        guard h > 0 else { return }
        let cap = 20.swh
        layer.cornerRadius = min(h * 0.5, cap)
        if #available(iOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            let pb = UIPasteboard.general
            if pb.hasImages || pb.contains(pasteboardTypes: ["com.compuserve.gif"]) {
                return true
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general

        if let gifData = pb.data(forPasteboardType: "com.compuserve.gif") {
            onGIFPasted?(gifData)
            if let text = pb.string, !text.isEmpty {
                super.paste(sender)
            }
            return
        }

        let dataImages = Self.imagesFromPasteboardData(pb)
        if !dataImages.isEmpty {
            onImagesPasted?(dataImages)
            if let text = pb.string, !text.isEmpty {
                insertText(text)
            }
            return
        }

        if let images = pb.images, !images.isEmpty {
            let pasted = images.map { PastedImage(image: Self.normalizedOrientation($0), data: nil, fileExtension: nil) }
            onImagesPasted?(pasted)
            if let text = pb.string, !text.isEmpty {
                insertText(text)
            }
            return
        }

        if pb.hasImages, let image = pb.image {
            onImagesPasted?([PastedImage(image: Self.normalizedOrientation(image), data: nil, fileExtension: nil)])
            return
        }

        if let text = pb.string, !text.isEmpty, onLongTextPasted?(text) == true {
            return
        }

        super.paste(sender)
    }

    private static let imageDataPasteboardTypes: [(uti: String, ext: String)] = [
        ("public.heic", "heic"),
        ("public.heif", "heif"),
        ("public.jpeg", "jpg"),
        ("public.png", "png"),
        ("public.tiff", "tiff"),
        ("public.webp", "webp"),
        ("public.image", ""),
    ]

    private static func imagesFromPasteboardData(_ pb: UIPasteboard) -> [PastedImage] {
        let itemCount = pb.numberOfItems
        guard itemCount > 0 else { return [] }
        var result: [PastedImage] = []
        for i in 0..<itemCount {
            for entry in imageDataPasteboardTypes {
                guard let data = pb.data(forPasteboardType: entry.uti, inItemSet: IndexSet(integer: i))?.first,
                      let decoded = UIImage(data: data) else { continue }
                let resolvedExt = entry.ext.isEmpty ? Self.inferExtension(from: data) : entry.ext
                result.append(PastedImage(
                    image: normalizedOrientation(decoded),
                    data: data,
                    fileExtension: resolvedExt
                ))
                break
            }
        }
        return result
    }

    private static func inferExtension(from data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if bytes.starts(with: [0x42, 0x4D]) { return "bmp" }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            switch brand {
            case "heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs": return "heic"
            case "mif1", "msf1": return "heif"
            default: return nil
            }
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           bytes.count >= 12,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "webp"
        }
        return nil
    }

    private static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private final class OverflowHitTestView: UIView {

    var overflowTargets: (() -> [UIView])?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for target in overflowTargets?() ?? [] where !target.isHidden && target.isUserInteractionEnabled {
            let converted = convert(point, to: target)
            guard target.point(inside: converted, with: event) else { continue }
            if let hit = target.hitTest(converted, with: event) {
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }
}


extension SendMessageInputViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var didHitLimit = false
        for url in urls {
            guard remainingAttachmentSlots > 0 else { didHitLimit = true; break }
            let filename = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let filetype = Self.mimeType(for: ext)

            guard let stableURL = Self.copyPickedFileToStableLocation(from: url, ext: ext) else { continue }
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: stableURL.path)[.size] as? Int) ?? 0

            let fileInfo = PickedFileInfo(url: stableURL, filename: filename, filesize: fileSize, filetype: filetype)
            pickedFiles.append(fileInfo)
            attachmentPreviewView.addFile(fileInfo)
        }
        if didHitLimit { notifyAttachmentLimitReached() }
        updatePreviewVisibility()
    }

    static func copyPickedFileToStableLocation(from url: URL, ext: String) -> URL? {
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mezon-uploads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var dest = dir.appendingPathComponent(UUID().uuidString)
            if !ext.isEmpty { dest.appendPathExtension(ext) }
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "SendMessageInputViewController.copyPickedFileToStableLocation",
                "filename": url.lastPathComponent,
            ])
            return nil
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    }
}
