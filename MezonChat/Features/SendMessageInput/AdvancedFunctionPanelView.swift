import UIKit

struct AdvancedFunctionItem {
    let id: String
    let label: String
    let systemIcon: String
    let backgroundColor: UIColor
}

final class AdvancedFunctionPanelView: UIView, UIGestureRecognizerDelegate {

    var onRequestDismiss: (() -> Void)?
    var onActionTapped: ((AdvancedFunctionItem) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    var collapsedHeight: CGFloat = 260
    var expandedHeight: CGFloat = 500

    private(set) var isExpanded = false

    private let grabberBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.mezonLabel.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let handleArea: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let gridScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let gridContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private static let handleHeight: CGFloat = 24
    private static let collapsingConstraintPriority = UILayoutPriority(rawValue: 999)
    private static let columnsCount: Int = 4
    private static let iconContainerSize: CGFloat = 42
    private static let itemSpacingV: CGFloat = 20
    private static let itemPaddingH: CGFloat = 8

    private var sheetPanGesture: UIPanGestureRecognizer!
    private var dragStartHeight: CGFloat = 0

    private var actionItems: [AdvancedFunctionItem] = []
    private var gridHeightConstraint: NSLayoutConstraint?

    static func defaultActionItems(
        anonymousOn: Bool,
        includeAnonymous: Bool,
        includeCreateThread: Bool = false
    ) -> [AdvancedFunctionItem] {
        var items: [AdvancedFunctionItem] = []
        if !anonymousOn {
            items.append(AdvancedFunctionItem(id: "location", label: "Location", systemIcon: "location.fill",
                                              backgroundColor: UIColor(red: 0.91, green: 0.60, blue: 0.58, alpha: 1)))
            items.append(AdvancedFunctionItem(id: "create_poll", label: L(L10n.CreatePoll.poll), systemIcon: "chart.bar.xaxis",
                                              backgroundColor: UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)))
        }
        items.append(contentsOf: [
            AdvancedFunctionItem(id: "pickFiles", label: "Files", systemIcon: "doc.fill",
                                 backgroundColor: UIColor(red: 0.15, green: 0.27, blue: 0.88, alpha: 1)),
            AdvancedFunctionItem(id: "buzz", label: "Buzz", systemIcon: "megaphone.fill",
                                 backgroundColor: UIColor(red: 0.83, green: 0.40, blue: 0.48, alpha: 1)),
        ])
        if includeCreateThread {
            items.append(AdvancedFunctionItem(
                id: "create_thread",
                label: L(L10n.MessageAction.createThread),
                systemIcon: "bubble.left.and.bubble.right.fill",
                backgroundColor: UIColor(red: 0.45, green: 0.52, blue: 0.92, alpha: 1)
            ))
        }
        if includeAnonymous {
            let anonLabel = anonymousOn ? "Anonymous\nOn" : "Anonymous"
            items.append(AdvancedFunctionItem(id: "anonymous", label: anonLabel, systemIcon: "Chat/AnonymousIcon",
                                              backgroundColor: UIColor(red: 0.32, green: 0.34, blue: 0.42, alpha: 1)))
        }
        items.append(AdvancedFunctionItem(id: "transfer_funds", label: "Transfer\nfunds", systemIcon: "arrow.up.circle.fill",
                                          backgroundColor: UIColor(red: 0.36, green: 0.73, blue: 0.55, alpha: 1)))
        if !anonymousOn {
            items.append(AdvancedFunctionItem(id: "share_contact", label: "Share\nContact", systemIcon: "person.crop.circle.badge.plus",
                                              backgroundColor: UIColor(red: 0.42, green: 0.71, blue: 1.0, alpha: 1)))
        }
        return items
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        actionItems = Self.defaultActionItems(anonymousOn: false, includeAnonymous: true, includeCreateThread: false)
        setupLayout()
        setupGrid()
        setupGestures()
    }

    func setActions(_ items: [AdvancedFunctionItem]) {
        actionItems = items
        gridContainerView.subviews.forEach { $0.removeFromSuperview() }
        if let gh = gridHeightConstraint {
            NSLayoutConstraint.deactivate([gh])
            gridHeightConstraint = nil
        }
        setupGrid()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
    }

    func resetToCollapsed() {
        isExpanded = false
        gridScrollView.setContentOffset(.zero, animated: false)
    }

    func applySnapCollapsed() {
        isExpanded = false
        gridScrollView.setContentOffset(.zero, animated: false)
        onHeightChanged?(collapsedHeight)
    }

