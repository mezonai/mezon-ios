import UIKit

enum QuickActionKind {
    case flashMessage
    case quickMenu

    var quickMenuType: MezonConstants.QuickMenuType {
        switch self {
        case .flashMessage: return .flashMessage
        case .quickMenu: return .quickMenu
        }
    }

    var menuType: Int32 {
        quickMenuType.rawValue
    }

    var typeLabel: String {
        switch self {
        case .flashMessage: return L(L10n.QuickAction.flashMessage)
        case .quickMenu: return L(L10n.QuickAction.quickMenu)
        }
    }

    func commandLabel(for item: Mezon_Api_QuickMenuAccess) -> String {
        switch self {
        case .flashMessage: return "/" + item.menuName
        case .quickMenu: return item.menuName
        }
    }
}

enum QuickActionPalette {
    static let commandChip = UIColor(rgb: 0x00d4aa)
    static let typeBadge = UIColor(rgb: 0x3b82f6)
    static let typeBadgeText = UIColor(rgb: 0x60a5fa)
    static let calloutBody = UIColor(rgb: 0x93c5fd)
}

@MainActor
final class QuickActionListViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64

    private var activeKind: QuickActionKind = .flashMessage
    private var itemsByKind: [QuickActionKind: [Mezon_Api_QuickMenuAccess]] = [:]
    private var loadedKinds: Set<QuickActionKind> = []
    private var loadingKinds: Set<QuickActionKind> = []
    private var reloadSeq: [QuickActionKind: Int] = [:]
    private var deletingIds: Set<Int64> = []

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let tabStack = UIStackView()
    private let flashTabButton = QuickActionTabButton()
    private let menuTabButton = QuickActionTabButton()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = QuickActionEmptyView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let addButton = UIButton(type: .system)

    init(context: AccountContext, clanId: Int64, channelId: Int64) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    private var activeItems: [Mezon_Api_QuickMenuAccess] {
        itemsByKind[activeKind] ?? []
    }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupTabs()
        setupAddButton()
        setupTableView()
        setupEmptyView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for kind in [QuickActionKind.flashMessage, .quickMenu] {
            if let cached = SlashCommandCatalog.shared.cached(channelId: channelId, menuType: kind.quickMenuType) {
                itemsByKind[kind] = cached
            }
        }
        reload(.flashMessage)
        reload(.quickMenu)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        titleLabel.text = L(L10n.QuickAction.title)
        backButton.tintColor = t.textStrong
        descriptionLabel.textColor = t.textDisabled
        descriptionLabel.text = L(L10n.QuickAction.description)
        tableView.backgroundColor = .clear
        loadingIndicator.color = t.textDisabled
        addButton.backgroundColor = t.bgViolet
        addButton.tintColor = .white
        addButton.setTitleColor(.white, for: .normal)
        emptyView.applyTheme()
        updateContent()
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textAlignment = .center

        [backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        descriptionLabel.font = .systemFont(ofSize: 13.sf)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8.sw),

            descriptionLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw)
        ])
    }

    private func setupTabs() {
        tabStack.axis = .horizontal
        tabStack.spacing = 8.sw
        tabStack.alignment = .center
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabStack)

        flashTabButton.addTarget(self, action: #selector(flashTabTapped), for: .touchUpInside)
        menuTabButton.addTarget(self, action: #selector(menuTabTapped), for: .touchUpInside)
        tabStack.addArrangedSubview(flashTabButton)
        tabStack.addArrangedSubview(menuTabButton)

        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 16.sh),
            tabStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16.sw)
        ])
    }

    private func setupAddButton() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15.sf, weight: .semibold)
        addButton.setImage(UIImage(systemName: "plus.circle.fill", withConfiguration: symbolConfig), for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        addButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4.sw, bottom: 0, right: 4.sw)
        addButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4.sw, bottom: 0, right: -4.sw)
        addButton.layer.cornerRadius = 12
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)

        NSLayoutConstraint.activate([
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12.sh),
            addButton.heightAnchor.constraint(equalToConstant: 48.sh)
        ])
    }

    private func setupTableView() {
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96.sh
        tableView.contentInset = UIEdgeInsets(top: 4.sh, left: 0, bottom: 12.sh, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(QuickActionItemCell.self, forCellReuseIdentifier: QuickActionItemCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tabStack.bottomAnchor, constant: 12.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: tabStack.bottomAnchor, constant: 48.sh)
        ])
    }

    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)

        NSLayoutConstraint.activate([
            emptyView.topAnchor.constraint(equalTo: tabStack.bottomAnchor, constant: 16.sh),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw)
        ])
    }

    private func updateContent() {
        let flashCount = itemsByKind[.flashMessage]?.count ?? 0
        let menuCount = itemsByKind[.quickMenu]?.count ?? 0
        flashTabButton.configure(title: L(L10n.QuickAction.flashMessages), count: flashCount, isActive: activeKind == .flashMessage)
        menuTabButton.configure(title: L(L10n.QuickAction.quickMenus), count: menuCount, isActive: activeKind == .quickMenu)

        let addTitle = activeKind == .flashMessage ? L(L10n.QuickAction.addFlashMessage) : L(L10n.QuickAction.addQuickMenu)
        addButton.setTitle(addTitle, for: .normal)

        let items = activeItems
        let isLoading = loadingKinds.contains(activeKind) && !loadedKinds.contains(activeKind)
        if items.isEmpty && isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
        emptyView.configure(kind: activeKind)
        emptyView.isHidden = !items.isEmpty || isLoading
        tableView.isHidden = items.isEmpty
        tableView.reloadData()
    }

    private func reload(_ kind: QuickActionKind) {
        let seq = (reloadSeq[kind] ?? 0) + 1
        reloadSeq[kind] = seq
        loadingKinds.insert(kind)
        updateContent()
        Task { [weak self] in
            guard let self else { return }
            let token = await self.context.getToken()
            var fetched: [Mezon_Api_QuickMenuAccess]?
            var failure: Error?
            if let token {
                do {
                    fetched = try await MezonHTTPClient.shared.listQuickMenuAccess(
                        channelId: self.channelId,
                        menuType: kind.menuType,
                        token: token
                    )
                } catch {
                    failure = error
                }
            }
            guard self.reloadSeq[kind] == seq else { return }
            self.loadingKinds.remove(kind)
            if let fetched {
                self.loadedKinds.insert(kind)
                self.setItems(fetched, for: kind)
            } else if kind == self.activeKind {
                Toast.error(token == nil ? L(L10n.ClanInviteSheet.sessionNotFound) : (failure?.localizedDescription ?? L(L10n.Error.somethingWentWrong)))
            }
            self.updateContent()
        }
    }

    private func setItems(_ items: [Mezon_Api_QuickMenuAccess], for kind: QuickActionKind) {
        itemsByKind[kind] = items
        SlashCommandCatalog.shared.replace(channelId: channelId, menuType: kind.quickMenuType, items: items)
    }

    private func select(_ kind: QuickActionKind) {
        guard activeKind != kind else { return }
        activeKind = kind
        if !loadedKinds.contains(kind) && !loadingKinds.contains(kind) {
            reload(kind)
        } else {
            updateContent()
        }
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func flashTabTapped() {
        select(.flashMessage)
    }

    @objc private func menuTabTapped() {
        select(.quickMenu)
    }

    @objc private func addTapped() {
        openEditor(kind: activeKind, editing: nil)
    }

    private func openEditor(kind: QuickActionKind, editing: Mezon_Api_QuickMenuAccess?) {
        let vc = QuickActionEditViewController(
            context: context,
            clanId: clanId,
            channelId: channelId,
            kind: kind,
            editing: editing,
            existingItems: itemsByKind[kind] ?? []
        )
        vc.onSaved = { [weak self] item, isNew in
            self?.applySaved(item, kind: kind, isNew: isNew)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func applySaved(_ item: Mezon_Api_QuickMenuAccess, kind: QuickActionKind, isNew: Bool) {
        var items = itemsByKind[kind] ?? []
        if isNew {
            items.insert(item, at: 0)
        } else if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.botID = items[index].botID
            items[index] = updated
        }
        setItems(items, for: kind)
        updateContent()
        reload(kind)
    }

    private func confirmDelete(_ item: Mezon_Api_QuickMenuAccess, kind: QuickActionKind) {
        let alert = UIAlertController(
            title: L(L10n.QuickAction.delete) + " " + kind.typeLabel,
            message: L(L10n.QuickAction.deleteConfirm, kind.commandLabel(for: item)),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.QuickAction.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.QuickAction.delete), style: .destructive) { [weak self] _ in
            self?.performDelete(item, kind: kind)
        })
        present(alert, animated: true)
    }

    private func performDelete(_ item: Mezon_Api_QuickMenuAccess, kind: QuickActionKind) {
        guard !deletingIds.contains(item.id) else { return }
        deletingIds.insert(item.id)
        Task { [weak self] in
            guard let self else { return }
            defer { self.deletingIds.remove(item.id) }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                try await MezonHTTPClient.shared.deleteQuickMenuAccess(
                    id: item.id,
                    clanId: self.clanId,
                    menuName: item.menuName,
                    token: token
                )
                let remaining = (self.itemsByKind[kind] ?? []).filter { $0.id != item.id }
                self.setItems(remaining, for: kind)
                self.updateContent()
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }
}

