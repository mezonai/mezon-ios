import AsyncDisplayKit
import UIKit

private enum ReportMessageAbuseType: String, CaseIterable {
    case spam = "SPAM"
    case abuseOrHarassment = "ABUSE_OR_HARASSMENT"
    case harmfulMisinformation = "HARMFUL_MISINFORMATION_OR_GLORIFYING_VIOLENCE"
    case exposingPrivateInfo = "EXPOSING_PRIVATE_IDENTIFYING_INFORMATION"

    var titleKey: String {
        switch self {
        case .spam: return L10n.ReportMessage.spam
        case .abuseOrHarassment: return L10n.ReportMessage.harassment
        case .harmfulMisinformation: return L10n.ReportMessage.violentContent
        case .exposingPrivateInfo: return L10n.ReportMessage.privateInfo
        }
    }
}

final class ReportMessageModalController: ViewController {

    private let context: AccountContext
    private let messageId: String
    var onDismiss: (() -> Void)?

    private var sheetNode: ReportMessageModalNode {
        displayNode as! ReportMessageModalNode
    }

    init(context: AccountContext, messageId: String) {
        self.context = context
        self.messageId = messageId
        super.init(navigationBarPresentationData: nil)
        statusBar.statusBarStyle = .Ignore
        blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ReportMessageModalNode(
            onSubmit: { [weak self] abuseType in
                self?.submitReport(abuseType: abuseType)
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
            self?.onDismiss?()
            completion?()
        }
    }

    private func submitReport(abuseType: ReportMessageAbuseType) {
        let id = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let msgId = Int64(id) else {
            Toast.error(L(L10n.ReportMessage.failed))
            return
        }
        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ReportMessage.failed))
                return
            }
            do {
                try await self.context.account.network.reportMessageAbuse(
                    messageId: msgId,
                    abuseType: abuseType.rawValue,
                    token: token
                )
                Toast.success(L(L10n.ReportMessage.submitted))
                self.animateDismiss(completion: nil)
            } catch {
                Toast.error(error.localizedDescription.isEmpty ? L(L10n.ReportMessage.failed) : error.localizedDescription)
            }
        }
    }
}

private final class ReportMessageModalNode: ASDisplayNode {

    private let onSubmit: (ReportMessageAbuseType) -> Void
    private let onDimTapped: () -> Void

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let scrollView = UIScrollView()

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var didBuild = false

    private var selectedCategory: ReportMessageAbuseType?
    private var pendingSubmitCategory: ReportMessageAbuseType?
    private var rebuildWidth: CGFloat = 320
    private var contentRoot: UIView?

    private let padH: CGFloat = 24
    private let handleH: CGFloat = 25
    private let rowH: CGFloat = 52

    init(onSubmit: @escaping (ReportMessageAbuseType) -> Void, onDimTapped: @escaping () -> Void) {
        self.onSubmit = onSubmit
        self.onDimTapped = onDimTapped
        super.init()
        dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingNode.alpha = 0
        let t = UIColor.theme
        containerNode.backgroundColor = t.primary
        containerNode.cornerRadius = 14
        containerNode.clipsToBounds = true
        handleNode.backgroundColor = t.textDisabled
        handleNode.cornerRadius = 2.5
        addSubnode(dimmingNode)
        addSubnode(containerNode)
        containerNode.addSubnode(handleNode)
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)
        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        scrollView.showsVerticalScrollIndicator = true
        scrollView.delaysContentTouches = false
        containerNode.view.addSubview(scrollView)
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func reportSummaryBackTapped() {
        selectedCategory = nil
        pendingSubmitCategory = nil
        rebuildContent(width: rebuildWidth)
    }

    @objc private func reportSummarySubmitTapped() {
        guard let c = pendingSubmitCategory else { return }
        onSubmit(c)
    }

