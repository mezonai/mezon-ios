import UIKit
import AsyncDisplayKit

final class EmbedFormState {
    static let shared = EmbedFormState()
    private var state: [String: [String: String]] = [:]
    func setValue(_ value: String, forComponent componentId: String, messageId: String) {
        if state[messageId] == nil { state[messageId] = [:] }
        state[messageId]?[componentId] = value
    }
    func getValue(forComponent componentId: String, messageId: String) -> String? { return state[messageId]?[componentId] }
    func getJSONString(for messageId: String) -> String {
        guard let dict = state[messageId] else { return "{}" }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    func clear(messageId: String) { state.removeValue(forKey: messageId) }
    func removeAll() { state.removeAll() }
}

final class MessageEmbedNode: ASDisplayNode {

    private var embedNodes: [EmbedItemNode] = []
    private var cachedTotalSize: CGSize = .zero
    var onEmbedImageTapped: ((String) -> Void)?
    var onEmbedButtonTapped: ((ParsedEmbedButton, String) -> Void)?

    override init() {
        super.init()
    }

    func configure(embeds: [ParsedEmbed], messageId: String, isEphemeral: Bool) {
        embedNodes.forEach { $0.removeFromSupernode() }
        embedNodes = embeds.map { EmbedItemNode(embed: $0, messageId: messageId, isEphemeral: isEphemeral) }
        for node in embedNodes {
            node.onEmbedImageTapped = { [weak self] url in
                self?.onEmbedImageTapped?(url)
            }
            node.onButtonTapped = { [weak self] btn in
                self?.onEmbedButtonTapped?(btn, messageId)
            }
            addSubnode(node)
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !embedNodes.isEmpty else {
            cachedTotalSize = .zero
            return .zero
        }
        let spacing: CGFloat = 8
        var totalH: CGFloat = 0
        for (i, node) in embedNodes.enumerated() {
            if i > 0 { totalH += spacing }
            let sz = node.measureSize(maxWidth: maxWidth)
            _ = sz
            totalH += node.cachedSize.height
        }
        cachedTotalSize = CGSize(width: maxWidth, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 8
        var y: CGFloat = 0
        for (i, node) in embedNodes.enumerated() {
            if i > 0 { y += spacing }
            node.frame = CGRect(x: 0, y: y, width: node.cachedSize.width, height: node.cachedSize.height)
            y += node.cachedSize.height
        }
    }
}

final class EmbedItemNode: ASDisplayNode {

    private let colorBarNode = ASDisplayNode()
    private let contentBgNode = ASDisplayNode()
    private var authorIconNode: TransformImageNode?
    private var authorNameNode: ASTextNode2?
    private var titleNode: ASTextNode2?
    private var descriptionNode: ASTextNode2?
    private var descriptionRichNode: MessageTextContentNode?

    private struct FieldItemNodes {
        var nameNode: ASTextNode2?
        var valueTextNode: ASTextNode2?
        var valueRichNode: MessageTextContentNode?
        var inputNode: ASDisplayNode?
        var cachedNameSize: CGSize
        var cachedValueSize: CGSize
        var cachedInputSize: CGSize
    }
    private var fieldItems: [FieldItemNodes] = []
    private var actionButtonsNode: EmbedActionButtonsNode?
    private var cachedActionButtonsSize: CGSize = .zero
    private var imageNode: TransformImageNode?
    private var thumbnailNode: TransformImageNode?
    private var footerIconNode: TransformImageNode?
    private var footerTextNode: ASTextNode2?

    private let embed: ParsedEmbed
    private let messageId: String
    var onButtonTapped: ((ParsedEmbedButton) -> Void)?
    var onEmbedImageTapped: ((String) -> Void)?
    var onEmbedButtonTapped: ((ParsedEmbedButton, String) -> Void)?

    private static let colorBarWidth: CGFloat = 4
    private static let thumbnailSize: CGFloat = 50
    private static let contentInsetH: CGFloat = 10
    private static let contentInsetV: CGFloat = 10
    static let embedImageProxyDimension: Int = 200
    private static let embedImageMinDisplayHeight: CGFloat = 260
    private static let embedImageMaxDisplayHeight: CGFloat = 400

    fileprivate(set) var cachedSize: CGSize = .zero

    private var cachedAuthorIconSize: CGSize = .zero
    private var cachedAuthorNameSize: CGSize = .zero
    private var cachedTitleSize: CGSize = .zero
    private var cachedDescSize: CGSize = .zero
    
    private var cachedImageSize: CGSize = .zero
    private var cachedThumbSize: CGSize = .zero
    private var cachedFooterIconSize: CGSize = .zero
    private var cachedFooterTextSize: CGSize = .zero
    private var cachedContentColumnH: CGFloat = 0

    init(embed: ParsedEmbed, messageId: String, isEphemeral: Bool) {
        self.messageId = messageId
        self.embed = embed
        super.init()

        let t = UIColor.theme

        if let hex = embed.color, !hex.isEmpty {
            colorBarNode.backgroundColor = UIColor(embedHex: hex)
        } else {
            colorBarNode.backgroundColor = .systemIndigo
        }
        colorBarNode.cornerRadius = 2
        addSubnode(colorBarNode)

        contentBgNode.backgroundColor = t.secondaryLight
        contentBgNode.cornerRadius = 4
        insertSubnode(contentBgNode, at: 0)

        if let authorName = embed.authorName, !authorName.isEmpty {
            let node = ASTextNode2()
            node.attributedText = NSAttributedString(
                string: authorName,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: t.textStrong,
                ]
            )
            node.maximumNumberOfLines = 1
            authorNameNode = node
            addSubnode(node)

            if let iconURL = embed.authorIconURL, !iconURL.isEmpty {
                let icon = TransformImageNode()
                icon.setSignal(remoteImageSignal(url: iconURL, resizeMode: .fill), attemptSynchronously: false)
                let layout = icon.asyncLayout()
                let apply = layout(TransformImageArguments(
                    corners: ImageCorners(radius: 14),
                    imageSize: CGSize(width: 28, height: 28),
                    boundingSize: CGSize(width: 28, height: 28),
                    intrinsicInsets: .zero
                ))
                apply()
                authorIconNode = icon
                addSubnode(icon)
            }
        }

                if let title = embed.title, !title.isEmpty {
            let node = ASTextNode2()
            let attrs: [NSAttributedString.Key: Any]
            if embed.url != nil {
                attrs = [.font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
            } else {
                attrs = [.font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: t.textStrong]
            }
            node.attributedText = NSAttributedString(string: title, attributes: attrs)
            node.maximumNumberOfLines = 3
            titleNode = node
            addSubnode(node)
        }
        
        if let desc = embed.description, !desc.isEmpty {
            if Self.containsLocalCodeFence(desc) {
                let node = MessageTextContentNode()
                node.configure(parsedContent: MessageContentParser.parseLocalCodeBlocks(text: desc))
                descriptionRichNode = node
                addSubnode(node)
            } else {
                let node = ASTextNode2()
                node.attributedText = NSAttributedString(
                    string: desc,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 14),
                        .foregroundColor: t.text,
                    ]
                )
                node.maximumNumberOfLines = 10
                descriptionNode = node
                addSubnode(node)
            }
        }

        fieldItems = []
        for field in embed.fields {
            var nameNode: ASTextNode2? = nil
            if !field.name.isEmpty {
                let node = ASTextNode2()
                node.attributedText = NSAttributedString(
                    string: field.name,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: t.textStrong,
                    ]
                )
                node.maximumNumberOfLines = 0
                addSubnode(node)
                nameNode = node
            }

            var valueTextNode: ASTextNode2? = nil
            var valueRichNode: MessageTextContentNode? = nil
            if !field.value.isEmpty {
                if Self.containsLocalCodeFence(field.value) {
                    let node = MessageTextContentNode()
                    node.configure(parsedContent: MessageContentParser.parseLocalCodeBlocks(text: field.value))
                    valueRichNode = node
                    addSubnode(node)
                } else {
                    let node = ASTextNode2()
                    node.attributedText = NSAttributedString(
                        string: field.value,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 14),
                            .foregroundColor: t.text,
                        ]
                    )
                    node.maximumNumberOfLines = 0
                    addSubnode(node)
                    valueTextNode = node
                }
            }
            
