import UIKit
import SwiftProtobuf

private enum ForwardOutgoing {
    private static let maxExtraTextLen = 2000

    static func contentJSONString(for record: MessageRecord) -> String {
        if var dict = try? JSONSerialization.jsonObject(with: record.content) as? [String: Any] {
            dict["fwd"] = true
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        return #"{"fwd":true}"#
    }

    static func attachments(for record: MessageRecord) -> [Mezon_Api_MessageAttachment] {
        guard !record.attachmentsJSON.isEmpty else { return [] }
        if let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: record.attachmentsJSON) {
            return list.attachments
        }
        return []
    }

    static func mentions(
        record: MessageRecord,
        destinationChannelID: Int64,
        forwardFromChannelID: Int64
    ) -> [Mezon_Api_MessageMention] {
        guard forwardFromChannelID == destinationChannelID else { return [] }
        return MentionPayload.parseList(from: record.mentionsJSON)
    }

    static func sanitizedComment(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func commentContentJSON(trimmed: String) -> String? {
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > maxExtraTextLen { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: ["t": trimmed]),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
}

private enum MentionPayload {
    static func parseList(from data: Data) -> [Mezon_Api_MessageMention] {
        guard !data.isEmpty else { return [] }
        if let list = try? Mezon_Api_MessageMentionList(serializedBytes: data), !list.mentions.isEmpty {
            return list.mentions
        }
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { item in
                var m = Mezon_Api_MessageMention()
                if let uid = item["user_id"] as? String, let v = Int64(uid) {
                    m.userID = v
                } else if let uid = item["user_id"] as? Int64 {
                    m.userID = uid
                } else if let uid = item["user_id"] as? Double {
                    m.userID = Int64(uid)
                }
                if let rid = item["role_id"] as? String, let v = Int64(rid) {
                    m.roleID = v
                } else if let rid = item["role_id"] as? Int64 {
                    m.roleID = rid
                } else if let rid = item["role_id"] as? Double {
                    m.roleID = Int64(rid)
                }
                return m
            }
        }
        return []
    }
}

final class ForwardMessageViewController: UIViewController {

    private let context: AccountContext
    private let messagesToForward: [MessageRecord]
    private let forwardFromChannelID: Int64

    private var suggestions: [SharingSuggestionItem] = []
    private var filteredItems: [SharingSuggestionItem] = []
    private var channelMap: [Int64: Mezon_Api_ChannelDescription] = [:]
    private var clanNames: [Int64: String] = [:]
    private var clanLogos: [Int64: String] = [:]

    private var selectedIDs: Set<Int64> = []
    private var searchText = ""
    private var isSending = false

    private lazy var closeButton = UIButton(type: .system)
    private lazy var titleLbl = UILabel()
    private lazy var searchWrap = UIView()
    private lazy var searchIcon = UIImageView()
    private lazy var searchField = UITextField()
    private lazy var previewCard = UIView()
    private lazy var previewLbl = UILabel()
    private lazy var tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.separatorStyle = .none
        t.keyboardDismissMode = .interactive
        return t
    }()
    private lazy var inputBg = UIView()
    private lazy var commentField = UITextField()
    private lazy var sendBtn = UIButton(type: .system)
    private let bottomBar = UIView()

    private var bottomLiftConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?
    private var isKeyboardVisible = false

    init(
        context: AccountContext,
        messagesToForward: [MessageRecord],
        forwardFromChannelID: Int64
    ) {
        self.context = context
        self.messagesToForward = messagesToForward
        self.forwardFromChannelID = forwardFromChannelID
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { ThemeManager.shared.preferredStatusBarStyle }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShowNotification(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(langChanged), name: LanguageManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: ThemeManager.didChangeNotification, object: nil)
        setupUI()
        applyThemeStrings()
        loadDestinations()
    }

