import UIKit
import AVFoundation


enum StickersPanelThemePlacement {
    case composerInline
    case secondaryBottomSheet
}

private enum StickerCategoryOrdering {
    static let forSale = "forsale"


    static func categoryOrder(clanNames: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = [forSale]
        seen.insert(forSale)
        for c in clanNames where !c.isEmpty {
            if seen.insert(c).inserted { out.append(c) }
        }
        return out
    }
}

private let stickerColumns = 5
private let audioStickerColumns = 2


private enum StickerGridItem {
    case header(key: String, title: String, collapsed: Bool)
    case sticker(CachedClanStickerRecord)
    case emptyPad
}


final class StickersPanel: UIView {

    var onStickerSelected: ((CachedClanStickerRecord) -> Void)?
    var onSearchFocusChanged: ((Bool) -> Void)?

    var onInnerScroll: ((CGFloat, Bool) -> Void)?

    var searchPlaceholderText: String = "Find the perfect sticker" {
        didSet { applyTheme() }
    }

    private weak var cacheEngine: MezonEngine?

    private var allStickers: [CachedClanStickerRecord] = []
    private var categoryOrder: [String] = []
    private var stickersByCategory: [String: [CachedClanStickerRecord]] = [:]
    private var collapsedCategories: Set<String> = [StickerCategoryOrdering.forSale]
    private var selectedStripCategory: String?
    private var isSearchActive = false
    private var searchQuery = ""
    private var rawStickerCache: [CachedClanStickerRecord] = []
    private var isAudioStickerMode = false
    private var audioPreviewPlayer: AVPlayer?
    private var audioPreviewEndObs: NSObjectProtocol?
    private var audioPreviewPlayingId: Int64?

    private var flatItems: [StickerGridItem] = []
    private var headerIndexMap: [String: Int] = [:]


