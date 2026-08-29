import UIKit
import AsyncDisplayKit

enum ChannelNotificationType: Int32, CaseIterable {
    case useDefault     = 0
    case allMessages    = 1
    case mentionsOnly   = 2
    case nothing        = 3

    var title: String {
        switch self {
        case .useDefault:   return L(L10n.NotificationSettings.useDefault)
        case .allMessages:  return L(L10n.NotificationSettings.allMessages)
        case .mentionsOnly: return L(L10n.NotificationSettings.mentionsOnly)
        case .nothing:      return L(L10n.NotificationSettings.nothing)
        }
    }
}

final class NotificationSettingsSheetController: ViewController {

    private let channelId: Int64
    private let clanId: Int64
    private let context: AccountContext
    private var selectedType: ChannelNotificationType
    private let defaultLabel: String

    init(
        channelId: Int64,
        clanId: Int64,
        context: AccountContext,
        currentType: ChannelNotificationType,
        defaultLabel: String
    ) {
        self.channelId = channelId
        self.clanId = clanId
        self.context = context
        self.selectedType = currentType
        self.defaultLabel = defaultLabel
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    private var sheetNode: NotificationSettingsSheetNode {
        displayNode as! NotificationSettingsSheetNode
    }

    override func loadDisplayNode() {
        displayNode = NotificationSettingsSheetNode(
            selectedType: selectedType,
            defaultLabel: defaultLabel,
            onSelect: { [weak self] type in
                if #available(iOS 13.0, *) {
                    self?.handleSelection(type)
                }
            },
            onDismiss: { [weak self] in
                self?.dismissSheet()
            }
        )
        displayNodeDidLoad()
        setupSocketListener()
        if #available(iOS 13.0, *) {
            fetchSetting()
        }
    }
    
    private func setupSocketListener() {
        NotificationCenter.default.addObserver(forName: .mezonNotificationSettingDidUpdate, object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let updatedChannelId = userInfo["channelId"] as? Int64,
                  updatedChannelId == self.channelId,
                  let record = userInfo["record"] as? NotificationSettingRecord else { return }
            
            let typeInt = record.notificationSettingType
            if let newType = ChannelNotificationType(rawValue: typeInt), newType != self.selectedType {
                self.selectedType = newType
                self.sheetNode.updateSelection(newType)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        sheetNode.updateLayout(layout: layout, transition: transition)
    }

    func animateIn() {
        sheetNode.animateIn()
    }

    private func dismissSheet() {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
        }
    }
    
    @available(iOS 13.0, *)
    private func fetchSetting() {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let channelNotif = try await MezonHTTPClient.shared.getNotificationChannel(channelId: channelId, token: token)
                
                let record = NotificationSettingRecord(id: 0, entityId: channelId, scope: .channel, notificationSettingType: channelNotif.notificationSettingType, timeMuteSeconds: UInt32(bitPattern: channelNotif.timeMuteSeconds), active: channelNotif.active)
                context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }
                
                if let newType = ChannelNotificationType(rawValue: channelNotif.notificationSettingType), newType != self.selectedType {
                    self.selectedType = newType
                    self.sheetNode.updateSelection(newType)
                }
            } catch {
            }
        }
    }

    @available(iOS 13.0, *)
    private func handleSelection(_ type: ChannelNotificationType) {
        guard type != selectedType else {
            dismissSheet()
            return
        }

        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                if type == .useDefault {
                    try await MezonHTTPClient.shared.deleteNotificationChannel(
                        channelId: channelId,
                        token: token
                    )
                } else {
                    try await MezonHTTPClient.shared.setNotificationChannel(
                        channelId: channelId,
                        notificationType: type.rawValue,
                        clanId: clanId,
                        token: token
                    )
                }
                
                let record = NotificationSettingRecord(id: 0, entityId: channelId, scope: .channel, notificationSettingType: type.rawValue, timeMuteSeconds: 0, active: 1)
                context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }
                
                selectedType = type
                sheetNode.updateSelection(type)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.dismissSheet()
                }
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }
}

private final class NotificationSettingsSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {

    private let dimNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let group2Node = ASDisplayNode()
    private let separators: [ASDisplayNode] = [ASDisplayNode(), ASDisplayNode(), ASDisplayNode()]

