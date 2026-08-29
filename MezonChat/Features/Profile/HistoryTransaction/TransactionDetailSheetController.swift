import UIKit

final class TransactionDetailSheetController: BaseViewController {
    private var transaction: MmnTransaction
    private let walletAddress: String
    private let context: AccountContext
    
    private var senderValueLabel: UILabel?
    private var receiverValueLabel: UILabel?
    private var noteValueLabel: UILabel?
    
    init(transaction: MmnTransaction, walletAddress: String, context: AccountContext) {
        self.transaction = transaction
        self.walletAddress = walletAddress
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        if #available(iOS 13.0, *) {
            fetchDetail()
        }
    }
    
    @available(iOS 13.0, *)
    private func fetchDetail() {
        Task { @MainActor in
            do {
                let detail = try await MmnClient.shared.getTransactionDetail(hash: transaction.hash)
                self.transaction = detail
                
                let ids = self.extractUserIds(from: detail.extra_info)
                
                let fallbackSender = detail.from_username ?? detail.sender_name ?? detail.from_address ?? ""
                let finalSenderName = self.getDisplayName(for: ids.senderId, fallbackName: fallbackSender, isCurrentUser: detail.from_address == self.walletAddress)
                
                let fallbackReceiver = detail.to_username ?? detail.receiver_name ?? detail.to_address ?? ""
                let finalReceiverName = self.getDisplayName(for: ids.receiverId, fallbackName: fallbackReceiver, isCurrentUser: detail.to_address == self.walletAddress)
                
                senderValueLabel?.text = finalSenderName
                receiverValueLabel?.text = finalReceiverName
                noteValueLabel?.text = detail.note ?? "Transfer funds"
                
            } catch {
                
            }
        }
    }
    
    override func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        
        let cardView = UIView()
        cardView.backgroundColor = UIColor.theme.primary
        cardView.layer.cornerRadius = 16.swh
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)
        
        let headerContainer = UIView()
        headerContainer.backgroundColor = UIColor.theme.primary 
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(headerContainer)
        
        let headerSeparator = UIView()
        headerSeparator.backgroundColor = UIColor.theme.textDisabled.withAlphaComponent(0.2)
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerSeparator)
        
        let titleLabel = UILabel()
        titleLabel.text = L(L10n.Profile.historyDetailTitle)
        titleLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(titleLabel)
        
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage.mezonSystemImage("xmark"), for: .normal)
        closeButton.tintColor = UIColor.theme.text
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerContainer.addSubview(closeButton)
        
        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.spacing = 20.sh
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(mainStackView)
        
        NSLayoutConstraint.activate([
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            
            headerContainer.topAnchor.constraint(equalTo: cardView.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            headerContainer.heightAnchor.constraint(equalToConstant: 56.sh),
            
            headerSeparator.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),
            
            titleLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor),
            
            closeButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16.sw),
            closeButton.widthAnchor.constraint(equalToConstant: 24.swh),
            closeButton.heightAnchor.constraint(equalToConstant: 24.swh),
            
            mainStackView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 20.sh),
            mainStackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20.sw),
            mainStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20.sw),
            mainStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24.sh)
        ])
        
        func createVStack() -> UIStackView {
            let sv = UIStackView()
            sv.axis = .vertical
            sv.spacing = 6.sh
            sv.alignment = .leading
            return sv
        }
        
        func createLabel(text: String, isTitle: Bool) -> UILabel {
            let lbl = UILabel()
            lbl.text = text
            lbl.font = .systemFont(ofSize: 14.sf, weight: isTitle ? .bold : .regular)
            lbl.textColor = isTitle ? UIColor.theme.textStrong : UIColor.theme.text
            lbl.numberOfLines = 0
            return lbl
        }
        
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.alignment = .top
        row1.distribution = .fillEqually
        row1.spacing = 16.sw
        
        let left1 = createVStack()
        let txIdHeader = UIStackView()
        txIdHeader.axis = .horizontal
        txIdHeader.spacing = 6.sw
        txIdHeader.alignment = .center
        let txIdTitle = createLabel(text: L(L10n.Profile.historyTransactionId).replacingOccurrences(of: ":", with: ""), isTitle: true)
        txIdHeader.addArrangedSubview(txIdTitle)
        
        let copyIcon = UIImageView(image: UIImage.mezonSystemImage("square.on.square"))
        copyIcon.tintColor = UIColor.theme.text
        copyIcon.contentMode = .scaleAspectFit
        copyIcon.translatesAutoresizingMaskIntoConstraints = false
        copyIcon.widthAnchor.constraint(equalToConstant: 14.swh).isActive = true
        copyIcon.heightAnchor.constraint(equalToConstant: 14.swh).isActive = true
        txIdHeader.addArrangedSubview(copyIcon)
        
        txIdHeader.isUserInteractionEnabled = true
        let copyTap = UITapGestureRecognizer(target: self, action: #selector(copyHash))
        txIdHeader.addGestureRecognizer(copyTap)
        
        let txIdValue = createLabel(text: transaction.hash, isTitle: false)
        txIdValue.lineBreakMode = .byCharWrapping
        left1.addArrangedSubview(txIdHeader)
        left1.addArrangedSubview(txIdValue)
        
        let right1 = createVStack()
        let timeTitle = createLabel(text: L(L10n.Profile.historyTime), isTitle: true)
        var timeStr = ""
        if let timestamp = transaction.transaction_timestamp {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy HH:mm"
            timeStr = formatter.string(from: date)
        }
        let timeValue = createLabel(text: timeStr, isTitle: false)
        right1.addArrangedSubview(timeTitle)
        right1.addArrangedSubview(timeValue)
        
        row1.addArrangedSubview(left1)
        row1.addArrangedSubview(right1)
        
        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.alignment = .top
        row2.distribution = .fillEqually
        row2.spacing = 16.sw
        
        let ids = self.extractUserIds(from: transaction.extra_info)
        
        let left2 = createVStack()
        let senderTitle = createLabel(text: L(L10n.Profile.historySenderName), isTitle: true)
        let fallbackSender = transaction.from_username ?? transaction.sender_name ?? transaction.from_address ?? ""
        let finalSenderName = self.getDisplayName(for: ids.senderId, fallbackName: fallbackSender, isCurrentUser: transaction.from_address == self.walletAddress)
        
        let senderValue = createLabel(text: finalSenderName, isTitle: false) 
        senderValue.lineBreakMode = .byCharWrapping
        self.senderValueLabel = senderValue
        left2.addArrangedSubview(senderTitle)
        left2.addArrangedSubview(senderValue)
        
        let right2 = createVStack()
        let receiverTitle = createLabel(text: L(L10n.Profile.historyReceiverName), isTitle: true)
        let fallbackReceiver = transaction.to_username ?? transaction.receiver_name ?? transaction.to_address ?? ""
        let finalReceiverName = self.getDisplayName(for: ids.receiverId, fallbackName: fallbackReceiver, isCurrentUser: transaction.to_address == self.walletAddress)
        
        let receiverValue = createLabel(text: finalReceiverName, isTitle: false)
        receiverValue.lineBreakMode = .byCharWrapping
        self.receiverValueLabel = receiverValue
        right2.addArrangedSubview(receiverTitle)
        right2.addArrangedSubview(receiverValue)
        
        row2.addArrangedSubview(left2)
        row2.addArrangedSubview(right2)
        
        let row3 = UIStackView()
        row3.axis = .horizontal
        row3.alignment = .top
        row3.distribution = .fillEqually
        row3.spacing = 16.sw
        
        let left3 = createVStack()
        let amountTitle = createLabel(text: L(L10n.Profile.transferAmount), isTitle: true)
        let valueStr = String(transaction.value ?? 0)
        let formattedValue = BalanceFormatter.format(valueStr)
        let amountValue = createLabel(text: "\(formattedValue) \(L(L10n.Profile.currency))", isTitle: false)
        left3.addArrangedSubview(amountTitle)
        left3.addArrangedSubview(amountValue)
        
        let right3 = createVStack()
        let noteTitle = createLabel(text: L(L10n.Profile.sendTokenNote), isTitle: true)
        let finalNote = transaction.note ?? L(L10n.Profile.sendTokenDefaultNote)
        let noteValue = createLabel(text: finalNote, isTitle: false)
        self.noteValueLabel = noteValue
        
        right3.addArrangedSubview(noteTitle)
        right3.addArrangedSubview(noteValue)
        
        row3.addArrangedSubview(left3)
        row3.addArrangedSubview(right3)
        
        mainStackView.addArrangedSubview(row1)
        mainStackView.addArrangedSubview(row2)
        mainStackView.addArrangedSubview(row3)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        view.addGestureRecognizer(tap)
        
        let cardTap = UITapGestureRecognizer(target: self, action: nil)
        cardView.addGestureRecognizer(cardTap)
    }
    
    @objc private func copyHash() {
        UIPasteboard.general.string = transaction.hash
        Toast.success(L(L10n.Profile.historyTransactionIdCopied)) 
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    private func extractUserIds(from extraInfo: String?) -> (senderId: String?, receiverId: String?) {
        guard let extraStr = extraInfo,
              let data = extraStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        
        var senderId: String? = nil
        var receiverId: String? = nil
        
        if let uid = dict["UserSenderId"] as? String { senderId = uid }
        else if let uidInt = dict["UserSenderId"] as? Int { senderId = String(uidInt) }
        else if let uidInt = dict["UserSenderId"] as? Int64 { senderId = String(uidInt) }
        
        if let uid = dict["UserReceiverId"] as? String { receiverId = uid }
        else if let uidInt = dict["UserReceiverId"] as? Int { receiverId = String(uidInt) }
        else if let uidInt = dict["UserReceiverId"] as? Int64 { receiverId = String(uidInt) }
        
        return (senderId, receiverId)
    }
    
    private func getDisplayName(for userId: String?, fallbackName: String, isCurrentUser: Bool) -> String {
        if isCurrentUser {
            let currentName = context.currentUser?.displayName ?? context.currentUser?.username ?? ""
            if !currentName.isEmpty { return currentName }
        }
        
        var finalName = fallbackName
        if let uid = userId, let p = context.account.postbox.read({ tx in tx.getProfile(userId: uid) }) {
            if let name = p.username ?? p.displayName, !name.isEmpty {
                finalName = name
            }
        }
        
        return finalName
    }
}