    @objc private func categoryRowTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0, idx < ReportMessageAbuseType.allCases.count else { return }
        selectedCategory = ReportMessageAbuseType.allCases[idx]
        rebuildContent(width: rebuildWidth)
    }

    @objc private func reportCancelTapped() {
        onDimTapped()
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeBottom = layout.intrinsicInsets.bottom
        transition.updateFrame(node: dimmingNode, frame: bounds)
        let screenW = layout.size.width
        let maxH = layout.size.height * 0.72
        let scrollH = maxH - handleH - safeBottom - 8
        containerHeight = handleH + scrollH + safeBottom + 8
        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))
        scrollView.frame = CGRect(x: 0, y: handleH, width: screenW, height: scrollH)
        if !didBuild {
            didBuild = true
            rebuildContent(width: screenW)
        } else {
            rebuildContent(width: screenW)
        }
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight
        containerNode.frame.origin.y = fromY
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame.origin.y = toY
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else {
            completion()
            return
        }
        let bottomY = layout.size.height
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame.origin.y = bottomY
        }) { _ in
            completion()
        }
    }

    private func rebuildContent(width: CGFloat) {
        rebuildWidth = width
        contentRoot?.removeFromSuperview()
        let root = UIView()
        root.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(root)
        contentRoot = root
        let t = UIColor.theme

        if let sel = selectedCategory {
            pendingSubmitCategory = sel
            let backBtn = UIButton(type: .system)
            backBtn.translatesAutoresizingMaskIntoConstraints = false
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            backBtn.setImage(UIImage(systemName: "chevron.left", withConfiguration: cfg), for: .normal)
            backBtn.tintColor = t.textStrong
            backBtn.addTarget(self, action: #selector(reportSummaryBackTapped), for: .touchUpInside)

            let title = UILabel()
            title.translatesAutoresizingMaskIntoConstraints = false
            title.text = L(L10n.ReportMessage.summaryTitle)
            title.font = .systemFont(ofSize: 18, weight: .semibold)
            title.textColor = t.textStrong

            let sub = UILabel()
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.text = L(L10n.ReportMessage.reviewBeforeSubmit)
            sub.font = .systemFont(ofSize: 14)
            sub.textColor = t.textDisabled
            sub.numberOfLines = 0

            let catLabel = UILabel()
            catLabel.translatesAutoresizingMaskIntoConstraints = false
            catLabel.text = L(L10n.ReportMessage.categoryLabel)
            catLabel.font = .systemFont(ofSize: 13, weight: .medium)
            catLabel.textColor = t.textDisabled

            let pill = UIView()
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.backgroundColor = t.secondary
            pill.layer.cornerRadius = 8
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = t.bgViolet
            dot.layer.cornerRadius = 3
            let catTitle = UILabel()
            catTitle.translatesAutoresizingMaskIntoConstraints = false
            catTitle.text = L(L(sel.titleKey))
            catTitle.font = .systemFont(ofSize: 15, weight: .medium)
            catTitle.textColor = t.textStrong
            pill.addSubview(dot)
            pill.addSubview(catTitle)

            let desc = UILabel()
            desc.translatesAutoresizingMaskIntoConstraints = false
            desc.text = L(L10n.ReportMessage.submitDescription)
            desc.font = .systemFont(ofSize: 14)
            desc.textColor = t.textDisabled
            desc.numberOfLines = 0

            let submit = UIButton(type: .system)
            submit.translatesAutoresizingMaskIntoConstraints = false
            submit.setTitle(L(L10n.ReportMessage.submitReport), for: .normal)
            submit.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            submit.backgroundColor = t.bgViolet
            submit.setTitleColor(.white, for: .normal)
            submit.layer.cornerRadius = 10
            submit.clipsToBounds = true
            submit.addTarget(self, action: #selector(reportSummarySubmitTapped), for: .touchUpInside)

            root.addSubview(backBtn)
            root.addSubview(title)
            root.addSubview(sub)
            root.addSubview(catLabel)
            root.addSubview(pill)
            root.addSubview(desc)
            root.addSubview(submit)

            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
                root.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: padH),
                root.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
                root.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * padH),

                backBtn.topAnchor.constraint(equalTo: root.topAnchor),
                backBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor),

                title.centerYAnchor.constraint(equalTo: backBtn.centerYAnchor),
                title.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 8),
                title.trailingAnchor.constraint(equalTo: root.trailingAnchor),

                sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
                sub.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: root.trailingAnchor),

                catLabel.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 20),
                catLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor),

                pill.topAnchor.constraint(equalTo: catLabel.bottomAnchor, constant: 8),
                pill.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                pill.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                pill.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

                dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
                dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),

                catTitle.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
                catTitle.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
                catTitle.topAnchor.constraint(equalTo: pill.topAnchor, constant: 12),
                catTitle.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -12),

                desc.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 20),
                desc.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                desc.trailingAnchor.constraint(equalTo: root.trailingAnchor),

                submit.topAnchor.constraint(equalTo: desc.bottomAnchor, constant: 16),
                submit.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                submit.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                submit.heightAnchor.constraint(equalToConstant: 48),
                submit.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        } else {
            let title = UILabel()
            title.translatesAutoresizingMaskIntoConstraints = false
            title.text = L(L10n.ReportMessage.title)
            title.font = .systemFont(ofSize: 18, weight: .semibold)
            title.textColor = t.textStrong

            let sub = UILabel()
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.text = L(L10n.ReportMessage.subtitle)
            sub.font = .systemFont(ofSize: 14)
            sub.textColor = t.textDisabled
            sub.numberOfLines = 0

            let hint = UILabel()
            hint.translatesAutoresizingMaskIntoConstraints = false
            hint.text = L(L10n.ReportMessage.selectedMessage)
            hint.font = .systemFont(ofSize: 13, weight: .medium)
            hint.textColor = t.textDisabled

            root.addSubview(title)
            root.addSubview(sub)
            root.addSubview(hint)

            NSLayoutConstraint.activate([
                title.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
                title.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                title.trailingAnchor.constraint(equalTo: root.trailingAnchor),

                sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
                sub.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: root.trailingAnchor),

                hint.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
                hint.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                hint.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ])

            let stack = UIStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .vertical
            stack.spacing = 0
            stack.layer.cornerRadius = 10
            stack.clipsToBounds = true
            stack.backgroundColor = t.secondary
            root.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
                stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ])

            for (idx, opt) in ReportMessageAbuseType.allCases.enumerated() {
                let row = UIButton(type: .system)
                row.translatesAutoresizingMaskIntoConstraints = false
                row.backgroundColor = .clear
                let lbl = UILabel()
                lbl.translatesAutoresizingMaskIntoConstraints = false
                lbl.text = L(L(opt.titleKey))
                lbl.font = .systemFont(ofSize: 16)
                lbl.textColor = t.textStrong
                lbl.textAlignment = .center
                lbl.isUserInteractionEnabled = false
                let chev = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
                chev.tintColor = t.textDisabled
                chev.translatesAutoresizingMaskIntoConstraints = false
                chev.setContentHuggingPriority(.required, for: .horizontal)
                chev.setContentCompressionResistancePriority(.required, for: .horizontal)
                chev.isUserInteractionEnabled = false
                row.addSubview(lbl)
                row.addSubview(chev)
                let rowInward: CGFloat = 20
                NSLayoutConstraint.activate([
                    row.heightAnchor.constraint(equalToConstant: rowH),
                    lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowInward),
                    lbl.trailingAnchor.constraint(equalTo: chev.leadingAnchor, constant: -10),
                    lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    chev.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -rowInward),
                    chev.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                ])
                row.tag = idx
                row.addTarget(self, action: #selector(categoryRowTapped(_:)), for: .touchUpInside)
                stack.addArrangedSubview(row)
                if idx < ReportMessageAbuseType.allCases.count - 1 {
                    let sep = UIView()
                    sep.translatesAutoresizingMaskIntoConstraints = false
                    sep.backgroundColor = t.tertiary
                    sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                    stack.addArrangedSubview(sep)
                }
            }

            let cancel = UIButton(type: .system)
            cancel.translatesAutoresizingMaskIntoConstraints = false
            cancel.setTitle(L(L10n.ReportMessage.cancel), for: .normal)
            cancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            cancel.setTitleColor(t.textStrong, for: .normal)
            cancel.backgroundColor = t.secondary
            cancel.layer.cornerRadius = 10
            cancel.clipsToBounds = true
            cancel.addTarget(self, action: #selector(reportCancelTapped), for: .touchUpInside)
            root.addSubview(cancel)

            NSLayoutConstraint.activate([
                cancel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
                cancel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                cancel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                cancel.heightAnchor.constraint(equalToConstant: 48),
                cancel.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])

            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
                root.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: padH),
                root.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
                root.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * padH),
            ])
        }

        scrollView.layoutIfNeeded()
    }
}
