import UIKit
import AsyncDisplayKit

final class MessageFileAttachmentNode: ASDisplayNode {

    private var fileNodes: [FileItemNode] = []
    var onFileTapped: ((String) -> Void)?

    override init() {
        super.init()
    }

    func configure(files: [ParsedAttachment]) {
        fileNodes.forEach { $0.removeFromSupernode() }
        fileNodes.removeAll()
        for (i, file) in files.enumerated() {
            let node = FileItemNode(attachment: file)
            node.tag = i
            node.onTapped = { [weak self] in
                self?.onFileTapped?(file.url)
            }
            fileNodes.append(node)
            addSubnode(node)
        }
    }

    static func estimatedMeasureSize(files: [ParsedAttachment], maxWidth: CGFloat) -> CGSize {
        guard !files.isEmpty else { return .zero }
        let rowH: CGFloat = 52
        let spacing: CGFloat = 6
        let h = CGFloat(files.count) * rowH + CGFloat(max(0, files.count - 1)) * spacing
        return CGSize(width: maxWidth, height: h)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !fileNodes.isEmpty else { return .zero }
        let spacing: CGFloat = 6
        var totalH: CGFloat = 0
        for (i, node) in fileNodes.enumerated() {
            let size = node.measureSize(maxWidth: maxWidth)
            _ = size
            if i > 0 { totalH += spacing }
            totalH += node.cachedSize.height
        }
        return CGSize(width: maxWidth, height: totalH)
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 6
        var y: CGFloat = 0
        for (i, node) in fileNodes.enumerated() {
            if i > 0 { y += spacing }
            node.frame = CGRect(x: 0, y: y, width: node.cachedSize.width, height: node.cachedSize.height)
            y += node.cachedSize.height
        }
    }
}

