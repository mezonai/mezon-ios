import AsyncDisplayKit
import UIKit

struct MezonConfirmConfiguration {
    var title: String
    var content: String?
    var confirmTitle: String
    var cancelTitle: String
    var showsCancelButton: Bool
    var isDanger: Bool
    var customBodyNode: ASDisplayNode?
    var onConfirm: () -> Void
    var onCancel: () -> Void

    init(
        title: String,
        content: String? = nil,
        confirmTitle: String,
        cancelTitle: String = L(L10n.Common.cancel),
        showsCancelButton: Bool = true,
        isDanger: Bool = false,
        customBodyNode: ASDisplayNode? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.title = title
        self.content = content
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.showsCancelButton = showsCancelButton
        self.isDanger = isDanger
        self.customBodyNode = customBodyNode
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

enum MezonConfirm {
    @MainActor
    static func present(from presenter: UIViewController, configuration: MezonConfirmConfiguration) {
        let vc = MezonConfirmController(configuration: configuration)
        presenter.present(vc, animated: true)
    }

    @MainActor
    static func present(
        from presenter: UIViewController,
        title: String,
        content: String? = nil,
        confirmTitle: String,
        cancelTitle: String = L(L10n.Common.cancel),
        showsCancelButton: Bool = true,
        isDanger: Bool = false,
        customBodyNode: ASDisplayNode? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        present(
            from: presenter,
            configuration: MezonConfirmConfiguration(
                title: title,
                content: content,
                confirmTitle: confirmTitle,
                cancelTitle: cancelTitle,
                showsCancelButton: showsCancelButton,
                isDanger: isDanger,
                customBodyNode: customBodyNode,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }
}

@MainActor
final class MezonConfirmController: UIViewController {

    private let configuration: MezonConfirmConfiguration
    private var rootNode: MezonConfirmRootNode!

    init(configuration: MezonConfirmConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let node = MezonConfirmRootNode(configuration: configuration) { [weak self] work in
            self?.dismiss(animated: true, completion: work)
        }
        rootNode = node
        view = node.view
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        rootNode.frame = view.bounds
    }
}

private final class MezonConfirmRootNode: ASDisplayNode {

    private let backdropNode = ASDisplayNode()
    private let cardNode: MezonConfirmCardNode
    private let dismissAnimated: (@escaping () -> Void) -> Void
    private let onCancel: () -> Void

    init(configuration: MezonConfirmConfiguration, dismissAnimated: @escaping (@escaping () -> Void) -> Void) {
        self.dismissAnimated = dismissAnimated
        self.onCancel = configuration.onCancel
        self.cardNode = MezonConfirmCardNode(
            title: configuration.title,
            content: configuration.content,
            confirmTitle: configuration.confirmTitle,
            cancelTitle: configuration.cancelTitle,
            isDanger: configuration.isDanger,
            showsCancelButton: configuration.showsCancelButton,
            customBodyNode: configuration.customBodyNode
        )
        super.init()
        automaticallyManagesSubnodes = false
        backdropNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backdropNode.isUserInteractionEnabled = true

        let onConf = configuration.onConfirm
        let onCanc = configuration.onCancel
        cardNode.setHandlers(
            onConfirmTap: { dismissAnimated { onConf() } },
            onCancelTap: { dismissAnimated { onCanc() } }
        )
    }

    override func didLoad() {
        super.didLoad()
        addSubnode(backdropNode)
        addSubnode(cardNode)
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        backdropNode.view.addGestureRecognizer(tap)
    }

    @objc private func backdropTapped() {
        dismissAnimated { self.onCancel() }
    }

    override func layout() {
        super.layout()
        backdropNode.frame = bounds
        let wide = bounds.width >= 720
        let margin = wide ? bounds.width * 0.2 : bounds.width * 0.05
        let maxW = min(520, bounds.width - margin * 2)
        let maxH = bounds.height - 48
        let sz = cardNode.measure(CGSize(width: max(0, maxW), height: max(0, maxH)))
        cardNode.frame = CGRect(
            x: floor((bounds.width - sz.width) / 2),
            y: floor((bounds.height - sz.height) / 2),
            width: sz.width,
            height: sz.height
        )
    }
}

private final class MezonConfirmCardNode: ASDisplayNode {

    private let titleNode = ASTextNode()
    private let separatorNode = ASDisplayNode()
    private let contentNode = ASTextNode()
    private let customBodyNode: ASDisplayNode?
    private let confirmButton = ASButtonNode()
    private let cancelButton = ASButtonNode()
    private let cardBg = ASDisplayNode()
    private let showsCancelButton: Bool

    private var onConfirmTap: () -> Void = {}
    private var onCancelTap: () -> Void = {}

    func setHandlers(onConfirmTap: @escaping () -> Void, onCancelTap: @escaping () -> Void) {
        self.onConfirmTap = onConfirmTap
        self.onCancelTap = onCancelTap
    }

    init(
        title: String,
        content: String?,
        confirmTitle: String,
        cancelTitle: String,
        isDanger: Bool,
        showsCancelButton: Bool,
        customBodyNode: ASDisplayNode?
    ) {
        self.showsCancelButton = showsCancelButton
        self.customBodyNode = customBodyNode
        super.init()
        automaticallyManagesSubnodes = true

        let t = UIColor.theme
        cardBg.backgroundColor = t.secondary
        cardBg.cornerRadius = 16
        cardBg.clipsToBounds = true

        let titlePara = NSMutableParagraphStyle()
        titlePara.alignment = .center
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: t.textStrong,
                .paragraphStyle: titlePara,
            ]
        )
        titleNode.maximumNumberOfLines = 0

        separatorNode.backgroundColor = t.border
        separatorNode.style.height = ASDimension(unit: .points, value: 1)

        let hasCustom = customBodyNode != nil
        let text = content ?? ""
        let hasText = !text.isEmpty
        contentNode.isHidden = hasCustom || !hasText
        if hasText {
            let contentPara = NSMutableParagraphStyle()
            contentPara.alignment = .center
            contentNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: t.text,
                    .paragraphStyle: contentPara,
                ]
            )
            contentNode.maximumNumberOfLines = 0
        }

        if let c = customBodyNode {
            c.isHidden = false
        }

        confirmButton.cornerRadius = 20
        confirmButton.clipsToBounds = true
        confirmButton.setTitle(confirmTitle, with: .systemFont(ofSize: 16, weight: .semibold), with: .white, for: .normal)
        if isDanger {
            confirmButton.backgroundColor = UIColor(red: 0.92, green: 0.25, blue: 0.25, alpha: 1)
        } else {
            confirmButton.backgroundColor = t.bgViolet
        }
        confirmButton.addTarget(self, action: #selector(confirmPressed), forControlEvents: .touchUpInside)
        confirmButton.style.height = ASDimension(unit: .points, value: 44)

        cancelButton.cornerRadius = 20
        cancelButton.clipsToBounds = true
        cancelButton.setTitle(cancelTitle, with: .systemFont(ofSize: 16, weight: .semibold), with: t.textStrong, for: .normal)
        cancelButton.backgroundColor = t.primary
        cancelButton.addTarget(self, action: #selector(cancelPressed), forControlEvents: .touchUpInside)
        cancelButton.style.height = ASDimension(unit: .points, value: 44)
        cancelButton.isHidden = !showsCancelButton
    }

    @objc private func confirmPressed() { onConfirmTap() }
    @objc private func cancelPressed() { onCancelTap() }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let maxW = constrainedSize.max.width
        titleNode.style.maxWidth = ASDimension(unit: .points, value: maxW - 32)
        contentNode.style.maxWidth = ASDimension(unit: .points, value: maxW - 32)
        if let c = customBodyNode {
            c.style.maxWidth = ASDimension(unit: .points, value: maxW - 32)
        }

        let headerChildren: [ASLayoutElement] = [titleNode, separatorNode]
        let header = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 12,
            justifyContent: .start,
            alignItems: .stretch,
            children: headerChildren
        )

        var middle: [ASLayoutElement] = []
        if let c = customBodyNode, !c.isHidden {
            middle.append(c)
        }
        if !contentNode.isHidden {
            middle.append(contentNode)
        }

        var buttonChildren: [ASLayoutElement] = [confirmButton]
        if showsCancelButton {
            buttonChildren.append(cancelButton)
        }
        let buttons = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 12,
            justifyContent: .start,
            alignItems: .stretch,
            children: buttonChildren
        )

        var sections: [ASLayoutElement] = [header]
        if !middle.isEmpty {
            let midStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 12,
                justifyContent: .start,
                alignItems: .stretch,
                children: middle
            )
            sections.append(midStack)
        }
        sections.append(buttons)

        let inner = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 20,
            justifyContent: .start,
            alignItems: .stretch,
            children: sections
        )
        let padded = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
            child: inner
        )
        return ASBackgroundLayoutSpec(child: padded, background: cardBg)
    }
}