    private let searchBarContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.image = UIImage(systemName: "magnifyingglass")
        iv.tintColor = UIColor.mezonSecondaryLabel
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 15)
        tf.returnKeyType = .search
        tf.clearButtonMode = .whileEditing
        tf.autocorrectionType = .no
        return tf
    }()

    private let soundFilterButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let fallback = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        let voiceImg = UIImage(named: "Channel/channelVoice")?.withRenderingMode(.alwaysTemplate) ?? fallback
        b.setImage(voiceImg, for: .normal)
        b.imageView?.contentMode = .scaleAspectFit
        b.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        b.layer.cornerRadius = 9
        b.clipsToBounds = true
        return b
    }()

    private lazy var categoryCollection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        cv.register(StickerCategoryStripCell.self, forCellWithReuseIdentifier: StickerCategoryStripCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        cv.tag = 1
        return cv
    }()

    private lazy var stickerGrid: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = true
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag
        cv.register(StickerCell.self, forCellWithReuseIdentifier: StickerCell.reuseId)
        cv.register(SoundStickerCell.self, forCellWithReuseIdentifier: SoundStickerCell.reuseId)
        cv.register(StickerSectionHeaderCell.self, forCellWithReuseIdentifier: StickerSectionHeaderCell.reuseId)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "pad")
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self
        cv.tag = 2
        return cv
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.mezonLabel.withAlphaComponent(0.3)
        label.textAlignment = .center
        return label
    }()

    private lazy var emptyStack: UIStackView = {
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(named: "Chat/FaceIcon")
            ?? UIImage(systemName: "face.smiling")
        icon.tintColor = UIColor.mezonLabel.withAlphaComponent(0.2)
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)])
        emptyStateLabel.text = "Stickers will appear here"
        let sv = UIStackView(arrangedSubviews: [icon, emptyStateLabel])
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 12
        return sv
    }()

    private var categoryStripCategories: [String] = []
    private var categoryStripLogos: [String: String] = [:]
    private var logoByClanId: [Int64: String] = [:]
    private var searchDebounceWorkItem: DispatchWorkItem?

    private var voiceReactionSoundOnlyMode = false
    private var searchBarTrailingToFilterConstraint: NSLayoutConstraint?
    private var searchBarTrailingToSuperviewConstraint: NSLayoutConstraint?

    private var stickersPanelPlacement: StickersPanelThemePlacement = .composerInline

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
        searchTextField.addTarget(self, action: #selector(searchEditingDidBegin), for: .editingDidBegin)
        searchTextField.addTarget(self, action: #selector(searchEditingDidEnd), for: .editingDidEnd)
        searchTextField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        soundFilterButton.addTarget(self, action: #selector(soundFilterTapped), for: .touchUpInside)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stopAudioPreview() }
    }

    required init?(coder: NSCoder) { fatalError() }


    func bindStickerCache(engine: MezonEngine) {
        cacheEngine = engine
        reloadFromPostboxCache()
    }

    func reloadFromPostboxCache() {
        let cache = cacheEngine?.data.cachedStickerList(clanId: 0)
        let stickers = cache?.stickers ?? []
        ingestStickers(stickers)
    }

    func configureVoiceReactionSoundOnlyLayout(_ enabled: Bool) {
        voiceReactionSoundOnlyMode = enabled
        soundFilterButton.isHidden = enabled
        if enabled {
            isAudioStickerMode = true
            searchBarTrailingToFilterConstraint?.isActive = false
            searchBarTrailingToSuperviewConstraint?.isActive = true
        } else {
            isAudioStickerMode = false
            searchBarTrailingToSuperviewConstraint?.isActive = false
            searchBarTrailingToFilterConstraint?.isActive = true
        }
        rebuildStickerListsFromCache()
        refreshSoundFilterButtonAppearance()
        updateEmptyState()
    }

    func applyTheme(placement: StickersPanelThemePlacement = .composerInline) {
        stickersPanelPlacement = placement
        let t = UIColor.theme
        switch placement {
        case .composerInline:
            searchBarContainer.backgroundColor = t.primary
        case .secondaryBottomSheet:
            searchBarContainer.backgroundColor = t.tertiary
        }
        searchIconView.tintColor = t.textDisabled
        searchTextField.textColor = t.textStrong
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: searchPlaceholderText,
            attributes: [.foregroundColor: t.textDisabled]
        )
        categoryCollection.reloadData()
        stickerGrid.reloadData()
        refreshSoundFilterButtonAppearance()
    }


    private func setupLayout() {
        addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIconView)
        searchBarContainer.addSubview(searchTextField)
        addSubview(soundFilterButton)
        addSubview(categoryCollection)
        addSubview(stickerGrid)
        addSubview(emptyStack)

        let trailToFilter = searchBarContainer.trailingAnchor.constraint(equalTo: soundFilterButton.leadingAnchor, constant: -8)
        let trailToSuper = searchBarContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        trailToSuper.isActive = false
        searchBarTrailingToFilterConstraint = trailToFilter
        searchBarTrailingToSuperviewConstraint = trailToSuper

        NSLayoutConstraint.activate([
            searchBarContainer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchBarContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            trailToFilter,
            searchBarContainer.heightAnchor.constraint(equalToConstant: 40),

            soundFilterButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            soundFilterButton.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            soundFilterButton.widthAnchor.constraint(equalToConstant: 38),
            soundFilterButton.heightAnchor.constraint(equalToConstant: 38),

            searchIconView.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor, constant: 12),
            searchIconView.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 18),
            searchIconView.heightAnchor.constraint(equalToConstant: 18),

            searchTextField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 8),
            searchTextField.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor, constant: -12),
            searchTextField.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
            searchTextField.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor),

            categoryCollection.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 8),
            categoryCollection.leadingAnchor.constraint(equalTo: leadingAnchor),
            categoryCollection.trailingAnchor.constraint(equalTo: trailingAnchor),
            categoryCollection.heightAnchor.constraint(equalToConstant: 44),

            stickerGrid.topAnchor.constraint(equalTo: categoryCollection.bottomAnchor, constant: 4),
            stickerGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            stickerGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            stickerGrid.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStack.topAnchor.constraint(equalTo: categoryCollection.bottomAnchor, constant: 40),
        ])
    }

    private func updateEmptyState() {
        let hasData = !allStickers.isEmpty
        emptyStack.isHidden = hasData
        stickerGrid.isHidden = !hasData
        categoryCollection.isHidden = !hasData
        emptyStateLabel.text = voiceReactionSoundOnlyMode ? "No sound stickers yet" : "Stickers will appear here"
    }


    private func stickerGridColumnCount() -> Int {
        isAudioStickerMode ? audioStickerColumns : stickerColumns
    }

    private func stickerCellWidth() -> CGFloat {
        let cols = stickerGridColumnCount()
        let inset: CGFloat = 8
        let spacing: CGFloat = 4
        let availW = stickerGrid.bounds.width - inset * 2 - spacing * CGFloat(cols - 1)
        guard availW > 0 else { return 60 }
        return floor(availW / CGFloat(cols))
    }

    private func ingestStickers(_ stickers: [CachedClanStickerRecord]) {
        rawStickerCache = stickers
        rebuildStickerListsFromCache()
    }

    private func isAudioStickerRecord(_ sticker: CachedClanStickerRecord) -> Bool {
        if sticker.mediaType == StickerMediaType.audio.rawValue { return true }
        let src = sticker.source.lowercased()
        if src.hasSuffix(".mp3") || src.hasSuffix(".wav") || src.hasSuffix(".m4a") { return true }
        if src.contains("/sounds/") { return true }
        return false
    }

    private func isVisualStickerRecord(_ sticker: CachedClanStickerRecord) -> Bool {
        !isAudioStickerRecord(sticker)
    }

    private func rebuildStickerListsFromCache() {
        let baseValid = rawStickerCache.filter { $0.id != 0 && !$0.shortname.isEmpty }
        let visual = baseValid.filter { isVisualStickerRecord($0) }
        let audio = baseValid.filter { isAudioStickerRecord($0) }
        if isAudioStickerMode {
            allStickers = audio
            buildStickerCategoryMaps(from: audio, includeForSale: false)
            collapsedCategories = []
        } else {
            allStickers = visual
            buildStickerCategoryMaps(from: visual, includeForSale: true)
        }
        rebuildFlatItems()
        rebuildCategoryStrip()
        stickerGrid.reloadData()
        categoryCollection.reloadData()
        updateEmptyState()
        refreshSoundFilterButtonAppearance()
    }

    private func buildStickerCategoryMaps(from stickers: [CachedClanStickerRecord], includeForSale: Bool) {
        let clanTuples = uniqueClans(from: stickers)
        let clanNames = clanTuples.map(\.name).filter { !$0.isEmpty }
        if includeForSale {
            categoryOrder = StickerCategoryOrdering.categoryOrder(clanNames: clanNames)
        } else {
            var seen = Set<String>()
            var out: [String] = []
            for c in clanNames where !c.isEmpty {
                if seen.insert(c).inserted { out.append(c) }
            }
            categoryOrder = out
        }

        var map: [String: [CachedClanStickerRecord]] = [:]
        for c in categoryOrder { map[c] = [] }

        for sticker in stickers {
            if includeForSale && sticker.isForSale {
                map[StickerCategoryOrdering.forSale, default: []].append(sticker)
                continue
            }
            let cat = sticker.clanName.isEmpty ? sticker.category : sticker.clanName
            if !cat.isEmpty {
                if map[cat] != nil {
                    map[cat, default: []].append(sticker)
                } else {
                    categoryOrder.append(cat)
                    map[cat] = [sticker]
                }
            }
        }
        stickersByCategory = map
    }

    @objc private func soundFilterTapped() {
        guard !voiceReactionSoundOnlyMode else { return }
        searchDebounceWorkItem?.cancel()
        searchTextField.text = ""
        searchQuery = ""
        isSearchActive = false
        stopAudioPreview()
        isAudioStickerMode.toggle()
        rebuildStickerListsFromCache()
    }

    private func refreshSoundFilterButtonAppearance() {
        let t = UIColor.theme
        if isAudioStickerMode {
            soundFilterButton.backgroundColor = t.bgViolet
            soundFilterButton.tintColor = .white
        } else {
            soundFilterButton.backgroundColor = t.secondaryLight
            soundFilterButton.tintColor = t.textStrong
        }
    }

    private func stopAudioPreview() {
        audioPreviewPlayer?.pause()
        audioPreviewPlayer = nil
        if let o = audioPreviewEndObs {
            NotificationCenter.default.removeObserver(o)
            audioPreviewEndObs = nil
        }
        audioPreviewPlayingId = nil
    }

    private func soundStickerIsActivelyPlaying(_ stickerId: Int64) -> Bool {
        audioPreviewPlayingId == stickerId && (audioPreviewPlayer?.rate ?? 0) > 0
    }

    fileprivate func handleSoundStickerPlayToggle(_ sticker: CachedClanStickerRecord) {
        let urlStr = Self.resolvedStickerMediaURLString(for: sticker)
        guard !urlStr.isEmpty, let url = URL(string: urlStr), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        if audioPreviewPlayingId == sticker.id {
            if (audioPreviewPlayer?.rate ?? 0) > 0 {
                audioPreviewPlayer?.pause()
            } else {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
                audioPreviewPlayer?.play()
            }
            reloadVisibleSoundStickerCells()
            return
        }
        stopAudioPreview()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        audioPreviewPlayer = player
        audioPreviewPlayingId = sticker.id
        audioPreviewEndObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.stopAudioPreview()
            self?.stickerGrid.reloadData()
        }
        player.play()
        reloadVisibleSoundStickerCells()
    }

    fileprivate func handleSoundStickerSend(_ sticker: CachedClanStickerRecord) {
        stopAudioPreview()
        guard !Self.resolvedStickerMediaURLString(for: sticker).isEmpty else { return }
        onStickerSelected?(sticker)
    }

    private func reloadVisibleSoundStickerCells() {
        let ips = stickerGrid.indexPathsForVisibleItems
        guard !ips.isEmpty else { return }
        UIView.performWithoutAnimation {
            self.stickerGrid.reloadItems(at: ips)
        }
    }

    private func uniqueClans(from stickers: [CachedClanStickerRecord]) -> [(id: Int64, name: String)] {
        var seen = Set<Int64>()
        var out: [(Int64, String)] = []
        for s in stickers where s.clanID != 0 {
            if seen.insert(s.clanID).inserted { out.append((s.clanID, s.clanName)) }
        }
        return out
    }

    private func rebuildLogoByClanId() {
        var map: [Int64: String] = [:]
        for s in rawStickerCache where s.clanID != 0 {
            let l = s.logo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty, map[s.clanID] == nil { map[s.clanID] = l }
        }
        if let emojis = cacheEngine?.data.cachedEmojiList(clanId: 0)?.emojis {
            for e in emojis where e.clanID != 0 {
                let l = e.logo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !l.isEmpty, map[e.clanID] == nil { map[e.clanID] = l }
            }
        }
        logoByClanId = map
    }

    private func rebuildCategoryStrip() {
        rebuildLogoByClanId()
        categoryStripCategories = categoryOrder.filter { !(stickersByCategory[$0] ?? []).isEmpty }
        var logos: [String: String] = [:]
        for key in categoryStripCategories where key != StickerCategoryOrdering.forSale {
            guard let list = stickersByCategory[key], let first = list.first else { continue }
            let fromSticker = first.logo.trimmingCharacters(in: .whitespacesAndNewlines)
            let fromClan = first.clanID != 0 ? (logoByClanId[first.clanID] ?? "") : ""
            let raw = !fromSticker.isEmpty ? fromSticker : fromClan
            guard !raw.isEmpty else { continue }
            let resolved = resolveClanStickerLogoURL(raw)
            if !resolved.isEmpty { logos[key] = resolved }
        }
        categoryStripLogos = logos
    }

    private func resolveClanStickerLogoURL(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if let u = URL(string: t), u.scheme != nil { return t }
        if t.hasPrefix("//") { return "https:\(t)" }
        let base = MezonConfig.baseImgURL
        if t.hasPrefix("/") { return "\(base)\(t)" }
        return "\(base)/\(t)"
    }


    private func rebuildFlatItems() {
        var items: [StickerGridItem] = []
        var hMap: [String: Int] = [:]

        let cols = stickerGridColumnCount()
        if isSearchActive, !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            let filtered = allStickers.filter { $0.shortname.lowercased().contains(q) }
            for s in filtered { items.append(.sticker(s)) }
            let remainder = filtered.count % cols
            if remainder > 0 { for _ in 0..<(cols - remainder) { items.append(.emptyPad) } }
        } else {
            for key in categoryOrder {
                let list = stickersByCategory[key] ?? []
                guard !list.isEmpty else { continue }
                let collapsed = collapsedCategories.contains(key)
                hMap[key] = items.count
                items.append(.header(key: key, title: displayTitle(for: key), collapsed: collapsed))
                if !collapsed {
                    for s in list { items.append(.sticker(s)) }
                    let remainder = list.count % cols
                    if remainder > 0 { for _ in 0..<(cols - remainder) { items.append(.emptyPad) } }
                }
            }
        }
        flatItems = items
        headerIndexMap = hMap
    }

    private func displayTitle(for key: String) -> String {
        if key == StickerCategoryOrdering.forSale { return "FOR SALE" }
        return key.uppercased()
    }


    @objc private func searchTextChanged() {
        searchDebounceWorkItem?.cancel()
        let text = searchTextField.text ?? ""
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isSearchActive = !self.searchQuery.isEmpty
            self.rebuildFlatItems()
            self.stickerGrid.reloadData()
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    @objc private func searchEditingDidBegin() { onSearchFocusChanged?(true) }
    @objc private func searchEditingDidEnd() { onSearchFocusChanged?(false) }


    private func selectCategoryFromStrip(_ categoryKey: String) {
        selectedStripCategory = categoryKey
        collapsedCategories.remove(categoryKey)
        rebuildFlatItems()
        categoryCollection.reloadData()
        stickerGrid.reloadData()
        stickerGrid.layoutIfNeeded()

        if let idx = headerIndexMap[categoryKey], idx < flatItems.count {
            stickerGrid.scrollToItem(at: IndexPath(item: idx, section: 0), at: .top, animated: true)
        }
    }

    private func toggleSectionHeaderByKey(_ key: String) {
        if collapsedCategories.contains(key) {
            collapsedCategories.remove(key)
        } else {
            collapsedCategories.insert(key)
        }
        rebuildFlatItems()
        stickerGrid.reloadData()
    }


    static func resolvedStickerMediaURLString(for sticker: CachedClanStickerRecord) -> String {
        let src = sticker.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.isEmpty { return "" }
        if let u = URL(string: src), u.scheme != nil { return src }
        if src.hasPrefix("//") { return "https:\(src)" }
        let base = MezonConfig.baseImgURL
        if src.hasPrefix("/") { return "\(base)\(src)" }
        return "\(base)/\(src)"
    }

    fileprivate static func stickerImageURL(for sticker: CachedClanStickerRecord) -> String {
        let src = sticker.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty, URL(string: src)?.scheme != nil { return src }

        return "\(MezonConfig.baseImgURL)/stickers/\(sticker.id).webp"
    }

    fileprivate func loadStickerImage(for sticker: CachedClanStickerRecord, into imageView: UIImageView) {
        let sourceURL = Self.stickerImageURL(for: sticker)
        guard !sourceURL.isEmpty else {
            return
        }

        let proxyURL = ImgproxyURL.create(from: sourceURL, width: 150, height: 150)

        if let cached = ImageCache.shared.memoryImage(forKey: proxyURL) {
            imageView.image = cached
            return
        }

        imageView.image = nil
        ImageCache.shared.loadImage(urlString: proxyURL) { [weak imageView] image in
            imageView?.image = image
        }
    }

    fileprivate func handleStickerTap(_ sticker: CachedClanStickerRecord) {
        if sticker.isForSale && sticker.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        onStickerSelected?(sticker)
    }
}


