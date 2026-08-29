import UIKit

struct PickedFileInfo {
    let url: URL
    let filename: String
    let filesize: Int
    let filetype: String
}

struct RemoteAttachmentPreview {
    let url: String
    let filename: String
    let filetype: String
    let isVideo: Bool
}

final class AttachmentPreviewView: UIView {

    var onRemove: ((Int) -> Void)?

    private(set) var images: [UIImage] = []
    private(set) var videoIndices: Set<Int> = []
    private(set) var fileItems: [PickedFileInfo] = []
    private(set) var remoteImages: [RemoteAttachmentPreview] = []
    private(set) var remoteFiles: [RemoteAttachmentPreview] = []

    static let previewHeight: CGFloat = 110

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 14.sw
        layout.minimumLineSpacing = 14.sw
        layout.sectionInset = UIEdgeInsets(top: 9.sh, left: 14.sw, bottom: 9.sh, right: 20.sw)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        cv.delaysContentTouches = false
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(collectionView)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AttachmentThumbCell.self, forCellWithReuseIdentifier: AttachmentThumbCell.reuseId)
        collectionView.register(AttachmentFileCell.self, forCellWithReuseIdentifier: AttachmentFileCell.reuseId)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        disablesInteractiveTransitionGestureRecognizer = true
        collectionView.disablesInteractiveTransitionGestureRecognizer = true
        disablesInteractiveTransitionGestureRecognizerNow = { true }
        collectionView.disablesInteractiveTransitionGestureRecognizerNow = { true }
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        collectionView.reloadData()
    }

    func forceReload() {
        collectionView.reloadData()
    }

    func addImage(_ image: UIImage) {
        images.append(image)
        collectionView.reloadData()
    }

    func addVideo(thumbnail: UIImage) {
        let index = images.count
        images.append(thumbnail)
        videoIndices.insert(index)
        collectionView.reloadData()
    }

    func markAsVideo(at index: Int) {
        videoIndices.insert(index)
        collectionView.reloadData()
    }

    func addFile(_ file: PickedFileInfo) {
        fileItems.append(file)
        collectionView.reloadData()
    }

    func removeFile(at index: Int) {
        guard index >= 0, index < fileItems.count else { return }
        fileItems.remove(at: index)
        collectionView.reloadData()
    }

    func removeImage(at index: Int) {
        guard index >= 0, index < images.count else { return }
        images.remove(at: index)

        var newIndices: Set<Int> = []
        for vi in videoIndices where vi != index {
            newIndices.insert(vi > index ? vi - 1 : vi)
        }
        videoIndices = newIndices
        collectionView.reloadData()
    }

    func removeAll() {
        images.removeAll()
        videoIndices.removeAll()
        fileItems.removeAll()
        remoteImages.removeAll()
        remoteFiles.removeAll()
        collectionView.reloadData()
    }

    func setRemoteAttachments(images: [RemoteAttachmentPreview], files: [RemoteAttachmentPreview]) {
        self.remoteImages = images
        self.remoteFiles = files
        collectionView.reloadData()
    }

    func removeRemoteImage(at index: Int) {
        guard index >= 0, index < remoteImages.count else { return }
        remoteImages.remove(at: index)
        collectionView.reloadData()
    }

    func removeRemoteFile(at index: Int) {
        guard index >= 0, index < remoteFiles.count else { return }
        remoteFiles.remove(at: index)
        collectionView.reloadData()
    }

    var totalImageCount: Int { remoteImages.count + images.count }
    var totalFileCount: Int { remoteFiles.count + fileItems.count }

    var hasAnyAttachment: Bool {
        totalImageCount > 0 || totalFileCount > 0
    }

    var preferredPreviewHeight: CGFloat {
        Self.preferredHeight(imageCount: totalImageCount, fileCount: totalFileCount)
    }

    static func preferredHeight(imageCount: Int, fileCount: Int) -> CGFloat {
        guard imageCount > 0 || fileCount > 0 else { return 0 }
        let insetV = 9.sh * 2
        var maxRow: CGFloat = 0
        if imageCount > 0 { maxRow = max(maxRow, Self.imageItemRowHeight) }
        if fileCount > 0 { maxRow = max(maxRow, Self.fileItemRowHeight) }
        return insetV + maxRow
    }

    static var imageItemRowHeight: CGFloat { 80.sh }
    static var fileItemRowHeight: CGFloat { 56.sh }

    func setImages(_ newImages: [UIImage]) {
        images = newImages
        videoIndices.removeAll()
        collectionView.reloadData()
    }
}