            var iNode: ASDisplayNode? = nil
            if let inputComp = field.inputComponent {
                switch inputComp.type {
                case .input: iNode = EmbedInputFieldNode(component: inputComp, messageId: messageId)
                case .select: iNode = EmbedSelectFieldNode(component: inputComp, messageId: messageId)
                case .radio: iNode = EmbedRadioGroupNode(component: inputComp, messageId: messageId)
                case .datepicker: iNode = EmbedDatePickerFieldNode(component: inputComp, messageId: messageId)
                default: break
                }
                if let iNode { addSubnode(iNode) }
            }
            fieldItems.append(FieldItemNodes(
                nameNode: nameNode,
                valueTextNode: valueTextNode,
                valueRichNode: valueRichNode,
                inputNode: iNode,
                cachedNameSize: .zero,
                cachedValueSize: .zero,
                cachedInputSize: .zero
            ))
        }
        
        if !embed.actionRows.isEmpty {
            let abn = EmbedActionButtonsNode()
            abn.configure(actionRows: embed.actionRows)
            abn.onButtonTapped = { [weak self] btn in self?.onButtonTapped?(btn) }
            actionButtonsNode = abn
            addSubnode(abn)
        }


        if let imageURL = embed.imageURL, !imageURL.isEmpty {
            let node = TransformImageNode()
            node.contentAnimations = [.firstUpdate]
            let d = Self.embedImageProxyDimension
            let embedProxyURL = ImgproxyURL.attachmentURL(from: imageURL, width: d, height: d)
            let hasMem = ImageCache.shared.memoryImage(forKey: embedProxyURL) != nil
            node.setSignal(remoteImageSignal(url: embedProxyURL, resizeMode: .fillLeading), attemptSynchronously: hasMem)
            imageNode = node
            addSubnode(node)
        }

        if let thumbURL = embed.thumbnailURL, !thumbURL.isEmpty {
            let node = TransformImageNode()
            let thumbProxy = ImgproxyURL.attachmentURL(from: thumbURL, width: Int(Self.thumbnailSize) * Int(UIScreen.main.scale), height: Int(Self.thumbnailSize) * Int(UIScreen.main.scale), resizeType: "fill")
            let hasThumbMem = ImageCache.shared.memoryImage(forKey: thumbProxy) != nil
            node.setSignal(remoteImageSignal(url: thumbProxy, resizeMode: .fill), attemptSynchronously: hasThumbMem)
            let layout = node.asyncLayout()
            let apply = layout(TransformImageArguments(
                corners: ImageCorners(radius: 4),
                imageSize: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize),
                boundingSize: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize),
                intrinsicInsets: .zero
            ))
            apply()
            thumbnailNode = node
            addSubnode(node)
        }

        if let footerText = embed.footerText, !footerText.isEmpty {
            let node = ASTextNode2()
            var text = footerText
            if let ts = embed.timestamp, !ts.isEmpty {
                let dateStr = Self.formatTimestamp(ts)
                if !dateStr.isEmpty { text += " • \(dateStr)" }
            }
            node.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: t.text,
                ]
            )
            node.maximumNumberOfLines = 1
            footerTextNode = node
            addSubnode(node)

            if let iconURL = embed.footerIconURL, !iconURL.isEmpty {
                let icon = TransformImageNode()
                icon.setSignal(remoteImageSignal(url: iconURL, resizeMode: .fill), attemptSynchronously: false)
                let layout = icon.asyncLayout()
                let apply = layout(TransformImageArguments(
                    corners: ImageCorners(radius: 12),
                    imageSize: CGSize(width: 24, height: 24),
                    boundingSize: CGSize(width: 24, height: 24),
                    intrinsicInsets: .zero
                ))
                apply()
                footerIconNode = icon
                addSubnode(icon)
            }
        }
    }

    override func didLoad() {
        super.didLoad()
        if let imageNode {
            imageNode.isUserInteractionEnabled = true
            imageNode.view.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleEmbedMainImageTap))
            imageNode.view.addGestureRecognizer(tap)
        }
        if let thumbnailNode {
            thumbnailNode.isUserInteractionEnabled = true
            thumbnailNode.view.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleEmbedThumbnailTap))
            thumbnailNode.view.addGestureRecognizer(tap)
        }
        if let titleNode, embed.url != nil {
            titleNode.isUserInteractionEnabled = true
            titleNode.view.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTitleTap))
            titleNode.view.addGestureRecognizer(tap)
        }
    }

    @objc private func handleTitleTap() {
        guard let urlStr = embed.url, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func handleEmbedMainImageTap() {
        guard let url = embed.imageURL, !url.isEmpty else { return }
        onEmbedImageTapped?(url)
    }

    @objc private func handleEmbedThumbnailTap() {
        guard let url = embed.thumbnailURL, !url.isEmpty else { return }
        onEmbedImageTapped?(url)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let barW = Self.colorBarWidth
        let inH = Self.contentInsetH
        let inV = Self.contentInsetV
        let spacing: CGFloat = 10

        let thumbW = thumbnailNode != nil ? Self.thumbnailSize + 10 : 0
        let contentMaxW = maxWidth - barW - inH * 2 - thumbW

        var contentH: CGFloat = 0


        if let authorNameNode {
            cachedAuthorNameSize = authorNameNode.measure(CGSize(width: contentMaxW - 36, height: 30))
            cachedAuthorIconSize = authorIconNode != nil ? CGSize(width: 28, height: 28) : .zero
            let rowH = max(cachedAuthorIconSize.height, cachedAuthorNameSize.height)
            contentH += rowH + spacing
        }



        if let titleNode {
            cachedTitleSize = titleNode.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
            contentH += cachedTitleSize.height + spacing
        }

        if let descriptionNode {
            cachedDescSize = descriptionNode.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
            contentH += cachedDescSize.height + spacing
        } else if let descriptionRichNode {
            cachedDescSize = descriptionRichNode.measureSize(maxWidth: contentMaxW)
            contentH += cachedDescSize.height + spacing
        }

        for i in 0..<fieldItems.count {
            if let nNode = fieldItems[i].nameNode {
                fieldItems[i].cachedNameSize = nNode.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
                contentH += fieldItems[i].cachedNameSize.height + 2
            }
            if let vNode = fieldItems[i].valueTextNode {
                fieldItems[i].cachedValueSize = vNode.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
                contentH += fieldItems[i].cachedValueSize.height + spacing
            } else if let rich = fieldItems[i].valueRichNode {
                fieldItems[i].cachedValueSize = rich.measureSize(maxWidth: contentMaxW)
                contentH += fieldItems[i].cachedValueSize.height + spacing
            }
            if let iNode = fieldItems[i].inputNode as? EmbedFormInputNode {
                fieldItems[i].cachedInputSize = iNode.measureSize(maxWidth: contentMaxW)
                contentH += fieldItems[i].cachedInputSize.height + spacing
            }
        }


        if let footerTextNode {
            cachedFooterTextSize = footerTextNode.measure(CGSize(width: contentMaxW - 30, height: 30))
            cachedFooterIconSize = footerIconNode != nil ? CGSize(width: 24, height: 24) : .zero
            let rowH = max(cachedFooterIconSize.height, cachedFooterTextSize.height)
            contentH += rowH + spacing
        }

        if contentH > 0 { contentH -= spacing }
        cachedContentColumnH = contentH


        cachedThumbSize = thumbnailNode != nil ? CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize) : .zero
        let mainRowH = max(contentH, cachedThumbSize.height)

        var totalH = inV + mainRowH + inV


        if let imageNode {
            let imgContentW = maxWidth - barW - inH * 2
            let finalW = max(imgContentW, 100)
            let metaW = max(CGFloat(embed.imageWidth ?? 400), 1)
            let metaH = max(CGFloat(embed.imageHeight ?? 200), 1)
            let aspect = metaW / metaH
            var finalH = floor(finalW / aspect)
            finalH = min(Self.embedImageMaxDisplayHeight, max(Self.embedImageMinDisplayHeight, finalH))
            cachedImageSize = CGSize(width: finalW, height: finalH)

            let args = TransformImageArguments(
                corners: ImageCorners(radius: 4),
                imageSize: cachedImageSize,
                boundingSize: cachedImageSize,
                intrinsicInsets: .zero
            )
            let layout = imageNode.asyncLayout()
            let apply = layout(args)
            apply()

            totalH += 8 + finalH
        }

        if let abn = actionButtonsNode { cachedActionButtonsSize = abn.measureSize(maxWidth: maxWidth); totalH += 8 + cachedActionButtonsSize.height }
        cachedSize = CGSize(width: maxWidth, height: totalH)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let barW = Self.colorBarWidth
        let inH = Self.contentInsetH
        let inV = Self.contentInsetV
        let spacing: CGFloat = 10
        let w = bounds.width
        let h = bounds.height

        let hasButtons = actionButtonsNode != nil; let embedBoxHeight = hasButtons ? bounds.height - 8 - cachedActionButtonsSize.height : bounds.height; contentBgNode.frame = CGRect(x: 0, y: 0, width: w, height: embedBoxHeight)
        colorBarNode.frame = CGRect(x: 0, y: 0, width: barW, height: embedBoxHeight)
        if let abn = actionButtonsNode { abn.frame = CGRect(x: 0, y: embedBoxHeight + 8, width: cachedActionButtonsSize.width, height: cachedActionButtonsSize.height) }

        var y = inV
        let contentX = barW + inH

        let thumbW = thumbnailNode != nil ? Self.thumbnailSize + 10 : 0
        let contentMaxW = w - barW - inH * 2 - thumbW

        if let authorNameNode {
            var ax = contentX
            if let authorIconNode {
                authorIconNode.frame = CGRect(x: ax, y: y, width: cachedAuthorIconSize.width, height: cachedAuthorIconSize.height)
                ax += cachedAuthorIconSize.width + 8
            }
            let rowH = max(cachedAuthorIconSize.height, cachedAuthorNameSize.height)
            authorNameNode.frame = CGRect(x: ax, y: y + (rowH - cachedAuthorNameSize.height) / 2, width: cachedAuthorNameSize.width, height: cachedAuthorNameSize.height)
            y += rowH + spacing
        }

        if let titleNode {
            titleNode.frame = CGRect(x: contentX, y: y, width: cachedTitleSize.width, height: cachedTitleSize.height)
            y += cachedTitleSize.height + spacing
        }

        if let descriptionNode {
            descriptionNode.frame = CGRect(x: contentX, y: y, width: cachedDescSize.width, height: cachedDescSize.height)
            y += cachedDescSize.height + spacing
        } else if let descriptionRichNode {
            descriptionRichNode.frame = CGRect(x: contentX, y: y, width: contentMaxW, height: cachedDescSize.height)
            y += cachedDescSize.height + spacing
        }

        for item in fieldItems {
            if let nNode = item.nameNode {
                nNode.frame = CGRect(x: contentX, y: y, width: item.cachedNameSize.width, height: item.cachedNameSize.height)
                y += item.cachedNameSize.height + 2
            }
            if let vNode = item.valueTextNode {
                vNode.frame = CGRect(x: contentX, y: y, width: item.cachedValueSize.width, height: item.cachedValueSize.height)
                y += item.cachedValueSize.height + spacing
            } else if let rich = item.valueRichNode {
                rich.frame = CGRect(x: contentX, y: y, width: contentMaxW, height: item.cachedValueSize.height)
                y += item.cachedValueSize.height + spacing
            }
            if let iNode = item.inputNode {
                iNode.frame = CGRect(x: contentX, y: y, width: item.cachedInputSize.width, height: item.cachedInputSize.height)
                y += item.cachedInputSize.height + spacing
            }
        }


        if let footerTextNode {
            var fx = contentX
            if let footerIconNode {
                footerIconNode.frame = CGRect(x: fx, y: y, width: cachedFooterIconSize.width, height: cachedFooterIconSize.height)
                fx += cachedFooterIconSize.width + 6
            }
            let rowH = max(cachedFooterIconSize.height, cachedFooterTextSize.height)
            footerTextNode.frame = CGRect(x: fx, y: y + (rowH - cachedFooterTextSize.height) / 2, width: cachedFooterTextSize.width, height: cachedFooterTextSize.height)
            y += rowH + spacing
        }


        if let thumbnailNode {
            thumbnailNode.frame = CGRect(x: w - inH - Self.thumbnailSize, y: inV, width: Self.thumbnailSize, height: Self.thumbnailSize)
        }

        if let imageNode {
            imageNode.frame = CGRect(x: contentX, y: y + 2, width: cachedImageSize.width, height: cachedImageSize.height)
        }
    }

    private static func formatTimestamp(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: ts) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: ts) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        return ""
    }

    private static func containsLocalCodeFence(_ text: String) -> Bool {
        text.contains("```")
    }
}

