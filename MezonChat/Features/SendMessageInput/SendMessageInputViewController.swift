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
    var range: NSRange
}

final class SendMessageInputViewController: UIViewController {

    private static let mentionHereUserId: Int64 = 1_775_731_111_020_111_321

    private let context: AccountContext
    private let channel: Mezon_Api_ChannelDescription
    private let clanId: Int64
    var topicId: Int64 = 0
    private var disposables = DisposableSet()

    private let textPipe = ValuePipe<String>()
    private let placeholderPipe = ValuePipe<String>()

    private(set) var text: String = ""
    var placeholder: String

    var onVoiceTapped: (() -> Void)?
    var onSent: (() -> Void)?
    var onError: ((String) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    var inputBarBottomConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    private var replyBannerHeightConstraint: NSLayoutConstraint?

    private(set) var replyDisplay: ChatMessageDisplay?
    private static let replyBannerHeight: CGFloat = 40

    private static var channelAttachmentCache: [String: [UIImage]] = [:]

    private var cacheKey: String { "\(clanId)-\(channel.channelID)" }

    private(set) var pickedImages: [UIImage] = []
    private var pickedFileURLs: [Int: URL] = [:]

    private var allMentionMembers: [MentionMember] = []
    private var allMentionSuggestionItems: [MentionSuggestionItem] = []
    private var activeMentions: [ComposerMention] = []
    private var activeHashtags: [ComposerHashtag] = []

    private var emojiIdByColonToken: [String: String] = [:]
    private var mentionSuggestionView: MentionSuggestionView?
    private var mentionSuggestionHeightConstraint: NSLayoutConstraint?

    private var allSuggestionEmojis: [CachedClanEmojiRecord] = []
    private var emojiSuggestionView: EmojiSuggestionView?
    private var emojiSuggestionHeightConstraint: NSLayoutConstraint?

    private var allHashtagChannelCandidates: [Mezon_Api_ChannelDescription] = []
    private var hashtagSuggestionView: HashtagSuggestionView?
    private var hashtagSuggestionHeightConstraint: NSLayoutConstraint?

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
        btn.addAction(UIAction { [weak self] _ in
            self?.clearReply()
        }, for: .touchUpInside)
        return btn
    }()

