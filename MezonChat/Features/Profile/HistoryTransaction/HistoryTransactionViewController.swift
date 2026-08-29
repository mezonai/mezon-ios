import UIKit

final class HistoryTransactionViewController: BaseViewController {
    
    private let context: AccountContext
    private var transactions: [MmnTransaction] = []
    private var isLoadMore = false
    private var hasMore = true
    private var activeTab: FilterType = .all
    private var walletDetail: WalletDetail?
    private var walletAddress: String?
    
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    
    private let cardView = UIView()
    private let debitAccountLabel = UILabel()
    private let debitNameLabel = UILabel()
    private let balanceTitleLabel = UILabel()
    private let balanceValueLabel = UILabel()
    
    private let historyTitleLabel = UILabel()
    private let tabContainer = UIView()
    private let allTabButton = UIButton(type: .system)
    private let incomingTabButton = UIButton(type: .system)
    private let outgoingTabButton = UIButton(type: .system)
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView.mezonMedium()
    private let footerSpinner = UIActivityIndicatorView.mezonMedium()
    
    enum FilterType: String {
        case all = "all"
        case incoming = "incoming"
        case outgoing = "outgoing"
    }
    
    private var cachedTransactions: [FilterType: [MmnTransaction]] = [:]
    private var cachedHasMore: [FilterType: Bool] = [:]
    private var cachedScrollOffsets: [FilterType: CGFloat] = [:]
    
    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        
        setupHeader()
        setupCard()
        setupTabs()
        setupTableView()
        
