import UIKit
import AsyncDisplayKit

final class MessageReplyNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let avatarContainerNode = ASDisplayNode()
    private let avatarImageNode = ASNetworkImageNode()
    private let avatarPlaceholderNode = ASTextNode2()
    private let nameNode = ASTextNode2()
    private let previewNode = ASTextNode2()
    private let attachmentIconNode = ASImageNode()

    private var hasAttachment = false
    private var hasAvatar = false

    var onTapped: (() -> Void)?

    private var cachedIconSize = CGSize(width: 30, height: 10)
    private let avatarSz: CGFloat = 20
    private var cachedNameSize: CGSize = .zero
    private var cachedPreviewSize: CGSize = .zero
    private let attachmentIconSize = CGSize(width: 14, height: 14)
    private let leadingInset: CGFloat = 30.sw
    private let bottomInset: CGFloat = 6.sh

    override init() {
        super.init()

        iconNode.image = Self.replyIcon(tintColor: UIColor.theme.textDisabled)
        iconNode.contentMode = .scaleAspectFit
        addSubnode(iconNode)


        avatarContainerNode.cornerRadius = 10
        avatarContainerNode.clipsToBounds = true

        avatarImageNode.cornerRadius = 10
        avatarImageNode.clipsToBounds = true
        avatarImageNode.contentMode = .scaleAspectFill
        avatarImageNode.defaultImage = nil

        avatarPlaceholderNode.isLayerBacked = true

        nameNode.maximumNumberOfLines = 1
        addSubnode(nameNode)

        previewNode.maximumNumberOfLines = 1
        previewNode.truncationMode = .byTruncatingTail
        addSubnode(previewNode)

        attachmentIconNode.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
        attachmentIconNode.tintColor = UIColor.theme.textDisabled
        attachmentIconNode.contentMode = .scaleAspectFit
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTapped?()
    }

    func configure(ref: Mezon_Api_MessageRef) {
        let t = UIColor.theme
        let name = ref.messageSenderClanNick.isEmpty
            ? (ref.messageSenderDisplayName.isEmpty ? ref.messageSenderUsername : ref.messageSenderDisplayName)
            : ref.messageSenderClanNick
        let displayName = name.isEmpty ? "Anonymous" : name

        nameNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                .foregroundColor: t.textRoleLink
            ]
        )

        let isAnonymous = ref.messageSenderID == MezonConstants.anonymousUserId

        if isAnonymous {
            hasAvatar = true
            avatarPlaceholderNode.isHidden = true
            avatarImageNode.isHidden = false
            avatarImageNode.url = nil
            avatarImageNode.backgroundColor = UIColor.theme.tertiary
            
            if let raw = UIImage(named: "Chat/AnonymousIcon") {
                let size = CGSize(width: avatarSz, height: avatarSz)
                let format = UIGraphicsImageRendererFormat()
                format.scale = UIScreen.main.scale
                format.opaque = false
                let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    let tinted = raw.withRenderingMode(.alwaysTemplate).withTintColor(UIColor.theme.textStrong, renderingMode: .alwaysOriginal)
                    let iconSz = CGSize(width: 14, height: 14)
                    let origin = CGPoint(x: (size.width - iconSz.width) / 2, y: (size.height - iconSz.height) / 2)
                    tinted.draw(in: CGRect(origin: origin, size: iconSz))
                }
                avatarImageNode.image = img
            } else {
                avatarImageNode.image = nil
            }
            
            avatarContainerNode.removeFromSupernode()
            avatarPlaceholderNode.removeFromSupernode()
            if avatarImageNode.supernode == nil { addSubnode(avatarImageNode) }
        } else if !ref.messageSenderAvatar.isEmpty, let url = URL(string: ref.messageSenderAvatar) {
            hasAvatar = true
            avatarPlaceholderNode.isHidden = true
            avatarImageNode.isHidden = false
            avatarImageNode.url = url
            avatarImageNode.backgroundColor = UIColor.theme.primary
            avatarContainerNode.removeFromSupernode()
            avatarPlaceholderNode.removeFromSupernode()
            if avatarImageNode.supernode == nil { addSubnode(avatarImageNode) }
        } else {
            hasAvatar = false
            avatarImageNode.isHidden = true
            avatarPlaceholderNode.isHidden = false
            
            let charSource = ref.messageSenderUsername
            let charStr = String(charSource.prefix(1)).uppercased()
            
            avatarPlaceholderNode.attributedText = NSAttributedString(
                string: charStr,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10.sf, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
            )
            avatarContainerNode.backgroundColor = UIColor.avatarColor(for: charSource)
            avatarImageNode.removeFromSupernode()
            if avatarContainerNode.supernode == nil {
                addSubnode(avatarContainerNode)
                avatarContainerNode.addSubnode(avatarPlaceholderNode)
            }
        }

        if ref.hasAttachment_p {
            hasAttachment = true
            previewNode.isHidden = false
            previewNode.attributedText = NSAttributedString(
                string: "Tap to see attachment",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.textDisabled
                ]
            )
            if attachmentIconNode.supernode == nil { addSubnode(attachmentIconNode) }
        } else {
            hasAttachment = false
            attachmentIconNode.removeFromSupernode()
            let raw = ref.content
            let preview: String
            if raw.isEmpty {
                preview = ""
            } else if let data = raw.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let textVal = (json["t"] as? String) ?? (json["text"] as? String)
                if let s = textVal {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    preview = trimmed.isEmpty ? "" : (trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed)
                } else {
                    preview = ""
                }
            } else {
                preview = raw.count > 80 ? String(raw.prefix(80)) + "…" : raw
            }
            previewNode.isHidden = preview.isEmpty
            previewNode.attributedText = NSAttributedString(
                string: preview,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.textDisabled
                ]
            )
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let contentWidth = maxWidth - leadingInset
        let spacing: CGFloat = 6.sw
        let textSpacing: CGFloat = 4.sw

        cachedNameSize = nameNode.measure(CGSize(width: contentWidth * 0.4, height: 30))

        let remainW = contentWidth - cachedIconSize.width - spacing - avatarSz - spacing - cachedNameSize.width - textSpacing
            - (hasAttachment ? attachmentIconSize.width + textSpacing : 0)
        if previewNode.isHidden {
            cachedPreviewSize = .zero
        } else {
            cachedPreviewSize = previewNode.measure(CGSize(width: max(remainW, 50), height: 30))
        }

        let rowH = max(avatarSz, cachedNameSize.height, cachedPreviewSize.height)
        return CGSize(width: maxWidth, height: rowH + bottomInset)
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 6.sw
        let textSpacing: CGFloat = 4.sw
        var x = leadingInset

        let rowH = bounds.height - bottomInset
        let centerY = rowH / 2

        iconNode.frame = CGRect(x: x, y: centerY - cachedIconSize.height / 2, width: cachedIconSize.width, height: cachedIconSize.height)
        x += cachedIconSize.width + spacing

        if hasAvatar {
            avatarImageNode.frame = CGRect(x: x, y: centerY - avatarSz / 2, width: avatarSz, height: avatarSz)
        } else {
            avatarContainerNode.frame = CGRect(x: x, y: centerY - avatarSz / 2, width: avatarSz, height: avatarSz)
            let phSize = avatarPlaceholderNode.measure(CGSize(width: avatarSz, height: avatarSz))
            avatarPlaceholderNode.frame = CGRect(
                x: (avatarSz - phSize.width) / 2,
                y: (avatarSz - phSize.height) / 2,
                width: phSize.width, height: phSize.height
            )
        }
        x += avatarSz + spacing

        nameNode.frame = CGRect(x: x, y: centerY - cachedNameSize.height / 2, width: cachedNameSize.width, height: cachedNameSize.height)
        x += cachedNameSize.width + textSpacing

        if !previewNode.isHidden {
            previewNode.frame = CGRect(x: x, y: centerY - cachedPreviewSize.height / 2, width: cachedPreviewSize.width, height: cachedPreviewSize.height)
            x += cachedPreviewSize.width + textSpacing
        } else {
            previewNode.frame = .zero
        }

        if hasAttachment {
            attachmentIconNode.frame = CGRect(x: x, y: centerY - attachmentIconSize.height / 2, width: attachmentIconSize.width, height: attachmentIconSize.height)
        }
    }

    static func replyIcon(tintColor: UIColor) -> UIImage? {
        guard let pdfImage = UIImage(named: "Chat/IconReply") else { return nil }
        let size = CGSize(width: 60, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            tintColor.setFill()
            let rect = CGRect(origin: .zero, size: size)
            pdfImage.withRenderingMode(.alwaysTemplate).draw(in: rect)
            ctx.cgContext.setBlendMode(.sourceIn)
            ctx.cgContext.fill(rect)
        }
    }
}