extension StickersPanel: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView.tag == 1 { return categoryStripCategories.count }
        return flatItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView.tag == 1 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StickerCategoryStripCell.reuseId, for: indexPath) as! StickerCategoryStripCell
            let key = categoryStripCategories[indexPath.item]
            cell.configure(
                categoryKey: key,
                title: displayTitle(for: key),
                logoURLString: categoryStripLogos[key],
                isSelected: key == selectedStripCategory
            )
            return cell
        }
        let item = flatItems[indexPath.item]
        switch item {
        case .header(let key, let title, let collapsed):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StickerSectionHeaderCell.reuseId, for: indexPath) as! StickerSectionHeaderCell
            cell.configure(key: key, title: title, collapsed: collapsed) { [weak self] k in
                self?.toggleSectionHeaderByKey(k)
            }
            return cell
        case .sticker(let sticker):
            if isAudioStickerMode {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SoundStickerCell.reuseId, for: indexPath) as! SoundStickerCell
                cell.configure(sticker: sticker, playing: soundStickerIsActivelyPlaying(sticker.id), panel: self, placement: stickersPanelPlacement)
                return cell
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StickerCell.reuseId, for: indexPath) as! StickerCell
            cell.configure(sticker: sticker, panel: self)
            return cell
        case .emptyPad:
            return collectionView.dequeueReusableCell(withReuseIdentifier: "pad", for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.tag == 1 {
            selectCategoryFromStrip(categoryStripCategories[indexPath.item])
            return
        }
        if isAudioStickerMode, case .sticker = flatItems[indexPath.item] { return }
        if case .sticker(let s) = flatItems[indexPath.item] {
            handleStickerTap(s)
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView.tag == 2, !isAudioStickerMode else { return }
        for ip in indexPaths {
            guard ip.item < flatItems.count, case .sticker(let s) = flatItems[ip.item] else { continue }
            let sourceURL = Self.stickerImageURL(for: s)
            let proxyURL = ImgproxyURL.create(from: sourceURL, width: 150, height: 150)
            guard ImageCache.shared.memoryImage(forKey: proxyURL) == nil else { continue }
            ImageCache.shared.loadImage(urlString: proxyURL) { _ in }
        }
    }
}


