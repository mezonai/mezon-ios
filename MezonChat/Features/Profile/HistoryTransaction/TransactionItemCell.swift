import UIKit

final class TransactionItemCell: UITableViewCell {
    static let reuseId = "TransactionItemCell"
    
    private let containerView = UIView()
    private let iconContainer = UIView()
    private let chevronIcon = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let codeLabel = UILabel()
    private let timeLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupUI() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.theme.secondary
        containerView.layer.cornerRadius = 12.swh
        contentView.addSubview(containerView)
        
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 20.swh
        containerView.addSubview(iconContainer)
        
        chevronIcon.translatesAutoresizingMaskIntoConstraints = false
        chevronIcon.contentMode = .scaleAspectFit
        iconContainer.addSubview(chevronIcon)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .bold)
        containerView.addSubview(titleLabel)
        
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12.sf)
        statusLabel.textColor = UIColor.theme.textDisabled
        containerView.addSubview(statusLabel)
        
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.font = .systemFont(ofSize: 13.sf)
        codeLabel.textColor = UIColor.theme.textStrong
        codeLabel.textAlignment = .right
        containerView.addSubview(codeLabel)
        
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 12.sf)
        timeLabel.textColor = UIColor.theme.textDisabled
        timeLabel.textAlignment = .right
        containerView.addSubview(timeLabel)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4.sh),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4.sh),
            
            iconContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12.sw),
            iconContainer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 40.swh),
            iconContainer.heightAnchor.constraint(equalToConstant: 40.swh),
            
            chevronIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            chevronIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            chevronIcon.widthAnchor.constraint(equalToConstant: 20.swh),
            chevronIcon.heightAnchor.constraint(equalToConstant: 20.swh),
            
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12.sh),
            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12.sw),
            
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4.sh),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12.sh),
            
            codeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            codeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12.sw),
            
            timeLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12.sw)
        ])
    }
    
    func configure(with transaction: MmnTransaction, walletAddress: String) {
        let isIncoming = transaction.from_address != walletAddress
        
        if isIncoming {
            iconContainer.backgroundColor = UIColor(hex: 0x14532D, alpha: 0.2) 
            chevronIcon.image = UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate)
            chevronIcon.tintColor = UIColor.theme.textSuccess
            titleLabel.textColor = UIColor.theme.textSuccess
            statusLabel.text = L(L10n.Profile.historyReceived)
        } else {
            iconContainer.backgroundColor = UIColor(hex: 0x7F1D1D, alpha: 0.2) 
            chevronIcon.image = UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate)
            chevronIcon.tintColor = .systemRed
            titleLabel.textColor = .systemRed
            statusLabel.text = L(L10n.Profile.historySent)
        }
        
        let valueStr = String(transaction.value ?? 0)
        let formattedValue = BalanceFormatter.format(valueStr)
        titleLabel.text = "\(formattedValue) \(L(L10n.Profile.currency))"
        
        let hashLength = 8
        let shortHash = transaction.hash.count > hashLength ? String(transaction.hash.suffix(hashLength)) : transaction.hash
        codeLabel.text = "ID: #\(shortHash)"
        
        if let timestamp = transaction.transaction_timestamp {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy HH:mm"
            timeLabel.text = formatter.string(from: date)
        } else {
            timeLabel.text = "--/--/---- --:--"
        }
    }
}
