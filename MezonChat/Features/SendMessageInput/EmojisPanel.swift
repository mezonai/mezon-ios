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


private enum EmojiGridItem {
    case header(key: String, title: String, collapsed: Bool)
    case emoji(CachedClanEmojiRecord)
    case emptyPad
}


final class EmojisPanel: UIView {

    var onEmojiSelected: ((String, String) -> Void)?
    var onSearchFocusChanged: ((Bool) -> Void)?

    var onInnerScroll: ((CGFloat, Bool) -> Void)?

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
        cv.register(EmojiCategoryStripCell.self, forCellWithReuseIdentifier: EmojiCategoryStripCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        cv.tag = 1
        return cv
    }()


    private lazy var emojiGrid: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = true
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag
        cv.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseId)
        cv.register(EmojiSectionHeaderCell.self, forCellWithReuseIdentifier: EmojiSectionHeaderCell.reuseId)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "pad")
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self
        cv.tag = 2
        return cv
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


    func bindEmojiCache(engine: MezonEngine) {
        cacheEngine = engine
        reloadFromPostboxCache()
    }

    func reloadFromPostboxCache() {
        let cache = cacheEngine?.data.cachedEmojiList(clanId: 0)
        let emojis = cache?.emojis ?? []
        ingestEmojis(emojis)
    }

    func applyTheme() {
        let t = UIColor.theme
        searchBarContainer.backgroundColor = t.primary
        searchIconView.tintColor = t.textDisabled
        searchTextField.textColor = t.textStrong
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Find the perfect emoji",
            attributes: [.foregroundColor: t.textDisabled]
        )
        categoryCollection.reloadData()
        emojiGrid.reloadData()
    }


    private func setupLayout() {
        addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIconView)
        searchBarContainer.addSubview(searchTextField)
        addSubview(categoryCollection)
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

            emojiGrid.topAnchor.constraint(equalTo: categoryCollection.bottomAnchor, constant: 4),
            emojiGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            emojiGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            emojiGrid.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }


    private func emojiCellWidth() -> CGFloat {
        let inset: CGFloat = 8
        let availW = emojiGrid.bounds.width - inset * 2
        guard availW > 0 else { return 36 }
        return floor(availW / CGFloat(emojiColumns))
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

    @objc private func toggleSectionHeader(_ gesture: UITapGestureRecognizer) {
        guard let key = gesture.view?.accessibilityIdentifier, !key.isEmpty else { return }
        if collapsedCategories.contains(key) {
            collapsedCategories.remove(key)
        } else {
            collapsedCategories.insert(key)
        }
        rebuildFlatItems()
        emojiGrid.reloadData()
    }


    private static let imageCache = NSCache<NSString, UIImage>()
    private static let resizedCache = NSCache<NSString, UIImage>()
    private static let decodeQueue = DispatchQueue(label: "emoji.decode", qos: .userInitiated, attributes: .concurrent)

    fileprivate static func emojiImageURL(for emoji: CachedClanEmojiRecord) -> URL? {
        if let url = URL(string: emoji.src), url.scheme != nil { return url }
        return MezonConfig.emojiResourceURL(emojiId: "\(emoji.id)", imgproxyFitSide: 32)
    }


    private static func decodeEmojiImage(from data: Data) -> UIImage? {
        UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
    }

    fileprivate func loadEmojiImage(for emoji: CachedClanEmojiRecord, into imageView: UIImageView) {
        guard let url = Self.emojiImageURL(for: emoji) else { return }
        let key = url.absoluteString as NSString


        if let resized = Self.resizedCache.object(forKey: key) {
            imageView.image = resized
            return
        }

        if let raw = Self.imageCache.object(forKey: key) {
            Self.decodeQueue.async { [weak imageView] in
                let resized = Self.resizeImage(raw, to: CGSize(width: 32, height: 32))
                Self.resizedCache.setObject(resized, forKey: key)
                DispatchQueue.main.async { imageView?.image = resized }
            }
            return
        }

        imageView.image = nil
        URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
            guard let data, !data.isEmpty, let img = Self.decodeEmojiImage(from: data) else { return }
            Self.imageCache.setObject(img, forKey: key)
            Self.decodeQueue.async {
                let resized = Self.resizeImage(img, to: CGSize(width: 32, height: 32))
                Self.resizedCache.setObject(resized, forKey: key)
                DispatchQueue.main.async { imageView?.image = resized }
            }
        }.resume()
    }

    private static func resizeImage(_ img: UIImage, to size: CGSize) -> UIImage {
        if let frames = img.images, frames.count > 1 {
            let scaled = frames.map { resizeStaticImage($0, to: size) }
            let duration = img.duration > 0 ? img.duration : Double(frames.count) * 0.06
            return UIImage.animatedImage(with: scaled, duration: duration) ?? resizeStaticImage(img, to: size)
        }
        return resizeStaticImage(img, to: size)
    }

    private static func resizeStaticImage(_ img: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }

    fileprivate func handleEmojiTap(_ emoji: CachedClanEmojiRecord) {
        if emoji.isForSale && emoji.src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        onEmojiSelected?("\(emoji.id)", emoji.shortname)
    }
}


