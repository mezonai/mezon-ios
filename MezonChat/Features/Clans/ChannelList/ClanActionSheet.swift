import AsyncDisplayKit
import UIKit

enum ClanAction: CaseIterable {
    case invite
    case notifications
    case settings
    case markAsRead
    case createEvent
    case createCategory
    case editClanProfile
    case auditLog
    case leaveClan
    case deleteClan
    case showEmptyCategories

    var title: String {
        switch self {
        case .invite: return L(L10n.ClanAction.invite)
        case .notifications: return L(L10n.Common.notifications)
        case .settings: return L(L10n.Common.settings)
        case .markAsRead: return L(L10n.ClanAction.markAsRead)
        case .createEvent: return L(L10n.ClanAction.createEvent)
        case .createCategory: return L(L10n.ClanAction.createCategory)
        case .editClanProfile: return L(L10n.ClanAction.editClanProfile)
        case .auditLog: return L(L10n.ClanAction.auditLog)
        case .leaveClan: return L(L10n.ClanAction.leaveClan)
        case .deleteClan: return L(L10n.ClanAction.deleteClan)
        case .showEmptyCategories: return L(L10n.ClanAction.showEmptyCategories)
        }
    }

    var iconName: String? {
        switch self {
        case .invite: return "ClanSetting/InviteIcon"
        case .notifications: return "ClanSetting/BellIcon"
        case .settings: return "Profile/SettingIcon"
        case .markAsRead: return nil
        case .createEvent: return nil
        case .createCategory: return nil
        case .editClanProfile: return nil
        case .auditLog: return nil
        case .leaveClan: return nil
        case .deleteClan: return nil
        case .showEmptyCategories: return nil
        }
    }

    var isDestructive: Bool {
        self == .leaveClan || self == .deleteClan
    }
}

final class ClanActionSheetController: ViewController {

    private let clanName: String
    private let avatarURL: String
    private let memberCount: Int
    private let isCommunity: Bool
    private let onAction: (ClanAction) -> Void
    var onDismiss: (() -> Void)?

    private var sheetNode: ClanActionSheetNode {
        return displayNode as! ClanActionSheetNode
    }

