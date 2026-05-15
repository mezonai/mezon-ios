import UIKit
import SwiftProtobuf

final class DmListItemCell: UITableViewCell {

    static let reuseId = "DmListItemCell"

    private static let groupDmListPlaceholderOrange = UIColor(red: 249/255, green: 115/255, blue: 22/255, alpha: 1)

    private let textAvatar = TextAvatarView(username: "", size: 40.swh, fontSize: 16.sf)

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 20.swh
        return iv
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

    private var imageTask: URLSessionDataTask?
    private var avatarLoadGeneration: UInt = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadGeneration += 1
        imageTask?.cancel()
        imageTask = nil
        avatarImageView.image = nil
        groupIconView.isHidden = true
        onlineIndicator.isHidden = true
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        textAvatar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textAvatar)
        textAvatar.addSubview(avatarImageView)
        textAvatar.addSubview(groupIconView)
        containerView.addSubview(onlineIndicator)
        containerView.addSubview(nameLabel)
        containerView.addSubview(lastMessageLabel)
        containerView.addSubview(timeLabel)

        let avatarSize: CGFloat = 40.swh

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5.sh),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5.sh),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10.sw),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10.sw),

            textAvatar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8.sw),
            textAvatar.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textAvatar.widthAnchor.constraint(equalToConstant: avatarSize),
            textAvatar.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarImageView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),

            groupIconView.centerXAnchor.constraint(equalTo: textAvatar.centerXAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: textAvatar.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 20.swh),
            groupIconView.heightAnchor.constraint(equalToConstant: 20.swh),

            onlineIndicator.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor, constant: 1.swh),
            onlineIndicator.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor, constant: 1.swh),
            onlineIndicator.widthAnchor.constraint(equalToConstant: 14.swh),
            onlineIndicator.heightAnchor.constraint(equalToConstant: 14.swh),

            nameLabel.leadingAnchor.constraint(equalTo: textAvatar.trailingAnchor, constant: 10.sw),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8.sh),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -6.sw),

            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8.sw),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lastMessageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            lastMessageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3.sh),
            lastMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -8.sw),
            lastMessageLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -8.sh),
        ])
    }

    func configure(channel: Mezon_Api_ChannelDescription, context: AccountContext? = nil) {
        groupIconView.tintColor = .mezonTextSecondary

        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let displayName = displayName(for: channel)
        let isUnread = channel.countMessUnread > 0

        nameLabel.text = displayName
        nameLabel.textColor = isUnread ? .mezonTextStrong : UIColor.theme.textDisabled
        nameLabel.font = .systemFont(ofSize: 14.sf, weight: isUnread ? .semibold : .medium)

        onlineIndicator.layer.borderColor = UIColor.theme.primary.cgColor

        if isGroup {
            textAvatar.showImageMode()
            onlineIndicator.isHidden = true
            if !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
               let url = URL(string: channel.channelAvatar) {
                groupIconView.isHidden = true
                loadImage(url: url, fallbackUsername: nil)
            } else {
                avatarLoadGeneration += 1
                imageTask?.cancel()
                imageTask = nil
                avatarImageView.image = nil
                textAvatar.backgroundColor = Self.groupDmListPlaceholderOrange
                groupIconView.tintColor = .white
                groupIconView.isHidden = false
            }
        } else {
            groupIconView.isHidden = true
            let isOnline = channel.onlines.contains(true)
            onlineIndicator.isHidden = !isOnline

            let username = channel.usernames.first ?? ""
            textAvatar.configure(username: username, fontSize: 16.sf)
            let resolvedURLString = Self.resolveDmAvatarURL(channel: channel, context: context)

            if let urlString = resolvedURLString, let url = URL(string: urlString) {
                loadImage(url: url, fallbackUsername: username)
            } else {
                avatarLoadGeneration += 1
                imageTask?.cancel()
                imageTask = nil
                avatarImageView.image = nil
            }
        }

        let (preview, time) = lastMessagePreview(channel: channel)
        lastMessageLabel.text = preview
        lastMessageLabel.textColor = isUnread ? UIColor.theme.textStrong : UIColor.theme.textDisabled
        timeLabel.text = time
        timeLabel.textColor = isUnread ? UIColor.theme.textStrong : UIColor.theme.textDisabled
    }

    private static func resolveDmAvatarURL(
        channel: Mezon_Api_ChannelDescription,
        context: AccountContext?
    ) -> String? {
        if let server = channel.avatars.first {
            let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if URL(string: trimmed) != nil {
                    return trimmed
                }
                if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   URL(string: encoded) != nil {
                    return encoded
                }
            }
        }
        let userId = channel.userIds.first ?? 0
        guard userId != 0, let context else { return nil }
        if let cached = context.account.postbox.read({ $0.getProfile(userId: "\(userId)") }),
           let pbAvatar = cached.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pbAvatar.isEmpty,
           URL(string: pbAvatar) != nil {
            return pbAvatar
        }
        if let friendAvatar = context.engine.friendsData.allFriends().first(where: { $0.user.id == userId })?.user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines),
           !friendAvatar.isEmpty,
           URL(string: friendAvatar) != nil {
            return friendAvatar
        }
        return nil
    }

    private func loadImage(url: URL, fallbackUsername: String?) {
        imageTask?.cancel()
        imageTask = nil
        avatarLoadGeneration += 1
        let gen = avatarLoadGeneration
        let proxied = ImgproxyURL.avatarProxyURL(from: url.absoluteString, width: 100, height: 100)
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            guard gen == avatarLoadGeneration else { return }
            avatarImageView.image = cached
            textAvatar.showImageMode()
            return
        }
        avatarImageView.image = nil
        imageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self, gen == self.avatarLoadGeneration else { return }
            if let image {
                self.avatarImageView.image = image
                self.textAvatar.showImageMode()
            } else if let fallbackUsername {
                self.avatarImageView.image = nil
                self.textAvatar.configure(username: fallbackUsername, fontSize: 16.sf)
            } else {
                self.avatarImageView.image = nil
            }
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

    private func lastMessagePreview(channel: Mezon_Api_ChannelDescription) -> (String, String) {
        let msg = channel.lastSentMessage
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
            return (Self.previewLayoutPlaceholder, time)
        }

        let time = formatRelativeTime(timestamp: msg.timestampSeconds)

        let preview: String
        if let payload = Self.messageContentPayload(from: msg.content) {
            if Self.isRNEmptyMessageContent(payload) {
                preview = Self.previewWhenNoMessageBody()
            } else {
                preview = Self.dmPreviewBody(from: payload, channelId: channel.channelID)
            }
        } else if msg.content.isEmpty {
            preview = Self.previewWhenNoMessageBody()
        } else {
            preview = Self.normalizeJsonEscapedSlashes(in: msg.content)
        }

        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (Self.previewWhenNoMessageBody(), time)
        }
        let body = Self.normalizeJsonEscapedSlashes(in: preview)
        return (body.count >= 20 ? body + "..." : body, time)
    }

    private static func normalizeJsonEscapedSlashes(in text: String) -> String {
        text.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func previewWhenNoMessageBody() -> String {
        Self.previewLayoutPlaceholder
    }


    private static func messageContentPayload(from raw: String) -> [String: Any]? {
        guard !raw.isEmpty else { return nil }
        if let p = messageContentPayloadParsing(raw) { return p }
        let slashesFixed = raw.replacingOccurrences(of: "\\/", with: "/")
        if slashesFixed != raw { return messageContentPayloadParsing(slashesFixed) }
        return nil
    }

    private static func messageContentPayloadParsing(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
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
        let raw: String = {
            if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = v as? NSNumber { return n.stringValue }
            return String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        return raw.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func dmPreviewBody(from content: [String: Any], channelId: Int64) -> String {
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
            return ""
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
        return ""
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