private extension UIColor {
    convenience init(embedHex hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }

        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        let r, g, b: CGFloat
        if hex.count == 6 {
            r = CGFloat((rgb >> 16) & 0xFF) / 255
            g = CGFloat((rgb >> 8) & 0xFF) / 255
            b = CGFloat(rgb & 0xFF) / 255
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

protocol EmbedFormInputNode: ASDisplayNode {
    func measureSize(maxWidth: CGFloat) -> CGSize
}

final class EmbedInputFieldNode: ASDisplayNode, EmbedFormInputNode, UITextFieldDelegate {
    private let textField = UITextField()
    private let component: ParsedEmbedInputComponent
    private let messageId: String
    private var cachedSize: CGSize = .zero
    private static let cornerRadius: CGFloat = 8

    init(component: ParsedEmbedInputComponent, messageId: String) {
        self.component = component
        self.messageId = messageId
        super.init()
        
        let t = UIColor.theme
        backgroundColor = t.primary
        cornerRadius = Self.cornerRadius
        borderWidth = 1
        borderColor = t.border.withAlphaComponent(0.5).cgColor
        clipsToBounds = true

        if let placeholder = component.placeholder {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: t.textDisabled]
            )
        }
        textField.font = UIFont.systemFont(ofSize: 15)
        textField.textColor = UIColor.theme.textStrong
        textField.delegate = self
        textField.returnKeyType = .done
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        if let existing = EmbedFormState.shared.getValue(forComponent: component.id, messageId: messageId) {
            textField.text = existing
        } else if let def = component.defaultValue, !def.isEmpty {
            textField.text = def
            EmbedFormState.shared.setValue(def, forComponent: component.id, messageId: messageId)
        }
        
        let wrapper = ASDisplayNode { [weak self] in return self?.textField ?? UIView() }
        addSubnode(wrapper)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        cachedSize = CGSize(width: maxWidth, height: 40)
        return cachedSize
    }

