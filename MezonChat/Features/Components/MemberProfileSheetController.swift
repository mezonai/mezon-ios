import UIKit
import AsyncDisplayKit

struct MemberProfileVoiceChannelActions {
    let showMute: Bool
    let showKick: Bool
    let confirmUserLabel: String
    let onMute: () async throws -> Void
    let onKick: () async throws -> Void
}

struct MemberProfileGroupAction {
    let confirmUserLabel: String
    let onRemove: () async throws -> Void
}

private struct MemberProfileRole {
    let id: Int64
    let title: String
    let color: UIColor
    let iconURL: String?
    let canRemove: Bool
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
    private let clanId: Int64
    private let voiceChannelActions: MemberProfileVoiceChannelActions?
    private let groupAction: MemberProfileGroupAction?
    private let onDismiss: (() -> Void)?
    private let onSendMessage: ((Mezon_Api_ChannelDescription) -> Void)?
    private let onStartCall: ((Mezon_Api_ChannelDescription) -> Void)?
    private let onTransferFunds: ((TransferQRPayload) -> Void)?
    private let isWebhook: Bool

    private var sheetNode: MemberProfileSheetNode { displayNode as! MemberProfileSheetNode }

    init(
        user: Mezon_Api_User,
        context: AccountContext,
        isCurrentUser: Bool = false,
        clanId: Int64 = 0,
        voiceChannelActions: MemberProfileVoiceChannelActions? = nil,
        groupAction: MemberProfileGroupAction? = nil,
        onDismiss: (() -> Void)? = nil,
        onSendMessage: ((Mezon_Api_ChannelDescription) -> Void)? = nil,
        onStartCall: ((Mezon_Api_ChannelDescription) -> Void)? = nil,
        onTransferFunds: ((TransferQRPayload) -> Void)? = nil
    ) {
        self.user = user
        self.context = context
        self.isCurrentUser = isCurrentUser
        self.clanId = clanId
        self.voiceChannelActions = voiceChannelActions
        self.groupAction = groupAction
        self.onDismiss = onDismiss
        self.onSendMessage = onSendMessage
        self.onStartCall = onStartCall
        self.onTransferFunds = onTransferFunds
        self.isWebhook = user.username.isEmpty
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Hide
        self.blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = MemberProfileSheetNode(
            user: user,
            isCurrentUser: isCurrentUser,
            roles: resolveProfileRoles(),
            showCallAction: onStartCall != nil && !isCurrentUser && user.id != 0 && !isWebhook,
            showAddFriendAction: voiceChannelActions == nil && shouldShowAddFriendAction() && !isWebhook,
            voiceChannelActions: user.id != 0 && !isWebhook ? voiceChannelActions : nil,
            showRemoveFromGroup: groupAction != nil && !isCurrentUser && user.id != 0 && !isWebhook,
            showTransferAction: onTransferFunds != nil && !isCurrentUser && user.id != 0 && !isWebhook,
            isWebhook: isWebhook,
            onSendMessageTapped: { [weak self] in
                self?.handleSendMessage()
            },
            onStartCallTapped: { [weak self] in
                self?.handleStartCall()
            },
            onAddFriendTapped: { [weak self] in
                self?.handleAddFriend()
            },
            onTransferFundsTapped: { [weak self] in
                self?.handleTransferFunds()
            },
            onDimTapped: { [weak self] in
                self?.animateDismiss()
            },
            onVoiceMuteTap: { [weak self] in
                self?.presentVoiceMuteConfirm()
            },
            onVoiceKickTap: { [weak self] in
                self?.presentVoiceKickConfirm()
            },
            onRemoveFromGroupTap: { [weak self] in
                self?.presentRemoveFromGroupConfirm()
            },
            onRemoveRoleTapped: { [weak self] role in
                self?.presentRemoveRoleConfirm(role)
            }
        )
        displayNodeDidLoad()
    }

    private func resolveProfileRoles() -> [MemberProfileRole] {
        guard clanId != 0, user.id != 0 else { return [] }
        guard let response = context.engine.clanData.getClanRoles(clanId: clanId) else { return [] }

        let userId = user.id
        let memberRoleIds = Set(context.account.postbox.read { tx in
            tx.getClanMembers(clanId: clanId).first(where: { $0.userId == userId })?.roleIds ?? []
        })

        let indexedRoles = response.roles.roles.enumerated().filter { _, role in
            guard role.active != 0 else { return false }
            guard role.slug != "everyone-\(role.clanID)" else { return false }
            if !memberRoleIds.isEmpty {
                return memberRoleIds.contains(role.id)
            }
            return role.roleUserList.roleUsers.contains(where: { $0.id == userId })
        }
        let repository = RolesRepository(context: context)

        return indexedRoles
            .sorted { lhs, rhs in
                if lhs.element.orderRole != rhs.element.orderRole {
                    return lhs.element.orderRole < rhs.element.orderRole
                }
                return lhs.offset < rhs.offset
            }
            .map { _, role in
                let icon = role.roleIcon.trimmingCharacters(in: .whitespacesAndNewlines)
                return MemberProfileRole(
                    id: role.id,
                    title: role.title,
                    color: RoleColors.uiColor(forRole: role),
                    iconURL: icon.isEmpty ? nil : icon,
                    canRemove: repository.canEditRole(role, clanId: clanId)
                )
            }
    }

