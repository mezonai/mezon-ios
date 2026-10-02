import UIKit
import SwiftProtobuf
import AVFoundation

final class SharingViewController: UIViewController {

    private let context: AccountContext
    private let sharedContent: SharingManager.SharedContent

    private enum Section: Int, CaseIterable { case suggestions }

    private var allSuggestions: [SharingSuggestionItem] = []
    private var searchResults: [SharingSuggestionItem] = []
    private var filteredSuggestions: [SharingSuggestionItem] = []
    private var channelMap: [Int64: Mezon_Api_ChannelDescription] = [:]
    private var clanNames: [Int64: String] = [:]
    private var clanLogos: [Int64: String] = [:]
    private var selectedChannel: Mezon_Api_ChannelDescription?
    private var selectedItemIdentity: String?
    private var searchText: String = ""
    private var ctrlKGeneration: UInt64 = 0
    private var awaitingSearchResults = false
    private var isUploading = false
    private var sendTask: Task<Void, Never>?
    private var searchDebounceTimer: Foundation.Timer?

    private var uploadProgressByKey: [String: Double] = [:]
    private var uploadSizeByKey: [String: Int] = [:]
    private var uploadTotalBytes: Int = 0
    private var showsUploadProgress = false

    private var diffableDataSource: UITableViewDiffableDataSource<Section, SharingSuggestionItem>!

    private var sharedMediaFiles: [SharingManager.SharedMediaFile] = []
    private var existingVideoAttachment: SharingManager.ExistingVideoAttachment?

