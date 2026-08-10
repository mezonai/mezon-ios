import UIKit
import SwiftProtobuf

final class DmListItemCell: UITableViewCell {

    static let reuseId = "DmListItemCell"

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

    private var avatarLoadGeneration: UInt = 0
    private var lastMessageTopConstraint: NSLayoutConstraint?
    private var lastMessageZeroHeightConstraint: NSLayoutConstraint?
    private var configuredAvatarURLString: String?
    private var isAvatarLoadInFlight = false
    private var hasPreviewLayout: Bool?

    private static let unreadNameFont = UIFont.systemFont(ofSize: 14.sf, weight: .semibold)
    private static let readNameFont = UIFont.systemFont(ofSize: 14.sf, weight: .medium)

    private static let avatarMemoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 600
        return c
    }()

    private struct PreviewBodyKey: Hashable {
        let channelId: Int64
        let hasLastSentMessage: Bool
        let messageId: Int64
        let timestampSeconds: UInt32
        let senderId: Int64
        let contentByteCount: Int
    }

    private static var previewBodyCache: [PreviewBodyKey: String] = [:]
    private static var previewBodyCacheOrder: [PreviewBodyKey] = []
    private static let previewBodyCacheLimit = 400
    private static var absoluteDateCache: [UInt32: String] = [:]
    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d/M/yy"
        return formatter
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadGeneration += 1
        isAvatarLoadInFlight = false
        configuredAvatarURLString = nil
        avatarImageView.image = nil
        textAvatar.showImageMode()
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

        let textBlockGuide = UILayoutGuide()
        containerView.addLayoutGuide(textBlockGuide)

        let lastMessageTopConstraint = lastMessageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3.sh)
        let lastMessageZeroHeightConstraint = lastMessageLabel.heightAnchor.constraint(equalToConstant: 0)
        lastMessageZeroHeightConstraint.isActive = false
        self.lastMessageTopConstraint = lastMessageTopConstraint
        self.lastMessageZeroHeightConstraint = lastMessageZeroHeightConstraint

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5.sh),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5.sh),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10.sw),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10.sw),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52.sh),

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
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -6.sw),

            textBlockGuide.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            textBlockGuide.bottomAnchor.constraint(equalTo: lastMessageLabel.bottomAnchor),
            textBlockGuide.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8.sw),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lastMessageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            lastMessageTopConstraint,
            lastMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -8.sw),
        ])
    }

    func configure(channel: Mezon_Api_ChannelDescription, resolvedAvatarURL: String? = nil) {
        groupIconView.tintColor = .mezonTextSecondary

        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let displayName = displayName(for: channel)
        let isUnread = channel.countMessUnread > 0

        nameLabel.text = displayName
        nameLabel.textColor = isUnread ? .mezonTextStrong : UIColor.theme.textDisabled
        nameLabel.font = isUnread ? Self.unreadNameFont : Self.readNameFont

        onlineIndicator.layer.borderColor = UIColor.theme.primary.cgColor

        if isGroup {
            onlineIndicator.isHidden = true
            if let urlString = resolvedAvatarURL, let url = URL(string: urlString) {
                loadImage(url: url, fallbackUsername: nil)
            } else {
                avatarLoadGeneration += 1
                isAvatarLoadInFlight = false
                configuredAvatarURLString = nil
                avatarImageView.image = nil
                showGroupAvatarPlaceholder()
            }
        } else {
            groupIconView.isHidden = true
            let isOnline = channel.onlines.contains(true)
            onlineIndicator.isHidden = !isOnline

            let username = channel.usernames.first ?? ""
            let avatarSeed = username

            if let urlString = resolvedAvatarURL, let url = URL(string: urlString) {
                loadImage(url: url, fallbackUsername: avatarSeed)
            } else {
                avatarLoadGeneration += 1
                isAvatarLoadInFlight = false
                configuredAvatarURLString = nil
                avatarImageView.image = nil
                textAvatar.configure(username: avatarSeed, fontSize: 16.sf)
            }
        }

        let (preview, time) = lastMessagePreview(channel: channel)
        let hasPreview = !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lastMessageLabel.text = hasPreview ? preview : ""
        lastMessageLabel.isHidden = !hasPreview
        if hasPreviewLayout != hasPreview {
            hasPreviewLayout = hasPreview
            lastMessageTopConstraint?.constant = hasPreview ? 3.sh : 0
            lastMessageZeroHeightConstraint?.isActive = !hasPreview
        }
        lastMessageLabel.textColor = isUnread ? UIColor.theme.textStrong : UIColor.theme.textDisabled
        timeLabel.text = time
        timeLabel.textColor = isUnread ? UIColor.theme.textStrong : UIColor.theme.textDisabled
    }

    private func showGroupAvatarPlaceholder() {
        textAvatar.showImageMode()
        textAvatar.backgroundColor = .groupDMDefaultAvatar
        groupIconView.tintColor = .white
        groupIconView.isHidden = false
    }

    private func loadImage(url: URL, fallbackUsername: String?) {
        let source = url.absoluteString
        if configuredAvatarURLString == source && (isAvatarLoadInFlight || avatarImageView.image != nil) {
            return
        }
        configuredAvatarURLString = source
        avatarLoadGeneration += 1
        let gen = avatarLoadGeneration
        let proxied = ImgproxyURL.avatarProxyURL(from: url.absoluteString, width: 100, height: 100)
        let raw = url.absoluteString
        let proxiedKey = proxied as NSString
        let rawKey = raw as NSString
        
        if let cached = Self.avatarMemoryCache.object(forKey: proxiedKey) ?? ImageCache.shared.memoryImage(forKey: proxied) ?? Self.avatarMemoryCache.object(forKey: rawKey) ?? ImageCache.shared.memoryImage(forKey: raw) {
            Self.avatarMemoryCache.setObject(cached, forKey: proxiedKey)
            guard gen == avatarLoadGeneration else { return }
            isAvatarLoadInFlight = false
            groupIconView.isHidden = true
            avatarImageView.image = cached
            textAvatar.showImageMode()
            return
        }

        avatarImageView.image = nil
        isAvatarLoadInFlight = true
        if let fallbackUsername {
            textAvatar.configure(username: fallbackUsername, fontSize: 16.sf)
        } else {
            showGroupAvatarPlaceholder()
        }

        ImageCache.shared.loadAvatar(urlString: proxied) { [weak self] image in
            if let image {
                Self.avatarMemoryCache.setObject(image, forKey: proxiedKey)
                guard let self, gen == self.avatarLoadGeneration else { return }
                self.isAvatarLoadInFlight = false
                self.groupIconView.isHidden = true
                self.avatarImageView.image = image
                self.textAvatar.showImageMode()
            } else if proxied != raw {
                guard let self, gen == self.avatarLoadGeneration else { return }
                ImageCache.shared.loadAvatar(urlString: raw) { [weak self] rawImage in
                    if let rawImage { Self.avatarMemoryCache.setObject(rawImage, forKey: rawKey) }
                    guard let self, gen == self.avatarLoadGeneration else { return }
                    self.isAvatarLoadInFlight = false
                    if let rawImage {
                        self.groupIconView.isHidden = true
                        self.avatarImageView.image = rawImage
                        self.textAvatar.showImageMode()
                    } else if let fallbackUsername {
                        self.avatarImageView.image = nil
                        self.textAvatar.configure(username: fallbackUsername, fontSize: 16.sf)
                    } else {
                        self.avatarImageView.image = nil
                        self.showGroupAvatarPlaceholder()
                    }
                }
            } else {
                guard let self, gen == self.avatarLoadGeneration else { return }
                self.isAvatarLoadInFlight = false
                if let fallbackUsername {
                    self.avatarImageView.image = nil
                    self.textAvatar.configure(username: fallbackUsername, fontSize: 16.sf)
                } else {
                    self.avatarImageView.image = nil
                    self.showGroupAvatarPlaceholder()
                }
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

    private func lastMessagePreview(channel: Mezon_Api_ChannelDescription) -> (String, String) {
        let msg = channel.lastSentMessage
        let time = previewTimeString(channel: channel, msg: msg)
        let key = PreviewBodyKey(
            channelId: channel.channelID,
            hasLastSentMessage: channel.hasLastSentMessage,
            messageId: msg.id,
            timestampSeconds: msg.timestampSeconds,
            senderId: msg.senderID,
            contentByteCount: msg.content.utf8.count
        )
        if let cachedBody = Self.previewBodyCache[key] {
            return (cachedBody, time)
        }
        let body = computeLastMessagePreviewBody(channel: channel, msg: msg)
        Self.storePreviewBodyCache(body, for: key)
        return (body, time)
    }

    private func previewTimeString(
        channel: Mezon_Api_ChannelDescription,
        msg: Mezon_Api_ChannelMessageHeader
    ) -> String {
        let hasHeaderPayload =
            channel.hasLastSentMessage
            || msg.timestampSeconds > 0
            || !msg.content.isEmpty
            || msg.id != 0
            || msg.senderID != 0

        if !hasHeaderPayload {
            let ts = max(
                channel.updateTimeSeconds,
                channel.createTimeSeconds
            )
            return ts > 0 ? formatRelativeTime(timestamp: ts) : ""
        }
        return formatRelativeTime(timestamp: msg.timestampSeconds)
    }

    private static func storePreviewBodyCache(_ value: String, for key: PreviewBodyKey) {
        guard previewBodyCache[key] == nil else { return }
        previewBodyCache[key] = value
        previewBodyCacheOrder.append(key)
        if previewBodyCacheOrder.count > previewBodyCacheLimit {
            let overflow = previewBodyCacheOrder.count - previewBodyCacheLimit
            let removed = previewBodyCacheOrder.prefix(overflow)
            for key in removed {
                previewBodyCache.removeValue(forKey: key)
            }
            previewBodyCacheOrder.removeFirst(overflow)
        }
    }

    private func computeLastMessagePreviewBody(
        channel: Mezon_Api_ChannelDescription,
        msg: Mezon_Api_ChannelMessageHeader
    ) -> String {
        let hasHeaderPayload =
            channel.hasLastSentMessage
            || msg.timestampSeconds > 0
            || !msg.content.isEmpty
            || msg.id != 0
            || msg.senderID != 0

        if !hasHeaderPayload {
            return ""
        }

        let preview: String
        if let payload = Self.messageContentPayload(from: msg.content) {
            if Self.isRNEmptyMessageContent(payload) {
                preview = Self.rawContentFallbackPreview(from: msg.content) ?? Self.previewWhenNoMessageBody()
            } else {
                preview = Self.dmPreviewBody(from: payload, channelId: channel.channelID)
            }
        } else if msg.content.isEmpty {
            preview = Self.previewWhenNoMessageBody()
        } else {
            preview = Self.rawContentFallbackPreview(from: msg.content)
                ?? Self.normalizeJsonEscapedSlashes(in: msg.content)
        }

        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if Self.shouldInferAttachmentOnlyListPreview(msg: msg) {
                return Self.attachmentBracketPreviewText()
            }
            return Self.previewWhenNoMessageBody()
        }
        let body = Self.stripHeadingMarkdown(
            from: Self.normalizeJsonEscapedSlashes(in: preview)
        )
        return Self.appendPreviewEllipsisIfTruncated(body)
    }

    private static let headingMarkdownRegex = try? NSRegularExpression(
        pattern: #"^#{1,6}\s+"#,
        options: [.anchorsMatchLines]
    )

    private static func stripHeadingMarkdown(from text: String) -> String {
        guard let headingMarkdownRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return headingMarkdownRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: ""
        )
    }

    private static func appendPreviewEllipsisIfTruncated(_ body: String) -> String {
        let serverLimit = 32
        let maxUTF8CharWidth = 4
        let truncationThreshold = serverLimit - maxUTF8CharWidth
        return body.utf8.count >= truncationThreshold ? body + "..." : body
    }

    private static let contentKeysAllowingEmptyAttachmentInference: Set<String> = ["t", "mk", "ej", "hg"]

    private static func attachmentBracketPreviewText() -> String {
        "[\(L(L10n.DirectMessage.previewFile))]"
    }

    private static func shouldInferAttachmentOnlyListPreview(msg: Mezon_Api_ChannelMessageHeader) -> Bool {
        guard msg.senderID != 0, msg.id != 0 || msg.timestampSeconds > 0 else { return false }
        let c = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty || c == "{}" { return true }
        guard let payload = messageContentPayload(from: msg.content) else { return false }
        if isRNEmptyMessageContent(payload) { return true }
        let keys = Set(payload.keys.map { String($0) })
        guard keys.isSubset(of: contentKeysAllowingEmptyAttachmentInference) else { return false }
        let t = messageTextT(from: payload)
        guard t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard attachmentDicts(from: payload).isEmpty else { return false }
        guard !hasEmbedPayload(in: payload) else { return false }
        return true
    }

    private static func normalizeJsonEscapedSlashes(in text: String) -> String {
        text.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func previewWhenNoMessageBody() -> String {
        ""
    }


    private static func messageContentPayload(from raw: String) -> [String: Any]? {
        guard !raw.isEmpty else { return nil }
        if let p = messageContentPayloadParsing(raw) { return p }
        let slashesFixed = raw.replacingOccurrences(of: "\\/", with: "/")
        if slashesFixed != raw { return messageContentPayloadParsing(slashesFixed) }
        let quotesFixed = slashesFixed.replacingOccurrences(of: "\\\"", with: "\"")
        if quotesFixed != slashesFixed { return messageContentPayloadParsing(quotesFixed) }
        return nil
    }

    private static func rawContentFallbackPreview(from raw: String) -> String? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = raw
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\\"", with: "\"")
        if normalized.contains(MezonConstants.shareContactKey) || normalized.contains("share_contact_key") {
            return "[\(L(L10n.DirectMessage.previewContact))]"
        }
        if let text = rawPreviewTextValue(from: normalized), !text.isEmpty {
            return text
        }
        if normalized.contains("\"lk\"") {
            return "[\(L(L10n.DirectMessage.previewLink))]"
        }
        if normalized.contains("\"attachments\"") || normalized.contains("\"a\":") {
            return Self.attachmentBracketPreviewText()
        }
        if normalized.contains("\"embed\"") {
            return bracketEmbedPreview()
        }
        return nil
    }

    private static func rawPreviewTextValue(from raw: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #""t"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            options: []
        ) else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let value = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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

    private static let shareContactFieldValues: Set<String> = ["share_contact", "share_contact_key"]

    private static func attachmentDicts(from content: [String: Any]) -> [[String: Any]] {
        if let arr = content["attachments"] as? [[String: Any]] { return arr }
        if let arr = content["a"] as? [[String: Any]] { return arr }
        if let arr = content["attachments"] as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        if let arr = content["a"] as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func bracketAttachmentPreview(from items: [[String: Any]]) -> String? {
        guard !items.isEmpty else { return nil }
        return attachmentBracketPreviewText()
    }

    private static func nonEmptyEmbedString(_ embed: [String: Any], key: String) -> String? {
        guard let s = embed[key] as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func firstEmbed(in content: [String: Any]) -> [String: Any]? {
        if let arr = content["embed"] as? [[String: Any]] { return arr.first }
        if let arr = content["embed"] as? [Any] {
            for item in arr {
                if let d = item as? [String: Any] { return d }
            }
        }
        if let one = content["embed"] as? [String: Any] { return one }
        if let arr = content["embeds"] as? [[String: Any]] { return arr.first }
        if let arr = content["embeds"] as? [Any] {
            for item in arr {
                if let d = item as? [String: Any] { return d }
            }
        }
        if let one = content["embeds"] as? [String: Any] { return one }
        return nil
    }

    private static func hasEmbedPayload(in content: [String: Any]) -> Bool {
        content["embed"] != nil || content["embeds"] != nil
    }

    private static func bracketEmbedPreview() -> String {
        "[\(L(L10n.DirectMessage.previewEmbed))]"
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
        let attachmentItems = attachmentDicts(from: content)

        if let embed = firstEmbed(in: content) {
            if let title = nonEmptyEmbedString(embed, key: "title") { return title }
            if let desc = nonEmptyEmbedString(embed, key: "description") { return desc }
            if embedFieldsContainShareContact(embed["fields"]) {
                return "[\(L(L10n.DirectMessage.previewContact))]"
            }
            if let u = nonEmptyEmbedString(embed, key: "url"), textContainsURL(u) {
                return "[\(L(L10n.DirectMessage.previewLink))] \(u)"
            }
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

        if let att = bracketAttachmentPreview(from: attachmentItems) {
            return att
        }

        if hasEmbedPayload(in: content) {
            return bracketEmbedPreview()
        }

        return ""
    }

    private static func embedFieldsContainShareContact(_ fields: Any?) -> Bool {
        if let fields = fields as? [[String: Any]] {
            return fields.contains(where: fieldContainsShareContact)
        }
        if let fields = fields as? [Any] {
            return fields.contains { item in
                guard let field = item as? [String: Any] else { return false }
                return fieldContainsShareContact(field)
            }
        }
        return false
    }

    private static func fieldContainsShareContact(_ field: [String: Any]) -> Bool {
        let name = ((field["name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let value = ((field["value"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if name == "key", shareContactFieldValues.contains(value) { return true }
        return shareContactFieldValues.contains(value)
    }

    private static func textContainsURL(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard let detector = urlDetector else { return false }
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
        if let cached = Self.absoluteDateCache[timestamp] { return cached }
        let formatted = Self.relativeDateFormatter.string(from: date)
        Self.absoluteDateCache[timestamp] = formatted
        return formatted
    }
}
