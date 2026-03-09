import Combine
import UIKit

private struct NotificationTab {
    let title: String
    let tag: Int
}

final class NotificationViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: NotificationsViewModel
    private let sharedContext: SharedAccountContext

    private var selectedTabIndex: Int = 1

    private let tabs: [NotificationTab] = [
        NotificationTab(title: L(L10n.Notifications.mentions), tag: 1),
        NotificationTab(title: L(L10n.Notifications.messages), tag: 2),
        NotificationTab(title: L(L10n.Notifications.forYou), tag: 3),
    ]

    // MARK: - UI Components

    private lazy var headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 28, weight: .bold)
        l.textColor = .mezonTextPrimary
        l.text = L(L10n.Notifications.title)
        return l
    }()

    /// Horizontal scroll container for bubble tab buttons
    private lazy var tabScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    /// Horizontal stack that holds the bubble tab buttons
    private lazy var tabStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        s.distribution = .fillProportionally
        return s
    }()

    /// Array of bubble tab buttons, built from `tabs`
    private var tabButtons: [UIButton] = []

    /// Main scroll view for notification content
    private lazy var contentScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 0
        s.alignment = .fill
        s.isLayoutMarginsRelativeArrangement = true
        s.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 24, right: 20)
        return s
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15)
        l.textColor = .mezonTextSecondary
        l.textAlignment = .center
        l.text = "No notifications"
        l.isHidden = false
        return l
    }()

    private var headerTopConstraint: NSLayoutConstraint?

    // MARK: - Init

    init(viewModel: NotificationsViewModel, sharedContext: SharedAccountContext) {
        self.viewModel = viewModel
        self.sharedContext = sharedContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let top = view.safeAreaInsets.top
        let statusBarOnly = min(top, 59)
        headerTopConstraint?.constant = statusBarOnly
    }

    // MARK: - BaseViewController Overrides

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let categoryTag = tabs[selectedTabIndex].tag
        Task { await viewModel.fetchNotifications(category: Int32(categoryTag)) }
    }

    override func setupUI() {
        view.backgroundColor = .mezonBackground

        // ── Header ──────────────────────────────────────────────
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)

        headerTopConstraint = headerView.topAnchor.constraint(
            equalTo: view.topAnchor, constant: 59
        )
        NSLayoutConstraint.activate([
            headerTopConstraint!,
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        // ── Bubble Tabs ──────────────────────────────────────────
        view.addSubview(tabScrollView)
        tabScrollView.addSubview(tabStack)

        NSLayoutConstraint.activate([
            tabScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            tabScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tabScrollView.heightAnchor.constraint(equalToConstant: 40),

            tabStack.topAnchor.constraint(equalTo: tabScrollView.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: tabScrollView.bottomAnchor),
            tabStack.leadingAnchor.constraint(
                equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStack.trailingAnchor.constraint(
                equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabScrollView.heightAnchor),
        ])

        buildTabButtons()

        // ── Content ──────────────────────────────────────────────
        view.addSubview(contentScrollView)
        contentScrollView.addSubview(contentStack)
        contentScrollView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(
                equalTo: tabScrollView.bottomAnchor, constant: 12),
            contentScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(
                equalTo: contentScrollView.frameLayoutGuide.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: contentScrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentScrollView.centerYAnchor),
        ])

        selectTab(at: 0)
    }

    override func setupBindings() {
        viewModel.$notifications
            .receive(on: RunLoop.main)
            .sink { [weak self] notifications in
                self?.emptyLabel.isHidden = !notifications.isEmpty
                self?.renderNotifications(notifications)
            }
            .store(in: &cancellables)
    }

    private func renderNotifications(_ notifications: [Notifications]) {
        // Clear stack
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for notif in notifications {
            let itemView = NotificationItemView()
            itemView.configure(with: notif)
            contentStack.addArrangedSubview(itemView)
        }
    }

    override func applyTheme() {
        view.backgroundColor = .mezonBackground
        titleLabel.textColor = .mezonTextPrimary
        updateTabStyles()
    }

    // MARK: - Bubble Tab Builder

    private func buildTabButtons() {
        tabButtons.removeAll()
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tab) in tabs.enumerated() {
            let btn = makeBubbleButton(title: tab.title, tag: tab.tag)
            btn.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            btn.accessibilityIdentifier = "notif_tab_\(index)"
            tabStack.addArrangedSubview(btn)
            tabButtons.append(btn)
        }
    }

    private func makeBubbleButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.tag = tag
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.subtitleLabel?.textColor = .mezonPrimary
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        btn.layer.cornerRadius = 16
        btn.layer.masksToBounds = true
        return btn
    }

    // MARK: - Tab Selection

    @objc private func tabButtonTapped(_ sender: UIButton) {
        selectTab(at: sender.tag - 1)
    }

    private func selectTab(at index: Int) {
        selectedTabIndex = index
        updateTabStyles()
        reloadContentForSelectedTab()
    }

    private func updateTabStyles() {
        for (i, btn) in tabButtons.enumerated() {
            let isSelected = i == selectedTabIndex
            btn.backgroundColor = isSelected ? .mezonLink : .mezonPrimary
            btn.setTitleColor(isSelected ? .white : .mezonChannelText, for: .normal)
            btn.layer.borderWidth = isSelected ? 0 : 1
            btn.layer.borderColor = UIColor.mezonBorder.cgColor
        }
    }

    private func reloadContentForSelectedTab() {
        let categoryTag = tabs[selectedTabIndex].tag
        Task {
            await viewModel.fetchNotifications(category: Int32(categoryTag))
        }
    }
}

// MARK: - NotificationItemView

private final class NotificationItemView: UIView {

    private let avatarSize: CGFloat = 36.0

    private lazy var avatarView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = avatarSize / 2
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .colorAvatarDefault
        return iv
    }()

    private lazy var avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private lazy var timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = .mezonChannelText
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = .mezonTextMuted
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var verticalLine: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonBorder
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        addSubview(titleLabel)
        addSubview(timeLabel)
        addSubview(contentLabel)
        addSubview(verticalLine)

        NSLayoutConstraint.activate([
            // Avatar constraints
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            // Time constraints (anchored to right)
            timeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Title constraints
            titleLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor),

            // Vertical Line
            verticalLine.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            verticalLine.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            verticalLine.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            verticalLine.widthAnchor.constraint(equalToConstant: 2),

            // Content Label
            contentLabel.topAnchor.constraint(equalTo: verticalLine.topAnchor),
            contentLabel.leadingAnchor.constraint(
                equalTo: verticalLine.trailingAnchor, constant: 8),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
        ])
    }

    func configure(with notification: Notifications) {
        titleLabel.text = notification.subject

        if !notification.content.isEmpty {
            contentLabel.text = notification.content
        } else {
            contentLabel.text = nil
        }

        // Placeholder and avatar mapping
        let avatarURLStr = notification.avatarURL
        if !avatarURLStr.isEmpty, let url = URL(string: avatarURLStr) {
            avatarPlaceholder.isHidden = true
            URLSession.shared.dataTask(with: url) { [weak avatarView] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { avatarView?.image = img }
            }
            .resume()
        } else {
            avatarView.image = nil
            avatarPlaceholder.isHidden = false
            if let firstChar = notification.subject.first {
                avatarPlaceholder.text = String(firstChar).uppercased()
            } else {
                avatarPlaceholder.text = "N"
            }
        }

        // Simple relative time formatting
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
}