    private func shouldShowAddFriendAction() -> Bool {
        guard clanId != 0, !isCurrentUser, user.id != 0 else { return false }
        guard let friend = context.engine.friendsData.allFriends().first(where: { $0.hasUser && $0.user.id == user.id }) else {
            return true
        }
        switch friend.state {
        case EStateFriend.friend.rawValue,
             EStateFriend.otherPending.rawValue,
             EStateFriend.myPending.rawValue,
             EStateFriend.block.rawValue:
            return false
        default:
            return true
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        sheetNode.updateLayout(layout: layout, transition: transition)
    }

    func animateIn() {
        sheetNode.animateIn()
    }

    private func animateDismiss(completion: (() -> Void)? = nil) {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            self?.onDismiss?()
            completion?()
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

    private func presentRemoveFromGroupConfirm() {
        guard let action = groupAction else { return }
        let alert = UIAlertController(
            title: L(L10n.ChannelDetail.removeFromGroupConfirmTitle),
            message: L(L10n.ChannelDetail.removeFromGroupConfirmBody, action.confirmUserLabel),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: L(L10n.Common.cancel),
            style: .cancel))
        alert.addAction(UIAlertAction(
            title: L(L10n.ChannelDetail.removeFromGroupConfirmAction),
            style: .destructive,
            handler: { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    do {
                        try await action.onRemove()
                        self.animateDismiss()
                    } catch {
                        Toast.error(L(L10n.ChannelDetail.removeFromGroupFailed))
                    }
                }
            }))
        present(alert, animated: true)
    }

    private func presentRemoveRoleConfirm(_ role: MemberProfileRole) {
        guard role.canRemove, clanId != 0, user.id != 0 else { return }
        let displayName = user.displayName.isEmpty ? user.username : user.displayName
        let alert = UIAlertController(
            title: "Remove role?",
            message: "Remove \(role.title) from \(displayName)?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: L(L10n.Common.cancel),
            style: .cancel))
        alert.addAction(UIAlertAction(
            title: L(L10n.ClanRoles.iconRemove),
            style: .destructive,
            handler: { [weak self] _ in
                self?.removeRoleFromProfile(role)
            }))
        present(alert, animated: true)
    }

    private func removeRoleFromProfile(_ role: MemberProfileRole) {
        guard role.canRemove, clanId != 0, user.id != 0 else { return }
        let userId = user.id
        sheetNode.setRoleRemoving(roleId: role.id, removing: true)

        Task { @MainActor in
            do {
                try await RolesRepository(context: context).updateRole(
                    roleId: role.id,
                    clanId: clanId,
                    title: nil,
                    color: nil,
                    roleIcon: nil,
                    addUserIds: [],
                    activePermissionIds: [],
                    removeUserIds: [userId],
                    removePermissionIds: []
                )
                sheetNode.removeRole(roleId: role.id)
                Toast.success("Role removed")
            } catch {
                sheetNode.setRoleRemoving(roleId: role.id, removing: false)
                Toast.error(L(L10n.ClanRoles.failed))
            }
        }
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
            guard let channel = await resolveDirectMessageChannel() else { return }
            animateDismiss()
            onSendMessage?(channel)
        }
    }

    private func handleStartCall() {
        guard onStartCall != nil else { return }
        sheetNode.setLoading(true)

        Task { @MainActor in
            defer { sheetNode.setLoading(false) }
            guard let channel = await resolveDirectMessageChannel() else { return }
            animateDismiss()
            onStartCall?(channel)
        }
    }

    private func handleAddFriend() {
        guard !isCurrentUser, user.id != 0 else { return }

        Task { @MainActor in
            guard let token = await context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                try await context.account.network.addFriends(ids: [user.id], token: token)
                await context.engine.friendsData.refreshFromNetwork(token: token, force: true)
                Toast.success(L(L10n.FriendRequest.toastSendSuccess))
            } catch {
                let message = error.localizedDescription.isEmpty
                    ? L(L10n.FriendRequest.toastSelfAddError)
                    : error.localizedDescription
                Toast.error(message, title: "")
            }
        }
    }

    private func handleTransferFunds() {
        guard !isCurrentUser, user.id != 0, let onTransferFunds else { return }

        let displayName = user.displayName.isEmpty ? user.username : user.displayName
        let payload = TransferQRPayload(
            receiverUserId: String(user.id),
            walletAddress: nil,
            suggestedAmount: "10000",
            note: L(L10n.Profile.transferFunds),
            extraAttribute: nil,
            receiverDisplayName: displayName.isEmpty ? String(user.id) : displayName,
            recipientLocked: true
        )

        animateDismiss {
            onTransferFunds(payload)
        }
    }

    private func resolveDirectMessageChannel() async -> Mezon_Api_ChannelDescription? {
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return nil
        }
        guard user.id != 0 else { return nil }
        let targetUserId = user.id

        let dmChannels = try? await context.account.network.listDirectMessageChannels(token: token)
        if var existing = dmChannels?.first(where: { ch in
            ch.type == MezonConstants.ChannelType.dm.rawValue
                && ch.userIds.count == 1
                && ch.userIds.contains(targetUserId)
        }) {
            fillDirectMessageFallbackUserInfo(&existing)
            return existing
        }

        do {
            var channel = try await context.account.network.createDirectMessage(
                userId: targetUserId,
                token: token
            )
            fillDirectMessageFallbackUserInfo(&channel)
            return channel
        } catch {
            if !error.localizedDescription.isEmpty {
                Toast.error(error.localizedDescription)
            }
            return nil
        }
    }

    private func fillDirectMessageFallbackUserInfo(_ channel: inout Mezon_Api_ChannelDescription) {
        if channel.usernames.isEmpty {
            channel.usernames = [user.username]
        }
        if channel.displayNames.isEmpty {
            channel.displayNames = [user.displayName]
        }
        if channel.avatars.isEmpty {
            channel.avatars = [user.avatarURL]
        }
        if channel.userIds.isEmpty {
            channel.userIds = [user.id]
        }
    }
}

