import UIKit
import QuartzCore

enum JoinChannelSheetKind {
    case voice
    case streaming
}

final class JoinVoiceChannelSheetViewController: UIViewController {

    static let sheetTransitionDuration: CFTimeInterval = 0.22

    @available(iOS 15.0, *)
    static let contentSizedDetentIdentifier = UISheetPresentationController.Detent.Identifier("mezon.joinVoice.content")

    static func preferredSheetHeight(safeAreaBottomInset: CGFloat, hasMembers: Bool) -> CGFloat {
        let grabberBlock: CGFloat = 8 + 5 + 12
        let header: CGFloat = 60
        let headerToCenter: CGFloat = 20
        let iconOuter: CGFloat = 20 + 36 + 20
        let stackSpacing: CGFloat = 6 + 6
        let voiceTitleLine: CGFloat = 24
        let statusLines: CGFloat = 40
        let centerCore = iconOuter + stackSpacing + voiceTitleLine + statusLines
        let middleTail: CGFloat = hasMembers ? (16 + 44 + 4) : 20
        let footerBlock: CGFloat = 50 + 22
        return grabberBlock + header + headerToCenter + centerCore + middleTail + footerBlock + safeAreaBottomInset
    }

    private let channelTitle: String
    private let chatUnreadCount: Int
    private let members: [VoiceMemberDisplay]
    private let kind: JoinChannelSheetKind
    private let canJoin: Bool
    private let onChat: () -> Void
    private let onJoinVoice: (SfuRole) -> Void
    private let onInvite: () -> Void
    private var selectedRole: SfuRole = .speaker

    private let contentContainer = UIView()
    private let grabber = UIView()
    private let headerRow = UIStackView()
    private let headerLeft = UIStackView()
    private let dismissButton = UIButton(type: .custom)
    private let inviteButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let centerStack = UIStackView()
    private let membersContainer = UIView()
    private let iconOuter = UIView()
    private let iconView = UIImageView()
    private let voiceTitleLabel = UILabel()
    private let statusLabel = UILabel()

    private let footerRow = UIStackView()
    private let leftFooterSpacer = UIView()
    private let joinButtonHost = UIView()
    private let joinButton = UIButton(type: .custom)
    private let splitJoinContainer = UIView()
    private let splitJoinDivider = UIView()
    private let roleDropdownButton = UIButton(type: .custom)
    private var roleMenuHost: UIView?
    private let chatWrap = UIView()
    private let chatButton = UIButton(type: .custom)
    private let chatBadge = UILabel()

    init(
        channelTitle: String,
        chatUnreadCount: Int = 0,
        members: [VoiceMemberDisplay] = [],
        kind: JoinChannelSheetKind = .voice,
        canJoin: Bool = true,
        onChat: @escaping () -> Void,
        onJoinVoice: @escaping (SfuRole) -> Void,
        onInvite: @escaping () -> Void = {}
    ) {
        self.channelTitle = channelTitle
        self.chatUnreadCount = chatUnreadCount
        self.members = members
        self.kind = kind
        self.canJoin = canJoin
        self.onChat = onChat
        self.onJoinVoice = onJoinVoice
        self.onInvite = onInvite
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true

        grabber.backgroundColor = UIColor.theme.textDisabled.withAlphaComponent(0.5)
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false

        headerLeft.axis = .horizontal
        headerLeft.alignment = .center
        headerLeft.spacing = 10
        headerLeft.translatesAutoresizingMaskIntoConstraints = false

        styleTertiaryCircleButton(dismissButton, systemImage: "chevron.down", pointSize: 18)
        dismissButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = channelTitle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerLeft.addArrangedSubview(dismissButton)
        headerLeft.addArrangedSubview(titleLabel)

        styleTertiaryCircleButton(inviteButton, systemImage: "person.badge.plus", pointSize: 18)
        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)
        inviteButton.isHidden = kind == .streaming

        headerRow.axis = .horizontal
        headerRow.alignment = .top
        headerRow.spacing = 10
        headerRow.distribution = .fill
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(headerLeft)
        headerRow.addArrangedSubview(inviteButton)

