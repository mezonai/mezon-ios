import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

final class SendMessageInputViewController: UIViewController {

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
    private var activeMentions: [(userId: Int64, displayName: String, range: NSRange)] = []
    private var mentionSuggestionView: MentionSuggestionView?
    private var mentionSuggestionHeightConstraint: NSLayoutConstraint?

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
    private static let inputBarPadding: CGFloat = 16 // top 8 + bottom 8

    private lazy var emojiButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
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
        v.overflowTarget = { [weak self] in self?.mentionSuggestionView }
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMentionSuggestion()
        setupBindings()
        setupThemeObserver()
        applyTheme()
        restoreFromCache()
        loadClanMembers()
    }

    func send() {
        let plainText = buildPlainTextFromAttributed()
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !pickedImages.isEmpty
        guard !trimmed.isEmpty || hasImages else { return }
        sendChannelMessage(text: trimmed, images: pickedImages, clanId: clanId, channel: channel)
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

    func clearText() { text = ""; textPipe.putNext("") }
    func updateText(_ newText: String) { text = newText; textPipe.putNext(newText) }

    private func openPhotoPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
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

            // Attachment preview
            attachmentPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            attachmentPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            attachmentPreviewView.topAnchor.constraint(equalTo: replyBannerView.bottomAnchor),

            inputBarView.topAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor),
            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight,
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
        sv.onSelectMember = { [weak self] member in
            self?.insertMention(member: member)
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

    private func loadClanMembers() {
        guard clanId != 0 else { return }
        if let clanUsers = context.engine.clanData.getClanUsers(clanId: clanId) {
            buildMentionMembers(from: clanUsers)
        } else {
            Task { @MainActor in
                guard let token = await context.getToken() else { return }
                do {
                    let response = try await context.account.network.listClanUsers(clanId: clanId, token: token)
                    buildMentionMembers(from: response)
                } catch {
                    AppLogger.network.warning("[MentionSuggestion] loadClanMembers failed: \(error)")
                }
            }
        }
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

    private func updateMentionSuggestions() {
        guard let keyword = detectMentionKeyword() else {
            hideMentionSuggestions()
            return
        }

        let filtered: [MentionMember]
        if keyword.isEmpty {
            filtered = allMentionMembers
        } else {
            let lower = keyword.lowercased()
            filtered = allMentionMembers.filter {
                $0.displayName.lowercased().contains(lower) ||
                $0.username.lowercased().contains(lower)
            }.sorted { a, b in
                let aStarts = a.displayName.lowercased().hasPrefix(lower) || a.username.lowercased().hasPrefix(lower)
                let bStarts = b.displayName.lowercased().hasPrefix(lower) || b.username.lowercased().hasPrefix(lower)
                if aStarts != bStarts { return aStarts }
                return a.displayName < b.displayName
            }
        }

        guard !filtered.isEmpty else {
            hideMentionSuggestions()
            return
        }
        showMentionSuggestions(members: filtered)
    }

    private func showMentionSuggestions(members: [MentionMember]) {
        guard let sv = mentionSuggestionView else { return }
        sv.update(members: members)
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

    private func insertMention(member: MentionMember) {
        guard let keyword = detectMentionKeyword() else { return }
        guard let selectedRange = textView.selectedTextRange else { return }
        let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)

        let fullText = textView.text ?? ""
        let textBefore = String(fullText.prefix(cursorOffset))
        guard let atIdx = textBefore.lastIndex(of: "@") else { return }
        let atIntIdx = textBefore.distance(from: textBefore.startIndex, to: atIdx)
        let replaceRange = NSRange(location: atIntIdx, length: cursorOffset - atIntIdx)

        let mentionText = "@\(member.displayName)"
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

        let mentionNSRange = NSRange(location: atIntIdx, length: mentionText.count)
        let lengthDelta = insertText.count - replaceRange.length
        activeMentions = activeMentions.map { m in
            if m.range.location >= replaceRange.location + replaceRange.length {
                return (m.userId, m.displayName, NSRange(location: m.range.location + lengthDelta, length: m.range.length))
            }
            return m
        }
        activeMentions.append((userId: member.userId, displayName: member.displayName, range: mentionNSRange))

        let newCursorPos = atIntIdx + insertText.count
        if let pos = textView.position(from: textView.beginningOfDocument, offset: newCursorPos) {
            textView.selectedTextRange = textView.textRange(from: pos, to: pos)
        }

        textView.typingAttributes = normalAttrs

        text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        updateTextViewHeight()
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
                        return (m.userId, m.displayName, NSRange(location: m.range.location - deletedLength, length: m.range.length))
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
                updateMentionSuggestions()
                return false // handled, don't let the default edit happen
            }
        }
        return true // no mention affected, proceed normally
    }

    private func buildPlainTextFromAttributed() -> String {
        return textView.text ?? ""
    }

    private func buildMentionList() -> [Mezon_Api_MessageMention] {
        return activeMentions.map { m in
            var mention = Mezon_Api_MessageMention()
            mention.userID = m.userId
            mention.s = Int32(m.range.location)
            mention.e = Int32(m.range.location + m.range.length)
            return mention
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyTheme()
    }

    deinit {
        disposables.dispose()
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
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

        if let sender = context.currentUser {
            let pendingRecord = MessageRecord.pending(localId: localId, text: text, channelId: channelIdStr, clanId: clanId, sender: sender)
            self.context.account.postbox.write { tx in tx.addMessages([pendingRecord]) }
        }

        let mentionList = buildMentionList()

        self.text = ""
        self.activeMentions = []
        textView.attributedText = nil
        textView.text = ""
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.theme.textStrong
        ]
        placeholderLabel.isHidden = false
        clearPickedImages()
        clearReply()
        hideMentionSuggestions()
        onSent?()

        let contentJSON: [String: Any] = text.isEmpty ? [:] : ["t": text]
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
                return MezonConstants.ChannelStreamMode.thread.rawValue // 6
            case MezonConstants.ChannelType.dm.rawValue:
                return MezonConstants.ChannelStreamMode.dm.rawValue // 4
            case MezonConstants.ChannelType.group.rawValue:
                return MezonConstants.ChannelStreamMode.group.rawValue // 3
            default:
                return clanId == 0
                    ? MezonConstants.ChannelStreamMode.group.rawValue // 3
                    : MezonConstants.ChannelStreamMode.channel.rawValue // 2
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
                self.context.account.postbox.write { tx in tx.deleteMessage(id: localId) }
                ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
            } catch {
                self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                ParsedAttachment.pendingImageCache.removeValue(forKey: localId)
                self.onError?(error.localizedDescription)
            }
        }
    }

    private func buildReplyRef() -> Mezon_Api_MessageRef? {
        guard let display = replyDisplay else { return nil }
        var ref = Mezon_Api_MessageRef()
        ref.messageID = 0
        ref.messageRefID = Int64(display.message.id) ?? 0
        ref.refType = 0 // reply
        ref.messageSenderID = Int64(display.message.senderId) ?? 0
        ref.messageSenderUsername = display.senderDisplayName
        ref.messageSenderDisplayName = display.senderDisplayName
        ref.mesagesSenderAvatar = display.avatarURL ?? ""
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
        updateMentionSuggestions()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateMentionSuggestions()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            send()
            return false
        }
        if !handleMentionProtection(range: range, replacementText: text) {
            return false
        }
        if !text.isEmpty && range.length == 0 {
            let insertLen = (text as NSString).length
            activeMentions = activeMentions.map { m in
                if m.range.location >= range.location {
                    return (m.userId, m.displayName, NSRange(location: m.range.location + insertLen, length: m.range.length))
                }
                return m
            }
        } else if text.isEmpty && range.length > 0 {
            activeMentions = activeMentions.map { m in
                if m.range.location >= range.location + range.length {
                    return (m.userId, m.displayName, NSRange(location: m.range.location - range.length, length: m.range.length))
                }
                return m
            }
        } else if !text.isEmpty && range.length > 0 {
            let delta = (text as NSString).length - range.length
            activeMentions = activeMentions.map { m in
                if m.range.location >= range.location + range.length {
                    return (m.userId, m.displayName, NSRange(location: m.range.location + delta, length: m.range.length))
                }
                return m
            }
        }
        return true
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