    init(
        clanName: String, avatarURL: String, memberCount: Int, isCommunity: Bool,
        onAction: @escaping (ClanAction) -> Void
    ) {
        self.clanName = clanName
        self.avatarURL = avatarURL
        self.memberCount = memberCount
        self.isCommunity = isCommunity
        self.onAction = onAction

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = .Hide
        self.blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        self.displayNode = ClanActionSheetNode(
            clanName: clanName,
            avatarURL: avatarURL,
            memberCount: memberCount,
            isCommunity: isCommunity,
            onAction: { [weak self] action in
                guard let self else { return }
                self.animateDismiss {
                    self.onAction(action)
                }
            },
            onDimTapped: { [weak self] in
                self?.animateDismiss(completion: nil)
            }
        )
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition
    ) {
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
}

private final class ClanActionSheetNode: ASDisplayNode, UIGestureRecognizerDelegate,
    UIScrollViewDelegate
{

    private let dimmingNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private let handleNode: ASDisplayNode
    private let scrollView = UIScrollView()

    private let clanName: String
    private let avatarURL: String
    private let memberCount: Int
    private let isCommunity: Bool
    private let onAction: (ClanAction) -> Void
    private let onDimTapped: () -> Void

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var didBuildContent = false

    private var panGesture: UIPanGestureRecognizer!
    private var panStartY: CGFloat = 0
    private var isDraggingSheet = false

    private let padH: CGFloat = 16.sw
    private let handleH: CGFloat = 25.sh

    init(
        clanName: String, avatarURL: String, memberCount: Int, isCommunity: Bool,
        onAction: @escaping (ClanAction) -> Void, onDimTapped: @escaping () -> Void
    ) {
        self.clanName = clanName
        self.avatarURL = avatarURL
        self.memberCount = memberCount
        self.isCommunity = isCommunity
        self.onAction = onAction
        self.onDimTapped = onDimTapped

        self.dimmingNode = ASDisplayNode()
        self.containerNode = ASDisplayNode()
        self.handleNode = ASDisplayNode()

        super.init()

        self.dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        self.dimmingNode.alpha = 0

        let t = UIColor.theme
        self.containerNode.backgroundColor = t.primary
        self.containerNode.cornerRadius = 24.swh
        self.containerNode.clipsToBounds = true

        self.handleNode.backgroundColor = t.textDisabled.withAlphaComponent(0.5)
        self.handleNode.cornerRadius = 2.5

        self.addSubnode(dimmingNode)
        self.addSubnode(containerNode)
        self.containerNode.addSubnode(handleNode)
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        scrollView.delaysContentTouches = false
        containerNode.view.addSubview(scrollView)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
        scrollView.panGestureRecognizer.require(toFail: panGesture)
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            panStartY = containerNode.frame.origin.y
            isDraggingSheet = true

        case .changed:
            let offsetY = max(0, translation.y)
            containerNode.frame.origin.y = panStartY + offsetY
            dimmingNode.alpha = 1 - offsetY / containerHeight

        case .ended, .cancelled:
            isDraggingSheet = false
            if translation.y > containerHeight * 0.3 || velocity.y > 500 {
                onDimTapped()
            } else {
                let targetY = layout.size.height - containerHeight
                UIView.animate(
                    withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9,
                    initialSpringVelocity: 0, options: []
                ) {
                    self.containerNode.frame.origin.y = targetY
                    self.dimmingNode.alpha = 1
                }
            }

        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        let vel = panGesture.velocity(in: view)
        return scrollView.contentOffset.y <= 0 && vel.y > 0
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        let screenW = layout.size.width
        let safeBottom = layout.intrinsicInsets.bottom

        transition.updateFrame(node: dimmingNode, frame: CGRect(origin: .zero, size: layout.size))

        let topHeaderH: CGFloat = 160.sh
        let quickActionsH: CGFloat = 70.sh
        let listActionsH: CGFloat = 4 * 56.sh + 40.sh
        let toggleH: CGFloat = 80.sh

        let totalContentH = topHeaderH + quickActionsH + listActionsH + toggleH + 40.sh

        let maxScrollH = layout.size.height * 0.95 - handleH - safeBottom
        let scrollH = min(totalContentH, maxScrollH)
        containerHeight = handleH + scrollH + safeBottom + 20.sh

        let containerY = layout.size.height - containerHeight
        transition.updateFrame(
            node: containerNode,
            frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(
            node: handleNode,
            frame: CGRect(x: (screenW - 48.sw) / 2, y: 10.sh, width: 48.sw, height: 5.sh))

        scrollView.frame = CGRect(x: 0, y: handleH, width: screenW, height: scrollH)
        scrollView.contentSize = CGSize(width: screenW, height: totalContentH)
        scrollView.alwaysBounceVertical = totalContentH > scrollH

        if !didBuildContent {
            didBuildContent = true
            buildContent(screenW: screenW)
        }
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight

        containerNode.frame.origin.y = fromY
        UIView.animate(
            withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
            options: []
        ) {
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
        UIView.animate(
            withDuration: 0.2, delay: 0, options: .curveEaseIn,
            animations: {
                self.dimmingNode.alpha = 0
                self.containerNode.frame.origin.y = bottomY
            }
        ) { _ in
            completion()
        }
    }

    private func buildContent(screenW: CGFloat) {
        let contentW = screenW - padH * 2
        var y: CGFloat = 0


        let avatarSize: CGFloat = 64.swh
        let avatarContainer = UIView()
        avatarContainer.frame = CGRect(x: padH, y: y, width: avatarSize, height: avatarSize)
        avatarContainer.backgroundColor = colorFor(name: clanName)
        avatarContainer.layer.cornerRadius = 12.swh
        avatarContainer.clipsToBounds = true
        scrollView.addSubview(avatarContainer)

        let initialsLabel = UILabel()
        initialsLabel.text = initials(for: clanName)
        initialsLabel.font = .systemFont(ofSize: 24.sf, weight: .bold)
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        initialsLabel.frame = avatarContainer.bounds
        avatarContainer.addSubview(initialsLabel)

        let avatarImageView = UIImageView()
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.frame = avatarContainer.bounds
        avatarContainer.addSubview(avatarImageView)

        if !avatarURL.isEmpty {
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: avatarURL, width: 150, height: 150)) { [weak avatarImageView, weak initialsLabel] image in
                if let image = image {
                    avatarImageView?.image = image
                    initialsLabel?.isHidden = true
                }
            }
        }

        y += avatarSize + 12.sh

        let nameLabel = UILabel()
        nameLabel.text = clanName
        nameLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.frame = CGRect(x: padH, y: y, width: contentW, height: 28.sh)
        scrollView.addSubview(nameLabel)

        y += 48.sh

        let tagsStack = UIStackView()
        tagsStack.axis = .horizontal
        tagsStack.spacing = 12.sw
        tagsStack.alignment = .center
        tagsStack.distribution = .fill
        tagsStack.frame = CGRect(x: padH, y: y, width: contentW, height: 24.sh)
        scrollView.addSubview(tagsStack)

        if isCommunity {
            let commTag = createTagView(
                text: L(L10n.ClanAction.community), icon: "checkmark.seal.fill", bgColor: UIColor.theme.border,
                textColor: UIColor.theme.textDisabled)
            tagsStack.addArrangedSubview(commTag)
        }

        let membersTag = createDotTagView(text: L(L10n.ClanAction.memberCount, memberCount), dotColor: .gray)
        tagsStack.addArrangedSubview(membersTag)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tagsStack.addArrangedSubview(spacer)

        y += 48.sh

        let quickActions = [ClanAction.invite, .notifications, .settings]
        let quickActionsStack = UIStackView()
        quickActionsStack.axis = .horizontal
        quickActionsStack.distribution = .equalSpacing
        quickActionsStack.alignment = .top
        quickActionsStack.frame = CGRect(x: 16.sw, y: y, width: screenW - 32.sw, height: 80.sh)
        scrollView.addSubview(quickActionsStack)

        for action in quickActions {
            let btn = createQuickActionButton(action: action)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 80.sw).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 80.sh).isActive = true
            quickActionsStack.addArrangedSubview(btn)
        }

