import UIKit


final class HashtagSuggestionView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelectChannel: ((Mezon_Api_ChannelDescription) -> Void)?
    private(set) var items: [Mezon_Api_ChannelDescription] = []

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.rowHeight = 50
        tv.bounces = true
        tv.keyboardDismissMode = .none
        tv.register(HashtagSuggestionCell.self, forCellReuseIdentifier: HashtagSuggestionCell.reuseId)
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

    func update(items: [Mezon_Api_ChannelDescription]) {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: HashtagSuggestionCell.reuseId, for: indexPath) as! HashtagSuggestionCell
        cell.configure(channel: items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onSelectChannel?(items[indexPath.row])
    }
}

private final class HashtagSuggestionCell: UITableViewCell {
    static let reuseId = "HashtagSuggestionCell"

    private let hashLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 15, weight: .semibold)
        return lbl
    }()

    private let subLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 12, weight: .medium)
        return lbl
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(hashLabel)
        contentView.addSubview(subLabel)
        NSLayoutConstraint.activate([
            hashLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            hashLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            hashLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),

            subLabel.leadingAnchor.constraint(equalTo: hashLabel.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: hashLabel.trailingAnchor),
            subLabel.topAnchor.constraint(equalTo: hashLabel.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(channel: Mezon_Api_ChannelDescription) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        contentView.backgroundColor = t.secondary
        hashLabel.textColor = t.textStrong
        subLabel.textColor = t.textDisabled

        let name = channel.channelLabel.isEmpty ? "#" : "#\(channel.channelLabel)"
        hashLabel.text = name
        let sub = channel.categoryName.isEmpty ? channel.clanName : channel.categoryName
        subLabel.text = sub.uppercased()
    }
}
