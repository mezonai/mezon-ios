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

    var onTapped: (() -> Void)?
    var tag: Int = 0

    fileprivate(set) var cachedSize: CGSize = .zero
    private var cachedIconSize = CGSize(width: 30, height: 30)
    private var cachedNameSize: CGSize = .zero

    init(attachment: ParsedAttachment) {
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
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTapped?()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let insetH: CGFloat = 12
        let insetV: CGFloat = 10
        let spacing: CGFloat = 10
        let nameMaxW = maxWidth * 0.7 - cachedIconSize.width - spacing - insetH * 2

        cachedNameSize = nameNode.measure(CGSize(width: max(nameMaxW, 50), height: .greatestFiniteMagnitude))

        let contentW = insetH + cachedIconSize.width + spacing + cachedNameSize.width + insetH
        let contentH = insetV + max(cachedIconSize.height, cachedNameSize.height) + insetV

        cachedSize = CGSize(width: contentW, height: contentH)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let insetH: CGFloat = 12
        let spacing: CGFloat = 10

        bgNode.frame = bounds
        let centerY = bounds.height / 2

        let iconX = insetH
        iconNode.frame = CGRect(x: iconX, y: centerY - cachedIconSize.height / 2, width: cachedIconSize.width, height: cachedIconSize.height)

        let nameX = iconX + cachedIconSize.width + spacing
        nameNode.frame = CGRect(x: nameX, y: centerY - cachedNameSize.height / 2, width: cachedNameSize.width, height: cachedNameSize.height)
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
