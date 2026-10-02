import UIKit

@MainActor
enum EventDeleteConfirmation {
    static func present(event: Mezon_Api_EventManagement, clanId: Int64, context: AccountContext, from presenter: UIViewController, onDeleted: (() -> Void)? = nil) {
        guard EventEditorAccess.canEdit(event, context: context) else { return }
        let alert = UIAlertController(title: L(L10n.EventMenu.deleteTitle), message: L(L10n.EventMenu.deleteMessage, event.title), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.EventMenu.deleteEvent), style: .destructive) { [weak presenter] _ in
            guard let presenter, EventEditorAccess.canEdit(event, context: context) else { return }
            presenter.view.isUserInteractionEnabled = false
            presenter.isModalInPresentation = true
            Task { @MainActor in
                defer {
                    presenter.view.isUserInteractionEnabled = true
                    presenter.isModalInPresentation = false
                }
                guard let token = await context.getToken() else {
                    Toast.error(L(L10n.EventEditor.sessionExpired))
                    return
                }
                do {
                    try await context.engine.clanData.deleteEvent(event, clanId: clanId, token: token)
                    Toast.success(L(L10n.EventMenu.deleted))
                    onDeleted?()
                } catch {
                    Toast.error(error.localizedDescription)
                }
            }
        })
        presenter.present(alert, animated: true)
    }
}