    private func setupLayout() {
        addSubview(handleArea)
        handleArea.addSubview(grabberBar)
        addSubview(gridScrollView)
        gridScrollView.addSubview(gridContainerView)

        let handleH = handleArea.heightAnchor.constraint(equalToConstant: Self.handleHeight)
        handleH.priority = Self.collapsingConstraintPriority
        let gridTop = gridScrollView.topAnchor.constraint(equalTo: handleArea.bottomAnchor, constant: 8)
        gridTop.priority = Self.collapsingConstraintPriority
        let gridW = gridContainerView.widthAnchor.constraint(equalTo: gridScrollView.frameLayoutGuide.widthAnchor)
        gridW.priority = Self.collapsingConstraintPriority
        NSLayoutConstraint.activate([
            handleArea.topAnchor.constraint(equalTo: topAnchor),
            handleArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            handleArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            handleH,

            grabberBar.centerXAnchor.constraint(equalTo: handleArea.centerXAnchor),
            grabberBar.centerYAnchor.constraint(equalTo: handleArea.centerYAnchor),
            grabberBar.widthAnchor.constraint(equalToConstant: 36),
            grabberBar.heightAnchor.constraint(equalToConstant: 5),

            gridTop,
            gridScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            gridContainerView.topAnchor.constraint(equalTo: gridScrollView.contentLayoutGuide.topAnchor),
            gridContainerView.leadingAnchor.constraint(equalTo: gridScrollView.contentLayoutGuide.leadingAnchor),
            gridContainerView.trailingAnchor.constraint(equalTo: gridScrollView.contentLayoutGuide.trailingAnchor),
            gridW,
        ])
    }

    private func setupGrid() {
        let columns = Self.columnsCount
        let containerSize = Self.iconContainerSize
        let spacingV = Self.itemSpacingV
        let itemHeight: CGFloat = containerSize + 30

        var itemConstraints: [NSLayoutConstraint] = []

        for (index, action) in actionItems.enumerated() {
            let col = index % columns
            let row = index / columns

            let itemView = makeItemView(action: action)
            gridContainerView.addSubview(itemView)

            let topOffset = CGFloat(row) * (itemHeight + spacingV) + 8

            itemConstraints.append(contentsOf: [
                itemView.topAnchor.constraint(equalTo: gridContainerView.topAnchor, constant: topOffset),
                itemView.leadingAnchor.constraint(equalTo: gridContainerView.leadingAnchor,
                    constant: CGFloat(col) * (1.0 / CGFloat(columns)) * UIScreen.main.bounds.width),
                itemView.widthAnchor.constraint(equalTo: gridContainerView.widthAnchor, multiplier: 1.0 / CGFloat(columns)),
                itemView.heightAnchor.constraint(equalToConstant: itemHeight),
            ])
        }

        let rows = ceil(Double(actionItems.count) / Double(columns))
        let totalH = CGFloat(rows) * (itemHeight + spacingV) + 16
        let gh = gridContainerView.heightAnchor.constraint(equalToConstant: totalH)
        gridHeightConstraint = gh
        itemConstraints.append(gh)

        NSLayoutConstraint.activate(itemConstraints)
    }

    private func makeItemView(action: AdvancedFunctionItem) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.backgroundColor = action.backgroundColor
        iconContainer.layer.cornerRadius = Self.iconContainerSize / 2
        iconContainer.clipsToBounds = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let iconImage = UIImage(named: action.systemIcon)?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: action.systemIcon, withConfiguration: iconConfig)
        let iconImageView = UIImageView(image: iconImage)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.addSubview(iconImageView)

        let label = UILabel()
        label.text = action.label
        label.font = .systemFont(ofSize: 11)
        label.textColor = UIColor.theme.textDisabled
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconContainer)
        container.addSubview(label)

        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(btn)
        btn.tag = actionItems.firstIndex(where: { $0.id == action.id }) ?? 0
        btn.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: container.topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Self.iconContainerSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Self.iconContainerSize),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            label.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.itemPaddingH),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.itemPaddingH),

            btn.topAnchor.constraint(equalTo: container.topAnchor),
            btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0, index < actionItems.count else { return }
        let item = actionItems[index]
        onActionTapped?(item)
    }

    private func setupGestures() {
        sheetPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        sheetPanGesture.delegate = self
        sheetPanGesture.cancelsTouchesInView = false
        addGestureRecognizer(sheetPanGesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer == sheetPanGesture else { return true }
        var v: UIView? = touch.view
        while let cur = v {
            if cur is UIControl { return false }
            if cur === self { break }
            v = cur.superview
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == sheetPanGesture else { return true }
        let velocity = sheetPanGesture.velocity(in: self)
        let isVertical = abs(velocity.y) > abs(velocity.x)
        guard isVertical else { return false }

        if !isExpanded {
            return true
        } else {
            let atTop = gridScrollView.contentOffset.y <= 0
            let draggingDown = velocity.y > 0
            return atTop && draggingDown
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragStartHeight = bounds.height
        case .changed:
            let translation = gesture.translation(in: self)
            let raw = dragStartHeight - translation.y
            let newHeight = min(max(raw, collapsedHeight), expandedHeight)
            onHeightChanged?(newHeight)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).y
            snapWithVelocity(velocity)
        default:
            break
        }
    }

    private func snapWithVelocity(_ velocityY: CGFloat) {
        let currentH = bounds.height
        let midPoint = (collapsedHeight + expandedHeight) / 2

        if velocityY < -500 {
            snapTo(expanded: true)
        } else if velocityY > 500 {
            snapTo(expanded: false)
        } else {
            snapTo(expanded: currentH > midPoint)
        }
    }

    private func snapTo(expanded: Bool) {
        let targetH = expanded ? expandedHeight : collapsedHeight
        isExpanded = expanded
        onHeightChanged?(targetH)

        if !expanded {
            gridScrollView.setContentOffset(.zero, animated: false)
        }
    }
}