extension StickersPanel: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView.tag == 1 {
            return CGSize(width: 36, height: 36)
        }
        guard indexPath.item < flatItems.count else { return .zero }
        switch flatItems[indexPath.item] {
        case .header:
            return CGSize(width: collectionView.bounds.width - 16, height: 36)
        case .sticker:
            let w = stickerCellWidth()
            if isAudioStickerMode { return CGSize(width: w, height: 52) }
            return CGSize(width: w, height: w)
        case .emptyPad:
            let w = stickerCellWidth()
            if isAudioStickerMode { return CGSize(width: w, height: 52) }
            return CGSize(width: w, height: w)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if collectionView.tag == 1 { return UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16) }
        return UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == 1 { return 8 }
        return 4
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == 1 { return 8 }
        return 4
    }
}


extension StickersPanel {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.tag == 2 else { return }
        onInnerScroll?(scrollView.contentOffset.y, scrollView.isDragging || scrollView.isDecelerating)
    }
}


private final class SoundStickerCell: UICollectionViewCell {
    static let reuseId = "SoundStickerCell"

    private let rowBackground = UIView()
    private let playOuter = UIView()
    private let playInner = UIImageView()
    private let nameLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private var onPlay: (() -> Void)?
    private var onSend: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        rowBackground.translatesAutoresizingMaskIntoConstraints = false
        rowBackground.layer.cornerRadius = 10
        rowBackground.clipsToBounds = true
        playOuter.translatesAutoresizingMaskIntoConstraints = false
        playOuter.layer.cornerRadius = 14
        playInner.translatesAutoresizingMaskIntoConstraints = false
        playInner.contentMode = .scaleAspectFit
        if #available(iOS 13.0, *) {
            playInner.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        }
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        let sendCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let sendImg = UIImage(named: "Chat/SendMessageIcon")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: "paperplane.fill", withConfiguration: sendCfg)
        sendButton.setImage(sendImg, for: .normal)
        sendButton.imageView?.contentMode = .scaleAspectFit
        sendButton.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)

        contentView.addSubview(rowBackground)
        rowBackground.addSubview(playOuter)
        playOuter.addSubview(playInner)
        rowBackground.addSubview(nameLabel)
        rowBackground.addSubview(sendButton)

        NSLayoutConstraint.activate([
            rowBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            rowBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            rowBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            rowBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),

            playOuter.leadingAnchor.constraint(equalTo: rowBackground.leadingAnchor, constant: 8),
            playOuter.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            playOuter.widthAnchor.constraint(equalToConstant: 28),
            playOuter.heightAnchor.constraint(equalToConstant: 28),

            playInner.centerXAnchor.constraint(equalTo: playOuter.centerXAnchor),
            playInner.centerYAnchor.constraint(equalTo: playOuter.centerYAnchor),
            playInner.widthAnchor.constraint(equalToConstant: 12),
            playInner.heightAnchor.constraint(equalToConstant: 12),

            sendButton.trailingAnchor.constraint(equalTo: rowBackground.trailingAnchor, constant: -5),
            sendButton.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: playOuter.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            nameLabel.centerYAnchor.constraint(equalTo: rowBackground.centerYAnchor),
        ])

        let playTap = UITapGestureRecognizer(target: self, action: #selector(playTapped))
        playOuter.addGestureRecognizer(playTap)
        playOuter.isUserInteractionEnabled = true
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(sticker: CachedClanStickerRecord, playing: Bool, panel: StickersPanel, placement: StickersPanelThemePlacement) {
        let t = UIColor.theme
        switch placement {
        case .composerInline:
            rowBackground.backgroundColor = t.primary
        case .secondaryBottomSheet:
            rowBackground.backgroundColor = t.tertiary
        }
        playOuter.backgroundColor = t.secondary
        playInner.tintColor = t.bgViolet
        nameLabel.textColor = t.textStrong
        sendButton.tintColor = t.textStrong
        nameLabel.text = sticker.shortname
        let sym = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        playInner.image = UIImage(systemName: playing ? "pause.fill" : "play.fill", withConfiguration: sym)
        onPlay = { [weak panel] in panel?.handleSoundStickerPlayToggle(sticker) }
        onSend = { [weak panel] in panel?.handleSoundStickerSend(sticker) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPlay = nil
        onSend = nil
        nameLabel.text = nil
    }

    @objc private func playTapped() { onPlay?() }
    @objc private func sendTapped() { onSend?() }
}


private final class StickerSectionHeaderCell: UICollectionViewCell {
    static let reuseId = "StickerSectionHeaderCell"

    private let chevronView = UIImageView()
    private let titleLabel = UILabel()
    private var onToggle: ((String) -> Void)?
    private var categoryKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        }
        chevronView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong

        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(key: String, title: String, collapsed: Bool, onToggle: @escaping (String) -> Void) {
        categoryKey = key
        self.onToggle = onToggle
        titleLabel.text = title
        let t = UIColor.theme
        titleLabel.textColor = t.textStrong
        chevronView.tintColor = t.textStrong
        let chevronName = collapsed ? "chevron.right" : "chevron.down"
        chevronView.image = UIImage(systemName: chevronName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    }

    @objc private func tapped() { onToggle?(categoryKey) }
}


private final class StickerCell: UICollectionViewCell {
    static let reuseId = "StickerCell"

    private let stickerImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 6
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(stickerImageView)
        NSLayoutConstraint.activate([
            stickerImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            stickerImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            stickerImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            stickerImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(sticker: CachedClanStickerRecord, panel: StickersPanel) {
        stickerImageView.image = nil
        if sticker.isForSale && sticker.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentView.alpha = 0.45
        } else {
            contentView.alpha = 1
        }
        panel.loadStickerImage(for: sticker, into: stickerImageView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stickerImageView.image = nil
        contentView.alpha = 1
    }
}


private final class StickerCategoryStripCell: UICollectionViewCell {
    static let reuseId = "StickerCategoryStripCell"

    private let imageView = UIImageView()
    private let initialLabel = UILabel()
    private var logoLoadKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        imageView.tintColor = UIColor.theme.textStrong
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.font = .systemFont(ofSize: 12, weight: .bold)
        initialLabel.textColor = UIColor.theme.textStrong
        initialLabel.textAlignment = .center
        contentView.addSubview(imageView)
        contentView.addSubview(initialLabel)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),
            initialLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        logoLoadKey = nil
        imageView.image = nil
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 6
    }

    func configure(categoryKey: String, title: String, logoURLString: String?, isSelected: Bool) {
        contentView.backgroundColor = isSelected
            ? UIColor.theme.bgViolet.withAlphaComponent(0.35)
            : UIColor.theme.primary.withAlphaComponent(0.5)
        if categoryKey == StickerCategoryOrdering.forSale {
            logoLoadKey = nil
            imageView.isHidden = false
            initialLabel.isHidden = true
            imageView.contentMode = .scaleAspectFit
            imageView.layer.cornerRadius = 0
            imageView.tintColor = UIColor.theme.textStrong
            let storeCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let storeImg = UIImage(named: "Chat/StoreIcon")?.withRenderingMode(.alwaysTemplate)
                ?? UIImage(systemName: "bag.fill", withConfiguration: storeCfg)?.withRenderingMode(.alwaysTemplate)
            imageView.image = storeImg
            return
        }
        let logo = logoURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !logo.isEmpty {
            logoLoadKey = logo
            imageView.isHidden = false
            initialLabel.isHidden = true
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = 6
            imageView.tintColor = nil
            imageView.image = nil
            let px = Int(24 * UIScreen.main.scale)
            let proxy = ImgproxyURL.create(from: logo, width: px, height: px)
            if let mem = ImageCache.shared.memoryImage(forKey: proxy) {
                imageView.image = mem
            } else {
                ImageCache.shared.loadImage(urlString: proxy) { [weak self] img in
                    guard let self else { return }
                    guard self.logoLoadKey == logo else { return }
                    self.imageView.image = img
                }
            }
            return
        }
        logoLoadKey = nil
        imageView.isHidden = true
        initialLabel.isHidden = false
        initialLabel.text = String(title.prefix(1)).uppercased()
    }
}
