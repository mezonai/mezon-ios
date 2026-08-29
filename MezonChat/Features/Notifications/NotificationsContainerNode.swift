import AsyncDisplayKit
import Combine
import UIKit

enum NotificationTabCategory {
    static let topic: Int32 = 4
}

enum NotificationItem {
    case notification(NotificationRecord)
    case topic(TopicRecord)

    var id: Int64 {
        switch self {
        case .notification(let n): return n.id
        case .topic(let t): return t.id
        }
    }

    var subject: String {
        switch self {
        case .notification(let n): return n.subject
        case .topic:
            return L(L10n.Notifications.topicDiscussion)
        }
    }

    var content: String {
        switch self {
        case .notification(let n): return n.previewText
        case .topic(let t):
            let raw = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = Self.parseTopicMessage(content: raw)
            return L(L10n.Notifications.repliedTo) + preview
        }
    }

    private static func parseTopicMessage(content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return L(L10n.Notifications.topicOriginalAttachment)
        }
        guard trimmed.first == "{" || trimmed.first == "[" else {
            return normalizePreviewText(trimmed)
        }
        guard trimmed.first == "{",
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return L(L10n.Notifications.topicOriginalAttachment)
        }

        if isShareContactPayload(obj) {
            return L(L10n.Notifications.topicOriginalContact)
        }
        if hasAttachmentPayload(obj) {
            return L(L10n.Notifications.topicOriginalAttachment)
        }
        let text = nonEmptyString(obj["t"]) ?? nonEmptyString(obj["text"])
        let link = linkValue(obj["lk"])
        if hasInteractivePayload(obj, includeRichEmbedOnly: text == nil && link == nil) {
            return L(L10n.Notifications.topicOriginalInteractiveMessage)
        }
        if let text {
            return normalizePreviewText(text)
        }
        if let link {
            return normalizePreviewText(link)
        }
        if let embedPreview = firstEmbedPreview(in: obj) {
            return normalizePreviewText(embedPreview)
        }
        return L(L10n.Notifications.topicOriginalAttachment)
    }

    private static func normalizePreviewText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 200 else { return normalized }
        return String(normalized.prefix(200))
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hasAttachmentPayload(_ obj: [String: Any]) -> Bool {
        if containsAttachmentMarker(obj) { return true }
        if hasNonEmptyPayloadValue(obj["a"]) { return true }
        return false
    }

    private static func containsAttachmentMarker(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let obj = value as? [String: Any] {
            for (key, nested) in obj {
                let normalizedKey = key.lowercased()
                if normalizedKey == "has_attachment" || normalizedKey == "hasattachment" {
                    if boolValue(nested) { return true }
                }
                if normalizedKey == "attachments" || normalizedKey == "attachment" ||
                    normalizedKey == "files" || normalizedKey == "file" {
                    if hasNonEmptyPayloadValue(nested) { return true }
                }
                if containsAttachmentMarker(nested) { return true }
            }
        }
        if let items = value as? [Any] {
            return items.contains { containsAttachmentMarker($0) }
        }
        return false
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let double = value as? Double { return double != 0 }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1" || normalized == "yes"
        }
        return false
    }

    private static func hasNonEmptyPayloadValue(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let string = value as? String {
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let bool = value as? Bool {
            return bool
        }
        if let items = value as? [Any] {
            return !items.isEmpty
        }
        if let obj = value as? [String: Any] {
            return !obj.isEmpty
        }
        return true
    }

    private static func embedItems(in obj: [String: Any]) -> [[String: Any]] {
        func normalize(_ value: Any?) -> [[String: Any]] {
            if let item = value as? [String: Any] { return [item] }
            if let items = value as? [[String: Any]] { return items }
            if let items = value as? [Any] { return items.compactMap { $0 as? [String: Any] } }
            return []
        }
        let embed = normalize(obj["embed"])
        return embed.isEmpty ? normalize(obj["embeds"]) : embed
    }

    private static func isShareContactPayload(_ obj: [String: Any]) -> Bool {
        for embed in embedItems(in: obj) {
            guard let fields = embed["fields"] as? [Any] else { continue }
            for item in fields {
                guard let field = item as? [String: Any] else { continue }
                let name = nonEmptyString(field["name"])?.lowercased() ?? ""
                let value = nonEmptyString(field["value"])?.lowercased() ?? ""
                if (name == "key" && (value == "share_contact" || value == "share_contact_key")) ||
                    value == "share_contact" ||
                    value == "share_contact_key" {
                    return true
                }
            }
        }
        return false
    }

    private static func hasInteractivePayload(_ obj: [String: Any], includeRichEmbedOnly: Bool) -> Bool {
        if let components = obj["components"] as? [Any], !components.isEmpty {
            return true
        }
        for embed in embedItems(in: obj) {
            guard let fields = embed["fields"] as? [Any] else { continue }
            if !fields.isEmpty {
                return true
            }
        }
        return includeRichEmbedOnly && embedItems(in: obj).contains { hasRichIntegrationEmbedPayload($0) }
    }

    private static func hasRichIntegrationEmbedPayload(_ embed: [String: Any]) -> Bool {
        return hasNonEmptyPayloadValue(embed["author"]) ||
            hasNonEmptyPayloadValue(embed["footer"]) ||
            hasNonEmptyPayloadValue(embed["image"]) ||
            hasNonEmptyPayloadValue(embed["thumbnail"]) ||
            hasNonEmptyPayloadValue(embed["video"])
    }

    private static func linkValue(_ value: Any?) -> String? {
        if let string = nonEmptyString(value) { return string }
        if let obj = value as? [String: Any] {
            return nonEmptyString(obj["url"]) ?? nonEmptyString(obj["href"])
        }
        if let items = value as? [Any] {
            for item in items {
                if let value = linkValue(item) { return value }
            }
        }
        return nil
    }

    private static func firstEmbedPreview(in obj: [String: Any]) -> String? {
        for embed in embedItems(in: obj) {
            if let title = nonEmptyString(embed["title"]) { return title }
            if let description = nonEmptyString(embed["description"]) { return description }
            if let url = nonEmptyString(embed["url"]) { return url }
        }
        return nil
    }

    var avatarURL: String {
        switch self {
        case .notification(let n): return n.avatarURL
        case .topic(let t): return t.senderAvatarURL
        }
    }

    var avatarPlaceholderSeed: String {
        switch self {
        case .notification(let n):
            let name = NotificationRecord.placeholderName(from: n.subject)
            if !name.isEmpty { return name }
            return n.subject
        case .topic(let t):
            if !t.senderDisplayName.isEmpty { return t.senderDisplayName }
            return String(t.lastSenderID)
        }
    }

    var createTimeSeconds: UInt32 {
        switch self {
        case .notification(let n): return n.createTimeSeconds
        case .topic(let t): return t.updateTimeSeconds
        }
    }
}

