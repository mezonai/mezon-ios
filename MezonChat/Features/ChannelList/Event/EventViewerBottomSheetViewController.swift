import UIKit

enum EventListFilter {
    static func visibleEvents(
        from events: [Mezon_Api_EventManagement],
        currentUserId: Int64,
        channels: [Mezon_Api_ChannelDescription]
    ) -> [Mezon_Api_EventManagement] {
        let accessibleChannelIds = Set(channels.map(\.channelID))
        let privateTextChannelIds = privateTextChannelIds(from: channels)
        return events.filter { event in
            let passesPrivacy = !event.isPrivate || event.creatorID == currentUserId
            let passesChannel = event.channelID == 0
                || accessibleChannelIds.contains(event.channelID)
                || privateTextChannelIds.contains(event.channelID)
            return passesPrivacy && passesChannel
        }
    }

    static func privateTextChannelIds(from channels: [Mezon_Api_ChannelDescription]) -> Set<Int64> {
        Set(
            channels.filter { channel in
                let isPrivate = channel.channelPrivate != 0
                let isText = channel.type == MezonConstants.ChannelType.channel.rawValue
                let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
                return isPrivate && (isText || isThread)
            }.map(\.channelID)
        )
    }
}

enum EventDisplayStatus: Int32 {
    case created = 0
    case upcoming = 1
    case ongoing = 2
    case completed = 3
}

enum EventDisplayHelper {
    static func resolvedStatus(for event: Mezon_Api_EventManagement, now: Date = Date()) -> EventDisplayStatus {
        if let stored = EventDisplayStatus(rawValue: event.eventStatus) {
            return stored
        }
        guard event.startTimeSeconds > 0 else { return .created }
        let start = Date(timeIntervalSince1970: TimeInterval(event.startTimeSeconds))
        let secondsLeft = start.timeIntervalSince(now)
        if secondsLeft <= 0 { return .ongoing }
        if secondsLeft <= 10 * 60 { return .upcoming }
        return .created
    }

    static func statusText(for event: Mezon_Api_EventManagement, status: EventDisplayStatus) -> String {
        switch status {
        case .upcoming:
            let start = Date(timeIntervalSince1970: TimeInterval(event.startTimeSeconds))
            let minutes = max(1, Int(ceil(start.timeIntervalSinceNow / 60)))
            return L(L10n.EventMenu.tenMinutesLeft, minutes)
        case .ongoing:
            return L(L10n.EventMenu.eventIsTaking)
        default:
            guard event.startTimeSeconds > 0 else { return "" }
            let date = Date(timeIntervalSince1970: TimeInterval(event.startTimeSeconds))
            return EventDisplayHelper.eventDateFormatter.string(from: date)
        }
    }

    static func statusColor(for status: EventDisplayStatus) -> UIColor {
        switch status {
        case .upcoming:
            return UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        case .ongoing:
            return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        default:
            return UIColor.theme.textStrong
        }
    }

    static func isToday(_ event: Mezon_Api_EventManagement) -> Bool {
        guard event.startTimeSeconds > 0 else { return false }
        let date = Date(timeIntervalSince1970: TimeInterval(event.startTimeSeconds))
        return Calendar.current.isDateInToday(date)
    }

    static func headerTitle(count: Int) -> String {
        if count == 1 {
            return "1 \(L(L10n.EventMenu.eventOne))"
        }
        if count > 1 {
            return "\(count) \(L(L10n.EventMenu.title))"
        }
        return L(L10n.EventMenu.title)
    }

