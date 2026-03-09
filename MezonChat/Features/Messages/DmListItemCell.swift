import UIKit
import SwiftProtobuf

final class DmListItemCell: UITableViewCell {

    static let reuseId = "DmListItemCell"

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 24
        iv.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = .mezonTextPrimary
        return l
    }()

    private let groupIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "person.2.fill"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .mezonTextSecondary
        iv.isHidden = true
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.numberOfLines = 1
        return l
    }()

    private let lastMessageLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14)
        l.textColor = .mezonTextSecondary
        l.numberOfLines = 1
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12)
        l.textColor = .mezonTextSecondary
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        avatarView.addSubview(groupIconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(lastMessageLabel)
        contentView.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            groupIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 24),
            groupIconView.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lastMessageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            lastMessageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            lastMessageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    func configure(channel: Mezon_Api_ChannelDescription, currentUserId: String?) {
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let displayName = displayName(for: channel)
        nameLabel.text = displayName

        if isGroup {
            avatarPlaceholder.isHidden = true
            groupIconView.isHidden = false
            if !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
               let url = URL(string: channel.channelAvatar) {
                avatarView.image = nil
                avatarView.backgroundColor = .clear
                URLSession.shared.dataTask(with: url) { [weak avatarView] data, _, _ in
                    guard let data, let img = UIImage(data: data) else { return }
                    DispatchQueue.main.async { avatarView?.image = img }
                }.resume()
            } else {
                avatarView.image = nil
                avatarView.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
                groupIconView.isHidden = false
            }
        } else {
            groupIconView.isHidden = true
            if let avatarURL = channel.avatars.first, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                avatarPlaceholder.isHidden = true
                avatarView.image = nil
                avatarView.backgroundColor = .clear
                URLSession.shared.dataTask(with: url) { [weak avatarView] data, _, _ in
                    guard let data, let img = UIImage(data: data) else { return }
                    DispatchQueue.main.async { avatarView?.image = img }
                }.resume()
            } else {
                avatarView.image = nil
                avatarView.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(displayName.prefix(1)).uppercased()
            }
        }

        let (preview, time) = lastMessagePreview(channel: channel, currentUserId: currentUserId)
        lastMessageLabel.text = preview
        timeLabel.text = time
    }

    private func displayName(for channel: Mezon_Api_ChannelDescription) -> String {
        if !channel.channelLabel.isEmpty { return channel.channelLabel }
        if let first = channel.displayNames.first, !first.isEmpty { return first }
        if let first = channel.usernames.first, !first.isEmpty { return first }
        if !channel.creatorName.isEmpty { return "\(channel.creatorName)'s Group" }
        return "Chat"
    }

    private func lastMessagePreview(channel: Mezon_Api_ChannelDescription, currentUserId: String?) -> (String, String) {
        guard channel.hasLastSentMessage else { return ("", "") }
        let msg = channel.lastSentMessage
        let isFromMe = currentUserId.map { String(msg.senderID) == $0 } ?? false
        let prefix = isFromMe ? "\(L(L10n.DirectMessage.you)): " : ""

        var text = ""
        if !msg.content.isEmpty {
            if let data = msg.content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let t = json["t"] as? String, !t.isEmpty {
                text = t
            } else {
                text = msg.content
            }
        }
        let preview = prefix + (text.isEmpty ? "" : text)

        let time = formatRelativeTime(timestamp: msg.timestampSeconds)
        return (preview, time)
    }

    private func formatRelativeTime(timestamp: UInt32) -> String {
        let now = Date()
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let diff = now.timeIntervalSince(date)

        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 604800 { return "\(Int(diff / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}
