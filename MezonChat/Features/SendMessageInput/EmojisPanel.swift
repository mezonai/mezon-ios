import UIKit

private enum EmojiCategoryOrdering {
    static let forSale = "forsale"
    static let recent = "Recent"
    static let frequently = "Frequently"
    static let predefinedSuffix = ["People", "Nature", "Food", "Activities", "Travel", "Objects", "Symbols", "Flags"]
    static let predefinedPrefix = [recent, forSale, frequently]

    static func categoryOrder(clanNames: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for c in predefinedPrefix + clanNames + predefinedSuffix where !c.isEmpty {
            if seen.insert(c).inserted { out.append(c) }
        }
        return out
    }
}

private let emojiColumns = 9
private let emojiGridProxySide = 32
private let emojiGridInteritemSpacing: CGFloat = 2
private let emojiGridLineSpacing: CGFloat = 4

private func dbg(_ message: String) {
}

enum EmojisPanelThemePlacement {
    case composerInline
    case secondaryBottomSheet
}

private enum EmojiGridItem {
    case header(key: String, title: String, collapsed: Bool)
    case emoji(CachedClanEmojiRecord)
    case emptyPad
}


final class EmojisPanel: UIView {

    var onEmojiSelected: ((String, String) -> Void)?
    var onSearchFocusChanged: ((Bool) -> Void)?

    var onInnerScroll: ((CGFloat, Bool) -> Void)?

    var sheetPanCoordinationScrollView: UIScrollView { emojiGrid }

    var searchPlaceholderText: String = "Find the perfect emoji"

    private weak var cacheEngine: MezonEngine?

    private var allEmojis: [CachedClanEmojiRecord] = []
    private var categoryOrder: [String] = []
    private var emojisByCategory: [String: [CachedClanEmojiRecord]] = [:]
    private var collapsedCategories: Set<String> = [EmojiCategoryOrdering.forSale]
    private var selectedStripCategory: String?
    private var isSearchActive = false
    private var searchQuery = ""

    private var flatItems: [EmojiGridItem] = []

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
        cv.register(EmojiCategoryStripCell.self, forCellWithReuseIdentifier: EmojiCategoryStripCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        cv.tag = 1
        return cv
    }()