extension AttachmentPreviewView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private var totalItemCount: Int {
        totalImageCount + totalFileCount
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        totalItemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = indexPath.item
        let remoteImageCount = remoteImages.count
        let localImageCount = images.count
        let remoteFileCount = remoteFiles.count

        if item < remoteImageCount {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentThumbCell.reuseId, for: indexPath) as! AttachmentThumbCell
            let remote = remoteImages[item]
            cell.configure(remoteURL: remote.url, isVideo: remote.isVideo)
            cell.onClose = { [weak self] in
                self?.onRemove?(item)
            }
            return cell
        }

        let afterRemoteImage = item - remoteImageCount
        if afterRemoteImage < localImageCount {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentThumbCell.reuseId, for: indexPath) as! AttachmentThumbCell
            let isVideo = videoIndices.contains(afterRemoteImage)
            cell.configure(image: images[afterRemoteImage], isVideo: isVideo)
            cell.onClose = { [weak self] in
                self?.onRemove?(item)
            }
            return cell
        }

        let afterImages = afterRemoteImage - localImageCount
        if afterImages < remoteFileCount {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentFileCell.reuseId, for: indexPath) as! AttachmentFileCell
            cell.configure(remoteFile: remoteFiles[afterImages])
            cell.onClose = { [weak self] in
                self?.onRemove?(item)
            }
            return cell
        }

        let fileIndex = afterImages - remoteFileCount
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentFileCell.reuseId, for: indexPath) as! AttachmentFileCell
        cell.configure(file: fileItems[fileIndex])
        cell.onClose = { [weak self] in
            self?.onRemove?(item)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if indexPath.item < totalImageCount {
            return CGSize(width: 70.sw, height: AttachmentPreviewView.imageItemRowHeight)
        } else {
            return CGSize(width: 220.sw, height: AttachmentPreviewView.fileItemRowHeight)
        }
    }
}


private final class AttachmentThumbCell: UICollectionViewCell {

    static let reuseId = "AttachmentThumbCell"

    var onClose: (() -> Void)?

    private var currentRemoteURL: String?

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 6
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let playOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        v.isHidden = true

        let config = MezonSymbolConfiguration(pointSize: 14, weight: .bold)
        let playIcon = UIImageView(image: UIImage.mezonSystemImage("play.fill", withConfiguration: config))
        playIcon.tintColor = .white
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: v.centerXAnchor, constant: 1),
            playIcon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    private lazy var closeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let config = MezonSymbolConfiguration(pointSize: 10, weight: .bold)
        btn.setImage(UIImage.mezonSystemImage("xmark", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.gray
        btn.layer.cornerRadius = 12
        btn.layer.borderWidth = 2
        btn.layer.borderColor = UIColor.theme.secondary.cgColor
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return btn
    }()

    @objc private func closeTapped() { onClose?() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = false
        clipsToBounds = false

        contentView.addSubview(thumbImageView)
        contentView.addSubview(playOverlay)
        contentView.addSubview(closeButton)

        let closeSize: CGFloat = 24
        let playSize: CGFloat = 32

        NSLayoutConstraint.activate([
            thumbImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            thumbImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: closeSize / 2),

            playOverlay.centerXAnchor.constraint(equalTo: thumbImageView.centerXAnchor),
            playOverlay.centerYAnchor.constraint(equalTo: thumbImageView.centerYAnchor),
            playOverlay.widthAnchor.constraint(equalToConstant: playSize),
            playOverlay.heightAnchor.constraint(equalToConstant: playSize),

            closeButton.widthAnchor.constraint(equalToConstant: closeSize),
            closeButton.heightAnchor.constraint(equalToConstant: closeSize),
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: closeSize / 2 - 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentRemoteURL = nil
        thumbImageView.image = nil
        playOverlay.isHidden = true
    }

    func configure(image: UIImage, isVideo: Bool = false) {
        currentRemoteURL = nil
        thumbImageView.image = image
        playOverlay.isHidden = !isVideo
    }

    func configure(remoteURL: String, isVideo: Bool) {
        let proxyURL = ImgproxyURL.attachmentURL(
            from: remoteURL,
            width: 200,
            height: 200,
            resizeType: "fill"
        )
        currentRemoteURL = proxyURL
        playOverlay.isHidden = !isVideo
        if let cached = ImageCache.shared.image(forKey: proxyURL) {
            thumbImageView.image = cached
            return
        }
        thumbImageView.image = nil
        ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
            guard let self, self.currentRemoteURL == proxyURL else { return }
            self.thumbImageView.image = image
        }
    }
}