    private var selectedType: ChannelNotificationType
    private let defaultLabel: String
    private let onSelect: (ChannelNotificationType) -> Void
    private let onDismiss: () -> Void

    private var optionRows: [ChannelNotificationType: NotificationOptionRow] = [:]
    private var panGesture: UIPanGestureRecognizer!
    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?

    init(
        selectedType: ChannelNotificationType,
        defaultLabel: String,
        onSelect: @escaping (ChannelNotificationType) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedType = selectedType
        self.defaultLabel = defaultLabel
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        super.init()
        automaticallyManagesSubnodes = false
        buildNodes()
    }

    private func buildNodes() {
        dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimNode.alpha = 0
        addSubnode(dimNode)

        containerNode.backgroundColor = UIColor.theme.primary
        containerNode.cornerRadius = 16
        containerNode.clipsToBounds = true
        addSubnode(containerNode)

        handleNode.backgroundColor = UIColor.theme.textDisabled
        handleNode.cornerRadius = 2.5
        containerNode.addSubnode(handleNode)

        group2Node.backgroundColor = UIColor.theme.secondary
        group2Node.cornerRadius = 16
        containerNode.addSubnode(group2Node)

        for sep in separators {
            sep.backgroundColor = UIColor.theme.border
            group2Node.addSubnode(sep)
        }

        let titleNode = ASTextNode()
        titleNode.attributedText = NSAttributedString(
            string: L(L10n.NotificationSettings.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.mezonTextStrong
            ]
        )
        containerNode.addSubnode(titleNode)
        self.titleNode = titleNode

        let types: [ChannelNotificationType] = [.useDefault, .allMessages, .mentionsOnly, .nothing]
        for type in types {
            let subtitle: String? = (type == .useDefault) ? defaultLabel : nil
            let row = NotificationOptionRow(
                type: type,
                subtitle: subtitle,
                isSelected: type == selectedType
            ) { [weak self] in
                self?.onSelect(type)
            }
            group2Node.addSubnode(row)
            optionRows[type] = row
        }
    }

    private var titleNode: ASTextNode?

    func updateSelection(_ type: ChannelNotificationType) {
        selectedType = type
        for (rowType, row) in optionRows {
            row.setSelected(rowType == type)
        }
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let width = layout.size.width
        let bottomInset = layout.intrinsicInsets.bottom

        dimNode.frame = CGRect(origin: .zero, size: layout.size)

        let handleH: CGFloat = 5
        let handleTop: CGFloat = 12
        let titleH: CGFloat = 44
        let rowH: CGFloat = 52
        let rowCount = CGFloat(optionRows.count)
        let bottomPad: CGFloat = 16 + bottomInset

        containerHeight = handleTop + handleH + 8 + titleH + (rowH * rowCount) + bottomPad

        let containerY = layout.size.height - containerHeight
        let containerFrame = CGRect(x: 0, y: containerY, width: width, height: containerHeight)
        transition.updateFrame(node: containerNode, frame: containerFrame)

        let handleWidth: CGFloat = 40
        handleNode.frame = CGRect(
            x: (width - handleWidth) / 2, y: handleTop,
            width: handleWidth, height: handleH
        )

        var y = handleTop + handleH + 8
        if let titleNode = titleNode {
            let titleSize = titleNode.calculateSizeThatFits(CGSize(width: width - 32, height: 44))
            titleNode.frame = CGRect(
                x: (width - titleSize.width) / 2, y: y + (titleH - titleSize.height) / 2,
                width: titleSize.width, height: titleSize.height
            )
        }
        y += titleH

        let groupW = width - 32
        let groupX: CGFloat = 16

        group2Node.frame = CGRect(x: groupX, y: y, width: groupW, height: rowH * 4)
        let group2Types: [ChannelNotificationType] = [.useDefault, .allMessages, .mentionsOnly, .nothing]
        for (i, type) in group2Types.enumerated() {
            if let row = optionRows[type] {
                row.frame = CGRect(x: 0, y: CGFloat(i) * rowH, width: groupW, height: rowH)
            }
            if i < 3 {
                separators[i].frame = CGRect(x: 0, y: CGFloat(i + 1) * rowH, width: groupW, height: 1.0 / UIScreen.main.scale)
            }
        }
        y += rowH * 4

        if panGesture == nil {
            panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.delegate = self
            containerNode.view.addGestureRecognizer(panGesture)

            let dimTap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
            dimNode.view.addGestureRecognizer(dimTap)
        }
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let containerY = layout.size.height - containerHeight
        containerNode.frame.origin.y = layout.size.height
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseOut) {
            self.dimNode.alpha = 1
            self.containerNode.frame.origin.y = containerY
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else { completion(); return }
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
            self.dimNode.alpha = 0
            self.containerNode.frame.origin.y = layout.size.height
        } completion: { _ in
            completion()
        }
    }

    @objc private func dimTapped() {
        onDismiss()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: containerNode.view)
        let restY = layout.size.height - containerHeight

        switch gesture.state {
        case .changed:
            let newY = max(restY, restY + translation.y)
            containerNode.frame.origin.y = newY
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: containerNode.view).y
            if translation.y > containerHeight * 0.3 || velocity > 500 {
                onDismiss()
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                    self.containerNode.frame.origin.y = restY
                }
            }
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