private final class MemberProfileSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {

    private static var bannerTintCache: [String: UIColor] = [:]

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let contentNode = ASDisplayNode()
    private let scrollView = UIScrollView()
    private let handleNode = ASDisplayNode()

    private let bannerNode = ASDisplayNode()

    private let avatarNode = ASImageNode()
    private let textAvatarNode = TextAvatarNode(username: "", size: 80.sf, fontSize: 32.sf)
    private let statusDotNode = ASDisplayNode()

    private let infoCardNode = ASDisplayNode()
    private let displayNameNode = ASTextNode2()
    private let usernameNode = ASTextNode2()

    private let actionRow = ASDisplayNode()
    private let messageBtn = ProfileActionButton(icon: "bubble.left.fill", title: "Message")
    private let callBtn = ProfileActionButton(icon: "phone.fill", title: "Call")
    private let addFriendBtn = ProfileActionButton(icon: "person.badge.plus", title: "Add Friend", isGreen: true)
    private let transferButton = ASButtonNode()
    private let removeFromGroupButton = ASButtonNode()

    private let memberCardNode = ASDisplayNode()
    private let memberSinceTitleNode = ASTextNode2()
    private let memberSinceDateNode = ASTextNode2()

    private let rolesCardNode = ASDisplayNode()
    private let rolesTitleNode = ASTextNode2()

    private let onSendMessageTapped: () -> Void
    private let onStartCallTapped: () -> Void
    private let onAddFriendTapped: () -> Void
    private let onTransferFundsTapped: () -> Void
    private let onDimTapped: () -> Void
    private let onVoiceMuteTap: () -> Void
    private let onVoiceKickTap: () -> Void
    private let onRemoveFromGroupTap: () -> Void
    private let onRemoveRoleTapped: (MemberProfileRole) -> Void
    private let isCurrentUser: Bool
    private let showCallAction: Bool
    private let showAddFriendAction: Bool
    private let showTransferAction: Bool
    private let voiceChannelActions: MemberProfileVoiceChannelActions?
    private let showRemoveFromGroup: Bool
    private let isWebhook: Bool

