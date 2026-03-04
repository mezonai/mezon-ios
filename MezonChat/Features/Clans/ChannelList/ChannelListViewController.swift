import UIKit
import Combine


final class ChannelListViewController: BaseViewController {

    private let viewModel: ChannelListViewModel


    private lazy var headerView = ChannelListHeaderView()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.rowHeight = 36.sh
        tv.sectionHeaderHeight = 32.sh
        tv.showsVerticalScrollIndicator = false
        tv.register(ChannelCell.self, forCellReuseIdentifier: ChannelCell.reuseId)
        tv.register(CategoryHeaderView.self, forHeaderFooterViewReuseIdentifier: CategoryHeaderView.reuseId)
        tv.dataSource = self
        tv.delegate   = self
        return tv
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.translatesAutoresizingMaskIntoConstraints = false
        ai.hidesWhenStopped = true
        return ai
    }()


    init(viewModel: ChannelListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }


    override func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56.sh),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func setupBindings() {
        viewModel.$categories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.loadingIndicator.startAnimating()
                        : self?.loadingIndicator.stopAnimating()
            }
            .store(in: &cancellables)

        viewModel.$selectedChannelId
            .receive(on: DispatchQueue.main)
            .scan((previous: Int64?.none, current: Int64?.none)) { acc, newId in
                (previous: acc.current, current: newId)
            }
            .sink { [weak self] previous, current in
                guard let self else { return }
                var paths: [IndexPath] = []
                for (s, cat) in self.viewModel.categories.enumerated() {
                    for (r, ch) in cat.channels.enumerated() {
                        if ch.channelID == previous || ch.channelID == current {
                            paths.append(IndexPath(row: r, section: s))
                        }
                    }
                }
                guard !paths.isEmpty else { return }
                UIView.performWithoutAnimation {
                    self.tableView.reloadRows(at: paths, with: .none)
                }
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { msg in AppLogger.network.error("[ChannelList] \(msg)") }
            .store(in: &cancellables)
    }

    override func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor       = t.secondary
        loadingIndicator.color     = t.textDisabled
        headerView.applyTheme()
        tableView.reloadData()
    }


    func configure(clanId: Int64, clanName: String) {
        headerView.configure(title: clanName)
        viewModel.load(clanId: clanId, clanName: clanName)
    }

    func refresh() {
        Task { await viewModel.fetchChannels() }
    }
}


extension ChannelListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.categories.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let cat = viewModel.categories[section]
        return cat.isCollapsed ? 0 : cat.channels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cat     = viewModel.categories[indexPath.section]
        let channel = cat.channels[indexPath.row]
        let cell    = tableView.dequeueReusableCell(withIdentifier: ChannelCell.reuseId, for: indexPath) as! ChannelCell
        cell.configure(channel: channel, isSelected: channel.channelID == viewModel.selectedChannelId)
        return cell
    }
}


extension ChannelListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: CategoryHeaderView.reuseId) as! CategoryHeaderView
        let cat = viewModel.categories[section]
        header.configure(category: cat)
        header.onTap = { [weak self] in self?.viewModel.toggleCollapse(categoryId: cat.id) }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 32.sh }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        viewModel.select(channel: viewModel.categories[indexPath.section].channels[indexPath.row])
    }
}


private final class CategoryHeaderView: UITableViewHeaderFooterView {
    static let reuseId = "CategoryHeaderView"

    var onTap: (() -> Void)?

    private let arrowLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        contentView.addSubview(arrowLabel)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            arrowLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8.sw),
            arrowLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            arrowLabel.widthAnchor.constraint(equalToConstant: 14.sw),

            titleLabel.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: 4.sw),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8.sw)
        ])

        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(category: ChannelCategory) {
        let t = UIColor.theme
        contentView.backgroundColor = t.secondary
        titleLabel.textColor        = t.textDisabled
        arrowLabel.textColor        = t.textDisabled
        titleLabel.text             = category.name.uppercased()
        arrowLabel.text             = category.isCollapsed ? "▶" : "▾"
    }

    @objc private func handleTap() { onTap?() }
}


private final class ChannelCell: UITableViewCell {
    static let reuseId = "ChannelCell"

    private let selectedIndicator: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 2
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16.sf, weight: .regular)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let badgeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11.sf, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 8.swh
        l.layer.masksToBounds = true
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle  = .none

        contentView.addSubview(selectedIndicator)
        contentView.addSubview(iconLabel)
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            selectedIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectedIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectedIndicator.widthAnchor.constraint(equalToConstant: 4.sw),
            selectedIndicator.heightAnchor.constraint(equalToConstant: 20.sh),

            iconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            iconLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 20.swh),

            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18.swh),
            iconImageView.heightAnchor.constraint(equalToConstant: 18.swh),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 6.sw),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: badgeLabel.leadingAnchor, constant: -6.sw),

            badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),
            badgeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16.swh),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16.swh)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(channel: Mezon_Api_ChannelDescription, isSelected: Bool) {
        let t      = UIColor.theme
        let unread = channel.countMessUnread

        nameLabel.text = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel

        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        if chType.isSystemImage {
            iconLabel.isHidden    = true
            iconImageView.isHidden = false
            iconImageView.image   = UIImage(systemName: chType.icon)
        } else {
            iconLabel.isHidden    = false
            iconImageView.isHidden = true
            iconLabel.text        = chType.icon
        }

        badgeLabel.backgroundColor = .mezonUnreadBadge
        if unread > 0 {
            badgeLabel.isHidden = false
            badgeLabel.text     = unread > 99 ? "99+" : "\(unread)"
        } else {
            badgeLabel.isHidden = true
        }

        if isSelected {
            contentView.backgroundColor = t.colorActiveClan
            selectedIndicator.backgroundColor = t.channelUnread
            selectedIndicator.isHidden  = false
            nameLabel.textColor         = t.channelUnread
            iconLabel.textColor         = t.channelUnread
            iconImageView.tintColor     = t.channelUnread
        } else {
            contentView.backgroundColor = .clear
            selectedIndicator.isHidden  = true
            let color = unread > 0 ? t.channelUnread : t.channelNormal
            nameLabel.textColor     = color
            iconLabel.textColor     = color
            iconImageView.tintColor = color
        }
    }
}


private final class ChannelListHeaderView: UIView {

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let memberButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "person.2.fill")
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let separator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(memberButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16.sw),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: memberButton.leadingAnchor, constant: -8.sw),

            memberButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12.sw),
            memberButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            memberButton.widthAnchor.constraint(equalToConstant: 36.swh),
            memberButton.heightAnchor.constraint(equalToConstant: 36.swh),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        titleLabel.text = title
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor          = t.secondary
        titleLabel.textColor     = t.textStrong
        separator.backgroundColor = t.border
        memberButton.tintColor   = t.textDisabled
    }
}
