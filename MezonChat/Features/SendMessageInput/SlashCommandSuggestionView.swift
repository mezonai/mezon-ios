import UIKit


final class SlashCommandSuggestionView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelectCommand: ((Mezon_Api_QuickMenuAccess) -> Void)?
    private(set) var items: [Mezon_Api_QuickMenuAccess] = []

    private let headerLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 12, weight: .bold)
        return lbl
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.rowHeight = SlashCommandSuggestionView.rowHeight
        tv.bounces = true
        tv.keyboardDismissMode = .none
        tv.register(SlashCommandSuggestionCell.self, forCellReuseIdentifier: SlashCommandSuggestionCell.reuseId)
        return tv
    }()

    private static let maxVisibleRows = 3
    static let headerHeight: CGFloat = 32
    static let rowHeight: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(headerLabel)
        addSubview(tableView)
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            headerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            headerLabel.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor),
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
        headerLabel.textColor = t.textStrong
        headerLabel.text = L(L10n.SlashCommand.header)
    }

    func update(items: [Mezon_Api_QuickMenuAccess]) {
        self.items = items
        tableView.reloadData()
        if !items.isEmpty {
            tableView.setContentOffset(.zero, animated: false)
        }
    }

    var preferredHeight: CGFloat {
        guard !items.isEmpty else { return 0 }
        let rows = min(items.count, Self.maxVisibleRows)
        return Self.headerHeight + CGFloat(rows) * Self.rowHeight
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SlashCommandSuggestionCell.reuseId, for: indexPath) as! SlashCommandSuggestionCell
        cell.configure(command: items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onSelectCommand?(items[indexPath.row])
    }
}

private final class SlashCommandSuggestionCell: UITableViewCell {
    static let reuseId = "SlashCommandSuggestionCell"

    private let commandLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 15, weight: .bold)
        lbl.lineBreakMode = .byTruncatingTail
        return lbl
    }()

    private let descriptionLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 12, weight: .regular)
        lbl.lineBreakMode = .byTruncatingTail
        return lbl
    }()

    private let separatorView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(commandLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(separatorView)
        NSLayoutConstraint.activate([
            commandLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            commandLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            commandLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            descriptionLabel.leadingAnchor.constraint(equalTo: commandLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: commandLabel.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 4),

            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(command: Mezon_Api_QuickMenuAccess) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        contentView.backgroundColor = t.secondary
        commandLabel.textColor = t.textStrong
        descriptionLabel.textColor = t.text
        separatorView.backgroundColor = t.border

        commandLabel.text = "/" + command.menuName
        descriptionLabel.text = command.actionMsg
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