extension QuickActionListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        activeItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: QuickActionItemCell.reuseId, for: indexPath) as! QuickActionItemCell
        let kind = activeKind
        let item = activeItems[indexPath.row]
        cell.configure(item: item, kind: kind)
        cell.onEdit = { [weak self] in
            self?.openEditor(kind: kind, editing: item)
        }
        cell.onDelete = { [weak self] in
            self?.confirmDelete(item, kind: kind)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard activeItems.indices.contains(indexPath.row) else { return }
        openEditor(kind: activeKind, editing: activeItems[indexPath.row])
    }
}

final class QuickActionTabButton: UIControl {

    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let countLabel = QuickActionPaddedLabel(insets: UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8))

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8

        stack.axis = .horizontal
        stack.spacing = 8.sw
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        countLabel.font = .systemFont(ofSize: 12.sf, weight: .medium)
        countLabel.textAlignment = .center
        countLabel.clipsToBounds = true
        countLabel.isCapsule = true
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8.sh),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8.sh),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14.sw),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14.sw)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int, isActive: Bool) {
        let t = UIColor.theme
        titleLabel.text = title
        countLabel.text = "\(count)"
        backgroundColor = isActive ? t.bgViolet : .clear
        titleLabel.textColor = isActive ? .white : t.text
        countLabel.textColor = isActive ? .white : t.text
        countLabel.backgroundColor = isActive ? UIColor.white.withAlphaComponent(0.2) : t.secondary
    }
}

