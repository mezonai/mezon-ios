import UIKit

@MainActor
final class AuditLogViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64

    private var logs: [Mezon_Api_AuditLog] = []
    private var members: [ClanMemberRecord] = []
    
    private var selectedAction: AuditLogAction = .allActionAudit
    private var selectedUser: ClanMemberRecord? = nil
    private var selectedDate: Date = Date()
    
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let filterButton = UIButton(type: .system)
    
    private let filterSummaryContainer = UIView()
    private let filterUserLabel = UILabel()
    private let filterActionLabel = UILabel()
    
    private let datePickerContainer = UIView()
    private let datePicker = UIDatePicker()
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    
    private let emptyView = UIView()
    private let emptyIcon = UIImageView()
    private let emptyLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupFilterSummary()
        setupDatePicker()
        setupTableView()
        setupEmptyView()
        setupActivityIndicator()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        fetchMembers()
        fetchAuditLogs()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func applyTheme() {
        let currentTheme = ThemeManager.shared.current
        let effectiveTheme = currentTheme == .system ? (UITraitCollection.current.userInterfaceStyle == .dark ? AppTheme.dark : AppTheme.light) : currentTheme
        self.overrideUserInterfaceStyle = (effectiveTheme == .light || effectiveTheme == .sunrise) ? .light : .dark
        view.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
        filterButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        
        filterSummaryContainer.backgroundColor = UIColor.theme.secondary
        filterUserLabel.textColor = UIColor.theme.textStrong
        filterActionLabel.textColor = UIColor.theme.textStrong
        
        emptyIcon.tintColor = UIColor.theme.textDisabled
        emptyLabel.textColor = UIColor.theme.textDisabled
        
        tableView.reloadData()
    }
    
    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        
        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        titleLabel.text = L(L10n.AuditLog.title)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        
        filterButton.setTitle(L(L10n.AuditLog.filterBtn), for: .normal)
        filterButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
        filterButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        
        if #available(iOS 14.0, *) {
            let filterUserAction = UIAction(title: L(L10n.AuditLog.filterByUser), image: UIImage(systemName: "person")) { [weak self] _ in
                self?.openFilterUser()
            }
            let filterActionAction = UIAction(title: L(L10n.AuditLog.filterByAction), image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                self?.openFilterAction()
            }
            let menu = UIMenu(title: "", children: [filterUserAction, filterActionAction])
            filterButton.menu = menu
            filterButton.showsMenuAsPrimaryAction = true
        } else {
            filterButton.addTarget(self, action: #selector(filterFallbackTapped), for: .touchUpInside)
        }
        
        [backButton, titleLabel, filterButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),
            
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),
            
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            filterButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            filterButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }
    

    
    private func setupFilterSummary() {
        filterSummaryContainer.backgroundColor = UIColor.theme.secondary
        filterSummaryContainer.layer.cornerRadius = 8
        filterSummaryContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterSummaryContainer)
        
        filterUserLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        filterUserLabel.textColor = UIColor.theme.textStrong
        
        filterActionLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        filterActionLabel.textColor = UIColor.theme.textStrong
        
        let divider = UIView()
        divider.backgroundColor = UIColor.theme.border
        divider.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = UIStackView(arrangedSubviews: [filterUserLabel, divider, filterActionLabel, UIView()])
        stack.axis = .horizontal
        stack.spacing = 8.sw
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        filterSummaryContainer.addSubview(stack)
        
        NSLayoutConstraint.activate([
            filterSummaryContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8.sh),
            filterSummaryContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            filterSummaryContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            filterSummaryContainer.heightAnchor.constraint(equalToConstant: 44.sh),
            
            stack.leadingAnchor.constraint(equalTo: filterSummaryContainer.leadingAnchor, constant: 12.sw),
            stack.trailingAnchor.constraint(equalTo: filterSummaryContainer.trailingAnchor, constant: -12.sw),
            stack.topAnchor.constraint(equalTo: filterSummaryContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: filterSummaryContainer.bottomAnchor),
            
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 16.sh)
        ])
        
        updateFilterSummaryText()
    }
    
    private func updateFilterSummaryText() {
        filterUserLabel.text = selectedUser?.username ?? L(L10n.AuditLog.allUsers)
        filterActionLabel.text = selectedAction == .allActionAudit ? L(L10n.AuditLog.allActions) : selectedAction.localizedString
    }
    
    private func setupDatePicker() {
        datePickerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(datePickerContainer)
        
        datePicker.datePickerMode = .date
        if #available(iOS 14.0, *) {
            datePicker.preferredDatePickerStyle = .compact
        }
        datePicker.maximumDate = Date()
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        
        datePickerContainer.addSubview(datePicker)
        
        NSLayoutConstraint.activate([
            datePickerContainer.topAnchor.constraint(equalTo: filterSummaryContainer.bottomAnchor, constant: 12.sh),
            datePickerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            datePickerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            datePickerContainer.heightAnchor.constraint(equalToConstant: 44.sh),
            
            datePicker.leadingAnchor.constraint(equalTo: datePickerContainer.leadingAnchor),
            datePicker.centerYAnchor.constraint(equalTo: datePickerContainer.centerYAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AuditLogItemCell.self, forCellReuseIdentifier: AuditLogItemCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.showsVerticalScrollIndicator = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: datePickerContainer.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)
        
        emptyIcon.image = UIImage(named: "ClanSetting/AuditLog")?.withRenderingMode(.alwaysTemplate)
        emptyIcon.tintColor = UIColor.theme.textDisabled
        emptyIcon.contentMode = .scaleAspectFit
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        
        emptyLabel.text = L(L10n.AuditLog.empty)
        emptyLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        emptyLabel.textColor = UIColor.theme.textDisabled
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        emptyView.addSubview(emptyIcon)
        emptyView.addSubview(emptyLabel)
        
        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32.sw),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32.sw),
            
            emptyIcon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyIcon.topAnchor.constraint(equalTo: emptyView.topAnchor),
            emptyIcon.widthAnchor.constraint(equalToConstant: 100.swh),
            emptyIcon.heightAnchor.constraint(equalToConstant: 100.swh),
            
            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 16.sh),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyView.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyView.trailingAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyView.bottomAnchor)
        ])
    }
    
    private func setupActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor.theme.textStrong
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])
    }
    
    private func fetchMembers() {
        self.members = context.account.postbox.read { $0.getClanMembers(clanId: self.clanId) }
    }
    
    private func fetchAuditLogs() {
        activityIndicator.startAnimating()
        tableView.isHidden = true
        emptyView.isHidden = true
        Task { [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            
            do {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "dd-MM-yyyy"
                let dateStr = formatter.string(from: self.selectedDate)
                
                var req = Mezon_Api_ListAuditLogRequest()
                req.clanID = self.clanId
                req.dateLog = dateStr
                req.actionLog = self.selectedAction == .allActionAudit ? "" : self.selectedAction.rawValue
                
                if let uid = self.selectedUser?.userId, uid != 0 {
                    req.userID = uid
                }
                
                let response = try await MezonHTTPClient.shared.listAuditLog(request: req, token: token)
                self.logs = response.logs
                self.reloadUI()
            } catch let error as MezonError {
                if case .httpError(let code, let msg) = error {
                    Toast.error("ListAuditLog: HTTP \(code): \(msg)")
                } else {
                    Toast.error("ListAuditLog: \(error.localizedDescription)")
                }
                self.logs = []
                self.reloadUI()
            } catch {
                Toast.error("ListAuditLog: \(error.localizedDescription)")
                self.logs = []
                self.reloadUI()
            }
        }
    }
    
    private func reloadUI() {
        activityIndicator.stopAnimating()
        tableView.reloadData()
        emptyView.isHidden = !logs.isEmpty
        tableView.isHidden = logs.isEmpty
        
        if !logs.isEmpty {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        }
    }
    
    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }
    

    
    @objc private func filterFallbackTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L(L10n.AuditLog.filterByUser), style: .default, handler: { [weak self] _ in
            self?.openFilterUser()
        }))
        alert.addAction(UIAlertAction(title: L(L10n.AuditLog.filterByAction), style: .default, handler: { [weak self] _ in
            self?.openFilterAction()
        }))
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = filterButton
            popover.sourceRect = filterButton.bounds
        }
        present(alert, animated: true)
    }
    
    @objc private func dateChanged() {
        selectedDate = datePicker.date
        fetchAuditLogs()
    }
    
    private func openFilterUser() {
        let vc = AuditLogFilterUserViewController(context: context, clanId: clanId, currentUser: selectedUser) { [weak self] user in
            self?.selectedUser = user
            self?.updateFilterSummaryText()
            self?.fetchAuditLogs()
        }
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            vc.sheetPresentationController?.detents = [.medium(), .large()]
        }
        present(vc, animated: true)
    }
    
    private func openFilterAction() {
        let vc = AuditLogFilterActionViewController(context: context, clanId: clanId, currentAction: selectedAction) { [weak self] action in
            self?.selectedAction = action
            self?.updateFilterSummaryText()
            self?.fetchAuditLogs()
        }
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            vc.sheetPresentationController?.detents = [.medium(), .large()]
        }
        present(vc, animated: true)
    }
}

extension AuditLogViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return logs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AuditLogItemCell.reuseId, for: indexPath) as! AuditLogItemCell
        let log = logs[indexPath.row]
        let member = members.first { $0.userId == log.userID }
        let isLast = indexPath.row == logs.count - 1
        cell.configure(with: log, memberInfo: member, isLast: isLast)
        return cell
    }
}