    private func applyThemeStrings() {
        titleLbl.text = L(L10n.Forward.screenTitle)
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Common.search),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        commentField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Sharing.commentPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled.withAlphaComponent(0.85)]
        )
        updatePreviewLabel()
        tableView.reloadData()
    }

    @objc private func langChanged() {
        applyThemeStrings()
    }

    @objc private func themeChanged() {
        applyTheme()
        applyThemeStrings()
        tableView.reloadData()
    }

    private func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        closeButton.tintColor = t.textStrong
        titleLbl.textColor = t.textStrong
        searchWrap.backgroundColor = t.secondary
        searchIcon.tintColor = t.textDisabled
        searchField.textColor = t.textStrong
        previewCard.backgroundColor = t.secondary
        previewLbl.textColor = t.textStrong
        inputBg.backgroundColor = t.secondary
        commentField.textColor = t.textStrong
        refreshSendButtonVisual()
    }

    private func setupUI() {
        let cc = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: cc), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLbl.font = .systemFont(ofSize: 20, weight: .bold)
        titleLbl.textAlignment = .center

        searchWrap.layer.cornerRadius = 20
        searchIcon.image = UIImage(systemName: "magnifyingglass")
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.font = .systemFont(ofSize: 15)
        searchField.autocorrectionType = .no
        searchField.addTarget(self, action: #selector(searchChanged(_:)), for: .editingChanged)

        previewCard.layer.cornerRadius = 12
        previewLbl.font = .systemFont(ofSize: 14)
        previewLbl.numberOfLines = 4

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SharingChannelCell.self, forCellReuseIdentifier: SharingChannelCell.reuseId)
        tableView.backgroundColor = .clear

        inputBg.layer.cornerRadius = 22
        commentField.font = .systemFont(ofSize: 15)
        commentField.borderStyle = .none
        commentField.backgroundColor = .clear

        sendBtn.layer.cornerRadius = 20
        sendBtn.clipsToBounds = true
        let sendCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let sendImg = UIImage(named: "Chat/SendMessageIcon")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: "paperplane.fill", withConfiguration: sendCfg)
        sendBtn.setImage(sendImg, for: .normal)
        sendBtn.imageView?.contentMode = .scaleAspectFit
        let iconInset: CGFloat = 9
        sendBtn.imageEdgeInsets = UIEdgeInsets(top: iconInset, left: iconInset, bottom: iconInset, right: iconInset)
        sendBtn.isEnabled = false
        sendBtn.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        searchWrap.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewLbl.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        inputBg.translatesAutoresizingMaskIntoConstraints = false
        commentField.translatesAutoresizingMaskIntoConstraints = false
        sendBtn.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = .clear

        view.addSubview(closeButton)
        view.addSubview(titleLbl)
        view.addSubview(searchWrap)
        searchWrap.addSubview(searchIcon)
        searchWrap.addSubview(searchField)
        view.addSubview(previewCard)
        previewCard.addSubview(previewLbl)
        view.addSubview(tableView)
        view.addSubview(bottomBar)
        bottomBar.addSubview(inputBg)
        bottomBar.addSubview(sendBtn)
        inputBg.addSubview(commentField)

        let safe = view.safeAreaLayoutGuide
        let lift = bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
        bottomLiftConstraint = lift
        let composerPad = inputBg.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -8)
        composerBottomConstraint = composerPad

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: safe.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLbl.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            searchWrap.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 10),
            searchWrap.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchWrap.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchWrap.heightAnchor.constraint(equalToConstant: 40),

            searchIcon.leadingAnchor.constraint(equalTo: searchWrap.leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchWrap.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor),

            previewCard.topAnchor.constraint(equalTo: searchWrap.bottomAnchor, constant: 14),
            previewCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previewCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewLbl.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 10),
            previewLbl.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -10),
            previewLbl.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            previewLbl.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: 14),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lift,

            inputBg.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            inputBg.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            inputBg.heightAnchor.constraint(equalToConstant: 44),

            commentField.leadingAnchor.constraint(equalTo: inputBg.leadingAnchor, constant: 14),
            commentField.trailingAnchor.constraint(equalTo: inputBg.trailingAnchor, constant: -12),
            commentField.centerYAnchor.constraint(equalTo: inputBg.centerYAnchor),

            sendBtn.leadingAnchor.constraint(equalTo: inputBg.trailingAnchor, constant: 8),
            sendBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            sendBtn.centerYAnchor.constraint(equalTo: inputBg.centerYAnchor),
            sendBtn.widthAnchor.constraint(equalToConstant: 40),
            sendBtn.heightAnchor.constraint(equalToConstant: 40),

            composerPad,
        ])

        applyTheme()

        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset.bottom = 0
        tableView.verticalScrollIndicatorInsets.bottom = 0
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isKeyboardVisible else { return }
        let inset = max(view.safeAreaInsets.bottom, 8)
        composerBottomConstraint?.constant = -inset
    }

    private func refreshSendButtonVisual() {
        let t = UIColor.theme
        let sendBlue = UIColor(red: 0.34, green: 0.54, blue: 0.95, alpha: 1)
        sendBtn.alpha = 1
        guard sendBtn.isEnabled else {
            sendBtn.backgroundColor = t.borderDim
            sendBtn.tintColor = t.textDisabled
            return
        }
        sendBtn.backgroundColor = sendBlue
        sendBtn.tintColor = .white
    }

    @objc private func keyboardWillShowNotification(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        isKeyboardVisible = true
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        bottomLiftConstraint?.constant = -overlap
        composerBottomConstraint?.constant = -8
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHideNotification(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        isKeyboardVisible = false
        bottomLiftConstraint?.constant = 0
        let inset = max(view.safeAreaInsets.bottom, 8)
        composerBottomConstraint?.constant = -inset
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    private func sharingRecencyTimestamp(_ ch: Mezon_Api_ChannelDescription) -> UInt32 {
        if ch.hasLastSeenMessage { return ch.lastSeenMessage.timestampSeconds }
        if ch.hasLastSentMessage { return ch.lastSentMessage.timestampSeconds }
        return 0
    }

    private func resolvedClanInfo(for ch: Mezon_Api_ChannelDescription) -> (clanID: Int64, channelClanName: String) {
        var clanID = ch.clanID
        var channelClanName = ch.clanName
        if ch.type == MezonConstants.ChannelType.thread.rawValue, ch.parentID != 0,
            let parent = channelMap[ch.parentID] {
            if clanID == 0 {
                clanID = parent.clanID
            }
            if channelClanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                channelClanName = parent.clanName
            }
        }
        return (clanID, channelClanName)
    }

    private func loadDestinations() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await context.getToken() else { return }

            var dmList: [Mezon_Api_ChannelDescription] = []
            var clanList: [Mezon_Api_ChannelDescription] = []

            do {
                var dms = try await context.account.network.listDirectMessageChannels(token: token)
                do {
                    let badgeResponse = try await context.account.network.listChannelBadgeCount(clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &dms, badgeRows: badgeResponse.channeldesc)
                } catch {}

                dmList = dms.filter { ch in
                    guard ch.type != MezonConstants.ChannelType.mezonVoice.rawValue else { return false }
                    if !ch.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                    if ch.displayNames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
                    if ch.usernames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
                    return false
                }
                dmList.sort { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
            } catch {}

            if let allChannelsList = context.engine.clanData.getAllChannelsByUser() {
                clanList = allChannelsList.channeldesc.filter { ch in
                    let t = ch.type
                    return t == MezonConstants.ChannelType.channel.rawValue
                        || t == MezonConstants.ChannelType.thread.rawValue
                        || t == MezonConstants.ChannelType.announcement.rawValue
                }
                clanList.sort { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
            }

            do {
                let clanDescs = try await context.account.network.listClanDescs(token: token)
                for clan in clanDescs {
                    clanNames[clan.clanID] = clan.clanName
                    if !clan.logo.isEmpty {
                        clanLogos[clan.clanID] = clan.logo
                    }
                }
            } catch {}

            if clanList.isEmpty {
                do {
                    let fetched = try await context.account.network.listChannelByUserId(token: token)
                    if let data = try? fetched.serializedData() {
                        context.account.postbox.setPreferenceData(key: PreferencesKeys.allChannelsByUser, value: data)
                    }
                    clanList = fetched.channeldesc.filter { ch in
                        let t = ch.type
                        return t == MezonConstants.ChannelType.channel.rawValue
                            || t == MezonConstants.ChannelType.thread.rawValue
                            || t == MezonConstants.ChannelType.announcement.rawValue
                    }
                    clanList.sort { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
                } catch {}
            }

            channelMap.removeAll(keepingCapacity: true)
            for ch in dmList + clanList {
                channelMap[ch.channelID] = ch
            }

            var built: [SharingSuggestionItem] = []
            built.reserveCapacity(dmList.count + clanList.count)

            for ch in dmList {
                built.append(SharingSuggestionItem(
                    channelID: ch.channelID,
                    clanID: ch.clanID,
                    type: ch.type,
                    displayName: SharingChannelCell.displayName(for: ch),
                    avatarURL: ch.avatars.first,
                    channelAvatar: ch.channelAvatar,
                    channelPrivate: ch.channelPrivate,
                    ageRestricted: ch.ageRestricted,
                    clanName: nil,
                    clanLogo: nil
                ))
            }
            for ch in clanList {
                let (cid, chClanNameRaw) = resolvedClanInfo(for: ch)
                let mapName = (clanNames[cid] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let chClanName = chClanNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedClanName: String? = {
                    if !mapName.isEmpty { return mapName }
                    if !chClanName.isEmpty { return chClanName }
                    return nil
                }()
                built.append(SharingSuggestionItem(
                    channelID: ch.channelID,
                    clanID: cid,
                    type: ch.type,
                    displayName: SharingChannelCell.displayName(for: ch),
                    avatarURL: ch.avatars.first,
                    channelAvatar: ch.channelAvatar,
                    channelPrivate: ch.channelPrivate,
                    ageRestricted: ch.ageRestricted,
                    clanName: resolvedClanName,
                    clanLogo: clanLogos[cid]
                ))
            }

            suggestions = built
            applyFilter(resetSelection: false)
            tableView.reloadData()
        }
    }

    private func applyFilter(resetSelection _: Bool = false) {
        let trimmed = ForwardOutgoing.sanitizedComment(searchText)
        let hashtag = trimmed.lowercased().hasPrefix("#")

        func fold(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }

        func matches(_ item: SharingSuggestionItem, ch: Mezon_Api_ChannelDescription?, qRaw: String) -> Bool {
            if hashtag {
                let t = ch?.type ?? item.type
                return t == MezonConstants.ChannelType.channel.rawValue
                    || t == MezonConstants.ChannelType.thread.rawValue
                    || t == MezonConstants.ChannelType.announcement.rawValue
            }
            let q = fold(qRaw)
            guard !q.isEmpty else { return true }
            if fold(item.displayName).contains(q) { return true }
            if let cn = item.clanName, fold(cn).contains(q) { return true }
            if let ch,
               fold(SharingChannelCell.displayName(for: ch)).contains(q) { return true }
            return false
        }

        filteredItems = suggestions.filter { item in
            matches(item, ch: channelMap[item.channelID], qRaw: trimmed)
        }
        if hashtag {
            filteredItems.sort {
                forwardingDisplayName(for: $0).localizedCaseInsensitiveCompare(forwardingDisplayName(for: $1)) == .orderedAscending
            }
        }
    }

    private func foldingMatchSort(_ trimmed: String) -> [SharingSuggestionItem] {
        let qFold = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !qFold.isEmpty else { return filteredItems }
        return filteredItems.sorted { a, b in
            let na = forwardingDisplayName(for: a).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let nb = forwardingDisplayName(for: b).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let xa = na == qFold
            let xb = nb == qFold
            if xa != xb { return xa && !xb }
            let pa = na.hasPrefix(qFold)
            let pb = nb.hasPrefix(qFold)
            if pa != pb { return pa && !pb }
            return na < nb
        }
    }

    private func forwardingDisplayName(for item: SharingSuggestionItem) -> String {
        if let ch = channelMap[item.channelID] {
            return SharingChannelCell.displayName(for: ch)
        }
        return item.displayName
    }

    private var displaySuggestions: [SharingSuggestionItem] {
        let trimmed = ForwardOutgoing.sanitizedComment(searchText)
        guard !trimmed.hasPrefix("#") else { return filteredItems }
        return foldingMatchSort(trimmed)
    }

    private func updatePreviewLabel() {
        guard let first = messagesToForward.first else {
            previewLbl.text = ""
            return
        }
        var parts: [String] = []
        let text = Self.previewPlainText(for: first)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(text)
        }
        let attcount = ForwardOutgoing.attachments(for: first).count
        let extra = messagesToForward.count - 1
        if attcount > 0 {
            parts.append(attcount > 1 ? "\(attcount) \(L(L10n.Forward.attachmentsPlural))" : "\(attcount) \(L(L10n.Forward.attachmentsSingular))")
        }
        if extra > 0 {
            parts.append("+\(extra) \(L(L10n.Forward.moreBundledMessages))")
        }
        previewLbl.text = parts.isEmpty ? L(L10n.Forward.previewPlaceholder) : parts.joined(separator: "\n")
    }

    private static func previewPlainText(for record: MessageRecord) -> String {
        let parsed = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
        let t = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(500)) }
        return ""
    }

    @objc private func searchChanged(_ field: UITextField) {
        searchText = field.text ?? ""
        applyFilter()
        tableView.reloadData()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func forwardingMode(for channel: Mezon_Api_ChannelDescription) -> Int32 {
        switch channel.type {
        case MezonConstants.ChannelType.thread.rawValue:
            return MezonConstants.ChannelStreamMode.thread.rawValue
        case MezonConstants.ChannelType.dm.rawValue:
            return MezonConstants.ChannelStreamMode.dm.rawValue
        case MezonConstants.ChannelType.group.rawValue:
            return MezonConstants.ChannelStreamMode.group.rawValue
        case MezonConstants.ChannelType.announcement.rawValue:
            return MezonConstants.ChannelStreamMode.channel.rawValue
        default:
            if channel.clanID != 0 { return MezonConstants.ChannelStreamMode.channel.rawValue }
            return MezonConstants.ChannelStreamMode.group.rawValue
        }
    }

    private func forwardClanId(for channel: Mezon_Api_ChannelDescription) -> Int64 {
        let t = channel.type
        if t == MezonConstants.ChannelType.channel.rawValue
            || t == MezonConstants.ChannelType.thread.rawValue
            || t == MezonConstants.ChannelType.announcement.rawValue {
            return resolvedClanInfo(for: channel).clanID
        }
        return 0
    }

    private func isPublicDestination(_ channel: Mezon_Api_ChannelDescription) -> Bool {
        let t = channel.type
        if t == MezonConstants.ChannelType.channel.rawValue
            || t == MezonConstants.ChannelType.thread.rawValue
            || t == MezonConstants.ChannelType.announcement.rawValue {
            return channel.channelPrivate == 0
        }
        return false
    }

    @objc private func sendTapped() {
        guard !isSending, !selectedIDs.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let tok = await context.getToken() else {
                Toast.error(L(L10n.Sharing.sessionExpired))
                return
            }
            let targets = selectedIDs.compactMap { self.channelMap[$0] }
            guard !targets.isEmpty else { return }
            let extraRaw = ForwardOutgoing.sanitizedComment(commentField.text ?? "")
            if ForwardOutgoing.commentContentJSON(trimmed: extraRaw) == nil, !extraRaw.isEmpty {
                Toast.error(L(L10n.Forward.commentTooLong))
                return
            }
            isSending = true
            defer { self.isSending = false }
            do {
                for dest in targets {
                    let cid = forwardClanId(for: dest)
                    let mid = forwardingMode(for: dest)
                    let pub = isPublicDestination(dest)
                    let avatar = context.currentUser?.avatarURL?.absoluteString ?? ""
                    for msg in messagesToForward {
                        let contentStr = ForwardOutgoing.contentJSONString(for: msg)
                        let mentions = ForwardOutgoing.mentions(
                            record: msg,
                            destinationChannelID: dest.channelID,
                            forwardFromChannelID: forwardFromChannelID
                        )
                        let atts = ForwardOutgoing.attachments(for: msg)
                        _ = try await context.account.network.sendChannelMessage(
                            clanId: cid,
                            channelId: dest.channelID,
                            mode: mid,
                            isPublic: pub,
                            content: contentStr,
                            mentions: mentions,
                            attachments: atts,
                            references: [],
                            anonymous: false,
                            mentionEveryone: false,
                            avatar: avatar,
                            topicId: 0,
                            code: msg.code,
                            token: tok
                        )
                    }
                    if let cJSON = ForwardOutgoing.commentContentJSON(trimmed: extraRaw), !extraRaw.isEmpty {
                        _ = try await context.account.network.sendChannelMessage(
                            clanId: cid,
                            channelId: dest.channelID,
                            mode: mid,
                            isPublic: pub,
                            content: cJSON,
                            mentions: [],
                            attachments: [],
                            references: [],
                            anonymous: false,
                            mentionEveryone: false,
                            avatar: avatar,
                            topicId: 0,
                            code: 0,
                            token: tok
                        )
                    }
                }
                Toast.success(L(L10n.Forward.success))
                dismiss(animated: true)
            } catch {
                Toast.error(L(L10n.Sharing.errorTitle))
            }
        }
    }
}

extension ForwardMessageViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displaySuggestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SharingChannelCell.reuseId, for: indexPath) as! SharingChannelCell
        let item = displaySuggestions[indexPath.row]
        let ch = channelMap[item.channelID]
        cell.configure(item: item, channel: ch, isSelected: selectedIDs.contains(item.channelID))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = displaySuggestions[indexPath.row]
        if selectedIDs.contains(item.channelID) {
            selectedIDs.remove(item.channelID)
        } else {
            selectedIDs.insert(item.channelID)
        }
        let hasAny = !selectedIDs.isEmpty
        sendBtn.isEnabled = hasAny
        refreshSendButtonVisual()
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        56
    }
}