final class QuickActionEmptyView: UIView {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12
        layer.borderWidth = 1

        iconView.image = UIImage(named: "ChannelSetting/QuickActionIcon")?.withRenderingMode(.alwaysTemplate)
        iconView.contentMode = .scaleAspectFit

        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.font = .systemFont(ofSize: 14.sf)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        [iconView, titleLabel, messageLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 28.sh),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48.swh),
            iconView.heightAnchor.constraint(equalToConstant: 48.swh),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16.sh),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20.sw),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20.sw),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20.sw),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20.sw),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28.sh)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        layer.borderColor = t.border.cgColor
        iconView.tintColor = t.textDisabled
        titleLabel.textColor = t.textStrong
        messageLabel.textColor = t.textDisabled
    }

    func configure(kind: QuickActionKind) {
        switch kind {
        case .flashMessage:
            titleLabel.text = L(L10n.QuickAction.emptyFlashMessage)
            messageLabel.text = L(L10n.QuickAction.emptyFlashMessageDescription)
        case .quickMenu:
            titleLabel.text = L(L10n.QuickAction.emptyQuickMenu)
            messageLabel.text = L(L10n.QuickAction.emptyQuickMenuDescription)
        }
        applyTheme()
    }
}

final class QuickActionItemCell: UITableViewCell {