private final class AttachmentFileCell: UICollectionViewCell {

    static let reuseId = "AttachmentFileCell"

    var onClose: (() -> Void)?

    private let containerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 8
        v.clipsToBounds = true
        return v
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .mezonCompatSystemIndigo
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 12.sf, weight: .medium)
        lbl.numberOfLines = 1
        lbl.lineBreakMode = .byTruncatingMiddle
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }()

    private let sizeLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 10.sf, weight: .regular)
        lbl.numberOfLines = 1
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.setContentCompressionResistancePriority(.required, for: .horizontal)
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        return lbl
    }()

    private lazy var closeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let config = MezonSymbolConfiguration(pointSize: 10, weight: .bold)
        btn.setImage(UIImage.mezonSystemImage("xmark", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.gray
        btn.layer.cornerRadius = 12
        btn.layer.borderWidth = 2
        btn.layer.borderColor = UIColor.theme.secondary.cgColor
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return btn
    }()

    @objc private func closeTapped() { onClose?() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = false
        clipsToBounds = false

        contentView.addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(sizeLabel)
        contentView.addSubview(closeButton)

        let closeSize: CGFloat = 24

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: closeSize / 2),

            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 6),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeLabel.leadingAnchor, constant: -6),

            sizeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            sizeLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: closeSize),
            closeButton.heightAnchor.constraint(equalToConstant: closeSize),
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: closeSize / 2 - 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(file: PickedFileInfo) {
        let iconConfig = MezonSymbolConfiguration(pointSize: 18, weight: .medium)
        iconImageView.image = UIImage.mezonSystemImage(Self.iconName(for: file.filename), withConfiguration: iconConfig)
        nameLabel.text = file.filename
        nameLabel.textColor = UIColor.theme.text
        sizeLabel.text = Self.formattedSize(file.filesize)
        sizeLabel.textColor = UIColor.theme.textDisabled
        containerView.backgroundColor = UIColor.theme.secondaryLight
    }

    func configure(remoteFile: RemoteAttachmentPreview) {
        let iconConfig = MezonSymbolConfiguration(pointSize: 18, weight: .medium)
        iconImageView.image = UIImage.mezonSystemImage(Self.iconName(for: remoteFile.filename), withConfiguration: iconConfig)
        nameLabel.text = remoteFile.filename.isEmpty ? remoteFile.url : remoteFile.filename
        nameLabel.textColor = UIColor.theme.text
        sizeLabel.text = ""
        sizeLabel.textColor = UIColor.theme.textDisabled
        containerView.backgroundColor = UIColor.theme.secondaryLight
    }

    private static func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":                             return "doc.richtext"
        case "doc", "docx":                     return "doc.text"
        case "xls", "xlsx", "csv":              return "tablecells"
        case "ppt", "pptx":                     return "rectangle.split.3x3"
        case "zip", "rar", "7z", "tar", "gz":   return "doc.zipper"
        case "txt", "rtf":                      return "doc.plaintext"
        case "mp3", "wav", "aac", "m4a", "ogg": return "music.note"
        default:                                return "doc"
        }
    }

    private static func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}
