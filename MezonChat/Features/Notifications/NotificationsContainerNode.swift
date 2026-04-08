import AsyncDisplayKit
import Combine
import UIKit


private struct TopicContent: Decodable {
    let t: String?
}

enum NotificationItem {
    case notification(NotificationRecord)
    case topic(TopicRecord)

    var id: Int64 {
        switch self {
        case .notification(let n): return n.id
        case .topic(let t): return t.id
        }
    }

    var subject: String {
        switch self {
        case .notification(let n): return n.subject
        case .topic(let t):
            if let decoded: TopicContent = safeJsonDecode(t.content, to: TopicContent.self),
                let text = decoded.t
            {
                return L(L10n.Notifications.repliedTo) + text
            }
            return L(L10n.Notifications.repliedTo) + t.content
        }
    }

    var content: String {
        switch self {
        case .notification(let n): return n.content
        case .topic(let t):

            let msgText: String
            if let decoded: TopicContent = safeJsonDecode(
                t.lastSentMessageContent, to: TopicContent.self),
                let text = decoded.t, !text.isEmpty
            {
                msgText = text
            } else if !t.lastSentMessageContent.isEmpty && t.lastSentMessageContent != "{}" {
                msgText = t.lastSentMessageContent
            } else {
                msgText = L(L10n.Notifications.unreachableMessage)
            }

            let line = L(L10n.Notifications.sender) + msgText

            return line
        }
    }

    var avatarURL: String {
        switch self {
        case .notification(let n): return n.avatarURL
        case .topic(let t): return "default"
        }
    }

    var createTimeSeconds: UInt32 {
        switch self {
        case .notification(let n): return n.createTimeSeconds
        case .topic(let t): return t.updateTimeSeconds
        }
    }
}

struct NotificationsState {
    let items: [NotificationItem]
    let isLoading: Bool
    let isLoadingMore: Bool

    static let empty = NotificationsState(items: [], isLoading: false, isLoadingMore: false)
}


struct NotificationsInteraction {
    let onTabSelected: (Int32) -> Void
    let onLoadMore: () -> Void
    let onItemSelected: (NotificationItem) -> Void
}


final class NotificationItemCell: UITableViewCell {

    static let reuseId = "NotificationItemCell"

    private let avatarSize: CGFloat = 36

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .colorAvatarDefault
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = .mezonChannelText
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = .mezonTextMuted
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let verticalLine: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonBorder
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let separatorLine: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonBorder
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        contentView.addSubview(titleLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(contentLabel)
        contentView.addSubview(verticalLine)
        contentView.addSubview(separatorLine)

        NSLayoutConstraint.activate([

            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),


            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),


            titleLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            titleLabel.widthAnchor.constraint(
                lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),


            verticalLine.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            verticalLine.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -16),
            verticalLine.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            verticalLine.widthAnchor.constraint(equalToConstant: 2),


            contentLabel.topAnchor.constraint(equalTo: verticalLine.topAnchor),
            contentLabel.leadingAnchor.constraint(
                equalTo: verticalLine.trailingAnchor, constant: 8),
            contentLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            contentLabel.widthAnchor.constraint(
                lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),
            contentLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: separatorLine.topAnchor, constant: -16),


            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    func configure(with item: NotificationItem) {
        titleLabel.text = item.subject
        contentLabel.text = item.content.isEmpty ? nil : item.content


        let avatarURLStr = item.avatarURL
        imageTask?.cancel()
        if !avatarURLStr.isEmpty, let url = URL(string: avatarURLStr) {
            avatarPlaceholder.isHidden = true
            avatarView.image = nil
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.avatarView.image = img }
            }
            imageTask?.resume()
        } else {
            avatarView.image = nil
            avatarPlaceholder.isHidden = false
            avatarPlaceholder.text =
                item.subject.first.map { String($0).uppercased() } ?? "N"
        }


        let date = Date(timeIntervalSince1970: TimeInterval(item.createTimeSeconds))
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 {
            timeLabel.text = "Just now"
        } else if diff < 3600 {
            timeLabel.text = "\(diff / 60)m"
        } else if diff < 86400 {
            timeLabel.text = "\(diff / 3600)h"
        } else {
            timeLabel.text = "\(diff / 86400)d"
        }


        let t = UIColor.theme
        titleLabel.textColor = t.textStrong
        contentLabel.textColor = t.text
        timeLabel.textColor = t.textDisabled
        verticalLine.backgroundColor = t.border
        separatorLine.backgroundColor = t.borderDim
        avatarView.backgroundColor = t.primary
        avatarPlaceholder.textColor = t.text
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarView.image = nil
        avatarPlaceholder.text = nil
    }
}


@MainActor
final class NotificationsContainerNode: ASDisplayNode {


