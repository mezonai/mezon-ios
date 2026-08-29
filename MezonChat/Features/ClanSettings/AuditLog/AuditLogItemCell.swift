import UIKit

final class AuditLogItemCell: UITableViewCell {

    static let reuseId = "AuditLogItemCell"
    
    @available(iOS 13.0, *)
    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let legacyTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private let avatarView = TextAvatarView(username: "", size: 36)
    private let avatarImageView = UIImageView()
    private let contentStackView = UIStackView()
    private let actionLabel = UILabel()
    private let timeLabel = UILabel()
    private let separatorView = UIView()
    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 18
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.isHidden = true
        contentView.addSubview(avatarImageView)

        contentStackView.axis = .vertical
        contentStackView.spacing = 4
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStackView)

        actionLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
        actionLabel.textColor = UIColor.theme.text
        actionLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(actionLabel)

        timeLabel.font = .systemFont(ofSize: 12.sf)
        timeLabel.textColor = UIColor.theme.textDisabled
        timeLabel.numberOfLines = 1
        contentStackView.addArrangedSubview(timeLabel)

        separatorView.backgroundColor = UIColor.theme.border
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12.sh),
            avatarView.widthAnchor.constraint(equalToConstant: 36.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 36.swh),

            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.widthAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarImageView.heightAnchor.constraint(equalTo: avatarView.heightAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12.sh),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12.sh),

            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    func configure(with log: Mezon_Api_AuditLog, memberInfo: ClanMemberRecord?, isLast: Bool) {
        let username = memberInfo?.username ?? "\(log.userID)"
        let action = AuditLogAction(rawValue: log.actionLog) ?? .allActionAudit

        let attributedText = NSMutableAttributedString()
        
        let boldAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
            .foregroundColor: UIColor.theme.textStrong
        ]
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
            .foregroundColor: UIColor.theme.text
        ]
        
        attributedText.append(NSAttributedString(string: username, attributes: boldAttributes))
        
        if action.isChannelAction && log.channelID != 0 {
            let actionText = action.isAddAction ? L(L10n.AuditLog.add) : L(L10n.AuditLog.remove)
            let targetEntity = action.isAddAction || action.isRemoveAction ? " \(log.entityName)" : ""
            let channelLabel = log.channelLabel.isEmpty ? "\(log.channelID)" : log.channelLabel
            
            attributedText.append(NSAttributedString(string: " \(actionText)\(targetEntity) (\(log.entityID)) \(L(L10n.AuditLog.toChannel)) ", attributes: normalAttributes))
            attributedText.append(NSAttributedString(string: "#\(channelLabel) (\(log.channelID))", attributes: normalAttributes))
        } else {
            let actionText = log.actionLog.isEmpty ? action.localizedString : log.actionLog.replacingOccurrences(of: "_ACTION_AUDIT", with: "").lowercased()
            attributedText.append(NSAttributedString(string: " \(actionText) ", attributes: normalAttributes))
            
            let entityStr = log.entityName.isEmpty ? "" : "\(log.entityName) "
            attributedText.append(NSAttributedString(string: "#\(entityStr)(\(log.entityID))", attributes: normalAttributes))
        }
        
        actionLabel.attributedText = attributedText
        
        if #available(iOS 13.0, *) {
            timeLabel.text = formatTime(seconds: log.timeLogSeconds)
        } else {
            Self.legacyTimeFormatter.locale = LanguageManager.shared.current.locale
            timeLabel.text = Self.legacyTimeFormatter.string(
                from: Date(timeIntervalSince1970: TimeInterval(log.timeLogSeconds)))
        }
        
        separatorView.isHidden = isLast

        avatarView.configure(username: username)

        let avatar = memberInfo?.userAvatarURL ?? ""
        imageTask?.cancel()
        if !avatar.isEmpty, let url = URL(string: avatar) {
            avatarView.showSkeleton()
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard error == nil, let data = data, let image = UIImage(data: data) else {
                    DispatchQueue.main.async {
                        self?.avatarImageView.isHidden = true
                        self?.avatarView.showPlaceholder()
                    }
                    return
                }
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                    self?.avatarImageView.isHidden = false
                    self?.avatarView.showImageMode()
                }
            }
            imageTask?.resume()
        } else {
            avatarImageView.isHidden = true
            avatarView.showPlaceholder()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarView.showPlaceholder()
    }

    @available(iOS 13.0, *)
    private func formatTime(seconds: UInt32) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        Self.relativeTimeFormatter.locale = LanguageManager.shared.current.locale
        return Self.relativeTimeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
