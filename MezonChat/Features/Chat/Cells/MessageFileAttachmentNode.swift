import UIKit
import AsyncDisplayKit

final class MessageFileAttachmentNode: ASDisplayNode {

    private var fileNodes: [FileItemNode] = []
    var onFileTapped: ((String) -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
    }

    func configure(files: [ParsedAttachment]) {
        fileNodes.removeAll()
        for (i, file) in files.enumerated() {
            let node = FileItemNode(attachment: file)
            node.tag = i
            node.onTapped = { [weak self] in
                self?.onFileTapped?(file.url)
            }
            fileNodes.append(node)
        }
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        guard !fileNodes.isEmpty else { return ASLayoutSpec() }
        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: 6,
            justifyContent: .start,
            alignItems: .start,
            children: fileNodes
        )
    }
}

private final class FileItemNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let bgNode = ASDisplayNode()

    var onTapped: (() -> Void)?
    var tag: Int = 0

    init(attachment: ParsedAttachment) {
        super.init()
        automaticallyManagesSubnodes = true

        let t = UIColor.theme

        bgNode.backgroundColor = t.secondaryLight
        bgNode.cornerRadius = 8

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iconNode.image = UIImage(systemName: Self.iconName(for: attachment), withConfiguration: iconConfig)?
            .withTintColor(.systemIndigo, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit

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
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTapped?()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        iconNode.style.preferredSize = CGSize(width: 30, height: 30)
        nameNode.style.flexShrink = 1
        nameNode.style.maxWidth = ASDimensionMake(constrainedSize.max.width * 0.7)

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, nameNode]
        )

        let insets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let insetSpec = ASInsetLayoutSpec(insets: insets, child: row)

        return ASBackgroundLayoutSpec(child: insetSpec, background: bgNode)
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