private final class NotificationOptionRow: ASDisplayNode {
    private let labelNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let radioNode = ASDisplayNode()
    private let radioInner = ASDisplayNode()
    private let action: () -> Void
    private let type: ChannelNotificationType
    private var isSelectedState: Bool

    init(type: ChannelNotificationType, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) {
        self.type = type
        self.action = action
        self.isSelectedState = isSelected
        super.init()
        automaticallyManagesSubnodes = false

        labelNode.attributedText = NSAttributedString(
            string: type.title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.mezonTextPrimary
            ]
        )
        addSubnode(labelNode)

        if let subtitle = subtitle, !subtitle.isEmpty {
            subtitleNode.attributedText = NSAttributedString(
                string: subtitle,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: UIColor.mezonTextMuted
                ]
            )
            addSubnode(subtitleNode)
        }

        radioNode.cornerRadius = 12
        radioNode.borderWidth = 2
        addSubnode(radioNode)

        radioInner.cornerRadius = 7
        radioNode.addSubnode(radioInner)

        updateRadioAppearance()
    }

    func setSelected(_ selected: Bool) {
        isSelectedState = selected
        updateRadioAppearance()
    }

    private func updateRadioAppearance() {
        let accentColor = UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.0) 
        if isSelectedState {
            radioNode.borderColor = accentColor.cgColor
            radioNode.backgroundColor = accentColor
            radioInner.backgroundColor = .white
            radioInner.isHidden = false
        } else {
            radioNode.borderColor = UIColor.theme.textStrong.withAlphaComponent(0.3).cgColor
            radioNode.backgroundColor = .clear
            radioInner.isHidden = true
        }
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        view.addGestureRecognizer(tap)
        view.isUserInteractionEnabled = true
    }

    @objc private func tapped() {
        action()
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let radioSize: CGFloat = 24
        let innerSize: CGFloat = 14
        let padding: CGFloat = 16

        radioNode.frame = CGRect(
            x: bounds.width - padding - radioSize,
            y: (bounds.height - radioSize) / 2,
            width: radioSize, height: radioSize
        )
        radioInner.frame = CGRect(
            x: (radioSize - innerSize) / 2,
            y: (radioSize - innerSize) / 2,
            width: innerSize, height: innerSize
        )

        let labelMaxW = bounds.width - padding * 2 - radioSize - 12
        let hasSubtitle = subtitleNode.supernode != nil

        if hasSubtitle {
            let labelSize = labelNode.calculateSizeThatFits(CGSize(width: labelMaxW, height: 24))
            let subSize = subtitleNode.calculateSizeThatFits(CGSize(width: labelMaxW, height: 20))
            let totalH = labelSize.height + 2 + subSize.height
            let startY = (bounds.height - totalH) / 2

            labelNode.frame = CGRect(x: padding, y: startY, width: labelSize.width, height: labelSize.height)
            subtitleNode.frame = CGRect(x: padding, y: startY + labelSize.height + 2, width: subSize.width, height: subSize.height)
        } else {
            let labelSize = labelNode.calculateSizeThatFits(CGSize(width: labelMaxW, height: 24))
            labelNode.frame = CGRect(x: padding, y: (bounds.height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height)
        }
    }
}
