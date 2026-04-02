import UIKit
import AsyncDisplayKit

enum MessageAction: CaseIterable {
    case giveACoffee
    case reply
    case forwardMessage
    case createThread
    case copyText
    case markUnread
    case topicDiscussion
    case pinMessage
    case markMessage
    case quickMenu
    case editMessage
    case deleteMessage
    case report
    case resend
    case forward

    var title: String {
        switch self {
        case .giveACoffee:      return L(L10n.MessageAction.giveACoffee)
        case .reply:            return L(L10n.MessageAction.reply)
        case .forwardMessage:   return L(L10n.MessageAction.forwardMessage)
        case .createThread:     return L(L10n.MessageAction.createThread)
        case .copyText:         return L(L10n.MessageAction.copyText)
        case .markUnread:       return L(L10n.MessageAction.markUnread)
        case .topicDiscussion:  return L(L10n.MessageAction.topicDiscussion)
        case .pinMessage:       return L(L10n.MessageAction.pinMessage)
        case .markMessage:      return L(L10n.MessageAction.markMessage)
        case .quickMenu:        return L(L10n.MessageAction.quickMenu)
        case .editMessage:      return L(L10n.MessageAction.editMessage)
        case .deleteMessage:    return L(L10n.MessageAction.deleteMessage)
        case .report:           return L(L10n.MessageAction.report)
        case .resend:           return "Resend"
        case .forward:          return L(L10n.MessageAction.forward)
        }
    }

    var iconImageName: String? {
        switch self {
        case .giveACoffee:      return "Chat/IconGift"
        case .reply:            return "Chat/IconArrowLeftUp"
        case .forwardMessage:   return "Chat/IconArrowRightUp"
        case .createThread:     return nil
        case .copyText:         return "Chat/IconCopy"
        case .markUnread:       return "Chat/IconMarkUnread"
        case .topicDiscussion:  return nil
        case .pinMessage:       return "Chat/IconPin"
        case .markMessage:      return "Chat/IconStar"
        case .quickMenu:        return nil
        case .editMessage:      return nil
        case .deleteMessage:    return "Chat/IconTrash"
        case .report:           return nil
        case .resend:           return nil
        case .forward:          return "Chat/IconArrowRightUp"
        }
    }

    var sfSymbolName: String? {
        switch self {
        case .createThread:     return "square.and.pencil"
        case .topicDiscussion:  return "text.bubble"
        case .quickMenu:       return "bolt.fill"
        case .editMessage:      return "pencil"
        case .report:           return "flag.fill"
        case .resend:           return "arrow.clockwise"
        default:                return nil
        }
    }

    var isDestructive: Bool {
        self == .deleteMessage || self == .report
    }

    enum Group {
        case frequent, normal, warning
    }

    var group: Group {
        switch self {
        case .giveACoffee, .reply, .forwardMessage, .createThread, .resend, .editMessage, .forward:
            return .frequent
        case .copyText, .markUnread, .topicDiscussion, .pinMessage, .markMessage, .quickMenu:
            return .normal
        case .deleteMessage, .report:
            return .warning
        }
    }
}

final class MessageActionSheetController: ViewController {

    private let display: ChatMessageDisplay
    private let isOwnMessage: Bool
    private let onAction: (MessageAction) -> Void
    var onDismiss: (() -> Void)?
    var onEmojiReaction: ((String, String) -> Void)?

    private var sheetNode: MessageActionSheetNode {
        return displayNode as! MessageActionSheetNode
    }

    init(display: ChatMessageDisplay, isOwnMessage: Bool, onAction: @escaping (MessageAction) -> Void) {
        self.display = display
        self.isOwnMessage = isOwnMessage
        self.onAction = onAction

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = .Hide
        self.blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let actions = Self.availableActions(display: display, isOwnMessage: isOwnMessage)
        self.displayNode = MessageActionSheetNode(
            messageActions: actions,
            onAction: { [weak self] action in
                guard let self else { return }
                let callback = self.onAction
                self.animateDismiss {
                    callback(action)
                }
            },
            onEmojiReaction: { [weak self] emojiId, shortname in
                guard let self else { return }
                let callback = self.onEmojiReaction
                self.animateDismiss {
                    callback?(emojiId, shortname)
                }
            },
            onDimTapped: { [weak self] in
                self?.animateDismiss(completion: nil)
            }
        )
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        sheetNode.updateLayout(layout: layout, transition: transition)
    }