struct NotificationsState {
    let items: [NotificationItem]
    let isLoading: Bool
    let isLoadingMore: Bool
    let hasLoaded: Bool

    static let empty = NotificationsState(
        items: [], isLoading: false, isLoadingMore: false, hasLoaded: false)
}


struct NotificationsInteraction {
    let onTabSelected: (Int32) -> Void
    let onLoadMore: () -> Void
    let onItemSelected: (NotificationItem) -> Void
}


final class NotificationItemCell: UITableViewCell {

    static let reuseId = "NotificationItemCell"

    private let avatarSize: CGFloat = 36
    private static let avatarTargetPixelSize = 120

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = .mezonChannelText
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = .mezonTextMuted
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let verticalLine: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonBorder
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let separatorLine: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonBorder
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarSkeleton = UIView()
    private var previewConstraints: [NSLayoutConstraint] = []
    private var titleToSeparatorConstraint: NSLayoutConstraint?
    private var avatarLoadGeneration: UInt = 0
    private var configuredAvatarURLString: String?
    private var isAvatarLoadInFlight = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        avatarSkeleton.translatesAutoresizingMaskIntoConstraints = false
        avatarSkeleton.layer.cornerRadius = 18
        avatarSkeleton.clipsToBounds = true
        avatarSkeleton.isHidden = true

        contentView.addSubview(separatorLine)
        contentView.addSubview(verticalLine)
        contentView.addSubview(contentLabel)
        contentView.addSubview(titleLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(avatarSkeleton)
        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)

        NSLayoutConstraint.activate([

            avatarSkeleton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            avatarSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarSkeleton.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarSkeleton.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),


            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),


            titleLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            titleLabel.widthAnchor.constraint(
                lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),
        ])

        let vLineTop = verticalLine.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        let vLineBottom = verticalLine.bottomAnchor.constraint(
            equalTo: separatorLine.topAnchor, constant: -16)
        let vLineLeading = verticalLine.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor)
        let vLineWidth = verticalLine.widthAnchor.constraint(equalToConstant: 2)
        let cTop = contentLabel.topAnchor.constraint(equalTo: verticalLine.topAnchor)
        let cLead = contentLabel.leadingAnchor.constraint(
            equalTo: verticalLine.trailingAnchor, constant: 8)
        let cTrail = contentLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        let cWidth = contentLabel.widthAnchor.constraint(
            lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8)
        let cBottom = contentLabel.bottomAnchor.constraint(
            lessThanOrEqualTo: separatorLine.topAnchor, constant: -16)
        previewConstraints = [
            vLineTop, vLineBottom, vLineLeading, vLineWidth, cTop, cLead, cTrail, cWidth, cBottom,
        ]
        titleToSeparatorConstraint = titleLabel.bottomAnchor.constraint(
            equalTo: separatorLine.topAnchor, constant: -16)
        titleToSeparatorConstraint?.isActive = false

        NSLayoutConstraint.activate(previewConstraints)
        NSLayoutConstraint.activate([
            separatorLine.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setPreviewBlockVisible(_ visible: Bool) {
        if visible {
            titleToSeparatorConstraint?.isActive = false
            NSLayoutConstraint.activate(previewConstraints)
        } else {
            NSLayoutConstraint.deactivate(previewConstraints)
            titleToSeparatorConstraint?.isActive = true
        }
    }

    private func startAvatarSkeleton() {
        avatarSkeleton.isHidden = false
        avatarSkeleton.backgroundColor = UIColor.theme.tertiary
        avatarSkeleton.layer.removeAnimation(forKey: "notifSk")
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0.45
        a.toValue = 1
        a.duration = 0.8
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        avatarSkeleton.layer.add(a, forKey: "notifSk")
    }

    private func stopAvatarSkeleton() {
        avatarSkeleton.isHidden = true
        avatarSkeleton.layer.removeAnimation(forKey: "notifSk")
    }

    func configure(with item: NotificationItem) {
        titleLabel.text = item.subject
        let body = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        contentLabel.text = body.isEmpty ? nil : item.content
        setPreviewBlockVisible(!body.isEmpty)

        let avatarSeed = item.avatarPlaceholderSeed
        avatarPlaceholder.text =
            avatarSeed.first.map { String($0).uppercased() } ?? "N"

        let rawAvatarURL = item.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawAvatarURL.isEmpty, rawAvatarURL != "default" {
            let avatarURL = ImgproxyURL.absoluteResourceURL(from: rawAvatarURL)
            loadAvatar(sourceURL: avatarURL, placeholderSeed: avatarSeed)
        } else {
            avatarLoadGeneration += 1
            configuredAvatarURLString = nil
            isAvatarLoadInFlight = false
            showAvatarPlaceholder(seed: avatarSeed)
        }

        let date = Date(timeIntervalSince1970: TimeInterval(item.createTimeSeconds))
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 {
            timeLabel.text = "Just now"
        } else if diff < 3600 {
            timeLabel.text = "\(diff / 60)m"
        } else if diff < 86400 {
            timeLabel.text = "\(diff / 3600)h"
        } else {
            timeLabel.text = "\(diff / 86400)d"
        }

        let t = UIColor.theme
        titleLabel.textColor = t.textStrong
        contentLabel.textColor = t.text
        timeLabel.textColor = t.textDisabled
        verticalLine.backgroundColor = t.border
        separatorLine.backgroundColor = t.borderDim
        avatarPlaceholder.textColor = .white
    }

    private func loadAvatar(sourceURL: String, placeholderSeed: String) {
        if configuredAvatarURLString == sourceURL,
           isAvatarLoadInFlight || avatarView.image != nil {
            return
        }

        configuredAvatarURLString = sourceURL
        avatarLoadGeneration += 1
        let generation = avatarLoadGeneration
        let proxiedURL = ImgproxyURL.avatarProxyURL(from: sourceURL, width: 100, height: 100)
        let previewURL = ImgproxyURL.avatarPreviewProxyURL(
            from: sourceURL,
            width: 100,
            height: 100
        )

        if let cached = ImageCache.shared.memoryOptimizedAvatar(
            forURL: proxiedURL,
            targetPixelSize: Self.avatarTargetPixelSize
        ) ?? ImageCache.shared.memoryOptimizedAvatar(
            forURL: sourceURL,
            targetPixelSize: Self.avatarTargetPixelSize
        ) {
            isAvatarLoadInFlight = false
            showAvatarImage(cached)
            return
        }

        avatarView.stopAnimating()
        avatarView.image = nil
        avatarView.backgroundColor = .clear
        avatarPlaceholder.isHidden = true
        isAvatarLoadInFlight = true
        startAvatarSkeleton()

        let showPreview: (UIImage) -> Void = { [weak self] image in
            guard let self,
                  generation == self.avatarLoadGeneration,
                  self.isAvatarLoadInFlight else { return }
            self.showAvatarImage(image)
        }
        let hasRawDiskCache = ImageCache.shared.hasOptimizedAvatarDiskCache(
            forURL: sourceURL,
            targetPixelSize: Self.avatarTargetPixelSize
        )
        if !hasRawDiskCache, previewURL != proxiedURL {
            if let preview = ImageCache.shared.memoryImage(forKey: previewURL) {
                showPreview(preview)
            } else {
                ImageCache.shared.loadImage(urlString: previewURL) { image in
                    guard let image else { return }
                    showPreview(image)
                }
            }
        }

        let loadRawAvatar: () -> Void = {
            ImageCache.shared.loadOptimizedAvatar(
                urlString: sourceURL,
                targetPixelSize: Self.avatarTargetPixelSize,
                preview: showPreview
            ) { [weak self] image in
                guard let self, generation == self.avatarLoadGeneration else { return }
                self.isAvatarLoadInFlight = false
                if let image {
                    self.showAvatarImage(image)
                } else {
                    self.showAvatarPlaceholder(seed: placeholderSeed)
                }
            }
        }
        if hasRawDiskCache {
            loadRawAvatar()
            return
        }

        ImageCache.shared.loadOptimizedAvatar(
            urlString: proxiedURL,
            targetPixelSize: Self.avatarTargetPixelSize,
            preview: showPreview
        ) { [weak self] image in
            if let image {
                guard let self, generation == self.avatarLoadGeneration else { return }
                self.isAvatarLoadInFlight = false
                self.showAvatarImage(image)
            } else if proxiedURL != sourceURL {
                loadRawAvatar()
            } else {
                guard let self, generation == self.avatarLoadGeneration else { return }
                self.isAvatarLoadInFlight = false
                self.showAvatarPlaceholder(seed: placeholderSeed)
            }
        }
    }

    private func showAvatarImage(_ image: UIImage) {
        stopAvatarSkeleton()
        avatarView.stopAnimating()
        avatarView.image = image
        avatarView.backgroundColor = .clear
        avatarPlaceholder.isHidden = true
        if (image.images?.count ?? 0) > 1 {
            avatarView.startAnimating()
        }
    }

    private func showAvatarPlaceholder(seed: String) {
        stopAvatarSkeleton()
        avatarView.stopAnimating()
        avatarView.image = nil
        avatarView.backgroundColor = UIColor.avatarColor(for: seed)
        avatarPlaceholder.isHidden = false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadGeneration += 1
        configuredAvatarURLString = nil
        isAvatarLoadInFlight = false
        stopAvatarSkeleton()
        avatarView.stopAnimating()
        avatarView.image = nil
        avatarView.backgroundColor = .clear
        avatarPlaceholder.isHidden = false
        avatarPlaceholder.text = nil
    }
}


final class NotificationsContainerNode: ASDisplayNode {


    private struct TabInfo {
        let title: String
        let tag: Int32
        let iconName: String
    }


    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let tabScrollView = UIScrollView()
    private let tabStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let loadingIndicator = UIActivityIndicatorView.mezonMedium()

    private let emptyStateStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isHidden = true
        return sv
    }()
    private let emptyImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let emptyTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.textColor = .mezonTextPrimary
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let emptyDescLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14)
        l.textColor = .mezonTextSecondary
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var tabButtons: [UIButton] = []


    private var state: NotificationsState = .empty
    private let disposables = DisposableSet()
    private let interaction: NotificationsInteraction

    private let tabs: [TabInfo] = [
        TabInfo(title: L(L10n.Notifications.mentions), tag: 1, iconName: "Notifications/mentions"),
        TabInfo(title: L(L10n.Notifications.messages), tag: 2, iconName: "Notifications/messages"),
        TabInfo(title: L(L10n.Notifications.topic), tag: NotificationTabCategory.topic, iconName: "Notifications/topic"),
        TabInfo(title: L(L10n.Notifications.forYou), tag: 3, iconName: "Notifications/forYou"),
    ]
    private var selectedTabIndex: Int = 0


    init(signal: Signal<NotificationsState, NoError>, interaction: NotificationsInteraction) {
        self.interaction = interaction
        super.init()
        let t0 = UIColor.theme
        backgroundColor = t0.secondary

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.prefetchAvatarImages(for: Array(newState.items.prefix(16)))
                self.tableView.reloadData()
                let isEmpty =
                    newState.items.isEmpty && !newState.isLoading && newState.hasLoaded
                self.emptyStateStack.isHidden = !isEmpty
                if newState.isLoading {
                    self.loadingIndicator.startAnimating()
                } else {
                    self.loadingIndicator.stopAnimating()
                }

                if newState.isLoadingMore {
                    let spinner = UIActivityIndicatorView.mezonMedium()
                    spinner.startAnimating()
                    spinner.frame = CGRect(
                        x: 0, y: 0, width: self.tableView.bounds.width, height: 44)
                    self.tableView.tableFooterView = spinner
                } else {
                    self.tableView.tableFooterView = nil
                }
            })
        )
    }

    deinit { disposables.dispose() }


    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        backgroundColor = t.primary
        view.backgroundColor = t.primary
        tableView.isOpaque = false
        tableView.backgroundView = nil

        titleLabel.text = L(L10n.Notifications.title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary

        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.showsVerticalScrollIndicator = false

        tabStackView.axis = .horizontal
        tabStackView.spacing = 8
        tabStackView.alignment = .center
        tabStackView.distribution = .fill

        tabScrollView.addSubview(tabStackView)
        buildTabButtons()


        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.register(
            NotificationItemCell.self, forCellReuseIdentifier: NotificationItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.prefetchDataSource = self


        emptyImageView.image = UIImage(named: "Notifications/emptyNotifications")
        emptyImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            emptyImageView.widthAnchor.constraint(equalToConstant: 300),
            emptyImageView.heightAnchor.constraint(equalToConstant: 300),
        ])
        emptyTitleLabel.text = L(L10n.Notifications.emptyTitle)
        emptyDescLabel.text = L(L10n.Notifications.emptyDescription)

        emptyStateStack.addArrangedSubview(emptyTitleLabel)
        emptyStateStack.addArrangedSubview(emptyDescLabel)
        emptyStateStack.addArrangedSubview(emptyImageView)


        loadingIndicator.hidesWhenStopped = true

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        view.addSubview(tabScrollView)
        view.addSubview(tableView)
        view.addSubview(emptyStateStack)
        view.addSubview(loadingIndicator)


        NSLayoutConstraint.activate([
            emptyStateStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),
            emptyStateStack.widthAnchor.constraint(
                equalTo: view.widthAnchor, multiplier: 0.7),
        ])

        applyTheme()
    }


    private var lastLayout: ContainerViewLayout?

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        lastLayout = layout
        applyLayout(transition: transition)
    }

    private let listHeaderTopPadding: CGFloat = 8.sh

    private func resolvedNotificationsListTop(layout: ContainerViewLayout) -> CGFloat {
        let vTop = isNodeLoaded ? view.safeAreaInsets.top : 0
        let base = max(vTop, layout.safeInsets.top, layout.statusBarHeight ?? 0)
        return base + listHeaderTopPadding
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }

        if layer.maskedCorners != [.layerMinXMinYCorner] {
            layer.cornerRadius = 20.swh
            layer.maskedCorners = [.layerMinXMinYCorner]
            clipsToBounds = true
        }

        let listTopY = resolvedNotificationsListTop(layout: layout)

        let sideInset: CGFloat = 16
        let headerH: CGFloat = 44
        let tabH: CGFloat = 40
        let tabScrollY = listTopY + headerH + 4

        transition.updateFrame(
            view: headerView,
            frame: CGRect(x: 0, y: listTopY, width: layout.size.width, height: headerH))
        transition.updateFrame(
            view: titleLabel,
            frame: CGRect(
                x: sideInset, y: 0,
                width: layout.size.width - sideInset * 2, height: headerH))
        transition.updateFrame(
            view: tabScrollView,
            frame: CGRect(
                x: sideInset, y: tabScrollY, width: layout.size.width - sideInset * 2, height: tabH)
        )
        let stackWidth = tabStackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            .width
        tabStackView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: stackWidth, height: tabH))
        tabScrollView.contentSize = tabStackView.frame.size

        let tvTop = tabScrollY + tabH + 12
        let tvHeight = layout.size.height - tvTop - layout.intrinsicInsets.bottom
        transition.updateFrame(
            view: tableView,
            frame: CGRect(x: 0, y: tvTop, width: layout.size.width, height: max(0, tvHeight)))

        let liS: CGFloat = 24
        transition.updateFrame(
            view: loadingIndicator,
            frame: CGRect(
                x: (layout.size.width - liS) / 2, y: (layout.size.height - liS) / 2, width: liS,
                height: liS))
    }

    override func layout() {
        super.layout()
        applyLayout(transition: .immediate)
    }


    private func buildTabButtons() {
        tabButtons.removeAll()
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tab) in tabs.enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = index

            if #available(iOS 15.0, *) {
                var cfg = UIButton.Configuration.filled()
                cfg.cornerStyle = .fixed
                cfg.background.cornerRadius = 8
                cfg.imagePadding = 2
                cfg.contentInsets = NSDirectionalEdgeInsets(
                    top: 8, leading: 12, bottom: 6, trailing: 10)
                cfg.attributedTitle = AttributedString(
                    tab.title,
                    attributes: AttributeContainer([
                        .font: UIFont.systemFont(ofSize: 12, weight: .medium)
                    ])
                )

                if let raw = UIImage(named: tab.iconName) {
                    let iconSize = CGSize(width: 16, height: 18)
                    let ratio = min(16 / raw.size.width, 16 / raw.size.height)
                    let drawSize = CGSize(
                        width: raw.size.width * ratio, height: raw.size.height * ratio)
                    let origin = CGPoint(
                        x: (iconSize.width - drawSize.width) / 2,
                        y: 0)
                    let renderer = UIGraphicsImageRenderer(size: iconSize)
                    let resized = renderer.image { _ in
                        raw.draw(in: CGRect(origin: origin, size: drawSize))
                    }
                    cfg.image = resized.withRenderingMode(.alwaysOriginal)
                }

                btn.configuration = cfg
            } else {
                btn.setTitle(tab.title, for: .normal)
                btn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
                btn.layer.cornerRadius = 8
                btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 6, right: 10)
                if let raw = UIImage(named: tab.iconName) {
                    let iconSize = CGSize(width: 16, height: 18)
                    let ratio = min(16 / raw.size.width, 16 / raw.size.height)
                    let drawSize = CGSize(
                        width: raw.size.width * ratio, height: raw.size.height * ratio)
                    let origin = CGPoint(
                        x: (iconSize.width - drawSize.width) / 2,
                        y: 0)
                    let renderer = UIGraphicsImageRenderer(size: iconSize)
                    let resized = renderer.image { _ in
                        raw.draw(in: CGRect(origin: origin, size: drawSize))
                    }
                    btn.setImage(resized.withRenderingMode(.alwaysOriginal), for: .normal)
                }
            }
            btn.clipsToBounds = false
            btn.layer.masksToBounds = false
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            btn.accessibilityIdentifier = "notif_tab_\(index)"
            tabStackView.addArrangedSubview(btn)
            tabButtons.append(btn)
        }
        updateTabStyles()
    }

    private func updateTabStyles() {
        let t = UIColor.theme
        for (i, btn) in tabButtons.enumerated() {
            let selected = i == selectedTabIndex

            if #available(iOS 15.0, *) {
                var cfg = btn.configuration
                if selected {
                    cfg?.baseBackgroundColor = t.bgViolet
                    cfg?.baseForegroundColor = .white
                    cfg?.background.strokeWidth = 0
                } else {
                    cfg?.baseBackgroundColor = t.secondaryLight
                    cfg?.baseForegroundColor = t.textDisabled
                    cfg?.background.strokeColor = t.borderDim
                    cfg?.background.strokeWidth = 1
                }
                btn.configuration = cfg
            } else {
                if selected {
                    btn.backgroundColor = t.bgViolet
                    btn.setTitleColor(.white, for: .normal)
                    btn.layer.borderWidth = 0
                } else {
                    btn.backgroundColor = t.secondaryLight
                    btn.setTitleColor(t.textDisabled, for: .normal)
                    btn.layer.borderColor = t.borderDim.cgColor
                    btn.layer.borderWidth = 1
                }
            }
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index != selectedTabIndex else { return }
        selectedTabIndex = index
        updateTabStyles()
        interaction.onTabSelected(tabs[index].tag)
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        if isNodeLoaded {
            view.backgroundColor = t.secondary
        }
        tableView.backgroundColor = .clear
        headerView.backgroundColor = .clear
        tabScrollView.backgroundColor = .clear

        titleLabel.textColor = t.textStrong

        emptyTitleLabel.textColor = t.textStrong
        emptyDescLabel.textColor = t.textDisabled

        updateTabStyles()
        tableView.reloadData()
    }

    private func prefetchAvatarImages(for items: [NotificationItem]) {
        for item in items {
            let rawAvatarURL = item.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawAvatarURL.isEmpty, rawAvatarURL != "default" else { continue }
            let sourceURL = ImgproxyURL.absoluteResourceURL(from: rawAvatarURL)
            guard !sourceURL.isEmpty else { continue }

            let proxiedURL = ImgproxyURL.avatarProxyURL(
                from: sourceURL,
                width: 100,
                height: 100
            )
            let previewURL = ImgproxyURL.avatarPreviewProxyURL(
                from: sourceURL,
                width: 100,
                height: 100
            )
            let targetPixelSize = 120
            let hasRawDiskCache = ImageCache.shared.hasOptimizedAvatarDiskCache(
                forURL: sourceURL,
                targetPixelSize: targetPixelSize
            )

            if !hasRawDiskCache,
               previewURL != proxiedURL,
               ImageCache.shared.memoryImage(forKey: previewURL) == nil {
                ImageCache.shared.loadImage(urlString: previewURL) { _ in }
            }

            let cached = ImageCache.shared.memoryOptimizedAvatar(
                forURL: proxiedURL,
                targetPixelSize: targetPixelSize
            ) ?? ImageCache.shared.memoryOptimizedAvatar(
                forURL: sourceURL,
                targetPixelSize: targetPixelSize
            )
            guard cached == nil else { continue }

            let loadURL = hasRawDiskCache ? sourceURL : proxiedURL
            ImageCache.shared.loadOptimizedAvatar(
                urlString: loadURL,
                targetPixelSize: targetPixelSize
            ) { image in
                guard image == nil, loadURL != sourceURL else { return }
                ImageCache.shared.loadOptimizedAvatar(
                    urlString: sourceURL,
                    targetPixelSize: targetPixelSize
                ) { _ in }
            }
        }
    }
}


extension NotificationsContainerNode: UITableViewDataSource, UITableViewDelegate,
    UITableViewDataSourcePrefetching {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell =
            tableView.dequeueReusableCell(
                withIdentifier: NotificationItemCell.reuseId, for: indexPath)
            as! NotificationItemCell
        cell.configure(with: state.items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        interaction.onItemSelected(state.items[indexPath.row])
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let items = indexPaths.compactMap { indexPath -> NotificationItem? in
            guard indexPath.row >= 0, indexPath.row < state.items.count else { return nil }
            return state.items[indexPath.row]
        }
        prefetchAvatarImages(for: items)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height

        if offsetY > 0 && offsetY > contentHeight - height - 50 {
            if !state.isLoading && !state.isLoadingMore && !state.items.isEmpty {
                interaction.onLoadMore()
            }
        }
    }
}
