import UIKit

final class ClanPickerSheetViewController: UIViewController {

    private let clans: [Mezon_Api_ClanDesc]
    private let selectedClanId: Int64?
    private let sheetTitle: String
    private let onPick: (Mezon_Api_ClanDesc) -> Void

    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    private static let rowHeight: CGFloat = 56

    init(
        clans: [Mezon_Api_ClanDesc],
        selectedClanId: Int64?,
        title: String,
        onPick: @escaping (Mezon_Api_ClanDesc) -> Void
    ) {
        self.clans = clans
        self.selectedClanId = selectedClanId
        self.sheetTitle = title
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applySheetTheme()
        configureSheetPresentationIfAvailable()

        titleLabel.text = sheetTitle
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorInset = .zero
        tableView.tableFooterView = UIView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ClanPickerCell.self, forCellReuseIdentifier: ClanPickerCell.reuseId)
        view.addSubview(tableView)

        let titleTopPadding: CGFloat = 28
        let titleToTableSpacing: CGFloat = 12
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: titleTopPadding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: titleToTableSpacing),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    private func configureSheetPresentationIfAvailable() {
        guard #available(iOS 15.0, *) else { return }
        guard let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 16
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersEdgeAttachedInCompactHeight = true
        if #available(iOS 16.0, *) {
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
    }

    @objc private func themeDidChange() {
        applySheetTheme()
        tableView.reloadData()
    }

    private func applySheetTheme() {
        view.backgroundColor = .mezonPrimary
        titleLabel.textColor = .mezonTextStrong
        tableView.backgroundColor = .mezonPrimary
        tableView.separatorColor = .mezonSeparator
    }

    private func selectClan(_ clan: Mezon_Api_ClanDesc) {
        onPick(clan)
        dismiss(animated: true)
    }
}

extension ClanPickerSheetViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        clans.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        Self.rowHeight
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ClanPickerCell.reuseId, for: indexPath) as! ClanPickerCell
        let clan = clans[indexPath.row]
        let selected = clan.clanID == selectedClanId
        cell.configure(clan: clan, selected: selected)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectClan(clans[indexPath.row])
    }
}

private final class ClanPickerCell: UITableViewCell {

    static let reuseId = "ClanPickerCell"

    private var boundClanId: Int64?

    private let avatarView = UIImageView()
    private let placeholderView = UIView()
    private let initialLabel = UILabel()
    private let nameLabel = UILabel()
    private let checkView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        let selBg = UIView()
        selBg.backgroundColor = UIColor.mezonChannelSelected
        selectedBackgroundView = selBg

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 8

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.backgroundColor = .colorAvatarDefault
        placeholderView.layer.cornerRadius = 8
        placeholderView.clipsToBounds = true

        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        initialLabel.textAlignment = .center

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.contentMode = .scaleAspectFit
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        checkView.image = UIImage(systemName: "checkmark", withConfiguration: cfg)

        contentView.addSubview(placeholderView)
        contentView.addSubview(avatarView)
        placeholderView.addSubview(initialLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(checkView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            placeholderView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),

            initialLabel.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 14),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -8),

            checkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            checkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
        ])

        applyCellTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyCellTheme() {
        nameLabel.textColor = .mezonTextStrong
        initialLabel.textColor = .mezonTextStrong
        checkView.tintColor = .mezonSuccess
    }

    func configure(clan: Mezon_Api_ClanDesc, selected: Bool) {
        applyCellTheme()
        boundClanId = clan.clanID
        nameLabel.text = clan.clanName
        let initial = clan.clanName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
        initialLabel.text = initial
        checkView.isHidden = !selected
        avatarView.image = nil
        placeholderView.isHidden = false
        avatarView.isHidden = true

        let url = clan.logo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        if let cached = ImageCache.shared.memoryImage(forKey: url) {
            avatarView.image = cached
            placeholderView.isHidden = true
            avatarView.isHidden = false
            return
        }
        let expectId = clan.clanID
        ImageCache.shared.loadImage(urlString: url) { [weak self] img in
            DispatchQueue.main.async {
                guard let self, self.boundClanId == expectId, img != nil else { return }
                self.avatarView.image = img
                self.placeholderView.isHidden = true
                self.avatarView.isHidden = false
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        boundClanId = nil
        avatarView.image = nil
        placeholderView.isHidden = false
        avatarView.isHidden = true
        initialLabel.text = nil
        nameLabel.text = nil
        checkView.isHidden = true
    }
}
