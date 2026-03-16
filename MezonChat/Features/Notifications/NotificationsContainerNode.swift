import AsyncDisplayKit
import Combine
import UIKit

// MARK: - State

struct NotificationsState {
    var notifications: [Notifications]
    var isLoading: Bool
    var isLoadingMore: Bool

    static let empty = NotificationsState(notifications: [], isLoading: false, isLoadingMore: false)
}

// MARK: - Interaction

struct NotificationsInteraction {
    let onTabSelected: (Int32) -> Void  // passes the category tag
    let onLoadMore: () -> Void
}

// MARK: - NotificationItemCell

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
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .mezonTextPrimary
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
            // Avatar
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            // Time (anchored to trailing)
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Title
            titleLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),

            // Vertical accent line
            verticalLine.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            verticalLine.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -16),
            verticalLine.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            verticalLine.widthAnchor.constraint(equalToConstant: 2),

            // Body text
            contentLabel.topAnchor.constraint(equalTo: verticalLine.topAnchor),
            contentLabel.leadingAnchor.constraint(
                equalTo: verticalLine.trailingAnchor, constant: 8),
            contentLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -16),
            contentLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: separatorLine.topAnchor, constant: -16),

            // Separator Line
            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    func configure(with notification: Notifications) {
        titleLabel.text = notification.subject
        contentLabel.text = notification.content.isEmpty ? nil : notification.content

        // Avatar
        let avatarURLStr = notification.avatarURL
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
                notification.subject.first.map { String($0).uppercased() } ?? "N"
        }

        // Relative time
        let date = Date(timeIntervalSince1970: TimeInterval(notification.createTimeSeconds))
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
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarView.image = nil
        avatarPlaceholder.text = nil
    }
}

// MARK: - NotificationsContainerNode

@MainActor
final class NotificationsContainerNode: ASDisplayNode {

    // MARK: Private types

    private struct TabInfo {
        let title: String
        let tag: Int32
        let iconName: String
    }

    // MARK: UI

    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let tabScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var tabButtons: [UIButton] = []

    // MARK: Data

    private var state: NotificationsState = .empty
    private let disposables = DisposableSet()
    private let interaction: NotificationsInteraction

    private let tabs: [TabInfo] = [
        TabInfo(title: L(L10n.Notifications.mentions), tag: 1, iconName: "Notifications/mentions"),
        TabInfo(title: L(L10n.Notifications.messages), tag: 2, iconName: "Notifications/messages"),
        TabInfo(title: L(L10n.Notifications.forYou), tag: 3, iconName: "Notifications/forYou"),
    ]
    private var selectedTabIndex: Int = 0

    // MARK: Init

