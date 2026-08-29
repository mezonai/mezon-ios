import UIKit
import AsyncDisplayKit

final class ChannelDetailViewController: ViewController {

    private let context: AccountContext
    private let clanId: Int64
    private var channel: Mezon_Api_ChannelDescription

    private var detailNode: ChannelDetailContainerNode { displayNode as! ChannelDetailContainerNode }

    private func resolvedChannelTypeForDetail() -> Int32 {
        if channel.type != 0 { return channel.type }
        if let ch = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID),
            ch.type != 0 {
            return ch.type
        }
        return context.engine.clanData.resolvedListChannelUsersType(channelId: channel.channelID)
    }

    init(context: AccountContext, clanId: Int64, channel: Mezon_Api_ChannelDescription) {
        self.context = context
        self.clanId = clanId
        self.channel = channel
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ChannelDetailContainerNode(
            context: context,
            clanId: clanId,
            channel: channel,
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSettingsTapped: { [weak self] in
                self?.openSettings()
            },
            onSearchTapped: { [weak self] in
                self?.openChannelSearch()
            },
            onThreadsTapped: { [weak self] in
                self?.openThreadList()
            },
            onMuteTapped: { [weak self] in
                if #available(iOS 13.0, *) {
                    self?.handleMuteButtonTapped()
                }
            },
            onGroupOptionsTapped: { [weak self] in
                if #available(iOS 13.0, *) {
                    self?.showGroupDMOptions()
                }
            }
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        detailNode.applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelDescriptionDidUpdate(_:)),
            name: .mezonChannelDescriptionDidUpdate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationSettingDidUpdate(_:)),
            name: .mezonNotificationSettingDidUpdate,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshChannelFromStores()
    }

    private static func notificationInt64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        let notifChannelId = Self.notificationInt64(notification.userInfo?["channelId"])
        guard let cid = notifChannelId, cid == channel.channelID else {
            return
        }
        refreshChannelFromStores()
    }

    @objc private func handleNotificationSettingDidUpdate(_ notification: Notification) {
        guard let cid = Self.notificationInt64(notification.userInfo?["channelId"]), cid == channel.channelID else {
            return
        }
        detailNode.updateMuteButtonState()
    }

    private func resolvedChannelSnapshot() -> Mezon_Api_ChannelDescription {
        if let ch = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID) {
            return ch
        }
        return channel
    }

    private func refreshChannelFromStores() {
        channel = resolvedChannelSnapshot()
        detailNode.applyUpdatedChannel(channel)
    }

    private func openThreadList() {
        let t = resolvedChannelTypeForDetail()
        let parentId: Int64 =
            t == MezonConstants.ChannelType.thread.rawValue
            ? channel.parentID
            : channel.channelID
        let composerSurface = Self.surfaceChannelForThreadComposer(from: channel, resolvedType: t)
        let parentCategoryId: Int64 = {
            if let parent = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: parentId),
               parent.categoryID != 0 {
                return parent.categoryID
            }
            return channel.categoryID
        }()
        let vc = ThreadListViewController(
            context: context,
            clanId: clanId,
            parentChannelId: parentId,
            parentCategoryId: parentCategoryId,
            parentChannelLabel: channel.channelLabel,
            composerParentChannel: composerSurface
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private static func surfaceChannelForThreadComposer(from channel: Mezon_Api_ChannelDescription, resolvedType: Int32)
        -> Mezon_Api_ChannelDescription {
        guard resolvedType == MezonConstants.ChannelType.thread.rawValue else { return channel }
        var d = channel
        d.channelID = channel.parentID
        d.parentID = 0
        d.type = MezonConstants.ChannelType.forum.rawValue
        return d
    }

    private func openChannelSearch() {
        let t = resolvedChannelTypeForDetail()
        let isPrivateOrThread = channel.channelPrivate != 0 || channel.parentID != 0
            || t == MezonConstants.ChannelType.thread.rawValue
        let searchVC = SearchViewController(
            clanId: clanId,
            context: context,
            channelId: channel.channelID,
            channelLabel: channel.channelLabel,
            channelType: t != 0 ? t : MezonConstants.ChannelType.channel.rawValue,
            needsChannelMemberFilter: isPrivateOrThread
        )
        navigationController?.pushViewController(searchVC, animated: true)
    }

    private func openSettings() {
        let t = resolvedChannelTypeForDetail()
        let settingsVC = ChannelSettingsViewController(
            context: context,
            clanId: clanId,
            channelId: channel.channelID,
            categoryId: channel.categoryID,
            categoryName: channel.categoryName,
            channelType: t,
            channelPrivate: channel.channelPrivate == 1,
            channelName: channel.channelLabel,
            channelTopic: channel.topic
        )
        navigationController?.pushViewController(settingsVC, animated: true)
    }

    @available(iOS 13.0, *)
    private func handleMuteButtonTapped() {
        let isMuted = context.account.postbox.read { tx in
            guard let record = tx.getNotificationSetting(entityId: channel.channelID) else { return false }
            return record.timeMuteSeconds != 0
        }
        
        if isMuted {
            handleMuteChannel(muteTimeSeconds: 0)
        } else {
            openMuteDuration()
        }
    }

    @available(iOS 13.0, *)
    private func openMuteDuration() {
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let vc = MuteDurationViewController(
            channelName: channel.channelLabel,
            channelId: channel.channelID,
            clanId: channel.clanID,
            context: self.context,
            isThread: isThread,
            isGroupDirectMessage: isGroupDirectMessage
        ) { [weak self] duration in
            self?.handleMuteChannel(muteTimeSeconds: duration.seconds)
        }
        self.navigationController?.pushViewController(vc, animated: true)
    }

    @available(iOS 13.0, *)
    private func handleMuteChannel(muteTimeSeconds: Int32) {
        ChannelMuteHelper.setMuteChannel(
            context: context,
            channelId: channel.channelID,
            clanId: channel.clanID,
            muteTimeSeconds: muteTimeSeconds
        )
    }

    private var isGroupDirectMessage: Bool {
        clanId == 0 && resolvedChannelTypeForDetail() == MezonConstants.ChannelType.group.rawValue
    }

    private var currentUserNumericId: Int64? {
        context.currentUser.flatMap { Int64($0.id) }
    }

    private var isCurrentGroupCreator: Bool {
        guard isGroupDirectMessage,
              channel.creatorID != 0,
              let myId = currentUserNumericId else { return false }
        return myId == channel.creatorID
    }

    @available(iOS 13.0, *)
    private func showGroupDMOptions() {
        guard isGroupDirectMessage else { return }

        let sheet = GroupDMOptionsSheetViewController(
            customizeTitle: L(L10n.ChannelDetail.customizeGroup),
            leaveTitle: L(L10n.ChannelDetail.leaveGroup),
            deleteTitle: isCurrentGroupCreator ? L(L10n.ChannelDetail.deleteGroup) : nil,
            onCustomize: { [weak self] in
                self?.presentCustomizeGroup()
            },
            onLeave: { [weak self] in
                self?.confirmLeaveGroup()
            },
            onDelete: isCurrentGroupCreator ? { [weak self] in
                self?.confirmDeleteGroup()
            } : nil
        )
        sheet.modalPresentationStyle = .overFullScreen
        sheet.modalTransitionStyle = .crossDissolve
        present(sheet, animated: false)
    }

    private func presentCustomizeGroup() {
        let vc = GroupDMCustomizeViewController(context: context, channel: channel) { [weak self] updated in
            self?.applyUpdatedGroupDM(updated)
        }
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            vc.sheetPresentationController?.detents = [.medium()]
            vc.sheetPresentationController?.prefersGrabberVisible = true
        }
        present(vc, animated: true)
    }

    private func applyUpdatedGroupDM(_ updated: Mezon_Api_ChannelDescription) {
        channel = updated
        context.account.postbox.updateCachedDMChannelDescription(updated)
        detailNode.applyUpdatedChannel(updated)
        NotificationCenter.default.post(
            name: .mezonChannelDescriptionDidUpdate,
            object: nil,
            userInfo: ["clanId": Int64(0), "channelId": updated.channelID]
        )
    }

    @available(iOS 13.0, *)
    private func confirmLeaveGroup() {
        presentLeaveOrDeleteConfirmation(
            title: L(L10n.ChannelDetail.leaveGroupConfirmTitle),
            message: L(L10n.ChannelDetail.leaveGroupConfirmBody),
            actionTitle: L(L10n.ChannelDetail.leaveGroup),
            userConfirmedDelete: false
        )
    }

    @available(iOS 13.0, *)
    private func confirmDeleteGroup() {
        presentLeaveOrDeleteConfirmation(
            title: L(L10n.ChannelDetail.deleteGroupConfirmTitle),
            message: L(L10n.ChannelDetail.deleteGroupConfirmBody),
            actionTitle: L(L10n.ChannelDetail.deleteGroup),
            userConfirmedDelete: true
        )
    }

    @available(iOS 13.0, *)
    private func presentLeaveOrDeleteConfirmation(
        title: String,
        message: String,
        actionTitle: String,
        userConfirmedDelete: Bool
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive) { [weak self] _ in
            self?.performLeaveOrDeleteGroup(userConfirmedDelete: userConfirmedDelete)
        })
        present(alert, animated: true)
    }

    @available(iOS 13.0, *)
    private func performLeaveOrDeleteGroup(userConfirmedDelete: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            guard let myId = self.currentUserNumericId else {
                Toast.error(L(L10n.ChannelDetail.leaveGroupFailed))
                return
            }

            let deleteGroup = userConfirmedDelete && self.isCurrentGroupCreator

            do {
                if deleteGroup {
                    try await self.context.account.network.deleteChannelDesc(
                        channelId: self.channel.channelID,
                        clanId: 0,
                        token: token
                    )
                } else {
                    try await self.context.account.network.removeChannelUsers(
                        channelId: self.channel.channelID,
                        userIds: [myId],
                        token: token
                    )
                }
                self.context.account.postbox.removeCachedDMChannelDescription(channelId: self.channel.channelID)
                NotificationCenter.default.post(
                    name: .mezonChannelDescriptionDidUpdate,
                    object: nil,
                    userInfo: ["clanId": Int64(0), "channelId": self.channel.channelID, "removed": true]
                )
                Toast.success(deleteGroup ? L(L10n.ChannelDetail.groupDeleted) : L(L10n.ChannelDetail.groupLeft))
                self.exitRemovedGroupDM()
            } catch {
                Toast.error(L(L10n.ChannelDetail.leaveGroupFailed))
            }
        }
    }

    private func exitRemovedGroupDM() {
        guard let navigationController else {
            dismiss(animated: true)
            return
        }
        guard let mezonNavigation = navigationController as? NavigationController else {
            navigationController.popViewController(animated: true)
            return
        }

        var stack = mezonNavigation.viewControllers
        if let detailIndex = stack.firstIndex(where: { $0 === self }) {
            stack.remove(at: detailIndex)
            let previousIndex = detailIndex - 1
            if previousIndex >= 0, previousIndex < stack.count, stack[previousIndex] is ChatViewController {
                stack.remove(at: previousIndex)
            }
        } else if !stack.isEmpty {
            stack.removeLast()
        }

        if stack.isEmpty {
            mezonNavigation.popToRoot(animated: true)
        } else {
            mezonNavigation.setViewControllers(stack, animated: true)
        }
    }
}