        iconOuter.translatesAutoresizingMaskIntoConstraints = false
        iconOuter.backgroundColor = UIColor.theme.tertiary
        iconOuter.layer.cornerRadius = 999

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.image = kind == .streaming
            ? (UIImage(named: "Channel/channelStream") ?? UIImage(systemName: "dot.radiowaves.left.and.right"))?
                .withRenderingMode(.alwaysTemplate)
            : (UIImage(named: "Chat/SpeakerIcon") ?? UIImage(systemName: "speaker.wave.2.fill"))?
                .withRenderingMode(.alwaysTemplate)
        iconView.tintColor = UIColor.theme.textStrong

        iconOuter.addSubview(iconView)

        voiceTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        voiceTitleLabel.textColor = UIColor.theme.textStrong
        voiceTitleLabel.textAlignment = .center
        voiceTitleLabel.isUserInteractionEnabled = false
        voiceTitleLabel.text = kind == .streaming
            ? NSLocalizedString(
                "streamingRoom.joinSheet.stream", tableName: nil, bundle: .main, value: "Stream", comment: "")
            : NSLocalizedString(
                "voiceChannel.joinSheet.voiceRoom", tableName: nil, bundle: .main, value: "Voice Room", comment: "")

        statusLabel.font = .systemFont(ofSize: 16, weight: .regular)
        statusLabel.textColor = UIColor.theme.textDisabled
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isUserInteractionEnabled = false
        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let hasActiveStream = kind == .streaming && canJoin
        if members.isEmpty && !hasActiveStream {
            statusLabel.text = NSLocalizedString(
                kind == .streaming ? "streamingRoom.joinSheet.emptyStream" : "voiceChannel.joinSheet.emptyRoom",
                tableName: nil,
                bundle: .main,
                value: kind == .streaming ? "No one is currently in stream" : "No one is currently in room",
                comment: "")
        } else {
            statusLabel.text = NSLocalizedString(
                "voiceChannel.joinSheet.waiting", tableName: nil, bundle: .main,
                value: "Everyone is waiting for you inside", comment: "")
        }

        buildMembersRow()