final class EventDetailBottomSheetViewController: UIViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let clanName: String
    private let clanLogoURL: String
    private let channels: [Mezon_Api_ChannelDescription]
    private var event: Mezon_Api_EventManagement
    private let onOpenChannel: ((Mezon_Api_ChannelDescription) -> Void)?
    private let onPresentJoinVoice: ((Mezon_Api_ChannelDescription) -> Void)?

    private let segmentedControl = UISegmentedControl()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let interestButton = UIButton(type: .custom)
    private var eventsDisposable: Disposable?

    init(
        context: AccountContext,
        clanId: Int64,
        clanName: String,
        clanLogoURL: String,
        channels: [Mezon_Api_ChannelDescription],
        event: Mezon_Api_EventManagement,
        onOpenChannel: ((Mezon_Api_ChannelDescription) -> Void)? = nil,
        onPresentJoinVoice: ((Mezon_Api_ChannelDescription) -> Void)? = nil
    ) {
        self.context = context
        self.clanId = clanId
        self.clanName = clanName
        self.clanLogoURL = clanLogoURL
        self.channels = channels
        self.event = event
        self.onOpenChannel = onOpenChannel
        self.onPresentJoinVoice = onPresentJoinVoice
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        buildContent()
        applyTheme()
        showTab(0)
        eventsDisposable = context.engine.clanData.clanEventsUpdated.signal().start(next: { [weak self] updatedClanId in
            guard let self, updatedClanId == self.clanId else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let events = self.context.engine.clanData.getClanEvents(clanId: self.clanId)?.events else { return }
                guard let updated = events.first(where: { $0.id == self.event.id }) else {
                    self.dismissDetail()
                    return
                }
                self.event = updated
                self.updateInterestedSegmentTitle()
                self.rebuildContent()
            }
        })
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    deinit {
        eventsDisposable?.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeDidChange() {
        applyTheme()
        rebuildContent()
    }

    private func configureSheet() {
        if #available(iOS 15.0, *) {
            guard let sheet = sheetPresentationController else { return }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
        }
    }

    private func buildContent() {
        view.backgroundColor = UIColor.theme.primary

        let interestedCount = event.userIds.filter { $0 != 0 }.count
        segmentedControl.removeAllSegments()
        segmentedControl.insertSegment(withTitle: L(L10n.EventMenu.detailEventInfo), at: 0, animated: false)
        let membersTitle = interestedCount > 0
            ? "\(interestedCount) \(L(L10n.EventMenu.detailInterested))"
            : L(L10n.EventMenu.detailInterested)
        segmentedControl.insertSegment(withTitle: membersTitle, at: 1, animated: false)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        if #available(iOS 13.0, *) {
            segmentedControl.selectedSegmentTintColor = UIColor.theme.tertiary
            segmentedControl.backgroundColor = UIColor.theme.secondary
        }
        let font = UIFont.systemFont(ofSize: 13, weight: .medium)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.theme.textStrong,
            .font: font,
        ], for: .normal)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.theme.textStrong,
            .font: font,
        ], for: .selected)
    }

    @objc private func tabChanged() {
        showTab(segmentedControl.selectedSegmentIndex)
    }

    private func showTab(_ index: Int) {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if index == 0 {
            contentStack.addArrangedSubview(makeDetailCard())
        } else {
            contentStack.addArrangedSubview(makeMembersCard())
        }
    }

    private func editEvent() {
        guard EventEditorAccess.canEdit(event, context: context) else { return }
        let editor = EventEditorViewController(context: context, clanId: clanId, channels: channels, event: event)
        editor.onSaved = { [weak self] updated in
            guard let self, let updated else { return }
            self.event = updated
            self.updateInterestedSegmentTitle()
            self.rebuildContent()
        }
        present(editor, animated: true)
    }

    private var eventURL: URL? {
        if event.isPrivate {
            return MezonConfig.externalEventURL(event.meetRoom.externalLink)
        }
        let channelId = event.channelVoiceID != 0 ? event.channelVoiceID : event.channelID
        return MezonConfig.eventShareURL(clanId: clanId, channelId: channelId)
    }

    private func showEventActions(from source: UIView) {
        let menu = UIAlertController(title: event.title, message: nil, preferredStyle: .actionSheet)
        if EventEditorAccess.canEdit(event, context: context) {
            menu.addAction(UIAlertAction(title: L(L10n.EventEditor.edit), style: .default) { [weak self] _ in
                self?.editEvent()
            })
            menu.addAction(UIAlertAction(title: L(L10n.EventMenu.deleteEvent), style: .destructive) { [weak self] _ in
                self?.confirmDeleteEvent()
            })
        }
        if eventURL != nil {
            menu.addAction(UIAlertAction(title: L(L10n.ClanInviteSheet.copy), style: .default) { [weak self] _ in
                self?.copyEventLink()
            })
        }
        menu.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        menu.popoverPresentationController?.sourceView = source
        menu.popoverPresentationController?.sourceRect = source.bounds
        present(menu, animated: true)
    }

    private func confirmDeleteEvent() {
        EventDeleteConfirmation.present(event: event, clanId: clanId, context: context, from: self) { [weak self] in
            self?.dismissDetail()
        }
    }

    private func dismissDetail() {
        guard !isBeingDismissed else { return }
        presentingViewController?.dismiss(animated: true)
    }

    private func copyEventLink() {
        guard let url = eventURL else { return }
        UIPasteboard.general.string = url.absoluteString
        Toast.success(L(L10n.ClanInviteSheet.linkCopied))
    }

    private func shareEvent(from source: UIView) {
        guard let url = eventURL else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = source
        share.popoverPresentationController?.sourceRect = source.bounds
        present(share, animated: true)
    }

    private func inviteToEvent() {
        guard event.isPrivate, let url = eventURL else { return }
        let invite = ClanInviteSheetViewController(context: context, clanId: clanId, externalEventURL: url)
        invite.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            invite.sheetPresentationController?.prefersGrabberVisible = true
            invite.sheetPresentationController?.detents = [.medium(), .large()]
        }
        present(invite, animated: true)
    }

    private func rebuildContent() {
        showTab(segmentedControl.selectedSegmentIndex)
    }

    private func makeDetailCard() -> UIView {
        let wrapper = UIView()
        wrapper.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let card = eventCardContainer()
        card.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.topAnchor),
            card.leadingAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.bottomAnchor),

            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
        ])

        let more = EventEditorButton()
        more.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        more.tintColor = UIColor.theme.textStrong
        more.accessibilityLabel = L(L10n.EventMenu.actions)
        more.widthAnchor.constraint(equalToConstant: 44).isActive = true
        more.heightAnchor.constraint(equalToConstant: 44).isActive = true
        more.action = { [weak self, weak more] in
            guard let more else { return }
            self?.showEventActions(from: more)
        }
        let menuRow = UIStackView(arrangedSubviews: [UIView(), more])
        stack.addArrangedSubview(menuRow)
        menuRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if !event.logo.isEmpty {
            let cover = UIImageView()
            cover.contentMode = .scaleAspectFill
            cover.clipsToBounds = true
            cover.layer.cornerRadius = 8
            cover.translatesAutoresizingMaskIntoConstraints = false
            cover.heightAnchor.constraint(equalToConstant: 80).isActive = true
            let proxied = ImgproxyURL.create(from: event.logo, width: 600, height: 160)
            ImageCache.shared.loadImage(urlString: proxied) { image in
                cover.image = image
            }
            stack.addArrangedSubview(cover)
            cover.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        stack.addArrangedSubview(makeStatusRow())
        if let badge = EventDisplayHelper.eventBadge(for: event) {
            stack.addArrangedSubview(EventDisplayHelper.makeBadgeView(text: badge.text, color: badge.color))
        }

        let titleLabel = UILabel()
        titleLabel.text = event.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.numberOfLines = 0
        stack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let metaStack = UIStackView()
        metaStack.axis = .vertical
        metaStack.spacing = 10
        metaStack.alignment = .leading
        metaStack.addArrangedSubview(makeClanRow())
        if let locationRow = makeLocationRow() {
            metaStack.addArrangedSubview(locationRow)
        }
        metaStack.addArrangedSubview(makeInterestedSummaryRow())
        metaStack.addArrangedSubview(makeCreatorRow())
        stack.addArrangedSubview(metaStack)
        metaStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if !event.description_p.isEmpty {
            let desc = UILabel()
            desc.text = event.description_p
            desc.font = .systemFont(ofSize: 13)
            desc.textColor = UIColor.theme.textDisabled
            desc.numberOfLines = 0
            stack.addArrangedSubview(desc)
            desc.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let actionsRow = makeActionsRow()
        stack.addArrangedSubview(actionsRow)
        actionsRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        if event.isPrivate, eventURL != nil {
            let externalActions = UIStackView()
            externalActions.spacing = 8
            externalActions.distribution = .fillEqually
            externalActions.addArrangedSubview(actionButton(L(L10n.EventMenu.openLink), symbol: "arrow.up.right.square") { [weak self] in
                self?.handleVoiceJoin()
            })
            externalActions.addArrangedSubview(actionButton(L(L10n.ClanInviteSheet.invite), symbol: "person.badge.plus") { [weak self] in
                self?.inviteToEvent()
            })
            externalActions.addArrangedSubview(actionButton(L(L10n.ClanInviteSheet.copy), symbol: "link") { [weak self] in
                self?.copyEventLink()
            })
            stack.addArrangedSubview(externalActions)
            externalActions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if event.channelID != 0, let channel = channels.first(where: { $0.channelID == event.channelID }) {
            let audienceRow = makeChannelAudienceRow(channelLabel: channel.channelLabel)
            stack.addArrangedSubview(audienceRow)
            audienceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return wrapper
    }

    private func makeMembersCard() -> UIView {
        let wrapper = UIView()
        wrapper.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let card = eventCardContainer()
        card.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(card)

        let memberIds = event.userIds.filter { $0 != 0 }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.topAnchor),
            card.leadingAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.bottomAnchor),

            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor),
        ])

        if memberIds.isEmpty {
            let emptyStack = UIStackView()
            emptyStack.axis = .vertical
            emptyStack.spacing = 8
            emptyStack.alignment = .center
            let icon = UIImageView(image: UIImage(systemName: "person.2.fill"))
            icon.tintColor = UIColor.theme.textDisabled
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let label = UILabel()
            label.text = L(L10n.EventMenu.detailNoOneInterested)
            label.font = .systemFont(ofSize: 14)
            label.textColor = UIColor.theme.textDisabled
            label.textAlignment = .center
            label.numberOfLines = 0
            emptyStack.addArrangedSubview(icon)
            emptyStack.addArrangedSubview(label)
            stack.addArrangedSubview(emptyStack)
            return wrapper
        }

        let members = context.account.postbox.read { tx in
            tx.getClanMembers(clanId: clanId)
        }
        for userId in memberIds {
            let member = members.first(where: { $0.userId == userId })
            stack.addArrangedSubview(makeMemberRow(member: member))
        }
        return wrapper
    }

    private func eventCardContainer() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.theme.secondary
        card.layer.cornerRadius = 15
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.4).cgColor
        card.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return card
    }

    private func makeStatusRow() -> UIView {
        let status = EventDisplayHelper.resolvedStatus(for: event)
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        if EventDisplayHelper.isToday(event) {
            row.addArrangedSubview(EventDisplayHelper.makeBadgeView(
                text: L(L10n.EventMenu.newEvent),
                color: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
            ))
        }
        let icon = UIImageView(image: UIImage(named: "Channel/Event"))
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        row.addArrangedSubview(icon)
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.text = EventDisplayHelper.statusText(for: event, status: status)
        label.textColor = EventDisplayHelper.statusColor(for: status)
        row.addArrangedSubview(label)
        return row
    }

    private func makeClanRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        let avatar = TextAvatarView(username: clanName, size: 18)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 18).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 18).isActive = true
        if !clanLogoURL.isEmpty {
            let imageView = UIImageView(frame: avatar.bounds)
            imageView.contentMode = .scaleAspectFill
            avatar.addSubview(imageView)
            let proxied = ImgproxyURL.avatarProxyURL(from: clanLogoURL, width: 36, height: 36)
            ImageCache.shared.loadImage(urlString: proxied) { [weak avatar, weak imageView] image in
                if let image {
                    imageView?.image = image
                    avatar?.showImageMode()
                }
            }
        }
        let label = UILabel()
        label.text = clanName
        label.font = .systemFont(ofSize: 13)
        label.textColor = UIColor.theme.text
        row.addArrangedSubview(avatar)
        row.addArrangedSubview(label)
        return row
    }

    private func makeLocationRow() -> UIView? {
        if !event.address.isEmpty {
            return inlineRow(
                icon: UIImage(systemName: "mappin.and.ellipse"),
                text: event.address
            )
        }
        let voiceChannel = channels.first(where: { $0.channelID == event.channelVoiceID })
        let voiceLabel = voiceChannel?.channelLabel ?? L(L10n.EventMenu.privateRoom)
        return makeTappableVoiceRow(label: voiceLabel)
    }

    private func makeTappableVoiceRow(label: String) -> UIView {
        let control = UIControl()
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(row)

        let imageView = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
        imageView.tintColor = UIColor.theme.textStrong
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let textLabel = UILabel()
        textLabel.text = label
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = UIColor.theme.textStrong
        textLabel.numberOfLines = 0

        row.addArrangedSubview(imageView)
        row.addArrangedSubview(textLabel)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: control.topAnchor),
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: control.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: control.bottomAnchor),
        ])

        control.addTarget(self, action: #selector(voiceRowTapped), for: .touchUpInside)
        return control
    }

    @objc private func voiceRowTapped() {
        handleVoiceJoin()
    }

    private func handleVoiceJoin() {
        guard event.address.isEmpty else { return }
        if let voiceChannel = resolveVoiceChannel() {
            onPresentJoinVoice?(voiceChannel)
            return
        }
        if let url = MezonConfig.externalEventURL(event.meetRoom.externalLink) {
            UIApplication.shared.open(url)
        }
    }

    private func resolveVoiceChannel() -> Mezon_Api_ChannelDescription? {
        guard event.channelVoiceID != 0 else { return nil }
        if let channel = channels.first(where: { $0.channelID == event.channelVoiceID }) {
            return channel
        }
        var channel = Mezon_Api_ChannelDescription()
        channel.channelID = event.channelVoiceID
        channel.clanID = clanId
        channel.type = MezonConstants.ChannelType.mezonVoice.rawValue
        return channel
    }

    private func currentUserId() -> Int64 {
        if let userId = context.currentUser?.id, let parsed = Int64(userId) {
            return parsed
        }
        return 0
    }

    private func isCurrentUserInterested() -> Bool {
        let userId = currentUserId()
        return userId != 0 && event.userIds.contains(userId)
    }

    private func makeActionsRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .fill
        row.distribution = .fillEqually
        if event.address.isEmpty, eventURL != nil {
            let share = actionButton(L(L10n.Common.share), symbol: "square.and.arrow.up")
            share.action = { [weak self, weak share] in
                guard let share else { return }
                self?.shareEvent(from: share)
            }
            row.addArrangedSubview(share)
        }
        if EventDisplayHelper.resolvedStatus(for: event) != .ongoing {
            EventDisplayHelper.configureInterestButton(interestButton, isInterested: isCurrentUserInterested())
            interestButton.removeTarget(self, action: #selector(interestedTapped), for: .touchUpInside)
            interestButton.addTarget(self, action: #selector(interestedTapped), for: .touchUpInside)
            row.addArrangedSubview(interestButton)
        } else if EventEditorAccess.canEnd(event, context: context) {
            row.addArrangedSubview(actionButton(L(L10n.EventMenu.endEvent), symbol: "xmark.circle") { [weak self] in
                guard let self, EventEditorAccess.canEnd(self.event, context: self.context) else { return }
                self.confirmDeleteEvent()
            })
        }
        row.isHidden = row.arrangedSubviews.isEmpty
        return row
    }

    private func actionButton(_ title: String, symbol: String, action: (() -> Void)? = nil) -> EventEditorButton {
        let button = EventEditorButton()
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)
        button.tintColor = UIColor.theme.textStrong
        button.setTitleColor(UIColor.theme.textStrong, for: .normal)
        button.backgroundColor = UIColor.theme.secondary
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.4).cgColor
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.action = action
        return button
    }

    @objc private func interestedTapped() {
        Task { @MainActor in
            let userId = currentUserId()
            guard userId != 0, let token = await context.getToken() else { return }
            let interested = !isCurrentUserInterested()
            await context.engine.clanData.setUserEventInterest(
                clanId: clanId,
                eventId: event.id,
                userId: userId,
                interested: interested,
                token: token
            )
            if let updated = context.engine.clanData.getClanEvents(clanId: clanId)?.events.first(where: { $0.id == event.id }) {
                event = updated
            }
            updateInterestedSegmentTitle()
            rebuildContent()
        }
    }

    private func updateInterestedSegmentTitle() {
        let interestedCount = event.userIds.filter { $0 != 0 }.count
        let membersTitle = interestedCount > 0
            ? "\(interestedCount) \(L(L10n.EventMenu.detailInterested))"
            : L(L10n.EventMenu.detailInterested)
        segmentedControl.setTitle(membersTitle, forSegmentAt: 1)
    }

    private func makeInterestedSummaryRow() -> UIView {
        let count = event.userIds.filter { $0 != 0 }.count
        let text: String
        switch count {
        case 0: text = L(L10n.EventMenu.detailNoOneInterested)
        case 1: text = L(L10n.EventMenu.detailOnePersonInterested)
        default: text = L(L10n.EventMenu.detailPersonInterested, count)
        }
        return inlineRow(icon: UIImage(systemName: "bell.fill"), text: text)
    }

    private func makeCreatorRow() -> UIView {
        let creator = context.account.postbox.read { tx in
            tx.getClanMembers(clanId: clanId).first(where: { $0.userId == event.creatorID })
        }
        let name = creator.map { member in
            !member.clanNick.isEmpty ? member.clanNick : (!member.displayName.isEmpty ? member.displayName : member.username)
        } ?? ""
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        let avatar = UIImageView()
        avatar.layer.cornerRadius = 9
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 18).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 18).isActive = true
        loadMemberAvatar(creator, into: avatar)
        let prefix = UILabel()
        prefix.text = L(L10n.EventMenu.detailCreatedBy)
        prefix.font = .systemFont(ofSize: 13)
        prefix.textColor = UIColor.theme.text
        let highlight = UILabel()
        highlight.text = name
        highlight.font = .systemFont(ofSize: 13, weight: .medium)
        highlight.textColor = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        row.addArrangedSubview(avatar)
        row.addArrangedSubview(prefix)
        row.addArrangedSubview(highlight)
        return row
    }

    private func makeChannelAudienceRow(channelLabel: String) -> UIView {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = UIColor.theme.textDisabled
        label.numberOfLines = 0
        label.text = L(L10n.EventMenu.channelAudience, channelLabel)
        return label
    }

    private func makeMemberRow(member: ClanMemberRecord?) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        let avatar = UIImageView()
        avatar.layer.cornerRadius = 20
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 40).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 40).isActive = true
        loadMemberAvatar(member, into: avatar)
        let name = member.map { m in
            !m.clanNick.isEmpty ? m.clanNick : (!m.displayName.isEmpty ? m.displayName : m.username)
        } ?? ""
        let label = UILabel()
        label.text = name
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = UIColor.theme.textStrong
        row.addArrangedSubview(avatar)
        row.addArrangedSubview(label)
        return row
    }

    private func inlineRow(icon: UIImage?, text: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        let imageView = UIImageView(image: icon)
        imageView.tintColor = UIColor.theme.text
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = UIColor.theme.text
        label.numberOfLines = 0
        row.addArrangedSubview(imageView)
        row.addArrangedSubview(label)
        return row
    }

    private func loadMemberAvatar(_ member: ClanMemberRecord?, into imageView: UIImageView) {
        let raw = !(member?.clanAvatar.isEmpty ?? true)
            ? member?.clanAvatar
            : member?.userAvatarURL
        guard let raw, !raw.isEmpty else {
            imageView.image = UIImage(systemName: "person.circle.fill")
            imageView.tintColor = UIColor.theme.textDisabled
            return
        }
        let proxied = ImgproxyURL.avatarProxyURL(from: raw, width: 80, height: 80)
        ImageCache.shared.loadImage(urlString: proxied) { image in
            imageView.image = image ?? UIImage(systemName: "person.circle.fill")
        }
    }
}
