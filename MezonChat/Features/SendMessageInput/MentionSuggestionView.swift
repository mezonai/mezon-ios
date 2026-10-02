import UIKit

struct MentionMember: Equatable {
    let userId: Int64
    let displayName: String
    let username: String
    let avatarURL: String?
}

enum MentionSuggestionItem: Equatable {
    case user(MentionMember)
    case role(id: Int64, title: String, colorHex: String, iconURL: String?)
    case here

    var sortKey: String {
        switch self {
        case .user(let m): return m.displayName.lowercased()
        case .role(_, let title, _, _): return title.lowercased()
        case .here: return "here"
        }
    }
}

final class MentionSuggestionView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelectItem: ((MentionSuggestionItem) -> Void)?
    private(set) var items: [MentionSuggestionItem] = []

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.rowHeight = 44
        tv.bounces = true
        tv.keyboardDismissMode = .none
        tv.register(MentionSuggestionCell.self, forCellReuseIdentifier: "MentionCell")
        return tv
    }()

    private static let maxVisibleRows = 5
    static let rowHeight: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        clipsToBounds = true
        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        tableView.dataSource = self
        tableView.delegate = self
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.secondary
        tableView.backgroundColor = t.secondary
    }

    func update(items: [MentionSuggestionItem]) {
        self.items = items
        tableView.reloadData()
    }

    var preferredHeight: CGFloat {
        let rows = min(items.count, Self.maxVisibleRows)
        return CGFloat(rows) * Self.rowHeight
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MentionCell", for: indexPath) as! MentionSuggestionCell
        let item = items[indexPath.row]
        cell.configure(item: item)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let item = items[indexPath.row]
        onSelectItem?(item)
    }
}

