import AsyncDisplayKit
import UIKit

@MainActor
final class CanvasNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var canvases: [Mezon_Api_ChannelCanvasItem] = []
    private var searchQuery = ""
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var didLoadCanvases = false
    private var didFinishLoading = false

    private let tableNode: ASTableNode
    private let searchNode = CanvasSearchNode()
    private let emptyStateNode = ASTextNode2()

    init(context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType

        self.tableNode = ASTableNode()

        super.init()
        self.automaticallyManagesSubnodes = true

        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.backgroundColor = .clear
        tableNode.view.delaysContentTouches = false
        tableNode.view.keyboardDismissMode = .onDrag

        searchNode.onTextChanged = { [weak self] query in
            guard let self else { return }
            self.searchDebounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                self.tableNode.reloadData()
                self.setNeedsLayout()
            }
            self.searchDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: workItem)
        }

        emptyStateNode.attributedText = NSAttributedString(
            string: L(L10n.ChannelDetail.noCanvasFound),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .medium),
                .foregroundColor: UIColor.theme.textDisabled,
            ]
        )
        emptyStateNode.maximumNumberOfLines = 0
    }

    func loadTabDataIfNeeded() {
        guard !didLoadCanvases else { return }
        didLoadCanvases = true
        fetchCanvases()
    }

    override func didLoad() {
        super.didLoad()
        backgroundColor = UIColor.theme.primary
        tableNode.view.backgroundColor = .clear
    }

    private func fetchCanvases() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = await context.getToken() ?? ""
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listChannelCanvases(
                    clanId: targetClanId,
                    channelId: channelId,
                    token: token
                )
                self.canvases = res.channelCanvases
                self.didFinishLoading = true
                await self.tableNode.reloadData()
                self.setNeedsLayout()
            } catch {
            }
        }
    }

    private var displayedCanvases: [Mezon_Api_ChannelCanvasItem] {
        guard !searchQuery.isEmpty else { return canvases }
        return canvases.filter {
            let title = $0.title.isEmpty
                ? L(L10n.ChannelDetail.untitledCanvas)
                : $0.title.replacingOccurrences(of: "\n", with: " ")
            return title.range(
                of: searchQuery,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    private func presentCanvas(for item: Mezon_Api_ChannelCanvasItem) {
        guard let url = URL(string: MezonConfig.canvasShareURLString(
            clanId: clanId, channelId: channelId, canvasId: item.id)),
            let host = tableNode.view.findHostingViewController(),
            let nav = host.navigationController
        else { return }
        let title =
            item.title.isEmpty ? L(L10n.ChannelDetail.untitledCanvas) : item.title.replacingOccurrences(
                of: "\n", with: " ")
        let vc = CanvasWebViewController(
            pageURL: url,
            canvasTitle: title,
            expectsNonEmptyTitle: !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            accountContext: context,
            onDismiss: { [weak self] in
                self?.fetchCanvases()
            }
        )
        nav.pushViewController(vc, animated: true)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        searchNode.style.height = ASDimension(unit: .points, value: 40.sf)
        let search = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16),
            child: searchNode
        )

        let content: ASLayoutElement
        if didFinishLoading && displayedCanvases.isEmpty {
            content = ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: .minimumXY,
                child: emptyStateNode
            )
        } else {
            content = tableNode
        }
        content.style.flexGrow = 1
        content.style.flexShrink = 1

        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [search, content]
        )
    }
}

extension CanvasNode: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return displayedCanvases.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        let canvas = displayedCanvases[indexPath.row]
        let shareURL = MezonConfig.canvasShareURLString(
            clanId: clanId, channelId: channelId, canvasId: canvas.id)
        return {
            CanvasCellNode(
                canvas: canvas,
                onCopyLink: {
                    UIPasteboard.general.string = shareURL
                    Toast.success(L(L10n.MessageAction.copied))
                }
            )
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        let canvas = displayedCanvases[indexPath.row]
        presentCanvas(for: canvas)
    }
}