    private var containerHeight: CGFloat = 0
    private var contentHeight: CGFloat = 0
    private var minSnapHeight: CGFloat = 0
    private var maxSnapHeight: CGFloat = 0
    private var currentSnapHeight: CGFloat?
    private var panStartHeight: CGFloat = 0
    private var isSheetPanActive = false
    private var validLayout: ContainerViewLayout?
    private var loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let user: Mezon_Api_User
    private var roles: [MemberProfileRole]
    private var bannerTintRequestKey: String?
    private var rolesHostView: UIView?
    private var roleChipViews: [ProfileRoleChipView] = []
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
        roles: [MemberProfileRole],
        showCallAction: Bool,
        showAddFriendAction: Bool,
        voiceChannelActions: MemberProfileVoiceChannelActions?,
        showRemoveFromGroup: Bool,
        showTransferAction: Bool,
        isWebhook: Bool = false,
        onSendMessageTapped: @escaping () -> Void,
        onStartCallTapped: @escaping () -> Void,
        onAddFriendTapped: @escaping () -> Void,
        onTransferFundsTapped: @escaping () -> Void,
        onDimTapped: @escaping () -> Void,
        onVoiceMuteTap: @escaping () -> Void,
        onVoiceKickTap: @escaping () -> Void,
        onRemoveFromGroupTap: @escaping () -> Void,
        onRemoveRoleTapped: @escaping (MemberProfileRole) -> Void
    ) {
        self.user = user
        self.isCurrentUser = isCurrentUser
        self.roles = roles
        self.showCallAction = showCallAction
        self.showAddFriendAction = showAddFriendAction
        self.voiceChannelActions = voiceChannelActions
        self.showRemoveFromGroup = showRemoveFromGroup
        self.showTransferAction = showTransferAction
        self.onSendMessageTapped = onSendMessageTapped
        self.onStartCallTapped = onStartCallTapped
        self.onAddFriendTapped = onAddFriendTapped
        self.onTransferFundsTapped = onTransferFundsTapped
        self.onDimTapped = onDimTapped
        self.onVoiceMuteTap = onVoiceMuteTap
        self.onVoiceKickTap = onVoiceKickTap
        self.onRemoveFromGroupTap = onRemoveFromGroupTap
        self.onRemoveRoleTapped = onRemoveRoleTapped
        self.isWebhook = isWebhook
        super.init()

        let t = UIColor.theme

        dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingNode.alpha = 0

        containerNode.backgroundColor = t.primary
        containerNode.cornerRadius = 14.sf
        containerNode.clipsToBounds = true

        contentNode.backgroundColor = .clear

        handleNode.backgroundColor = t.textDisabled
        handleNode.cornerRadius = 2.5.sf

        bannerNode.backgroundColor = UIColor.avatarColor(for: user.username)

        let avatarSize: CGFloat = 80.sf
        avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.backgroundColor = .clear
        avatarNode.borderWidth = 4.sf
        avatarNode.borderColor = t.primary.cgColor
        avatarNode.isUserInteractionEnabled = false
        applyCachedAvatarToImageNodeIfAny()

        textAvatarNode.cornerRadius = avatarSize / 2
        textAvatarNode.borderWidth = 4.sf
        textAvatarNode.borderColor = t.primary.cgColor
        if avatarNode.image != nil {
            textAvatarNode.alpha = 1
            textAvatarNode.showImageMode()
        } else if profileAvatarCacheKeys() != nil {
            textAvatarNode.alpha = 0
            textAvatarNode.showSkeleton()
            avatarNode.backgroundColor = t.tertiary
        } else {
            textAvatarNode.alpha = 1
            textAvatarNode.configure(username: user.username, fontSize: 32.sf)
        }

        statusDotNode.backgroundColor = user.online ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1) : UIColor.gray
        statusDotNode.cornerRadius = 8.sf
        statusDotNode.borderWidth = 3.sf
        statusDotNode.borderColor = t.primary.cgColor
        statusDotNode.isUserInteractionEnabled = false

        infoCardNode.backgroundColor = t.secondary
        infoCardNode.cornerRadius = 10.sf

        transferButton.backgroundColor = t.tertiary
        transferButton.cornerRadius = 18.sf
        transferButton.clipsToBounds = true
        let transferIcon = UIImage(named: "Profile/TransferIcon", in: Bundle.main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
        transferButton.setImage(transferIcon, for: .normal)
        transferButton.imageNode.contentMode = .scaleAspectFit
        transferButton.imageNode.style.preferredSize = CGSize(width: 20.sf, height: 20.sf)
        transferButton.accessibilityLabel = L(L10n.Profile.transferFunds)

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

        rolesCardNode.backgroundColor = t.secondary
        rolesCardNode.cornerRadius = 10.sf

        rolesTitleNode.attributedText = NSAttributedString(
            string: "Roles",
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: t.textStrong,
            ]
        )

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
        contentNode.addSubnode(bannerNode)
        if voiceChannelActions != nil {
            voiceCardNode.backgroundColor = UIColor.theme.secondary
            voiceCardNode.cornerRadius = 10.sf
            voiceCardNode.isUserInteractionEnabled = true
        }
        contentNode.addSubnode(infoCardNode)
        if showTransferAction {
            contentNode.addSubnode(transferButton)
        }
        infoCardNode.addSubnode(displayNameNode)
        infoCardNode.addSubnode(usernameNode)
        infoCardNode.addSubnode(actionRow)
        actionRow.addSubnode(messageBtn)
        actionRow.addSubnode(callBtn)
        actionRow.addSubnode(addFriendBtn)
        if showRemoveFromGroup {
            let danger = UIColor(red: 0.92, green: 0.25, blue: 0.25, alpha: 1)
            removeFromGroupButton.setTitle(
                L(L10n.ChannelDetail.removeFromGroup),
                with: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
                with: danger,
                for: .normal)
            removeFromGroupButton.backgroundColor = t.tertiary
            removeFromGroupButton.cornerRadius = 10.sf
            removeFromGroupButton.clipsToBounds = true
            infoCardNode.addSubnode(removeFromGroupButton)
        }
        contentNode.addSubnode(memberCardNode)
        memberCardNode.addSubnode(memberSinceTitleNode)
        memberCardNode.addSubnode(memberSinceDateNode)
        if !roles.isEmpty {
            contentNode.addSubnode(rolesCardNode)
            rolesCardNode.addSubnode(rolesTitleNode)
        }
        contentNode.addSubnode(avatarNode)
        contentNode.addSubnode(textAvatarNode)
        contentNode.addSubnode(statusDotNode)
        if voiceChannelActions != nil {
            contentNode.addSubnode(voiceCardNode)
        }
    }

    override func didLoad() {
        super.didLoad()
        loadProfileAvatar()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = false
        scrollView.delaysContentTouches = false
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        containerNode.view.insertSubview(scrollView, at: 0)
        scrollView.addSubview(contentNode.view)

        bannerNode.layer.zPosition = 0
        handleNode.layer.zPosition = 1
        infoCardNode.layer.zPosition = 2
        rolesCardNode.layer.zPosition = 2
        memberCardNode.layer.zPosition = 2
        voiceCardNode.layer.zPosition = voiceChannelActions != nil ? 8 : 0
        avatarNode.layer.zPosition = 10
        textAvatarNode.layer.zPosition = 9
        transferButton.layer.zPosition = 12
        statusDotNode.layer.zPosition = 13

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = UIColor.theme.textDisabled
        containerNode.view.addSubview(loadingIndicator)

        messageBtn.onTapped = { [weak self] in self?.messageTapped() }
        callBtn.onTapped = { [weak self] in self?.callTapped() }
        addFriendBtn.onTapped = { [weak self] in self?.addFriendTapped() }
        if showTransferAction {
            transferButton.addTarget(self, action: #selector(transferTapped), forControlEvents: .touchUpInside)
        }
        if showRemoveFromGroup {
            removeFromGroupButton.addTarget(
                self, action: #selector(removeFromGroupTapped), forControlEvents: .touchUpInside)
        }
        setupRoleChipsIfNeeded()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
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

    private func setupRoleChipsIfNeeded() {
        guard !roles.isEmpty, rolesHostView == nil else { return }
        let host = UIView()
        host.backgroundColor = .clear
        rolesCardNode.view.addSubview(host)
        rolesHostView = host

        roleChipViews = roles.map { role in
            let chip = ProfileRoleChipView(role: role, onRemoveTapped: { [weak self] role in
                self?.onRemoveRoleTapped(role)
            })
            host.addSubview(chip)
            return chip
        }
    }

    func setRoleRemoving(roleId: Int64, removing: Bool) {
        roleChipViews.first(where: { $0.roleId == roleId })?.setRemoving(removing)
    }

    func removeRole(roleId: Int64) {
        roles.removeAll { $0.id == roleId }
        if let index = roleChipViews.firstIndex(where: { $0.roleId == roleId }) {
            let chip = roleChipViews.remove(at: index)
            chip.removeFromSuperview()
        }
        rolesCardNode.isHidden = roles.isEmpty
        if let layout = validLayout {
            updateLayout(layout: layout, transition: .immediate)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let fallback = super.hitTest(point, with: event)
        if voiceChannelActions != nil,
           voiceCardNode.supernode === contentNode,
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
    @objc private func removeFromGroupTapped() { onRemoveFromGroupTap() }
    @objc private func transferTapped() { onTransferFundsTapped() }
    private func messageTapped() { onSendMessageTapped() }
    private func callTapped() { onStartCallTapped() }
    private func addFriendTapped() { onAddFriendTapped() }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        switch gesture.state {
        case .began:
            isSheetPanActive = true
            panStartHeight = containerHeight
        case .changed:
            guard isSheetPanActive else { return }
            let ty = gesture.translation(in: view).y
            let nextHeight = clampedSheetHeight(panStartHeight - ty)
            applySheetHeight(nextHeight, layout: layout)
            if nextHeight < maxSnapHeight - 1, scrollView.contentOffset != .zero {
                scrollView.contentOffset = .zero
            }
        case .ended, .cancelled:
            guard isSheetPanActive else { return }
            isSheetPanActive = false
            let velocityY = gesture.velocity(in: view).y
            if velocityY > 900, containerHeight <= minSnapHeight + 8 {
                onDimTapped()
                return
            }
            let targetHeight: CGFloat
            if velocityY < -350 {
                targetHeight = maxSnapHeight
            } else if velocityY > 350 {
                targetHeight = minSnapHeight
            } else {
                let midpoint = (minSnapHeight + maxSnapHeight) / 2
                targetHeight = containerHeight >= midpoint ? maxSnapHeight : minSnapHeight
            }
            animateToSnap(targetHeight, initialVelocity: velocityY)
        default: break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.view === containerNode.view,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.y) > abs(velocity.x) else { return false }

        let location = pan.location(in: containerNode.view)
        if location.y <= 56.sh {
            return true
        }
        if velocity.y < 0, containerHeight < maxSnapHeight - 1 {
            return true
        }
        if velocity.y > 0, scrollView.contentOffset.y <= 0.5 {
            return true
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer.view === containerNode.view || otherGestureRecognizer.view === containerNode.view
    }

    private func clampedSheetHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minSnapHeight), maxSnapHeight)
    }

    private func applySheetHeight(_ height: CGFloat, layout: ContainerViewLayout? = nil) {
        guard let layout = layout ?? validLayout else { return }
        let resolvedHeight = clampedSheetHeight(height)
        containerHeight = resolvedHeight
        currentSnapHeight = resolvedHeight
        containerNode.frame = CGRect(
            x: 0,
            y: layout.size.height - resolvedHeight,
            width: layout.size.width,
            height: resolvedHeight
        )
        scrollView.frame = CGRect(x: 0, y: 0, width: layout.size.width, height: resolvedHeight)
        scrollView.isScrollEnabled = contentHeight > resolvedHeight + 1 && resolvedHeight >= maxSnapHeight - 1
        loadingIndicator.center = CGPoint(x: layout.size.width / 2, y: resolvedHeight / 2)
        let maxOffset = max(0, contentHeight - resolvedHeight)
        if scrollView.contentOffset.y > maxOffset {
            scrollView.contentOffset.y = maxOffset
        }
    }

    private func animateToSnap(_ height: CGFloat, initialVelocity: CGFloat = 0) {
        guard let layout = validLayout else { return }
        let targetHeight = clampedSheetHeight(height)
        let distance = abs(targetHeight - containerHeight)
        let duration = TimeInterval(min(0.24, max(0.14, distance / max(maxSnapHeight, 1) * 0.30)))
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: {
                self.applySheetHeight(targetHeight, layout: layout)
            }
        )
    }

    func setLoading(_ loading: Bool) {
        if loading {
            loadingIndicator.startAnimating()
            messageBtn.isUserInteractionEnabled = false
            callBtn.isUserInteractionEnabled = false
            addFriendBtn.isUserInteractionEnabled = false
            transferButton.isUserInteractionEnabled = false
            messageBtn.alpha = 0.5
            callBtn.alpha = 0.5
            addFriendBtn.alpha = 0.5
            transferButton.alpha = 0.5
        } else {
            loadingIndicator.stopAnimating()
            messageBtn.isUserInteractionEnabled = true
            callBtn.isUserInteractionEnabled = true
            addFriendBtn.isUserInteractionEnabled = true
            transferButton.isUserInteractionEnabled = true
            messageBtn.alpha = 1
            callBtn.alpha = 1
            addFriendBtn.alpha = 1
            transferButton.alpha = 1
        }
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeBottom = layout.intrinsicInsets.bottom
        let screenW = layout.size.width
        let pad: CGFloat = 16
        minSnapHeight = floor(layout.size.height * 0.45)
        maxSnapHeight = max(minSnapHeight + 1, floor(layout.size.height * 0.80))

        transition.updateFrame(node: dimmingNode, frame: bounds)

        let handleH: CGFloat = 25.sh

        let bannerH: CGFloat = 100.sh

        let avatarSize: CGFloat = 80.sf
        let avatarOverlap: CGFloat = avatarSize / 2
        let avatarTop = handleH + bannerH - avatarOverlap
        let avatarX: CGFloat = 20.sf

        let infoCardPad: CGFloat = 20.sf
        let infoBottomPad = infoCardPad + 4.sh

        let transferButtonSize: CGFloat = 36.sf
        let nameMaxWidth = max(1, screenW - pad * 2 - infoCardPad * 2)
        let nameSize = displayNameNode.measure(CGSize(width: nameMaxWidth, height: .greatestFiniteMagnitude))
        let userSize = usernameNode.attributedText != nil
            ? usernameNode.measure(CGSize(width: nameMaxWidth, height: .greatestFiniteMagnitude))
            : .zero

        let btnH: CGFloat = 76.sh
        let actionW = screenW - pad * 2 - infoCardPad * 2
        callBtn.isHidden = !showCallAction
        addFriendBtn.isHidden = !showAddFriendAction
        var visibleActionButtons: [ProfileActionButton] = []
        if user.id != 0 && !isWebhook {
            visibleActionButtons.append(messageBtn)
        } else {
            messageBtn.isHidden = true
        }
        if showCallAction {
            visibleActionButtons.append(callBtn)
        }
        if showAddFriendAction {
            visibleActionButtons.append(addFriendBtn)
        }
        let actionSpacing: CGFloat = visibleActionButtons.count > 1 ? 16.sw : 0
        let buttonCount = CGFloat(max(1, visibleActionButtons.count))
        let totalSpacing = actionSpacing * CGFloat(max(0, visibleActionButtons.count - 1))
        let maxFixedButtonWidth: CGFloat = 96
        let availableButtonWidth = floor((actionW - totalSpacing) / buttonCount)
        let btnW = min(maxFixedButtonWidth, max(1, availableButtonWidth))
        let actionStartX: CGFloat = 0

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

        if visibleActionButtons.isEmpty {
            actionRow.isHidden = true
        } else {
            actionRow.isHidden = false
            infoY += 12
            actionRow.frame = CGRect(x: infoCardPad, y: infoY, width: actionW, height: btnH)
            for (index, button) in visibleActionButtons.enumerated() {
                button.frame = CGRect(x: actionStartX + CGFloat(index) * (btnW + actionSpacing), y: 0, width: btnW, height: btnH)
            }
            infoY += btnH
        }

        if showRemoveFromGroup {
            infoY += 12.sh
            let removeH: CGFloat = 48.sh
            removeFromGroupButton.frame = CGRect(x: infoCardPad, y: infoY, width: actionW, height: removeH)
            infoY += removeH
        }

        infoY += infoBottomPad

        let infoCardH = infoY
        infoCardNode.frame = CGRect(x: pad, y: infoCardBaseTop, width: cardW, height: infoCardH)
        if showTransferAction {
            transferButton.frame = CGRect(
                x: screenW - pad - transferButtonSize,
                y: 12.sh,
                width: transferButtonSize,
                height: transferButtonSize
            )
        }

        var nextCardTop = infoCardBaseTop + infoCardH + 8

        var rolesCardH: CGFloat = 0
        if !roles.isEmpty {
            var roleY: CGFloat = 18.sh
            let rolesContentW = cardW - infoCardPad * 2
            let rolesTitleSize = rolesTitleNode.measure(CGSize(width: rolesContentW, height: .greatestFiniteMagnitude))
            rolesTitleNode.frame = CGRect(x: infoCardPad, y: roleY, width: rolesTitleSize.width, height: rolesTitleSize.height)
            roleY += rolesTitleSize.height + 14.sh

            let chipH: CGFloat = 32.sh
            let chipGapX: CGFloat = 10.sw
            let chipGapY: CGFloat = 10.sh
            var chipX: CGFloat = 0
            var chipY: CGFloat = 0
            for chip in roleChipViews {
                let chipW = chip.preferredWidth(maxWidth: rolesContentW)
                if chipX > 0, chipX + chipW > rolesContentW {
                    chipX = 0
                    chipY += chipH + chipGapY
                }
                chip.frame = CGRect(x: chipX, y: chipY, width: chipW, height: chipH)
                chipX += chipW + chipGapX
            }

            let chipsH = roleChipViews.isEmpty ? 0 : chipY + chipH
            rolesHostView?.frame = CGRect(x: infoCardPad, y: roleY, width: rolesContentW, height: chipsH)
            roleY += chipsH + 18.sh

            rolesCardH = roleY
            rolesCardNode.frame = CGRect(x: pad, y: nextCardTop, width: cardW, height: rolesCardH)
            nextCardTop += rolesCardH + 8
        }

        let memberCardTop = nextCardTop
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

        let contentBottom: CGFloat
        if user.createTimeSeconds > 0 {
            contentBottom = memberCardTop + memberCardH
        } else if rolesCardH > 0 {
            contentBottom = nextCardTop - 8
        } else {
            contentBottom = infoCardBaseTop + infoCardH
        }
        contentHeight = max(contentBottom + safeBottom + 16, minSnapHeight)
        let resolvedSheetHeight = clampedSheetHeight(currentSnapHeight ?? minSnapHeight)
        containerHeight = resolvedSheetHeight
        currentSnapHeight = resolvedSheetHeight

        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        scrollView.frame = CGRect(x: 0, y: 0, width: screenW, height: containerHeight)
        scrollView.contentSize = CGSize(width: screenW, height: contentHeight)
        scrollView.isScrollEnabled = contentHeight > containerHeight + 1 && containerHeight >= maxSnapHeight - 1
        contentNode.frame = CGRect(x: 0, y: 0, width: screenW, height: contentHeight)
        let maxOffset = max(0, contentHeight - containerHeight)
        if scrollView.contentOffset.y > maxOffset {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: maxOffset)
        }

        bannerNode.frame = CGRect(x: 0, y: 0, width: screenW, height: handleH + bannerH)
        avatarNode.frame = CGRect(x: avatarX, y: avatarTop, width: avatarSize, height: avatarSize)
        textAvatarNode.frame = CGRect(x: avatarX, y: avatarTop, width: avatarSize, height: avatarSize)
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
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
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

    private func profileAvatarCacheKeys() -> (full: String, list: String, absolute: String)? {
        let raw = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let abs = SharingImageProxy.resolvedAssetURLString(raw)
        guard !abs.isEmpty else { return nil }
        return (
            ImgproxyURL.create(from: abs, width: 200, height: 200),
            ImgproxyURL.create(from: abs, width: 100, height: 100),
            abs
        )
    }

    private func scheduleBannerTintUpdate(from image: UIImage) {
        guard let key = profileAvatarCacheKeys()?.absolute else {
            resetBannerToUsernameAccent()
            return
        }
        if let cached = Self.bannerTintCache[key] {
            bannerTintRequestKey = nil
            bannerNode.backgroundColor = cached
            return
        }

        bannerTintRequestKey = key
        let fallbackColor = UIColor.avatarColor(for: user.username)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, image, fallbackColor] in
            let color = image.dominantColor(sampleSize: 24) ?? fallbackColor
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Self.bannerTintCache[key] = color
                guard self.bannerTintRequestKey == key else { return }
                self.bannerNode.backgroundColor = color
            }
        }
    }

    private func resetBannerToUsernameAccent() {
        bannerTintRequestKey = nil
        bannerNode.backgroundColor = UIColor.avatarColor(for: user.username)
    }

    private func applyCachedAvatarToImageNodeIfAny() {
        guard let k = profileAvatarCacheKeys() else { return }
        if let i = ImageCache.shared.memoryImage(forKey: k.full) {
            avatarNode.image = i
            avatarNode.backgroundColor = .clear
            scheduleBannerTintUpdate(from: i)
        } else if let i = ImageCache.shared.memoryImage(forKey: k.list) {
            avatarNode.image = i
            avatarNode.backgroundColor = .clear
            scheduleBannerTintUpdate(from: i)
        }
    }



    private func applyLoadedAvatarImage(_ image: UIImage) {
        avatarNode.image = image
        avatarNode.backgroundColor = .clear
        textAvatarNode.alpha = 1
        textAvatarNode.showImageMode()
        scheduleBannerTintUpdate(from: image)
    }

    private func showAvatarInitialsOnly() {
        avatarNode.image = nil
        avatarNode.backgroundColor = .clear
        textAvatarNode.alpha = 1
        textAvatarNode.configure(username: user.username, fontSize: 32.sf)
        resetBannerToUsernameAccent()
    }

    private func loadProfileAvatar() {
        if avatarNode.image != nil {
            if let img = avatarNode.image {
                scheduleBannerTintUpdate(from: img)
            }
            return
        }
        guard let k = profileAvatarCacheKeys() else {
            showAvatarInitialsOnly()
            return
        }
        ImageCache.shared.loadAvatar(urlString: k.full) { [weak self] image in
            guard let self else { return }
            if let i = image {
                self.applyLoadedAvatarImage(i)
                return
            }
            ImageCache.shared.loadAvatar(urlString: k.list) { [weak self] image in
                guard let self else { return }
                if let i = image {
                    self.applyLoadedAvatarImage(i)
                    return
                }
                ImageCache.shared.loadImage(urlString: k.absolute) { [weak self] im in
                    guard let self else { return }
                    if let v = im {
                        self.applyLoadedAvatarImage(v)
                    } else {
                        self.showAvatarInitialsOnly()
                    }
                }
            }
        }
    }
}