private final class MentionSuggestionCell: UITableViewCell {

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.layer.cornerRadius = 14
        return iv
    }()

    private let placeholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.textAlignment = .center
        lbl.font = .systemFont(ofSize: 12, weight: .semibold)
        lbl.textColor = .white
        return lbl
    }()

    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        return lbl
    }()

    private let usernameLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        lbl.textAlignment = .right
        return lbl
    }()

    private var avatarWidthConstraint: NSLayoutConstraint!
    private var nameLeadingToAvatarConstraint: NSLayoutConstraint!
    private var nameLeadingToContentConstraint: NSLayoutConstraint!
    private var currentAvatarTask: URLSessionDataTask?
    private var currentAvatarURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        selectionStyle = .none
        contentView.addSubview(avatarImageView)
        contentView.addSubview(placeholderLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(usernameLabel)

        avatarWidthConstraint = avatarImageView.widthAnchor.constraint(equalToConstant: 28)
        nameLeadingToAvatarConstraint = nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10)
        nameLeadingToContentConstraint = nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarWidthConstraint,
            avatarImageView.heightAnchor.constraint(equalToConstant: 28),

            placeholderLabel.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),

            nameLeadingToAvatarConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: usernameLabel.leadingAnchor, constant: -8),

            usernameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            usernameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            usernameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
        ])
    }

    func configure(item: MentionSuggestionItem) {
        let t = UIColor.theme
        backgroundColor = t.secondary
        contentView.backgroundColor = t.secondary
        cancelAvatarLoad()
        avatarImageView.isHidden = false
        placeholderLabel.isHidden = true
        avatarImageView.image = nil
        avatarImageView.tintColor = nil
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 14
        avatarWidthConstraint.constant = 28
        nameLeadingToContentConstraint.isActive = false
        nameLeadingToAvatarConstraint.isActive = true

        switch item {
        case .user(let member):
            nameLabel.textColor = t.textStrong
            usernameLabel.textColor = t.textDisabled
            nameLabel.text = member.displayName
            usernameLabel.text = member.username

            if let raw = member.avatarURL, !raw.isEmpty {
                let proxied = ImgproxyURL.create(from: raw, width: 56, height: 56)
                if let imageURL = URL(string: proxied) {
                    placeholderLabel.isHidden = true
                    avatarImageView.backgroundColor = UIColor.avatarColor(for: member.username)
                    loadAvatar(from: imageURL, key: proxied)
                } else {
                    showPlaceholder(for: member.displayName, username: member.username)
                }
            } else {
                showPlaceholder(for: member.displayName, username: member.username)
            }

        case .role(_, let title, let colorHex, let iconURL):
            nameLabel.textColor = UIColor(hexString: colorHex) ?? t.textRoleLink
            usernameLabel.textColor = t.textDisabled
            usernameLabel.text = ""
            nameLabel.text = title
            let accent = UIColor(hexString: colorHex) ?? t.textRoleLink
            if let s = iconURL, !s.isEmpty {
                let proxied = ImgproxyURL.create(from: s, width: 56, height: 56)
                if let imageURL = URL(string: proxied) {
                    avatarImageView.backgroundColor = .clear
                    avatarImageView.contentMode = .scaleAspectFit
                    loadAvatar(from: imageURL, key: proxied)
                } else {
                    showRolePlaceholder(accent: accent)
                }
            } else {
                showRolePlaceholder(accent: accent)
            }

        case .here:
            nameLabel.textColor = t.textRoleLink
            usernameLabel.text = ""
            nameLabel.text = "@here"
            avatarImageView.isHidden = true
            avatarWidthConstraint.constant = 0
            nameLeadingToAvatarConstraint.isActive = false
            nameLeadingToContentConstraint.isActive = true
        }
    }

    private func showPlaceholder(for displayName: String, username: String) {
        avatarImageView.backgroundColor = UIColor.avatarColor(for: username)
        let initial = String(username.prefix(1)).uppercased()
        placeholderLabel.text = initial
        placeholderLabel.isHidden = false
    }

    private func showRolePlaceholder(accent: UIColor) {
        avatarImageView.backgroundColor = .clear
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.image = UIImage(systemName: "shield.fill")?.withRenderingMode(.alwaysTemplate)
        avatarImageView.tintColor = accent
    }

    private func cancelAvatarLoad() {
        currentAvatarTask?.cancel()
        currentAvatarTask = nil
        currentAvatarURL = nil
    }

    private func loadAvatar(from url: URL, key: String) {
        currentAvatarURL = key
        if let cached = ImageCache.shared.image(forKey: key) {
            avatarImageView.image = cached
            avatarImageView.backgroundColor = .clear
            return
        }
        avatarImageView.image = nil
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            ImageCache.shared.setImage(image, data: data, forKey: key)
            DispatchQueue.main.async {
                guard let self, self.currentAvatarURL == key else { return }
                self.avatarImageView.image = image
                self.avatarImageView.backgroundColor = .clear
            }
        }
        currentAvatarTask = task
        task.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelAvatarLoad()
        avatarImageView.image = nil
        avatarImageView.tintColor = nil
        avatarImageView.backgroundColor = .clear
        placeholderLabel.text = nil
        placeholderLabel.textColor = .white
        nameLabel.text = nil
        usernameLabel.text = nil
        avatarImageView.isHidden = false
    }
}

@MainActor
final class MentionRemoteSearch {

    struct Result {
        let users: [Mezon_Api_MentionUser]
        let pending: Bool

        static let none = Result(users: [], pending: false)
    }

    typealias Fetch = @MainActor (_ clanId: Int64, _ channelId: Int64, _ text: String) async throws -> [Mezon_Api_MentionUser]

    private struct Answer {
        let users: [Mezon_Api_MentionUser]
        let complete: Bool
        let failed: Bool
    }

    private static let minQueryCharacters = 2
    private static let maxQueryCharacters = 64
    private static let serverPageSize = 50
    private static let debounceInterval: TimeInterval = 0.2
    private static let unsupportedRetryInterval: TimeInterval = 600
    private static let maxCachedAnswers = 32
    private static let unknownApiStatusCode = 404
    private static var unsupportedUntil = Date.distantPast

    var onAnswer: (() -> Void)?

    private let fetch: Fetch
    private var scopeClanId: Int64 = 0
    private var scopeChannelId: Int64 = 0
    private var generation = 0
    private var answers: [String: Answer] = [:]
    private var answerOrder: [String] = []
    private var wantedKey: String?
    private var wantedText = ""
    private var lastInputAt = Date.distantPast
    private var debounceToken = 0
    private var requestInFlight = false

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func search(clanId: Int64, channelId: Int64, rosterCapped: Bool, keyword: String) -> Result {
        let text = keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let now = Date()
        guard clanId != 0, rosterCapped, Self.isSearchable(text), now >= Self.unsupportedUntil else {
            cancelPending()
            return .none
        }
        if scopeClanId != clanId || scopeChannelId != channelId {
            reset()
            scopeClanId = clanId
            scopeChannelId = channelId
        }
        let key = text.lowercased()
        if let known = lookup(key) {
            cancelPending()
            return Result(users: known, pending: false)
        }
        if wantedKey != key {
            wantedKey = key
            wantedText = text
            lastInputAt = now
            schedule(now: now)
        }
        return Result(users: [], pending: true)
    }

