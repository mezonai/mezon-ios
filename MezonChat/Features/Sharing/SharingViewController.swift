import UIKit
import SwiftProtobuf
import AVFoundation

final class SharingViewController: UIViewController {

    private let context: AccountContext
    private let sharedContent: SharingManager.SharedContent

    private struct SuggestionItem: Hashable {
        let channelID: Int64
        let clanID: Int64
        let type: Int32
        let displayName: String
        let avatarURL: String?
        let channelAvatar: String
        let channelPrivate: Int32
        let clanName: String?

        func hash(into hasher: inout Hasher) { hasher.combine(channelID) }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.channelID == rhs.channelID }
    }

    private enum Section: Int, CaseIterable { case suggestions }

    private enum SuggestionFilter: Int {
        case all = 0
        case users = 1
        case channels = 2
    }

    private var allSuggestions: [SuggestionItem] = []
    private var filteredSuggestions: [SuggestionItem] = []
    private var channelMap: [Int64: Mezon_Api_ChannelDescription] = [:]
    private var clanNames: [Int64: String] = [:]
    private var clanLogos: [Int64: String] = [:]
    private var selectedChannel: Mezon_Api_ChannelDescription?
    private var searchText: String = ""
    private var suggestionFilter: SuggestionFilter = .all
    private var filterTooltipHost: UIView?
    private var filterTooltipPanel: UIView?
    private var isUploading = false
    private var searchDebounceTimer: Foundation.Timer?

    private var diffableDataSource: UITableViewDiffableDataSource<Section, SuggestionItem>!

    private var sharedMediaFiles: [SharingManager.SharedMediaFile] = []
    private var sharedTexts: [String] = []

    private let headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Share"
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let searchContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        v.layer.cornerRadius = 20
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = UIColor.white.withAlphaComponent(0.5)
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private lazy var searchTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 15)
        tf.textColor = .white
        tf.attributedPlaceholder = NSAttributedString(
            string: "",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.tintColor = .white
        return tf
    }()

    private let searchClearButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        b.tintColor = UIColor.white.withAlphaComponent(0.6)
        b.backgroundColor = UIColor.white.withAlphaComponent(0.15)
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
        l.textColor = .white
        l.textAlignment = .center
        l.isHidden = true
        return l
    }()

    private let selectedNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .white
        l.lineBreakMode = .byTruncatingTail
        l.isHidden = true
        return l
    }()

    private let filterButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        b.setImage(UIImage(systemName: "slider.horizontal.3", withConfiguration: config), for: .normal)
        b.tintColor = UIColor.white.withAlphaComponent(0.6)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
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
        l.text = "SUGGESTIONS"
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .white
        return l
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorStyle = .none
        tv.keyboardDismissMode = .onDrag
        tv.rowHeight = 52
        tv.estimatedRowHeight = 52
        tv.showsVerticalScrollIndicator = false
        return tv
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
        tf.tintColor = .white
        return tf
    }()

    private let sendButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        b.setImage(UIImage(systemName: "arrow.up", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.layer.cornerRadius = 20
        b.isEnabled = false
        b.alpha = 0.5
        return b
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
        ai.color = .white
        ai.hidesWhenStopped = true
        return ai
    }()

    private let loadingLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "Sending..."
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .white
        l.textAlignment = .center
        return l
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
        loadChannels()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isKeyboardVisible {
            let safeBottom = view.safeAreaInsets.bottom
            inputRowBottomConstraint?.constant = -(max(safeBottom, 8))
        }
        layoutFilterTooltipPanelIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissFilterTooltip(animated: false)
    }

    private func parseSharedContent() {
        switch sharedContent {
        case .media(let files):
            sharedMediaFiles = files
        case .text(let texts):
            sharedTexts = texts
            if let firstText = texts.first {
                textField.text = firstText
            }
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
        view.addSubview(filterButton)

        view.addSubview(suggestionsCard)
        suggestionsCard.addSubview(suggestionsTitle)
        suggestionsCard.addSubview(tableView)

        view.addSubview(bottomArea)
        bottomArea.addSubview(attachmentScrollView)
        attachmentScrollView.addSubview(attachmentStackView)
        bottomArea.addSubview(inputRow)
        inputRow.addSubview(inputPill)
        inputPill.addSubview(textField)
        inputRow.addSubview(sendButton)

        view.addSubview(loadingOverlay)
        loadingOverlay.addSubview(activityIndicator)
        loadingOverlay.addSubview(loadingLabel)

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
            searchContainer.trailingAnchor.constraint(equalTo: filterButton.leadingAnchor, constant: -8),
            searchContainer.heightAnchor.constraint(equalToConstant: 40),

            filterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            filterButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 36),
            filterButton.heightAnchor.constraint(equalToConstant: 36),

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
            selectedAvatarView.widthAnchor.constraint(equalToConstant: 24),
            selectedAvatarView.heightAnchor.constraint(equalToConstant: 24),

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
        ])

        let bottomConstraint = bottomArea.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        self.bottomAreaBottomConstraint = bottomConstraint

        let attachHeight = attachmentScrollView.heightAnchor.constraint(equalToConstant: sharedMediaFiles.isEmpty ? 0 : 80)
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
            loadingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingOverlay.widthAnchor.constraint(equalToConstant: 140),
            loadingOverlay.heightAnchor.constraint(equalToConstant: 100),

            activityIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: -10),

            loadingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 8),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
        ])

        if !sharedMediaFiles.isEmpty {
            buildAttachmentPreviews()
        }

        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.register(SharingChannelCell.self, forCellReuseIdentifier: SharingChannelCell.reuseId)
        setupDiffableDataSource()

        searchTextField.delegate = self
        searchTextField.addTarget(self, action: #selector(searchTextChanged(_:)), for: .editingChanged)
        searchClearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        textField.delegate = self
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        refreshSearchPlaceholder()
        filterButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
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

    private func suggestionsForCurrentFilter() -> [SuggestionItem] {
        switch suggestionFilter {
        case .all: return allSuggestions
        case .users: return allSuggestions.filter { isUserFacingDMType($0.type) }
        case .channels: return allSuggestions.filter { isSharableClanChannelType($0.type) }
        }
    }

    private func refreshSearchPlaceholder() {
        let s: String
        switch suggestionFilter {
        case .all: s = "Select a channel or user..."
        case .users: s = "Select user"
        case .channels: s = "Select channel"
        }
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: s,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
    }

    @objc private func filterButtonTapped() {
        if filterTooltipHost != nil {
            dismissFilterTooltip(animated: true)
            return
        }
        showFilterTooltip()
    }

    @objc private func filterTooltipBackgroundTapped() {
        dismissFilterTooltip(animated: true)
    }

    @objc private func filterTooltipRowTapped(_ sender: UIButton) {
        guard let filter = SuggestionFilter(rawValue: sender.tag) else { return }
        dismissFilterTooltip(animated: true)
        applySuggestionFilter(filter)
    }

    private func layoutFilterTooltipPanelIfNeeded() {
        guard let host = filterTooltipHost, let panel = filterTooltipPanel else { return }
        host.frame = view.bounds
        if let blocker = host.subviews.first(where: { $0 !== panel }) {
            blocker.frame = host.bounds
        }
        let anchor = filterButton.convert(filterButton.bounds, to: host)
        let width = max(170, min(220, view.bounds.width - 32))
        var x = anchor.midX - width / 2
        x = max(16, min(x, view.bounds.width - width - 16))
        let marginTop: CGFloat = 8
        var y = anchor.maxY + marginTop
        let safeBottom = view.safeAreaLayoutGuide.layoutFrame.maxY
        let panelH = panel.bounds.height
        if y + panelH > safeBottom - 8 {
            y = max(view.safeAreaInsets.top + 8, anchor.minY - marginTop - panelH)
        }
        var frame = panel.frame
        frame.origin = CGPoint(x: x, y: y)
        frame.size.width = width
        panel.frame = frame
    }

    private func showFilterTooltip() {
        guard filterTooltipHost == nil else { return }
        let t = UIColor.theme
        let host = UIView(frame: view.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = true

        let blocker = UIButton(type: .custom)
        blocker.frame = host.bounds
        blocker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blocker.backgroundColor = .clear
        blocker.addTarget(self, action: #selector(filterTooltipBackgroundTapped), for: .touchUpInside)
        host.addSubview(blocker)

        let panel = UIView()
        panel.backgroundColor = t.primary
        panel.layer.cornerRadius = 10
        panel.layer.masksToBounds = true

        let titleLabel = UILabel()
        titleLabel.text = "Filter options"
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white

        let titleLine = UIView()
        titleLine.backgroundColor = t.borderDim

        let targetWidth = max(170, min(220, view.bounds.width - 32))
        let padX: CGFloat = 12
        let rowH: CGFloat = 44
        var contentY: CGFloat = 10
        titleLabel.frame = CGRect(x: padX, y: contentY, width: targetWidth - padX * 2, height: 22)
        contentY = titleLabel.frame.maxY + 10
        titleLine.frame = CGRect(x: 0, y: contentY, width: targetWidth, height: 2)
        contentY = titleLine.frame.maxY
        panel.addSubview(titleLabel)
        panel.addSubview(titleLine)

        let rowSpecs: [(SuggestionFilter, String, String)] = [
            (.all, "square.grid.2x2", "All"),
            (.users, "person.2", "Users"),
            (.channels, "bubble.left.and.bubble.right", "Channels"),
        ]
        for (index, spec) in rowSpecs.enumerated() {
            let row = UIButton(type: .custom)
            row.tag = spec.0.rawValue
            row.frame = CGRect(x: 0, y: contentY, width: targetWidth, height: rowH)
            let isRowSelected = spec.0 == suggestionFilter
            let iconWeight: UIImage.SymbolWeight = isRowSelected ? .semibold : .medium
            let sym = UIImage(systemName: spec.1, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: iconWeight))
            row.setImage(sym, for: .normal)
            row.tintColor = .white
            let titleFont = UIFont.systemFont(ofSize: 14, weight: isRowSelected ? .semibold : .regular)
            row.setAttributedTitle(
                NSAttributedString(string: spec.2, attributes: [.font: titleFont, .foregroundColor: UIColor.white]),
                for: .normal
            )
            row.contentHorizontalAlignment = .left
            let trailingPad: CGFloat = isRowSelected ? padX + 22 : padX
            row.contentEdgeInsets = UIEdgeInsets(top: 0, left: padX, bottom: 0, right: trailingPad)
            row.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
            row.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
            row.backgroundColor = isRowSelected ? t.borderDim : .clear
            if isRowSelected {
                let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
                check.tintColor = .white
                check.frame = CGRect(x: targetWidth - padX - 17, y: (rowH - 16) / 2, width: 16, height: 16)
                check.isUserInteractionEnabled = false
                row.addSubview(check)
            }
            row.addTarget(self, action: #selector(filterTooltipRowTapped(_:)), for: .touchUpInside)
            panel.addSubview(row)
            contentY += rowH
            if index < rowSpecs.count - 1 {
                let sep = UIView(frame: CGRect(x: 0, y: contentY, width: targetWidth, height: 1))
                sep.backgroundColor = t.borderDim
                panel.addSubview(sep)
                contentY += 1
            }
        }

        host.addSubview(panel)
        filterTooltipHost = host
        filterTooltipPanel = panel

        let panelH = contentY + 8
        panel.frame = CGRect(x: 0, y: 0, width: targetWidth, height: panelH)
        panel.alpha = 0
        panel.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)

        view.addSubview(host)
        layoutFilterTooltipPanelIfNeeded()

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.6,
            options: [.allowUserInteraction, .curveEaseOut]
        ) {
            panel.alpha = 1
            panel.transform = .identity
        }

        DispatchQueue.main.async { [weak self] in
            self?.searchTextField.becomeFirstResponder()
        }
    }

    private func dismissFilterTooltip(animated: Bool) {
        guard let host = filterTooltipHost else {
            filterTooltipPanel = nil
            return
        }
        let finish = {
            host.removeFromSuperview()
            self.filterTooltipHost = nil
            self.filterTooltipPanel = nil
        }
        if animated, let panel = filterTooltipPanel {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
                panel.alpha = 0
                panel.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            } completion: { _ in finish() }
        } else {
            finish()
        }
    }

    private func applySuggestionFilter(_ filter: SuggestionFilter) {
        suggestionFilter = filter
        refreshSearchPlaceholder()
        refreshFilterButtonAppearance()
        filterChannels()
    }

    private func itemMatchesSearch(_ item: SuggestionItem, query: String) -> Bool {
        if item.displayName.lowercased().contains(query) { return true }
        if item.clanName?.lowercased().contains(query) == true { return true }
        guard let ch = channelMap[item.channelID] else { return false }
        for u in ch.usernames where u.lowercased().contains(query) { return true }
        for d in ch.displayNames where d.lowercased().contains(query) { return true }
        return false
    }

    private func setupDiffableDataSource() {
        diffableDataSource = UITableViewDiffableDataSource<Section, SuggestionItem>(tableView: tableView) {
            [weak self] tableView, indexPath, item in
            let cell = tableView.dequeueReusableCell(withIdentifier: SharingChannelCell.reuseId, for: indexPath) as! SharingChannelCell
            guard let self else { return cell }
            if let channel = self.channelMap[item.channelID] {
                let isSelected = self.selectedChannel?.channelID == item.channelID
                cell.configure(channel: channel, clanName: item.clanName, isSelected: isSelected)
            }
            return cell
        }
        diffableDataSource.defaultRowAnimation = .none
    }

    private func applySnapshot(animated: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SuggestionItem>()
        snapshot.appendSections([.suggestions])
        snapshot.appendItems(filteredSuggestions, toSection: .suggestions)
        diffableDataSource.apply(snapshot, animatingDifferences: animated)
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
                iv.backgroundColor = UIColor.white.withAlphaComponent(0.1)
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
                iv.backgroundColor = UIColor.white.withAlphaComponent(0.1)
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
                wrapper.backgroundColor = UIColor.white.withAlphaComponent(0.1)
                let fileIcon = UIImageView(image: UIImage(systemName: "doc.fill"))
                fileIcon.translatesAutoresizingMaskIntoConstraints = false
                fileIcon.tintColor = .systemBlue
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
                nameLabel.textColor = UIColor.white.withAlphaComponent(0.5)
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
        bottomArea.backgroundColor = t.secondary

        inputPill.backgroundColor = t.primary
        textField.textColor = .white
        textField.attributedPlaceholder = NSAttributedString(
            string: "Add a Comment (Optional)",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )

        sendButton.backgroundColor = UIColor(red: 0.34, green: 0.54, blue: 0.95, alpha: 1.0)

        suggestionsTitle.textColor = .white

        filterButton.backgroundColor = t.secondary
        filterButton.layer.cornerRadius = 18
        filterButton.clipsToBounds = true
        refreshFilterButtonAppearance()
    }

    private func refreshFilterButtonAppearance() {
        let t = UIColor.theme
        filterButton.backgroundColor = t.secondary
        switch suggestionFilter {
        case .all:
            filterButton.layer.borderWidth = 0
            filterButton.tintColor = t.text.withAlphaComponent(0.85)
        case .users, .channels:
            filterButton.layer.borderWidth = 2
            filterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
            filterButton.tintColor = .white
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismissFilterTooltip(animated: false)
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
        view.endEditing(true)
        SharingManager.shared.cleanupSharedFiles(sharedMediaFiles)
        dismiss(animated: true)
    }

    @objc private func sendTapped() {
        guard let channel = selectedChannel, !isUploading else { return }
        view.endEditing(true)
        performSend(to: channel)
    }

    @objc private func searchTextChanged(_ tf: UITextField) {
        searchText = tf.text ?? ""
        searchClearButton.isHidden = searchText.isEmpty
        filterChannels()
    }

    @objc private func clearSearchTapped() {
        if selectedChannel != nil {
            selectedChannel = nil
            showSearchMode()
            updateSendButton()
            tableView.reloadData()
        }
        searchTextField.text = ""
        searchText = ""
        searchClearButton.isHidden = true
        filterChannels()
    }

    private func imgproxyAvatarURLString(_ raw: String, displayPoints: CGFloat) -> String {
        let side = Int(ceil(displayPoints * UIScreen.main.scale))
        return ImgproxyURL.create(from: raw, width: side, height: side)
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
        selectedAvatarView.tintColor = .white

        if isDM, let avatarURL = channel.avatars.first, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
            selectedInitialLabel.isHidden = true
            selectedAvatarView.contentMode = .scaleAspectFill
            selectedAvatarView.backgroundColor = .clear
            let urlStr = imgproxyAvatarURLString(url.absoluteString, displayPoints: 24)
            _ = ImageCache.shared.loadImage(urlString: urlStr) { [weak self] image in
                self?.selectedAvatarView.image = image
            }
        } else if isGroup, !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
                  let url = URL(string: channel.channelAvatar) {
            selectedInitialLabel.isHidden = true
            selectedAvatarView.contentMode = .scaleAspectFill
            selectedAvatarView.backgroundColor = .clear
            let urlStr = imgproxyAvatarURLString(url.absoluteString, displayPoints: 24)
            _ = ImageCache.shared.loadImage(urlString: urlStr) { [weak self] image in
                self?.selectedAvatarView.image = image
            }
        } else if isGroup {
            selectedAvatarView.image = UIImage(systemName: "person.2.fill")?.withRenderingMode(.alwaysTemplate)
            selectedAvatarView.contentMode = .scaleAspectFit
            selectedInitialLabel.isHidden = true
            selectedAvatarView.backgroundColor = SharingChannelCell.groupDefaultAvatarBackground
        } else {
            let iconName = channel.channelListIconAssetName()
            selectedAvatarView.image = (UIImage(named: iconName) ?? UIImage(systemName: "number"))?.withRenderingMode(.alwaysTemplate)
            selectedAvatarView.contentMode = .scaleAspectFit
            selectedInitialLabel.isHidden = true
            selectedAvatarView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        }
    }

    private func showSearchMode() {
        searchTextField.isHidden = false
        searchIconView.isHidden = false
        selectedAvatarView.isHidden = true
        selectedNameLabel.isHidden = true
        selectedInitialLabel.isHidden = true
    }

    private func loadChannels() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }

            var dmList: [Mezon_Api_ChannelDescription] = []
            var clanList: [Mezon_Api_ChannelDescription] = []

            do {
                var dms = try await self.context.account.network.listDirectMessageChannels(token: token)
                do {
                    let badgeResponse = try await self.context.account.network.listChannelBadgeCount(clanId: 0, token: token)
                    ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &dms, badgeRows: badgeResponse.channeldesc)
                } catch {
                    AppLogger.network.debug("[Sharing] ListChannelBadgeCount: \(error)")
                }
                dmList = dms
                    .filter {
                        $0.type != MezonConstants.ChannelType.mezonVoice.rawValue && !$0.channelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .sorted { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
            } catch {
                AppLogger.network.error("[Sharing] Failed to load DM channels: \(error)")
            }

            if let allChannelsList = self.context.engine.clanData.getAllChannelsByUser() {
                clanList = allChannelsList.channeldesc.filter { ch in
                    let t = ch.type
                    return t == MezonConstants.ChannelType.channel.rawValue
                        || t == MezonConstants.ChannelType.thread.rawValue
                        || t == MezonConstants.ChannelType.announcement.rawValue
                }
                clanList.sort { self.sharingRecencyTimestamp($0) > self.sharingRecencyTimestamp($1) }
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
                AppLogger.network.error("[Sharing] Failed to load clan names: \(error)")
            }

            var suggestions: [SuggestionItem] = []
            suggestions.reserveCapacity(dmList.count + clanList.count)

            for ch in dmList {
                self.channelMap[ch.channelID] = ch
                suggestions.append(SuggestionItem(
                    channelID: ch.channelID,
                    clanID: ch.clanID,
                    type: ch.type,
                    displayName: SharingChannelCell.displayName(for: ch),
                    avatarURL: ch.avatars.first,
                    channelAvatar: ch.channelAvatar,
                    channelPrivate: ch.channelPrivate,
                    clanName: nil
                ))
            }
            for ch in clanList {
                self.channelMap[ch.channelID] = ch
                suggestions.append(SuggestionItem(
                    channelID: ch.channelID,
                    clanID: ch.clanID,
                    type: ch.type,
                    displayName: SharingChannelCell.displayName(for: ch),
                    avatarURL: ch.avatars.first,
                    channelAvatar: ch.channelAvatar,
                    channelPrivate: ch.channelPrivate,
                    clanName: self.clanNames[ch.clanID]
                ))
            }

            self.allSuggestions = suggestions
            self.performFilter()
        }
    }

    private func filterChannels() {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] (_: Foundation.Timer) in
            self?.performFilter()
        }
    }

    private func performFilter() {
        let base = suggestionsForCurrentFilter()
        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredSuggestions = base
        } else {
            var matched: [SuggestionItem] = []
            var matchedIds = Set<Int64>()
            for item in base where itemMatchesSearch(item, query: query) {
                matched.append(item)
                matchedIds.insert(item.channelID)
            }
            for item in base {
                guard let ch = channelMap[item.channelID], ch.parentID != 0 else { continue }
                if matchedIds.contains(ch.parentID), !matchedIds.contains(item.channelID) {
                    matched.append(item)
                    matchedIds.insert(item.channelID)
                }
            }
            filteredSuggestions = matched
        }
        applySnapshot()
    }

    private func updateSendButton() {
        let hasContent = !sharedMediaFiles.isEmpty || !(textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sharedTexts.isEmpty
        let enabled = selectedChannel != nil && hasContent && !isUploading
        sendButton.isEnabled = enabled
        sendButton.alpha = enabled ? 1.0 : 0.5
    }

    private func performSend(to channel: Mezon_Api_ChannelDescription) {
        isUploading = true
        loadingOverlay.isHidden = false
        activityIndicator.startAnimating()
        updateSendButton()

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                self.showError("Session expired")
                self.isUploading = false
                self.loadingOverlay.isHidden = true
                self.activityIndicator.stopAnimating()
                self.updateSendButton()
                return
            }

            do {
                var uploadedAttachments: [Mezon_Api_MessageAttachment] = []

                for file in self.sharedMediaFiles {
                    guard let fileURL = SharingManager.shared.localFileURL(from: file.path),
                          let fileData = try? Data(contentsOf: fileURL) else { continue }

                    let filename = fileURL.lastPathComponent
                    let ext = fileURL.pathExtension.lowercased()
                    let filetype = SendMessageInputViewController.mimeType(for: ext)

                    var width = 0
                    var height = 0
                    if file.type == .image, let image = UIImage(data: fileData) {
                        width = Int(image.size.width)
                        height = Int(image.size.height)
                    }

                    let sanitized = filename.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)

                    let uploadInfo = try await self.context.account.network.uploadAttachmentFile(
                        filename: sanitized,
                        filetype: filetype,
                        size: fileData.count,
                        width: width,
                        height: height,
                        token: token
                    )

                    try await self.context.account.network.uploadToMinIO(
                        url: uploadInfo.url,
                        data: fileData,
                        contentType: filetype
                    )

                    let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                    var att = Mezon_Api_MessageAttachment()
                    att.filename = filename
                    att.url = cdnURL
                    att.filetype = filetype
                    att.size = Int32(fileData.count)
                    if width > 0 { att.width = Int32(width) }
                    if height > 0 { att.height = Int32(height) }
                    if let duration = file.duration { att.duration = Int32(duration / 1000) }
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

                let isDM = channel.type == MezonConstants.ChannelType.dm.rawValue
                let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue
                let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue

                let clanId: Int64 = isDM || isGroup ? 0 : channel.clanID
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
                let isPublic = channel.channelPrivate == 0

                _ = try await self.context.account.network.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
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
                self.isUploading = false
                self.loadingOverlay.isHidden = true
                self.activityIndicator.stopAnimating()
                self.dismiss(animated: true)

            } catch {
                self.isUploading = false
                self.loadingOverlay.isHidden = true
                self.activityIndicator.stopAnimating()
                self.updateSendButton()
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    deinit {
        searchDebounceTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

extension SharingViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath),
              let channel = channelMap[item.channelID] else { return }

        let previousSelectedID = selectedChannel?.channelID

        if previousSelectedID == channel.channelID {
            selectedChannel = nil
            showSearchMode()
        } else {
            selectedChannel = channel
            showSelectedChannel(channel)
        }

        updateSendButton()

        var indexPathsToReload: [IndexPath] = [indexPath]
        if let prevID = previousSelectedID, prevID != channel.channelID,
           let prevIndex = filteredSuggestions.firstIndex(where: { $0.channelID == prevID }) {
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
            if let urlStr = item.avatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                let proxyURL = imgproxyAvatarURLString(url.absoluteString, displayPoints: 36)
                if ImageCache.shared.cachedImage(forURL: proxyURL) == nil {
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
