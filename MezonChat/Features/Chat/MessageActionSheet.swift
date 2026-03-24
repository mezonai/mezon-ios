import UIKit

enum MessageAction: CaseIterable {
    case reply
    case copyText
    case editMessage
    case deleteMessage
    case pinMessage
    case forward
    case resend

    var title: String {
        switch self {
        case .reply:         return L(L10n.MessageAction.reply)
        case .copyText:      return L(L10n.MessageAction.copyText)
        case .editMessage:   return L(L10n.MessageAction.editMessage)
        case .deleteMessage: return L(L10n.MessageAction.deleteMessage)
        case .pinMessage:    return L(L10n.MessageAction.pinMessage)
        case .forward:       return L(L10n.MessageAction.forward)
        case .resend:        return "Resend"
        }
    }

    var iconName: String {
        switch self {
        case .reply:         return "arrowshape.turn.up.left"
        case .copyText:      return "doc.on.doc"
        case .editMessage:   return "pencil"
        case .deleteMessage: return "trash"
        case .pinMessage:    return "pin"
        case .forward:       return "arrowshape.turn.up.right"
        case .resend:        return "arrow.clockwise"
        }
    }

    var isDestructive: Bool {
        self == .deleteMessage
    }
}

final class MessageActionSheet: UIViewController {

    private let display: ChatMessageDisplay
    private let isOwnMessage: Bool
    private let onAction: (MessageAction) -> Void
    var onDismiss: (() -> Void)?

    private let containerView = UIView()
    private let handleView = UIView()
    private let stackView = UIStackView()
    private let dimmingView = UIView()

    init(display: ChatMessageDisplay, isOwnMessage: Bool, onAction: @escaping (MessageAction) -> Void) {
        self.display = display
        self.isOwnMessage = isOwnMessage
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let t = UIColor.theme

        // Dimming background — starts transparent
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingView.alpha = 0
        dimmingView.frame = view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmingView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissSheet))
        dimmingView.addGestureRecognizer(tap)

        // Container — starts offscreen
        containerView.backgroundColor = t.secondary
        containerView.layer.cornerRadius = 14
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Handle bar
        handleView.backgroundColor = t.textDisabled
        handleView.layer.cornerRadius = 2.5
        handleView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(handleView)

        // Actions stack
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            handleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            handleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 36),
            handleView.heightAnchor.constraint(equalToConstant: 5),

            stackView.topAnchor.constraint(equalTo: handleView.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        buildActions()

        // Start offscreen for animation
        containerView.transform = CGAffineTransform(translationX: 0, y: 400)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.dimmingView.alpha = 1
            self.containerView.transform = .identity
        }
    }

    private func animateDismiss(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingView.alpha = 0
            self.containerView.transform = CGAffineTransform(translationX: 0, y: 400)
        }) { _ in
            self.dismiss(animated: false) {
                self.onDismiss?()
                completion?()
            }
        }
    }

    private func buildActions() {
        let actions = availableActions()
        for action in actions {
            let row = makeActionRow(action)
            stackView.addArrangedSubview(row)
        }
    }

    private func availableActions() -> [MessageAction] {
        if display.isFailed {
            return [.resend, .deleteMessage]
        }

        var actions: [MessageAction] = []

        actions.append(.reply)

        let hasText = !display.parsedContent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            actions.append(.copyText)
        }

        if isOwnMessage {
            actions.append(.editMessage)
        }

        actions.append(.forward)
        actions.append(.pinMessage)

        if isOwnMessage {
            actions.append(.deleteMessage)
        }

        return actions
    }

    private func makeActionRow(_ action: MessageAction) -> UIView {
        let t = UIColor.theme
        let button = UIButton(type: .system)

        let textColor = action.isDestructive ? UIColor.systemRed : t.textStrong
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let icon = UIImage(systemName: action.iconName, withConfiguration: iconConfig)

        var config = UIButton.Configuration.plain()
        config.image = icon
        config.title = action.title
        config.baseForegroundColor = textColor
        config.imagePadding = 14
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var attr = attr
            attr.font = .systemFont(ofSize: 16, weight: .regular)
            return attr
        }
        config.imagePlacement = .leading
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.tag = MessageAction.allCases.firstIndex(of: action) ?? 0
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)

        return button
    }

    @objc private func actionTapped(_ sender: UIButton) {
        let action = MessageAction.allCases[sender.tag]
        animateDismiss { [onAction] in
            onAction(action)
        }
    }

    @objc private func dismissSheet() {
        animateDismiss()
    }
}
