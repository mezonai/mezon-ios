import UIKit

@MainActor
final class AuditLogFilterUserViewController: BaseViewController {
    
    private let context: AccountContext
    private let clanId: Int64
    private let onUserSelected: (ClanMemberRecord?) -> Void
    private let currentUser: ClanMemberRecord?
    
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    
    private var allMembers: [ClanMemberRecord] = []
    private var filteredMembers: [ClanMemberRecord] = []
    private var searchWorkItem: DispatchWorkItem?
    
    init(context: AccountContext, clanId: Int64, currentUser: ClanMemberRecord?, onUserSelected: @escaping (ClanMemberRecord?) -> Void) {
        self.context = context
        self.clanId = clanId
        self.currentUser = currentUser
        self.onUserSelected = onUserSelected
        super.init(navigationBarPresentationData: nil)
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupSearchBar()
        setupTableView()
        fetchMembers()
    }
    
    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        
        titleLabel.text = L(L10n.AuditLog.filterByUser)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        
        closeButton.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = UIColor.theme.textStrong
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        [titleLabel, closeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),
            
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44.swh),
            closeButton.heightAnchor.constraint(equalToConstant: 44.swh)
        ])
    }
    
    private func setupSearchBar() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.backgroundImage = UIImage()
        searchBar.isTranslucent = false
        searchBar.barTintColor = UIColor.theme.secondary
        searchBar.backgroundColor = UIColor.theme.secondary
        searchBar.layer.cornerRadius = 16
        searchBar.layer.masksToBounds = true
        searchBar.searchTextField.backgroundColor = .clear
        searchBar.searchTextField.textColor = UIColor.theme.textStrong
        
        searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Common.search),
            attributes: [
                .foregroundColor: UIColor.theme.textDisabled,
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .regular)
            ]
        )
        
        if let leftIconView = searchBar.searchTextField.leftView as? UIImageView {
            leftIconView.image = leftIconView.image?.withRenderingMode(.alwaysTemplate)
            leftIconView.tintColor = UIColor.theme.textDisabled
        }
        
        if let rightButton = searchBar.searchTextField.value(forKey: "clearButton") as? UIButton {
            rightButton.setImage(rightButton.imageView?.image?.withRenderingMode(.alwaysTemplate), for: .normal)
            rightButton.tintColor = UIColor.theme.textDisabled
        }
        view.addSubview(searchBar)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            searchBar.heightAnchor.constraint(equalToConstant: 44.sh)
        ])
    }
    
    private func setupTableView() {
        tableView.backgroundColor = UIColor.theme.secondary
        tableView.layer.cornerRadius = 16
        tableView.layer.masksToBounds = true
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.theme.border
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UserCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorInset = .zero
        tableView.layoutMargins = .zero
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 16.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16.sh)
        ])
    }
    
    private func fetchMembers() {
        Task {
            let members = context.account.postbox.read { $0.getClanMembers(clanId: clanId) }
            self.allMembers = members.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            self.filteredMembers = self.allMembers
            self.tableView.reloadData()
        }
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

extension AuditLogFilterUserViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        return filteredMembers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        
        if indexPath.section == 0 {
            cell.textLabel?.text = L(L10n.AuditLog.allUsers)
            cell.imageView?.image = nil
            if currentUser == nil {
                cell.accessoryType = .checkmark
                cell.tintColor = UIColor.theme.bgViolet
            } else {
                cell.accessoryType = .none
            }
        } else {
            let member = filteredMembers[indexPath.row]
            cell.textLabel?.text = member.username
            if currentUser?.userId == member.userId {
                cell.accessoryType = .checkmark
                cell.tintColor = UIColor.theme.bgViolet
            } else {
                cell.accessoryType = .none
            }
        }
        
        cell.textLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        cell.textLabel?.textColor = UIColor.theme.textStrong
        
        cell.separatorInset = .zero
        cell.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            onUserSelected(nil)
        } else {
            onUserSelected(filteredMembers[indexPath.row])
        }
        dismiss(animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 56.sh
    }
}

extension AuditLogFilterUserViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchWorkItem?.cancel()
        
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedText.isEmpty {
                self.filteredMembers = self.allMembers
            } else {
                self.filteredMembers = self.allMembers.filter { $0.username.localizedCaseInsensitiveContains(trimmedText) }
            }
            self.tableView.reloadData()
        }
        
        searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