extension EmojisPanel: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView.tag == 1 { return categoryStripCategories.count }
        return flatItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        if collectionView.tag == 1 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCategoryStripCell.reuseId, for: indexPath) as! EmojiCategoryStripCell
            let key = categoryStripCategories[indexPath.item]
            cell.configure(categoryKey: key, title: displayTitle(for: key), isSelected: key == selectedStripCategory, symbol: Self.stripSymbol(for: key))
            return cell
        }

        let item = flatItems[indexPath.item]
        switch item {
        case .header(let key, let title, let collapsed):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiSectionHeaderCell.reuseId, for: indexPath) as! EmojiSectionHeaderCell
            cell.configure(key: key, title: title, collapsed: collapsed) { [weak self] headerKey in
                self?.toggleSectionHeaderByKey(headerKey)
            }
            return cell
        case .emoji(let emoji):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseId, for: indexPath) as! EmojiCell
            cell.configure(emoji: emoji, panel: self)
            return cell
        case .emptyPad:
            return collectionView.dequeueReusableCell(withReuseIdentifier: "pad", for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.tag == 1 {
            let key = categoryStripCategories[indexPath.item]
            selectCategoryFromStrip(key)
            return
        }
        if case .emoji(let emoji) = flatItems[indexPath.item] {
            handleEmojiTap(emoji)
        }
    }


    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView.tag == 2 else { return }
        for ip in indexPaths {
            guard ip.item < flatItems.count, case .emoji(let emoji) = flatItems[ip.item] else { continue }
            guard let url = Self.emojiImageURL(for: emoji) else { continue }
            let key = url.absoluteString as NSString
            guard Self.imageCache.object(forKey: key) == nil else { continue }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = Self.decodeEmojiImage(from: data) else { return }
                Self.imageCache.setObject(img, forKey: key)
            }.resume()
        }
    }

    private func toggleSectionHeaderByKey(_ key: String) {
        if collapsedCategories.contains(key) {
            collapsedCategories.remove(key)
        } else {
            collapsedCategories.insert(key)
        }
        rebuildFlatItems()
        emojiGrid.reloadData()
    }
}


extension EmojisPanel: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

        if collectionView.tag == 1 {
            return CGSize(width: 40, height: 40)
        }

        guard indexPath.item < flatItems.count else { return .zero }
        let item = flatItems[indexPath.item]
        switch item {
        case .header:

            let w = collectionView.bounds.width - 16
            return CGSize(width: w, height: 36)
        case .emoji:
            let cellW = emojiCellWidth()
            return CGSize(width: cellW, height: 44)
        case .emptyPad:
            let cellW = emojiCellWidth()
            return CGSize(width: cellW, height: 44)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if collectionView.tag == 1 {
            return UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        }
        return UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == 1 { return 8 }
        return 0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == 1 { return 8 }
        return 0
    }
}


extension EmojisPanel {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.tag == 2 else { return }
        onInnerScroll?(scrollView.contentOffset.y, scrollView.isDragging || scrollView.isDecelerating)
    }
}


extension EmojisPanel {
    fileprivate static func stripSymbol(for key: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        switch key {
        case EmojiCategoryOrdering.recent: return UIImage(systemName: "clock", withConfiguration: config)
        case EmojiCategoryOrdering.forSale: return UIImage(systemName: "bag.fill", withConfiguration: config)
        case EmojiCategoryOrdering.frequently: return UIImage(systemName: "star.fill", withConfiguration: config)
        case "People": return UIImage(systemName: "face.smiling", withConfiguration: config)
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


private final class EmojiCell: UICollectionViewCell {
    static let reuseId = "EmojiCell"

    private let emojiImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        return iv
    }()

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

    func configure(emoji: CachedClanEmojiRecord, panel: EmojisPanel) {
        emojiImageView.image = nil
        if emoji.isForSale && emoji.src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentView.alpha = 0.45
        } else {
            contentView.alpha = 1
        }
        panel.loadEmojiImage(for: emoji, into: emojiImageView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        emojiImageView.image = nil
        contentView.alpha = 1
    }


}


private final class EmojiCategoryStripCell: UICollectionViewCell {
    static let reuseId = "EmojiCategoryStripCell"

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

    func configure(categoryKey: String, title: String, isSelected: Bool, symbol: UIImage?) {
        let predefined = EmojiCategoryOrdering.predefinedPrefix.contains(categoryKey)
            || EmojiCategoryOrdering.predefinedSuffix.contains(categoryKey)
        if predefined, let symbol {
            imageView.isHidden = false
            initialLabel.isHidden = true
            imageView.image = symbol
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
