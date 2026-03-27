import UIKit

struct MentionMember {
    let userId: Int64
    let displayName: String
    let username: String
    let avatarURL: String?
}

final class MentionSuggestionView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelectMember: ((MentionMember) -> Void)?
    private(set) var members: [MentionMember] = []

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

    func update(members: [MentionMember]) {
        self.members = members
        tableView.reloadData()
    }

    var preferredHeight: CGFloat {
        let rows = min(members.count, Self.maxVisibleRows)
        return CGFloat(rows) * Self.rowHeight
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        members.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MentionCell", for: indexPath) as! MentionSuggestionCell
        let member = members[indexPath.row]
        cell.configure(member: member)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let member = members[indexPath.row]
        onSelectMember?(member)
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

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 28),
            avatarImageView.heightAnchor.constraint(equalToConstant: 28),

            placeholderLabel.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: usernameLabel.leadingAnchor, constant: -8),

            usernameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            usernameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            usernameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
        ])
    }

    func configure(member: MentionMember) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        contentView.backgroundColor = t.secondary
        nameLabel.textColor = t.textStrong
        usernameLabel.textColor = t.textDisabled

        nameLabel.text = member.displayName
        usernameLabel.text = member.username

        if let url = member.avatarURL, !url.isEmpty, let imageURL = URL(string: url) {
            placeholderLabel.isHidden = true
            avatarImageView.backgroundColor = .clear
            loadAvatar(from: imageURL)
        } else {
            avatarImageView.image = nil
            avatarImageView.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
            let initial = String(member.displayName.prefix(1)).uppercased()
            placeholderLabel.text = initial
            placeholderLabel.isHidden = false
        }
    }

    private func loadAvatar(from url: URL) {
        let cacheKey = url.absoluteString
        if let cached = ImageCache.shared.image(forKey: cacheKey) {
            avatarImageView.image = cached
            return
        }
        avatarImageView.image = nil
        let expectedURL = url
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            ImageCache.shared.setImage(image, data: data, forKey: cacheKey)
            DispatchQueue.main.async {
                guard let self else { return }
                self.avatarImageView.image = image
            }
        }.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        placeholderLabel.text = nil
        nameLabel.text = nil
        usernameLabel.text = nil
    }
}
