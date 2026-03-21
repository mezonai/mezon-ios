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

    override init() {
        super.init()
        automaticallyManagesSubnodes = true

        iconNode.image = Self.replyIcon(tintColor: UIColor.theme.textDisabled)
        iconNode.contentMode = .scaleAspectFit

        avatarContainerNode.backgroundColor = .colorAvatarDefault
        avatarContainerNode.cornerRadius = 10
        avatarContainerNode.clipsToBounds = true

        avatarImageNode.cornerRadius = 10
        avatarImageNode.clipsToBounds = true
        avatarImageNode.contentMode = .scaleAspectFill
        avatarImageNode.defaultImage = nil

        avatarPlaceholderNode.isLayerBacked = true

        nameNode.maximumNumberOfLines = 1
        previewNode.maximumNumberOfLines = 1
        previewNode.truncationMode = .byTruncatingTail

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
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .semibold),
                .foregroundColor: t.textRoleLink
            ]
        )

        if !ref.mesagesSenderAvatar.isEmpty, let url = URL(string: ref.mesagesSenderAvatar) {
            hasAvatar = true
            avatarPlaceholderNode.isHidden = true
            avatarImageNode.isHidden = false
            avatarImageNode.url = url
        } else {
            hasAvatar = false
            avatarImageNode.isHidden = true
            avatarPlaceholderNode.isHidden = false
            avatarPlaceholderNode.attributedText = NSAttributedString(
                string: String((displayName).prefix(1)).uppercased(),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 8.sf, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
            )
        }

        if ref.hasAttachment_p {
            hasAttachment = true
            previewNode.attributedText = NSAttributedString(
                string: "Tap to see attachment",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13.sf),
                    .foregroundColor: t.textDisabled
                ]
            )
        } else {
            hasAttachment = false
            let raw = ref.content
            let preview: String
            if raw.isEmpty {
                preview = ""
            } else if let data = raw.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let textVal = json["t"] as? String, !textVal.isEmpty {
                preview = textVal.count > 80 ? String(textVal.prefix(80)) + "…" : textVal
            } else {
                preview = raw.count > 80 ? String(raw.prefix(80)) + "…" : raw
            }
            previewNode.attributedText = NSAttributedString(
                string: preview,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13.sf),
                    .foregroundColor: t.textDisabled
                ]
            )
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        iconNode.style.preferredSize = CGSize(width: 30, height: 10)
        let avatarSz: CGFloat = 20

        // Avatar: either image or placeholder letter on colored background
        let avatarSpec: ASLayoutElement
        if hasAvatar {
            avatarImageNode.style.preferredSize = CGSize(width: avatarSz, height: avatarSz)
            avatarSpec = avatarImageNode
        } else {
            avatarContainerNode.style.preferredSize = CGSize(width: avatarSz, height: avatarSz)
            let placeholderCenter = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: avatarPlaceholderNode)
            avatarSpec = ASBackgroundLayoutSpec(child: placeholderCenter, background: avatarContainerNode)
        }

        nameNode.style.flexShrink = 0
        previewNode.style.flexShrink = 1

        var textChildren: [ASLayoutElement] = [nameNode, previewNode]
        if hasAttachment {
            attachmentIconNode.style.preferredSize = CGSize(width: 14, height: 14)
            textChildren.append(attachmentIconNode)
        }

        let textRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 4.sw,
            justifyContent: .start,
            alignItems: .center,
            children: textChildren
        )
        textRow.style.flexShrink = 1

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 6.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, avatarSpec, textRow]
        )

        let insets = UIEdgeInsets(top: 0, left: 30.sw, bottom: 6.sh, right: 0)
        return ASInsetLayoutSpec(insets: insets, child: row)
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

// MARK: - Deleted Reply Node

final class MessageDeletedReplyNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let trashNode = ASImageNode()
    private let labelNode = ASTextNode2()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true

        let t = UIColor.theme
        iconNode.image = MessageReplyNode.replyIcon(tintColor: t.textDisabled)
        iconNode.contentMode = .scaleAspectFit

        trashNode.image = UIImage(systemName: "trash")?.withRenderingMode(.alwaysTemplate)
        trashNode.tintColor = t.textDisabled
        trashNode.contentMode = .scaleAspectFit

        labelNode.attributedText = NSAttributedString(
            string: "Original message was deleted",
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.textDisabled
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        iconNode.style.preferredSize = CGSize(width: 20, height: 20)
        trashNode.style.preferredSize = CGSize(width: 12, height: 12)

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 4.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, trashNode, labelNode]
        )

        let insets = UIEdgeInsets(top: 0, left: 30.sw, bottom: 0, right: 0)
        return ASInsetLayoutSpec(insets: insets, child: row)
    }
}