        centerStack.axis = .vertical
        centerStack.alignment = .center
        centerStack.spacing = 6
        centerStack.isUserInteractionEnabled = false
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        centerStack.setContentHuggingPriority(.defaultHigh, for: .vertical)
        centerStack.setContentCompressionResistancePriority(.required, for: .vertical)
        centerStack.addArrangedSubview(iconOuter)
        centerStack.addArrangedSubview(voiceTitleLabel)
        centerStack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: iconOuter.topAnchor, constant: 20),
            iconView.bottomAnchor.constraint(equalTo: iconOuter.bottomAnchor, constant: -20),
            iconView.leadingAnchor.constraint(equalTo: iconOuter.leadingAnchor, constant: 20),
            iconView.trailingAnchor.constraint(equalTo: iconOuter.trailingAnchor, constant: -20),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
        ])

        leftFooterSpacer.translatesAutoresizingMaskIntoConstraints = false
        leftFooterSpacer.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            leftFooterSpacer.widthAnchor.constraint(equalToConstant: 50),
            leftFooterSpacer.heightAnchor.constraint(equalToConstant: 50),
        ])

        joinButtonHost.translatesAutoresizingMaskIntoConstraints = false
        joinButtonHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        joinButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        joinButton.titleLabel?.lineBreakMode = .byTruncatingTail
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.setTitleColor(.white, for: .highlighted)
        joinButton.tintColor = .white
        joinButton.isEnabled = isJoinActionEnabled
        joinButton.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
        if kind == .voice {
            joinButton.setTitle(joinTitleForSelectedRole(), for: .normal)
            buildSplitJoinControl()
        } else {
            joinButton.setTitle(
                NSLocalizedString(
                    "streamingRoom.joinSheet.joinStream", tableName: nil, bundle: .main, value: "Join Stream", comment: ""),
                for: .normal)
            joinVoiceButtonCapsuleStyle(joinButton, height: 50)
            joinButtonHost.addSubview(joinButton)
            NSLayoutConstraint.activate([
                joinButton.leadingAnchor.constraint(equalTo: joinButtonHost.leadingAnchor),
                joinButton.trailingAnchor.constraint(equalTo: joinButtonHost.trailingAnchor),
                joinButton.topAnchor.constraint(equalTo: joinButtonHost.topAnchor),
                joinButton.bottomAnchor.constraint(equalTo: joinButtonHost.bottomAnchor),
            ])
        }
        joinButtonHost.heightAnchor.constraint(equalToConstant: 50).isActive = true
        updateJoinButtonAppearance()

        chatWrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chatWrap.widthAnchor.constraint(equalToConstant: 50),
            chatWrap.heightAnchor.constraint(equalToConstant: 50),
        ])
        styleTertiaryCircleButton(chatButton, systemImage: "bubble.left.and.bubble.right.fill", pointSize: 18)
        chatButton.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)
        chatWrap.addSubview(chatButton)
        NSLayoutConstraint.activate([
            chatButton.centerXAnchor.constraint(equalTo: chatWrap.centerXAnchor),
            chatButton.centerYAnchor.constraint(equalTo: chatWrap.centerYAnchor),
            chatButton.widthAnchor.constraint(equalToConstant: 50),
            chatButton.heightAnchor.constraint(equalToConstant: 50),
        ])

        chatBadge.font = .systemFont(ofSize: 11, weight: .bold)
        chatBadge.textColor = .white
        chatBadge.backgroundColor = .systemRed
        chatBadge.textAlignment = .center
        chatBadge.layer.cornerRadius = 10
        chatBadge.clipsToBounds = true
        chatBadge.isUserInteractionEnabled = false
        chatBadge.translatesAutoresizingMaskIntoConstraints = false
        chatBadge.isHidden = chatUnreadCount <= 0
        if chatUnreadCount > 0 {
            chatBadge.text = chatUnreadCount > 99 ? "99+" : "\(chatUnreadCount)"
        }
        chatWrap.addSubview(chatBadge)
        NSLayoutConstraint.activate([
            chatBadge.topAnchor.constraint(equalTo: chatWrap.topAnchor, constant: -4),
            chatBadge.trailingAnchor.constraint(equalTo: chatWrap.trailingAnchor, constant: 4),
            chatBadge.heightAnchor.constraint(equalToConstant: 20),
            chatBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])

        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.spacing = 20
        footerRow.distribution = .fill
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footerRow.isUserInteractionEnabled = true
        footerRow.addArrangedSubview(leftFooterSpacer)
        footerRow.addArrangedSubview(joinButtonHost)
        footerRow.addArrangedSubview(chatWrap)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.isUserInteractionEnabled = true
        view.addSubview(contentContainer)
        contentContainer.addSubview(grabber)
        contentContainer.addSubview(headerRow)
        contentContainer.addSubview(centerStack)
        view.addSubview(footerRow)
        if !members.isEmpty {
            view.insertSubview(membersContainer, belowSubview: footerRow)
        }

        var layoutConstraints: [NSLayoutConstraint] = [
            footerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            footerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            footerRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),

            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            grabber.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            headerRow.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 12),
            headerRow.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 10),
            headerRow.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -10),

            inviteButton.widthAnchor.constraint(equalToConstant: 44),
            inviteButton.heightAnchor.constraint(equalToConstant: 44),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
            dismissButton.heightAnchor.constraint(equalToConstant: 44),

            centerStack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 20),
            centerStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 16),
            centerStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -16),
        ]
        if members.isEmpty {
            layoutConstraints.append(contentsOf: [
                centerStack.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor, constant: -8),
                contentContainer.bottomAnchor.constraint(equalTo: footerRow.topAnchor, constant: -12),
            ])
        } else {
            layoutConstraints.append(contentsOf: [
                centerStack.bottomAnchor.constraint(equalTo: membersContainer.topAnchor, constant: -16),
                membersContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                membersContainer.bottomAnchor.constraint(equalTo: footerRow.topAnchor, constant: -4),
                contentContainer.bottomAnchor.constraint(equalTo: membersContainer.topAnchor, constant: -4),
            ])
        }
        NSLayoutConstraint.activate(layoutConstraints)

        view.bringSubviewToFront(footerRow)

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: ThemeManager.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    private var isJoinActionEnabled: Bool {
        switch kind {
        case .voice:
            return true
        case .streaming:
            return canJoin
        }
    }

    private func updateJoinButtonAppearance() {
        let background = joinButton.isEnabled ? Self.joinVoiceGreen : UIColor.theme.textDisabled
        let alpha: CGFloat = joinButton.isEnabled ? 1 : 0.72
        if kind == .voice {
            splitJoinContainer.backgroundColor = background
            splitJoinContainer.alpha = alpha
            joinButton.backgroundColor = .clear
        } else {
            joinButton.backgroundColor = background
            joinButton.alpha = alpha
        }
    }

    private func buildSplitJoinControl() {
        splitJoinContainer.translatesAutoresizingMaskIntoConstraints = false
        splitJoinContainer.layer.cornerRadius = 25
        splitJoinContainer.layer.cornerCurve = .continuous
        splitJoinContainer.clipsToBounds = true

        splitJoinDivider.translatesAutoresizingMaskIntoConstraints = false
        splitJoinDivider.backgroundColor = UIColor.black.withAlphaComponent(0.2)

        roleDropdownButton.translatesAutoresizingMaskIntoConstraints = false
        let chevronCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        roleDropdownButton.setImage(
            UIImage(systemName: "chevron.down", withConfiguration: chevronCfg)?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        roleDropdownButton.tintColor = .white
        roleDropdownButton.addTarget(self, action: #selector(roleDropdownTapped), for: .touchUpInside)

        joinButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 10)
        splitJoinContainer.addSubview(joinButton)
        splitJoinContainer.addSubview(splitJoinDivider)
        splitJoinContainer.addSubview(roleDropdownButton)
        joinButtonHost.addSubview(splitJoinContainer)
        NSLayoutConstraint.activate([
            splitJoinContainer.leadingAnchor.constraint(equalTo: joinButtonHost.leadingAnchor),
            splitJoinContainer.trailingAnchor.constraint(equalTo: joinButtonHost.trailingAnchor),
            splitJoinContainer.topAnchor.constraint(equalTo: joinButtonHost.topAnchor),
            splitJoinContainer.bottomAnchor.constraint(equalTo: joinButtonHost.bottomAnchor),

            joinButton.leadingAnchor.constraint(equalTo: splitJoinContainer.leadingAnchor),
            joinButton.topAnchor.constraint(equalTo: splitJoinContainer.topAnchor),
            joinButton.bottomAnchor.constraint(equalTo: splitJoinContainer.bottomAnchor),

            splitJoinDivider.leadingAnchor.constraint(equalTo: joinButton.trailingAnchor),
            splitJoinDivider.widthAnchor.constraint(equalToConstant: 1),
            splitJoinDivider.topAnchor.constraint(equalTo: splitJoinContainer.topAnchor, constant: 10),
            splitJoinDivider.bottomAnchor.constraint(equalTo: splitJoinContainer.bottomAnchor, constant: -10),

            roleDropdownButton.leadingAnchor.constraint(equalTo: splitJoinDivider.trailingAnchor),
            roleDropdownButton.trailingAnchor.constraint(equalTo: splitJoinContainer.trailingAnchor),
            roleDropdownButton.topAnchor.constraint(equalTo: splitJoinContainer.topAnchor),
            roleDropdownButton.bottomAnchor.constraint(equalTo: splitJoinContainer.bottomAnchor),
            roleDropdownButton.widthAnchor.constraint(equalToConstant: 46),
        ])
    }

    private func selectRole(_ role: SfuRole) {
        selectedRole = role
        joinButton.setTitle(joinTitleForSelectedRole(), for: .normal)
    }

    @objc private func roleDropdownTapped() {
        if roleMenuHost != nil {
            dismissRoleMenu()
        } else {
            presentRoleMenu()
        }
    }

    private func presentRoleMenu() {
        guard roleMenuHost == nil else { return }
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.backgroundColor = .clear

        let dismissTap = UIButton(type: .custom)
        dismissTap.translatesAutoresizingMaskIntoConstraints = false
        dismissTap.backgroundColor = .clear
        dismissTap.addTarget(self, action: #selector(dismissRoleMenuTapped), for: .touchUpInside)

        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor.theme.tertiary
        panel.layer.cornerRadius = 14
        panel.layer.cornerCurve = .continuous
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor.theme.border.cgColor
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.22
        panel.layer.shadowRadius = 16
        panel.layer.shadowOffset = CGSize(width: 0, height: 6)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0

        let speakerRow = makeRoleMenuRow(
            role: .speaker,
            title: NSLocalizedString(
                "voiceChannel.joinSheet.joinAsSpeaker", tableName: nil, bundle: .main, value: "Join as speaker", comment: ""))
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.theme.border.withAlphaComponent(0.7)
        let audienceRow = makeRoleMenuRow(
            role: .audience,
            title: NSLocalizedString(
                "voiceChannel.joinSheet.joinAsAudience", tableName: nil, bundle: .main, value: "Join as audience", comment: ""))
        stack.addArrangedSubview(speakerRow)
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(audienceRow)

        panel.addSubview(stack)
        host.addSubview(dismissTap)
        host.addSubview(panel)
        view.addSubview(host)

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dismissTap.topAnchor.constraint(equalTo: host.topAnchor),
            dismissTap.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            dismissTap.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            dismissTap.bottomAnchor.constraint(equalTo: host.bottomAnchor),

            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            panel.widthAnchor.constraint(equalToConstant: 232),
            panel.trailingAnchor.constraint(equalTo: joinButtonHost.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: joinButtonHost.topAnchor, constant: -8),
        ])

        roleMenuHost = host
        panel.alpha = 0
        panel.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.97, y: 0.97)
        UIView.animate(
            withDuration: 0.24, delay: 0,
            usingSpringWithDamping: 0.86, initialSpringVelocity: 0.4,
            options: [.curveEaseOut]
        ) {
            panel.alpha = 1
            panel.transform = .identity
        }
        UIView.animate(withDuration: 0.2) {
            self.roleDropdownButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        }
    }

    private func makeRoleMenuRow(role: SfuRole, title: String) -> UIControl {
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 46).isActive = true
        row.tag = role == .audience ? 1 : 0
        row.addTarget(self, action: #selector(roleMenuRowTapped(_:)), for: .touchUpInside)

        let selected = selectedRole == role

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: selected ? .semibold : .regular)
        label.textColor = UIColor.theme.textStrong
        label.isUserInteractionEnabled = false

        let check = UIImageView()
        check.translatesAutoresizingMaskIntoConstraints = false
        let checkCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        check.image = UIImage(systemName: "checkmark", withConfiguration: checkCfg)?.withRenderingMode(.alwaysTemplate)
        check.tintColor = Self.joinVoiceGreen
        check.isHidden = !selected
        check.isUserInteractionEnabled = false

        row.addSubview(label)
        row.addSubview(check)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -8),
            check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc private func roleMenuRowTapped(_ sender: UIControl) {
        selectRole(sender.tag == 1 ? .audience : .speaker)
        dismissRoleMenu()
    }

    @objc private func dismissRoleMenuTapped() {
        dismissRoleMenu()
    }

    private func dismissRoleMenu() {
        guard let host = roleMenuHost else { return }
        roleMenuHost = nil
        UIView.animate(withDuration: 0.16, animations: {
            host.alpha = 0
            self.roleDropdownButton.imageView?.transform = .identity
        }, completion: { _ in
            host.removeFromSuperview()
        })
    }

    private func joinTitleForSelectedRole() -> String {
        selectedRole == .speaker
            ? NSLocalizedString(
                "voiceChannel.joinSheet.joinAsSpeakerTitle", tableName: nil, bundle: .main, value: "Join as Speaker", comment: "")
            : NSLocalizedString(
                "voiceChannel.joinSheet.joinAsAudienceTitle", tableName: nil, bundle: .main, value: "Join as Audience", comment: "")
    }

    private static let joinVoiceGreen = UIColor(red: 0.133, green: 0.694, blue: 0.298, alpha: 1)

    private func styleTertiaryCircleButton(_ button: UIButton, systemImage: String, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.theme.tertiary
        button.layer.cornerRadius = 22
        let img = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        button.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = UIColor.theme.textStrong
        button.imageView?.contentMode = .scaleAspectFit
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    }

    private static let memberAvatarSize: CGFloat = 40
    private static let memberOverlap: CGFloat = 10
    private static let maxVisibleMembers = 5

    private func buildMembersRow() {
        guard !members.isEmpty else { return }
        membersContainer.translatesAutoresizingMaskIntoConstraints = false

        let avatarSize = Self.memberAvatarSize
        let overlap = Self.memberOverlap
        let maxVisible = Self.maxVisibleMembers
        let visible = Array(members.prefix(maxVisible))
        let overflowCount = members.count - visible.count

        let showBadge = overflowCount > 0
        let totalItems = visible.count + (showBadge ? 1 : 0)
        let totalWidth = avatarSize + CGFloat(totalItems - 1) * (avatarSize - overlap)

        NSLayoutConstraint.activate([
            membersContainer.heightAnchor.constraint(equalToConstant: avatarSize + 4),
            membersContainer.widthAnchor.constraint(equalToConstant: totalWidth),
        ])

        for (i, member) in visible.enumerated() {
            let container = TextAvatarView(size: avatarSize)
            container.translatesAutoresizingMaskIntoConstraints = false
            container.layer.borderWidth = 2
            container.layer.borderColor = UIColor.theme.secondary.cgColor

            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = avatarSize / 2

            if let av = member.avatarURL, !av.isEmpty {
                let px = 100
                let proxy = ImgproxyURL.iconURL(from: av, width: px, height: px)
                container.showSkeleton()
                ImageCache.shared.loadAvatar(urlString: proxy) { [weak container] img in
                    imageView.image = img
                    if img != nil {
                        container?.showImageMode()
                    } else {
                        container?.showPlaceholder()
                    }
                }
            } else {
                container.showPlaceholder()
            }

            container.addSubview(imageView)
            membersContainer.addSubview(container)

            let xOffset = CGFloat(i) * (avatarSize - overlap)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: membersContainer.leadingAnchor, constant: xOffset),
                container.centerYAnchor.constraint(equalTo: membersContainer.centerYAnchor),
                container.widthAnchor.constraint(equalToConstant: avatarSize),
                container.heightAnchor.constraint(equalToConstant: avatarSize),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            membersContainer.bringSubviewToFront(container)
        }

        if showBadge {
            let badge = UIView()
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.layer.cornerRadius = avatarSize / 2
            badge.clipsToBounds = true
            badge.backgroundColor = UIColor.theme.tertiary
            badge.layer.borderWidth = 2
            badge.layer.borderColor = UIColor.theme.secondary.cgColor

            let badgeLabel = UILabel()
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            badgeLabel.textColor = UIColor.theme.textStrong
            badgeLabel.textAlignment = .center
            badgeLabel.text = "+\(overflowCount)"

            badge.addSubview(badgeLabel)
            membersContainer.addSubview(badge)

            let xOffset = CGFloat(visible.count) * (avatarSize - overlap)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: membersContainer.leadingAnchor, constant: xOffset),
                badge.centerYAnchor.constraint(equalTo: membersContainer.centerYAnchor),
                badge.widthAnchor.constraint(equalToConstant: avatarSize),
                badge.heightAnchor.constraint(equalToConstant: avatarSize),
                badgeLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            ])
        }
    }

    @objc private func applyTheme() {
        view.backgroundColor = UIColor.theme.secondary
        titleLabel.textColor = UIColor.theme.textStrong
        voiceTitleLabel.textColor = UIColor.theme.textStrong
        statusLabel.textColor = UIColor.theme.textDisabled
        iconOuter.backgroundColor = UIColor.theme.tertiary
        iconView.tintColor = UIColor.theme.textStrong
        dismissButton.backgroundColor = UIColor.theme.tertiary
        dismissButton.tintColor = UIColor.theme.textStrong
        inviteButton.backgroundColor = UIColor.theme.tertiary
        inviteButton.tintColor = UIColor.theme.textStrong
        chatButton.backgroundColor = UIColor.theme.tertiary
        chatButton.tintColor = UIColor.theme.textStrong
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.setTitleColor(.white, for: .highlighted)
        joinButton.tintColor = .white
        updateJoinButtonAppearance()
    }

    @objc private func closeTapped() {
        dismissSheet(animated: true, completion: nil)
    }

    @objc private func inviteTapped() {
        onInvite()
    }

    @objc private func joinTapped() {
        let action = onJoinVoice
        let role = selectedRole
        dismissSheet(animated: true) {
            DispatchQueue.main.async {
                action(role)
            }
        }
    }

    @objc private func chatTapped() {
        let action = onChat
        dismissSheet(animated: true) {
            DispatchQueue.main.async {
                action()
            }
        }
    }

    private func dismissSheet(animated: Bool, completion: (() -> Void)?) {
        guard animated else {
            dismiss(animated: false, completion: completion)
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        dismiss(animated: true, completion: completion)
        CATransaction.commit()
    }

    private func joinVoiceButtonCapsuleStyle(_ button: UIButton, height: CGFloat) {
        let r = height / 2
        button.layer.cornerRadius = r
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
    }
}

