import UIKit

/// The participant invitation uses the same card, room badge and action hierarchy
/// as desktop, with a scrollable body for small screens and larger text sizes.
@MainActor
final class VoiceBreakoutInviteController: UIViewController {
    enum Mode { case assigned, choose, returnToMain }

    struct Room {
        let channelId: Int64
        let name: String
    }

    private let mode: Mode
    private let rooms: [Room]
    private let onJoin: (Int64) -> Void
    private let onNotNow: () -> Void
    private var isCompleting = false
    private let card = UIView()
    private let titleLabel = UILabel()
    private let bodyScroll = UIScrollView()
    private let bodyStack = UIStackView()
    private let footer = UIStackView()
    private let footerSpacer = UIView()
    private var primaryActionButton: UIButton?
    private var actionButtons: [UIButton] = []

    private static let surface = UIColor(white: 0.14, alpha: 1)
    private static let roomSurface = UIColor(white: 0.18, alpha: 1)
    private static let border = UIColor(white: 0.24, alpha: 1)
    private static let text = UIColor(white: 0.95, alpha: 1)
    private static let secondaryText = UIColor(white: 0.72, alpha: 1)
    private static let accent = UIColor(red: 0.345, green: 0.396, blue: 0.949, alpha: 1)

    init(mode: Mode, rooms: [Room], onJoin: @escaping (Int64) -> Void, onNotNow: @escaping () -> Void) {
        self.mode = mode
        self.rooms = rooms
        self.onJoin = onJoin
        self.onNotNow = onNotNow
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        let backdrop = UIControl()
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        backdrop.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.isAccessibilityElement = false
        view.addSubview(backdrop)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Self.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = Self.border.cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.3
        card.layer.shadowRadius = 28
        card.layer.shadowOffset = CGSize(width: 0, height: 12)
        view.addSubview(card)

        let symbol = UIImageView(image: UIImage(systemName: "square.split.2x2"))
        symbol.tintColor = Self.secondaryText
        symbol.contentMode = .scaleAspectFit
        symbol.isAccessibilityElement = false
        symbol.widthAnchor.constraint(equalToConstant: 20).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 20).isActive = true
        titleLabel.text = L("voiceChannel.breakout.title")
        titleLabel.font = scaledFont(size: 18, weight: .semibold, style: .headline, maximum: 28)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Self.text
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.accessibilityTraits = .header
        let header = UIStackView(arrangedSubviews: [symbol, titleLabel])
        header.alignment = .center
        header.spacing = 10

        bodyScroll.translatesAutoresizingMaskIntoConstraints = false
        bodyScroll.contentInsetAdjustmentBehavior = .never
        bodyScroll.bounces = false
        bodyStack.axis = .vertical
        bodyStack.spacing = 16
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyScroll.addSubview(bodyStack)
        let message = UILabel()
        switch mode {
        case .assigned: message.text = L("voiceChannel.breakout.assigned")
        case .choose: message.text = L("voiceChannel.breakout.choose")
        case .returnToMain: message.text = L("voiceChannel.breakout.return")
        }
        message.font = scaledFont(size: 14)
        message.adjustsFontForContentSizeCategory = true
        message.textColor = UIColor(white: 0.85, alpha: 1)
        message.numberOfLines = 0
        message.setContentCompressionResistancePriority(.required, for: .vertical)
        bodyStack.addArrangedSubview(message)
        if mode == .assigned, let room = rooms.first {
            bodyStack.addArrangedSubview(makeRoomRow(room, index: nil))
        } else if mode == .choose {
            let list = UIStackView()
            list.axis = .vertical
            list.spacing = 8
            for (index, room) in rooms.enumerated() {
                list.addArrangedSubview(makeRoomRow(room, index: index))
            }
            bodyStack.addArrangedSubview(list)
        }