        if #available(iOS 13.0, *) {
            fetchInitial()
        }
    }
    
    override func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
        
        historyTitleLabel.textColor = UIColor.theme.textStrong
        tabContainer.backgroundColor = UIColor.theme.secondary
        
        tableView.backgroundColor = UIColor.theme.primary
        updateTabSelection()
        tableView.reloadData()
    }
    
    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        titleLabel.text = L(L10n.Profile.historyTransaction)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center

        [backButton, titleLabel].forEach {
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
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }
    
    private func setupCard() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 16.swh
        cardView.clipsToBounds = true
        view.addSubview(cardView)
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.theme.primaryGradient.cgColor,
            UIColor.theme.secondaryLight.cgColor,
            UIColor.theme.secondary.withAlphaComponent(0.5).cgColor
        ]
        gradientLayer.locations = [0.0, 0.5, 1.0]
        gradientLayer.startPoint = CGPoint(x: 1, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 32.sw, height: 100.sh)
        cardView.layer.insertSublayer(gradientLayer, at: 0)
        
        debitAccountLabel.text = L(L10n.Profile.sendTokenDebitAccount)
        debitAccountLabel.font = .systemFont(ofSize: 14.sf)
        debitAccountLabel.textColor = UIColor.theme.text
        debitAccountLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(debitAccountLabel)
        
        debitNameLabel.font = .systemFont(ofSize: 14.sf)
        debitNameLabel.textColor = UIColor.theme.text
        debitNameLabel.translatesAutoresizingMaskIntoConstraints = false
        debitNameLabel.text = context.currentUser?.displayName ?? context.currentUser?.username
        cardView.addSubview(debitNameLabel)
        
        balanceTitleLabel.text = L(L10n.Profile.balance)
        balanceTitleLabel.font = .systemFont(ofSize: 14.sf)
        balanceTitleLabel.textColor = UIColor.theme.text
        balanceTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(balanceTitleLabel)
        
        balanceValueLabel.font = .systemFont(ofSize: 18.sf, weight: .semibold)
        balanceValueLabel.textColor = UIColor.theme.text
        balanceValueLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceValueLabel.text = "0 \(L(L10n.Profile.currency))"
        cardView.addSubview(balanceValueLabel)
        
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16.sh),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            cardView.heightAnchor.constraint(equalToConstant: 100.sh),
            
            debitAccountLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20.sh),
            debitAccountLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16.sw),
            
            debitNameLabel.topAnchor.constraint(equalTo: debitAccountLabel.topAnchor),
            debitNameLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16.sw),
            
            balanceTitleLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -20.sh),
            balanceTitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16.sw),
            
            balanceValueLabel.bottomAnchor.constraint(equalTo: balanceTitleLabel.bottomAnchor),
            balanceValueLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16.sw)
        ])
    }
    
    private func setupTabs() {
        historyTitleLabel.text = L(L10n.Profile.historyTransaction)
        historyTitleLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        historyTitleLabel.textColor = UIColor.theme.textStrong
        historyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(historyTitleLabel)
        
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.backgroundColor = UIColor.theme.secondary
        tabContainer.layer.cornerRadius = 24.swh
        view.addSubview(tabContainer)
        
        [allTabButton, incomingTabButton, outgoingTabButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
            $0.layer.cornerRadius = 20.swh
            $0.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabContainer.addSubview($0)
        }
        
        allTabButton.setTitle(L(L10n.Profile.historyAll), for: .normal)
        incomingTabButton.setTitle(L(L10n.Profile.historyIncoming), for: .normal)
        outgoingTabButton.setTitle(L(L10n.Profile.historyOutgoing), for: .normal)
        
        NSLayoutConstraint.activate([
            historyTitleLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 24.sh),
            historyTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            
            tabContainer.topAnchor.constraint(equalTo: historyTitleLabel.bottomAnchor, constant: 16.sh),
            tabContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tabContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            tabContainer.heightAnchor.constraint(equalToConstant: 48.sh),
            
            allTabButton.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: 4.sw),
            allTabButton.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 4.sh),
            allTabButton.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -4.sh),
            
            incomingTabButton.leadingAnchor.constraint(equalTo: allTabButton.trailingAnchor, constant: 4.sw),
            incomingTabButton.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 4.sh),
            incomingTabButton.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -4.sh),
            incomingTabButton.widthAnchor.constraint(equalTo: allTabButton.widthAnchor),
            
            outgoingTabButton.leadingAnchor.constraint(equalTo: incomingTabButton.trailingAnchor, constant: 4.sw),
            outgoingTabButton.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: -4.sw),
            outgoingTabButton.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 4.sh),
            outgoingTabButton.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -4.sh),
            outgoingTabButton.widthAnchor.constraint(equalTo: allTabButton.widthAnchor)
        ])
        
        updateTabSelection()
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = UIColor.theme.primary
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TransactionItemCell.self, forCellReuseIdentifier: TransactionItemCell.reuseId)
        view.addSubview(tableView)
        
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)
        
        let footerView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50.sh))
        footerSpinner.translatesAutoresizingMaskIntoConstraints = false
        footerSpinner.hidesWhenStopped = true
        footerView.addSubview(footerSpinner)
        footerSpinner.centerXAnchor.constraint(equalTo: footerView.centerXAnchor).isActive = true
        footerSpinner.centerYAnchor.constraint(equalTo: footerView.centerYAnchor).isActive = true
        tableView.tableFooterView = footerView
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: 16.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            spinner.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])
    }
    
    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func tabTapped(_ sender: UIButton) {
        if #available(iOS 13.0, *) {
            cachedScrollOffsets[activeTab] = tableView.contentOffset.y
        
            if sender == allTabButton { activeTab = .all }
            else if sender == incomingTabButton { activeTab = .incoming }
            else if sender == outgoingTabButton { activeTab = .outgoing }
        
            updateTabSelection()
            fetchInitial()
        }
    }
    
    private func updateTabSelection() {
        allTabButton.backgroundColor = activeTab == .all ? UIColor.theme.primary : .clear
        allTabButton.setTitleColor(activeTab == .all ? UIColor.theme.textStrong : UIColor.theme.textDisabled, for: .normal)
        
        incomingTabButton.backgroundColor = activeTab == .incoming ? UIColor.theme.primary : .clear
        incomingTabButton.setTitleColor(activeTab == .incoming ? UIColor.theme.textStrong : UIColor.theme.textDisabled, for: .normal)
        
        outgoingTabButton.backgroundColor = activeTab == .outgoing ? UIColor.theme.primary : .clear
        outgoingTabButton.setTitleColor(activeTab == .outgoing ? UIColor.theme.textStrong : UIColor.theme.textDisabled, for: .normal)
    }
    
    private var fetchTask: CancelHandle?
    
    @available(iOS 13.0, *)
    private func fetchInitial() {
        fetchTask?.cancel()
        
        if let cached = cachedTransactions[activeTab] {
            self.transactions = cached
            self.hasMore = cachedHasMore[activeTab] ?? false
            self.tableView.reloadData()
            
            self.tableView.layoutIfNeeded()
            let offset = self.cachedScrollOffsets[self.activeTab] ?? 0
            if offset > 0 {
                let maxOffset = max(0, self.tableView.contentSize.height - self.tableView.bounds.height + self.tableView.contentInset.bottom)
                let safeOffset = min(offset, maxOffset)
                self.tableView.setContentOffset(CGPoint(x: 0, y: safeOffset), animated: false)
            } else {
                self.tableView.setContentOffset(.zero, animated: false)
            }
            return
        } else {
            transactions.removeAll()
            self.tableView.reloadData()
            spinner.startAnimating()
        }
        
        hasMore = true
        isLoadMore = false
        footerSpinner.stopAnimating()
        
        let fetchTaskWork = Task {
            do {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                
                if walletDetail == nil, let userId = context.currentUser?.id {
                    walletDetail = try await MmnClient.shared.getAccountByUserId(userId)
                    walletAddress = walletDetail?.address
                    let balanceStr = String(walletDetail?.balance ?? "0")
                    let formatted = BalanceFormatter.format(balanceStr)
                    balanceValueLabel.text = "\(formatted) \(L(L10n.Profile.currency))"
                }
                
                guard let addr = walletAddress else {
                    spinner.stopAnimating()
                    return
                }
                
                let results = try await MmnClient.shared.getTransactionHistory(
                    address: addr,
                    filter: activeTab.rawValue,
                    timeStamp: nil,
                    lastHash: nil
                )
                
                if Task.isCancelled { return }
                
                self.transactions = results
                self.hasMore = !results.isEmpty
                self.cachedTransactions[self.activeTab] = results
                self.cachedHasMore[self.activeTab] = self.hasMore
                self.tableView.reloadData()
            } catch {
                if Task.isCancelled { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                Toast.error(error.localizedDescription)
            }
            if !Task.isCancelled {
                spinner.stopAnimating()
            }
        }
        
        fetchTask = CancelHandle { fetchTaskWork.cancel() }
    }
    
    @available(iOS 13.0, *)
    private func fetchLoadMore() {
        guard hasMore, !isLoadMore else { return }
        isLoadMore = true
        footerSpinner.startAnimating()
        
        let fetchTaskWork = Task {
            do {
                guard let addr = walletAddress else {
                    footerSpinner.stopAnimating()
                    isLoadMore = false
                    return
                }
                
                var timeStampStr: String? = nil
                var lastHash: String? = nil
                
                let lastItem = transactions.last
                if let ts = lastItem?.transaction_timestamp {
                    let date = Date(timeIntervalSince1970: TimeInterval(ts))
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    timeStampStr = formatter.string(from: date)
                }
                lastHash = lastItem?.hash
                
                let results = try await MmnClient.shared.getTransactionHistory(
                    address: addr,
                    filter: activeTab.rawValue,
                    timeStamp: timeStampStr,
                    lastHash: lastHash
                )
                
                if Task.isCancelled { return }
                
                self.transactions.append(contentsOf: results)
                self.hasMore = !results.isEmpty
                self.cachedTransactions[self.activeTab] = self.transactions
                self.cachedHasMore[self.activeTab] = self.hasMore
                self.tableView.reloadData()
            } catch {
                if Task.isCancelled { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                Toast.error(error.localizedDescription)
            }
            if !Task.isCancelled {
                isLoadMore = false
                footerSpinner.stopAnimating()
            }
        }
        
        fetchTask = CancelHandle { fetchTaskWork.cancel() }
    }
}

extension HistoryTransactionViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TransactionItemCell.reuseId, for: indexPath) as! TransactionItemCell
        let tx = transactions[indexPath.row]
        cell.configure(with: tx, walletAddress: walletAddress ?? "")
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let tx = transactions[indexPath.row]
        let sheet = TransactionDetailSheetController(transaction: tx, walletAddress: walletAddress ?? "", context: context)
        sheet.modalPresentationStyle = .overFullScreen
        sheet.modalTransitionStyle = .crossDissolve
        present(sheet, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72.sh
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if #available(iOS 13.0, *) {
            guard !transactions.isEmpty else { return }
            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let height = scrollView.frame.size.height
        
            if offsetY > contentHeight - height - 100 {
                fetchLoadMore()
            }
        }
    }
}