private final class ProfileRoleChipView: UIView {

    private let role: MemberProfileRole
    private let iconImageView = UIImageView()
    private let colorDotView = UIView()
    private let titleLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private let onRemoveTapped: (MemberProfileRole) -> Void

    var roleId: Int64 { role.id }

    init(role: MemberProfileRole, onRemoveTapped: @escaping (MemberProfileRole) -> Void) {
        self.role = role
        self.onRemoveTapped = onRemoveTapped
        super.init(frame: .zero)

        backgroundColor = UIColor.theme.tertiary
        layer.cornerRadius = 8.sf
        clipsToBounds = true

        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 7.5.sf

        colorDotView.backgroundColor = role.color
        colorDotView.layer.cornerRadius = 7.5.sf
        colorDotView.clipsToBounds = true

        titleLabel.text = role.title
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        removeButton.tintColor = UIColor.theme.textDisabled
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.contentEdgeInsets = .zero
        removeButton.imageView?.contentMode = .scaleAspectFit
        removeButton.isHidden = !role.canRemove
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        addSubview(colorDotView)
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(removeButton)

        loadRoleIconIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError() }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let titleWidth = ceil(titleLabel.sizeThatFits(CGSize(width: maxWidth, height: 32.sh)).width)
        let trailingWidth: CGFloat = role.canRemove ? 38.sw : 18.sw
        return min(max(titleWidth + 12.sw + 15.sf + 8.sw + trailingWidth, 80.sw), maxWidth)
    }

    func setRemoving(_ removing: Bool) {
        removeButton.isEnabled = !removing
        removeButton.alpha = removing ? 0.45 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconSize: CGFloat = 15.sf
        let iconX: CGFloat = 12.sw
        let iconY = (bounds.height - iconSize) / 2
        colorDotView.frame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        iconImageView.frame = colorDotView.frame
        let removeSize: CGFloat = 18.sf
        if role.canRemove {
            removeButton.frame = CGRect(
                x: bounds.width - 10.sw - removeSize,
                y: (bounds.height - removeSize) / 2,
                width: removeSize,
                height: removeSize
            )
        }
        let trailingWidth: CGFloat = role.canRemove ? 10.sw + removeSize + 8.sw : 18.sw
        titleLabel.frame = CGRect(
            x: iconX + iconSize + 8.sw,
            y: 0,
            width: max(0, bounds.width - iconX - iconSize - 8.sw - trailingWidth),
            height: bounds.height
        )
    }

    @objc private func removeTapped() {
        onRemoveTapped(role)
    }

    private func loadRoleIconIfNeeded() {
        guard let rawURL = role.iconURL else {
            iconImageView.isHidden = true
            colorDotView.isHidden = false
            return
        }

        let resolved = SharingImageProxy.resolvedAssetURLString(rawURL)
        guard !resolved.isEmpty else {
            iconImageView.isHidden = true
            colorDotView.isHidden = false
            return
        }

        let url = ImgproxyURL.create(from: resolved, width: 40, height: 40)
        iconImageView.isHidden = false
        colorDotView.isHidden = false
        ImageCache.shared.loadImage(urlString: url) { [weak self] image in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let image else {
                    self.iconImageView.isHidden = true
                    self.colorDotView.isHidden = false
                    return
                }
                self.iconImageView.image = image
                self.iconImageView.isHidden = false
                self.colorDotView.isHidden = true
            }
        }
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
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .medium),
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