        footer.spacing = 8
        footer.addArrangedSubview(footerSpacer)
        let cancel = makeAction(title: L("voiceChannel.breakout.notNow"), primary: false)
        cancel.accessibilityIdentifier = "voice.breakout.notNow"
        cancel.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)
        if mode != .choose, !rooms.isEmpty {
            let primary = makeAction(title: L(mode == .returnToMain
                ? "voiceChannel.breakout.returnToMain" : "voiceChannel.breakout.join"), primary: true)
            primary.accessibilityIdentifier = "voice.breakout.join"
            primary.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
            primaryActionButton = primary
            footer.addArrangedSubview(primary)
        }
        footer.addArrangedSubview(cancel)
        updateFooterLayout(cardWidth: min(420, view.bounds.width - 40))

        let stack = UIStackView(arrangedSubviews: [header, bodyScroll, footer])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 420)
        preferredWidth.priority = UILayoutPriority(999)
        let naturalBodyHeight = bodyScroll.heightAnchor.constraint(equalTo: bodyStack.heightAnchor)
        // Expand to the content when it fits; once capped, scroll instead of
        // compressing away the message or truncating longer room names.
        naturalBodyHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            preferredWidth,
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            bodyStack.leadingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.leadingAnchor),
            bodyStack.trailingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.trailingAnchor),
            bodyStack.topAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.topAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.bottomAnchor),
            bodyStack.widthAnchor.constraint(equalTo: bodyScroll.frameLayoutGuide.widthAnchor),
            naturalBodyHeight,
            bodyScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 320),
            bodyScroll.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.55),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFooterLayout(cardWidth: card.bounds.width)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
    }

    override func accessibilityPerformEscape() -> Bool {
        notNowTapped()
        return true
    }

    private func makeAction(title: String, primary: Bool) -> UIButton {
        let button = UIButton(type: .system)
        let font = scaledFont(size: 14, weight: .medium, maximum: 22)
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.baseForegroundColor = primary ? .white : Self.secondaryText
            configuration.titleAlignment = .center
            configuration.titleLineBreakMode = .byWordWrapping
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
            configuration.background.backgroundColor = primary ? Self.accent : .clear
            configuration.background.cornerRadius = 8
            configuration.cornerStyle = .fixed
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var attributes = incoming
                attributes.font = font
                return attributes
            }
            button.configuration = configuration
        } else {
            button.setTitle(title, for: .normal)
            button.setTitleColor(primary ? .white : Self.secondaryText, for: .normal)
            button.titleLabel?.font = font
            button.contentEdgeInsets = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
            button.backgroundColor = primary ? Self.accent : .clear
            button.layer.cornerRadius = 8
        }
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        actionButtons.append(button)
        return button
    }

    private func makeRoomRow(_ room: Room, index: Int?) -> UIView {
        let row: UIView
        if let index {
            let button = UIButton(type: .custom)
            button.tag = index
            button.accessibilityLabel = room.name
            button.accessibilityHint = L("voiceChannel.breakout.join")
            button.accessibilityIdentifier = "voice.breakout.room.\(room.channelId)"
            button.addTarget(self, action: #selector(roomTapped(_:)), for: .touchUpInside)
            actionButtons.append(button)
            row = button
        } else {
            row = UIView()
        }
        row.backgroundColor = Self.roomSurface
        row.layer.cornerRadius = 8
        row.layer.borderWidth = 1
        row.layer.borderColor = Self.border.cgColor
        let icon = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
        icon.tintColor = Self.accent
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let label = UILabel()
        label.text = room.name
        label.font = scaledFont(size: 14, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Self.text
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        let content = UIStackView(arrangedSubviews: [icon, label])
        content.alignment = .center
        content.spacing = 10
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        if index != nil {
            let join = UILabel()
            join.text = L("voiceChannel.breakout.join")
            join.textColor = Self.accent
            join.font = scaledFont(size: 14, weight: .semibold, maximum: 22)
            join.adjustsFontForContentSizeCategory = true
            join.setContentHuggingPriority(.required, for: .horizontal)
            join.setContentCompressionResistancePriority(.required, for: .horizontal)
            content.addArrangedSubview(join)
        }
        row.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        return row
    }

    @objc private func roomTapped(_ sender: UIButton) {
        guard rooms.indices.contains(sender.tag) else { return }
        let channelId = rooms[sender.tag].channelId
        complete { [onJoin] in onJoin(channelId) }
    }

    private func scaledFont(size: CGFloat, weight: UIFont.Weight = .regular,
                            style: UIFont.TextStyle = .subheadline, maximum: CGFloat = 24) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(
            for: .systemFont(ofSize: size, weight: weight), maximumPointSize: maximum, compatibleWith: traitCollection)
    }

    private func updateFooterLayout(cardWidth: CGFloat) {
        let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory || cardWidth < 340
        let axis: NSLayoutConstraint.Axis = vertical ? .vertical : .horizontal
        let primaryIndex = vertical ? 1 : footer.arrangedSubviews.count - 1
        let reorderPrimary = primaryActionButton.map {
            footer.arrangedSubviews.firstIndex(of: $0) != primaryIndex
        } ?? false
        guard footer.axis != axis || footerSpacer.isHidden != vertical || reorderPrimary else { return }
        footer.axis = axis
        footerSpacer.isHidden = vertical
        if reorderPrimary, let primaryActionButton {
            footer.removeArrangedSubview(primaryActionButton)
            footer.insertArrangedSubview(primaryActionButton, at: primaryIndex)
        }
        view.setNeedsLayout()
    }

    @objc private func joinTapped() {
        guard let room = rooms.first else { return }
        complete { [onJoin] in onJoin(room.channelId) }
    }

    @objc private func notNowTapped() { complete(onNotNow) }

    private func complete(_ action: @escaping () -> Void) {
        guard !isCompleting else { return }
        isCompleting = true
        actionButtons.forEach { $0.isEnabled = false }
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled, completion: action)
    }
}