private final class CanvasSearchNode: ASDisplayNode {
    private let iconNode = ASImageNode()
    private let textFieldNode: ASDisplayNode
    private let textField: UITextField
    private let clearButton = UIButton(type: .system)
    var onTextChanged: ((String) -> Void)?

    override init() {
        let textField = UITextField()
        self.textField = textField
        self.textFieldNode = ASDisplayNode(viewBlock: { textField })
        super.init()

        automaticallyManagesSubnodes = true
        backgroundColor = UIColor.theme.secondary
        cornerRadius = 10.sf
        clipsToBounds = true

        let theme = UIColor.theme
        iconNode.image = UIImage(systemName: "magnifyingglass")?.withTintColor(
            theme.text, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 18.sf, height: 18.sf)

        textField.font = UIFont.systemFont(ofSize: 14.sf)
        textField.textColor = UIColor.theme.textStrong
        textField.tintColor = UIColor.theme.textStrong
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .never
        textField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ChannelDetail.searchCanvasPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )

        clearButton.frame = CGRect(x: 2, y: 4, width: 32, height: 32)
        clearButton.tintColor = theme.text
        clearButton.setImage(
            UIImage(systemName: "xmark.circle.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)),
            for: .normal
        )
        clearButton.isHidden = true
        clearButton.accessibilityLabel = L(L10n.Common.close)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        let clearButtonContainer = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 40))
        clearButtonContainer.addSubview(clearButton)
        textField.rightView = clearButtonContainer
        textField.rightViewMode = .always
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }

    @objc private func textChanged() {
        clearButton.isHidden = textField.text?.isEmpty ?? true
        onTextChanged?(textField.text ?? "")
    }

    @objc private func clearTapped() {
        textField.text = ""
        clearButton.isHidden = true
        onTextChanged?("")
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        textFieldNode.style.flexGrow = 1
        textFieldNode.style.flexShrink = 1
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8,
            justifyContent: .start,
            alignItems: .center,
            children: [iconNode, textFieldNode]
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 8),
            child: row
        )
    }
}

private final class CanvasCellNode: ASCellNode {
    private let cardNode = ASDisplayNode()
    private let titleNode = ASTextNode2()
    private let copyLinkButton = ASButtonNode()
    private let onCopyLink: () -> Void

    init(canvas: Mezon_Api_ChannelCanvasItem, onCopyLink: @escaping () -> Void) {
        self.onCopyLink = onCopyLink
        super.init()
        self.automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none

        let t = UIColor.theme

        cardNode.backgroundColor = t.secondary
        cardNode.cornerRadius = 10.sf
        cardNode.clipsToBounds = true

        let title =
            canvas.title.isEmpty ? L(L10n.ChannelDetail.untitledCanvas) : canvas.title.replacingOccurrences(
                of: "\n", with: " ")
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .medium),
                .foregroundColor: t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 2
        titleNode.truncationMode = .byTruncatingTail

        copyLinkButton.setTitle(
            L(L10n.ChannelAction.copyLink), with: UIFont.systemFont(ofSize: 12.sf, weight: .medium),
            with: t.textLink, for: .normal)
        copyLinkButton.backgroundColor = t.secondaryLight
        copyLinkButton.cornerRadius = 6
        copyLinkButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        copyLinkButton.addTarget(
            self, action: #selector(copyLinkTapped), forControlEvents: .touchUpInside)
    }

    @objc private func copyLinkTapped() {
        onCopyLink()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let rowStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .spaceBetween,
            alignItems: .center,
            children: [titleNode, copyLinkButton]
        )
        titleNode.style.flexShrink = 1
        titleNode.style.flexGrow = 1

        let cardContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14),
            child: rowStack
        )
        let card = ASBackgroundLayoutSpec(child: cardContent, background: cardNode)

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16),
            child: card
        )
    }
}

private extension UIView {
    func findHostingViewController() -> ViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? ViewController { return vc }
            responder = next
        }
        return nil
    }
}
