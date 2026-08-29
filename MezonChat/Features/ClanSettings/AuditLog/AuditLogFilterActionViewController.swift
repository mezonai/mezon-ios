import UIKit

final class AuditLogFilterActionViewController: BaseViewController {
    
    private let context: AccountContext
    private let clanId: Int64
    private let onActionSelected: (AuditLogAction) -> Void
    private let currentAction: AuditLogAction
    
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    
    private let actions = AuditLogAction.allCases
    
    init(context: AccountContext, clanId: Int64, currentAction: AuditLogAction, onActionSelected: @escaping (AuditLogAction) -> Void) {
        self.context = context
        self.clanId = clanId
        self.currentAction = currentAction
        self.onActionSelected = onActionSelected
        super.init(navigationBarPresentationData: nil)
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupTableView()
    }
    
    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        
        titleLabel.text = L(L10n.AuditLog.filterByAction)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        
        closeButton.setImage(UIImage.mezonSystemImage("xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
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
    
    private func setupTableView() {
        tableView.backgroundColor = UIColor.theme.secondary
        tableView.layer.cornerRadius = 16
        tableView.layer.masksToBounds = true
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.theme.border
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ActionCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorInset = .zero
        tableView.layoutMargins = .zero
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16.sh)
        ])
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

extension AuditLogFilterActionViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return actions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        
        let action = actions[indexPath.row]
        cell.textLabel?.text = action.localizedString
        cell.textLabel?.font = .systemFont(ofSize: 14.sf, weight: .medium)
        cell.textLabel?.textColor = UIColor.theme.textStrong
        
        if action == currentAction {
            cell.accessoryType = .checkmark
            cell.tintColor = UIColor.theme.bgViolet
        } else {
            cell.accessoryType = .none
        }
        
        cell.separatorInset = .zero
        cell.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onActionSelected(actions[indexPath.row])
        dismiss(animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 56.sh
    }
}
