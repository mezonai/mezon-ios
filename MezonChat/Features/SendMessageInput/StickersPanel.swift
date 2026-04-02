import UIKit


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


private enum StickerGridItem {
    case header(key: String, title: String, collapsed: Bool)
    case sticker(CachedClanStickerRecord)
    case emptyPad
}


final class StickersPanel: UIView {

    var onStickerSelected: ((CachedClanStickerRecord) -> Void)?
    var onSearchFocusChanged: ((Bool) -> Void)?

    var onInnerScroll: ((CGFloat, Bool) -> Void)?

    private weak var cacheEngine: MezonEngine?

    private var allStickers: [CachedClanStickerRecord] = []
    private var categoryOrder: [String] = []
    private var stickersByCategory: [String: [CachedClanStickerRecord]] = [:]
    private var collapsedCategories: Set<String> = [StickerCategoryOrdering.forSale]
    private var selectedStripCategory: String?
    private var isSearchActive = false
    private var searchQuery = ""

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
        iv.tintColor = .secondaryLabel
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
        cv.register(StickerSectionHeaderCell.self, forCellWithReuseIdentifier: StickerSectionHeaderCell.reuseId)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "pad")
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self
        cv.tag = 2
        return cv
    }()

    private let emptyStack: UIStackView = {
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(systemName: "face.smiling")
        icon.tintColor = UIColor.label.withAlphaComponent(0.2)
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)])
        let label = UILabel()
        label.text = "Stickers will appear here"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.label.withAlphaComponent(0.3)
        label.textAlignment = .center
        let sv = UIStackView(arrangedSubviews: [icon, label])
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 12
        return sv
    }()

    private var categoryStripCategories: [String] = []
    private var searchDebounceWorkItem: DispatchWorkItem?


    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
        searchTextField.addTarget(self, action: #selector(searchEditingDidBegin), for: .editingDidBegin)
        searchTextField.addTarget(self, action: #selector(searchEditingDidEnd), for: .editingDidEnd)
        searchTextField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
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

    func applyTheme() {
        let t = UIColor.theme
        searchBarContainer.backgroundColor = t.primary
        searchIconView.tintColor = t.textDisabled
        searchTextField.textColor = t.textStrong
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Find the perfect sticker",
            attributes: [.foregroundColor: t.textDisabled]
        )
        categoryCollection.reloadData()
        stickerGrid.reloadData()
    }


    private func setupLayout() {
        addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIconView)
        searchBarContainer.addSubview(searchTextField)
        addSubview(categoryCollection)
        addSubview(stickerGrid)
        addSubview(emptyStack)

        NSLayoutConstraint.activate([
            searchBarContainer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchBarContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            searchBarContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 40),

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
    }


    private func stickerCellWidth() -> CGFloat {
        let inset: CGFloat = 8
        let spacing: CGFloat = 4
        let availW = stickerGrid.bounds.width - inset * 2 - spacing * CGFloat(stickerColumns - 1)
        guard availW > 0 else { return 60 }
        return floor(availW / CGFloat(stickerColumns))
    }


    private func ingestStickers(_ stickers: [CachedClanStickerRecord]) {


        let visualStickers = stickers.filter { sticker in
            guard sticker.id != 0, !sticker.shortname.isEmpty else { return false }
            if sticker.mediaType == StickerMediaType.audio.rawValue { return false }
            let src = sticker.source.lowercased()
            if src.hasSuffix(".mp3") || src.hasSuffix(".wav") || src.contains("/sounds/") { return false }
            return true
        }
        allStickers = visualStickers

        let clanTuples = uniqueClans(from: visualStickers)
        let clanNames = clanTuples.map(\.name).filter { !$0.isEmpty }
        categoryOrder = StickerCategoryOrdering.categoryOrder(clanNames: clanNames)

        var map: [String: [CachedClanStickerRecord]] = [:]
        for c in categoryOrder { map[c] = [] }

        var unmapped = 0
        for sticker in visualStickers {
            if sticker.isForSale {
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
            } else {
                unmapped += 1
            }
        }
        stickersByCategory = map
        rebuildFlatItems()
        rebuildCategoryStrip()
        stickerGrid.reloadData()
        categoryCollection.reloadData()
        updateEmptyState()
    }

    private func uniqueClans(from stickers: [CachedClanStickerRecord]) -> [(id: Int64, name: String)] {
        var seen = Set<Int64>()
        var out: [(Int64, String)] = []
        for s in stickers where s.clanID != 0 {
            if seen.insert(s.clanID).inserted { out.append((s.clanID, s.clanName)) }
        }
        return out
    }

    private func rebuildCategoryStrip() {
        categoryStripCategories = categoryOrder.filter { !(stickersByCategory[$0] ?? []).isEmpty }
    }


    private func rebuildFlatItems() {
        var items: [StickerGridItem] = []
        var hMap: [String: Int] = [:]

        if isSearchActive, !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            let filtered = allStickers.filter { $0.shortname.lowercased().contains(q) }
            for s in filtered { items.append(.sticker(s)) }
            let remainder = filtered.count % stickerColumns
            if remainder > 0 { for _ in 0..<(stickerColumns - remainder) { items.append(.emptyPad) } }
        } else {
            for key in categoryOrder {
                let list = stickersByCategory[key] ?? []
                guard !list.isEmpty else { continue }
                let collapsed = collapsedCategories.contains(key)
                hMap[key] = items.count
                items.append(.header(key: key, title: displayTitle(for: key), collapsed: collapsed))
                if !collapsed {
                    for s in list { items.append(.sticker(s)) }
                    let remainder = list.count % stickerColumns
                    if remainder > 0 { for _ in 0..<(stickerColumns - remainder) { items.append(.emptyPad) } }
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
            cell.configure(categoryKey: key, title: displayTitle(for: key), isSelected: key == selectedStripCategory)
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
        if case .sticker(let s) = flatItems[indexPath.item] {
            handleStickerTap(s)
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView.tag == 2 else { return }
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
            return CGSize(width: 40, height: 40)
        }
        guard indexPath.item < flatItems.count else { return .zero }
        switch flatItems[indexPath.item] {
        case .header:
            return CGSize(width: collectionView.bounds.width - 16, height: 36)
        case .sticker, .emptyPad:
            let w = stickerCellWidth()
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
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.theme.textStrong
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.font = .systemFont(ofSize: 14, weight: .bold)
        initialLabel.textColor = UIColor.theme.textStrong
        initialLabel.textAlignment = .center
        contentView.addSubview(imageView)
        contentView.addSubview(initialLabel)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),
            initialLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(categoryKey: String, title: String, isSelected: Bool) {
        if categoryKey == StickerCategoryOrdering.forSale {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            imageView.isHidden = false
            initialLabel.isHidden = true
            imageView.image = UIImage(systemName: "bag.fill", withConfiguration: config)
        } else {
            imageView.isHidden = true
            initialLabel.isHidden = false
            initialLabel.text = String(title.prefix(1)).uppercased()
        }
        contentView.backgroundColor = isSelected
            ? UIColor.theme.bgViolet.withAlphaComponent(0.35)
            : UIColor.theme.primary.withAlphaComponent(0.5)
    }
}