private final class GroupDMOptionsSheetViewController: UIViewController {

    private let customizeTitle: String
    private let leaveTitle: String
    private let deleteTitle: String?
    private let onCustomize: () -> Void
    private let onLeave: () -> Void
    private let onDelete: (() -> Void)?

    private let dimView = UIView()
    private let containerView = UIView()
    private var didAnimateIn = false

    init(
        customizeTitle: String,
        leaveTitle: String,
        deleteTitle: String?,
        onCustomize: @escaping () -> Void,
        onLeave: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) {
        self.customizeTitle = customizeTitle
        self.leaveTitle = leaveTitle
        self.deleteTitle = deleteTitle
        self.onCustomize = onCustomize
        self.onLeave = onLeave
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            setupUI()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        animateIn()
    }

    private func setupUI() {
        view.backgroundColor = .clear

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped)))

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.theme.primary
        containerView.layer.cornerRadius = 24.sf
        containerView.layer.masksToBounds = true

        let customizeButton = makeActionButton(
            title: customizeTitle,
            titleColor: UIColor.theme.textStrong
        )
        customizeButton.addTarget(self, action: #selector(customizePressed), for: .touchUpInside)

        let leaveButton = makeActionButton(
            title: leaveTitle,
            titleColor: UIColor.systemRed
        )
        leaveButton.addTarget(self, action: #selector(leavePressed), for: .touchUpInside)

        var arrangedSubviews: [UIView] = [customizeButton, leaveButton]
        var deleteButton: UIButton?
        if let deleteTitle, onDelete != nil {
            let button = makeActionButton(
                title: deleteTitle,
                titleColor: UIColor.systemRed
            )
            button.addTarget(self, action: #selector(deletePressed), for: .touchUpInside)
            deleteButton = button
            arrangedSubviews.append(button)
        }

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10.sh

        view.addSubview(dimView)
        view.addSubview(containerView)
        containerView.addSubview(stack)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10.sh),

            stack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16.sh),
            stack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14.sw),
            stack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14.sw),
            stack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16.sh),

            customizeButton.heightAnchor.constraint(equalToConstant: 52.sh),
            leaveButton.heightAnchor.constraint(equalToConstant: 52.sh)
        ])
        if let deleteButton {
            deleteButton.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        }
    }

    private func makeActionButton(title: String, titleColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.theme.secondary
        button.layer.cornerRadius = 16.sf
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18.sw, bottom: 0, right: 18.sw)
        return button
    }

    private func animateIn() {
        view.layoutIfNeeded()
        containerView.transform = CGAffineTransform(translationX: 0, y: containerView.bounds.height + 40.sh)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.containerView.transform = .identity
        }
    }

    private func dismissSheet(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            self.containerView.transform = CGAffineTransform(translationX: 0, y: self.containerView.bounds.height + 40.sh)
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    @objc private func backgroundTapped() {
        dismissSheet()
    }

    @objc private func customizePressed() {
        dismissSheet(completion: onCustomize)
    }

    @objc private func leavePressed() {
        dismissSheet(completion: onLeave)
    }

    @objc private func deletePressed() {
        dismissSheet(completion: onDelete)
    }
}