final class MessageDeletedReplyNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let trashNode = ASImageNode()
    private let labelNode = ASTextNode2()

    private let iconSize = CGSize(width: 20, height: 20)
    private let trashSize = CGSize(width: 12, height: 12)
    private var cachedLabelSize: CGSize = .zero
    private let leadingInset: CGFloat = 30.sw

    override init() {
        super.init()

        let t = UIColor.theme
        iconNode.image = MessageReplyNode.replyIcon(tintColor: t.textDisabled)
        iconNode.contentMode = .scaleAspectFit
        addSubnode(iconNode)

        trashNode.image = UIImage(systemName: "trash")?.withRenderingMode(.alwaysTemplate)
        trashNode.tintColor = t.textDisabled
        trashNode.contentMode = .scaleAspectFit
        addSubnode(trashNode)

        labelNode.attributedText = NSAttributedString(
            string: "Original message was deleted",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.textDisabled
            ]
        )
        addSubnode(labelNode)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let spacing: CGFloat = 4.sw
        let contentW = maxWidth - leadingInset - iconSize.width - spacing - trashSize.width - spacing
        cachedLabelSize = labelNode.measure(CGSize(width: contentW, height: 30))
        let height = max(iconSize.height, trashSize.height, cachedLabelSize.height)
        return CGSize(width: maxWidth, height: height)
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 4.sw
        var x = leadingInset
        let centerY = bounds.height / 2

        iconNode.frame = CGRect(x: x, y: centerY - iconSize.height / 2, width: iconSize.width, height: iconSize.height)
        x += iconSize.width + spacing

        trashNode.frame = CGRect(x: x, y: centerY - trashSize.height / 2, width: trashSize.width, height: trashSize.height)
        x += trashSize.width + spacing

        labelNode.frame = CGRect(x: x, y: centerY - cachedLabelSize.height / 2, width: cachedLabelSize.width, height: cachedLabelSize.height)
    }
}