    func animateIn() {
        sheetNode.animateIn()
    }

    private func animateDismiss(completion: (() -> Void)?) {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            self?.onDismiss?()
            completion?()
        }
    }


    private static func availableActions(display: ChatMessageDisplay, isOwnMessage: Bool) -> [MessageAction] {
        if display.isFailed {
            return [.resend, .deleteMessage]
        }

        var actions: [MessageAction] = []

        if !isOwnMessage {
            actions.append(.giveACoffee)
        }

        actions.append(.reply)

        let hasText = !display.parsedContent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        actions.append(.forwardMessage)
        actions.append(.createThread)

        if hasText {
            actions.append(.copyText)
        }

        actions.append(.markUnread)
        actions.append(.topicDiscussion)
        actions.append(.pinMessage)
        actions.append(.markMessage)
        actions.append(.quickMenu)

        if isOwnMessage {
            actions.append(.deleteMessage)
        }

        if !isOwnMessage {
            actions.append(.report)
        }

        return actions
    }
}

private final class MessageActionSheetNode: ASDisplayNode, UIGestureRecognizerDelegate, UIScrollViewDelegate {

    private let dimmingNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private let handleNode: ASDisplayNode
    private let scrollView = UIScrollView()

    private let messageActions: [MessageAction]
    private let onAction: (MessageAction) -> Void
    private let onEmojiReaction: (String, String) -> Void
    private let onDimTapped: () -> Void

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var didBuildContent = false

    private var panGesture: UIPanGestureRecognizer!
    private var panStartY: CGFloat = 0
    private var isDraggingSheet = false
    private let padH: CGFloat = 10
    private let rowH: CGFloat = 48
    private let emojiRowH: CGFloat = 52
    private let groupSpacing: CGFloat = 10
    private let groupCorner: CGFloat = 10
    private let handleH: CGFloat = 25
    private let iconSize: CGFloat = 24

    private static let emojiData: [(id: String, shortname: String)] = [
        ("7227274405304181951", ":100:"),
        ("7227274405302432668", ":joy:"),
        ("7227274405303613492", ":like:"),
        ("7227274405305046042", ":laughing:"),
        ("7227274405301971870", ":innocent:"),
    ]

    init(
        messageActions: [MessageAction],
        onAction: @escaping (MessageAction) -> Void,
        onEmojiReaction: @escaping (String, String) -> Void,
        onDimTapped: @escaping () -> Void
    ) {
        self.messageActions = messageActions
        self.onAction = onAction
        self.onEmojiReaction = onEmojiReaction
        self.onDimTapped = onDimTapped

        self.dimmingNode = ASDisplayNode()
        self.containerNode = ASDisplayNode()
        self.handleNode = ASDisplayNode()

        super.init()

        self.dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        self.dimmingNode.alpha = 0

        let t = UIColor.theme
        self.containerNode.backgroundColor = t.primary
        self.containerNode.cornerRadius = 14
        self.containerNode.clipsToBounds = true

        self.handleNode.backgroundColor = t.textDisabled
        self.handleNode.cornerRadius = 2.5

        self.addSubnode(dimmingNode)
        self.addSubnode(containerNode)
        self.containerNode.addSubnode(handleNode)
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        scrollView.delaysContentTouches = false
        containerNode.view.addSubview(scrollView)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
        scrollView.panGestureRecognizer.require(toFail: panGesture)
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            panStartY = containerNode.frame.origin.y
            isDraggingSheet = true

        case .changed:
            let offsetY = max(0, translation.y)
            containerNode.frame.origin.y = panStartY + offsetY
            dimmingNode.alpha = 1 - offsetY / containerHeight

        case .ended, .cancelled:
            isDraggingSheet = false
            if translation.y > containerHeight * 0.3 || velocity.y > 500 {
                onDimTapped()
            } else {
                let targetY = layout.size.height - containerHeight
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
                    self.containerNode.frame.origin.y = targetY
                    self.dimmingNode.alpha = 1
                }
            }

        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        let vel = panGesture.velocity(in: view)
        return scrollView.contentOffset.y <= 0 && vel.y > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeBottom = layout.intrinsicInsets.bottom

