import UIKit
import SwiftProtobuf

final class DmListItemCell: UITableViewCell {

    static let reuseId = "DmListItemCell"

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 20.swh
        iv.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.textAlignment = .center
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

    private let onlineIndicator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .mezonSuccess
        v.layer.cornerRadius = 7.swh
        v.layer.borderWidth = 2
        v.isHidden = true
        return v
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14.sf, weight: .medium)
        l.numberOfLines = 1
        return l
    }()

    private let lastMessageLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13.sf)
        l.numberOfLines = 1
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12.sf)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    private let unreadBadge: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 10.sf, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = .systemRed
        l.layer.cornerRadius = 10.swh
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarView.image = nil
        avatarPlaceholder.isHidden = true
        groupIconView.isHidden = true
        onlineIndicator.isHidden = true
        unreadBadge.isHidden = true
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        containerView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        avatarView.addSubview(groupIconView)
        containerView.addSubview(onlineIndicator)
        containerView.addSubview(nameLabel)
        containerView.addSubview(lastMessageLabel)
        containerView.addSubview(timeLabel)
        containerView.addSubview(unreadBadge)

        let avatarSize: CGFloat = 40.swh

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5.sh),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5.sh),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10.sw),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10.sw),

            avatarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8.sw),
            avatarView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            groupIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 20.swh),
            groupIconView.heightAnchor.constraint(equalToConstant: 20.swh),

            onlineIndicator.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 1.swh),
            onlineIndicator.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 1.swh),
            onlineIndicator.widthAnchor.constraint(equalToConstant: 14.swh),
            onlineIndicator.heightAnchor.constraint(equalToConstant: 14.swh),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10.sw),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8.sh),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -6.sw),

            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8.sw),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lastMessageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            lastMessageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3.sh),
            lastMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor, constant: -6.sw),
            lastMessageLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -8.sh),

            unreadBadge.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8.sw),
            unreadBadge.centerYAnchor.constraint(equalTo: lastMessageLabel.centerYAnchor),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20.swh),
            unreadBadge.heightAnchor.constraint(equalToConstant: 20.swh),
        ])
    }

    func configure(channel: Mezon_Api_ChannelDescription, currentUserId: String?) {
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let displayName = displayName(for: channel)
        let unread = channel.countMessUnread
        let isUnread = unread > 0
            || (channel.hasLastSentMessage && channel.lastSeenMessage.timestampSeconds < channel.lastSentMessage.timestampSeconds)

        nameLabel.text = displayName
        nameLabel.textColor = isUnread ? .mezonTextStrong : UIColor.theme.textDisabled
        nameLabel.font = .systemFont(ofSize: 14.sf, weight: isUnread ? .semibold : .medium)

        onlineIndicator.layer.borderColor = UIColor.theme.primary.cgColor

        if isGroup {
            avatarPlaceholder.isHidden = true
            groupIconView.isHidden = false
            onlineIndicator.isHidden = true
            if !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
               let url = URL(string: channel.channelAvatar) {
                avatarView.backgroundColor = .clear
                loadImage(url: url)
            } else {
                avatarView.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
                groupIconView.isHidden = false
            }
        } else {
            groupIconView.isHidden = true
            let isOnline = channel.onlines.contains(true)
            onlineIndicator.isHidden = !isOnline

            if let avatarURL = channel.avatars.first, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                avatarPlaceholder.isHidden = true
                avatarView.backgroundColor = .clear
                loadImage(url: url)
            } else {
                avatarView.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(displayName.prefix(1)).uppercased()
            }
        }

        let (preview, time) = lastMessagePreview(channel: channel, currentUserId: currentUserId)
        lastMessageLabel.text = preview
        lastMessageLabel.textColor = isUnread ? UIColor.theme.textStrong : UIColor.theme.textDisabled
        timeLabel.text = time
        timeLabel.textColor = isUnread ? UIColor.theme.textStrong : UIColor.theme.textDisabled

        if unread > 0 {
            unreadBadge.text = unread > 99 ? "99+" : "\(unread)"
            unreadBadge.isHidden = false
        } else {
            unreadBadge.isHidden = true
        }
    }

    private func loadImage(url: URL) {
        let urlString = ImgproxyURL.create(from: url.absoluteString)
        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            avatarView.image = cached
            return
        }
        imageTask = ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            self?.avatarView.image = image
        }
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

        var senderPrefix = ""
        if isFromMe {
            senderPrefix = "\(L(L10n.DirectMessage.you)): "
        } else {
            let senderName = channel.displayNames.first(where: { !$0.isEmpty }) ?? channel.usernames.first(where: { !$0.isEmpty }) ?? ""
            if !senderName.isEmpty {
                senderPrefix = "\(senderName): "
            }
        }

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

        let preview = senderPrefix + (text.isEmpty ? "" : text)
        let time = formatRelativeTime(timestamp: msg.timestampSeconds)
        return (preview, time)
    }

    private func formatRelativeTime(timestamp: UInt32) -> String {
        guard timestamp > 0 else { return "" }
        let now = Date()
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let diff = now.timeIntervalSince(date)

        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 604800 { return "\(Int(diff / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d/M/yy"
        return formatter.string(from: date)
    }
}
