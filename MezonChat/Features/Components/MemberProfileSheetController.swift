import UIKit
import AsyncDisplayKit

struct MemberProfileVoiceChannelActions {
    let showMute: Bool
    let showKick: Bool
    let confirmUserLabel: String
    let onMute: () async throws -> Void
    let onKick: () async throws -> Void
}

private final class VoiceActionClosureButton: UIButton {
    var onTap: (() -> Void)?
    init() {
        super.init(frame: .zero)
        addTarget(self, action: #selector(invoke), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() {
        onTap?()
    }
}

private func memberProfileMakeVoiceManagePill(systemName: String, title: String, action: @escaping () -> Void) -> UIButton {
    let b = VoiceActionClosureButton()
    b.translatesAutoresizingMaskIntoConstraints = false
    b.backgroundColor = UIColor.theme.primary
    b.layer.cornerRadius = 8
    b.clipsToBounds = true
    b.onTap = action
    let iv = UIImageView(image: UIImage(systemName: systemName)?.withRenderingMode(.alwaysTemplate))
    iv.tintColor = UIColor(red: 0.92, green: 0.25, blue: 0.25, alpha: 1)
    iv.contentMode = .scaleAspectFit
    iv.translatesAutoresizingMaskIntoConstraints = false
    let lab = UILabel()
    lab.text = title
    lab.font = .systemFont(ofSize: 14.sf, weight: .regular)
    lab.textColor = UIColor(red: 0.92, green: 0.25, blue: 0.25, alpha: 1)
    let row = UIStackView(arrangedSubviews: [iv, lab])
    row.isUserInteractionEnabled = false
    row.axis = .horizontal
    row.spacing = 6
    row.alignment = .center
    row.translatesAutoresizingMaskIntoConstraints = false
    b.addSubview(row)
    NSLayoutConstraint.activate([
        iv.widthAnchor.constraint(equalToConstant: 18),
        iv.heightAnchor.constraint(equalToConstant: 18),
        row.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 10),
        row.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -10),
        row.topAnchor.constraint(equalTo: b.topAnchor, constant: 10),
        row.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -10),
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
    ])
    return b
}

@MainActor
private final class VoiceChannelMeetActionConfirmViewController: UIViewController {

    enum Kind {
        case mute
        case kick
    }

    private let kind: Kind
    private let userLabel: String
    private let onConfirm: () -> Void

    init(kind: Kind, userLabel: String, onConfirm: @escaping () -> Void) {
        self.kind = kind
        self.userLabel = userLabel
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.theme.secondary
        card.layer.cornerRadius = 14
        card.clipsToBounds = true

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = UIColor.theme.textDisabled
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        switch kind {
        case .mute:
            titleLabel.text = NSLocalizedString(
                "voiceChannel.muteModal.title", tableName: nil, bundle: .main, value: "Mute member", comment: "")
            bodyLabel.text = String(format: NSLocalizedString(
                "voiceChannel.muteModal.content", tableName: nil, bundle: .main,
                value: "Please confirm if you would like to mute \"%@\"?", comment: ""), userLabel)
        case .kick:
            titleLabel.text = NSLocalizedString(
                "voiceChannel.kickModal.title", tableName: nil, bundle: .main, value: "Kick member", comment: "")
            bodyLabel.text = String(format: NSLocalizedString(
                "voiceChannel.kickModal.content", tableName: nil, bundle: .main,
                value: "Please confirm if you would like to kick \"%@\"?", comment: ""), userLabel)
        }

        let confirmTitle: String
        switch kind {
        case .mute:
            confirmTitle = NSLocalizedString(
                "voiceChannel.muteModal.mute", tableName: nil, bundle: .main, value: "Mute", comment: "")
        case .kick:
            confirmTitle = NSLocalizedString(
                "voiceChannel.kickModal.kick", tableName: nil, bundle: .main, value: "Kick", comment: "")
        }

        let confirmBtn = UIButton(type: .system)
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.setTitle(confirmTitle, for: .normal)
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        confirmBtn.setTitleColor(.white, for: .normal)
        confirmBtn.backgroundColor = UIColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1)
        confirmBtn.layer.cornerRadius = 12
        confirmBtn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.setTitle(
            NSLocalizedString("voiceChannel.cancel", tableName: nil, bundle: .main, value: "Cancel", comment: ""),
            for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelBtn.setTitleColor(UIColor.theme.textStrong, for: .normal)
        cancelBtn.backgroundColor = UIColor.theme.tertiary
        cancelBtn.layer.cornerRadius = 12
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        view.addSubview(card)
        card.addSubview(titleLabel)
        card.addSubview(bodyLabel)
        card.addSubview(confirmBtn)
        card.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            bodyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            confirmBtn.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 22),
            confirmBtn.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            confirmBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            confirmBtn.heightAnchor.constraint(equalToConstant: 48),