        transition.updateFrame(node: dimmingNode, frame: bounds)

        let screenW = layout.size.width

        let frequent = messageActions.filter { $0.group == .frequent }
        let normal = messageActions.filter { $0.group == .normal }
        let warning = messageActions.filter { $0.group == .warning }

        var totalContentH: CGFloat = emojiRowH + groupSpacing
        if !frequent.isEmpty { totalContentH += CGFloat(frequent.count) * rowH + groupSpacing }
        if !normal.isEmpty { totalContentH += CGFloat(normal.count) * rowH + groupSpacing }
        if !warning.isEmpty { totalContentH += CGFloat(warning.count) * rowH + groupSpacing }
        totalContentH += 10

        let maxScrollH = layout.size.height * 0.7 - handleH - safeBottom
        let scrollH = min(totalContentH, maxScrollH)
        containerHeight = handleH + scrollH + safeBottom + 8

        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))

        scrollView.frame = CGRect(x: 0, y: handleH, width: screenW, height: scrollH)
        scrollView.contentSize = CGSize(width: screenW, height: totalContentH)
        scrollView.alwaysBounceVertical = totalContentH > scrollH

        if !didBuildContent {
            didBuildContent = true
            buildContent(screenW: screenW)
        }
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight

        containerNode.frame.origin.y = fromY
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame.origin.y = toY
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else {
            completion()
            return
        }
        let bottomY = layout.size.height
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame.origin.y = bottomY
        }) { _ in
            completion()
        }
    }

    private func buildContent(screenW: CGFloat) {
        let contentW = screenW - padH * 2
        var y: CGFloat = 0

        buildEmojiRow(at: y, screenW: screenW)
        y += emojiRowH + groupSpacing

        let frequent = messageActions.filter { $0.group == .frequent }
        let normal = messageActions.filter { $0.group == .normal }
        let warning = messageActions.filter { $0.group == .warning }

        if !frequent.isEmpty {
            buildActionGroup(frequent, at: y, contentW: contentW, isWarning: false)
            y += CGFloat(frequent.count) * rowH + groupSpacing
        }
        if !normal.isEmpty {
            buildActionGroup(normal, at: y, contentW: contentW, isWarning: false)
            y += CGFloat(normal.count) * rowH + groupSpacing
        }
        if !warning.isEmpty {
            buildActionGroup(warning, at: y, contentW: contentW, isWarning: true)
        }
    }

    private func buildEmojiRow(at y: CGFloat, screenW: CGFloat) {
        let t = UIColor.theme
        let btnSize: CGFloat = 44
        let contentW = screenW - padH * 2
        let totalButtons = Self.emojiData.count + 1
        let spacing = (contentW - CGFloat(totalButtons) * btnSize) / CGFloat(totalButtons - 1)
        var x = padH

        for (idx, emoji) in Self.emojiData.enumerated() {
            let btn = UIButton(type: .custom)
            btn.frame = CGRect(x: x, y: y + (emojiRowH - btnSize) / 2, width: btnSize, height: btnSize)
            btn.backgroundColor = t.secondary
            btn.layer.cornerRadius = btnSize / 2
            btn.clipsToBounds = true
            btn.tag = idx

            if let url = MezonConfig.emojiResourceURL(emojiId: emoji.id, imgproxyFitSide: 40) {
                loadEmojiImage(url: url, into: btn)
            }

            btn.addTarget(self, action: #selector(emojiTapped(_:)), for: .touchUpInside)
            scrollView.addSubview(btn)
            x += btnSize + spacing
        }

        let pickerBtn = UIButton(type: .system)
        pickerBtn.frame = CGRect(x: contentW + padH - btnSize, y: y + (emojiRowH - btnSize) / 2, width: btnSize, height: btnSize)
        pickerBtn.backgroundColor = t.secondary
        pickerBtn.layer.cornerRadius = btnSize / 2
        pickerBtn.clipsToBounds = true
        let smileyConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        pickerBtn.setImage(UIImage(systemName: "smiley", withConfiguration: smileyConfig), for: .normal)
        pickerBtn.tintColor = t.textStrong
        scrollView.addSubview(pickerBtn)
    }

    @objc private func emojiTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx < Self.emojiData.count else { return }
        let emoji = Self.emojiData[idx]
        onEmojiReaction(emoji.id, emoji.shortname)
    }

    private func loadEmojiImage(url: URL, into button: UIButton) {
        let key = url.absoluteString
        if let cached = ImageCache.shared.image(forKey: key) {
            button.setImage(resizedEmoji(cached), for: .normal)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak button, weak self] data, _, _ in
            guard let data, !data.isEmpty, let self else { return }
            let animated = UIImage.animatedImage(from: data)
            guard let img = animated ?? UIImage.decodeImage(from: data) else { return }
            ImageCache.shared.setImage(img, data: data, forKey: key)
            DispatchQueue.main.async {
                button?.setImage(self.resizedEmoji(img), for: .normal)
            }
        }.resume()
    }

    private func resizedEmoji(_ img: UIImage) -> UIImage {
        let sz = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: sz).image { _ in
            img.draw(in: CGRect(origin: .zero, size: sz))
        }
    }

    private func buildActionGroup(_ actions: [MessageAction], at y: CGFloat, contentW: CGFloat, isWarning: Bool) {
        let t = UIColor.theme
        let groupH = CGFloat(actions.count) * rowH

        let bg = UIView(frame: CGRect(x: padH, y: y, width: contentW, height: groupH))
        bg.backgroundColor = t.secondary
        bg.layer.cornerRadius = groupCorner
        bg.clipsToBounds = true
        scrollView.addSubview(bg)

        for (i, action) in actions.enumerated() {
            let rowY = CGFloat(i) * rowH
            buildActionRow(action, in: bg, at: rowY, width: contentW, height: rowH, isWarning: isWarning)

            if i < actions.count - 1 {
                let sepX: CGFloat = isWarning ? 58 : 52
                let sep = UIView(frame: CGRect(x: sepX, y: rowY + rowH - 0.5, width: contentW - sepX - 16, height: 0.5))
                sep.backgroundColor = t.tertiary
                bg.addSubview(sep)
            }
        }
    }

    private func buildActionRow(_ action: MessageAction, in parent: UIView, at y: CGFloat, width: CGFloat, height: CGFloat, isWarning: Bool = false) {
        let t = UIColor.theme
        let textColor = action.isDestructive ? UIColor.systemRed : t.textStrong
        let iconTint = action.isDestructive ? UIColor.systemRed : t.textStrong

        var iconImage: UIImage?
        if let assetName = action.iconImageName {
            iconImage = UIImage(named: assetName)?.withRenderingMode(.alwaysTemplate)
        } else if let sfName = action.sfSymbolName {
            let config = UIImage.SymbolConfiguration(pointSize: isWarning ? 14 : 20, weight: .medium)
            iconImage = UIImage(systemName: sfName, withConfiguration: config)
        }

        var labelX: CGFloat

        if isWarning {

            let circleSize: CGFloat = 32
            let circleX: CGFloat = 12
            let circleY = y + (height - circleSize) / 2
            let circleView = UIView(frame: CGRect(x: circleX, y: circleY, width: circleSize, height: circleSize))
            circleView.backgroundColor = t.tertiary
            circleView.layer.cornerRadius = circleSize / 2
            circleView.clipsToBounds = true
            parent.addSubview(circleView)

            let innerIconSize: CGFloat = 16
            let iconView = UIImageView(frame: CGRect(
                x: (circleSize - innerIconSize) / 2,
                y: (circleSize - innerIconSize) / 2,
                width: innerIconSize,
                height: innerIconSize
            ))
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = iconTint
            iconView.image = iconImage
            circleView.addSubview(iconView)

            labelX = circleX + circleSize + 10
        } else {
            let iconX: CGFloat = 16
            let iconView = UIImageView(frame: CGRect(x: iconX, y: y + (height - iconSize) / 2, width: iconSize, height: iconSize))
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = iconTint
            iconView.image = iconImage
            parent.addSubview(iconView)

            labelX = iconX + iconSize + 12
        }

        let label = UILabel(frame: CGRect(x: labelX, y: y, width: width - labelX - 16, height: height))
        label.text = action.title
        label.font = .systemFont(ofSize: 16)
        label.textColor = textColor
        parent.addSubview(label)

        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: 0, y: y, width: width, height: height)
        btn.addAction(UIAction { [weak self] _ in
            self?.onAction(action)
        }, for: .touchUpInside)
        parent.addSubview(btn)
    }
}