extension SendMessageInputViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        for result in results {
            let provider = result.itemProvider

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                    guard let url else { return }

                    let tempDir = FileManager.default.temporaryDirectory
                    let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: destURL)

                    let thumbnail = Self.generateVideoThumbnail(from: destURL)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let thumb = thumbnail {
                            let index = self.pickedImages.count
                            self.pickedImages.append(thumb)
                            self.attachmentPreviewView.addVideo(thumbnail: thumb)
                            self.pickedFileURLs[index] = destURL
                            self.saveToCache()
                            self.updatePreviewVisibility()
                        }
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
                    guard let url else { return }

                    let tempDir = FileManager.default.temporaryDirectory
                    let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: destURL)

                    guard let image = UIImage(contentsOfFile: destURL.path) else { return }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        let index = self.pickedImages.count
                        self.pickedImages.append(image)
                        self.attachmentPreviewView.addImage(image)
                        self.pickedFileURLs[index] = destURL
                        self.saveToCache()
                        self.updatePreviewVisibility()
                    }
                }
            }
        }
    }

    private static func generateVideoThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
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
    var overflowTarget: (() -> UIView?)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let target = overflowTarget?(), !target.isHidden {
            let converted = convert(point, to: target)
            if let hit = target.hitTest(converted, with: event) {
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }
}