    init(signal: Signal<NotificationsState, NoError>, interaction: NotificationsInteraction) {
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.tableView.reloadData()
                let isEmpty = newState.notifications.isEmpty && !newState.isLoading
                self.emptyLabel.isHidden = !isEmpty
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

    // MARK: ASDisplayNode lifecycle

    override func didLoad() {
        super.didLoad()

        view.backgroundColor = .mezonBackground

        // Title label
        titleLabel.text = L(L10n.Notifications.title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        headerView.translatesAutoresizingMaskIntoConstraints = false

        // Tab scroll
        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.showsVerticalScrollIndicator = false
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabStackView.axis = .horizontal
        tabStackView.spacing = 8
        tabStackView.alignment = .center
        tabStackView.distribution = .fillProportionally
        tabStackView.translatesAutoresizingMaskIntoConstraints = false

        tabScrollView.addSubview(tabStackView)
        buildTabButtons()

        // Table view
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.register(
            NotificationItemCell.self, forCellReuseIdentifier: NotificationItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        // Empty label
        emptyLabel.text = "No notifications"
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .mezonTextSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        // Loading
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        view.addSubview(tabScrollView)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(loadingIndicator)
    }

    // MARK: Layout

    private var lastLayout: ContainerViewLayout?

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        lastLayout = layout
        applyLayout(transition: transition)
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }

        let safeTop: CGFloat
        let realSafeTop = view.safeAreaInsets.top
        safeTop = realSafeTop > 20 ? realSafeTop : max(layout.safeInsets.top, 54)

        let sideInset: CGFloat = 16
        let headerH: CGFloat = 56
        let tabH: CGFloat = 40
        let tabScrollY = safeTop + headerH + 8

        transition.updateFrame(
            view: headerView,
            frame: CGRect(x: 0, y: safeTop, width: layout.size.width, height: headerH))
        transition.updateFrame(
            view: titleLabel,
            frame: CGRect(
                x: sideInset, y: 0, width: layout.size.width - sideInset * 2, height: headerH))
        transition.updateFrame(
            view: tabScrollView,
            frame: CGRect(
                x: sideInset, y: tabScrollY, width: layout.size.width - sideInset * 2, height: tabH)
        )

        // tabStack fills scroll content
        let stackWidth = tabStackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            .width
        tabStackView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: max(stackWidth, layout.size.width - sideInset * 2), height: tabH))
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
        transition.updateFrame(
            view: emptyLabel,
            frame: CGRect(
                x: 0, y: (layout.size.height - 44) / 2, width: layout.size.width, height: 44))
    }

    override func layout() {
        super.layout()
        applyLayout(transition: .immediate)
    }

    // MARK: Bubble tabs

    private func buildTabButtons() {
        tabButtons.removeAll()
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tab) in tabs.enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = index

            var cfg = UIButton.Configuration.filled()
            cfg.cornerStyle = .capsule
            cfg.imagePadding = 6
            cfg.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: 14, bottom: 0, trailing: 14)
            cfg.attributedTitle = AttributedString(
                tab.title,
                attributes: AttributeContainer([
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
                ])
            )

            if let raw = UIImage(named: tab.iconName) {
                let iconSize = CGSize(width: 16, height: 16)
                let ratio = min(iconSize.width / raw.size.width, iconSize.height / raw.size.height)
                let drawSize = CGSize(
                    width: raw.size.width * ratio, height: raw.size.height * ratio)
                let origin = CGPoint(
                    x: (iconSize.width - drawSize.width) / 2,
                    y: (iconSize.height - drawSize.height) / 2)
                let renderer = UIGraphicsImageRenderer(size: iconSize)
                let resized = renderer.image { _ in
                    raw.draw(in: CGRect(origin: origin, size: drawSize))
                }
                cfg.image = resized.withRenderingMode(.alwaysOriginal)
            }

            btn.configuration = cfg
            // Fix height
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            btn.accessibilityIdentifier = "notif_tab_\(index)"
            tabStackView.addArrangedSubview(btn)
            tabButtons.append(btn)
        }
        updateTabStyles()
    }

    private func updateTabStyles() {
        for (i, btn) in tabButtons.enumerated() {
            let selected = i == selectedTabIndex

            var cfg = btn.configuration
            if selected {
                cfg?.baseBackgroundColor = .mezonLink
                cfg?.baseForegroundColor = .white
                cfg?.background.strokeWidth = 0
            } else {
                cfg?.baseBackgroundColor = .mezonPrimary
                cfg?.baseForegroundColor = .mezonChannelText
                cfg?.background.strokeColor = .mezonBorder
                cfg?.background.strokeWidth = 1
            }
            btn.configuration = cfg
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index != selectedTabIndex else { return }
        selectedTabIndex = index
        updateTabStyles()
        interaction.onTabSelected(tabs[index].tag)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension NotificationsContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.notifications.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell =
            tableView.dequeueReusableCell(
                withIdentifier: NotificationItemCell.reuseId, for: indexPath)
            as! NotificationItemCell
        cell.configure(with: state.notifications[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height

        if offsetY > 0 && offsetY > contentHeight - height - 50 {
            if !state.isLoading && !state.isLoadingMore && !state.notifications.isEmpty {
                interaction.onLoadMore()
            }
        }
    }
}
