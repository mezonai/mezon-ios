import UIKit
import AsyncDisplayKit

final class MemberProfileSheetController: ViewController {

    private let user: Mezon_Api_User
    private let context: AccountContext
    private let isCurrentUser: Bool
    private let onDismiss: (() -> Void)?
    private let onSendMessage: ((Mezon_Api_ChannelDescription) -> Void)?

    private var sheetNode: MemberProfileSheetNode { displayNode as! MemberProfileSheetNode }

    init(
        user: Mezon_Api_User,
        context: AccountContext,
        isCurrentUser: Bool = false,
        onDismiss: (() -> Void)? = nil,
        onSendMessage: ((Mezon_Api_ChannelDescription) -> Void)? = nil
    ) {
        self.user = user
        self.context = context
        self.isCurrentUser = isCurrentUser
        self.onDismiss = onDismiss
        self.onSendMessage = onSendMessage
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Hide
        self.blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = MemberProfileSheetNode(
            user: user,
            isCurrentUser: isCurrentUser,
            onSendMessageTapped: { [weak self] in
                self?.handleSendMessage()
            },
            onDimTapped: { [weak self] in
                self?.animateDismiss()
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

    private func animateDismiss() {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            self?.onDismiss?()
        }
    }

    private func handleSendMessage() {
        sheetNode.setLoading(true)

        Task { @MainActor in
            defer { sheetNode.setLoading(false) }

            guard let token = await context.getToken() else { return }
            let targetUserId = user.id

            let dmChannels = try? await context.account.network.listDirectMessageChannels(token: token)
            if let existing = dmChannels?.first(where: { ch in
                ch.type == MezonConstants.ChannelType.dm.rawValue
                && ch.userIds.count == 1
                && ch.userIds.contains(targetUserId)
            }) {
                animateDismiss()
                onSendMessage?(existing)
                return
            }

            do {
                let channel = try await context.account.network.createDirectMessage(
                    userId: targetUserId,
                    token: token
                )
                animateDismiss()
                onSendMessage?(channel)
            } catch {
                AppLogger.network.warning("[MemberProfile] createDirectMessage failed: \(error)")
            }
        }
    }
}

private final class MemberProfileSheetNode: ASDisplayNode {

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let scrollView = UIScrollView()
    private let handleNode = ASDisplayNode()

    private let bannerNode = ASDisplayNode()

    private let avatarNode = ASNetworkImageNode()
    private let statusDotNode = ASDisplayNode()

    private let infoCardNode = ASDisplayNode()
    private let displayNameNode = ASTextNode2()
    private let usernameNode = ASTextNode2()

    private let actionRow = ASDisplayNode()
    private let messageBtn = ProfileActionButton(icon: "bubble.left.fill", title: "Message")
    private let callBtn = ProfileActionButton(icon: "phone.fill", title: "Call")
    private let addFriendBtn = ProfileActionButton(icon: "person.badge.plus", title: "Add Friend", isGreen: true)

    private let memberCardNode = ASDisplayNode()
    private let memberSinceTitleNode = ASTextNode2()
    private let memberSinceDateNode = ASTextNode2()

    private let onSendMessageTapped: () -> Void
    private let onDimTapped: () -> Void
    private let isCurrentUser: Bool

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let user: Mezon_Api_User

    init(
        user: Mezon_Api_User,
        isCurrentUser: Bool,
        onSendMessageTapped: @escaping () -> Void,
        onDimTapped: @escaping () -> Void
    ) {
        self.user = user
        self.isCurrentUser = isCurrentUser
        self.onSendMessageTapped = onSendMessageTapped
        self.onDimTapped = onDimTapped
        super.init()

        let t = UIColor.theme

        dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingNode.alpha = 0

        containerNode.backgroundColor = t.primary
        containerNode.cornerRadius = 14.sf
        containerNode.clipsToBounds = true

        handleNode.backgroundColor = t.textDisabled
        handleNode.cornerRadius = 2.5.sf

        bannerNode.backgroundColor = avatarColor(for: user)

        let avatarSize: CGFloat = 80.sf
        avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = t.tertiary
        avatarNode.borderWidth = 4.sf
        avatarNode.borderColor = t.primary.cgColor
        if !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL) {
            avatarNode.url = url
        }

        statusDotNode.backgroundColor = user.online ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1) : UIColor.gray
        statusDotNode.cornerRadius = 8.sf
        statusDotNode.borderWidth = 3.sf
        statusDotNode.borderColor = t.primary.cgColor

        infoCardNode.backgroundColor = t.secondary
        infoCardNode.cornerRadius = 10.sf

        let name = user.displayName.isEmpty ? user.username : user.displayName
        displayNameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: t.textStrong,
            ]
        )

        if !user.username.isEmpty {
            usernameNode.attributedText = NSAttributedString(
                string: user.username,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf),
                    .foregroundColor: t.textDisabled,
                ]
            )
        }

        actionRow.backgroundColor = .clear

        memberCardNode.backgroundColor = t.secondary
        memberCardNode.cornerRadius = 10.sf

        memberSinceTitleNode.attributedText = NSAttributedString(
            string: "MEZON MEMBER SINCE",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11.sf, weight: .bold),
                .foregroundColor: t.textStrong,
            ]
        )

        let dateString: String
        if user.createTimeSeconds > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(user.createTimeSeconds))
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM dd, yyyy"
            dateString = formatter.string(from: date)
        } else {
            dateString = "N/A"
        }
        memberSinceDateNode.attributedText = NSAttributedString(
            string: dateString,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.textDisabled,
            ]
        )

        addSubnode(dimmingNode)
        addSubnode(containerNode)
        containerNode.addSubnode(handleNode)
        containerNode.addSubnode(bannerNode)
        containerNode.addSubnode(infoCardNode)
        infoCardNode.addSubnode(displayNameNode)
        infoCardNode.addSubnode(usernameNode)
        infoCardNode.addSubnode(actionRow)
        actionRow.addSubnode(messageBtn)
        actionRow.addSubnode(callBtn)
        actionRow.addSubnode(addFriendBtn)
        containerNode.addSubnode(memberCardNode)
        memberCardNode.addSubnode(memberSinceTitleNode)
        memberCardNode.addSubnode(memberSinceDateNode)
        containerNode.addSubnode(avatarNode)
        containerNode.addSubnode(statusDotNode)
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = UIColor.theme.textDisabled
        containerNode.view.addSubview(loadingIndicator)

        messageBtn.onTapped = { [weak self] in self?.messageTapped() }
        callBtn.onTapped = { [weak self] in self?.callTapped() }
        addFriendBtn.onTapped = { [weak self] in self?.addFriendTapped() }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        containerNode.view.addGestureRecognizer(pan)
    }

    @objc private func dimTapped() { onDimTapped() }
    private func messageTapped() { onSendMessageTapped() }
    private func callTapped() {  }
    private func addFriendTapped() {  }

    private var panStartY: CGFloat = 0

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        switch gesture.state {
        case .began:
            panStartY = containerNode.frame.origin.y
        case .changed:
            let ty = gesture.translation(in: view).y
            let newY = max(panStartY + ty, layout.size.height - containerHeight)
            containerNode.frame.origin.y = newY
        case .ended, .cancelled:
            let vel = gesture.velocity(in: view).y
            if vel > 500 || containerNode.frame.origin.y > layout.size.height - containerHeight / 2 {
                animateOut { [weak self] in self?.onDimTapped() }
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                    self.containerNode.frame.origin.y = layout.size.height - self.containerHeight
                }
            }
        default: break
        }
    }

    func setLoading(_ loading: Bool) {
        if loading {
            loadingIndicator.startAnimating()
            messageBtn.isUserInteractionEnabled = false
            messageBtn.alpha = 0.5
        } else {
            loadingIndicator.stopAnimating()
            messageBtn.isUserInteractionEnabled = true
            messageBtn.alpha = 1
        }
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeBottom = layout.intrinsicInsets.bottom
        let screenW = layout.size.width
        let pad: CGFloat = 16

        transition.updateFrame(node: dimmingNode, frame: bounds)

        let handleH: CGFloat = 25.sh

        let bannerH: CGFloat = 100.sh

        let avatarSize: CGFloat = 80.sf
        let avatarOverlap: CGFloat = avatarSize / 2
        let avatarTop = handleH + bannerH - avatarOverlap
        let avatarX: CGFloat = 20.sf

        let infoCardTop = handleH + bannerH + 8.sh
        let infoCardPad: CGFloat = 16.sf

        let nameSize = displayNameNode.measure(CGSize(width: screenW - pad * 2 - infoCardPad * 2, height: .greatestFiniteMagnitude))
        let userSize = usernameNode.attributedText != nil
            ? usernameNode.measure(CGSize(width: screenW - pad * 2 - infoCardPad * 2, height: .greatestFiniteMagnitude))
            : .zero

        let btnH: CGFloat = 64.sh
        let btnSpacing: CGFloat = 8.sf
        let actionW = screenW - pad * 2 - infoCardPad * 2
        let showCallAndAddFriend = !isCurrentUser
        callBtn.isHidden = !showCallAndAddFriend
        addFriendBtn.isHidden = !showCallAndAddFriend
        let btnW: CGFloat
        if showCallAndAddFriend {
            btnW = (actionW - btnSpacing * 2) / 3
        } else {
            btnW = actionW
        }

        var infoY: CGFloat = avatarOverlap + 8.sh
        displayNameNode.frame = CGRect(x: infoCardPad, y: infoY, width: nameSize.width, height: nameSize.height)
        infoY += nameSize.height + 2

        if userSize != .zero {
            usernameNode.frame = CGRect(x: infoCardPad, y: infoY, width: userSize.width, height: userSize.height)
            infoY += userSize.height
        }

        infoY += 12
        actionRow.frame = CGRect(x: infoCardPad, y: infoY, width: actionW, height: btnH)
        messageBtn.frame = CGRect(x: 0, y: 0, width: btnW, height: btnH)
        if showCallAndAddFriend {
            callBtn.frame = CGRect(x: btnW + btnSpacing, y: 0, width: btnW, height: btnH)
            addFriendBtn.frame = CGRect(x: (btnW + btnSpacing) * 2, y: 0, width: btnW, height: btnH)
        }
        infoY += btnH + infoCardPad

        let infoCardH = infoY
        infoCardNode.frame = CGRect(x: pad, y: infoCardTop, width: screenW - pad * 2, height: infoCardH)

        let memberCardTop = infoCardTop + infoCardH + 8
        var memberY: CGFloat = 12

        let memberW = screenW - pad * 2 - infoCardPad * 2

        let sinceTitleSize = memberSinceTitleNode.measure(CGSize(width: memberW, height: .greatestFiniteMagnitude))
        memberSinceTitleNode.frame = CGRect(x: infoCardPad, y: memberY, width: sinceTitleSize.width, height: sinceTitleSize.height)
        memberY += sinceTitleSize.height + 4

        if memberSinceDateNode.attributedText != nil {
            let dateSize = memberSinceDateNode.measure(CGSize(width: memberW, height: .greatestFiniteMagnitude))
            memberSinceDateNode.frame = CGRect(x: infoCardPad, y: memberY, width: dateSize.width, height: dateSize.height)
            memberY += dateSize.height + 12
        }

        let memberCardH = memberY
        memberCardNode.frame = CGRect(x: pad, y: memberCardTop, width: screenW - pad * 2, height: memberCardH)
        memberCardNode.isHidden = (user.createTimeSeconds == 0)

        let totalH = (user.createTimeSeconds > 0 ? memberCardTop + memberCardH : infoCardTop + infoCardH) + safeBottom + 16
        containerHeight = totalH

        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))

        bannerNode.frame = CGRect(x: 0, y: 0, width: screenW, height: handleH + bannerH)
        avatarNode.frame = CGRect(x: avatarX, y: avatarTop, width: avatarSize, height: avatarSize)
        statusDotNode.frame = CGRect(
            x: avatarX + avatarSize - 20.sf,
            y: avatarTop + avatarSize - 20.sh,
            width: 16.sf, height: 16.sh
        )
        handleNode.frame = CGRect(x: (screenW - 36.sf) / 2, y: 8.sh, width: 36.sf, height: 5.sh)

        loadingIndicator.center = CGPoint(x: screenW / 2, y: containerHeight / 2)
    }


    func animateIn() {
        guard let layout = validLayout else { return }
        containerNode.frame.origin.y = layout.size.height
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame.origin.y = layout.size.height - self.containerHeight
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else { completion(); return }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame.origin.y = layout.size.height
        }) { _ in
            completion()
        }
    }

    private func avatarColor(for user: Mezon_Api_User) -> UIColor {
        let hash = abs(user.username.hashValue)
        let hue = CGFloat(hash % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.3, brightness: 0.35, alpha: 1)
    }
}