final class ExternalMeetingLinkSheetViewController: UIViewController {

    @available(iOS 15.0, *)
    static let contentSizedDetentIdentifier = UISheetPresentationController.Detent.Identifier("mezon.externalMeeting.content")

    private static let iconOuterSize: CGFloat = 64
    private static let actionHeight: CGFloat = 50

    static func preferredSheetHeight(safeAreaBottomInset: CGFloat) -> CGFloat {
        let grabberBlock: CGFloat = 8 + 5 + 12
        let header: CGFloat = 44
        let headerToCenter: CGFloat = 16
        let stackSpacing: CGFloat = 12 + 6
        let linkLine: CGFloat = 22
        let promptLines: CGFloat = 40
        let centerToActions: CGFloat = 24
        let actions = actionHeight + 10 + actionHeight
        let bottomPadding: CGFloat = 16
        return grabberBlock + header + headerToCenter + iconOuterSize + stackSpacing + linkLine + promptLines
            + centerToActions + actions + bottomPadding + safeAreaBottomInset
    }

    private let meeting: ExternalMeetingRoom
    private let url: URL
    private let onJoinInApp: () -> Void
    private let onOpenInBrowser: () -> Void

    private let grabber = UIView()
    private let headerRow = UIStackView()
    private let dismissButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let centerStack = UIStackView()
    private let iconOuter = UIView()
    private let iconView = UIImageView()
    private let linkLabel = UILabel()
    private let promptLabel = UILabel()
    private let actionStack = UIStackView()
    private let joinButton = UIButton(type: .custom)
    private let browserButton = UIButton(type: .custom)