final class ShareContactPickerViewController: ViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    var onSelectFriend: ((Mezon_Api_Friend) -> Void)?

    private let context: AccountContext
    private var allFriends: [Mezon_Api_Friend] = []
    private var filteredFriends: [Mezon_Api_Friend] = []
    private var refreshTask: Task<Void, Never>?

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let searchContainer = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    deinit {
        refreshTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Share Contact"
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupSearch()
        setupTable()
        setupEmptyState()
        reloadFriendsFromCache()
        refreshFriends()
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor.theme.primary
        view.addSubview(headerView)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.tintColor = UIColor.theme.textStrong
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        headerView.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Share Contact"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 52),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])
    }

    private func setupSearch() {
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.backgroundColor = UIColor.theme.secondary
        searchContainer.layer.cornerRadius = 18
        searchContainer.clipsToBounds = true
        view.addSubview(searchContainer)

        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.image = UIImage(systemName: "magnifyingglass")
        searchIcon.tintColor = UIColor.theme.textDisabled
        searchIcon.contentMode = .scaleAspectFit
        searchContainer.addSubview(searchIcon)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = L(L10n.DirectMessage.searchFriends)
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = UIColor.theme.textStrong
        searchField.tintColor = UIColor.theme.textStrong
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.DirectMessage.searchFriends),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        searchContainer.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchContainer.heightAnchor.constraint(equalToConstant: 42),

            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor),
        ])
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.register(ShareContactPickerCell.self, forCellReuseIdentifier: ShareContactPickerCell.reuseIdentifier)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = L(L10n.DirectMessage.noFriends)
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = UIColor.theme.textDisabled
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func reloadFriendsFromCache() {
        allFriends = context.engine.friendsData.allFriends()
            .filter { $0.state == EStateFriend.friend.rawValue && $0.hasUser }
            .sorted { lhs, rhs in
                friendDisplayName(lhs).localizedCaseInsensitiveCompare(friendDisplayName(rhs)) == .orderedAscending
            }
        applyFilter()
    }

    private func refreshFriends() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            await self.context.engine.friendsData.refreshFromNetwork(token: token)
            self.reloadFriendsFromCache()
        }
    }

    private func applyFilter() {
        let query = (searchField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        if query.isEmpty {
            filteredFriends = allFriends
        } else {
            filteredFriends = allFriends.filter { friend in
                let name = friendDisplayName(friend)
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current)
                let username = friend.user.username
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current)
                return name.contains(query) || username.contains(query)
            }
        }
        tableView.reloadData()
        emptyLabel.isHidden = !filteredFriends.isEmpty
    }

    private func friendDisplayName(_ friend: Mezon_Api_Friend) -> String {
        let display = friend.user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let username = friend.user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "\(friend.user.id)" : username
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    @objc private func backPressed() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredFriends.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ShareContactPickerCell.reuseIdentifier, for: indexPath)
        if let cell = cell as? ShareContactPickerCell {
            cell.configure(friend: filteredFriends[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredFriends.count else { return }
        onSelectFriend?(filteredFriends[indexPath.row])
    }
}

private final class ShareContactPickerCell: UITableViewCell {
    static let reuseIdentifier = "ShareContactPickerCell"

    private let avatarView = UIImageView()
    private let placeholderLabel = UILabel()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = UIColor.theme.secondary.withAlphaComponent(0.55)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 22
        contentView.addSubview(avatarView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        placeholderLabel.textColor = .white
        placeholderLabel.textAlignment = .center
        avatarView.addSubview(placeholderLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.numberOfLines = 1
        contentView.addSubview(nameLabel)

        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.font = .systemFont(ofSize: 13)
        usernameLabel.textColor = UIColor.theme.textDisabled
        usernameLabel.numberOfLines = 1
        contentView.addSubview(usernameLabel)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            placeholderLabel.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            placeholderLabel.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),

            usernameLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            usernameLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        avatarView.image = nil
    }

    func configure(friend: Mezon_Api_Friend) {
        let user = friend.user
        let display = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = display.isEmpty ? (username.isEmpty ? "\(user.id)" : username) : display

        nameLabel.text = resolvedName
        usernameLabel.text = username.isEmpty ? "" : "@\(username)"
        placeholderLabel.text = String((username.isEmpty ? resolvedName : username).prefix(1)).uppercased()
        avatarView.backgroundColor = UIColor.avatarColor(for: username.isEmpty ? resolvedName : username)
        placeholderLabel.isHidden = false
        avatarView.image = nil

        let rawAvatar = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawAvatar.isEmpty else { return }
        let proxied = ImgproxyURL.avatarProxyURL(from: rawAvatar, width: 120, height: 120)
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            avatarView.image = cached
            placeholderLabel.isHidden = true
            avatarView.backgroundColor = .clear
            return
        }
        imageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self, let image else { return }
            self.avatarView.image = image
            self.placeholderLabel.isHidden = true
            self.avatarView.backgroundColor = .clear
        }
    }
}