    private struct TabInfo {
        let title: String
        let tag: Int32
        let iconName: String
    }


    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let addFriendButton = UIButton(type: .system)
    private let tabScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0, y: 0)
        gl.endPoint = CGPoint(x: 1, y: 1)
        gl.locations = [0.2, 0.4, 0.7, 0.9] as [NSNumber]
        return gl
    }()


    private let emptyStateStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isHidden = true
        return sv
    }()
    private let emptyImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let emptyTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let emptyDescLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.textColor = .mezonTextSecondary
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var tabButtons: [UIButton] = []


    private var state: NotificationsState = .empty
    private let disposables = DisposableSet()
    private let interaction: NotificationsInteraction

    private let tabs: [TabInfo] = [
        TabInfo(title: L(L10n.Notifications.mentions), tag: 1, iconName: "Notifications/mentions"),
        TabInfo(title: L(L10n.Notifications.messages), tag: 2, iconName: "Notifications/messages"),
        TabInfo(title: L(L10n.Notifications.topic), tag: 4, iconName: "Notifications/topic"),
        TabInfo(title: L(L10n.Notifications.forYou), tag: 3, iconName: "Notifications/forYou"),
    ]
    private var selectedTabIndex: Int = 0


    init(signal: Signal<NotificationsState, NoError>, interaction: NotificationsInteraction) {
        self.interaction = interaction
        super.init()
        backgroundColor = .clear

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.tableView.reloadData()
                let isEmpty = newState.items.isEmpty && !newState.isLoading
                self.emptyStateStack.isHidden = !isEmpty
                if newState.isLoading {
                    self.loadingIndicator.startAnimating()
                } else {
                    self.loadingIndicator.stopAnimating()
                }

                if newState.isLoadingMore {
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    spinner.frame = CGRect(
                        x: 0, y: 0, width: self.tableView.bounds.width, height: 44)
                    self.tableView.tableFooterView = spinner
                } else {
                    self.tableView.tableFooterView = nil
                }
            })
        )
    }

    deinit { disposables.dispose() }


    override func didLoad() {
        super.didLoad()

        layer.insertSublayer(gradientLayer, at: 0)


        titleLabel.text = L(L10n.Notifications.title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary


        addFriendButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        addFriendButton.layer.cornerRadius = 18
        addFriendButton.clipsToBounds = true
        addFriendButton.layer.borderColor = UIColor.mezonBorder.cgColor
        addFriendButton.layer.borderWidth = 1.5
        addFriendButton.tintColor = .mezonTextPrimary
        if let raw = UIImage(named: "Notifications/addfriend")?.withRenderingMode(.alwaysOriginal) {
            let iconSize = CGSize(width: 20, height: 20)
            let ratio = min(iconSize.width / raw.size.width, iconSize.height / raw.size.height)
            let drawSize = CGSize(width: raw.size.width * ratio, height: raw.size.height * ratio)
            let origin = CGPoint(
                x: (iconSize.width - drawSize.width) / 2,
                y: (iconSize.height - drawSize.height) / 2)
            let renderer = UIGraphicsImageRenderer(size: iconSize)
            let resized = renderer.image { _ in
                raw.draw(in: CGRect(origin: origin, size: drawSize))
            }
            addFriendButton.setImage(resized.withRenderingMode(.alwaysTemplate), for: .normal)
        }
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)
        addFriendButton.accessibilityIdentifier = "notif_add_friend"


        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.showsVerticalScrollIndicator = false

        tabStackView.axis = .horizontal
        tabStackView.spacing = 8
        tabStackView.alignment = .center
        tabStackView.distribution = .fill

        tabScrollView.addSubview(tabStackView)
        buildTabButtons()


        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.register(
            NotificationItemCell.self, forCellReuseIdentifier: NotificationItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self


        emptyImageView.image = UIImage(named: "Notifications/emptyNotifications")
        emptyImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            emptyImageView.widthAnchor.constraint(equalToConstant: 300),
            emptyImageView.heightAnchor.constraint(equalToConstant: 300),
        ])
        emptyTitleLabel.text = L(L10n.Notifications.emptyTitle)
        emptyDescLabel.text = L(L10n.Notifications.emptyDescription)

        emptyStateStack.addArrangedSubview(emptyTitleLabel)
        emptyStateStack.addArrangedSubview(emptyDescLabel)
        emptyStateStack.addArrangedSubview(emptyImageView)


        loadingIndicator.hidesWhenStopped = true

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(addFriendButton)
        view.addSubview(tabScrollView)
        view.addSubview(tableView)
        view.addSubview(emptyStateStack)
        view.addSubview(loadingIndicator)


        NSLayoutConstraint.activate([
            emptyStateStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),
            emptyStateStack.widthAnchor.constraint(
                equalTo: view.widthAnchor, multiplier: 0.7),
        ])

        applyTheme()
    }


    private var lastLayout: ContainerViewLayout?

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        lastLayout = layout
        applyLayout(transition: transition)
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }

        if layer.maskedCorners != [.layerMinXMinYCorner] {
            layer.cornerRadius = 20.swh
            layer.maskedCorners = [.layerMinXMinYCorner]
            clipsToBounds = true
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()

        let safeTop: CGFloat
        let realSafeTop = view.safeAreaInsets.top
        safeTop = realSafeTop > 20 ? realSafeTop : max(layout.safeInsets.top, 54)

        let sideInset: CGFloat = 16
        let btnSize: CGFloat = 32
        let headerH: CGFloat = 44
        let tabH: CGFloat = 40
        let tabScrollY = safeTop + headerH + 4

        transition.updateFrame(
            view: headerView,
            frame: CGRect(x: 0, y: safeTop, width: layout.size.width, height: headerH))
        transition.updateFrame(
            view: titleLabel,
            frame: CGRect(
                x: sideInset, y: 0,
                width: layout.size.width - sideInset * 2 - btnSize - 8, height: headerH))
        transition.updateFrame(
            view: addFriendButton,
            frame: CGRect(
                x: layout.size.width - sideInset - btnSize,
                y: (headerH - btnSize) / 2,
                width: btnSize, height: btnSize))
        transition.updateFrame(
            view: tabScrollView,
            frame: CGRect(
                x: sideInset, y: tabScrollY, width: layout.size.width - sideInset * 2, height: tabH)
        )
        let stackWidth = tabStackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            .width
        tabStackView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: stackWidth, height: tabH))
        tabScrollView.contentSize = tabStackView.frame.size

        let tvTop = tabScrollY + tabH + 12
        let tvHeight = layout.size.height - tvTop - layout.intrinsicInsets.bottom
        transition.updateFrame(
            view: tableView,
            frame: CGRect(x: 0, y: tvTop, width: layout.size.width, height: max(0, tvHeight)))

        let liS: CGFloat = 24
        transition.updateFrame(
            view: loadingIndicator,
            frame: CGRect(
                x: (layout.size.width - liS) / 2, y: (layout.size.height - liS) / 2, width: liS,
                height: liS))
    }

    override func layout() {
        super.layout()
        applyLayout(transition: .immediate)
    }


    private func buildTabButtons() {
        tabButtons.removeAll()
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tab) in tabs.enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = index

            btn.layer.cornerRadius = 8
            btn.clipsToBounds = true
            btn.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 6, right: 10)
            btn.setAttributedTitle(
                NSAttributedString(string: tab.title, attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium)
                ]),
                for: .normal
            )

            if let raw = UIImage(named: tab.iconName) {
                let iconSize = CGSize(width: 16, height: 18)
                let ratio = min(16 / raw.size.width, 16 / raw.size.height)
                let drawSize = CGSize(
                    width: raw.size.width * ratio, height: raw.size.height * ratio)
                let origin = CGPoint(
                    x: (iconSize.width - drawSize.width) / 2,
                    y: 0)
                let renderer = UIGraphicsImageRenderer(size: iconSize)
                let resized = renderer.image { _ in
                    raw.draw(in: CGRect(origin: origin, size: drawSize))
                }
                btn.setImage(resized.withRenderingMode(.alwaysOriginal), for: .normal)
            }
            btn.clipsToBounds = false
            btn.layer.masksToBounds = false
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            btn.accessibilityIdentifier = "notif_tab_\(index)"
            tabStackView.addArrangedSubview(btn)
            tabButtons.append(btn)
        }
        updateTabStyles()
    }

    private func updateTabStyles() {
        let t = UIColor.theme
        for (i, btn) in tabButtons.enumerated() {
            let selected = i == selectedTabIndex

            if selected {
                btn.backgroundColor = t.bgViolet
                btn.tintColor = t.channelUnread
                btn.setTitleColor(t.channelUnread, for: .normal)
                btn.layer.borderWidth = 0
            } else {
                btn.backgroundColor = t.secondaryLight
                btn.tintColor = t.textDisabled
                btn.setTitleColor(t.textDisabled, for: .normal)
                btn.layer.borderColor = t.borderDim.cgColor
                btn.layer.borderWidth = 1
            }
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index != selectedTabIndex else { return }
        selectedTabIndex = index
        updateTabStyles()
        interaction.onTabSelected(tabs[index].tag)
    }

    @objc private func addFriendTapped() {

    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [
            t.primaryGradient.cgColor,
            t.secondary.cgColor,
            t.secondary.cgColor,
            t.primaryGradient.cgColor,
        ]
        backgroundColor = .clear
        tableView.backgroundColor = .clear
        headerView.backgroundColor = .clear
        tabScrollView.backgroundColor = .clear

        titleLabel.textColor = t.textStrong
        addFriendButton.tintColor = t.textStrong
        addFriendButton.layer.borderColor = t.border.cgColor

        emptyTitleLabel.textColor = t.textStrong
        emptyDescLabel.textColor = t.textDisabled

        updateTabStyles()
        tableView.reloadData()
    }
}


extension NotificationsContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell =
            tableView.dequeueReusableCell(
                withIdentifier: NotificationItemCell.reuseId, for: indexPath)
            as! NotificationItemCell
        cell.configure(with: state.items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        interaction.onItemSelected(state.items[indexPath.row])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height

        if offsetY > 0 && offsetY > contentHeight - height - 50 {
            if !state.isLoading && !state.isLoadingMore && !state.items.isEmpty {
                interaction.onLoadMore()
            }
        }
    }
}