    private lazy var attachmentPreviewView: AttachmentPreviewView = {
        let v = AttachmentPreviewView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.clipsToBounds = true
        v.onRemove = { [weak self] index in
            self?.removePickedImage(at: index)
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

    private lazy var attachButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        btn.addAction(UIAction { [weak self] _ in self?.openPhotoPicker() }, for: .touchUpInside)
        return btn
    }()

    private lazy var textView: PastableTextView = {
        let tv = PastableTextView()
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 36)
        tv.textContainer.lineFragmentPadding = 0
        tv.layer.cornerRadius = 20.swh
        tv.clipsToBounds = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.returnKeyType = .send
        tv.enablesReturnKeyAutomatically = true
        tv.onImagesPasted = { [weak self] images in
            self?.handlePastedImages(images)
        }
        tv.onGIFPasted = { [weak self] data in
            self?.handlePastedGIF(data)
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
    private static let textViewMinHeight: CGFloat = 40
    private static let inputBarPadding: CGFloat = 16

    private(set) var isEmojiPickerVisible = false
    private var lastKeyboardHeight: CGFloat = 260
    var keyboardOverlayHeightEstimate: CGFloat { lastKeyboardHeight }
    var onToggleEmojiPicker: ((Bool, CGFloat) -> Void)?

    private lazy var emojiButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addAction(UIAction { [weak self] _ in self?.toggleEmojiPicker() }, for: .touchUpInside)
        return btn
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        btn.clipsToBounds = true
        btn.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        btn.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        return btn
    }()

    private static let previewHeight: CGFloat = AttachmentPreviewView.previewHeight

    private var inputBarCurrentHeight: CGFloat {
        return currentTextViewHeight + Self.inputBarPadding
    }

    var totalHeight: CGFloat {
        var h = inputBarCurrentHeight
        if !pickedImages.isEmpty {
            h += Self.previewHeight
        }
        if replyDisplay != nil {
            h += Self.replyBannerHeight
        }
        return h
    }

    private var currentTextViewHeight: CGFloat = textViewMinHeight

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
        restoreFromCache()
        loadClanMembers()
        bindMentionDataUpdates()
        reloadEmojiSuggestionList()
        reloadHashtagChannelCandidates()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEmojiListDidUpdate),
                                               name: Self.emojiListDidUpdateNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let bottomInset = view.safeAreaInsets.bottom
            lastKeyboardHeight = frame.height - bottomInset
        }
        if isEmojiPickerVisible {
            isEmojiPickerVisible = false
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 18.sf)
            emojiButton.setImage(UIImage(systemName: "face.smiling", withConfiguration: iconConfig), for: .normal)
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

    private func bindMentionDataUpdates() {
        disposables.add(
            (context.engine.clanData.clanUsersUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] updatedClanId in
                    guard let self, updatedClanId == self.clanId else { return }
                    if let clanUsers = self.context.engine.clanData.getClanUsers(clanId: self.clanId) {
                        self.buildMentionMembers(from: clanUsers)
                        self.rebuildMentionSuggestionItems()
                    }
                })
        )
        disposables.add(
            (context.engine.clanData.clanRolesUpdated.signal() |> deliverOnMainQueue)
                .start(next: { [weak self] updatedClanId in
                    guard let self, updatedClanId == self.clanId else { return }
                    self.rebuildMentionSuggestionItems()
                })
        )
    }

    func send() {
        let plainText = buildPlainTextFromAttributed()
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !pickedImages.isEmpty
        guard !trimmed.isEmpty || hasImages else { return }
        sendChannelMessage(text: trimmed, images: pickedImages, clanId: clanId, channel: channel)
    }


    func sendSticker(_ sticker: CachedClanStickerRecord) {
        let src = sticker.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageUrl = !src.isEmpty ? src : "\(MezonConfig.baseImgURL)/stickers/\(sticker.id).webp"

        var att = Mezon_Api_MessageAttachment()
        att.url = imageUrl
        att.filetype = "image/gif"
        att.filename = "\(sticker.id)"

        sendChannelMessageWithAttachments(text: "", attachments: [att])
    }


    func sendGif(url: String) {
        var att = Mezon_Api_MessageAttachment()
        att.url = url
        att.filetype = "image/gif"
        sendChannelMessageWithAttachments(text: "", attachments: [att])
    }

    func setReply(_ display: ChatMessageDisplay) {
        replyDisplay = display
        replyLabel.text = "Replying to \(display.senderDisplayName)"
        updateReplyBannerVisibility()
        textView.becomeFirstResponder()
    }

    func clearReply() {
        replyDisplay = nil
        updateReplyBannerVisibility()
    }

    private func updateReplyBannerVisibility() {
        let shouldShow = replyDisplay != nil
        let targetH: CGFloat = shouldShow ? Self.replyBannerHeight : 0
        let heightChanged = replyBannerHeightConstraint?.constant != targetH
        if heightChanged {
            replyBannerHeightConstraint?.constant = targetH
            onHeightChanged?(totalHeight)
        }
        UIView.animate(withDuration: 0.2) {
            self.view.superview?.layoutIfNeeded()
        }
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
    }
    func updateText(_ newText: String) { text = newText; textPipe.putNext(newText) }

    private func openPhotoPicker() {
        MediaPickerViewController.present(from: self) { [weak self] results in
            guard let self else { return }
            for result in results {
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

    private func toggleEmojiPicker() {
        isEmojiPickerVisible.toggle()

        if isEmojiPickerVisible {
            hideEmojiSuggestions()
            hideHashtagSuggestions()
            textView.resignFirstResponder()
            let collapsedH = max(lastKeyboardHeight, 260)
            onToggleEmojiPicker?(true, collapsedH)
        } else {
            onToggleEmojiPicker?(false, 0)
            DispatchQueue.main.async { [weak self] in
                self?.textView.becomeFirstResponder()
            }
        }

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18.sf)
        let iconName = isEmojiPickerVisible ? "keyboard" : "face.smiling"
        emojiButton.setImage(UIImage(systemName: iconName, withConfiguration: iconConfig), for: .normal)
    }


    private static func normalizedEmojiToken(from shortname: String) -> String {
        let inner = shortname.split(separator: ":").joined()
        guard !inner.isEmpty else { return "::" }
        return ":\(inner):"
    }

    func insertEmoji(_ emojiId: String, shortname: String) {
        applyEmojiInsertion(emojiId: emojiId, shortname: shortname, replaceRange: textView.selectedRange)
    }


    private func applyEmojiInsertion(emojiId: String, shortname: String, replaceRange: NSRange) {
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
        hideEmojiSuggestions()
    }

    private func insertEmojiFromSuggestion(_ emoji: CachedClanEmojiRecord) {
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
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18.sf)
        emojiButton.setImage(UIImage(systemName: "face.smiling", withConfiguration: iconConfig), for: .normal)
        DispatchQueue.main.async { [weak self] in
            self?.textView.becomeFirstResponder()
        }
    }

    private func addPickedImage(_ image: UIImage) {
        pickedImages.append(image)
        attachmentPreviewView.addImage(image)
        saveToCache()
        updatePreviewVisibility()
    }

    private func handlePastedImages(_ images: [UIImage]) {
        let tempDir = FileManager.default.temporaryDirectory
        for image in images {
            let filename = "pasted-\(UUID().uuidString).png"
            let fileURL = tempDir.appendingPathComponent(filename)
            guard let data = image.pngData() else { continue }
            do {
                try data.write(to: fileURL)
            } catch {
                continue
            }
            let index = pickedImages.count
            pickedImages.append(image)
            attachmentPreviewView.addImage(image)
            pickedFileURLs[index] = fileURL
        }
        saveToCache()
        updatePreviewVisibility()
    }

    private func handlePastedGIF(_ data: Data) {
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

    func clearPickedImages() {
        pickedImages.removeAll()
        attachmentPreviewView.removeAll()
        pickedFileURLs.removeAll()
        Self.channelAttachmentCache.removeValue(forKey: cacheKey)
        updatePreviewVisibility()
    }

    private func saveToCache() {
        if pickedImages.isEmpty {
            Self.channelAttachmentCache.removeValue(forKey: cacheKey)
        } else {
            Self.channelAttachmentCache[cacheKey] = pickedImages
        }
    }

    private func restoreFromCache() {
        guard let cached = Self.channelAttachmentCache[cacheKey], !cached.isEmpty else { return }
        pickedImages = cached
        attachmentPreviewView.setImages(cached)
        let targetH = Self.previewHeight
        previewHeightConstraint?.constant = targetH
        onHeightChanged?(totalHeight)
        view.layoutIfNeeded()
    }

    private func updatePreviewVisibility() {
        let shouldShow = !pickedImages.isEmpty
        let targetH = shouldShow ? Self.previewHeight : 0
        let heightChanged = previewHeightConstraint?.constant != targetH
        if heightChanged {
            previewHeightConstraint?.constant = targetH
            onHeightChanged?(totalHeight)
        }
        UIView.animate(withDuration: 0.25, animations: {
            self.view.superview?.layoutIfNeeded()
        }, completion: { _ in
            self.attachmentPreviewView.forceReload()
        })
    }

    private func setupUI() {
        replyBannerView.addSubview(replyLabel)
        replyBannerView.addSubview(replyCancelButton)
        view.addSubview(replyBannerView)

        view.addSubview(attachmentPreviewView)
        view.addSubview(inputBarView)
        inputBarView.addSubview(topSeparator)
        inputBarView.addSubview(attachButton)
        inputBarView.addSubview(textView)
        inputBarView.addSubview(placeholderLabel)
        inputBarView.addSubview(emojiButton)
        inputBarView.addSubview(sendButton)

        let bottomConstraint = inputBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint

        let btnSize: CGFloat = 40.swh

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

            inputBarView.topAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor),
            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight,

            topSeparator.topAnchor.constraint(equalTo: inputBarView.topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 0.5),
            bottomConstraint,

            attachButton.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 4.sw),
            attachButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            attachButton.widthAnchor.constraint(equalToConstant: btnSize),
            attachButton.heightAnchor.constraint(equalToConstant: btnSize),

            textView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4.sw),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6.sw),
            textView.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            tvHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),

            emojiButton.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -8.sw),
            emojiButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -6),
            emojiButton.widthAnchor.constraint(equalToConstant: 28.swh),
            emojiButton.heightAnchor.constraint(equalToConstant: 28.swh),

            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -4.sw),
            sendButton.bottomAnchor.constraint(equalTo: inputBarView.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: btnSize),
            sendButton.heightAnchor.constraint(equalToConstant: btnSize),
        ])

        let phc = attachmentPreviewView.heightAnchor.constraint(equalToConstant: 0)
        phc.isActive = true
        previewHeightConstraint = phc
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
        NSLayoutConstraint.activate([
            sv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: replyBannerView.topAnchor),
            hc,
        ])
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
        NSLayoutConstraint.activate([
            ev.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ev.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ev.bottomAnchor.constraint(equalTo: replyBannerView.topAnchor),
            hc,
        ])
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
        NSLayoutConstraint.activate([
            hv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hv.bottomAnchor.constraint(equalTo: replyBannerView.topAnchor),
            hc,
        ])
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
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    private func reloadEmojiSuggestionList() {
        let cache = context.engine.data.cachedEmojiList(clanId: 0)
        let emojis = cache?.emojis ?? []
        var seenIds = Set<Int64>()
        var seenNormShort = Set<String>()
        var unique: [CachedClanEmojiRecord] = []
        unique.reserveCapacity(emojis.count)
        for e in emojis {
            guard e.id != 0, !e.shortname.isEmpty else { continue }
            guard seenIds.insert(e.id).inserted else { continue }
            let norm = e.shortname.split(separator: ":").joined().lowercased()
            guard !norm.isEmpty, seenNormShort.insert(norm).inserted else { continue }
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

    private func loadClanMembers() {
        guard clanId != 0 else {
            allMentionMembers = []
            rebuildMentionSuggestionItems()
            return
        }
        if let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId) {
            buildMentionMembers(from: clanUsers)
            ensureRolesLoadedIfNeeded()
            rebuildMentionSuggestionItems()
        } else {
            Task { @MainActor in
                guard let token = await context.getToken() else { return }
                do {
                    let response = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                    buildMentionMembers(from: response)
                    ensureRolesLoadedIfNeeded()
                    rebuildMentionSuggestionItems()
                } catch {
                    AppLogger.network.warning("[MentionSuggestion] loadClanMembers failed: \(error)")
                }
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
                AppLogger.network.warning("[MentionSuggestion] listRoles failed: \(error)")
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

    private func buildMentionMembers(from clanUsers: Mezon_Api_ClanUserList) {
        var nickMap: [Int64: String] = [:]
        for cu in clanUsers.clanUsers where !cu.clanNick.isEmpty {
            nickMap[cu.user.id] = cu.clanNick
        }
        var seen = Set<Int64>()
        allMentionMembers = clanUsers.clanUsers.compactMap { cu in
            let user = cu.user
            guard seen.insert(user.id).inserted else { return nil }
            let nick = nickMap[user.id]
            let display = nick ?? (user.displayName.isEmpty ? user.username : user.displayName)
            return MentionMember(
                userId: user.id,
                displayName: display,
                username: user.username,
                avatarURL: cu.clanAvatar.isEmpty ? (user.avatarURL.isEmpty ? nil : user.avatarURL) : cu.clanAvatar
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
        let fullText = textView.text ?? ""
        guard cursorOffset > 0, cursorOffset <= fullText.count else { return nil }

        let textBefore = String(fullText.prefix(cursorOffset))

        for mention in activeMentions {
            if cursorOffset > mention.range.location && cursorOffset <= mention.range.location + mention.range.length {
                return nil
            }
        }

        guard let atIdx = textBefore.lastIndex(of: "@") else { return nil }
        let atIntIdx = textBefore.distance(from: textBefore.startIndex, to: atIdx)

        if atIntIdx > 0 {
            let charBefore = textBefore[textBefore.index(before: atIdx)]
            guard charBefore == " " || charBefore == "\n" else { return nil }
        }

        let keyword = String(textBefore[textBefore.index(after: atIdx)...])
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
        sv.update(items: items)
        sv.applyTheme()
        let h = sv.preferredHeight
        mentionSuggestionHeightConstraint?.constant = h
        sv.isHidden = false
        UIView.animate(withDuration: 0.15) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    private func hideMentionSuggestions() {
        guard let sv = mentionSuggestionView, !sv.isHidden else { return }
        mentionSuggestionHeightConstraint?.constant = 0
        sv.isHidden = true
        UIView.animate(withDuration: 0.15) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    private func updateEmojiSuggestions() {
        if allSuggestionEmojis.isEmpty {
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
        ev.update(items: items)
        ev.applyTheme()
        let h = ev.preferredHeight
        emojiSuggestionHeightConstraint?.constant = h
        ev.isHidden = false
        UIView.animate(withDuration: 0.15) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    private func hideEmojiSuggestions() {
        emojiSuggestionHeightConstraint?.constant = 0
        guard let ev = emojiSuggestionView, !ev.isHidden else { return }
        ev.isHidden = true
        UIView.animate(withDuration: 0.15) {
            self.view.superview?.layoutIfNeeded()
        }
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
        hv.update(items: items)
        hv.applyTheme()
        let h = hv.preferredHeight
        hashtagSuggestionHeightConstraint?.constant = h
        hv.isHidden = false
        UIView.animate(withDuration: 0.15) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    private func hideHashtagSuggestions() {
        hashtagSuggestionHeightConstraint?.constant = 0
        guard let hv = hashtagSuggestionView, !hv.isHidden else { return }
        hv.isHidden = true
        UIView.animate(withDuration: 0.15) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    private func insertMention(item: MentionSuggestionItem) {
        guard case .mention = dominantInlineCompletion() else { return }
        guard let selectedRange = textView.selectedTextRange else { return }
        let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)

        let fullText = textView.text ?? ""
        let textBefore = String(fullText.prefix(cursorOffset))
        guard let atIdx = textBefore.lastIndex(of: "@") else { return }
        let atIntIdx = textBefore.distance(from: textBefore.startIndex, to: atIdx)
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
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 15.sf),
            .foregroundColor: UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        ]

        let attrText = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
        let tagAttrStr = NSMutableAttributedString(string: token, attributes: tagAttrs)
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
        textView.text ?? ""
    }

    private static let emojiListDidUpdateNotification = Notification.Name("MezonEmojiListDidUpdate")


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
            if !h.channelLabel.isEmpty {
                dict["channelLabel"] = h.channelLabel
            }
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
            })
        )
    }

    private func setupThemeObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    @objc private func handleThemeChange() { applyTheme() }

    private func applyTheme() {
        let t = UIColor.theme
        inputBarView.backgroundColor = t.secondary
        topSeparator.backgroundColor = t.border
        textView.backgroundColor = t.tertiary
        textView.textColor = t.textStrong
        textView.font = .systemFont(ofSize: 15.sf)
        placeholderLabel.font = .systemFont(ofSize: 15.sf)
        placeholderLabel.textColor = t.textDisabled
        attachButton.backgroundColor = t.tertiary
        attachButton.tintColor = t.textStrong
        emojiButton.tintColor = t.textDisabled
        attachmentPreviewView.applyTheme()
        replyBannerView.backgroundColor = t.secondary
        replyLabel.textColor = t.textDisabled
        replyCancelButton.tintColor = t.textDisabled
        mentionSuggestionView?.applyTheme()
        emojiSuggestionView?.applyTheme()
        hashtagSuggestionView?.applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyTheme()
        reloadEmojiSuggestionList()
        reloadHashtagChannelCandidates()
    }

    deinit {
        disposables.dispose()
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: Self.emojiListDidUpdateNotification, object: nil)
    }


    private func uploadAttachments(_ images: [UIImage], fileURLs: [Int: URL], token: String) async throws -> [Mezon_Api_MessageAttachment] {
        var attachments: [Mezon_Api_MessageAttachment] = []

        for (index, image) in images.enumerated() {
            guard let fileURL = fileURLs[index] else { continue }
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }

            let originalFilename = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            let filetype = Self.mimeType(for: ext)

            let width = Int(image.size.width)
            let height = Int(image.size.height)

            let sanitizedFilename = originalFilename.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)

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

            if !filetype.hasPrefix("video/") {
                ImageCache.shared.setImage(image, data: fileData, forKey: cdnURL)
            }

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

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "heic", "heif": return "image/heic"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        case "m4v":         return "video/x-m4v"
        case "avi":         return "video/avi"
        default:            return "application/octet-stream"
        }
    }


    private func sendChannelMessage(text: String, images: [UIImage], clanId: Int64, channel: Mezon_Api_ChannelDescription) {
        let localId = "pending-\(UUID().uuidString)"
        let channelIdStr = topicId != 0 ? "topic-\(topicId)" : "\(channel.channelID)"

        let imagesToUpload = images
        let fileURLsToUpload = pickedFileURLs
        if !imagesToUpload.isEmpty {
            ParsedAttachment.pendingImageCache[localId] = imagesToUpload
        }

        let replyRef: Mezon_Api_MessageRef? = buildReplyRef()
        let built = ComposerContentPayloadBuilder.build(rawInput: text, emojiIdByColon: emojiIdByColonToken)
        let displayText = built.displayText
        let mentionList = buildMentionList(displayPlain: displayText)
        let hashtagListForContent = buildHashtagList(displayPlain: displayText)

        var contentJSON: [String: Any] = text.isEmpty ? [:] : ["t": displayText]
        if !text.isEmpty {
            if !built.mk.isEmpty {
                contentJSON["mk"] = built.mk
            }
            if !built.ej.isEmpty {
                contentJSON["ej"] = built.ej
            }
            if !hashtagListForContent.isEmpty {
                contentJSON["hg"] = hashtagListForContent
            }
        }
        let outgoingContentData = (try? JSONSerialization.data(withJSONObject: contentJSON)) ?? Data()

        if let sender = context.currentUser {
            let referencesData: Data = {
                guard let ref = replyRef else { return Data() }
                var list = Mezon_Api_MessageRefList()
                list.refs = [ref]
                return (try? list.serializedData()) ?? Data()
            }()

            let mentionsData: Data = {
                guard !mentionList.isEmpty else { return Data() }
                var list = Mezon_Api_MessageMentionList()
                list.mentions = mentionList
                return (try? list.serializedData()) ?? Data()
            }()

            let senderId = Int64(sender.id) ?? 0
            let clanMember = self.allMentionMembers.first(where: { $0.userId == senderId })

            let resolvedName: String = clanMember?.displayName
                ?? (sender.displayName.isEmpty ? sender.username : sender.displayName)
            let resolvedAvatar: String? = clanMember?.avatarURL
                ?? sender.avatarURL?.absoluteString

            let pendingRecord = MessageRecord.pending(
                localId: localId,
                text: displayText,
                channelId: channelIdStr,
                clanId: clanId,
                sender: sender,
                displayName: resolvedName,
                avatarURL: resolvedAvatar,
                referencesData: referencesData,
                mentionsData: mentionsData,
                contentData: outgoingContentData
            )
            self.context.account.postbox.write { tx in
                tx.addMessages([pendingRecord])
            }
        }

        self.text = ""
        self.activeMentions = []
        self.activeHashtags = []
        self.emojiIdByColonToken.removeAll()
        textView.attributedText = nil
        textView.text = ""
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.theme.textStrong
        ]
        placeholderLabel.isHidden = false
        textView.isScrollEnabled = false
        resetTextViewHeight()
        clearPickedImages()
        clearReply()
        hideMentionSuggestions()
        hideEmojiSuggestions()
        hideHashtagSuggestions()
        onSent?()

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

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                self.onError?("No session")
                return
            }
            do {
                var uploadedAttachments: [Mezon_Api_MessageAttachment] = []
                if !imagesToUpload.isEmpty {
                    uploadedAttachments = try await self.uploadAttachments(imagesToUpload, fileURLs: fileURLsToUpload, token: token)
                }

                _ = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: mentionList,
                    attachments: uploadedAttachments,
                    references: references,
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: avatar,
                    topicId: self.topicId,
                    token: token
                )
                self.context.account.postbox.write { tx in
                    let msgs = tx.getMessages(channelId: channelIdStr)
                    let pendingStillExists = msgs.contains { $0.id == localId }
                    if pendingStillExists {
                        tx.markMessageSent(id: localId)
                    } else {
                        ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                    }
                }
            } catch {
                self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                self.onError?(error.localizedDescription)
            }
        }
    }


    private func sendChannelMessageWithAttachments(text: String, attachments: [Mezon_Api_MessageAttachment]) {
        let replyRef = buildReplyRef()
        let references: [Mezon_Api_MessageRef] = replyRef.map { [$0] } ?? []
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

        clearReply()
        onSent?()

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.onError?("No session")
                return
            }
            do {
                _ = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: [],
                    attachments: attachments,
                    references: references,
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: avatar,
                    topicId: self.topicId,
                    token: token
                )
            } catch {
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
        ref.messageSenderUsername = display.senderDisplayName
        ref.messageSenderDisplayName = display.senderDisplayName
        ref.messageSenderAvatar = display.avatarURL ?? ""
        ref.hasAttachment_p = !display.attachments.isEmpty
        let contentJSON: [String: Any] = ["t": display.parsedContent.text]
        if let jsonData = try? JSONSerialization.data(withJSONObject: contentJSON),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            ref.content = jsonStr
        }
        return ref
    }
}