    private let headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = ""
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let searchContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 20
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private lazy var searchTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 15)
        tf.attributedPlaceholder = NSAttributedString(string: "")
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        return tf
    }()

    private let searchClearButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        b.layer.cornerRadius = 12
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isHidden = true
        return b
    }()

    private let selectedAvatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        iv.isHidden = true
        return iv
    }()

    private let selectedInitialLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textAlignment = .center
        l.isHidden = true
        return l
    }()

    private let selectedNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.lineBreakMode = .byTruncatingTail
        l.isHidden = true
        return l
    }()

    private let suggestionsCard: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 12
        return v
    }()

    private let suggestionsTitle: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = ""
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        return l
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.keyboardDismissMode = .onDrag
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 58
        tv.showsVerticalScrollIndicator = false
        return tv
    }()

    private let emptySuggestionsLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.isHidden = true
        return l
    }()

    private let bottomArea: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let attachmentScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        return sv
    }()

    private let attachmentStackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.spacing = 10
        sv.alignment = .center
        return sv
    }()

    private let inputRow: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let inputPill: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 22
        return v
    }()

    private lazy var textField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 15)
        return tf
    }()

    private let sendButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        b.setImage(UIImage(systemName: "arrow.up", withConfiguration: config), for: .normal)
        b.layer.cornerRadius = 20
        b.isEnabled = false
        b.alpha = 1.0
        return b
    }()

    private let blockingBackdrop: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        v.isHidden = true
        return v
    }()

    private let loadingOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        v.isHidden = true
        v.layer.cornerRadius = 12
        return v
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.translatesAutoresizingMaskIntoConstraints = false
        ai.hidesWhenStopped = true
        return ai
    }()

    private let loadingLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "Sending..."
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textAlignment = .center
        return l
    }()

    private let uploadProgressView: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .default)
        p.translatesAutoresizingMaskIntoConstraints = false
        p.progress = 0
        p.isHidden = true
        return p
    }()

    private var bottomAreaBottomConstraint: NSLayoutConstraint?
    private var attachmentHeightConstraint: NSLayoutConstraint?
    private var inputRowBottomConstraint: NSLayoutConstraint?
    private var isKeyboardVisible = false

    init(context: AccountContext, sharedContent: SharingManager.SharedContent) {
        self.context = context
        self.sharedContent = sharedContent
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        parseSharedContent()
        setupUI()
        applyTheme()
        refreshLocalizedStrings()
        updateSendButton()
        loadChannels()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleLanguageChange), name: LanguageManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleUploadProgress(_:)), name: .mezonAttachmentUploadProgress, object: nil)
    }

    @objc private func handleUploadProgress(_ note: Notification) {
        guard isUploading, showsUploadProgress, uploadTotalBytes > 0 else { return }
        guard let info = note.userInfo,
              let key = info["key"] as? String,
              uploadSizeByKey[key] != nil,
              let progress = info["progress"] as? Double else { return }
        uploadProgressByKey[key] = min(max(progress, 0), 1)
        let uploadedBytes = uploadSizeByKey.reduce(0.0) { acc, entry in
            acc + (uploadProgressByKey[entry.key] ?? 0) * Double(entry.value)
        }
        let fraction = min(max(uploadedBytes / Double(uploadTotalBytes), 0), 1)
        uploadProgressView.setProgress(Float(fraction), animated: true)
        loadingLabel.text = "\(L(L10n.Sharing.uploading)) \(Int(fraction * 100))%"
    }

    @objc private func handleThemeChange() {
        applyTheme()
        tableView.reloadData()
    }

    @objc private func handleLanguageChange() {
        refreshLocalizedStrings()
        applySnapshot(animated: false)
    }

    private func refreshLocalizedStrings() {
        titleLabel.text = L(L10n.Sharing.title)
        suggestionsTitle.text = L(L10n.Sharing.suggestionsSection).uppercased()
        loadingLabel.text = L(L10n.Sharing.sending)
        refreshLocalizedPlaceholderColors()
        refreshSearchPlaceholder()
    }

    private func placeholderForegroundColor() -> UIColor {
        UIColor.theme.textDisabled.withAlphaComponent(0.85)
    }

    private func refreshLocalizedPlaceholderColors() {
        textField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Sharing.commentPlaceholder),
            attributes: [.foregroundColor: placeholderForegroundColor()]
        )
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { ThemeManager.shared.preferredStatusBarStyle }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isKeyboardVisible {
            let safeBottom = view.safeAreaInsets.bottom
            inputRowBottomConstraint?.constant = -(max(safeBottom, 8))
        }
    }

    private func parseSharedContent() {
        switch sharedContent {
        case .media(let files):
            sharedMediaFiles = files.filter { f in
                guard let url = SharingManager.shared.localFileURL(from: f.path) else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
        case .text(let texts):
            let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if let first = trimmed.first {
                textField.text = first
            }
        case .existingVideo(let attachment):
            existingVideoAttachment = attachment
        }
    }

    private func setupUI() {
        view.addSubview(headerView)
        headerView.addSubview(closeButton)
        headerView.addSubview(titleLabel)

        view.addSubview(searchContainer)
        searchContainer.addSubview(searchIconView)
        searchContainer.addSubview(searchTextField)
        searchContainer.addSubview(searchClearButton)
        searchContainer.addSubview(selectedAvatarView)
        selectedAvatarView.addSubview(selectedInitialLabel)
        searchContainer.addSubview(selectedNameLabel)

        view.addSubview(suggestionsCard)
        suggestionsCard.addSubview(suggestionsTitle)
        suggestionsCard.addSubview(tableView)
        suggestionsCard.addSubview(emptySuggestionsLabel)

        view.addSubview(bottomArea)
        bottomArea.addSubview(attachmentScrollView)
        attachmentScrollView.addSubview(attachmentStackView)
        bottomArea.addSubview(inputRow)
        inputRow.addSubview(inputPill)
        inputPill.addSubview(textField)
        inputRow.addSubview(sendButton)

        view.addSubview(blockingBackdrop)
        view.addSubview(loadingOverlay)
        loadingOverlay.addSubview(activityIndicator)
        loadingOverlay.addSubview(loadingLabel)
        loadingOverlay.addSubview(uploadProgressView)

        let safeArea = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 48),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchContainer.heightAnchor.constraint(equalToConstant: 40),

            searchIconView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 12),
            searchIconView.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 18),
            searchIconView.heightAnchor.constraint(equalToConstant: 18),

            searchTextField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 8),
            searchTextField.trailingAnchor.constraint(equalTo: searchClearButton.leadingAnchor, constant: -4),
            searchTextField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            searchClearButton.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -8),
            searchClearButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchClearButton.widthAnchor.constraint(equalToConstant: 24),
            searchClearButton.heightAnchor.constraint(equalToConstant: 24),

            selectedAvatarView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 8),
            selectedAvatarView.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            selectedAvatarView.widthAnchor.constraint(equalToConstant: 20),
            selectedAvatarView.heightAnchor.constraint(equalToConstant: 20),

            selectedInitialLabel.centerXAnchor.constraint(equalTo: selectedAvatarView.centerXAnchor),
            selectedInitialLabel.centerYAnchor.constraint(equalTo: selectedAvatarView.centerYAnchor),

            selectedNameLabel.leadingAnchor.constraint(equalTo: selectedAvatarView.trailingAnchor, constant: 8),
            selectedNameLabel.trailingAnchor.constraint(equalTo: searchClearButton.leadingAnchor, constant: -4),
            selectedNameLabel.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
        ])

        NSLayoutConstraint.activate([
            suggestionsCard.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 16),
            suggestionsCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            suggestionsCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            suggestionsTitle.topAnchor.constraint(equalTo: suggestionsCard.topAnchor, constant: 16),
            suggestionsTitle.leadingAnchor.constraint(equalTo: suggestionsCard.leadingAnchor, constant: 16),
            suggestionsTitle.trailingAnchor.constraint(equalTo: suggestionsCard.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: suggestionsTitle.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: suggestionsCard.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: suggestionsCard.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: suggestionsCard.bottomAnchor),

            emptySuggestionsLabel.leadingAnchor.constraint(equalTo: suggestionsCard.leadingAnchor, constant: 20),
            emptySuggestionsLabel.trailingAnchor.constraint(equalTo: suggestionsCard.trailingAnchor, constant: -20),
            emptySuggestionsLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        let bottomConstraint = bottomArea.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        self.bottomAreaBottomConstraint = bottomConstraint

        let attachHeight = attachmentScrollView.heightAnchor.constraint(
            equalToConstant: hasAttachmentPreview ? 80 : 0
        )
        self.attachmentHeightConstraint = attachHeight

        NSLayoutConstraint.activate([
            suggestionsCard.bottomAnchor.constraint(equalTo: bottomArea.topAnchor, constant: -1),

            bottomArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,

            attachmentScrollView.topAnchor.constraint(equalTo: bottomArea.topAnchor, constant: 8),
            attachmentScrollView.leadingAnchor.constraint(equalTo: bottomArea.leadingAnchor, constant: 16),
            attachmentScrollView.trailingAnchor.constraint(equalTo: bottomArea.trailingAnchor, constant: -16),
            attachHeight,

            attachmentStackView.topAnchor.constraint(equalTo: attachmentScrollView.topAnchor),
            attachmentStackView.bottomAnchor.constraint(equalTo: attachmentScrollView.bottomAnchor),
            attachmentStackView.leadingAnchor.constraint(equalTo: attachmentScrollView.leadingAnchor),
            attachmentStackView.trailingAnchor.constraint(equalTo: attachmentScrollView.trailingAnchor),
            attachmentStackView.heightAnchor.constraint(equalTo: attachmentScrollView.heightAnchor),

            inputRow.topAnchor.constraint(equalTo: attachmentScrollView.bottomAnchor, constant: 8),
            inputRow.leadingAnchor.constraint(equalTo: bottomArea.leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: bottomArea.trailingAnchor, constant: -16),
            inputRow.heightAnchor.constraint(equalToConstant: 44),
        ])

        let irBottom = inputRow.bottomAnchor.constraint(equalTo: bottomArea.bottomAnchor, constant: -34)
        irBottom.isActive = true
        self.inputRowBottomConstraint = irBottom

        NSLayoutConstraint.activate([

            inputPill.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor),
            inputPill.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputPill.topAnchor.constraint(equalTo: inputRow.topAnchor),
            inputPill.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor),

            textField.leadingAnchor.constraint(equalTo: inputPill.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: inputPill.trailingAnchor, constant: -16),
            textField.centerYAnchor.constraint(equalTo: inputPill.centerYAnchor),

            sendButton.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor),
            sendButton.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        NSLayoutConstraint.activate([
            blockingBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            blockingBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blockingBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockingBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            loadingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingOverlay.widthAnchor.constraint(equalToConstant: 220),
            loadingOverlay.heightAnchor.constraint(equalToConstant: 110),

            activityIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: loadingOverlay.topAnchor, constant: 20),

            loadingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 8),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingOverlay.leadingAnchor, constant: 20),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingOverlay.trailingAnchor, constant: -20),

            uploadProgressView.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 10),
            uploadProgressView.leadingAnchor.constraint(equalTo: loadingOverlay.leadingAnchor, constant: 20),
            uploadProgressView.trailingAnchor.constraint(equalTo: loadingOverlay.trailingAnchor, constant: -20),
        ])

        if !sharedMediaFiles.isEmpty {
            buildAttachmentPreviews()
        }
        if existingVideoAttachment != nil {
            buildExistingVideoPreview()
        }

        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.register(SharingChannelCell.self, forCellReuseIdentifier: SharingChannelCell.reuseId)
        setupDiffableDataSource()

        searchTextField.delegate = self
        searchTextField.addTarget(self, action: #selector(searchTextChanged(_:)), for: .editingChanged)
        searchClearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        textField.delegate = self
        textField.addTarget(self, action: #selector(commentTextChanged(_:)), for: .editingChanged)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        refreshSearchPlaceholder()
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

    private var trimmedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshSearchPlaceholder() {
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Sharing.searchPlaceholderAll),
            attributes: [.foregroundColor: placeholderForegroundColor()]
        )
    }

    private func scheduleSearch() {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] (_: Foundation.Timer) in
            self?.applySearchQuery()
        }
    }

    private func applySearchQuery() {
        searchDebounceTimer?.invalidate()
        let query = trimmedSearchQuery
        if query.isEmpty {
            ctrlKGeneration &+= 1
            searchResults = []
            awaitingSearchResults = false
        } else {
            awaitingSearchResults = fetchCtrlKResults(query)
            if !awaitingSearchResults {
                searchResults = []
            }
        }
        renderSuggestions()
        scrollSuggestionsListToTop(animated: false)
    }

    private func fetchCtrlKResults(_ rawQuery: String) -> Bool {
        let type: Int32 = rawQuery.hasPrefix("@") ? 1 : rawQuery.hasPrefix("#") ? 2 : 0
        let text = type == 0
            ? rawQuery
            : String(rawQuery.dropFirst()).trimmingCharacters(in: .whitespaces)
        ctrlKGeneration &+= 1
        guard !text.isEmpty, text.utf8.count <= 255 else { return false }
        let generation = ctrlKGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            var response: Mezon_Api_SearchCtrlKResponse?
            if let token = await self.context.getToken() {
                response = try? await self.context.account.network.searchCtrlK(
                    text: text, type: type, token: token)
            }
            guard self.ctrlKGeneration == generation else { return }
            if let response {
                self.searchResults = self.buildSearchResults(users: response.users, channels: response.channels)
            } else {
                self.searchResults = []
            }
            self.awaitingSearchResults = false
            self.renderSuggestions()
            self.scrollSuggestionsListToTop(animated: false)
        }
        return true
    }

    private func renderSuggestions() {
        let searching = !trimmedSearchQuery.isEmpty
        filteredSuggestions = searching ? searchResults : allSuggestions
        suggestionsTitle.isHidden = searching
        applySnapshot()
    }

    private func buildSearchResults(
        users: [Mezon_Api_User],
        channels: [Mezon_Api_ChannelDescription]
    ) -> [SharingSuggestionItem] {
        var directChannelByUserID: [Int64: Mezon_Api_ChannelDescription] = [:]
        for ch in channelMap.values
        where ch.type == MezonConstants.ChannelType.dm.rawValue && ch.userIds.count == 1 && ch.userIds[0] != 0 {
            directChannelByUserID[ch.userIds[0]] = ch
        }

        var items: [SharingSuggestionItem] = []
        var seen = Set<String>()
        for user in users where user.id != 0 {
            let existing = directChannelByUserID[user.id]
            let name = user.displayName.isEmpty ? user.username : user.displayName
            guard !name.isEmpty else { continue }
            let item = SharingSuggestionItem(
                channelID: existing?.channelID ?? 0,
                userID: user.id,
                clanID: 0,
                type: MezonConstants.ChannelType.dm.rawValue,
                displayName: name,
                avatarURL: user.avatarURL.isEmpty ? existing?.avatars.first : user.avatarURL,
                channelAvatar: "",
                channelPrivate: 1,
                ageRestricted: 0,
                clanName: nil,
                clanLogo: nil
            )
            guard seen.insert(item.identity).inserted else { continue }
            items.append(item)
        }
        for ch in channels where ch.channelID != 0 {
            let item: SharingSuggestionItem
            if ch.type == MezonConstants.ChannelType.group.rawValue {
                item = directMessageSuggestion(for: ch)
            } else if isSharableClanChannelType(ch.type) {
                item = clanChannelSuggestion(for: ch)
            } else {
                continue
            }
            guard !item.displayName.isEmpty, seen.insert(item.identity).inserted else { continue }
            channelMap[ch.channelID] = ch
            items.append(item)
        }
        return items
    }

    private func directMessageSuggestion(for ch: Mezon_Api_ChannelDescription) -> SharingSuggestionItem {
        SharingSuggestionItem(
            channelID: ch.channelID,
            userID: ch.type == MezonConstants.ChannelType.dm.rawValue ? (ch.userIds.first ?? 0) : 0,
            clanID: ch.clanID,
            type: ch.type,
            displayName: SharingChannelCell.displayName(for: ch),
            avatarURL: ch.avatars.first,
            channelAvatar: ch.channelAvatar,
            channelPrivate: ch.channelPrivate,
            ageRestricted: ch.ageRestricted,
            clanName: nil,
            clanLogo: nil
        )
    }

    private func clanChannelSuggestion(for ch: Mezon_Api_ChannelDescription) -> SharingSuggestionItem {
        let (cid, chClanNameRaw) = resolvedClanInfo(for: ch)
        let mapName = (clanNames[cid] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chClanName = chClanNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedClanName: String? = {
            if !mapName.isEmpty { return mapName }
            if !chClanName.isEmpty { return chClanName }
            return nil
        }()
        return SharingSuggestionItem(
            channelID: ch.channelID,
            userID: 0,
            clanID: cid,
            type: ch.type,
            displayName: SharingChannelCell.displayName(for: ch),
            avatarURL: ch.avatars.first,
            channelAvatar: ch.channelAvatar,
            channelPrivate: ch.channelPrivate,
            ageRestricted: ch.ageRestricted,
            clanName: resolvedClanName,
            clanLogo: clanLogos[cid]
        )
    }

    private func channelDescription(for item: SharingSuggestionItem) -> Mezon_Api_ChannelDescription? {
        if item.channelID != 0 { return channelMap[item.channelID] }
        guard item.needsDirectMessageChannel else { return nil }
        var ch = Mezon_Api_ChannelDescription()
        ch.type = MezonConstants.ChannelType.dm.rawValue
        ch.channelPrivate = 1
        ch.userIds = [item.userID]
        ch.displayNames = [item.displayName]
        if let avatar = item.avatarURL, !avatar.isEmpty {
            ch.avatars = [avatar]
        }
        return ch
    }

    private func scrollSuggestionsListToTop(animated: Bool) {
        guard tableView.numberOfSections > 0 else {
            tableView.setContentOffset(.zero, animated: animated)
            return
        }
        let n = tableView.numberOfRows(inSection: 0)
        guard n > 0 else {
            tableView.setContentOffset(.zero, animated: animated)
            return
        }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
    }

    private func setupDiffableDataSource() {
        diffableDataSource = UITableViewDiffableDataSource<Section, SharingSuggestionItem>(tableView: tableView) {
            [weak self] tableView, indexPath, item in
            let cell = tableView.dequeueReusableCell(withIdentifier: SharingChannelCell.reuseId, for: indexPath) as! SharingChannelCell
            guard let self else { return cell }
            let channel = self.channelMap[item.channelID]
            let isSelected = self.selectedItemIdentity == item.identity
            cell.configure(item: item, channel: channel, isSelected: isSelected)
            return cell
        }
        diffableDataSource.defaultRowAnimation = .none
    }

    private func applySnapshot(animated: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SharingSuggestionItem>()
        snapshot.appendSections([.suggestions])
        snapshot.appendItems(filteredSuggestions, toSection: .suggestions)
        diffableDataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptySuggestionsVisibility()
    }

    private func updateEmptySuggestionsVisibility() {
        let searching = !trimmedSearchQuery.isEmpty
        let empty = filteredSuggestions.isEmpty && !awaitingSearchResults
        emptySuggestionsLabel.text = L(searching ? L10n.Sharing.noResults : L10n.Sharing.emptySuggestions)
        emptySuggestionsLabel.isHidden = !empty
        tableView.isScrollEnabled = !empty
    }

    private func buildAttachmentPreviews() {
        for file in sharedMediaFiles {
            let thumbSize: CGFloat = 70
            let wrapper = UIView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.widthAnchor.constraint(equalToConstant: thumbSize).isActive = true
            wrapper.heightAnchor.constraint(equalToConstant: thumbSize).isActive = true
            wrapper.layer.cornerRadius = 6
            wrapper.clipsToBounds = true

            switch file.type {
            case .image:
                let iv = UIImageView()
                iv.translatesAutoresizingMaskIntoConstraints = false
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.backgroundColor = UIColor.theme.tertiary
                wrapper.addSubview(iv)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    iv.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                ])
                if let url = SharingManager.shared.localFileURL(from: file.path),
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    iv.image = image
                }

            case .video:
                let iv = UIImageView()
                iv.translatesAutoresizingMaskIntoConstraints = false
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.backgroundColor = UIColor.theme.tertiary
                wrapper.addSubview(iv)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    iv.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                ])
                if let thumbPath = file.thumbnail,
                   let url = SharingManager.shared.localFileURL(from: thumbPath),
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    iv.image = image
                } else if let url = SharingManager.shared.localFileURL(from: file.path) {
                    iv.image = generateVideoThumbnail(url: url)
                }

                let overlay = UIView()
                overlay.translatesAutoresizingMaskIntoConstraints = false
                overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
                wrapper.addSubview(overlay)
                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    overlay.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                    overlay.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                ])
                let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
                playIcon.translatesAutoresizingMaskIntoConstraints = false
                playIcon.tintColor = .white
                playIcon.contentMode = .scaleAspectFit
                overlay.addSubview(playIcon)
                NSLayoutConstraint.activate([
                    playIcon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                    playIcon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
                    playIcon.widthAnchor.constraint(equalToConstant: 20),
                    playIcon.heightAnchor.constraint(equalToConstant: 20),
                ])

            case .file:
                wrapper.backgroundColor = UIColor.theme.tertiary
                let fileIcon = UIImageView(image: UIImage(systemName: "doc.fill"))
                fileIcon.translatesAutoresizingMaskIntoConstraints = false
                fileIcon.tintColor = UIColor.theme.textLink
                fileIcon.contentMode = .scaleAspectFit
                wrapper.addSubview(fileIcon)
                NSLayoutConstraint.activate([
                    fileIcon.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                    fileIcon.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor, constant: -6),
                    fileIcon.widthAnchor.constraint(equalToConstant: 28),
                    fileIcon.heightAnchor.constraint(equalToConstant: 28),
                ])
                let nameLabel = UILabel()
                nameLabel.translatesAutoresizingMaskIntoConstraints = false
                nameLabel.font = .systemFont(ofSize: 8)
                nameLabel.textColor = UIColor.theme.textDisabled
                nameLabel.textAlignment = .center
                nameLabel.lineBreakMode = .byTruncatingMiddle
                if let url = SharingManager.shared.localFileURL(from: file.path) {
                    nameLabel.text = url.lastPathComponent
                }
                wrapper.addSubview(nameLabel)
                NSLayoutConstraint.activate([
                    nameLabel.topAnchor.constraint(equalTo: fileIcon.bottomAnchor, constant: 2),
                    nameLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 2),
                    nameLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -2),
                ])
            }

            let removeBtn = UIButton(type: .system)
            removeBtn.translatesAutoresizingMaskIntoConstraints = false
            let removeConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            removeBtn.setImage(UIImage(systemName: "xmark", withConfiguration: removeConfig), for: .normal)
            removeBtn.tintColor = .white
            removeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            removeBtn.layer.cornerRadius = 10
            removeBtn.tag = attachmentStackView.arrangedSubviews.count
            removeBtn.addTarget(self, action: #selector(removeAttachment(_:)), for: .touchUpInside)
            wrapper.addSubview(removeBtn)
            NSLayoutConstraint.activate([
                removeBtn.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 2),
                removeBtn.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -2),
                removeBtn.widthAnchor.constraint(equalToConstant: 20),
                removeBtn.heightAnchor.constraint(equalToConstant: 20),
            ])

            attachmentStackView.addArrangedSubview(wrapper)
        }
    }

    private func buildExistingVideoPreview() {
        guard let attachment = existingVideoAttachment else { return }
        let thumbSize: CGFloat = 70
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: thumbSize).isActive = true
        wrapper.heightAnchor.constraint(equalToConstant: thumbSize).isActive = true
        wrapper.layer.cornerRadius = 6
        wrapper.clipsToBounds = true

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.theme.tertiary
        wrapper.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        if !attachment.thumbnail.isEmpty {
            _ = ImageCache.shared.loadImage(urlString: attachment.thumbnail) { [weak imageView] image in
                imageView?.image = image
            }
        }

        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        wrapper.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: wrapper.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.tintColor = .white
        playIcon.contentMode = .scaleAspectFit
        overlay.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            playIcon.widthAnchor.constraint(equalToConstant: 20),
            playIcon.heightAnchor.constraint(equalToConstant: 20),
        ])

        let removeButton = UIButton(type: .system)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        let removeConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        removeButton.setImage(UIImage(systemName: "xmark", withConfiguration: removeConfig), for: .normal)
        removeButton.tintColor = .white
        removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        removeButton.layer.cornerRadius = 10
        removeButton.addTarget(self, action: #selector(removeExistingVideo(_:)), for: .touchUpInside)
        wrapper.addSubview(removeButton)
        NSLayoutConstraint.activate([
            removeButton.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 2),
            removeButton.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -2),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        attachmentStackView.addArrangedSubview(wrapper)
    }

    @objc private func removeExistingVideo(_ sender: UIButton) {
        existingVideoAttachment = nil
        sender.superview?.removeFromSuperview()
        if !hasAttachmentPreview {
            attachmentHeightConstraint?.constant = 0
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        }
        updateSendButton()
    }

    @objc private func removeAttachment(_ sender: UIButton) {
        let idx = sender.tag
        guard idx < sharedMediaFiles.count else { return }
        sharedMediaFiles.remove(at: idx)
        attachmentStackView.arrangedSubviews[idx].removeFromSuperview()
        for (i, v) in attachmentStackView.arrangedSubviews.enumerated() {
            if let btn = v.subviews.compactMap({ $0 as? UIButton }).first {
                btn.tag = i
            }
        }
        if sharedMediaFiles.isEmpty {
            attachmentHeightConstraint?.constant = 0
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        }
        updateSendButton()
    }

    private func generateVideoThumbnail(url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary

        headerView.backgroundColor = t.primary
        suggestionsCard.backgroundColor = t.secondary
        tableView.backgroundColor = t.secondary
        tableView.separatorStyle = .none
        bottomArea.backgroundColor = t.secondary

        closeButton.tintColor = t.iconSecondary
        titleLabel.textColor = t.textStrong

        searchContainer.backgroundColor = t.charcoal
        searchIconView.tintColor = t.iconSecondary
        searchTextField.textColor = t.textStrong
        searchTextField.tintColor = t.textLink
        searchClearButton.tintColor = t.iconSecondary
        searchClearButton.backgroundColor = t.tertiary

        selectedAvatarView.backgroundColor = t.tertiary
        selectedInitialLabel.textColor = t.textStrong
        selectedNameLabel.textColor = t.textStrong

        suggestionsTitle.textColor = t.textDisabled
        emptySuggestionsLabel.textColor = t.textDisabled
        loadingOverlay.backgroundColor = t.secondary
        loadingOverlay.layer.borderColor = t.border.cgColor
        loadingOverlay.layer.borderWidth = 1
        loadingLabel.textColor = t.textStrong
        activityIndicator.color = t.textLink
        uploadProgressView.progressTintColor = t.textLink
        uploadProgressView.trackTintColor = t.borderDim

        inputPill.backgroundColor = t.charcoal
        textField.textColor = t.textStrong
        textField.tintColor = t.textLink

        refreshLocalizedPlaceholderColors()
        refreshSearchPlaceholder()
        setNeedsStatusBarAppearanceUpdate()
        updateSendButton()
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        isKeyboardVisible = true
        bottomAreaBottomConstraint?.constant = -frame.height
        inputRowBottomConstraint?.constant = -8
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        isKeyboardVisible = false
        bottomAreaBottomConstraint?.constant = 0
        let safeBottom = view.safeAreaInsets.bottom
        inputRowBottomConstraint?.constant = -(max(safeBottom, 8))
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func closeTapped() {
        guard !isUploading else { return }
        view.endEditing(true)
        sendTask?.cancel()
        sendTask = nil
        SharingManager.shared.cleanupSharedFiles(sharedMediaFiles)
        dismiss(animated: true)
    }

    @objc private func sendTapped() {
        guard let channel = selectedChannel, !isUploading, hasShareableContent() else { return }
        view.endEditing(true)
        performSend(to: channel)
    }

    @objc private func commentTextChanged(_ tf: UITextField) {
        if tf === textField {
            updateSendButton()
        }
    }

    private func hasShareableContent() -> Bool {
        if hasAttachmentPreview { return true }
        let comment = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !comment.isEmpty
    }

    private var hasAttachmentPreview: Bool {
        !sharedMediaFiles.isEmpty || existingVideoAttachment != nil
    }

    @objc private func searchTextChanged(_ tf: UITextField) {
        searchText = tf.text ?? ""
        searchClearButton.isHidden = searchText.isEmpty
        scheduleSearch()
    }

    @objc private func clearSearchTapped() {
        if selectedChannel != nil {
            selectedChannel = nil
            selectedItemIdentity = nil
            showSearchMode()
            updateSendButton()
            tableView.reloadData()
        }
        searchTextField.text = ""
        searchText = ""
        searchClearButton.isHidden = true
        applySearchQuery()
    }

    private func showSelectedChannel(_ channel: Mezon_Api_ChannelDescription) {
        searchTextField.isHidden = true
        searchIconView.isHidden = true
        selectedAvatarView.isHidden = false
        selectedNameLabel.isHidden = false
        searchClearButton.isHidden = false

        let name = SharingChannelCell.displayName(for: channel)
        selectedNameLabel.text = name

        let isDM = channel.type == MezonConstants.ChannelType.dm.rawValue
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
        let st = UIColor.theme
        selectedAvatarView.tintColor = st.iconSecondary

        if isDM, let avatarURL = channel.avatars.first, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
            selectedInitialLabel.isHidden = true
            selectedAvatarView.contentMode = .scaleAspectFill
            selectedAvatarView.backgroundColor = .clear
            let urlStr = SharingImageProxy.proxiedAvatarURLString(url.absoluteString)
            _ = ImageCache.shared.loadImage(urlString: urlStr) { [weak self] image in
                self?.selectedAvatarView.image = image
            }
        } else if isGroup, !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
                  let url = URL(string: channel.channelAvatar) {
            selectedInitialLabel.isHidden = true
            selectedAvatarView.contentMode = .scaleAspectFill
            selectedAvatarView.backgroundColor = .clear
            let urlStr = SharingImageProxy.proxiedAvatarURLString(url.absoluteString)
            _ = ImageCache.shared.loadImage(urlString: urlStr) { [weak self] image in
                self?.selectedAvatarView.image = image
            }
        } else if isGroup {
            selectedAvatarView.image = UIImage(systemName: "person.2.fill")?.withRenderingMode(.alwaysTemplate)
            selectedAvatarView.contentMode = .scaleAspectFit
            selectedInitialLabel.isHidden = true
            selectedAvatarView.backgroundColor = SharingChannelCell.groupDefaultAvatarBackground
        } else if isDM {
            selectedAvatarView.image = nil
            selectedAvatarView.contentMode = .scaleAspectFill
            selectedAvatarView.backgroundColor = UIColor.avatarColor(for: channel.usernames.first ?? name)
            selectedInitialLabel.text = String(name.prefix(1)).uppercased()
            selectedInitialLabel.isHidden = false
        } else {
            let iconName = channel.channelListIconAssetName()
            selectedAvatarView.image = (UIImage(named: iconName) ?? UIImage(systemName: "number"))?.withRenderingMode(.alwaysTemplate)
            selectedAvatarView.contentMode = .scaleAspectFit
            selectedInitialLabel.isHidden = true
            selectedAvatarView.backgroundColor = st.tertiary
        }
    }

    private func showSearchMode() {
        searchTextField.isHidden = false
        searchIconView.isHidden = false
        selectedAvatarView.isHidden = true
        selectedNameLabel.isHidden = true
        selectedInitialLabel.isHidden = true
    }

    private func resolvedClanInfo(for ch: Mezon_Api_ChannelDescription) -> (clanID: Int64, channelClanName: String) {
        var clanID = ch.clanID
        var channelClanName = ch.clanName
        if ch.type == MezonConstants.ChannelType.thread.rawValue, ch.parentID != 0,
            let parent = channelMap[ch.parentID]
        {
            if clanID == 0 {
                clanID = parent.clanID
            }
            if channelClanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                channelClanName = parent.clanName
            }
        }
        return (clanID, channelClanName)
    }

    private func loadChannels() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }

            var dmList: [Mezon_Api_ChannelDescription] = []
            do {
                var dms = try await self.context.account.network.listDirectMessageChannels(token: token)
                do {
                    let badgeResponse = try await self.context.account.network.listChannelBadgeCount(clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &dms, badgeRows: badgeResponse.channeldesc)
                } catch {
                }
                dmList = dms
                    .filter { ch in
                        guard self.isUserFacingDMType(ch.type) else { return false }
                        if !ch.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                        if ch.displayNames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
                        if ch.usernames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
                        return false
                    }
                    .sorted { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
            } catch {
            }

            do {
                let clanDescs = try await self.context.account.network.listClanDescs(token: token)
                for clan in clanDescs {
                    self.clanNames[clan.clanID] = clan.clanName
                    if !clan.logo.isEmpty {
                        self.clanLogos[clan.clanID] = clan.logo
                    }
                }
            } catch {
            }

            for ch in dmList {
                self.channelMap[ch.channelID] = ch
            }
            self.allSuggestions = dmList.map { self.directMessageSuggestion(for: $0) }
            self.renderSuggestions()
        }
    }

    private func updateSendButton() {
        let t = UIColor.theme
        let hasContent = hasShareableContent()
        let enabled = selectedChannel != nil && hasContent && !isUploading
        sendButton.isEnabled = enabled
        sendButton.alpha = 1.0
        let sendBlue = UIColor(red: 0.34, green: 0.54, blue: 0.95, alpha: 1.0)
        if enabled {
            sendButton.backgroundColor = sendBlue
            sendButton.tintColor = .white
        } else {
            sendButton.backgroundColor = t.borderDim
            sendButton.tintColor = t.textDisabled
        }
    }

    private func uploadSharedVideoThumbnail(
        thumbnailURL: URL,
        videoFilename: String,
        token: String
    ) async -> String {
        guard let rawData = try? Data(contentsOf: thumbnailURL),
              let image = UIImage(data: rawData) else { return "" }
        let jpegData = image.jpegData(compressionQuality: 0.7) ?? rawData

        let baseName = (videoFilename as NSString).deletingPathExtension
        let thumbFilename = "\(baseName.isEmpty ? "video" : baseName)_thumb.jpg"
        let width = Int(image.size.width)
        let height = Int(image.size.height)

        do {
            let uploadInfo = try await context.account.network.uploadAttachmentFile(
                filename: thumbFilename, filetype: "image/jpeg", size: jpegData.count,
                width: width, height: height, token: token)
            try await context.account.network.uploadToMinIO(
                url: uploadInfo.url, data: jpegData, contentType: "image/jpeg")
            return "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "Sharing.uploadSharedVideoThumbnail",
                "filename": thumbFilename,
            ])
            return ""
        }
    }

    private static let chunkUploadThreshold = 50 * 1024 * 1024

    private func prepareUploadProgress() {
        uploadProgressByKey.removeAll()
        uploadSizeByKey.removeAll()
        uploadTotalBytes = 0
        showsUploadProgress = false

        var hasLargeFile = false
        for file in sharedMediaFiles {
            guard let fileURL = SharingManager.shared.localFileURL(from: file.path),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = (attrs[.size] as? NSNumber)?.intValue, size > 0 else { continue }
            uploadSizeByKey[fileURL.path] = size
            uploadTotalBytes += size
            if size >= Self.chunkUploadThreshold { hasLargeFile = true }
        }
        showsUploadProgress = hasLargeFile && uploadTotalBytes > 0
    }

    private func resolveSendTarget(
        _ channel: Mezon_Api_ChannelDescription,
        token: String
    ) async throws -> Mezon_Api_ChannelDescription {
        guard channel.channelID == 0 else { return channel }
        guard let userId = channel.userIds.first, userId != 0 else {
            throw SharingSendError.targetUnavailable
        }
        let created = try await context.account.network.createDirectMessage(userId: userId, token: token)
        channelMap[created.channelID] = created
        selectedChannel = created
        return created
    }

    private func performSend(to channel: Mezon_Api_ChannelDescription) {
        sendTask?.cancel()
        prepareUploadProgress()
        isUploading = true
        closeButton.isEnabled = false
        blockingBackdrop.isHidden = false
        loadingOverlay.isHidden = false
        activityIndicator.startAnimating()
        uploadProgressView.isHidden = !showsUploadProgress
        uploadProgressView.progress = 0
        loadingLabel.text = showsUploadProgress
            ? "\(L(L10n.Sharing.uploading)) 0%"
            : L(L10n.Sharing.sending)
        updateSendButton()

        sendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
            backgroundTaskID = UIApplication.shared.beginBackgroundTask {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }

            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }

            func finishUploadingUI() {
                self.isUploading = false
                self.closeButton.isEnabled = true
                self.blockingBackdrop.isHidden = true
                self.loadingOverlay.isHidden = true
                self.activityIndicator.stopAnimating()
                self.uploadProgressView.isHidden = true
                self.uploadProgressView.progress = 0
                self.showsUploadProgress = false
                self.uploadProgressByKey.removeAll()
                self.loadingLabel.text = L(L10n.Sharing.sending)
                self.updateSendButton()
                self.sendTask = nil
            }

            guard !Task.isCancelled else {
                finishUploadingUI()
                return
            }

            guard let token = await self.context.getToken() else {
                self.showError(L(L10n.Sharing.sessionExpired))
                finishUploadingUI()
                return
            }

            do {
                let target = try await self.resolveSendTarget(channel, token: token)
                var uploadedAttachments: [Mezon_Api_MessageAttachment] = []

                if let existingVideo = self.existingVideoAttachment {
                    let url = existingVideo.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { throw SharingSendError.fileUnavailable }
                    let remoteFilename = URL(string: url)?.lastPathComponent ?? ""
                    let filename = existingVideo.filename.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedFilename = !filename.isEmpty
                        ? filename
                        : (!remoteFilename.isEmpty ? remoteFilename : "video.mp4")
                    var attachment = Mezon_Api_MessageAttachment()
                    attachment.url = url
                    attachment.thumbnail = existingVideo.thumbnail
                    attachment.filename = resolvedFilename
                    attachment.filetype = "video"
                    attachment.size = Int32(clamping: max(existingVideo.size, 0))
                    attachment.width = Int32(clamping: max(existingVideo.width, 0))
                    attachment.height = Int32(clamping: max(existingVideo.height, 0))
                    attachment.duration = Int32(clamping: max(existingVideo.durationSeconds, 0))
                    uploadedAttachments.append(attachment)
                }

                for file in self.sharedMediaFiles {
                    try Task.checkCancellation()
                    guard let fileURL = SharingManager.shared.localFileURL(from: file.path) else {
                        throw SharingSendError.fileUnavailable
                    }
                    guard FileManager.default.fileExists(atPath: fileURL.path) else {
                        throw SharingSendError.fileUnavailable
                    }

                    let filename = fileURL.lastPathComponent
                    let ext = fileURL.pathExtension.lowercased()
                    let filetype = SendMessageInputViewController.mimeType(for: ext)
                    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    guard let fileSizeNumber = attrs[.size] as? NSNumber else {
                        throw SharingSendError.fileUnavailable
                    }
                    let fileSize = fileSizeNumber.intValue
                    guard fileSize > 0 else {
                        throw SharingSendError.fileUnavailable
                    }

                    var width = 0
                    var height = 0
                    if file.type == .image,
                       let imageData = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                       let image = UIImage(data: imageData) {
                        width = Int(image.size.width)
                        height = Int(image.size.height)
                    } else if file.type == .video {
                        if let w = file.width, let h = file.height {
                            width = Int(w)
                            height = Int(h)
                        }
                    }

                    let sanitized = filename.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)

                    let uploaded = try await AttachmentUploader.shared.uploadFile(
                        fileURL: fileURL,
                        filename: sanitized,
                        filetype: filetype,
                        fileSize: fileSize,
                        width: width,
                        height: height,
                        token: token,
                        progressKey: fileURL.path,
                        network: self.context.account.network
                    )

                    var att = Mezon_Api_MessageAttachment()
                    att.filename = filename
                    att.url = uploaded.cdnURL
                    att.filetype = AttachmentTypeClassifier.uploadType(for: filetype)
                    att.size = Int32(fileSize)
                    if width > 0 { att.width = Int32(width) }
                    if height > 0 { att.height = Int32(height) }
                    if let duration = file.duration { att.duration = Int32(duration / 1000) }
                    if file.type == .video,
                       let thumbPath = file.thumbnail,
                       let thumbURL = SharingManager.shared.localFileURL(from: thumbPath) {
                        att.thumbnail = await self.uploadSharedVideoThumbnail(
                            thumbnailURL: thumbURL, videoFilename: sanitized, token: token)
                    }
                    uploadedAttachments.append(att)
                }

                let messageText = (self.textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let built = ComposerContentPayloadBuilder.build(rawInput: messageText, emojiIdByColon: [:])
                var contentJSON: [String: Any] = [:]
                if !messageText.isEmpty {
                    contentJSON["t"] = built.displayText
                    if !built.mk.isEmpty {
                        contentJSON["mk"] = built.mk
                    }
                    if !built.ej.isEmpty {
                        contentJSON["ej"] = built.ej
                    }
                }
                let contentStr: String
                if contentJSON.isEmpty {
                    contentStr = "{}"
                } else if let data = try? JSONSerialization.data(withJSONObject: contentJSON),
                          let str = String(data: data, encoding: .utf8) {
                    contentStr = str
                } else {
                    contentStr = "{}"
                }

                let isDM = target.type == MezonConstants.ChannelType.dm.rawValue
                let isGroup = target.type == MezonConstants.ChannelType.group.rawValue
                let isThread = target.type == MezonConstants.ChannelType.thread.rawValue

                let clanId: Int64 = isDM || isGroup ? 0 : target.clanID
                let mode: Int32
                if isThread {
                    mode = MezonConstants.ChannelStreamMode.thread.rawValue
                } else if isDM {
                    mode = MezonConstants.ChannelStreamMode.dm.rawValue
                } else if isGroup {
                    mode = MezonConstants.ChannelStreamMode.group.rawValue
                } else {
                    mode = clanId == 0
                        ? MezonConstants.ChannelStreamMode.group.rawValue
                        : MezonConstants.ChannelStreamMode.channel.rawValue
                }
                let isPublic = target.channelPrivate == 0

                if uploadedAttachments.isEmpty, self.hasAttachmentPreview {
                    throw SharingSendError.fileUnavailable
                }

                _ = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: target.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: [],
                    attachments: uploadedAttachments,
                    references: [],
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: self.context.currentUser?.avatarURL?.absoluteString ?? "",
                    topicId: 0,
                    token: token
                )

                SharingManager.shared.cleanupSharedFiles(self.sharedMediaFiles)
                finishUploadingUI()
                self.dismiss(animated: true)

            } catch is CancellationError {
                finishUploadingUI()
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "Sharing.sendWithAttachments",
                    "mediaCount": self.sharedMediaFiles.count + (self.existingVideoAttachment == nil ? 0 : 1),
                ])
                finishUploadingUI()
                self.showError(self.userFacingShareError(error))
            }
        }
    }

    private func userFacingShareError(_ error: Error) -> String {
        if let sharingError = error as? SharingSendError {
            return sharingError.message
        }
        if error is CancellationError {
            return L(L10n.Sharing.uploadCancelled)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return L(L10n.Sharing.uploadCancelled)
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost:
                return L(L10n.Sharing.uploadNetworkError)
            default:
                break
            }
        }
        if let mezon = error as? MezonError, let desc = mezon.errorDescription, !desc.isEmpty {
            return desc
        }
        let system = error.localizedDescription
        if system.localizedCaseInsensitiveContains("cancel") {
            return L(L10n.Sharing.uploadCancelled)
        }
        if system.isEmpty {
            return L(L10n.Sharing.uploadFailed)
        }
        return system
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: L(L10n.Sharing.errorTitle), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L(L10n.Sharing.alertOK), style: .default))
        present(alert, animated: true)
    }

    deinit {
        sendTask?.cancel()
        searchDebounceTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

private enum SharingSendError: Error {
    case fileUnavailable
    case targetUnavailable

    var message: String {
        switch self {
        case .fileUnavailable:
            return L(L10n.Sharing.fileUnavailable)
        case .targetUnavailable:
            return L(L10n.Sharing.targetUnavailable)
        }
    }
}

extension SharingViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath),
              let channel = channelDescription(for: item) else { return }

        let previousIdentity = selectedItemIdentity

        if previousIdentity == item.identity {
            selectedChannel = nil
            selectedItemIdentity = nil
            showSearchMode()
        } else {
            selectedChannel = channel
            selectedItemIdentity = item.identity
            showSelectedChannel(channel)
        }

        updateSendButton()

        var indexPathsToReload: [IndexPath] = [indexPath]
        if let prev = previousIdentity, prev != item.identity,
           let prevIndex = filteredSuggestions.firstIndex(where: { $0.identity == prev }) {
            indexPathsToReload.append(IndexPath(row: prevIndex, section: 0))
        }

        var snapshot = diffableDataSource.snapshot()
        let itemsToReload = indexPathsToReload.compactMap { diffableDataSource.itemIdentifier(for: $0) }
        snapshot.reloadItems(itemsToReload)
        diffableDataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension SharingViewController: UITableViewDataSourcePrefetching {

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { continue }
            if let urlStr = item.avatarURL, !urlStr.isEmpty {
                let proxyURL = SharingImageProxy.proxiedAvatarURLString(urlStr)
                if !proxyURL.isEmpty, ImageCache.shared.cachedImage(forURL: proxyURL) == nil {
                    _ = ImageCache.shared.loadImage(urlString: proxyURL) { _ in }
                }
            }
            if let rawLogo = item.clanLogo, !rawLogo.isEmpty {
                let proxyURL = SharingImageProxy.proxiedAvatarURLString(rawLogo)
                if !proxyURL.isEmpty, ImageCache.shared.cachedImage(forURL: proxyURL) == nil {
                    _ = ImageCache.shared.loadImage(urlString: proxyURL) { _ in }
                }
            }
        }
    }
}

extension SharingViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == searchTextField {
            textField.resignFirstResponder()
        } else if textField == self.textField && sendButton.isEnabled {
            sendTapped()
        }
        return false
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        if textField == self.textField {
            updateSendButton()
        }
    }
}
