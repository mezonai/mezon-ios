import UIKit
import SwiftProtobuf

private enum ForwardOutgoing {
    private static let maxExtraTextLen = 2000

    static func contentJSONString(for record: MessageRecord) -> String {
        let parsedDict: [String: Any]?
        if let d = try? JSONSerialization.jsonObject(with: record.content) as? [String: Any] {
            parsedDict = d
        } else if let str = String(data: record.content, encoding: .utf8),
                  let sanitized = MessageContentParser.sanitizeAndRetryParse(str) {
            parsedDict = sanitized
        } else {
            parsedDict = nil
        }
        
        if var dict = parsedDict {
            dict["fwd"] = true
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        
        if let str = String(data: record.content, encoding: .utf8) {
             let extracted = MessageContentParser.regexExtractTextField(str)
             if !extracted.isEmpty {
                 let dict: [String: Any] = ["t": extracted, "fwd": true]
                 if let data = try? JSONSerialization.data(withJSONObject: dict),
                    let str = String(data: data, encoding: .utf8) {
                     return str
                 }
             }
        }
        
        return #"{"fwd":true}"#
    }

    static func attachments(for record: MessageRecord, fallback: [ParsedAttachment] = []) -> [Mezon_Api_MessageAttachment] {
        parsedAttachments(for: record, fallback: fallback).map { p in
            var att = Mezon_Api_MessageAttachment()
            att.url = p.url
            att.filename = p.filename
            att.filetype = p.filetype
            if let w = p.width { att.width = Int32(w) }
            if let h = p.height { att.height = Int32(h) }
            if let d = p.durationSeconds { att.duration = Int32(d) }
            return att
        }
    }

    static func parsedAttachments(for record: MessageRecord, fallback: [ParsedAttachment] = []) -> [ParsedAttachment] {
        var out: [ParsedAttachment] = []
        var seen = Set<String>()
        let append: ([ParsedAttachment]) -> Void = { items in
            for item in items {
                let key = attachmentDedupeKey(item)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(item)
            }
        }
        append(parsedAttachments(fromColumnData: record.attachmentsJSON))
        append(parsedAttachments(fromContentData: record.content))
        append(fallback)
        return out
    }

    private static func attachmentDedupeKey(_ item: ParsedAttachment) -> String {
        let u = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { return u }
        let name = item.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return "name:\(name)" }
        return ""
    }

    private static func parsedAttachments(fromColumnData data: Data, didUnwrapBase64: Bool = false) -> [ParsedAttachment] {
        guard !data.isEmpty else { return [] }

        if !didUnwrapBase64, let decoded = parsedAttachmentsFromBase64Wrapped(data) {
            return decoded
        }

        let isLikelyJson = data.first == UInt8(ascii: "[") || data.first == UInt8(ascii: "{")
        if !isLikelyJson {
            if let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: data),
               !list.attachments.isEmpty {
                let parsed = list.attachments.compactMap(parsedAttachment(from:))
                if !parsed.isEmpty { return parsed }
            }
            if let list = try? Mezon_Api_ChannelAttachmentList(serializedBytes: data),
               !list.attachments.isEmpty {
                return list.attachments.map(parsedAttachment(fromChannel:))
            }
            if let list = try? Mezon_Api_ListChannelTimelineAttachment(serializedBytes: data),
               !list.attachments.isEmpty {
                return list.attachments.map(parsedAttachment(fromTimeline:))
            }
        }