    func cancelPending() {
        wantedKey = nil
        wantedText = ""
        debounceToken += 1
    }

    func endSession() {
        cancelPending()
        let failedKeys = Set(answerOrder.filter { answers[$0]?.failed == true })
        guard !failedKeys.isEmpty else { return }
        for key in failedKeys {
            answers[key] = nil
        }
        answerOrder.removeAll { failedKeys.contains($0) }
    }

    func containsUser(_ userId: Int64) -> Bool {
        answers.values.contains { answer in answer.users.contains { $0.id == userId } }
    }

    private func reset() {
        generation += 1
        answers.removeAll()
        answerOrder.removeAll()
        cancelPending()
    }

    private static func isSearchable(_ text: String) -> Bool {
        if text.contains("  ") || text.contains(where: \.isNewline) { return false }
        let characters = text.unicodeScalars.filter { $0.properties.generalCategory != .control }.count
        return (minQueryCharacters...maxQueryCharacters).contains(characters)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }

    private static func matches(_ user: Mezon_Api_MentionUser, words: [String]) -> Bool {
        let fields = [user.username, user.displayName, user.clanNick].map(folded)
        return words.allSatisfy { word in fields.contains { $0.contains(word) } }
    }

    private static func uniqueUsers(_ users: [Mezon_Api_MentionUser]) -> [Mezon_Api_MentionUser] {
        var seen = Set<Int64>()
        return users.filter { $0.id != 0 && seen.insert($0.id).inserted }
    }

    private static func isUnknownApi(_ error: Error) -> Bool {
        if case MezonError.httpError(let statusCode, _) = error {
            return statusCode == unknownApiStatusCode
        }
        return false
    }

    private func lookup(_ key: String) -> [Mezon_Api_MentionUser]? {
        if let answer = answers[key] { return answer.users }
        for prefix in answerOrder {
            guard let answer = answers[prefix], answer.complete, key.hasPrefix(prefix) else { continue }
            let words = Self.folded(key).split(separator: " ").map(String.init)
            return answer.users.filter { Self.matches($0, words: words) }
        }
        return nil
    }

    private func store(_ answer: Answer, for key: String) {
        if answers[key] == nil { answerOrder.append(key) }
        answers[key] = answer
        if answerOrder.count > Self.maxCachedAnswers {
            answers[answerOrder.removeFirst()] = nil
        }
    }

    private func schedule(now: Date) {
        debounceToken += 1
        let token = debounceToken
        guard !requestInFlight else { return }
        let wait = max(0, Self.debounceInterval - now.timeIntervalSince(lastInputAt))
        Task { @MainActor [weak self] in
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            await self?.runRequest(token: token)
        }
    }

    private func runRequest(token: Int) async {
        guard token == debounceToken, !requestInFlight, let key = wantedKey, lookup(key) == nil else { return }
        requestInFlight = true
        let requestGeneration = generation
        let text = wantedText
        let answer: Answer
        do {
            let users = try await fetch(scopeClanId, scopeChannelId, text)
            answer = Answer(
                users: Self.uniqueUsers(users),
                complete: users.count < Self.serverPageSize,
                failed: false
            )
        } catch {
            if Self.isUnknownApi(error) {
                Self.unsupportedUntil = Date().addingTimeInterval(Self.unsupportedRetryInterval)
            }
            answer = Answer(users: [], complete: false, failed: true)
        }
        requestInFlight = false
        let answersCurrentScope = requestGeneration == generation
        if answersCurrentScope {
            store(answer, for: key)
        }
        if let wanted = wantedKey, lookup(wanted) == nil {
            schedule(now: Date())
        }
        if answersCurrentScope {
            onAnswer?()
        }
    }
}