    static func eventBadge(for event: Mezon_Api_EventManagement) -> (text: String, color: UIColor)? {
        if event.isPrivate {
            return (L(L10n.EventMenu.privateEvent), UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1))
        }
        if event.channelID != 0 {
            return (L(L10n.EventMenu.channelEvent), UIColor(red: 0.98, green: 0.55, blue: 0.15, alpha: 1))
        }
        return (L(L10n.EventMenu.clanEvent), UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1))
    }

    static func makeBadgeView(text: String, color: UIColor) -> UIView {
        let wrapper = UIView()
        let badge = UIView()
        badge.backgroundColor = color
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        wrapper.addSubview(badge)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            badge.topAnchor.constraint(equalTo: wrapper.topAnchor),
            badge.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            badge.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            badge.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        return wrapper
    }

    static func configureInterestButton(_ button: UIButton, isInterested: Bool) {
        let title = isInterested ? L(L10n.EventMenu.itemUninterested) : L(L10n.EventMenu.itemInterested)
        let iconName = isInterested ? "bell.slash" : "bell"
        let symbolConfig = MezonSymbolConfiguration(pointSize: 13, weight: .medium)
        let image = UIImage.mezonSystemImage(iconName, withConfiguration: symbolConfig)?
            .withRenderingMode(.alwaysTemplate)
        let textColor = UIColor.theme.textStrong
        button.setTitle(title, for: .normal)
        button.setImage(image, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.tintColor = textColor
        button.setTitleColor(textColor, for: .normal)
        button.backgroundColor = UIColor.theme.secondary
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.4).cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2, bottom: 0, right: 2)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: -2)
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

final class EventViewerBottomSheetViewController: UIViewController {

    @available(iOS 15.0, *)
    private static let fiftyPercentDetentId = UISheetPresentationController.Detent.Identifier("mezon.event.fiftyPercent")
    @available(iOS 15.0, *)
    private static let eightyPercentDetentId = UISheetPresentationController.Detent.Identifier("mezon.event.eightyPercent")

    private let context: AccountContext
    private let clanId: Int64
    private let clanName: String
    private let clanLogoURL: String
    private let channels: [Mezon_Api_ChannelDescription]