        return parsedAttachments(fromJSONData: data)
    }

    private static func parsedAttachmentsFromBase64Wrapped(_ data: Data) -> [ParsedAttachment]? {
        let ascii = data.reduce(true) { ok, b in ok && (b == 9 || b == 10 || b == 13 || b == 32 || (b >= 43 && b <= 122)) }
        guard ascii,
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              s.count >= 16,
              let inner = Data(base64Encoded: s),
              inner.count >= 8,
              inner != data else {
            return nil
        }
        let innerResult = parsedAttachments(fromColumnData: inner, didUnwrapBase64: true)
        return innerResult.isEmpty ? nil : innerResult
    }

    private static func parsedAttachments(fromContentData data: Data) -> [ParsedAttachment] {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var items: [[String: Any]] = []
        for key in ["attachments", "a", "at"] {
            if let arr = json[key] as? [[String: Any]] {
                items.append(contentsOf: arr)
            } else if let arr = json[key] as? [Any] {
                items.append(contentsOf: arr.compactMap { $0 as? [String: Any] })
            }
        }
        if let one = json["attachment"] as? [String: Any] {
            items.append(one)
        }
        return items.compactMap(parsedAttachment(fromJSONItem:))
    }

    private static func parsedAttachments(fromJSONData data: Data) -> [ParsedAttachment] {
        var jsonArray: [[String: Any]]?
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            jsonArray = arr
        } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = dict["attachments"] as? [[String: Any]] {
                jsonArray = arr
            } else if let arr = dict["a"] as? [[String: Any]] {
                jsonArray = arr
            } else if jsonItemLooksLikeAttachment(dict) {
                jsonArray = [dict]
            }
        } else if let str = String(data: data, encoding: .utf8),
                  let strData = str.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: strData) as? [[String: Any]] {
            jsonArray = arr
        }
        guard let jsonArray else { return [] }
        return jsonArray.compactMap(parsedAttachment(fromJSONItem:))
    }

    private static func jsonItemLooksLikeAttachment(_ dict: [String: Any]) -> Bool {
        let u = jsonAttachmentURL(from: dict)
        let name = jsonAttachmentFilename(from: dict)
        return !u.isEmpty || !name.isEmpty
    }

    private static func jsonAttachmentURL(from dict: [String: Any]) -> String {
        for key in ["url", "uri", "file_url", "fileUrl", "fileURL", "link"] {
            if let s = dict[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return (dict["thumbnail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func jsonAttachmentFilename(from dict: [String: Any]) -> String {
        for key in ["filename", "file_name", "fileName"] {
            if let s = dict[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return ""
    }

    private static func parsedAttachment(from att: Mezon_Api_MessageAttachment) -> ParsedAttachment? {
        let urlPrimary = att.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let thumb = att.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlStr = !urlPrimary.isEmpty ? urlPrimary : thumb
        guard !urlStr.isEmpty else { return nil }
        return ParsedAttachment(
            url: urlStr,
            filename: att.filename,
            filetype: att.filetype,
            width: att.width != 0 ? Int(att.width) : nil,
            height: att.height != 0 ? Int(att.height) : nil,
            durationSeconds: att.duration > 0 ? Int(att.duration) : nil
        )
    }

    private static func parsedAttachment(fromChannel att: Mezon_Api_ChannelAttachment) -> ParsedAttachment {
        ParsedAttachment(
            url: att.url,
            filename: att.filename,
            filetype: att.filetype,
            width: att.width == 0 ? nil : Int(att.width),
            height: att.height == 0 ? nil : Int(att.height),
            durationSeconds: nil
        )
    }

    private static func parsedAttachment(fromTimeline att: Mezon_Api_ChannelTimelineAttachment) -> ParsedAttachment {
        let urlStr = att.fileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let thumb = att.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedAttachment(
            url: !urlStr.isEmpty ? urlStr : thumb,
            filename: att.fileName,
            filetype: att.fileType,
            width: att.width == 0 ? nil : Int(att.width),
            height: att.height == 0 ? nil : Int(att.height),
            durationSeconds: att.duration > 0 ? Int(att.duration) : nil
        )
    }

    private static func parsedAttachment(fromJSONItem item: [String: Any]) -> ParsedAttachment? {
        let urlStr = jsonAttachmentURL(from: item)
        let filename = jsonAttachmentFilename(from: item)
        guard !urlStr.isEmpty || !filename.isEmpty else { return nil }
        let w = item["width"] as? Int ?? (item["width"] as? String).flatMap { Int($0) }
        let h = item["height"] as? Int ?? (item["height"] as? String).flatMap { Int($0) }
        let d: Int? = {
            if let n = item["duration"] as? Int { return n > 0 ? n : nil }
            if let n = item["duration"] as? Int64 { return n > 0 ? Int(n) : nil }
            if let s = item["duration"] as? String, let n = Int(s) { return n > 0 ? n : nil }
            return nil
        }()
        let ftRaw = (item["filetype"] as? String
            ?? item["file_type"] as? String
            ?? item["fileType"] as? String
            ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedAttachment(
            url: !urlStr.isEmpty ? urlStr : filename,
            filename: filename,
            filetype: ftRaw,
            width: w,
            height: h,
            durationSeconds: d
        )
    }

    static func attachmentPreviewLine(for record: MessageRecord, fallback: [ParsedAttachment] = []) -> String? {
        let parsed = parsedAttachments(for: record, fallback: fallback)
        guard !parsed.isEmpty else { return nil }

        let mediaCount = parsed.filter(\.isMedia).count
        let audioCount = parsed.filter { $0.isAudio && !$0.isMedia }.count
        let fileCount = parsed.filter { !$0.isMedia && !$0.isAudio }.count

        var segments: [String] = []
        if mediaCount > 0 {
            segments.append(countPhrase(
                mediaCount,
                singular: L10n.Forward.attachmentsSingular,
                plural: L10n.Forward.attachmentsPlural
            ))
        }
        if fileCount > 0 {
            segments.append(countPhrase(
                fileCount,
                singular: L10n.Forward.filesSingular,
                plural: L10n.Forward.filesPlural
            ))
        }
        if audioCount > 0 {
            segments.append(countPhrase(
                audioCount,
                singular: L10n.Forward.audioSingular,
                plural: L10n.Forward.audioPlural
            ))
        }
        return segments.isEmpty ? nil : segments.joined(separator: ", ")
    }

    private static func countPhrase(_ count: Int, singular: String, plural: String) -> String {
        let label = count == 1 ? L(singular) : L(plural)
        return "\(count) \(label)"
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
    private let attachmentHints: [String: [ParsedAttachment]]
    private let forwardFromChannelID: Int64

    private var suggestions: [SharingSuggestionItem] = []
    private var filteredItems: [SharingSuggestionItem] = []
    private var channelMap: [Int64: Mezon_Api_ChannelDescription] = [:]
    private var clanNames: [Int64: String] = [:]
    private var clanLogos: [Int64: String] = [:]
    private var blockedByMeUserIds: Set<Int64> = []

    private var selectedIDs: Set<Int64> = []
    private var searchText = ""
    private var isSending = false

    private lazy var closeButton = UIButton(type: .system)
    private lazy var titleLbl = UILabel()
    private lazy var searchWrap = UIView()
    private lazy var searchIcon = UIImageView()
    private lazy var searchField = UITextField()
    private lazy var previewCard = UIView()
    private lazy var previewAttLbl = UILabel()
    private lazy var previewLbl = UILabel()
    private var previewTextTopToAttConstraint: NSLayoutConstraint?
    private var previewTextTopToCardConstraint: NSLayoutConstraint?
    private lazy var tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.separatorStyle = .none
        t.keyboardDismissMode = .interactive
        return t
    }()
    private let emptyResultsLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.isHidden = true
        return l
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
        forwardFromChannelID: Int64,
        attachmentHints: [String: [ParsedAttachment]] = [:]
    ) {
        self.context = context
        self.messagesToForward = messagesToForward
        self.attachmentHints = attachmentHints
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
        if #available(iOS 13.0, *) {
            applyThemeStrings()
        }
        if #available(iOS 13.0, *) {
            loadDestinations()
        }
    }

    @available(iOS 13.0, *)
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
        updateEmptyResultsVisibility()
        tableView.reloadData()
    }

    @objc private func langChanged() {
        if #available(iOS 13.0, *) {
            applyThemeStrings()
        }
    }

    @objc private func themeChanged() {
        if #available(iOS 13.0, *) {
            applyTheme()
            applyThemeStrings()
            tableView.reloadData()
        }
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
        previewAttLbl.textColor = t.textStrong
        previewLbl.textColor = t.textStrong
        emptyResultsLabel.textColor = t.textDisabled
        inputBg.backgroundColor = t.secondary
        commentField.textColor = t.textStrong
        refreshSendButtonVisual()
    }

    private func setupUI() {
        let cc = MezonSymbolConfiguration(pointSize: 18, weight: .medium)
        closeButton.setImage(UIImage.mezonSystemImage("xmark", withConfiguration: cc), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLbl.font = .systemFont(ofSize: 20, weight: .bold)
        titleLbl.textAlignment = .center

        searchWrap.layer.cornerRadius = 20
        searchIcon.image = UIImage.mezonSystemImage("magnifyingglass")
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.font = .systemFont(ofSize: 15)
        searchField.autocorrectionType = .no
        searchField.addTarget(self, action: #selector(searchChanged(_:)), for: .editingChanged)

        previewCard.layer.cornerRadius = 12
        previewAttLbl.font = .systemFont(ofSize: 14, weight: .medium)
        previewAttLbl.numberOfLines = 2
        previewAttLbl.isHidden = true
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
        let sendCfg = MezonSymbolConfiguration(pointSize: 16, weight: .medium)
        let sendImg = UIImage(named: "Chat/SendMessageIcon")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage.mezonSystemImage("paperplane.fill", withConfiguration: sendCfg)
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
        previewAttLbl.translatesAutoresizingMaskIntoConstraints = false
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
        previewCard.addSubview(previewAttLbl)
        previewCard.addSubview(previewLbl)
        view.addSubview(tableView)
        view.addSubview(emptyResultsLabel)
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
            previewAttLbl.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 10),
            previewAttLbl.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            previewAttLbl.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            previewLbl.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            previewLbl.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            previewLbl.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -10),

            tableView.topAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: 14),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),

            emptyResultsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyResultsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            emptyResultsLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

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

        previewTextTopToAttConstraint = previewLbl.topAnchor.constraint(equalTo: previewAttLbl.bottomAnchor, constant: 6)
        previewTextTopToCardConstraint = previewLbl.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 10)
        previewTextTopToCardConstraint?.isActive = true

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

    private func isUserFacingDMType(_ type: Int32) -> Bool {
        type == MezonConstants.ChannelType.dm.rawValue || type == MezonConstants.ChannelType.group.rawValue
    }

    private func isSharableClanChannelType(_ type: Int32) -> Bool {
        type == MezonConstants.ChannelType.channel.rawValue
            || type == MezonConstants.ChannelType.thread.rawValue
            || type == MezonConstants.ChannelType.announcement.rawValue
    }

    private func currentUserId() -> Int64? {
        guard let id = context.currentUser?.id, let v = Int64(id) else { return nil }
        return v
    }

    private func peerUserIds(in channel: Mezon_Api_ChannelDescription) -> [Int64] {
        guard let myId = currentUserId() else {
            return channel.userIds.filter { $0 != 0 }
        }
        return channel.userIds.filter { $0 != 0 && $0 != myId }
    }

    private func shouldHideBlockedDestination(_ channel: Mezon_Api_ChannelDescription) -> Bool {
        guard isUserFacingDMType(channel.type), !blockedByMeUserIds.isEmpty else { return false }
        return peerUserIds(in: channel).contains { blockedByMeUserIds.contains($0) }
    }

    private func recencyTimestamp(for item: SharingSuggestionItem) -> UInt32 {
        guard let ch = channelMap[item.channelID] else { return 0 }
        return sharingRecencyTimestamp(ch)
    }

    private func sortSuggestionsByRecency(_ items: [SharingSuggestionItem]) -> [SharingSuggestionItem] {
        let users = items.filter { isUserFacingDMType($0.type) }
            .sorted { recencyTimestamp(for: $0) > recencyTimestamp(for: $1) }
        let channels = items.filter { isSharableClanChannelType($0.type) }
            .sorted { recencyTimestamp(for: $0) > recencyTimestamp(for: $1) }
        let other = items.filter { !isUserFacingDMType($0.type) && !isSharableClanChannelType($0.type) }
            .sorted { recencyTimestamp(for: $0) > recencyTimestamp(for: $1) }
        return users + channels + other
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

    @available(iOS 13.0, *)
    private func loadDestinations() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await context.getToken() else { return }

            await context.engine.friendsData.refreshFromNetwork(token: token)
            blockedByMeUserIds = context.engine.friendsData.blockedUserIds()

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
                    guard !self.shouldHideBlockedDestination(ch) else { return false }
                    if !ch.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                    if ch.displayNames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
                    if ch.usernames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
                    return false
                }
                dmList = dmList.sorted { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
            } catch {}

            if let allChannelsList = context.engine.clanData.getAllChannelsByUser() {
                clanList = allChannelsList.channeldesc.filter { ch in
                    let t = ch.type
                    return t == MezonConstants.ChannelType.channel.rawValue
                        || t == MezonConstants.ChannelType.thread.rawValue
                        || t == MezonConstants.ChannelType.announcement.rawValue
                }
                clanList = clanList.sorted { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
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
                    clanList = clanList.sorted { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
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
            updateEmptyResultsVisibility()
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
            guard let ch else { return false }
            if !ch.channelLabel.isEmpty, fold(ch.channelLabel).contains(q) { return true }
            if fold(SharingChannelCell.displayName(for: ch)).contains(q) { return true }
            for u in ch.usernames where fold(u).contains(q) { return true }
            for d in ch.displayNames where fold(d).contains(q) { return true }
            return false
        }

        var matchedItems = suggestions.filter { item in
            matches(item, ch: channelMap[item.channelID], qRaw: trimmed)
        }
        if !trimmed.isEmpty {
            var matchedIds = Set(matchedItems.map(\.channelID))
            for item in suggestions {
                guard let ch = channelMap[item.channelID], ch.parentID != 0 else { continue }
                guard matchedIds.contains(ch.parentID), !matchedIds.contains(item.channelID) else { continue }
                matchedItems.append(item)
                matchedIds.insert(item.channelID)
            }
        }
        filteredItems = matchedItems
        if hashtag {
            filteredItems.sort {
                forwardingDisplayName(for: $0).localizedCaseInsensitiveCompare(forwardingDisplayName(for: $1)) == .orderedAscending
            }
        } else {
            filteredItems = sortSuggestionsByRecency(filteredItems)
        }
        updateEmptyResultsVisibility()
    }

    private func updateEmptyResultsVisibility() {
        let trimmed = ForwardOutgoing.sanitizedComment(searchText)
        let isSearching = !trimmed.isEmpty
        let showEmpty = isSearching && displaySuggestions.isEmpty
        emptyResultsLabel.text = L(L10n.Forward.noResults)
        emptyResultsLabel.isHidden = !showEmpty
        tableView.isScrollEnabled = !showEmpty
    }

    private func forwardingDisplayName(for item: SharingSuggestionItem) -> String {
        if let ch = channelMap[item.channelID] {
            return SharingChannelCell.displayName(for: ch)
        }
        return item.displayName
    }

    private var displaySuggestions: [SharingSuggestionItem] {
        filteredItems
    }

    @available(iOS 13.0, *)
    private func updatePreviewLabel() {
        guard let first = messagesToForward.first else {
            previewAttLbl.text = ""
            previewLbl.text = ""
            setPreviewAttachmentVisible(false)
            return
        }
        let hints = attachmentHints[first.id] ?? []
        let attLine = ForwardOutgoing.attachmentPreviewLine(for: first, fallback: hints)
        if let attLine {
            previewAttLbl.text = attLine
            setPreviewAttachmentVisible(true)
        } else {
            previewAttLbl.text = ""
            setPreviewAttachmentVisible(false)
        }

        var textParts: [String] = []
        let text = Self.previewPlainText(for: first, maxLength: attLine == nil ? 500 : 200)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textParts.append(text)
        }
        let extra = messagesToForward.count - 1
        if extra > 0 {
            textParts.append("+\(extra) \(L(L10n.Forward.moreBundledMessages))")
        }
        if textParts.isEmpty, attLine == nil {
            previewLbl.text = L(L10n.Forward.previewPlaceholder)
        } else {
            previewLbl.text = textParts.joined(separator: "\n")
        }
    }

    private func setPreviewAttachmentVisible(_ visible: Bool) {
        previewAttLbl.isHidden = !visible
        previewTextTopToAttConstraint?.isActive = visible
        previewTextTopToCardConstraint?.isActive = !visible
    }

    private static func previewPlainText(for record: MessageRecord, maxLength: Int = 500) -> String {
        let parsed = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
        if record.code == MezonConstants.MessageCode.shareContact.rawValue || isShareContactEmbed(parsed.embeds) {
            return "[\(L(L10n.DirectMessage.previewContact))]"
        }
        let t = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if t.count <= maxLength { return t }
        return String(t.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func isShareContactEmbed(_ embeds: [ParsedEmbed]) -> Bool {
        embeds.contains { embed in
            embed.fields.contains { field in
                let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if name == "key", isShareContactValue(value) { return true }
                return isShareContactValue(value)
            }
        }
    }

    private static func isShareContactValue(_ value: String) -> Bool {
        value == MezonConstants.shareContactKey || value == "share_contact_key"
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
        if #available(iOS 13.0, *) {
            guard !isSending, !selectedIDs.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let tok = await context.getToken() else {
                    Toast.error(L(L10n.Sharing.sessionExpired))
                    return
                }
                let selectedChannels = selectedIDs.compactMap { self.channelMap[$0] }
                if selectedChannels.isEmpty {
                    return
                }
                let extraRaw = ForwardOutgoing.sanitizedComment(commentField.text ?? "")
                if ForwardOutgoing.commentContentJSON(trimmed: extraRaw) == nil, !extraRaw.isEmpty {
                    Toast.error(L(L10n.Forward.commentTooLong))
                    return
                }
                isSending = true
                defer { self.isSending = false }
                do {
                    for dest in selectedChannels {
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
                            let atts = ForwardOutgoing.attachments(for: msg, fallback: attachmentHints[msg.id] ?? [])
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
                    SentryLogger.capture(error, extras: [
                        "where": "ForwardMessage",
                        "messageCount": messagesToForward.count,
                        "destinationCount": selectedChannels.count,
                    ])
                    Toast.error(L(L10n.Sharing.errorTitle))
                }
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
        cell.configure(
            item: item,
            channel: ch,
            isSelected: selectedIDs.contains(item.channelID),
            statusNote: nil,
            isForwardingBlocked: false
        )
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