            cancelBtn.topAnchor.constraint(equalTo: confirmBtn.bottomAnchor, constant: 10),
            cancelBtn.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            cancelBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            cancelBtn.heightAnchor.constraint(equalToConstant: 48),
            cancelBtn.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func confirmTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onConfirm()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func backgroundTapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        guard let card = view.subviews.first else { return }
        if !card.frame.contains(p) {
            dismiss(animated: true)
        }
    }
}

final class MemberProfileSheetController: ViewController {

    private let user: Mezon_Api_User
    private let context: AccountContext
    private let isCurrentUser: Bool
    private let voiceChannelActions: MemberProfileVoiceChannelActions?
    private let onDismiss: (() -> Void)?
    private let onSendMessage: ((Mezon_Api_ChannelDescription) -> Void)?

    private var sheetNode: MemberProfileSheetNode { displayNode as! MemberProfileSheetNode }

    init(
        user: Mezon_Api_User,
        context: AccountContext,
        isCurrentUser: Bool = false,
        voiceChannelActions: MemberProfileVoiceChannelActions? = nil,
        onDismiss: (() -> Void)? = nil,
        onSendMessage: ((Mezon_Api_ChannelDescription) -> Void)? = nil
    ) {
        self.user = user
        self.context = context
        self.isCurrentUser = isCurrentUser
        self.voiceChannelActions = voiceChannelActions
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
            voiceChannelActions: voiceChannelActions,
            onSendMessageTapped: { [weak self] in
                self?.handleSendMessage()
            },
            onDimTapped: { [weak self] in
                self?.animateDismiss()
            },
            onVoiceMuteTap: { [weak self] in
                self?.presentVoiceMuteConfirm()
            },
            onVoiceKickTap: { [weak self] in
                self?.presentVoiceKickConfirm()
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

    private func presentVoiceMuteConfirm() {
        guard let actions = voiceChannelActions, actions.showMute else { return }
        let vc = VoiceChannelMeetActionConfirmViewController(kind: .mute, userLabel: actions.confirmUserLabel) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await actions.onMute()
                    self.animateDismiss()
                } catch {
                    self.presentVoiceMeetError(error)
                }
            }
        }
        present(vc, animated: true)
    }

    private func presentVoiceKickConfirm() {
        guard let actions = voiceChannelActions, actions.showKick else {
            return
        }
        let vc = VoiceChannelMeetActionConfirmViewController(kind: .kick, userLabel: actions.confirmUserLabel) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await actions.onKick()
                    self.animateDismiss()
                } catch {
                    self.presentVoiceMeetError(error)
                }
            }
        }
        present(vc, animated: true)
    }

    private func presentVoiceMeetError(_ error: Error) {
        let ac = UIAlertController(
            title: NSLocalizedString(
                "voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
            message: error.localizedDescription,
            preferredStyle: .alert)
        ac.addAction(UIAlertAction(
            title: NSLocalizedString("voiceChannel.ok", tableName: nil, bundle: .main, value: "OK", comment: ""),
            style: .default))
        present(ac, animated: true)
    }

    private func handleSendMessage() {
        sheetNode.setLoading(true)

        Task { @MainActor in
            defer { sheetNode.setLoading(false) }

            guard let token = await context.getToken() else { return }
            guard user.id != 0 else { return }
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
    private let onVoiceMuteTap: () -> Void
    private let onVoiceKickTap: () -> Void
    private let isCurrentUser: Bool
    private let voiceChannelActions: MemberProfileVoiceChannelActions?

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let user: Mezon_Api_User
    private let voiceCardNode = ASDisplayNode()
    private var voiceSettingsHost: UIView?
    private weak var voiceSettingsColumn: UIStackView?

    private enum VoiceSettingsContentInsets {
        static var vertical: CGFloat { 0.sh }
        static var leading: CGFloat { 2.sf }
    }

    init(
        user: Mezon_Api_User,
        isCurrentUser: Bool,
        voiceChannelActions: MemberProfileVoiceChannelActions?,
        onSendMessageTapped: @escaping () -> Void,
        onDimTapped: @escaping () -> Void,
        onVoiceMuteTap: @escaping () -> Void,
        onVoiceKickTap: @escaping () -> Void
    ) {
        self.user = user
        self.isCurrentUser = isCurrentUser
        self.voiceChannelActions = voiceChannelActions
        self.onSendMessageTapped = onSendMessageTapped
        self.onDimTapped = onDimTapped
        self.onVoiceMuteTap = onVoiceMuteTap
        self.onVoiceKickTap = onVoiceKickTap
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
        avatarNode.isUserInteractionEnabled = false

        statusDotNode.backgroundColor = user.online ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1) : UIColor.gray
        statusDotNode.cornerRadius = 8.sf
        statusDotNode.borderWidth = 3.sf
        statusDotNode.borderColor = t.primary.cgColor
        statusDotNode.isUserInteractionEnabled = false

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
        if voiceChannelActions != nil {
            voiceCardNode.backgroundColor = UIColor.theme.secondary
            voiceCardNode.cornerRadius = 10.sf
            voiceCardNode.isUserInteractionEnabled = true
        }
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
        if voiceChannelActions != nil {
            containerNode.addSubnode(voiceCardNode)
        }
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        bannerNode.layer.zPosition = 0
        handleNode.layer.zPosition = 1
        infoCardNode.layer.zPosition = 2
        memberCardNode.layer.zPosition = 2
        voiceCardNode.layer.zPosition = voiceChannelActions != nil ? 8 : 0
        avatarNode.layer.zPosition = 10
        statusDotNode.layer.zPosition = 11

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = UIColor.theme.textDisabled
        containerNode.view.addSubview(loadingIndicator)

        messageBtn.onTapped = { [weak self] in self?.messageTapped() }
        callBtn.onTapped = { [weak self] in self?.callTapped() }
        addFriendBtn.onTapped = { [weak self] in self?.addFriendTapped() }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        containerNode.view.addGestureRecognizer(pan)

        if let va = voiceChannelActions {
            let host = UIView()
            host.translatesAutoresizingMaskIntoConstraints = true
            host.backgroundColor = .clear
            host.isUserInteractionEnabled = true

            let title = UILabel()
            title.translatesAutoresizingMaskIntoConstraints = true
            title.font = .systemFont(ofSize: 15.sf, weight: .semibold)
            title.textColor = UIColor.theme.textStrong
            title.numberOfLines = 0
            title.text = NSLocalizedString(
                "voiceChannel.shortProfile.channelVoiceSettings", tableName: nil, bundle: .main,
                value: "Channel voice settings", comment: "")

            let row = UIStackView()
            row.translatesAutoresizingMaskIntoConstraints = true
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .center
            row.distribution = .fill

            if va.showMute {
                row.addArrangedSubview(memberProfileMakeVoiceManagePill(
                    systemName: "mic.slash.fill",
                    title: NSLocalizedString(
                        "voiceChannel.shortProfile.muteVoice", tableName: nil, bundle: .main, value: "Mute", comment: ""),
                    action: { [weak self] in self?.onVoiceMuteTap() }))
            }
            if va.showKick {
                row.addArrangedSubview(memberProfileMakeVoiceManagePill(
                    systemName: "person.fill.badge.minus",
                    title: NSLocalizedString(
                        "voiceChannel.shortProfile.kickVoice", tableName: nil, bundle: .main, value: "Kick", comment: ""),
                    action: { [weak self] in self?.onVoiceKickTap() }))
            }

            let column = UIStackView(arrangedSubviews: [title, row])
            column.translatesAutoresizingMaskIntoConstraints = true
            column.axis = .vertical
            column.spacing = 12
            column.alignment = .leading

            host.addSubview(column)
            voiceCardNode.view.addSubview(host)
            voiceSettingsHost = host
            voiceSettingsColumn = column
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let fallback = super.hitTest(point, with: event)
        if voiceChannelActions != nil,
           voiceCardNode.supernode === containerNode,
           !voiceCardNode.isHidden,
           voiceCardNode.frame.height > 1 {
            let inVoice = voiceCardNode.view.convert(point, from: self.view)
            let inside = voiceCardNode.view.point(inside: inVoice, with: event)
            if inside {
                let voiceRoot = voiceCardNode.view
                for sub in voiceRoot.subviews.reversed() {
                    let inSub = sub.convert(inVoice, from: voiceRoot)
                    if let h = sub.hitTest(inSub, with: event) {
                        return h
                    }
                }
                if let v = voiceRoot.hitTest(inVoice, with: event), v !== voiceRoot {
                    return v
                }
            }
        }
        return fallback
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

        let infoCardPad: CGFloat = 20.sf
        let infoBottomPad = infoCardPad + 4.sh

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

        let cardW = screenW - pad * 2

        var voiceCardH: CGFloat = 0
        var voiceHostLayout: (host: UIView, contentW: CGFloat, hostH: CGFloat, columnW: CGFloat, colH: CGFloat, insetV: CGFloat, insetL: CGFloat, voiceCardOuterV: CGFloat)?
        if let host = voiceSettingsHost, let col = voiceSettingsColumn {
            let contentW = cardW - infoCardPad * 2
            let insetL = VoiceSettingsContentInsets.leading
            let insetV = VoiceSettingsContentInsets.vertical
            let columnW = max(1, contentW - insetL)
            let colH = ceil(col.systemLayoutSizeFitting(
                CGSize(width: columnW, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height)
            let hostH = insetV + colH + insetV
            let voiceCardOuterV = infoCardPad
            voiceCardH = voiceCardOuterV + hostH + voiceCardOuterV
            voiceHostLayout = (host, contentW, hostH, columnW, colH, insetV, insetL, voiceCardOuterV)
        }

        let bannerBottom = handleH + bannerH
        let avatarBottom = avatarTop + avatarSize
        let voiceCardTop = voiceCardH > 0 ? max(bannerBottom + 8.sh, avatarBottom + 8.sh) : bannerBottom + 8.sh
        if voiceCardH > 0 {
            voiceCardNode.frame = CGRect(x: pad, y: voiceCardTop, width: cardW, height: voiceCardH)
            if let v = voiceHostLayout, let col = voiceSettingsColumn {
                v.host.frame = CGRect(x: infoCardPad, y: v.voiceCardOuterV, width: v.contentW, height: v.hostH)
                col.frame = CGRect(x: v.insetL, y: v.insetV, width: v.columnW, height: v.colH)
                col.setNeedsLayout()
                col.layoutIfNeeded()
                v.host.setNeedsLayout()
                v.host.layoutIfNeeded()
            }
        }
        let infoCardBaseTop = voiceCardH > 0 ? voiceCardTop + voiceCardH + 8.sh : handleH + bannerH + 8.sh

        let overlapIntoInfo = max(0, avatarBottom - infoCardBaseTop)
        let insetBelowAvatar = overlapIntoInfo > 0 ? overlapIntoInfo + 8.sh : 0
        var infoY = max(insetBelowAvatar, infoBottomPad)
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
        infoY += btnH + infoBottomPad

        let infoCardH = infoY
        infoCardNode.frame = CGRect(x: pad, y: infoCardBaseTop, width: cardW, height: infoCardH)

        let memberCardTop = infoCardBaseTop + infoCardH + 8
        var memberY: CGFloat = 16.sh

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

        let totalH = (user.createTimeSeconds > 0 ? memberCardTop + memberCardH : infoCardBaseTop + infoCardH) + safeBottom + 16
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