    init(
        meeting: ExternalMeetingRoom,
        url: URL,
        onJoinInApp: @escaping () -> Void,
        onOpenInBrowser: @escaping () -> Void
    ) {
        self.meeting = meeting
        self.url = url
        self.onJoinInApp = onJoinInApp
        self.onOpenInBrowser = onOpenInBrowser
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func present(from presenter: UIViewController) {
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = presenter.view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = Self.preferredSheetHeight(safeAreaBottomInset: bottomInset)
                let detentId = Self.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { ctx in
                    min(targetHeight, ctx.maximumDetentValue)
                }
                sheetPresentationController?.detents = [contentDetent]
                sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheetPresentationController?.detents = [.medium(), .large()]
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        presenter.present(self, animated: true)
        CATransaction.commit()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true

        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.layer.cornerRadius = 22
        dismissButton.setImage(
            UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))?
                .withRenderingMode(.alwaysTemplate),
            for: .normal)
        dismissButton.imageView?.contentMode = .scaleAspectFit
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        dismissButton.accessibilityLabel = L(L10n.Common.close)
        dismissButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = L(L10n.VoiceChannel.externalCall)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 10
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(dismissButton)
        headerRow.addArrangedSubview(titleLabel)

        iconOuter.translatesAutoresizingMaskIntoConstraints = false
        iconOuter.layer.cornerRadius = Self.iconOuterSize / 2
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.image = (UIImage(named: "Chat/SpeakerIcon") ?? UIImage(systemName: "speaker.wave.2.fill"))?
            .withRenderingMode(.alwaysTemplate)
        iconOuter.addSubview(iconView)

        linkLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        linkLabel.textAlignment = .center
        linkLabel.numberOfLines = 1
        linkLabel.lineBreakMode = meeting.title.isEmpty ? .byTruncatingMiddle : .byTruncatingTail
        linkLabel.text = meeting.title.isEmpty ? (url.host ?? "") + url.path : meeting.title

        promptLabel.font = .systemFont(ofSize: 15, weight: .regular)
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 2
        promptLabel.lineBreakMode = .byTruncatingTail
        promptLabel.text = L(L10n.VoiceChannel.externalLinkPrompt)
        promptLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        centerStack.axis = .vertical
        centerStack.alignment = .center
        centerStack.spacing = 6
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        centerStack.addArrangedSubview(iconOuter)
        centerStack.addArrangedSubview(linkLabel)
        centerStack.addArrangedSubview(promptLabel)
        centerStack.setCustomSpacing(12, after: iconOuter)

        styleActionButton(joinButton, title: L(L10n.EventMenu.joinInApp), systemImage: "speaker.wave.2.fill")
        joinButton.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
        styleActionButton(browserButton, title: L(L10n.EventMenu.openInBrowser), systemImage: "safari")
        browserButton.addTarget(self, action: #selector(openInBrowserTapped), for: .touchUpInside)

        actionStack.axis = .vertical
        actionStack.spacing = 10
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.addArrangedSubview(joinButton)
        actionStack.addArrangedSubview(browserButton)

        view.addSubview(grabber)
        view.addSubview(headerRow)
        view.addSubview(centerStack)
        view.addSubview(actionStack)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            headerRow.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 12),
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            headerRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
            dismissButton.heightAnchor.constraint(equalToConstant: 44),

