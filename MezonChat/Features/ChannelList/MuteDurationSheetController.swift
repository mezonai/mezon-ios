import UIKit
import AsyncDisplayKit

enum MuteDuration: CaseIterable {
    case for15Minutes
    case for1Hour
    case for3Hours
    case for8Hours
    case for24Hours
    case untilTurnedOff

    var title: String {
        switch self {
        case .for15Minutes:  return L(L10n.MuteDuration.for15Minutes)
        case .for1Hour:      return L(L10n.MuteDuration.for1Hour)
        case .for3Hours:     return L(L10n.MuteDuration.for3Hours)
        case .for8Hours:     return L(L10n.MuteDuration.for8Hours)
        case .for24Hours:    return L(L10n.MuteDuration.for24Hours)
        case .untilTurnedOff: return L(L10n.MuteDuration.untilTurnedOff)
        }
    }

    var seconds: Int32 {
        switch self {
        case .for15Minutes:  return 15 * 60       
        case .for1Hour:      return 60 * 60       
        case .for3Hours:     return 3 * 60 * 60   
        case .for8Hours:     return 8 * 60 * 60  
        case .for24Hours:    return 24 * 60 * 60   
        case .untilTurnedOff: return -1            
        }
    }
}

final class MuteDurationViewController: ViewController {

    private let channelName: String
    private let channelId: Int64
    private let clanId: Int64
    private let context: AccountContext
    private let isThread: Bool
    private let isGroupDirectMessage: Bool
    private let onSelect: (MuteDuration) -> Void

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    init(
        channelName: String,
        channelId: Int64,
        clanId: Int64,
        context: AccountContext,
        isThread: Bool,
        isGroupDirectMessage: Bool = false,
        onSelect: @escaping (MuteDuration) -> Void
    ) {
        self.channelName = channelName
        self.channelId = channelId
        self.clanId = clanId
        self.context = context
        self.isThread = isThread
        self.isGroupDirectMessage = isGroupDirectMessage
        self.onSelect = onSelect
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ASDisplayNode()
        displayNode.backgroundColor = UIColor.mezonBackground
        displayNodeDidLoad()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private func buildUI() {
        let bg = UIColor.mezonBackground

        let headerBar = UIView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.backgroundColor = bg
        view.addSubview(headerBar)

        let backBtn = UIButton(type: .system)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.setImage(
            UIImage(systemName: "chevron.left")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal)
        backBtn.tintColor = .mezonTextStrong
        backBtn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        headerBar.addSubview(backBtn)

        let titleLbl = UILabel()
        titleLbl.text = muteTitle
        titleLbl.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLbl.textColor = .mezonTextStrong

        let subtitleLbl = UILabel()
        subtitleLbl.text = isGroupDirectMessage ? channelName : "#\(channelName)"
        subtitleLbl.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLbl.textColor = .mezonTextMuted
        subtitleLbl.lineBreakMode = .byTruncatingTail

        let titleStack = UIStackView(arrangedSubviews: [titleLbl, subtitleLbl])
        titleStack.axis = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleStack)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 56),

            backBtn.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 4),
            backBtn.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 44),
            backBtn.heightAnchor.constraint(equalToConstant: 44),

            titleStack.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 4),
            titleStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: headerBar.trailingAnchor, constant: -16),
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = bg
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let cellBg = UIColor.mezonSecondaryBackground
        let separatorColor = UIColor.theme.border

        for (index, duration) in MuteDuration.allCases.enumerated() {
            let row = makeOptionRow(title: duration.title, bgColor: cellBg) { [weak self] in
                self?.onSelect(duration)
                self?.navigationController?.popViewController(animated: true)
            }
            contentStack.addArrangedSubview(row)

            if index < MuteDuration.allCases.count - 1 {
                let sep = makeSeparator(color: separatorColor)
                contentStack.addArrangedSubview(sep)
            }
        }

        if !isGroupDirectMessage {
            let gap = UIView()
            gap.backgroundColor = bg
            gap.translatesAutoresizingMaskIntoConstraints = false
            gap.heightAnchor.constraint(equalToConstant: 16).isActive = true
            contentStack.addArrangedSubview(gap)

            let settingsRow = makeSettingsRow(
                title: L(L10n.MuteDuration.notificationSettings),
                bgColor: cellBg
            ) { [weak self] in
                self?.presentNotificationSettings()
            }
            contentStack.addArrangedSubview(settingsRow)

            let descWrapper = UIView()
            descWrapper.backgroundColor = bg
            descWrapper.translatesAutoresizingMaskIntoConstraints = false

            let descLabel = UILabel()
            descLabel.text = L(L10n.MuteDuration.description)
            descLabel.font = .systemFont(ofSize: 13, weight: .regular)
            descLabel.textColor = .mezonTextMuted
            descLabel.numberOfLines = 0
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descWrapper.addSubview(descLabel)

            NSLayoutConstraint.activate([
                descLabel.topAnchor.constraint(equalTo: descWrapper.topAnchor, constant: 12),
                descLabel.leadingAnchor.constraint(equalTo: descWrapper.leadingAnchor, constant: 16),
                descLabel.trailingAnchor.constraint(equalTo: descWrapper.trailingAnchor, constant: -16),
                descLabel.bottomAnchor.constraint(equalTo: descWrapper.bottomAnchor, constant: -12),
            ])
            contentStack.addArrangedSubview(descWrapper)
        }
    }

    private var muteTitle: String {
        if isGroupDirectMessage {
            return L(L10n.MuteDuration.titleConversation)
        }
        return isThread ? L(L10n.MuteDuration.titleThread) : L(L10n.MuteDuration.title)
    }

    private func makeOptionRow(title: String, bgColor: UIColor, action: @escaping () -> Void) -> UIView {
        let container = MuteTapView(action: action)
        container.backgroundColor = bgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .mezonTextPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func makeSettingsRow(title: String, bgColor: UIColor, action: @escaping () -> Void) -> UIView {
        let container = MuteTapView(action: action)
        container.backgroundColor = bgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .mezonTextPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let chevron = UIImageView()
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        chevron.tintColor = .mezonTextPrimary
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chevron)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),

            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
        ])

        return container
    }

    private func makeSeparator(color: UIColor) -> UIView {
        let line = UIView()
        line.backgroundColor = color
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return line
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func presentNotificationSettings() {
        let currentTypeInt = context.account.postbox.read { tx in
            tx.getNotificationSetting(entityId: self.channelId)?.notificationSettingType
        }
        let currentType: ChannelNotificationType
        if let typeInt = currentTypeInt, let type = ChannelNotificationType(rawValue: typeInt) {
            currentType = type
        } else {
            currentType = .useDefault
        }
        
        let sheet = NotificationSettingsSheetController(
            channelId: channelId,
            clanId: clanId,
            context: context,
            currentType: currentType,
            defaultLabel: L(L10n.NotificationSettings.allMessages)
        )
        if let window = self.view.window as? WindowHost {
            window.present(sheet, on: .root, blockInteraction: false, completion: {})
            sheet.animateIn()
        }
    }
}

private final class MuteTapView: UIView {
    private let action: () -> Void
    private var originalBg: UIColor?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() {
        originalBg = backgroundColor
        UIView.animate(withDuration: 0.08, animations: {
            self.backgroundColor = .mezonChannelSelected
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.backgroundColor = self.originalBg
            }
            self.action()
        })
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        originalBg = backgroundColor
        backgroundColor = .mezonChannelSelected
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.15) {
            self.backgroundColor = self.originalBg
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.15) {
            self.backgroundColor = self.originalBg
        }
    }
}