    var onOpenChannel: ((Mezon_Api_ChannelDescription) -> Void)?
    var onPresentJoinVoice: ((Mezon_Api_ChannelDescription) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerTitleLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView.mezonMedium()
    private let loadingRow = UIView()
    private let listStack = UIStackView()
    private let emptyStateView = UIView()

    private var eventsDisposable: Disposable?
    private var isFetching = false
    private var loadedEvents: [Mezon_Api_EventManagement] = []

    init(
        context: AccountContext,
        clanId: Int64,
        clanName: String,
        clanLogoURL: String,
        channels: [Mezon_Api_ChannelDescription]
    ) {
        self.context = context
        self.clanId = clanId
        self.clanName = clanName
        self.clanLogoURL = clanLogoURL
        self.channels = channels
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        eventsDisposable?.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        buildContent()
        applyTheme()
        if #available(iOS 13.0, *) {
            reloadEvents()
        }
        if #available(iOS 13.0, *) {
            fetchEvents()
        }
        eventsDisposable = context.engine.clanData.clanEventsUpdated.signal().start(next: { [weak self] updatedClanId in
            guard let self, updatedClanId == self.clanId else { return }
            self.loadedEvents = self.context.engine.clanData.getClanEvents(clanId: self.clanId)?.events ?? []
            if #available(iOS 13.0, *) {
                self.reloadEvents()
            }
        })
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func themeDidChange() {
        if #available(iOS 13.0, *) {
            applyTheme()
            reloadEvents()
        }
    }

    private func configureSheet() {
        if #available(iOS 15.0, *) {
            guard let sheet = sheetPresentationController else { return }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            if #available(iOS 16.0, *) {
                let fiftyDetent = UISheetPresentationController.Detent.custom(
                    identifier: Self.fiftyPercentDetentId
                ) { context in
                    context.maximumDetentValue * 0.5
                }
                let eightyDetent = UISheetPresentationController.Detent.custom(
                    identifier: Self.eightyPercentDetentId
                ) { context in
                    context.maximumDetentValue * 0.8
                }
                sheet.detents = [fiftyDetent, eightyDetent]
                sheet.selectedDetentIdentifier = Self.fiftyPercentDetentId
            } else {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
        }
    }

    private func buildContent() {
        view.backgroundColor = UIColor.theme.primary

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        contentStack.addArrangedSubview(makeHeaderRow())
        contentStack.addArrangedSubview(makeLoadingRow(into: loadingRow))
        contentStack.addArrangedSubview(listStack)
        contentStack.addArrangedSubview(emptyStateView)
        emptyStateView.isHidden = true
    }

    private func makeHeaderRow() -> UIView {
        let container = UIView()
        headerTitleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        headerTitleLabel.textAlignment = .center
        headerTitleLabel.numberOfLines = 1
        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerTitleLabel)
        NSLayoutConstraint.activate([
            headerTitleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            headerTitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            headerTitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerTitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        return container
    }

    private func makeLoadingRow(into wrapper: UIView) -> UIView {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            loadingIndicator.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),
        ])
        wrapper.isHidden = true
        return wrapper
    }

    private func makeEmptyState() -> UIView {
        let wrapper = UIView()
        wrapper.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        let iconWrap = UIView()
        iconWrap.layer.cornerRadius = 28
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        let iconView = UIImageView(image: UIImage(named: "Channel/Event"))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.EventMenu.noEvent)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let descLabel = UILabel()
        descLabel.text = L(L10n.EventMenu.noEventDescription)
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0

        stack.addArrangedSubview(iconWrap)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(descLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.layoutMarginsGuide.bottomAnchor),

            iconWrap.widthAnchor.constraint(equalToConstant: 72),
            iconWrap.heightAnchor.constraint(equalToConstant: 72),
            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
        ])

        wrapper.tag = 9001
        return wrapper
    }

    private func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        headerTitleLabel.textColor = UIColor.theme.textStrong
        if let empty = emptyStateView.subviews.first {
            styleEmptyState(empty)
        }
    }

    private func styleEmptyState(_ view: UIView) {
        guard let stack = view.subviews.first as? UIStackView else { return }
        if let iconWrap = stack.arrangedSubviews.first {
            iconWrap.backgroundColor = UIColor.theme.tertiary
        }
        for case let label as UILabel in stack.arrangedSubviews {
            if label.font.pointSize >= 16 {
                label.textColor = UIColor.theme.text
            } else {
                label.textColor = UIColor.theme.textDisabled
            }
        }
    }

    private func currentUserId() -> Int64 {
        if let userId = context.currentUser?.id, let parsed = Int64(userId) {
            return parsed
        }
        return Int64(context.account.id) ?? 0
    }

    private func allEventsSource() -> [Mezon_Api_EventManagement] {
        if !loadedEvents.isEmpty {
            return loadedEvents
        }
        return context.engine.clanData.getClanEvents(clanId: clanId)?.events ?? []
    }

    private func filteredEvents() -> [Mezon_Api_EventManagement] {
        EventListFilter.visibleEvents(
            from: allEventsSource(),
            currentUserId: currentUserId(),
            channels: channels
        )
    }

    @available(iOS 13.0, *)
    private func reloadEvents() {
        let events = filteredEvents()
        headerTitleLabel.text = EventDisplayHelper.headerTitle(count: events.count)

        listStack.arrangedSubviews.forEach { view in
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if events.isEmpty {
            listStack.isHidden = true
            if emptyStateView.subviews.isEmpty {
                let empty = makeEmptyState()
                emptyStateView.addSubview(empty)
                empty.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    empty.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
                    empty.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
                    empty.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
                    empty.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor),
                ])
            }
            emptyStateView.isHidden = false
            styleEmptyState(emptyStateView.subviews.first!)
        } else {
            emptyStateView.isHidden = true
            listStack.isHidden = false
            listStack.axis = .vertical
            listStack.spacing = 12
            listStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 16, right: 16)
            listStack.isLayoutMarginsRelativeArrangement = true
            for event in events {
                listStack.addArrangedSubview(makeEventRow(event))
            }
        }

        loadingRow.isHidden = !isFetching
        loadingIndicator.isHidden = !isFetching
        if isFetching {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    @available(iOS 13.0, *)
    private func makeEventRow(_ event: Mezon_Api_EventManagement) -> UIView {
        let voiceChannelLabel = channels.first(where: { $0.channelID == event.channelVoiceID })?.channelLabel
        let textChannelLabel = channels.first(where: { $0.channelID == event.channelID })?.channelLabel
        let userId = currentUserId()
        let row = EventListItemView(
            event: event,
            creator: context.account.postbox.read { tx in
                tx.getClanMembers(clanId: clanId).first(where: { $0.userId == event.creatorID })
            },
            voiceChannelLabel: voiceChannelLabel,
            textChannelLabel: textChannelLabel,
            isInterested: userId != 0 && event.userIds.contains(userId)
        )
        row.onTap = { [weak self] in
            guard let self else { return }
            let latest = self.loadedEvents.first(where: { $0.id == event.id }) ?? event
            self.presentEventDetail(latest)
        }
        row.onToggleInterest = { [weak self] in
            self?.toggleEventInterest(event)
        }
        return row
    }

    @available(iOS 13.0, *)
    private func toggleEventInterest(_ event: Mezon_Api_EventManagement) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let userId = self.currentUserId()
            guard userId != 0, let token = await self.context.getToken() else { return }
            let interested = !event.userIds.contains(userId)
            await self.context.engine.clanData.setUserEventInterest(
                clanId: self.clanId,
                eventId: event.id,
                userId: userId,
                interested: interested,
                token: token
            )
            self.loadedEvents = self.context.engine.clanData.getClanEvents(clanId: self.clanId)?.events ?? []
            self.reloadEvents()
        }
    }

    private func presentEventDetail(_ event: Mezon_Api_EventManagement) {
        let vc = EventDetailBottomSheetViewController(
            context: context,
            clanId: clanId,
            clanName: clanName,
            clanLogoURL: clanLogoURL,
            channels: channels,
            event: event,
            onOpenChannel: { [weak self] channel in
                self?.onOpenChannel?(channel)
            },
            onPresentJoinVoice: { [weak self] channel in
                self?.onPresentJoinVoice?(channel)
            }
        )
        present(vc, animated: true)
    }

    @available(iOS 13.0, *)
    private func fetchEvents() {
        guard !isFetching else { return }
        isFetching = true
        reloadEvents()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isFetching = false
                self.reloadEvents()
            }
            guard let token = await self.context.getToken() else { return }
            do {
                let response = try await MezonHTTPClient.shared.listEvents(clanId: self.clanId, token: token)
                self.loadedEvents = response.events
                if let data = try? response.serializedData() {
                    self.context.account.postbox.setPreferenceDataSync(
                        key: PreferencesKeys.clanEvents(clanId: self.clanId),
                        value: data
                    )
                }
            } catch {
                await self.context.engine.clanData.refetchEvents(clanId: self.clanId, token: token)
                self.loadedEvents = self.context.engine.clanData.getClanEvents(clanId: self.clanId)?.events ?? []
            }
        }
    }
}