        y += 90.sh


        let groups: [[ClanAction]] = [
            [.markAsRead],
            [.createCategory, .createEvent],
            [.editClanProfile, .leaveClan, .deleteClan],
        ]

        for group in groups {
            let groupView = createActionGroup(actions: group, width: contentW)
            groupView.frame.origin = CGPoint(x: padH, y: y)
            scrollView.addSubview(groupView)
            y += groupView.frame.height + 12.sh
        }

        y += 8.sh


        let toggleRow = createToggleRow(action: .showEmptyCategories, width: contentW)
        toggleRow.frame.origin = CGPoint(x: padH, y: y)
        scrollView.addSubview(toggleRow)

        y += toggleRow.frame.height + 20.sh
        scrollView.contentSize.height = y
    }

    private func createTagView(text: String, icon: String?, bgColor: UIColor, textColor: UIColor)
        -> UIView
    {
        let v = UIView()
        v.backgroundColor = bgColor
        v.layer.cornerRadius = 10.swh

        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 11.sf, weight: .bold)
        l.textColor = textColor

        let stack = UIStackView(arrangedSubviews: [l])
        if let icon = icon {
            let iv = UIImageView(image: UIImage(systemName: icon))
            iv.contentMode = .scaleAspectFit
            iv.tintColor = textColor
            iv.widthAnchor.constraint(equalToConstant: 12.sw).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 12.sh).isActive = true
            stack.insertArrangedSubview(iv, at: 0)
        }
        stack.spacing = 4.sw
        stack.axis = .horizontal
        stack.alignment = .center

        v.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 4.sh),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4.sh),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4.sw),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4.sw),
        ])
        return v
    }

    private func createDotTagView(text: String, dotColor: UIColor) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.layer.cornerRadius = 14.swh

        let dot = UIView()
        dot.backgroundColor = dotColor
        dot.layer.cornerRadius = 3.swh
        dot.widthAnchor.constraint(equalToConstant: 6.sw).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6.sh).isActive = true

        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13.sf, weight: .medium)
        l.textColor = UIColor.theme.textDisabled

        let stack = UIStackView(arrangedSubviews: [dot, l])
        stack.spacing = 6.sw
        stack.axis = .horizontal
        stack.alignment = .center

        v.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 4.sh),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4.sh),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4.sw),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4.sw),
        ])
        return v
    }

    private func createQuickActionButton(action: ClanAction) -> UIView {
        let v = UIView()
        let iconBg = UIView()
        iconBg.backgroundColor = UIColor.theme.secondary
        iconBg.layer.cornerRadius = 24.swh
        iconBg.layer.borderWidth = 1.0
        iconBg.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.6).cgColor
        let iconView = UIImageView()
        if let name = action.iconName {
            if name.contains("/") {
                let needsOriginalRendering =
                    name == "ClanSetting/InviteIcon"
                    || name == "ClanSetting/BellIcon"
                    || name == "Profile/SettingIcon"

                let loadedImage = UIImage(named: name, in: Bundle.main, compatibleWith: nil)
                iconView.image = needsOriginalRendering
                    ? loadedImage?.withRenderingMode(.alwaysOriginal)
                    : loadedImage?.withRenderingMode(.alwaysTemplate)
            } else {
                // SF Symbols fallback.
                iconView.image = UIImage(systemName: name)
            }
        }
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.theme.textStrong

        let l = UILabel()
        l.text = action.title
        l.font = .systemFont(ofSize: 12.sf, weight: .medium)
        l.textColor = UIColor.theme.textDisabled
        l.textAlignment = .center

        v.addSubview(iconBg)
        iconBg.addSubview(iconView)
        v.addSubview(l)

        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        l.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconBg.topAnchor.constraint(equalTo: v.topAnchor),
            iconBg.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 48.swh),
            iconBg.heightAnchor.constraint(equalToConstant: 48.swh),

            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24.swh),
            iconView.heightAnchor.constraint(equalToConstant: 24.swh),

            l.topAnchor.constraint(equalTo: iconBg.bottomAnchor, constant: 8.sh),
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            l.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])

        let btn = UIButton(type: .custom)
        v.addSubview(btn)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: v.topAnchor),
            btn.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        let wrapper = ClanActionButton(type: .custom)
        wrapper.actionHandler = { [weak self] in self?.onAction(action) }
        wrapper.addTarget(wrapper, action: #selector(ClanActionButton.performAction), for: .touchUpInside)
        v.addSubview(wrapper)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: v.topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            wrapper.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])

        return v
    }

    private func createActionGroup(actions: [ClanAction], width: CGFloat) -> UIView {
        let groupH = CGFloat(actions.count) * 56.sh
        let v = UIView(frame: CGRect(x: 0, y: 0, width: width, height: groupH))
        v.backgroundColor = UIColor.theme.border
        v.layer.cornerRadius = 12.swh
        v.clipsToBounds = true

        for (i, action) in actions.enumerated() {
            let rowY = CGFloat(i) * 56.sh
            let row = createActionRow(action: action, width: width, height: 56.sh)
            row.frame.origin.y = rowY
            v.addSubview(row)

            if i < actions.count - 1 {
                let sep = UIView(
                    frame: CGRect(x: 0, y: rowY + 64.sh - 0.5, width: width, height: 0.5))
                sep.backgroundColor = UIColor.theme.border.withAlphaComponent(0.3)
                v.addSubview(sep)
            }
        }
        return v
    }

    private func createActionRow(action: ClanAction, width: CGFloat, height: CGFloat) -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let l = UILabel()
        l.text = action.title
        l.font = .systemFont(ofSize: 16.sf, weight: .medium)
        l.textColor = action.isDestructive ? .mezonError : UIColor.theme.textStrong

        v.addSubview(l)
        l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        let btn = ClanActionButton(type: .custom)
        btn.frame = v.bounds
        btn.actionHandler = { [weak self] in self?.onAction(action) }
        btn.addTarget(btn, action: #selector(ClanActionButton.performAction), for: .touchUpInside)
        v.addSubview(btn)

        return v
    }

    private func createToggleRow(action: ClanAction, width: CGFloat) -> UIView {
        let height: CGFloat = 64.sh
        let v = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        v.backgroundColor = UIColor.theme.border
        v.layer.cornerRadius = 12.swh

        let l = UILabel()
        l.text = action.title
        l.font = .systemFont(ofSize: 16.sf, weight: .medium)
        l.textColor = UIColor.theme.textStrong

        let sw = UISwitch()
        sw.onTintColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)

        v.addSubview(l)
        v.addSubview(sw)
        l.translatesAutoresizingMaskIntoConstraints = false
        sw.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            sw.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16.sw),
            sw.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        return v
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }

    private func colorFor(name: String) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1),
            UIColor(red: 0.23, green: 0.56, blue: 0.42, alpha: 1),
            UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 1),
            UIColor(red: 0.75, green: 0.52, blue: 0.18, alpha: 1),
            UIColor(red: 0.32, green: 0.52, blue: 0.78, alpha: 1),
            UIColor(red: 0.55, green: 0.28, blue: 0.68, alpha: 1),
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

private final class ClanActionButton: UIButton {
    var actionHandler: (() -> Void)?
    @objc func performAction() { actionHandler?() }
}
