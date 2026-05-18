import UIKit
import QuartzCore

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
    private let onChat: () -> Void
    private let onJoinVoice: () -> Void
    private let onInvite: () -> Void

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
    private let chatWrap = UIView()
    private let chatButton = UIButton(type: .custom)
    private let chatBadge = UILabel()

    init(
        channelTitle: String,
        chatUnreadCount: Int = 0,
        members: [VoiceMemberDisplay] = [],
        onChat: @escaping () -> Void,
        onJoinVoice: @escaping () -> Void,
        onInvite: @escaping () -> Void = {}
    ) {
        self.channelTitle = channelTitle
        self.chatUnreadCount = chatUnreadCount
        self.members = members
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
        iconView.image = (UIImage(named: "Chat/SpeakerIcon") ?? UIImage(systemName: "speaker.wave.2.fill"))?
            .withRenderingMode(.alwaysTemplate)
        iconView.tintColor = UIColor.theme.textStrong

        iconOuter.addSubview(iconView)

        voiceTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        voiceTitleLabel.textColor = UIColor.theme.textStrong
        voiceTitleLabel.textAlignment = .center
        voiceTitleLabel.isUserInteractionEnabled = false
        voiceTitleLabel.text = NSLocalizedString(
            "voiceChannel.joinSheet.voiceRoom", tableName: nil, bundle: .main, value: "Voice Room", comment: "")

        statusLabel.font = .systemFont(ofSize: 16, weight: .regular)
        statusLabel.textColor = UIColor.theme.textDisabled
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isUserInteractionEnabled = false
        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        if members.isEmpty {
            statusLabel.text = NSLocalizedString(
                "voiceChannel.joinSheet.emptyRoom", tableName: nil, bundle: .main,
                value: "No one is currently in room", comment: "")
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
        joinVoiceButtonCapsuleStyle(joinButton, height: 50)
        joinButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        joinButton.titleLabel?.lineBreakMode = .byTruncatingTail
        joinButton.setTitle(
            NSLocalizedString(
                "voiceChannel.joinSheet.joinVoice", tableName: nil, bundle: .main, value: "Join Voice", comment: ""),
            for: .normal)
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.setTitleColor(.white, for: .highlighted)
        joinButton.tintColor = .white
        joinButton.backgroundColor = Self.joinVoiceGreen
        joinButton.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
        joinButtonHost.addSubview(joinButton)
        NSLayoutConstraint.activate([
            joinButton.leadingAnchor.constraint(equalTo: joinButtonHost.leadingAnchor),
            joinButton.trailingAnchor.constraint(equalTo: joinButtonHost.trailingAnchor),
            joinButton.topAnchor.constraint(equalTo: joinButtonHost.topAnchor),
            joinButton.bottomAnchor.constraint(equalTo: joinButtonHost.bottomAnchor),
            joinButtonHost.heightAnchor.constraint(equalToConstant: 50),
        ])

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
        footerRow.addArrangedSubview(leftFooterSpacer)
        footerRow.addArrangedSubview(joinButtonHost)
        footerRow.addArrangedSubview(chatWrap)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
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
            let container = TextAvatarView(username: member.username, size: avatarSize, fontSize: 16)
            container.translatesAutoresizingMaskIntoConstraints = false
            container.layer.borderWidth = 2
            container.layer.borderColor = UIColor.theme.secondary.cgColor

            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = avatarSize / 2

            if let av = member.avatarURL, !av.isEmpty {
                let px = Int(avatarSize * UIScreen.main.scale)
                let proxy = ImgproxyURL.create(from: av, width: px, height: px)
                container.showSkeleton()
                let fallbackUsername = member.username
                ImageCache.shared.loadAvatar(urlString: proxy) { [weak container] img in
                    imageView.image = img
                    if img != nil {
                        container?.showImageMode()
                    } else {
                        container?.configure(username: fallbackUsername, fontSize: 16)
                    }
                }
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
        joinButton.backgroundColor = Self.joinVoiceGreen
    }

    @objc private func closeTapped() {
        dismissSheet(animated: true, completion: nil)
    }

    @objc private func inviteTapped() {
        onInvite()
    }

    @objc private func joinTapped() {
        let action = onJoinVoice
        dismissSheet(animated: true) {
            DispatchQueue.main.async {
                action()
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
