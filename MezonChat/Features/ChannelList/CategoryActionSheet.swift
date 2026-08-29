import UIKit
import AsyncDisplayKit

enum CategoryAction: CaseIterable {
    case createChannel

    var title: String {
        switch self {
        case .createChannel: return L(L10n.ChannelSetting.createChannel)
        }
    }

    var icon: String? {
        switch self {
        case .createChannel: return "ChannelSetting/CreateChannelIcon"
        }
    }

    var isDestructive: Bool { false }
}

final class CategoryActionSheetController: ViewController {
    private let categoryId: Int64
    private let categoryName: String
    private let clanName: String
    private let clanAvatarURL: String
    private let onAction: (CategoryAction) -> Void
    private var didRunEntranceAnimation = false

    init(categoryId: Int64, categoryName: String, clanName: String, clanAvatarURL: String, onAction: @escaping (CategoryAction) -> Void) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.clanName = clanName
        self.clanAvatarURL = clanAvatarURL
        self.onAction = onAction
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder: NSCoder) { fatalError() }

    private var actionSheetNode: CategoryActionSheetNode { displayNode as! CategoryActionSheetNode }

    override func loadDisplayNode() {
        displayNode = CategoryActionSheetNode(
            categoryId: categoryId,
            categoryName: categoryName,
            clanName: clanName,
            clanAvatarURL: clanAvatarURL,
            onAction: { [weak self] action in
                self?.dismissThenCallAction(action)
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        self.displayNodeDidLoad()
    }

    private func dismissThenCallAction(_ action: CategoryAction) {
        let callback = self.onAction
        actionSheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            DispatchQueue.main.async { callback(action) }
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        actionSheetNode.updateLayout(layout: layout, transition: transition)
        guard !didRunEntranceAnimation, layout.size.width > 1, layout.size.height > 1 else { return }
        didRunEntranceAnimation = true
        actionSheetNode.animateIn()
    }

    private func dismiss() {
        actionSheetNode.animateOut { [weak self] in self?.dismiss(animated: false) }
    }
}

private final class CategoryActionSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {
    private let dimNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let scrollNode = ASScrollNode()

    private let categoryId: Int64
    private let categoryName: String
    private let clanName: String
    private let clanAvatarURL: String
    private let onAction: (CategoryAction) -> Void
    private let onDismiss: () -> Void

    private var panGesture: UIPanGestureRecognizer!
    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var didBuildContent = false

    init(categoryId: Int64, categoryName: String, clanName: String, clanAvatarURL: String, onAction: @escaping (CategoryAction) -> Void, onDismiss: @escaping () -> Void) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.clanName = clanName
        self.clanAvatarURL = clanAvatarURL
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init()

        dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimNode.alpha = 0
        addSubnode(dimNode)

        containerNode.backgroundColor = UIColor.theme.primary
        containerNode.cornerRadius = 24.swh
        addSubnode(containerNode)

        handleNode.backgroundColor = UIColor.theme.textDisabled
        handleNode.cornerRadius = 2.5
        containerNode.addSubnode(handleNode)

        scrollNode.automaticallyManagesSubnodes = false
        scrollNode.automaticallyManagesContentSize = false
        containerNode.addSubnode(scrollNode)
    }

    override func didLoad() {
        super.didLoad()
        dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDimTap)))
        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
    }

    @objc private func handleDimTap() { onDismiss() }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        dimNode.frame = CGRect(origin: .zero, size: layout.size)
        let contentW = layout.size.width
        let safeBottom = layout.intrinsicInsets.bottom
        let groups = [[CategoryAction.createChannel]]
        var groupsH: CGFloat = 0
        for group in groups { groupsH += CGFloat(group.count) * 48.sh + 12.sh }
        let totalContentH = 48.swh + 16.sh + 24.sh + groupsH + safeBottom
        containerHeight = min(totalContentH + 40.sh, layout.size.height * 0.9)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: layout.size.height - containerHeight, width: contentW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (contentW - 40.sw) / 2, y: 8.sh, width: 40.sw, height: 5.sh))
        let scrollY: CGFloat = 8.sh + 5.sh + 16.sh + 48.swh + 24.sh
        scrollNode.frame = CGRect(x: 0, y: scrollY, width: contentW, height: containerHeight - scrollY - safeBottom)
        scrollNode.view.contentSize = CGSize(width: contentW, height: groupsH + 16.sh)
        if !didBuildContent {
            didBuildContent = true
            buildContent(width: contentW)
        }
    }

    private func buildContent(width: CGFloat) {
        let header = buildHeader(width: width)
        header.frame = CGRect(x: 16.sw, y: 24.sh, width: width - 32.sw, height: 56.swh)
        containerNode.view.addSubview(header)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.sh
        stack.frame = CGRect(x: 16.sw, y: 0, width: width - 32.sw, height: 0)
        scrollNode.view.addSubview(stack)

        stack.addArrangedSubview(buildGroup(actions: [.createChannel], width: width - 32.sw))
        stack.layoutIfNeeded()
        stack.frame.size.height = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        scrollNode.view.contentSize = CGSize(width: width, height: stack.frame.size.height + 20.sh)
    }

    private func buildHeader(width: CGFloat) -> UIView {
        let v = UIView()
        
        let avatarSize: CGFloat = 40.swh
        
        let avatar = TextAvatarView(username: clanName, size: avatarSize, fontSize: 16.sf)
        avatar.layer.cornerRadius = 8
        avatar.frame = CGRect(x: 0, y: (56.sh - avatarSize) / 2, width: avatarSize, height: avatarSize)
        v.addSubview(avatar)
        
        let avatarImageView = UIImageView(frame: avatar.bounds)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatar.addSubview(avatarImageView)

        if !clanAvatarURL.isEmpty {
            avatar.showImageMode()
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: clanAvatarURL, width: 150, height: 150)) { [weak avatarImageView, weak avatar] image in
                if let image = image {
                    avatarImageView?.image = image
                } else {
                    avatar?.showPlaceholder()
                }
            }
        }
        
        let labelX = 40.swh + 12.sw
        let labelW = width - 32.sw - labelX
        
        let nameLabel = UILabel(frame: CGRect(x: labelX, y: 16.sh, width: labelW, height: 24.sh))
        nameLabel.text = categoryName.uppercased()
        nameLabel.font = .systemFont(ofSize: 14.sf, weight: .bold)
        nameLabel.textColor = UIColor.theme.textDisabled
        v.addSubview(nameLabel)
        
        return v
    }

    private func buildGroup(actions: [CategoryAction], width: CGFloat) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.theme.secondary
        v.layer.cornerRadius = 12
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        v.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        for (idx, action) in actions.enumerated() {
            stack.addArrangedSubview(buildActionRow(action: action))
            if idx < actions.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }
        return v
    }

    private func buildActionRow(action: CategoryAction) -> UIView {
        let v = UIButton(type: .system)
        v.backgroundColor = .clear
        let icon = UIImageView()
        icon.image = UIImage.mezonSystemImage("plus")?.withRenderingMode(.alwaysTemplate)
        icon.tintColor = UIColor.theme.textStrong
        icon.contentMode = .scaleAspectFit
        v.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24.swh),
            icon.heightAnchor.constraint(equalToConstant: 24.swh),
        ])
        let l = UILabel()
        l.text = action.title
        l.font = .systemFont(ofSize: 14.sf, weight: .medium)
        l.textColor = UIColor.theme.textStrong
        v.addSubview(l)
        l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12.sw),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16.sw),
        ])
        v.heightAnchor.constraint(equalToConstant: 56.sh).isActive = true
        let wrapper = CategoryActionButton(type: .custom)
        wrapper.actionHandler = { [weak self] in self?.onAction(action) }
        wrapper.addTarget(wrapper, action: #selector(CategoryActionButton.performAction), for: .touchUpInside)
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

    func animateIn() {
        guard let layout = validLayout else { return }
        let toY = layout.size.height - containerHeight
        containerNode.frame.origin.y = layout.size.height
        dimNode.alpha = 0
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut) {
            self.containerNode.frame.origin.y = toY
            self.dimNode.alpha = 1
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else { completion(); return }
        UIView.animate(withDuration: 0.2, animations: {
            self.containerNode.frame.origin.y = layout.size.height
            self.dimNode.alpha = 0
        }) { _ in completion() }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began: break
        case .changed:
            if translation.y > 0 {
                containerNode.frame.origin.y = (layout.size.height - containerHeight) + translation.y
                dimNode.alpha = 1 - (translation.y / containerHeight)
            }
        case .ended:
            if translation.y > 100 { onDismiss() }
            else {
                UIView.animate(withDuration: 0.3) {
                    self.containerNode.frame.origin.y = layout.size.height - self.containerHeight
                    self.dimNode.alpha = 1
                }
            }
        default: break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let vel = gesture.velocity(in: view)
        return vel.y > 0 && scrollNode.view.contentOffset.y <= 0
    }
}

private final class CategoryActionButton: UIButton {
    var actionHandler: (() -> Void)?
    @objc func performAction() { actionHandler?() }
}