    private lazy var emojiGrid: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = emojiGridInteritemSpacing
        layout.minimumLineSpacing = emojiGridLineSpacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = true
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = true
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag
        cv.register(EmojiGridCell.self, forCellWithReuseIdentifier: EmojiGridCell.reuseId)
        cv.register(EmojiSectionHeaderCell.self, forCellWithReuseIdentifier: EmojiSectionHeaderCell.reuseId)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "emojiPad")
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self
        cv.tag = 2
        return cv
    }()

    private var categoryStripCategories: [String] = []
    private var categoryStripLogos: [String: String] = [:]
    private var searchDebounceWorkItem: DispatchWorkItem?

    private var themePlacement: EmojisPanelThemePlacement = .composerInline

    private var lastGridLayoutSize: CGSize = .zero
    private var lastNotifyPanelSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
        searchTextField.addTarget(self, action: #selector(searchEditingDidBegin), for: .editingDidBegin)
        searchTextField.addTarget(self, action: #selector(searchEditingDidEnd), for: .editingDidEnd)
        searchTextField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError() }

    func bindEmojiCache(engine: MezonEngine) {
        dbg("bindEmojiCache")
        cacheEngine = engine
        reloadFromPostboxCache()
    }

    func reloadFromPostboxCache() {
        let cache = cacheEngine?.data.cachedEmojiList(clanId: 0)
        let emojis = cache?.emojis ?? []
        dbg("reloadFromPostboxCache rawCount=\(emojis.count) cacheNil=\(cache == nil)")
        ingestEmojis(emojis)
    }

    func logEmojiLoadingState(tag: String) {
        _ = tag
    }

    func emojiGridDebugSummary() -> String {
        return "flatItems=\(flatItems.count) gridContentH=\(emojiGrid.contentSize.height) gridBounds=\(emojiGrid.bounds.size) visible=\(emojiGrid.visibleCells.count)"
    }

    func notifyEmbeddedPanelBoundsChanged() {
        let panelSz = bounds.size
        if abs(panelSz.width - lastNotifyPanelSize.width) > 0.5 || abs(panelSz.height - lastNotifyPanelSize.height) > 0.5 {
            lastNotifyPanelSize = panelSz
            lastGridLayoutSize = .zero
        }
        setNeedsLayout()
        layoutIfNeeded()
        layoutEmojiGridViewFrameIfNeeded()
        emojiGrid.collectionViewLayout.invalidateLayout()
        emojiGrid.layoutIfNeeded()
        let sz = emojiGrid.bounds.size
        if sz.width > 0, sz.height > 0 {
            lastGridLayoutSize = sz
        }
        dbg("notifyEmbedded bounds panel=\(bounds.size) gridView=\(emojiGrid.bounds.size) contentSize=\(emojiGrid.contentSize) visibleCells=\(emojiGrid.visibleCells.count)")
    }

    func applyTheme(placement: EmojisPanelThemePlacement = .composerInline) {
        themePlacement = placement
        let t = UIColor.theme
        backgroundColor = .clear
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
        if placement == .secondaryBottomSheet {
            if let p = categoryStripCategories.first(where: { $0 != EmojiCategoryOrdering.forSale }) {
                selectCategoryFromStrip(p)
            } else if flatItems.isEmpty {
                categoryCollection.reloadData()
                emojiGrid.reloadData()
            }
        } else if flatItems.isEmpty {
            categoryCollection.reloadData()
            emojiGrid.reloadData()
        }
    }

    private func setupLayout() {
        addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIconView)
        searchBarContainer.addSubview(searchTextField)
        addSubview(categoryCollection)

        emojiGrid.backgroundColor = .clear
        addSubview(emojiGrid)

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
        ])
    }

    private func layoutEmojiGridViewFrameIfNeeded() {
        let top = categoryCollection.frame.maxY + 4
        let h = bounds.height - top
        guard bounds.width > 0, h > 0 else { return }
        let r = CGRect(x: 0, y: top, width: bounds.width, height: h)
        if emojiGrid.frame != r {
            emojiGrid.frame = r
        }
    }

    private func emojiGridCellColumnWidth(forGridWidth gridW: CGFloat) -> CGFloat {
        let inset: CGFloat = 8
        let availW = gridW - inset * 2
        guard availW > 0 else { return 36 }
        let gaps = emojiGridInteritemSpacing * CGFloat(emojiColumns - 1)
        return floor((availW - gaps) / CGFloat(emojiColumns))
    }

    private func emojiGridFlowLayoutItemSize(at indexPath: IndexPath, gridLayoutWidth gridW: CGFloat) -> CGSize {
        guard indexPath.item < flatItems.count else { return CGSize(width: 44, height: 44) }
        let cellW = emojiGridCellColumnWidth(forGridWidth: gridW)
        switch flatItems[indexPath.item] {
        case .header:
            let w = max(gridW - 16, 0)
            return CGSize(width: w, height: 36)
        case .emoji, .emptyPad:
            return CGSize(width: cellW, height: 44)
        }
    }

    private func emojiCellWidth() -> CGFloat {
        let gridW = emojiGrid.bounds.width > 0 ? emojiGrid.bounds.width : bounds.width
        return emojiGridCellColumnWidth(forGridWidth: gridW)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutEmojiGridViewFrameIfNeeded()
        let sz = emojiGrid.bounds.size
        if sz.width > 0, sz.height > 0,
           abs(sz.width - lastGridLayoutSize.width) > 0.5 || abs(sz.height - lastGridLayoutSize.height) > 0.5 {
            dbg("layoutSubviews grid size \(lastGridLayoutSize) -> \(sz)")
            lastGridLayoutSize = sz
            emojiGrid.collectionViewLayout.invalidateLayout()
        }
    }

    private func ingestEmojis(_ emojis: [CachedClanEmojiRecord]) {
        allEmojis = emojis
        let clanTuples = uniqueClans(from: emojis)
        let clanNames = clanTuples.map(\.name).filter { !$0.isEmpty }
        categoryOrder = EmojiCategoryOrdering.categoryOrder(clanNames: clanNames)

        var map: [String: [CachedClanEmojiRecord]] = [:]
        for c in categoryOrder { map[c] = [] }

        for emoji in emojis {
            guard emoji.id != 0, !emoji.shortname.isEmpty else { continue }
            if emoji.isForSale {
                map[EmojiCategoryOrdering.forSale, default: []].append(emoji)
                continue
            }
            guard !emoji.category.isEmpty else { continue }
            for cat in categoryOrder {
                if emoji.category.contains(cat) {
                    map[cat, default: []].append(emoji)
                }
            }
        }
        emojisByCategory = map
        rebuildFlatItems()
        rebuildCategoryStrip()
        dbg("ingest done flatItems=\(flatItems.count) stripCategories=\(categoryStripCategories.count)")
        emojiGrid.reloadData()
        categoryCollection.reloadData()
    }

    private func uniqueClans(from emojis: [CachedClanEmojiRecord]) -> [(id: Int64, name: String)] {
        var seen = Set<Int64>()
        var out: [(Int64, String)] = []
        for e in emojis where e.clanID != 0 {
            if seen.insert(e.clanID).inserted { out.append((e.clanID, e.clanName)) }
        }
        return out
    }

    private func rebuildCategoryStrip() {
        categoryStripCategories = categoryOrder.filter { !(emojisByCategory[$0] ?? []).isEmpty }
        var byClan: [Int64: String] = [:]
        for e in allEmojis where e.clanID != 0 {
            let l = e.logo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty, byClan[e.clanID] == nil { byClan[e.clanID] = l }
        }
        if let stickers = cacheEngine?.data.cachedStickerList(clanId: 0)?.stickers {
            for s in stickers where s.clanID != 0 {
                let l = s.logo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !l.isEmpty, byClan[s.clanID] == nil { byClan[s.clanID] = l }
            }
        }
        var logos: [String: String] = [:]
        for key in categoryStripCategories {
            if EmojiCategoryOrdering.predefinedPrefix.contains(key) || EmojiCategoryOrdering.predefinedSuffix.contains(key) { continue }
            guard let list = emojisByCategory[key], let first = list.first, first.clanID != 0 else { continue }
            let sLogo = first.logo.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = !sLogo.isEmpty ? sLogo : (byClan[first.clanID] ?? "")
            guard !raw.isEmpty else { continue }
            let resolved = Self.resolveClanStripLogoURL(raw)
            if !resolved.isEmpty { logos[key] = resolved }
        }
        categoryStripLogos = logos
    }

    private static func resolveClanStripLogoURL(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if let u = URL(string: t), u.scheme != nil { return t }
        if t.hasPrefix("//") { return "https:\(t)" }
        let base = MezonConfig.baseImgURL
        if t.hasPrefix("/") { return "\(base)\(t)" }
        return "\(base)/\(t)"
    }

    private func rebuildFlatItems() {
        var items: [EmojiGridItem] = []
        var hMap: [String: Int] = [:]

        if isSearchActive, !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            let filtered = allEmojis.filter { $0.shortname.lowercased().contains(q) }
            for emoji in filtered { items.append(.emoji(emoji)) }

            let remainder = filtered.count % emojiColumns
            if remainder > 0 { for _ in 0..<(emojiColumns - remainder) { items.append(.emptyPad) } }
        } else {
            for key in categoryOrder {
                let list = emojisByCategory[key] ?? []
                guard !list.isEmpty else { continue }
                let collapsed = collapsedCategories.contains(key)
                hMap[key] = items.count
                items.append(.header(key: key, title: displayTitle(for: key), collapsed: collapsed))
                if !collapsed {
                    for emoji in list { items.append(.emoji(emoji)) }
                    let remainder = list.count % emojiColumns
                    if remainder > 0 { for _ in 0..<(emojiColumns - remainder) { items.append(.emptyPad) } }
                }
            }
        }
        flatItems = items
        headerIndexMap = hMap
    }

    private func displayTitle(for key: String) -> String {
        switch key {
        case EmojiCategoryOrdering.recent: return "Recent"
        case EmojiCategoryOrdering.forSale: return "For sale"
        case EmojiCategoryOrdering.frequently: return "Frequently"
        default: return key
        }
    }

    private func emojiGridItemCount(forCategory key: String) -> Int {
        let list = emojisByCategory[key] ?? []
        guard !list.isEmpty else { return 0 }
        let remainder = list.count % emojiColumns
        return list.count + (remainder > 0 ? emojiColumns - remainder : 0)
    }

    private func emojiGridSectionItemRange(startingAt headerIdx: Int, in items: [EmojiGridItem]) -> Range<Int>? {
        guard headerIdx < items.count, case .header = items[headerIdx] else { return nil }
        var end = headerIdx + 1
        while end < items.count {
            if case .header = items[end] { break }
            end += 1
        }
        guard end > headerIdx + 1 else { return nil }
        return (headerIdx + 1)..<end
    }

    @objc private func searchTextChanged() {
        searchDebounceWorkItem?.cancel()
        let text = searchTextField.text ?? ""
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isSearchActive = !self.searchQuery.isEmpty
            self.rebuildFlatItems()
            self.emojiGrid.reloadData()
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
        emojiGrid.reloadData()
        emojiGrid.layoutIfNeeded()

        if let idx = headerIndexMap[categoryKey], idx < flatItems.count {
            emojiGrid.scrollToItem(at: IndexPath(item: idx, section: 0), at: .top, animated: true)
        }
    }

    fileprivate static func emojiImageURL(for emoji: CachedClanEmojiRecord) -> URL? {
        let side = emojiGridProxySide
        let trimmed = emoji.src.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed), u.scheme != nil {
            let proxied = ImgproxyURL.createEmoji(from: u.absoluteString, width: side, height: side)
            return URL(string: proxied)
        }
        return MezonConfig.emojiResourceURL(emojiId: "\(emoji.id)", imgproxyFitSide: side)
    }

    fileprivate func handleEmojiTap(_ emoji: CachedClanEmojiRecord) {
        if emoji.isForSale && emoji.src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        onEmojiSelected?("\(emoji.id)", emoji.shortname)
    }
}