private final class GroupDMCustomizeViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {

    private static let maxAvatarBytes = 10 * 1024 * 1024
    private static let maxGroupNameLength = 64

    private let context: AccountContext
    private let originalChannel: Mezon_Api_ChannelDescription
    private let onSaved: (Mezon_Api_ChannelDescription) -> Void

    private var avatarURL: String
    private var selectedImage: UIImage?
    private var selectedImageData: Data?
    private var avatarLoadTask: URLSessionDataTask?
    private var isSaving = false
    private var trimmedGroupName: String {
        (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let titleLabel = UILabel()
    private let avatarButton = UIButton(type: .system)
    private let avatarImageView = UIImageView()
    private let avatarPlaceholderImageView = UIImageView()
    private let removeAvatarButton = UIButton(type: .system)
    private let nameLabel = UILabel()
    private let nameCounterLabel = UILabel()
    private let nameField = UITextField()
    private let cancelButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView.mezonMedium()

    init(
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        onSaved: @escaping (Mezon_Api_ChannelDescription) -> Void
    ) {
        self.context = context
        self.originalChannel = channel
        self.avatarURL = channel.channelAvatar
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        avatarLoadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateAvatarPreview()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.theme.primary

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = L(L10n.ChannelDetail.customizeGroup)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.font = .systemFont(ofSize: 20.sf, weight: .bold)

        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.backgroundColor = UIColor.theme.secondary
        avatarButton.layer.cornerRadius = 44.swh
        avatarButton.clipsToBounds = true
        avatarButton.addTarget(self, action: #selector(pickAvatarTapped), for: .touchUpInside)

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true

        avatarPlaceholderImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarPlaceholderImageView.image = UIImage.mezonSystemImage("person.2.fill")
        avatarPlaceholderImageView.tintColor = .white
        avatarPlaceholderImageView.contentMode = .scaleAspectFit

        let avatarOverlay = UIView()
        avatarOverlay.translatesAutoresizingMaskIntoConstraints = false
        avatarOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        avatarOverlay.isUserInteractionEnabled = false

        let cameraImageView = UIImageView(image: UIImage.mezonSystemImage("camera.fill"))
        cameraImageView.translatesAutoresizingMaskIntoConstraints = false
        cameraImageView.tintColor = .white
        cameraImageView.contentMode = .scaleAspectFit

        avatarButton.addSubview(avatarImageView)
        avatarButton.addSubview(avatarPlaceholderImageView)
        avatarButton.addSubview(avatarOverlay)
        avatarButton.addSubview(cameraImageView)

        removeAvatarButton.translatesAutoresizingMaskIntoConstraints = false
        removeAvatarButton.setTitle(L(L10n.ChannelDetail.removeGroupLogo), for: .normal)
        removeAvatarButton.setTitleColor(UIColor.systemRed, for: .normal)
        removeAvatarButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        removeAvatarButton.addTarget(self, action: #selector(removeAvatarTapped), for: .touchUpInside)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = L(L10n.ChannelDetail.groupName)
        nameLabel.textColor = UIColor.theme.text
        nameLabel.font = .systemFont(ofSize: 13.sf, weight: .semibold)

        nameCounterLabel.translatesAutoresizingMaskIntoConstraints = false
        nameCounterLabel.textColor = UIColor.theme.textDisabled
        nameCounterLabel.font = .systemFont(ofSize: 12.sf, weight: .medium)
        nameCounterLabel.textAlignment = .right
        nameCounterLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameCounterLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.text = originalChannel.channelLabel
        nameField.placeholder = L(L10n.ChannelDetail.groupName)
        nameField.textColor = UIColor.theme.textStrong
        nameField.font = .systemFont(ofSize: 16.sf, weight: .regular)
        nameField.backgroundColor = UIColor.theme.secondary
        nameField.layer.cornerRadius = 10.sf
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
        nameField.leftViewMode = .always
        nameField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
        nameField.rightViewMode = .always
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameFieldEditingChanged), for: .editingChanged)
        nameField.addTarget(self, action: #selector(nameFieldDidReturn), for: .editingDidEndOnExit)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        cancelButton.backgroundColor = UIColor.theme.secondary
        cancelButton.layer.cornerRadius = 10.sf
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.setTitle(L(L10n.Common.save), for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.setTitleColor(.white.withAlphaComponent(0.65), for: .disabled)
        saveButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        saveButton.backgroundColor = UIColor.theme.bgViolet
        saveButton.layer.cornerRadius = 10.sf
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .white

        let avatarStack = UIStackView(arrangedSubviews: [avatarButton, removeAvatarButton])
        avatarStack.translatesAutoresizingMaskIntoConstraints = false
        avatarStack.axis = .vertical
        avatarStack.alignment = .center
        avatarStack.spacing = 8.sh

        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, saveButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12.sw
        buttonStack.distribution = .fillEqually

        let nameHeaderStack = UIStackView(arrangedSubviews: [nameLabel, nameCounterLabel])
        nameHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        nameHeaderStack.axis = .horizontal
        nameHeaderStack.alignment = .center
        nameHeaderStack.spacing = 8.sw

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            avatarStack,
            nameHeaderStack,
            nameField,
            buttonStack
        ])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14.sh
        contentStack.setCustomSpacing(18.sh, after: titleLabel)
        contentStack.setCustomSpacing(8.sh, after: nameHeaderStack)

        view.addSubview(contentStack)
        saveButton.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24.sh),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24.sw),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24.sw),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20.sh),

            avatarButton.widthAnchor.constraint(equalToConstant: 88.swh),
            avatarButton.heightAnchor.constraint(equalToConstant: 88.swh),

            avatarImageView.topAnchor.constraint(equalTo: avatarButton.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarButton.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor),

            avatarPlaceholderImageView.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor),
            avatarPlaceholderImageView.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor),
            avatarPlaceholderImageView.widthAnchor.constraint(equalToConstant: 38.swh),
            avatarPlaceholderImageView.heightAnchor.constraint(equalToConstant: 38.swh),

            avatarOverlay.leadingAnchor.constraint(equalTo: avatarButton.leadingAnchor),
            avatarOverlay.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor),
            avatarOverlay.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor),
            avatarOverlay.heightAnchor.constraint(equalToConstant: 30.sh),

            cameraImageView.centerXAnchor.constraint(equalTo: avatarOverlay.centerXAnchor),
            cameraImageView.centerYAnchor.constraint(equalTo: avatarOverlay.centerYAnchor),
            cameraImageView.widthAnchor.constraint(equalToConstant: 17.swh),
            cameraImageView.heightAnchor.constraint(equalToConstant: 17.swh),

            nameField.heightAnchor.constraint(equalToConstant: 46.sh),
            cancelButton.heightAnchor.constraint(equalToConstant: 46.sh),
            saveButton.heightAnchor.constraint(equalToConstant: 46.sh),

            activityIndicator.centerXAnchor.constraint(equalTo: saveButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])

        updateSaveButtonState()
    }

    private func updateAvatarPreview() {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil

        if let selectedImage {
            avatarImageView.image = selectedImage
            avatarImageView.isHidden = false
            avatarPlaceholderImageView.isHidden = true
            removeAvatarButton.isHidden = false
            return
        }

        let trimmed = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        removeAvatarButton.isHidden = trimmed.isEmpty || trimmed.contains("avatar-group.png")
        guard !trimmed.isEmpty, !trimmed.contains("avatar-group.png") else {
            avatarImageView.image = nil
            avatarImageView.isHidden = true
            avatarPlaceholderImageView.isHidden = false
            avatarButton.backgroundColor = .groupDMDefaultAvatar
            return
        }

        let proxied = ImgproxyURL.avatarProxyURL(from: trimmed, width: 180, height: 180)
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            avatarImageView.image = cached
            avatarImageView.isHidden = false
            avatarPlaceholderImageView.isHidden = true
            return
        }

        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarPlaceholderImageView.isHidden = false
        avatarButton.backgroundColor = .groupDMDefaultAvatar
        avatarLoadTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self, let image else { return }
            self.avatarImageView.image = image
            self.avatarImageView.isHidden = false
            self.avatarPlaceholderImageView.isHidden = true
        }
    }

    @objc private func pickAvatarTapped() {
        if #available(iOS 13.0, *) {
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    @objc private func removeAvatarTapped() {
        avatarURL = ""
        selectedImage = nil
        selectedImageData = nil
        updateAvatarPreview()
    }

    @objc private func nameFieldDidReturn() {
        view.endEditing(true)
    }

    @objc private func nameFieldEditingChanged() {
        updateSaveButtonState()
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        guard textField === nameField else { return true }
        let current = textField.text ?? ""
        guard let stringRange = Range(range, in: current) else { return false }
        let proposed = current.replacingCharacters(in: stringRange, with: string)
        if proposed.count <= Self.maxGroupNameLength || proposed.count < current.count {
            return true
        }

        let keptPrefixCount = current.distance(from: current.startIndex, to: stringRange.lowerBound)
        let keptSuffixCount = current.distance(from: stringRange.upperBound, to: current.endIndex)
        let remaining = Self.maxGroupNameLength - keptPrefixCount - keptSuffixCount
        guard remaining > 0 else { return false }

        let allowed = String(string.prefix(remaining))
        textField.text = current.replacingCharacters(in: stringRange, with: allowed)
        nameFieldEditingChanged()
        return false
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        if #available(iOS 13.0, *) {
            guard !isSaving else { return }
            let name = trimmedGroupName
            guard !name.isEmpty else {
                updateSaveButtonState()
                Toast.error(L(L10n.ChannelDetail.groupNameRequired))
                return
            }
            guard name.count <= Self.maxGroupNameLength else {
                updateSaveButtonState()
                return
            }

            setSaving(true)
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.setSaving(false) }
                guard let token = await self.context.getToken() else {
                    Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                    return
                }
                do {
                    let uploadedAvatarURL = try await self.uploadSelectedAvatarIfNeeded(token: token)
                    let response = try await self.context.account.network.updateChannelDesc(
                        clanId: 0,
                        channelId: self.originalChannel.channelID,
                        channelLabel: name,
                        channelAvatar: uploadedAvatarURL,
                        token: token
                    )

                    var updated = self.originalChannel
                    updated.channelLabel = response.channelLabel.isEmpty ? name : response.channelLabel
                    updated.channelAvatar = uploadedAvatarURL
                    if response.type != 0 {
                        updated.type = response.type
                    } else if updated.type == 0 {
                        updated.type = MezonConstants.ChannelType.group.rawValue
                    }
                    updated.clanID = 0
                    if response.updateTimeSeconds != 0 {
                        updated.updateTimeSeconds = response.updateTimeSeconds
                    }

                    self.onSaved(updated)
                    Toast.success(L(L10n.ChannelDetail.groupUpdated))
                    self.dismiss(animated: true)
                } catch {
                    SentryLogger.capture(error, extras: [
                        "where": "ChannelDetail.updateGroup",
                        "channelId": self.originalChannel.channelID,
                    ])
                    Toast.error(L(L10n.ChannelDetail.updateGroupFailed))
                }
            }
        }
    }

    private func setSaving(_ saving: Bool) {
        isSaving = saving
        nameField.isEnabled = !saving
        cancelButton.isEnabled = !saving
        saveButton.isEnabled = !saving
        avatarButton.isEnabled = !saving
        removeAvatarButton.isEnabled = !saving
        saveButton.setTitle(saving ? nil : L(L10n.Common.save), for: .normal)
        updateSaveButtonState()
        if saving {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func updateSaveButtonState() {
        updateNameCounter()
        let enabled = !trimmedGroupName.isEmpty && trimmedGroupName.count <= Self.maxGroupNameLength && !isSaving
        saveButton.isEnabled = enabled
        saveButton.backgroundColor = (enabled || isSaving)
            ? UIColor.theme.bgViolet
            : UIColor.theme.textDisabled.withAlphaComponent(0.45)
    }

    private func updateNameCounter() {
        let count = nameField.text?.count ?? 0
        nameCounterLabel.text = "\(count)/\(Self.maxGroupNameLength)"
        nameCounterLabel.textColor = count > Self.maxGroupNameLength
            ? UIColor.systemRed
            : UIColor.theme.textDisabled
    }

    @available(iOS 13.0, *)
    private func uploadSelectedAvatarIfNeeded(token: String) async throws -> String {
        guard let selectedImage, let selectedImageData else {
            return avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard selectedImageData.count <= Self.maxAvatarBytes else {
            throw MezonError.httpError(statusCode: 0, message: "File size exceeds 10MB limit")
        }

        let filename = "group_dm_\(originalChannel.channelID)_\(Int(Date().timeIntervalSince1970)).jpg"
        let filetype = "image/jpeg"
        let uploadInfo = try await context.account.network.uploadAttachmentFile(
            filename: filename,
            filetype: filetype,
            size: selectedImageData.count,
            width: Int(selectedImage.size.width),
            height: Int(selectedImage.size.height),
            token: token
        )
        try await context.account.network.uploadToMinIO(
            url: uploadInfo.url,
            data: selectedImageData,
            contentType: filetype
        )
        let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
        ImageCache.shared.setImage(selectedImage, data: selectedImageData, forKey: cdnURL)
        return cdnURL
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [weak self] in
            guard let self, let image else { return }
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            if data.count > Self.maxAvatarBytes {
                Toast.error("File size exceeds 10MB limit")
                return
            }
            self.selectedImage = image
            self.selectedImageData = data
            self.updateAvatarPreview()
        }
    }
}

enum ChannelMuteHelper {
    @available(iOS 13.0, *)
    static func setMuteChannel(
        context: AccountContext,
        channelId: Int64,
        clanId: Int64,
        muteTimeSeconds: Int32
    ) {
        Task { @MainActor in
            guard let token = await context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                try await MezonHTTPClient.shared.setMuteChannel(
                    id: channelId,
                    clanId: clanId,
                    muteTime: muteTimeSeconds,
                    active: 0,
                    token: token
                )
                
                let existingRecord = context.account.postbox.read { tx in
                    tx.getNotificationSetting(entityId: channelId)
                }
                let type = existingRecord?.notificationSettingType ?? 1
                let active = existingRecord?.active ?? 1
                
                let record = NotificationSettingRecord(
                    id: 0,
                    entityId: channelId,
                    scope: .channel,
                    notificationSettingType: type,
                    timeMuteSeconds: UInt32(bitPattern: muteTimeSeconds),
                    active: active
                )
                context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }
                
                NotificationCenter.default.post(
                    name: .mezonNotificationSettingDidUpdate,
                    object: nil,
                    userInfo: ["channelId": channelId, "record": record]
                )
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }
}