            iconOuter.widthAnchor.constraint(equalToConstant: Self.iconOuterSize),
            iconOuter.heightAnchor.constraint(equalToConstant: Self.iconOuterSize),
            iconView.centerXAnchor.constraint(equalTo: iconOuter.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconOuter.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            centerStack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 16),
            centerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            centerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            centerStack.bottomAnchor.constraint(lessThanOrEqualTo: actionStack.topAnchor, constant: -24),

            actionStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: ThemeManager.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    private func styleActionButton(_ button: UIButton, title: String, systemImage: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.setImage(
            UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))?
                .withRenderingMode(.alwaysTemplate),
            for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: -4)
        button.layer.cornerRadius = Self.actionHeight / 2
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.heightAnchor.constraint(equalToConstant: Self.actionHeight).isActive = true
    }

    @objc private func applyTheme() {
        view.backgroundColor = UIColor.theme.secondary
        grabber.backgroundColor = UIColor.theme.textDisabled.withAlphaComponent(0.5)
        dismissButton.backgroundColor = UIColor.theme.tertiary
        dismissButton.tintColor = UIColor.theme.textStrong
        titleLabel.textColor = UIColor.theme.textStrong
        iconOuter.backgroundColor = EventDisplayHelper.externalEventBadgeColor.withAlphaComponent(0.16)
        iconView.tintColor = EventDisplayHelper.externalEventBadgeColor
        linkLabel.textColor = UIColor.theme.textStrong
        promptLabel.textColor = UIColor.theme.textDisabled
        EventDisplayHelper.applyJoinInAppStyle(joinButton, iconHeight: 16)
        joinButton.setTitleColor(.white, for: .highlighted)
        browserButton.backgroundColor = UIColor.theme.tertiary
        browserButton.tintColor = UIColor.theme.textStrong
        browserButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        browserButton.setTitleColor(UIColor.theme.textStrong, for: .highlighted)
    }

    @objc private func closeTapped() {
        dismissSheet(completion: nil)
    }

    @objc private func joinTapped() {
        let action = onJoinInApp
        dismissSheet {
            DispatchQueue.main.async {
                action()
            }
        }
    }

    @objc private func openInBrowserTapped() {
        let action = onOpenInBrowser
        dismissSheet {
            DispatchQueue.main.async {
                action()
            }
        }
    }

    private func dismissSheet(completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        dismiss(animated: true, completion: completion)
        CATransaction.commit()
    }
}