    static let reuseId = "QuickActionItemCell"

    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private let cardView = UIView()
    private let chipStack = UIStackView()
    private let commandLabel = QuickActionPaddedLabel(insets: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
    private let typeLabel = QuickActionPaddedLabel(insets: UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8))
    private let previewLabel = UILabel()
    private let editButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        cardView.layer.cornerRadius = 12
        cardView.layer.borderWidth = 1
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        chipStack.axis = .horizontal
        chipStack.spacing = 8.sw
        chipStack.alignment = .center
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(chipStack)

        commandLabel.font = .monospacedSystemFont(ofSize: 14.sf, weight: .medium)
        commandLabel.textColor = QuickActionPalette.commandChip
        commandLabel.backgroundColor = QuickActionPalette.commandChip.withAlphaComponent(0.1)
        commandLabel.layer.cornerRadius = 4
        commandLabel.clipsToBounds = true
        commandLabel.lineBreakMode = .byTruncatingTail
        commandLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        typeLabel.font = .systemFont(ofSize: 12.sf, weight: .medium)
        typeLabel.textColor = QuickActionPalette.typeBadgeText
        typeLabel.backgroundColor = QuickActionPalette.typeBadge.withAlphaComponent(0.2)
        typeLabel.clipsToBounds = true
        typeLabel.isCapsule = true
        typeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        typeLabel.setContentHuggingPriority(.required, for: .horizontal)

        chipStack.addArrangedSubview(commandLabel)
        chipStack.addArrangedSubview(typeLabel)

        previewLabel.font = .systemFont(ofSize: 14.sf)
        previewLabel.numberOfLines = 4
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(previewLabel)

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 14.sf, weight: .medium)
        editButton.setImage(UIImage(systemName: "pencil", withConfiguration: iconConfig), for: .normal)
        editButton.accessibilityLabel = L(L10n.QuickAction.editCommand)
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        deleteButton.setImage(UIImage(systemName: "trash.fill", withConfiguration: iconConfig), for: .normal)
        deleteButton.accessibilityLabel = L(L10n.QuickAction.deleteCommand)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        [editButton, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6.sh),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6.sh),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),

            deleteButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8.sh),
            deleteButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8.sw),
            deleteButton.widthAnchor.constraint(equalToConstant: 36.swh),
            deleteButton.heightAnchor.constraint(equalToConstant: 36.swh),

            editButton.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 36.swh),
            editButton.heightAnchor.constraint(equalToConstant: 36.swh),

            chipStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14.sh),
            chipStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14.sw),
            chipStack.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -8.sw),

            previewLabel.topAnchor.constraint(equalTo: chipStack.bottomAnchor, constant: 10.sh),
            previewLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14.sw),
            previewLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14.sw),
            previewLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14.sh)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onEdit = nil
        onDelete = nil
    }

    func configure(item: Mezon_Api_QuickMenuAccess, kind: QuickActionKind) {
        let t = UIColor.theme
        cardView.backgroundColor = t.secondary
        cardView.layer.borderColor = t.border.cgColor
        previewLabel.textColor = t.text
        editButton.tintColor = t.textDisabled
        deleteButton.tintColor = t.textDisabled

        commandLabel.text = kind.commandLabel(for: item)
        typeLabel.text = kind.typeLabel
        switch kind {
        case .flashMessage:
            previewLabel.font = .systemFont(ofSize: 14.sf)
            previewLabel.text = item.actionMsg
        case .quickMenu:
            previewLabel.font = .italicSystemFont(ofSize: 14.sf)
            previewLabel.text = L(L10n.QuickAction.triggersBot)
        }
    }

    @objc private func editTapped() {
        onEdit?()
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}

final class QuickActionPaddedLabel: UILabel {

    private let insets: UIEdgeInsets
    var isCapsule = false

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isCapsule {
            layer.cornerRadius = bounds.height / 2
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = super.sizeThatFits(CGSize(
            width: max(0, size.width - insets.left - insets.right),
            height: max(0, size.height - insets.top - insets.bottom)
        ))
        return CGSize(width: inner.width + insets.left + insets.right, height: inner.height + insets.top + insets.bottom)
    }
}
