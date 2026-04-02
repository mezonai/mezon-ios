import UIKit


final class EmojiSuggestionView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelectEmoji: ((CachedClanEmojiRecord) -> Void)?
    private(set) var items: [CachedClanEmojiRecord] = []

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.rowHeight = 50
        tv.bounces = true
        tv.keyboardDismissMode = .none
        tv.register(EmojiSuggestionCell.self, forCellReuseIdentifier: EmojiSuggestionCell.reuseId)
        return tv
    }()

    private static let maxVisibleRows = 5
    static let rowHeight: CGFloat = 50

    override init(frame: CGRect) {
        super.init(frame: frame)
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

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        tableView.backgroundColor = t.secondary
    }

    func update(items: [CachedClanEmojiRecord]) {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: EmojiSuggestionCell.reuseId, for: indexPath) as! EmojiSuggestionCell
        cell.configure(emoji: items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onSelectEmoji?(items[indexPath.row])
    }

    static func emojiImageURL(for emoji: CachedClanEmojiRecord) -> URL? {
        if let url = URL(string: emoji.src), url.scheme != nil { return url }
        return MezonConfig.emojiResourceURL(emojiId: "\(emoji.id)", imgproxyFitSide: 32)
    }


    fileprivate static func decodeEmojiImage(from data: Data) -> UIImage? {
        UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
    }
}

private final class EmojiSuggestionCell: UITableViewCell {
    static let reuseId = "EmojiSuggestionCell"

    private let emojiImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 15, weight: .medium)
        return lbl
    }()

    private var loadTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(emojiImageView)
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            emojiImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            emojiImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            emojiImageView.widthAnchor.constraint(equalToConstant: 32),
            emojiImageView.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: emojiImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(emoji: CachedClanEmojiRecord) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        contentView.backgroundColor = t.secondary
        nameLabel.textColor = t.textStrong

        let inner = emoji.shortname.split(separator: ":").joined()
        nameLabel.text = inner.isEmpty ? emoji.shortname : ":\(inner):"

        loadTask?.cancel()
        loadTask = nil
        emojiImageView.image = nil

        guard let url = EmojiSuggestionView.emojiImageURL(for: emoji) else { return }
        let key = url.absoluteString


        if let diskData = ImageCache.shared.cachedData(forKey: key),
           let img = EmojiSuggestionView.decodeEmojiImage(from: diskData) {
            emojiImageView.image = img
            ImageCache.shared.setImage(img, data: diskData, forKey: key)
            return
        }
        if let mem = ImageCache.shared.memoryImage(forKey: key) {
            emojiImageView.image = mem
            return
        }

        loadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = EmojiSuggestionView.decodeEmojiImage(from: data) else { return }
            ImageCache.shared.setImage(img, data: data, forKey: key)
            DispatchQueue.main.async {
                self?.emojiImageView.image = img
            }
        }
        loadTask?.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        emojiImageView.image = nil
        nameLabel.text = nil
    }
}