    override func layout() {
        super.layout()
        if let wrapper = subnodes?.first {
            wrapper.frame = CGRect(x: 10, y: 0, width: bounds.width - 20, height: bounds.height)
        }
    }

    @objc private func textChanged() {
        EmbedFormState.shared.setValue(textField.text ?? "", forComponent: component.id, messageId: messageId)
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class EmbedSelectFieldNode: ASDisplayNode, EmbedFormInputNode {
    private let component: ParsedEmbedInputComponent
    private let messageId: String
    private var cachedSize: CGSize = .zero
    private let button = UIButton(type: .system)
    private let chevronNode = ASImageNode()
    private let buttonWrapperNode = ASDisplayNode()
    private var currentSheetController: EmbedSelectSheetController?
    private static let cornerRadius: CGFloat = 8

    init(component: ParsedEmbedInputComponent, messageId: String) {
        self.component = component
        self.messageId = messageId
        super.init()
        let t = UIColor.theme
        backgroundColor = t.primary
        cornerRadius = Self.cornerRadius
        borderWidth = 1
        borderColor = t.border.withAlphaComponent(0.5).cgColor

        chevronNode.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?.withRenderingMode(.alwaysTemplate)
        chevronNode.tintColor = t.textStrong
        chevronNode.contentMode = .scaleAspectFit
        chevronNode.isUserInteractionEnabled = false
        addSubnode(chevronNode)
        let placeholderText: String
        if let ph = component.placeholder, !ph.isEmpty, !ph.allSatisfy({ $0.isNumber }) {
            placeholderText = ph
        } else {
            placeholderText = "dd/mm/yyyy"
        }
        button.setTitle(placeholderText, for: .normal)
        button.contentHorizontalAlignment = .left
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.setTitleColor(t.textDisabled, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        buttonWrapperNode.setViewBlock({ [weak self] in
            return self?.button ?? UIView()
        })
        addSubnode(buttonWrapperNode)
        if let existing = EmbedFormState.shared.getValue(forComponent: component.id, messageId: messageId), !existing.isEmpty, isValidSelectValue(existing) {
            applySelected(value: existing, fallbackLabel: existing)
        } else if let existing = EmbedFormState.shared.getValue(forComponent: component.id, messageId: messageId), !existing.isEmpty, !isValidSelectValue(existing) {
            EmbedFormState.shared.clear(messageId: messageId)
        } else if let selected = component.selectedValue {
            applySelected(value: selected.value, fallbackLabel: selected.label)
        } else if let def = component.defaultValue, !def.isEmpty, isValidSelectValue(def) {
            applySelected(value: def, fallbackLabel: def)
        } else {
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        cachedSize = CGSize(width: maxWidth, height: 40)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let chevronSize = CGSize(width: 12, height: 12)
        chevronNode.frame = CGRect(x: bounds.width - chevronSize.width - 10, y: (bounds.height - chevronSize.height) / 2, width: chevronSize.width, height: chevronSize.height)
        buttonWrapperNode.frame = bounds
        button.frame = bounds
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 30)
    }

    @objc private func tapped() {
        guard let vc = findViewController() as? ViewController else { return }
        let options = component.selectOptions ?? []
        guard !options.isEmpty else { return }
        let sheet = EmbedSelectSheetController(options: options) { [weak self] selected in
            guard let self = self else {
                return
            }
            self.applySelected(value: selected.value, fallbackLabel: selected.label)
            self.currentSheetController = nil
        }
        currentSheetController = sheet
        vc.presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func applySelected(value: String, fallbackLabel: String) {
        let label = (component.selectOptions ?? []).first(where: { $0.value == value })?.label ?? (fallbackLabel.allSatisfy({ $0.isNumber }) ? component.placeholder ?? "Select..." : fallbackLabel)
        button.setTitle(label, for: .normal)
        button.setTitleColor(UIColor.theme.textStrong, for: .normal)
        button.setNeedsLayout()
        button.layoutIfNeeded()
        buttonWrapperNode.setNeedsLayout()
        buttonWrapperNode.setNeedsDisplay()
        setNeedsLayout()
        setNeedsDisplay()
        if isNodeLoaded {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        EmbedFormState.shared.setValue(value, forComponent: component.id, messageId: messageId)
    }

    private func isValidSelectValue(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let options = component.selectOptions ?? []
        if !options.isEmpty {
            return options.contains(where: { $0.value == value })
        }
        return !value.allSatisfy { $0.isNumber }
    }
}

final class EmbedRadioGroupNode: ASDisplayNode, EmbedFormInputNode {
    private let component: ParsedEmbedInputComponent
    private let messageId: String
    private var cachedSize: CGSize = .zero
    private var optionNodes: [ASDisplayNode] = []
    private static let cornerRadius: CGFloat = 8

    init(component: ParsedEmbedInputComponent, messageId: String) {
        self.component = component
        self.messageId = messageId
        super.init()
        let t = UIColor.theme
        backgroundColor = t.primary
        cornerRadius = Self.cornerRadius
        borderWidth = 1
        borderColor = t.border.withAlphaComponent(0.5).cgColor
        clipsToBounds = true

        for (i, opt) in (component.radioOptions ?? []).enumerated() {
            let n = ASDisplayNode()
            let btn = UIButton(type: .system)
            btn.setTitle("○ " + opt.label, for: .normal)
            btn.setTitleColor(UIColor.theme.textStrong, for: .normal)
            btn.contentHorizontalAlignment = .left
            btn.tag = i
            btn.addTarget(self, action: #selector(selected(_:)), for: .touchUpInside)
            let w = ASDisplayNode { return btn }
            n.addSubnode(w)
            optionNodes.append(n)
            addSubnode(n)
        }

        if let existing = EmbedFormState.shared.getValue(forComponent: component.id, messageId: messageId) {
            applySelectedValue(existing)
        } else if let def = component.defaultValue, !def.isEmpty {
            applySelectedValue(def)
        }
    }

    @objc private func selected(_ sender: UIButton) {
        let tag = sender.tag
        let opt = (component.radioOptions ?? [])[tag]
        applySelectedValue(opt.value)
    }

    private func applySelectedValue(_ value: String) {
        let opts = component.radioOptions ?? []
        var selectedIndex: Int? = nil
        if let idx = opts.firstIndex(where: { $0.value == value }) {
            selectedIndex = idx
        } else if let idx = opts.firstIndex(where: { $0.label == value }) {
            selectedIndex = idx
        }
        for (i, node) in optionNodes.enumerated() {
            if let btn = node.subnodes?.first?.view as? UIButton, i < opts.count {
                let prefix = (i == selectedIndex ? "● " : "○ ")
                btn.setTitle(prefix + opts[i].label, for: .normal)
            }
        }
        if let idx = selectedIndex, idx < opts.count {
            EmbedFormState.shared.setValue(opts[idx].value, forComponent: component.id, messageId: messageId)
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        cachedSize = CGSize(width: maxWidth, height: CGFloat((component.radioOptions ?? []).count * 36))
        return cachedSize
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for n in optionNodes {
            n.frame = CGRect(x: 0, y: y, width: bounds.width, height: 36)
            n.subnodes?.first?.frame = n.bounds
            y += 36
        }
    }
}

final class EmbedDatePickerFieldNode: ASDisplayNode, EmbedFormInputNode {
    private let component: ParsedEmbedInputComponent
    private let messageId: String
    private var cachedSize: CGSize = .zero
    private let button = UIButton(type: .system)
    private let chevronNode = ASImageNode()
    private static let cornerRadius: CGFloat = 8

    init(component: ParsedEmbedInputComponent, messageId: String) {
        self.component = component
        self.messageId = messageId
        super.init()
        let t = UIColor.theme
        backgroundColor = t.primary
        cornerRadius = Self.cornerRadius
        borderWidth = 1
        borderColor = t.border.withAlphaComponent(0.5).cgColor

        chevronNode.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?.withRenderingMode(.alwaysTemplate)
        chevronNode.tintColor = t.textStrong
        chevronNode.contentMode = .scaleAspectFit
        chevronNode.isUserInteractionEnabled = false
        addSubnode(chevronNode)
        button.setTitle("dd/mm/yyyy", for: .normal)
        button.contentHorizontalAlignment = .left
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.setTitleColor(t.textDisabled, for: .normal)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let wrapper = ASDisplayNode { [weak self] in return self?.button ?? UIView() }
        addSubnode(wrapper)

        if let existing = EmbedFormState.shared.getValue(forComponent: component.id, messageId: messageId), !existing.isEmpty, isValidDateFormat(existing) {
            button.setTitle(existing, for: .normal)
            button.setTitleColor(t.textStrong, for: .normal)
        } else if let existing = EmbedFormState.shared.getValue(forComponent: component.id, messageId: messageId), !existing.isEmpty, !isValidDateFormat(existing) {
            EmbedFormState.shared.clear(messageId: messageId)
        } else if let def = component.dateValue, !def.isEmpty, isValidDateFormat(def) {
            button.setTitle(def, for: .normal)
            button.setTitleColor(t.textStrong, for: .normal)
            EmbedFormState.shared.setValue(def, forComponent: component.id, messageId: messageId)
        }
    }
    func measureSize(maxWidth: CGFloat) -> CGSize {
        cachedSize = CGSize(width: maxWidth, height: 40)
        return cachedSize
    }
    override func layout() {
        super.layout()
        for node in subnodes ?? [] {
            if node !== chevronNode {
                node.frame = bounds
            }
        }
        let chevronSize = CGSize(width: 12, height: 12)
        chevronNode.frame = CGRect(x: bounds.width - chevronSize.width - 10, y: (bounds.height - chevronSize.height) / 2, width: chevronSize.width, height: chevronSize.height)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 30)
    }
    @objc private func tapped() {
        guard let vc = findViewController() as? ViewController else { return }
        let alert = UIAlertController(title: "Select Date", message: "\n\n\n\n\n\n\n\n", preferredStyle: .actionSheet)
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .wheels }
        picker.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 30),
            picker.widthAnchor.constraint(equalToConstant: 270),
            picker.heightAnchor.constraint(equalToConstant: 160)
        ])
        alert.addAction(UIAlertAction(title: "Done", style: .default, handler: { _ in
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy"
            let str = df.string(from: picker.date)
            self.button.setTitle(str, for: .normal)
            self.button.setTitleColor(UIColor.theme.textStrong, for: .normal)
            EmbedFormState.shared.setValue(str, forComponent: self.component.id, messageId: self.messageId)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = button
            popover.sourceRect = button.bounds
        }
        vc.present(alert, animated: true)
    }

    private func isValidDateFormat(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.date(from: dateString) != nil
    }
}

final class EmbedActionButtonsNode: ASDisplayNode {
    private var rowNodes: [EmbedActionRowNode] = []
    fileprivate(set) var cachedSize: CGSize = .zero
    var onButtonTapped: ((ParsedEmbedButton) -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = false
        isUserInteractionEnabled = true
    }

    func configure(actionRows: [ParsedEmbedActionRow]) {
        rowNodes.forEach { $0.removeFromSupernode() }
        rowNodes = actionRows.map { row in
            let node = EmbedActionRowNode(row: row)
            node.onButtonTapped = { [weak self] btn in self?.onButtonTapped?(btn) }
            return node
        }
        for node in rowNodes { addSubnode(node) }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !rowNodes.isEmpty else { return .zero }
        let rowSpacing: CGFloat = 6
        var totalH: CGFloat = 0
        for (i, node) in rowNodes.enumerated() {
            if i > 0 { totalH += rowSpacing }
            let sz = node.measureSize(maxWidth: maxWidth)
            _ = sz
            totalH += node.cachedSize.height
        }
        cachedSize = CGSize(width: maxWidth, height: totalH)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let rowSpacing: CGFloat = 6
        var y: CGFloat = 0
        for (i, node) in rowNodes.enumerated() {
            if i > 0 { y += rowSpacing }
            node.frame = CGRect(x: 0, y: y, width: node.cachedSize.width, height: node.cachedSize.height)
            y += node.cachedSize.height
        }
    }
}

private final class EmbedActionRowNode: ASDisplayNode {
    private var buttonNodes: [EmbedButtonNode] = []
    fileprivate(set) var cachedSize: CGSize = .zero
    var onButtonTapped: ((ParsedEmbedButton) -> Void)?

    init(row: ParsedEmbedActionRow) {
        super.init()
        automaticallyManagesSubnodes = false
        isUserInteractionEnabled = true
        buttonNodes = row.buttons.map { btn in
            let node = EmbedButtonNode(button: btn)
            node.onTapped = { [weak self] in self?.onButtonTapped?(btn) }
            return node
        }
        for node in buttonNodes { addSubnode(node) }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !buttonNodes.isEmpty else { return .zero }
        let buttonSpacing: CGFloat = 8
        let buttonHeight: CGFloat = 32
        var totalWidth: CGFloat = 0
        for (i, node) in buttonNodes.enumerated() {
            let bw = node.intrinsicWidth(maxWidth: maxWidth)
            node.cachedSize = CGSize(width: bw, height: buttonHeight)
            totalWidth += bw
            if i > 0 { totalWidth += buttonSpacing }
        }
        cachedSize = CGSize(width: min(totalWidth, maxWidth), height: buttonHeight)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let buttonSpacing: CGFloat = 8
        var x: CGFloat = 0
        for node in buttonNodes {
            node.frame = CGRect(x: x, y: 0, width: node.cachedSize.width, height: bounds.height)
            x += node.cachedSize.width + buttonSpacing
        }
    }
}

private final class EmbedButtonNode: ASDisplayNode {
    private let labelNode = ASTextNode2()
    private let button: ParsedEmbedButton
    private let control = UIButton(type: .custom)
    var onTapped: (() -> Void)?
    fileprivate(set) var cachedSize: CGSize = .zero

    init(button: ParsedEmbedButton) {
        self.button = button
        super.init()
        backgroundColor = Self.buttonColor(for: button.style)
        cornerRadius = 4
        clipsToBounds = true

        labelNode.attributedText = NSAttributedString(string: button.label, attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.white
        ])
        labelNode.maximumNumberOfLines = 1
        labelNode.truncationMode = .byTruncatingTail
        labelNode.isUserInteractionEnabled = false
        addSubnode(labelNode)

        let wrapper = ASDisplayNode { [weak self] in return self?.control ?? UIView() }
        addSubnode(wrapper)

        control.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        control.isEnabled = !button.disabled

        if button.url != nil {
            let underlineStr = NSMutableAttributedString(attributedString: labelNode.attributedText!)
            underlineStr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: underlineStr.length))
            labelNode.attributedText = underlineStr
        }
        alpha = button.disabled ? 0.5 : 1.0
    }

    func intrinsicWidth(maxWidth: CGFloat) -> CGFloat {
        let hPadding: CGFloat = 20
        let minWidth: CGFloat = 60
        let labelSize = labelNode.measure(CGSize(width: maxWidth - hPadding * 2, height: 32))
        return max(minWidth, ceil(labelSize.width) + hPadding * 2)
    }

    @objc private func handleTap() {
        if let url = button.url, let u = URL(string: url) { UIApplication.shared.open(u) }
        else { onTapped?() }
    }

    private static func buttonColor(for style: EmbedButtonStyle) -> UIColor {
        switch style {
        case .primary: return UIColor(red: 88.0/255, green: 101.0/255, blue: 242.0/255, alpha: 1.0)
        case .secondary, .link: return UIColor(red: 79.0/255, green: 84.0/255, blue: 92.0/255, alpha: 1.0)
        case .success: return UIColor(red: 45.0/255, green: 125.0/255, blue: 70.0/255, alpha: 1.0)
        case .danger: return UIColor(red: 218.0/255, green: 55.0/255, blue: 60.0/255, alpha: 1.0)
        }
    }

    override func layout() {
        super.layout()
        for node in subnodes ?? [] {
            if node !== labelNode {
                node.frame = bounds
            }
        }
        let hPadding: CGFloat = 20
        let labelSize = labelNode.measure(CGSize(width: bounds.width - hPadding * 2, height: bounds.height))
        let x = (bounds.width - labelSize.width) / 2
        let y = (bounds.height - labelSize.height) / 2
        labelNode.frame = CGRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
    }
}

extension ASDisplayNode {
    func findViewController() -> UIViewController? {
        guard isNodeLoaded else { return nil }
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

final class EmbedSelectSheetController: ViewController {
    private let options: [ParsedSelectOption]
    private let onSelected: (ParsedSelectOption) -> Void

    private var sheetNode: EmbedSelectSheetNode {
        return displayNode as! EmbedSelectSheetNode
    }

    init(options: [ParsedSelectOption], onSelected: @escaping (ParsedSelectOption) -> Void) {
        self.options = options
        self.onSelected = onSelected
        super.init(navigationBarPresentationData: nil)
        statusBar.statusBarStyle = .Ignore
        blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = EmbedSelectSheetNode(
            options: options,
            onOptionSelected: { [weak self] option in
                self?.animateDismiss {
                    self?.onSelected(option)
                }
            },
            onDimTapped: { [weak self] in
                self?.animateDismiss(completion: nil)
            }
        )
        displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        sheetNode.updateLayout(layout: layout, transition: transition)
    }

    func animateIn() {
        sheetNode.animateIn()
    }

    private func animateDismiss(completion: (() -> Void)?) {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            completion?()
        }
    }
}

private final class EmbedSelectSheetNode: ASDisplayNode {
    private let options: [ParsedSelectOption]
    private let onOptionSelected: (ParsedSelectOption) -> Void
    private let onDimTapped: () -> Void

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let scrollView = UIScrollView()
    private let innerCardView = UIView()
    private var optionViews: [UIView] = []

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private let handleH: CGFloat = 30
    private let optionH: CGFloat = 48
    private let bottomPad: CGFloat = 16
    private let cardInsetH: CGFloat = 16

