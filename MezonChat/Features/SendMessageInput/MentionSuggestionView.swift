import UIKit

struct MentionMember: Equatable {
    let userId: Int64
    let displayName: String
    let username: String
    let avatarURL: String?
}

enum MentionSuggestionItem: Equatable {
    case user(MentionMember)
    case role(id: Int64, title: String, colorHex: String, iconURL: String?)
    case here

    var sortKey: String {
        switch self {
        case .user(let m): return m.displayName.lowercased()
        case .role(_, let title, _, _): return title.lowercased()
        case .here: return "here"
        }
    }
}

final class MentionSuggestionView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelectItem: ((MentionSuggestionItem) -> Void)?
    private(set) var items: [MentionSuggestionItem] = []

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.rowHeight = 44
        tv.bounces = true
        tv.keyboardDismissMode = .none
        tv.register(MentionSuggestionCell.self, forCellReuseIdentifier: "MentionCell")
        return tv
    }()

    private static let maxVisibleRows = 5
    static let rowHeight: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        clipsToBounds = true
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        tableView.dataSource = self
        tableView.delegate = self
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        tableView.backgroundColor = t.secondary
    }

    func update(items: [MentionSuggestionItem]) {
        self.items = items
        tableView.reloadData()
    }

    var preferredHeight: CGFloat {
        let rows = min(items.count, Self.maxVisibleRows)
        return CGFloat(rows) * Self.rowHeight
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MentionCell", for: indexPath) as! MentionSuggestionCell
        let item = items[indexPath.row]
        cell.configure(item: item)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let item = items[indexPath.row]
        onSelectItem?(item)
    }
}

private final class MentionSuggestionCell: UITableViewCell {

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.layer.cornerRadius = 14
        return iv
    }()

    private let placeholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.textAlignment = .center
        lbl.font = .systemFont(ofSize: 12, weight: .semibold)
        lbl.textColor = .white
        return lbl
    }()

    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        return lbl
    }()

    private let usernameLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        lbl.textAlignment = .right
        return lbl
    }()

    private var avatarWidthConstraint: NSLayoutConstraint!
    private var nameLeadingToAvatarConstraint: NSLayoutConstraint!
    private var nameLeadingToContentConstraint: NSLayoutConstraint!
    private var currentAvatarTask: URLSessionDataTask?
    private var currentAvatarURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        selectionStyle = .none
        contentView.addSubview(avatarImageView)
        contentView.addSubview(placeholderLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(usernameLabel)

        avatarWidthConstraint = avatarImageView.widthAnchor.constraint(equalToConstant: 28)
        nameLeadingToAvatarConstraint = nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10)
        nameLeadingToContentConstraint = nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarWidthConstraint,
            avatarImageView.heightAnchor.constraint(equalToConstant: 28),

            placeholderLabel.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),

            nameLeadingToAvatarConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: usernameLabel.leadingAnchor, constant: -8),

            usernameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            usernameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            usernameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
        ])
    }

    func configure(item: MentionSuggestionItem) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        contentView.backgroundColor = t.secondary
        cancelAvatarLoad()
        avatarImageView.isHidden = false
        placeholderLabel.isHidden = true
        avatarImageView.image = nil
        avatarImageView.tintColor = nil
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 14
        avatarWidthConstraint.constant = 28
        nameLeadingToContentConstraint.isActive = false
        nameLeadingToAvatarConstraint.isActive = true

        switch item {
        case .user(let member):
            nameLabel.textColor = t.textStrong
            usernameLabel.textColor = t.textDisabled
            nameLabel.text = member.displayName
            usernameLabel.text = member.username

            if let raw = member.avatarURL, !raw.isEmpty {
                let proxied = ImgproxyURL.create(from: raw, width: 56, height: 56)
                if let imageURL = URL(string: proxied) {
                    placeholderLabel.isHidden = true
                    avatarImageView.backgroundColor = UIColor.avatarColor(for: member.username)
                    loadAvatar(from: imageURL, key: proxied)
                } else {
                    showPlaceholder(for: member.displayName, username: member.username)
                }
            } else {
                showPlaceholder(for: member.displayName, username: member.username)
            }

        case .role(_, let title, let colorHex, let iconURL):
            nameLabel.textColor = UIColor(hexString: colorHex) ?? t.textRoleLink
            usernameLabel.textColor = t.textDisabled
            usernameLabel.text = ""
            nameLabel.text = title
            let accent = UIColor(hexString: colorHex) ?? t.textRoleLink
            if let s = iconURL, !s.isEmpty {
                let proxied = ImgproxyURL.create(from: s, width: 56, height: 56)
                if let imageURL = URL(string: proxied) {
                    avatarImageView.backgroundColor = .clear
                    avatarImageView.contentMode = .scaleAspectFit
                    loadAvatar(from: imageURL, key: proxied)
                } else {
                    showRolePlaceholder(accent: accent)
                }
            } else {
                showRolePlaceholder(accent: accent)
            }

        case .here:
            nameLabel.textColor = t.textRoleLink
            usernameLabel.text = ""
            nameLabel.text = "@here"
            avatarImageView.isHidden = true
            avatarWidthConstraint.constant = 0
            nameLeadingToAvatarConstraint.isActive = false
            nameLeadingToContentConstraint.isActive = true
        }
    }

    private func showPlaceholder(for displayName: String, username: String) {
        avatarImageView.backgroundColor = UIColor.avatarColor(for: username)
        let initial = String(username.prefix(1)).uppercased()
        placeholderLabel.text = initial
        placeholderLabel.isHidden = false
    }

    private func showRolePlaceholder(accent: UIColor) {
        avatarImageView.backgroundColor = .clear
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.image = UIImage(systemName: "shield.fill")?.withRenderingMode(.alwaysTemplate)
        avatarImageView.tintColor = accent
    }

    private func cancelAvatarLoad() {
        currentAvatarTask?.cancel()
        currentAvatarTask = nil
        currentAvatarURL = nil
    }

    private func loadAvatar(from url: URL, key: String) {
        currentAvatarURL = key
        if let cached = ImageCache.shared.image(forKey: key) {
            avatarImageView.image = cached
            avatarImageView.backgroundColor = .clear
            return
        }
        avatarImageView.image = nil
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            ImageCache.shared.setImage(image, data: data, forKey: key)
            DispatchQueue.main.async {
                guard let self, self.currentAvatarURL == key else { return }
                self.avatarImageView.image = image
                self.avatarImageView.backgroundColor = .clear
            }
        }
        currentAvatarTask = task
        task.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelAvatarLoad()
        avatarImageView.image = nil
        avatarImageView.tintColor = nil
        avatarImageView.backgroundColor = .clear
        placeholderLabel.text = nil
        placeholderLabel.textColor = .white
        nameLabel.text = nil
        usernameLabel.text = nil
        avatarImageView.isHidden = false
    }
}