private final class EventListItemView: UIView, UIGestureRecognizerDelegate {

    var onTap: (() -> Void)?
    var onToggleInterest: (() -> Void)?

    private let event: Mezon_Api_EventManagement
    private let creator: ClanMemberRecord?
    private let voiceChannelLabel: String?
    private let textChannelLabel: String?
    private let isInterested: Bool
    private let cardView = UIView()
    private let interestButton = UIButton(type: .custom)
    private let openDetailGesture = UITapGestureRecognizer()

    init(
        event: Mezon_Api_EventManagement,
        creator: ClanMemberRecord?,
        voiceChannelLabel: String?,
        textChannelLabel: String?,
        isInterested: Bool
    ) {
        self.event = event
        self.creator = creator
        self.voiceChannelLabel = voiceChannelLabel
        self.textChannelLabel = textChannelLabel
        self.isInterested = isInterested
        super.init(frame: .zero)
        build()
        applyTheme()
        openDetailGesture.addTarget(self, action: #selector(handleTap))
        openDetailGesture.delegate = self
        addGestureRecognizer(openDetailGesture)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        onTap?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let touchedView = touch.view,
           touchedView === interestButton || touchedView.isDescendant(of: interestButton) {
            return false
        }
        let point = touch.location(in: interestButton)
        return !interestButton.point(inside: point, with: nil)
    }

    private func build() {
        cardView.isUserInteractionEnabled = true
        cardView.layer.cornerRadius = 15
        cardView.layer.borderWidth = 1
        cardView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 8
        root.isUserInteractionEnabled = true
        root.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(root)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            root.topAnchor.constraint(equalTo: cardView.layoutMarginsGuide.topAnchor),
            root.leadingAnchor.constraint(equalTo: cardView.layoutMarginsGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: cardView.layoutMarginsGuide.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: cardView.layoutMarginsGuide.bottomAnchor),
        ])

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(makeInfoRow())
        contentStack.addArrangedSubview(makeMainArea())
        if event.channelID != 0, let textChannelLabel, !textChannelLabel.isEmpty {
            contentStack.addArrangedSubview(makeChannelFooter(textChannelLabel))
        }