final class FileItemNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let bgNode = ASDisplayNode()
    private let spinnerNode: ASDisplayNode?
    private let progressLabelNode: ASTextNode2?
    private let showsUploadSpinner: Bool

    private static let spinnerSide: CGFloat = 24
    private static let spinnerLeadingGap: CGFloat = 8
    private static let progressLabelWidth: CGFloat = 40

    var onTapped: (() -> Void)?
    var tag: Int = 0

    fileprivate(set) var cachedSize: CGSize = .zero
    private var cachedIconSize = CGSize(width: 30, height: 30)
    private var cachedNameSize: CGSize = .zero

    init(attachment: ParsedAttachment) {
        let shows = attachment.isUploading
        let progress = attachment.uploadProgress
        let spinner: ASDisplayNode?
        let progressLabel: ASTextNode2?
        if shows {
            let s = ASDisplayNode()
            s.isUserInteractionEnabled = false
            s.setViewBlock {
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.color = UIColor.theme.text
                indicator.startAnimating()
                return indicator
            }
            s.style.preferredSize = CGSize(width: Self.spinnerSide, height: Self.spinnerSide)
            spinner = s

            if progress > 0 {
                let label = ASTextNode2()
                label.attributedText = NSAttributedString(
                    string: "\(Int(progress * 100))%",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                        .foregroundColor: UIColor.theme.textNormal,
                    ]
                )
                label.maximumNumberOfLines = 1
                progressLabel = label
            } else {
                progressLabel = nil
            }
        } else {
            spinner = nil
            progressLabel = nil
        }
        self.showsUploadSpinner = shows
        self.spinnerNode = spinner
        self.progressLabelNode = progressLabel
        super.init()

        let t = UIColor.theme

        bgNode.backgroundColor = t.secondaryLight
        bgNode.cornerRadius = 8
        addSubnode(bgNode)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iconNode.image = UIImage(systemName: Self.iconName(for: attachment), withConfiguration: iconConfig)?
            .withTintColor(.systemIndigo, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        addSubnode(iconNode)

        let filename = attachment.filename.isEmpty ? Self.fallbackFilename(from: attachment.url) : attachment.filename
        nameNode.attributedText = NSAttributedString(
            string: filename,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: t.text,
            ]
        )
        nameNode.maximumNumberOfLines = 2
        nameNode.truncationMode = .byTruncatingMiddle
        addSubnode(nameNode)

        if let spinner {
            addSubnode(spinner)
        }
        if let progressLabelNode {
            addSubnode(progressLabelNode)
        }
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        guard !showsUploadSpinner else { return }
        onTapped?()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let insetLeading: CGFloat = 14
        let insetTrailing: CGFloat = 14
        let insetV: CGFloat = 10
        let spacing: CGFloat = 10
        let progressReserve: CGFloat = progressLabelNode != nil ? Self.progressLabelWidth + Self.spinnerLeadingGap : 0
        let spinnerReserve: CGFloat = showsUploadSpinner ? Self.spinnerSide + Self.spinnerLeadingGap + progressReserve : 0
        let nameMaxW = maxWidth * 0.7 - cachedIconSize.width - spacing - insetLeading - insetTrailing - spinnerReserve

        cachedNameSize = nameNode.measure(CGSize(width: max(nameMaxW, 50), height: .greatestFiniteMagnitude))

        let contentW = insetLeading + cachedIconSize.width + spacing + cachedNameSize.width + spinnerReserve + insetTrailing
        let contentH = insetV + max(cachedIconSize.height, cachedNameSize.height, showsUploadSpinner ? Self.spinnerSide : 0) + insetV

        cachedSize = CGSize(width: contentW, height: contentH)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let insetLeading: CGFloat = 14
        let insetTrailing: CGFloat = 14
        let spacing: CGFloat = 10

        bgNode.frame = bounds
        let centerY = bounds.height / 2

        let iconX = insetLeading
        iconNode.frame = CGRect(x: iconX, y: centerY - cachedIconSize.height / 2, width: cachedIconSize.width, height: cachedIconSize.height)

        let nameX = iconX + cachedIconSize.width + spacing
        let spinnerW: CGFloat = showsUploadSpinner ? Self.spinnerSide : 0
        let gap: CGFloat = showsUploadSpinner ? Self.spinnerLeadingGap : 0
        let progressW: CGFloat = progressLabelNode != nil ? Self.progressLabelWidth : 0
        let progressGap: CGFloat = progressLabelNode != nil ? Self.spinnerLeadingGap : 0
        let nameAvailableW = bounds.width - nameX - insetTrailing - gap - spinnerW - progressGap - progressW
        let nameW = min(cachedNameSize.width, max(0, nameAvailableW))
        nameNode.frame = CGRect(x: nameX, y: centerY - cachedNameSize.height / 2, width: nameW, height: cachedNameSize.height)

        if let spinnerNode, showsUploadSpinner {
            let sx = bounds.width - insetTrailing - spinnerW
            spinnerNode.frame = CGRect(x: sx, y: centerY - spinnerW / 2, width: spinnerW, height: spinnerW)

            if let progressLabelNode {
                let px = sx - progressGap - progressW
                progressLabelNode.frame = CGRect(x: px, y: centerY - 9, width: progressW, height: 18)
            }
        }
    }

    private static func iconName(for attachment: ParsedAttachment) -> String {
        let ext = attachment.fileExtension.isEmpty
            ? (URL(string: attachment.url)?.pathExtension.lowercased() ?? "")
            : attachment.fileExtension

        switch ext {
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx", "csv":
            return "tablecells"
        case "ppt", "pptx":
            return "rectangle.split.3x3"
        case "zip", "rar", "7z", "tar", "gz":
            return "doc.zipper"
        case "txt", "rtf":
            return "doc.plaintext"
        case "mp3", "wav", "aac", "m4a", "ogg":
            return "music.note"
        default:
            return "doc"
        }
    }

    private static func fallbackFilename(from url: String) -> String {
        guard let urlObj = URL(string: url) else { return "File" }
        let name = urlObj.lastPathComponent
        return name.isEmpty ? "File" : name
    }
}
