import UIKit
import Combine
import SwiftProtobuf

final class MessagesViewController: BaseViewController {

    private let viewModel: MessagesViewModel
    private let sharedContext: SharedAccountContext

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
        l.text = L(L10n.Tab.messages)
        return l
    }()

    private lazy var addFriendButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "person.badge.plus")
        config.title = " • \(L(L10n.DirectMessage.addFriend))"
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var searchButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "magnifyingglass")
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.rowHeight = 72
        tv.showsVerticalScrollIndicator = true
        tv.register(DmListItemCell.self, forCellReuseIdentifier: DmListItemCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        return tv
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.translatesAutoresizingMaskIntoConstraints = false
        ai.hidesWhenStopped = true
        return ai
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15)
        l.textColor = .mezonTextSecondary
        l.textAlignment = .center
        l.text = L(L10n.ChannelMessages.emptyMessages)
        l.isHidden = true
        return l
    }()

    private var headerTopConstraint: NSLayoutConstraint?

    init(viewModel: MessagesViewModel, sharedContext: SharedAccountContext) {
        self.viewModel = viewModel
        self.sharedContext = sharedContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let top = view.safeAreaInsets.top
        let statusBarOnly = min(top, 59)
        headerTopConstraint?.constant = statusBarOnly
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await viewModel.fetchDirectMessages() }
    }

    override func setupUI() {
        view.backgroundColor = .mezonBackground
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(addFriendButton)
        headerView.addSubview(searchButton)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(emptyLabel)

        headerTopConstraint = headerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 59)
        NSLayoutConstraint.activate([
            headerTopConstraint!,
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            searchButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            searchButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            addFriendButton.trailingAnchor.constraint(equalTo: searchButton.leadingAnchor, constant: -8),
            addFriendButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func setupBindings() {
        viewModel.$directMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)

        viewModel.$isEmpty
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                self?.emptyLabel.isHidden = !empty || (self?.viewModel.isLoading ?? false)
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.loadingIndicator.startAnimating() : self?.loadingIndicator.stopAnimating()
                self?.emptyLabel.isHidden = loading
            }
            .store(in: &cancellables)
    }
}

extension MessagesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.directMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DmListItemCell.reuseId, for: indexPath) as! DmListItemCell
        let channel = viewModel.directMessages[indexPath.row]
        cell.configure(channel: channel, currentUserId: sharedContext.currentUser?.id)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = viewModel.directMessages[indexPath.row]
        let vm = ChannelMessagesViewModel(clanId: 0, channel: channel, sharedContext: sharedContext)
        let chatVC = ChannelMessagesViewController(viewModel: vm)
        navigationController?.pushViewController(chatVC, animated: true)
    }
}