extension EmojisPanel: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView.tag == 1 { return categoryStripCategories.count }
        return flatItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView.tag == 1 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCategoryStripCell.reuseId, for: indexPath) as! EmojiCategoryStripCell
            let key = categoryStripCategories[indexPath.item]
            let t = UIColor.theme
            let stripUnselected: UIColor
            switch themePlacement {
            case .composerInline:
                stripUnselected = t.primary.withAlphaComponent(0.5)
            case .secondaryBottomSheet:
                stripUnselected = t.tertiary
            }
            cell.configure(
                categoryKey: key,
                title: displayTitle(for: key),
                isSelected: key == selectedStripCategory,
                symbol: Self.stripSymbol(for: key),
                unselectedBackground: stripUnselected,
                logoURLString: categoryStripLogos[key]
            )
            return cell
        }

        let item = flatItems[indexPath.item]
        switch item {
        case .header(let key, let title, let collapsed):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiSectionHeaderCell.reuseId, for: indexPath) as! EmojiSectionHeaderCell
            cell.configure(key: key, title: title, collapsed: collapsed) { [weak self] k in
                self?.toggleSectionHeaderByKey(k)
            }
            return cell
        case .emoji(let emoji):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiGridCell.reuseId, for: indexPath) as! EmojiGridCell
            cell.configure(emoji: emoji)
            return cell
        case .emptyPad:
            return collectionView.dequeueReusableCell(withReuseIdentifier: "emojiPad", for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.tag == 1 {
            selectCategoryFromStrip(categoryStripCategories[indexPath.item])
            return
        }
        guard indexPath.item < flatItems.count else { return }
        switch flatItems[indexPath.item] {
        case .emoji(let emoji):
            handleEmojiTap(emoji)
        case .header, .emptyPad:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView.tag == 2 else { return }
        for ip in indexPaths {
            guard ip.item < flatItems.count, case .emoji(let emoji) = flatItems[ip.item],
                  let url = Self.emojiImageURL(for: emoji) else { continue }
            let key = url.absoluteString
            guard ImageCache.shared.memoryImage(forKey: key) == nil else { continue }
            ImageCache.shared.loadImage(urlString: key) { _ in }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView.tag == 1 {
            return CGSize(width: 36, height: 36)
        }
        let gridW = collectionView.bounds.width
        return emojiGridFlowLayoutItemSize(at: indexPath, gridLayoutWidth: gridW)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if collectionView.tag == 1 {
            return UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        }
        return UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == 1 { return 8 }
        return emojiGridInteritemSpacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == 1 { return 8 }
        return emojiGridLineSpacing
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.tag == 2 else { return }
        onInnerScroll?(scrollView.contentOffset.y, scrollView.isDragging)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView.tag == 2, !decelerate else { return }
        onInnerScroll?(scrollView.contentOffset.y, false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView.tag == 2 else { return }
        onInnerScroll?(scrollView.contentOffset.y, false)
    }

    fileprivate func toggleSectionHeaderByKey(_ key: String) {
        guard let headerIdx = headerIndexMap[key], headerIdx < flatItems.count else {
            if collapsedCategories.contains(key) {
                collapsedCategories.remove(key)
            } else {
                collapsedCategories.insert(key)
            }
            rebuildFlatItems()
            UIView.performWithoutAnimation {
                emojiGrid.reloadData()
            }
            return
        }

        let wasCollapsed = collapsedCategories.contains(key)
        let deleteRange = wasCollapsed ? nil : emojiGridSectionItemRange(startingAt: headerIdx, in: flatItems)
        let insertCount = wasCollapsed ? emojiGridItemCount(forCategory: key) : 0

        if wasCollapsed {
            collapsedCategories.remove(key)
        } else {
            collapsedCategories.insert(key)
        }
        rebuildFlatItems()

        let headerPath = IndexPath(item: headerIdx, section: 0)
        emojiGrid.performBatchUpdates({
            if wasCollapsed, insertCount > 0 {
                let paths = (0..<insertCount).map { IndexPath(item: headerIdx + 1 + $0, section: 0) }
                emojiGrid.insertItems(at: paths)
            } else if let range = deleteRange {
                emojiGrid.deleteItems(at: range.map { IndexPath(item: $0, section: 0) })
            }
            emojiGrid.reloadItems(at: [headerPath])
        }, completion: nil)
    }
}


extension EmojisPanel {
    fileprivate static func stripSymbol(for key: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        switch key {
        case EmojiCategoryOrdering.recent: return UIImage(systemName: "clock", withConfiguration: config)
        case EmojiCategoryOrdering.forSale:
            return UIImage(named: "Chat/StoreIcon")?.withRenderingMode(.alwaysTemplate)
                ?? UIImage(systemName: "bag.fill", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        case EmojiCategoryOrdering.frequently: return UIImage(systemName: "star.fill", withConfiguration: config)
        case "People":
            return UIImage(named: "Chat/FaceIcon")
                ?? UIImage(systemName: "face.smiling", withConfiguration: config)
        case "Nature": return UIImage(systemName: "leaf.fill", withConfiguration: config)
        case "Food": return UIImage(systemName: "fork.knife", withConfiguration: config)
        case "Activities": return UIImage(systemName: "figure.run", withConfiguration: config)
        case "Travel": return UIImage(systemName: "bicycle", withConfiguration: config)
        case "Objects": return UIImage(systemName: "archivebox.fill", withConfiguration: config)
        case "Symbols": return UIImage(systemName: "heart.fill", withConfiguration: config)
        case "Flags": return UIImage(systemName: "flag.fill", withConfiguration: config)
        default: return UIImage(systemName: "building.2.fill", withConfiguration: config)
        }
    }
}


private final class EmojiSectionHeaderCell: UICollectionViewCell {
    static let reuseId = "EmojiSectionHeaderCell"

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


private final class EmojiGridCell: UICollectionViewCell {
    static let reuseId = "EmojiGridCell"

    private let emojiImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        return iv
    }()

    private var loadKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(emojiImageView)
        NSLayoutConstraint.activate([
            emojiImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emojiImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            emojiImageView.widthAnchor.constraint(equalToConstant: 32),
            emojiImageView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadKey = nil
        emojiImageView.image = nil
        contentView.alpha = 1
    }

    func configure(emoji: CachedClanEmojiRecord) {
        if emoji.isForSale && emoji.src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentView.alpha = 0.45
        } else {
            contentView.alpha = 1
        }
        guard let url = EmojisPanel.emojiImageURL(for: emoji) else {
            loadKey = nil
            emojiImageView.image = nil
            return
        }
        let key = url.absoluteString
        loadKey = key
        if let cached = ImageCache.shared.memoryImage(forKey: key) {
            emojiImageView.image = cached
            return
        }
        emojiImageView.image = nil
        ImageCache.shared.loadImage(urlString: key) { [weak self] image in
            guard let self, self.loadKey == key else { return }
            self.emojiImageView.image = image
        }
    }
}


private final class EmojiCategoryStripCell: UICollectionViewCell {
    static let reuseId = "EmojiCategoryStripCell"

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
        imageView.tintColor = UIColor.theme.textStrong
    }

    func configure(categoryKey: String, title: String, isSelected: Bool, symbol: UIImage?, unselectedBackground: UIColor, logoURLString: String?) {
        let t = UIColor.theme
        contentView.backgroundColor = isSelected
            ? t.bgViolet.withAlphaComponent(0.35)
            : unselectedBackground
        let predefined = EmojiCategoryOrdering.predefinedPrefix.contains(categoryKey)
            || EmojiCategoryOrdering.predefinedSuffix.contains(categoryKey)
        if predefined, let symbol {
            logoLoadKey = nil
            imageView.isHidden = false
            initialLabel.isHidden = true
            imageView.contentMode = .scaleAspectFit
            imageView.layer.cornerRadius = 0
            imageView.tintColor = t.textStrong
            imageView.image = symbol
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
            let proxy = ImgproxyURL.create(from: logo, width: 150, height: 150)
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