        root.addArrangedSubview(contentStack)
        root.addArrangedSubview(makeActionsRow())
    }

    private func makeActionsRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = true
        EventDisplayHelper.configureInterestButton(interestButton, isInterested: isInterested)
        interestButton.addTarget(self, action: #selector(interestTapped), for: .touchUpInside)
        interestButton.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(interestButton)
        return row
    }

    @objc private func interestTapped() {
        onToggleInterest?()
    }

    private func makeInfoRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8

        let status = EventDisplayHelper.resolvedStatus(for: event)
        let statusStack = UIStackView()
        statusStack.axis = .horizontal
        statusStack.spacing = 6
        statusStack.alignment = .center
        statusStack.tag = 100

        if EventDisplayHelper.isToday(event) {
            statusStack.addArrangedSubview(EventDisplayHelper.makeBadgeView(
                text: L(L10n.EventMenu.newEvent),
                color: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
            ))
        }

        let icon = UIImageView(image: UIImage(named: "Channel/Event"))
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        icon.tag = 101
        statusStack.addArrangedSubview(icon)

        let statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.text = EventDisplayHelper.statusText(for: event, status: status)
        statusLabel.textColor = EventDisplayHelper.statusColor(for: status)
        statusLabel.tag = 102
        statusStack.addArrangedSubview(statusLabel)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rightStack = UIStackView()
        rightStack.axis = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .center

        let avatar = UIImageView()
        avatar.layer.cornerRadius = 10
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 20).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 20).isActive = true
        avatar.tag = 200
        loadAvatar(into: avatar)

        let countStack = UIStackView()
        countStack.axis = .horizontal
        countStack.spacing = 4
        countStack.alignment = .center
        let groupIcon = UIImageView(image: UIImage.mezonSystemImage("person.2.fill"))
        groupIcon.tintColor = UIColor.theme.text
        groupIcon.contentMode = .scaleAspectFit
        groupIcon.translatesAutoresizingMaskIntoConstraints = false
        groupIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        groupIcon.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let countLabel = UILabel()
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = UIColor.theme.text
        countLabel.text = "\(event.userIds.filter { $0 != 0 }.count)"
        countStack.addArrangedSubview(groupIcon)
        countStack.addArrangedSubview(countLabel)

        rightStack.addArrangedSubview(avatar)
        rightStack.addArrangedSubview(countStack)

        row.addArrangedSubview(statusStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(rightStack)
        return row
    }

    private func makeMainArea() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 5
        textStack.alignment = .leading
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let badge = EventDisplayHelper.eventBadge(for: event) {
            textStack.addArrangedSubview(EventDisplayHelper.makeBadgeView(text: badge.text, color: badge.color))
        }

        let titleLabel = UILabel()
        titleLabel.text = event.title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.numberOfLines = 0
        textStack.addArrangedSubview(titleLabel)

        if !event.description_p.isEmpty {
            let descLabel = UILabel()
            descLabel.text = event.description_p
            descLabel.font = .systemFont(ofSize: 13)
            descLabel.textColor = UIColor.theme.text
            descLabel.numberOfLines = 3
            textStack.addArrangedSubview(descLabel)
        }

        if let locationRow = makeLocationRow() {
            textStack.addArrangedSubview(locationRow)
        }

        row.addArrangedSubview(textStack)

        if !event.logo.isEmpty {
            let logoView = UIImageView()
            logoView.contentMode = .scaleAspectFill
            logoView.clipsToBounds = true
            logoView.layer.cornerRadius = 6
            logoView.translatesAutoresizingMaskIntoConstraints = false
            logoView.widthAnchor.constraint(equalToConstant: 80).isActive = true
            logoView.heightAnchor.constraint(equalToConstant: 80).isActive = true
            let proxied = ImgproxyURL.create(from: event.logo, width: 160, height: 160)
            ImageCache.shared.loadImage(urlString: proxied) { image in
                logoView.image = image
            }
            row.addArrangedSubview(logoView)
        }

        return row
    }

    private func makeLocationRow() -> UIView? {
        if !event.address.isEmpty {
            return inlineIconRow(
                icon: UIImage.mezonSystemImage("mappin.and.ellipse"),
                text: event.address
            )
        }
        guard event.channelVoiceID != 0 || voiceChannelLabel != nil else { return nil }
        let label = voiceChannelLabel ?? L(L10n.EventMenu.privateRoom)
        return inlineIconRow(icon: UIImage.mezonSystemImage("speaker.wave.2.fill"), text: label)
    }

    private func inlineIconRow(icon: UIImage?, text: String) -> UIView {
        let locationStack = UIStackView()
        locationStack.axis = .horizontal
        locationStack.spacing = 6
        locationStack.alignment = .center
        let iconView = UIImageView(image: icon)
        iconView.tintColor = UIColor.theme.textStrong
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let locationLabel = UILabel()
        locationLabel.text = text
        locationLabel.font = .systemFont(ofSize: 12)
        locationLabel.textColor = UIColor.theme.textStrong
        locationLabel.numberOfLines = 2
        locationStack.addArrangedSubview(iconView)
        locationStack.addArrangedSubview(locationLabel)
        return locationStack
    }

    private func makeChannelFooter(_ label: String) -> UIView {
        let footer = UILabel()
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = UIColor.theme.textDisabled
        footer.text = L(L10n.EventMenu.channelAudience, label)
        footer.numberOfLines = 0
        return footer
    }

    private func loadAvatar(into imageView: UIImageView) {
        let raw = !(creator?.clanAvatar.isEmpty ?? true)
            ? creator?.clanAvatar
            : creator?.userAvatarURL
        guard let raw, !raw.isEmpty else {
            imageView.image = UIImage.mezonSystemImage("person.circle.fill")
            imageView.tintColor = UIColor.theme.textDisabled
            return
        }
        let proxied = ImgproxyURL.avatarProxyURL(from: raw, width: 56, height: 56)
        ImageCache.shared.loadImage(urlString: proxied) { image in
            imageView.image = image ?? UIImage.mezonSystemImage("person.circle.fill")
        }
    }

    private func applyTheme() {
        cardView.backgroundColor = UIColor.theme.secondary
        cardView.layer.borderColor = UIColor.theme.border.withAlphaComponent(0.4).cgColor
    }
}