private final class ProfileActionButton: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let isGreen: Bool

    var onTapped: (() -> Void)?

    init(icon: String, title: String, isGreen: Bool = false) {
        self.isGreen = isGreen
        super.init()

        let t = UIColor.theme
        backgroundColor = t.tertiary
        cornerRadius = 10.sf

        let color = isGreen ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1) : t.textStrong
        iconNode.image = UIImage(systemName: icon)?.withRenderingMode(.alwaysTemplate)
        iconNode.tintColor = color
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 24.sf, height: 24.sh)

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11.sf, weight: .medium),
                .foregroundColor: color,
            ]
        )

        addSubnode(iconNode)
        addSubnode(titleNode)
    }

    override func didLoad() {
        super.didLoad()
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTapped?()
    }

    override func layout() {
        super.layout()
        let b = bounds
        let iconSize: CGFloat = 24.sf
        let titleSize = titleNode.measure(CGSize(width: b.width - 8.sf, height: .greatestFiniteMagnitude))
        let totalH = iconSize + 4.sh + titleSize.height
        let topY = (b.height - totalH) / 2

        iconNode.frame = CGRect(x: (b.width - iconSize) / 2, y: topY, width: iconSize, height: iconSize)
        titleNode.frame = CGRect(x: (b.width - titleSize.width) / 2, y: topY + iconSize + 4.sh, width: titleSize.width, height: titleSize.height)
    }
}