    init(options: [ParsedSelectOption], onOptionSelected: @escaping (ParsedSelectOption) -> Void, onDimTapped: @escaping () -> Void) {
        self.options = options
        self.onOptionSelected = onOptionSelected
        self.onDimTapped = onDimTapped
        super.init()

        dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingNode.alpha = 0

        let t = UIColor.theme
        containerNode.backgroundColor = t.secondary
        containerNode.cornerRadius = 14
        containerNode.clipsToBounds = true
        handleNode.backgroundColor = t.textDisabled.withAlphaComponent(0.55)
        handleNode.cornerRadius = 2.5

        addSubnode(dimmingNode)
        addSubnode(containerNode)
        containerNode.addSubnode(handleNode)

        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false

        innerCardView.backgroundColor = t.secondaryLight
        innerCardView.layer.cornerRadius = 10
        innerCardView.layer.borderWidth = 0.5
        innerCardView.layer.borderColor = t.border.withAlphaComponent(0.3).cgColor
        innerCardView.clipsToBounds = true
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)
        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        containerNode.view.addSubview(scrollView)
        scrollView.addSubview(innerCardView)

        let t = UIColor.theme
        for (index, option) in options.enumerated() {
            let row = UIView()
            row.backgroundColor = .clear
            row.tag = index

            let label = UILabel()
            label.text = option.label
            label.font = UIFont.systemFont(ofSize: 16)
            label.textColor = t.textStrong
            label.tag = 100
            row.addSubview(label)

            if index < options.count - 1 {
                let sep = UIView()
                sep.backgroundColor = t.border.withAlphaComponent(0.25)
                sep.tag = 200
                row.addSubview(sep)
            }

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(optionTapped(_:)))
            row.addGestureRecognizer(tapGesture)
            innerCardView.addSubview(row)
            optionViews.append(row)
        }
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func optionTapped(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view, row.tag < options.count else {
            return
        }
        let tag = row.tag
        let originalBG = row.backgroundColor
        row.backgroundColor = UIColor.theme.border.withAlphaComponent(0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            row.backgroundColor = originalBG
            guard let self = self else { return }
            self.onOptionSelected(self.options[tag])
        }
    }