extension SendMessageInputViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        updateTextViewHeight()
        updateInlineSuggestions()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateInlineSuggestions()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            send()
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
                        range: NSRange(location: h.range.location + delta, length: h.range.length)
                    )
                }
                return h
            }
        }
        return true
    }

    private func resetTextViewHeight() {
        currentTextViewHeight = Self.textViewMinHeight
        textViewHeightConstraint?.constant = Self.textViewMinHeight
        inputBarHeightConstraint?.constant = Self.textViewMinHeight + Self.inputBarPadding
        onHeightChanged?(totalHeight)
        view.superview?.layoutIfNeeded()
    }

    private func updateTextViewHeight() {
        let font = textView.font ?? .systemFont(ofSize: 15.sf)
        let lineHeight = font.lineHeight
        let maxLines: CGFloat = 3
        let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let maxHeight = lineHeight * maxLines + verticalInsets
        let minHeight = Self.textViewMinHeight

        let fittingSize = CGSize(width: textView.frame.width - textView.textContainerInset.left - textView.textContainerInset.right, height: .greatestFiniteMagnitude)
        let textHeight = textView.sizeThatFits(fittingSize).height
        let newHeight = min(max(textHeight, minHeight), maxHeight)

        textView.isScrollEnabled = textHeight > maxHeight

        guard abs(newHeight - currentTextViewHeight) > 0.5 else { return }
        currentTextViewHeight = newHeight
        textViewHeightConstraint?.constant = newHeight
        inputBarHeightConstraint?.constant = newHeight + Self.inputBarPadding
        onHeightChanged?(totalHeight)
        UIView.animate(withDuration: 0.2) {
            self.view.superview?.layoutIfNeeded()
        }
    }
}


final class PastableTextView: UITextView {

    var onImagesPasted: (([UIImage]) -> Void)?
    var onGIFPasted: ((Data) -> Void)?

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

        if let images = pb.images, !images.isEmpty {
            onImagesPasted?(images)
            if let text = pb.string, !text.isEmpty {
                insertText(text)
            }
            return
        }

        if pb.hasImages, let image = pb.image {
            onImagesPasted?([image])
            return
        }

        super.paste(sender)
    }
}

private final class OverflowHitTestView: UIView {

    var overflowTargets: (() -> [UIView])?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for target in overflowTargets?() ?? [] where !target.isHidden {
            let converted = convert(point, to: target)
            if let hit = target.hitTest(converted, with: event) {
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }
}
