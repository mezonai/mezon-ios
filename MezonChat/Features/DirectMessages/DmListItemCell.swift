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


    private static let previewLayoutPlaceholder = "\u{200B}"


    private func lastMessagePreview(channel: Mezon_Api_ChannelDescription, currentUserId: String?) -> (String, String) {
        let msg = channel.lastSentMessage
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let hasHeaderPayload =
            channel.hasLastSentMessage
            || msg.timestampSeconds > 0
            || !msg.content.isEmpty
            || msg.id != 0
            || msg.senderID != 0


        if !hasHeaderPayload {
            let ts = max(
                channel.updateTimeSeconds,
                channel.lastSeenMessage.timestampSeconds,
                channel.createTimeSeconds
            )
            let time = ts > 0 ? formatRelativeTime(timestamp: ts) : ""
            if isGroup {
                return (L(L10n.DirectMessage.groupCreated), time)
            }
            return (Self.previewLayoutPlaceholder, time)
        }

        let isFromMe: Bool = {
            if let uid = currentUserId.flatMap({ Int64($0) }) { return uid == msg.senderID }
            if let s = currentUserId { return String(msg.senderID) == s }
            return false
        }()

        var senderPrefix = ""
        if msg.senderID != 0 {
            if isFromMe {
                senderPrefix = "\(L(L10n.DirectMessage.you)): "
            } else {
                let senderName = channel.displayNames.first(where: { !$0.isEmpty }) ?? channel.usernames.first(where: { !$0.isEmpty }) ?? ""
                if !senderName.isEmpty {
                    senderPrefix = "\(senderName): "
                }
            }
        }

        let time = formatRelativeTime(timestamp: msg.timestampSeconds)


        let preview: String
        if let payload = Self.messageContentPayload(from: msg.content) {
            if Self.isRNEmptyMessageContent(payload) {
                preview = Self.previewWhenNoMessageBody(senderPrefix: senderPrefix, isGroup: isGroup)
            } else {
                preview = senderPrefix + Self.dmPreviewBody(from: payload)
            }
        } else if msg.content.isEmpty {
            preview = Self.previewWhenNoMessageBody(senderPrefix: senderPrefix, isGroup: isGroup)
        } else {
            preview = senderPrefix + msg.content
        }

        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (Self.previewLayoutPlaceholder, time)
        }
        return (preview, time)
    }

    private static func previewWhenNoMessageBody(senderPrefix: String, isGroup: Bool) -> String {
        if isGroup {
            return senderPrefix + L(L10n.DirectMessage.groupCreated)
        }
        let p = senderPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? previewLayoutPlaceholder : p
    }


    private static func messageContentPayload(from raw: String) -> [String: Any]? {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let dict = any as? [String: Any] {
            return unwrapContentNested(in: dict)
        }

        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let innerData = trimmed.data(using: .utf8),
                  let inner = try? JSONSerialization.jsonObject(with: innerData) else {
                return nil
            }
            if let dict = inner as? [String: Any] { return unwrapContentNested(in: dict) }
        }
        return nil
    }

    private static func unwrapContentNested(in top: [String: Any]) -> [String: Any] {
        if top["content"] != nil {
            if let inner = top["content"] as? [String: Any] { return inner }
            if let s = top["content"] as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if let innerData = trimmed.data(using: .utf8),
                   let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
                    return inner
                }
            }
        }
        return top
    }

    private static func isRNEmptyMessageContent(_ d: [String: Any]) -> Bool {
        d.isEmpty
    }

    private static let shareContactFieldValue = "share_contact"

    private static func firstEmbed(in content: [String: Any]) -> [String: Any]? {
        if let arr = content["embed"] as? [[String: Any]] { return arr.first }
        if let arr = content["embed"] as? [Any] {
            for item in arr {
                if let d = item as? [String: Any] { return d }
            }
        }
        if let one = content["embed"] as? [String: Any] { return one }
        return nil
    }


    private static func messageTextT(from content: [String: Any]) -> String {
        guard let v = content["t"] else { return "" }
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dmPreviewBody(from content: [String: Any]) -> String {
        let t = messageTextT(from: content)

        if let embed = firstEmbed(in: content) {
            let title = (embed["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let desc = (embed["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let title { return title }
            if let desc { return desc }
            if let fields = embed["fields"] as? [[String: Any]],
               fields.contains(where: { ($0["value"] as? String) == shareContactFieldValue }) {
                return "[\(L(L10n.DirectMessage.previewContact))]"
            }
            return "[\(L(L10n.DirectMessage.previewFile))]"
        }

        if isGoogleMapsLink(t) {
            return "[\(L(L10n.DirectMessage.previewLocation))]"
        }
        if textContainsURL(t) {
            return "[\(L(L10n.DirectMessage.previewLink))] \(t)"
        }
        if !t.isEmpty {
            return t
        }
        return "[\(L(L10n.DirectMessage.previewFile))]"
    }

    private static func textContainsURL(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func isGoogleMapsLink(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("google.com/maps") { return true }
        if lower.contains("maps.app.goo.gl") { return true }
        if lower.contains("goo.gl/maps") { return true }
        return false
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