    private func sheetHeight(for layout: ContainerViewLayout) -> CGFloat {
        let safeBottom = layout.intrinsicInsets.bottom
        let contentH = handleH + CGFloat(options.count) * optionH + cardInsetH * 2 + bottomPad + safeBottom
        let maxH = layout.size.height * 0.4
        return min(contentH, maxH)
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        let sh = sheetHeight(for: layout)
        containerHeight = sh
        let containerY = layout.size.height - sh
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: sh))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 10, width: 36, height: 5))
        layoutOptions(width: screenW, sheetHeight: sh)
    }

    private func layoutOptions(width: CGFloat, sheetHeight: CGFloat) {
        let safeBottom = validLayout?.intrinsicInsets.bottom ?? 0
        let scrollableH = sheetHeight - handleH - safeBottom
        scrollView.frame = CGRect(x: 0, y: handleH, width: width, height: scrollableH)

        let cardW = width - cardInsetH * 2
        let totalRowsH = CGFloat(options.count) * optionH
        let totalContentH = totalRowsH + cardInsetH * 2

        scrollView.contentSize = CGSize(width: width, height: totalContentH)
        innerCardView.frame = CGRect(x: cardInsetH, y: cardInsetH, width: cardW, height: totalRowsH)

        var y: CGFloat = 0
        for (index, row) in optionViews.enumerated() {
            row.frame = CGRect(x: 0, y: y, width: cardW, height: optionH)
            if let label = row.viewWithTag(100) as? UILabel {
                label.frame = CGRect(x: 16, y: 0, width: cardW - 32, height: optionH)
            }
            if index < options.count - 1, let sep = row.viewWithTag(200) {
                sep.frame = CGRect(x: 0, y: optionH - 0.5, width: cardW, height: 0.5)
            }
            y += optionH
        }
    }

    private var animateInRetryCount = 0

    func animateIn() {
        guard let layout = validLayout else {
            animateInRetryCount += 1
            guard animateInRetryCount < 90 else { animateInRetryCount = 0; return }
            DispatchQueue.main.async { [weak self] in self?.animateIn() }
            return
        }
        animateInRetryCount = 0
        let sh = sheetHeight(for: layout)
        containerHeight = sh
        let fromY = layout.size.height
        let toY = layout.size.height - sh
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: sh)
        layoutOptions(width: layout.size.width, sheetHeight: sh)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: sh)
        })
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else { completion(); return }
        let bottomY = layout.size.height
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame = CGRect(x: 0, y: bottomY, width: layout.size.width, height: self.containerHeight)
        }) { _ in
            completion()
        }
    }
}
