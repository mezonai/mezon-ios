import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

final class SendMessageInputViewController: UIViewController {

    private let context: AccountContext
    private let channel: Mezon_Api_ChannelDescription
    private let clanId: Int64
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

    private static var channelAttachmentCache: [String: [UIImage]] = [:]

    private var cacheKey: String { "\(clanId)-\(channel.channelID)" }

    private(set) var pickedImages: [UIImage] = []
    private var pickedFileURLs: [Int: URL] = [:]

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

    private lazy var textField: UITextField = {
        let tf = UITextField()
        tf.borderStyle = .none
        tf.returnKeyType = .send
        tf.layer.cornerRadius = 20.swh
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16.sw, height: 1))
        tf.leftViewMode = .always
        tf.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 40.sw, height: 1))
        tf.rightViewMode = .always
        tf.delegate = self
        return tf
    }()

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

    private static let inputBarOnlyHeight: CGFloat = 56
    private static let previewHeight: CGFloat = AttachmentPreviewView.previewHeight

    var totalHeight: CGFloat {
        if pickedImages.isEmpty {
            return Self.inputBarOnlyHeight
        }
        return Self.inputBarOnlyHeight + Self.previewHeight
    }

    init(placeholder: String = "", channel: Mezon_Api_ChannelDescription, clanId: Int64, context: AccountContext) {
        self.placeholder = placeholder
        self.channel = channel
        self.clanId = clanId
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        setupThemeObserver()
        applyTheme()
        restoreFromCache()
    }

    func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !pickedImages.isEmpty
        guard !trimmed.isEmpty || hasImages else { return }
        sendChannelMessage(text: trimmed, images: pickedImages, clanId: clanId, channel: channel)
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

    private func removePickedImage(at index: Int) {
        guard index >= 0, index < pickedImages.count else { return }
        pickedImages.remove(at: index)
        attachmentPreviewView.removeImage(at: index)

        // Clean up temp file
        if let fileURL = pickedFileURLs[index] {
            try? FileManager.default.removeItem(at: fileURL)
        }
        // Re-index file URLs after removal
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
        guard previewHeightConstraint?.constant != targetH else { return }
        previewHeightConstraint?.constant = targetH
        onHeightChanged?(totalHeight)
        UIView.animate(withDuration: 0.25) {
            self.view.superview?.layoutIfNeeded()
        }
    }

    private func setupUI() {
        view.addSubview(attachmentPreviewView)
        view.addSubview(inputBarView)
        inputBarView.addSubview(attachButton)
        inputBarView.addSubview(textField)
        inputBarView.addSubview(emojiButton)
        inputBarView.addSubview(sendButton)

        let bottomConstraint = inputBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint

        let btnSize: CGFloat = 40.swh

        NSLayoutConstraint.activate([
            attachmentPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            attachmentPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            attachmentPreviewView.topAnchor.constraint(equalTo: view.topAnchor),

            inputBarView.topAnchor.constraint(equalTo: attachmentPreviewView.bottomAnchor),
            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarView.heightAnchor.constraint(equalToConstant: Self.inputBarOnlyHeight),
            bottomConstraint,

            attachButton.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 4.sw),
            attachButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: btnSize),
            attachButton.heightAnchor.constraint(equalToConstant: btnSize),

            textField.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4.sw),
            textField.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6.sw),
            textField.heightAnchor.constraint(equalToConstant: 40.sh),

            emojiButton.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: -8.sw),
            emojiButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            emojiButton.widthAnchor.constraint(equalToConstant: 28.swh),
            emojiButton.heightAnchor.constraint(equalToConstant: 28.swh),

            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -4.sw),
            sendButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: btnSize),
            sendButton.heightAnchor.constraint(equalToConstant: btnSize),
        ])

        let phc = attachmentPreviewView.heightAnchor.constraint(equalToConstant: 0)
        phc.isActive = true
        previewHeightConstraint = phc
    }

    private func setupBindings() {
        textField.placeholder = placeholder

        disposables.add(
            (textPipe.signal() |> deliverOnMainQueue).start(next: { [weak self] text in
                guard self?.textField.text != text else { return }
                self?.textField.text = text
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
        textField.backgroundColor = t.tertiary
        textField.textColor = t.textStrong
        textField.font = .systemFont(ofSize: 15.sf)
        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: t.textDisabled])
        attachButton.backgroundColor = t.tertiary
        attachButton.tintColor = t.textStrong
        emojiButton.tintColor = t.textDisabled
        attachmentPreviewView.applyTheme()
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
            print("✅ CDN [\(index)] \(filetype): \(cdnURL)")

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
        guard let token = context.session?.token else {
            onError?("No session")
            return
        }
        let localId = "pending-\(UUID().uuidString)"
        let channelIdStr = "\(channel.channelID)"

        let imagesToUpload = images
        let fileURLsToUpload = pickedFileURLs
        if !imagesToUpload.isEmpty {
            ParsedAttachment.pendingImageCache[localId] = imagesToUpload
        }

        if let sender = context.currentUser {
            let pendingRecord = MessageRecord.pending(localId: localId, text: text, channelId: channelIdStr, clanId: clanId, sender: sender)
            self.context.account.postbox.write { tx in tx.addMessages([pendingRecord]) }
        }

        self.text = ""
        textPipe.putNext("")
        clearPickedImages()
        onSent?()

        let contentJSON: [String: Any] = text.isEmpty ? [:] : ["t": text]
        let contentStr: String
        if let data = try? JSONSerialization.data(withJSONObject: contentJSON),
           let str = String(data: data, encoding: .utf8) {
            contentStr = str
        } else {
            contentStr = "{}"
        }

        let mode: Int32 = clanId == 0 ? (channel.type == MezonConstants.ChannelType.dm.rawValue ? 4 : 3) : 2
        let isPublic = channel.parentID != 0 ? false : (channel.channelPrivate == 0)
        let avatar: String = context.currentUser?.avatarURL?.absoluteString ?? ""

        Task { @MainActor in
            do {
                var uploadedAttachments: [Mezon_Api_MessageAttachment] = []
                if !imagesToUpload.isEmpty {
                    uploadedAttachments = try await self.uploadAttachments(imagesToUpload, fileURLs: fileURLsToUpload, token: token)
                    print("📎 Uploaded \(uploadedAttachments.count) attachments")
                    for att in uploadedAttachments {
                        print("   → \(att.url)")
                    }
                }

                _ = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: [],
                    attachments: uploadedAttachments,
                    references: [],
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: avatar,
                    topicId: 0,
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
}

extension SendMessageInputViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return true
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        updateText(textField.text ?? "")
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
