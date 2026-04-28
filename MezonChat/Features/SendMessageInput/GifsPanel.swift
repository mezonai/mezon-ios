import UIKit


private struct TenorCategoriesResponse: Decodable {
    let tags: [TenorCategory]?
}

private struct TenorCategory: Decodable {
    let searchterm: String
    let path: String?
    let image: String
    let name: String
}

private struct TenorSearchResponse: Decodable {
    let results: [TenorGif]?
}

private struct TenorGif: Decodable {
    let id: String
    let media_formats: [String: TenorMediaFormat]?

    var tinygifURL: String? { media_formats?["tinygif"]?.url }
    var gifURL: String? { media_formats?["gif"]?.url }
}

private struct TenorMediaFormat: Decodable {
    let url: String
}


private enum GifDisplayMode {
    case categories
    case searchResults
    case loading
}


final class GifsPanel: UIView {

    var onGifSelected: ((String) -> Void)?
    var onSearchFocusChanged: ((Bool) -> Void)?

    var onInnerScroll: ((CGFloat, Bool) -> Void)?

    private weak var cacheEngine: MezonEngine?
    private var categories: [TenorCategory] = []
    private var featuredGifs: [TenorGif] = []
    private var searchResultGifs: [TenorGif] = []
    private var displayMode: GifDisplayMode = .categories

    private var searchDebounceWorkItem: DispatchWorkItem?


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

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = true
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag
        cv.register(GifCategoryCell.self, forCellWithReuseIdentifier: GifCategoryCell.reuseId)
        cv.register(GifItemCell.self, forCellWithReuseIdentifier: GifItemCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.hidesWhenStopped = true
        return v
    }()

    private let emptyStack: UIStackView = {
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = UIImage(systemName: "photo.on.rectangle.angled")
        icon.tintColor = UIColor.mezonLabel.withAlphaComponent(0.2)
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)])
        let label = UILabel()
        label.text = "GIFs will appear here"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.mezonLabel.withAlphaComponent(0.3)
        label.textAlignment = .center
        let sv = UIStackView(arrangedSubviews: [icon, label])
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 12
        return sv
    }()
    
    private let emptyLabel = UILabel()


    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
        searchTextField.addTarget(self, action: #selector(searchEditingDidBegin), for: .editingDidBegin)
        searchTextField.addTarget(self, action: #selector(searchEditingDidEnd), for: .editingDidEnd)
        searchTextField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError() }


    func bindGifCache(engine: MezonEngine) {
        cacheEngine = engine
        reloadFromPostboxCache()
    }

    func reloadFromPostboxCache() {
        guard let engine = cacheEngine else {
            return
        }


        if let cache = engine.data.cachedGifCategoriesJSON() {
            if let resp = try? JSONDecoder().decode(TenorCategoriesResponse.self, from: cache.jsonData) {
                categories = resp.tags ?? []
            }
        }


        if let cache = engine.data.cachedGifFeaturedJSON() {
            if let resp = try? JSONDecoder().decode(TenorSearchResponse.self, from: cache.jsonData) {
                featuredGifs = resp.results ?? []
            }
        }


        if categories.isEmpty && !featuredGifs.isEmpty {
            displayMode = .searchResults
            searchResultGifs = featuredGifs
        } else {
            displayMode = .categories
        }
        if categories.isEmpty && featuredGifs.isEmpty {
            loadInitialDataIfNeeded()
        }
        updateUI()
    }

    func applyTheme() {
        let t = UIColor.theme
        searchBarContainer.backgroundColor = t.primary
        searchIconView.tintColor = t.textDisabled
        searchTextField.textColor = t.textStrong
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Find the perfect GIF",
            attributes: [.foregroundColor: t.textDisabled]
        )
        collectionView.reloadData()
    }


    private func setupLayout() {
        addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIconView)
        searchBarContainer.addSubview(searchTextField)
        addSubview(collectionView)
        addSubview(loadingIndicator)
        addSubview(emptyStack)
        if let label = emptyStack.arrangedSubviews.compactMap({ $0 as? UILabel }).first {
            emptyLabel.font = label.font
            emptyLabel.textColor = label.textColor
            emptyLabel.textAlignment = label.textAlignment
            emptyLabel.numberOfLines = 0
            label.removeFromSuperview()
        } else {
            emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
            emptyLabel.textColor = UIColor.mezonLabel.withAlphaComponent(0.3)
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
        }
        emptyLabel.text = "GIFs will appear here"
        emptyStack.addArrangedSubview(emptyLabel)

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

            collectionView.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 40),

            emptyStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStack.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 40),
        ])
    }

    private func updateUI() {
        if !TenorGIFClient.isConfigured {
            emptyLabel.text = "GIF is not configured (missing TENOR_API_KEY / TENOR_CLIENT_KEY)."
        } else {
            emptyLabel.text = "GIFs will appear here"
        }
        switch displayMode {
        case .loading:
            loadingIndicator.startAnimating()
            collectionView.isHidden = true
            emptyStack.isHidden = true
        case .categories:
            loadingIndicator.stopAnimating()
            let hasData = !categories.isEmpty
            collectionView.isHidden = !hasData
            emptyStack.isHidden = hasData
            collectionView.reloadData()
        case .searchResults:
            loadingIndicator.stopAnimating()
            let hasData = !searchResultGifs.isEmpty
            collectionView.isHidden = !hasData
            emptyStack.isHidden = hasData
            collectionView.reloadData()
        }
    }
    
    private func loadInitialDataIfNeeded() {
        guard TenorGIFClient.isConfigured else { return }
        displayMode = .loading
        updateUI()
        if #available(iOS 13.0, *) {
            Task {
                async let categoriesTask = TenorGIFClient.fetchCategoriesData()
                async let featuredTask = TenorGIFClient.fetchFeaturedData()
                let categoriesData = try? await categoriesTask
                let featuredData = try? await featuredTask
                await MainActor.run {
                    if let categoriesData,
                       let resp = try? JSONDecoder().decode(TenorCategoriesResponse.self, from: categoriesData) {
                        self.categories = resp.tags ?? []
                    }
                    if let featuredData,
                       let resp = try? JSONDecoder().decode(TenorSearchResponse.self, from: featuredData) {
                        self.featuredGifs = resp.results ?? []
                    }
                    if self.categories.isEmpty && !self.featuredGifs.isEmpty {
                        self.searchResultGifs = self.featuredGifs
                        self.displayMode = .searchResults
                    } else {
                        self.displayMode = .categories
                    }
                    self.updateUI()
                }
            }
        }
    }


    private func cellSize(for collectionView: UICollectionView) -> CGSize {
        let inset: CGFloat = 10
        let spacing: CGFloat = 10
        let availW = collectionView.bounds.width - inset * 2 - spacing
        let w = floor(availW / 2)
        let nw = max(w, 60)
        let maxH = max(4, collectionView.bounds.height - inset * 2 - spacing)
        let nh = min(100, maxH)
        return CGSize(width: nw, height: nh)
    }


    @objc private func searchTextChanged() {
        searchDebounceWorkItem?.cancel()
        let text = searchTextField.text ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {

            if categories.isEmpty && !featuredGifs.isEmpty {
                searchResultGifs = featuredGifs
                displayMode = .searchResults
            } else {
                searchResultGifs = []
                displayMode = .categories
            }
            updateUI()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.performSearch(query: trimmed)
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func performSearch(query: String) {
        guard TenorGIFClient.isConfigured else { return }

        displayMode = .loading
        updateUI()

            Task {
                do {
                    let data = try await TenorGIFClient.fetchSearchData(query: query)
                    let resp = try JSONDecoder().decode(TenorSearchResponse.self, from: data)
                    await MainActor.run {
                        self.searchResultGifs = resp.results ?? []
                        self.displayMode = .searchResults
                        self.updateUI()
                    }
                } catch {
                    await MainActor.run {
                        self.searchResultGifs = []
                        self.displayMode = .searchResults
                        self.updateUI()
                }
            }
        }
    }

    private func handleCategoryTap(_ category: TenorCategory) {
        searchTextField.text = category.searchterm
        performSearch(query: category.searchterm)
    }

    @objc private func searchEditingDidBegin() { onSearchFocusChanged?(true) }
    @objc private func searchEditingDidEnd() { onSearchFocusChanged?(false) }
}


extension GifsPanel: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch displayMode {
        case .categories: return categories.count
        case .searchResults: return searchResultGifs.count
        case .loading: return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch displayMode {
        case .categories:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GifCategoryCell.reuseId, for: indexPath) as! GifCategoryCell
            let cat = categories[indexPath.item]
            cell.configure(name: cat.name, imageURL: cat.image)
            return cell
        case .searchResults:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GifItemCell.reuseId, for: indexPath) as! GifItemCell
            let gif = searchResultGifs[indexPath.item]
            cell.configure(imageURL: gif.tinygifURL ?? "")
            return cell
        case .loading:
            return collectionView.dequeueReusableCell(withReuseIdentifier: GifItemCell.reuseId, for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch displayMode {
        case .categories:
            handleCategoryTap(categories[indexPath.item])
        case .searchResults:
            let gif = searchResultGifs[indexPath.item]
            if let url = gif.gifURL {
                onGifSelected?(url)
            }
        case .loading:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        cellSize(for: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 10 }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { 10 }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
}


extension GifsPanel {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onInnerScroll?(scrollView.contentOffset.y, scrollView.isDragging || scrollView.isDecelerating)
    }
}


private final class GifCategoryCell: UICollectionViewCell {
    static let reuseId = "GifCategoryCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        return iv
    }()

    private let overlayView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        return v
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        contentView.addSubview(imageView)
        contentView.addSubview(overlayView)
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, imageURL: String) {
        nameLabel.text = name
        imageView.image = nil
        AnimatedGIFLoader.load(urlString: imageURL, into: imageView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        nameLabel.text = nil
    }
}


private enum AnimatedGIFLoader {

    private static let cache = NSCache<NSString, UIImage>()

    private static var inflight = Set<String>()
    private static let lock = NSLock()


    static func load(urlString: String, into imageView: UIImageView) {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        let key = urlString as NSString


        if let cached = cache.object(forKey: key) {
            imageView.image = cached
            return
        }


        if let data = ImageCache.shared.cachedData(forKey: urlString) {
            decodeAndSet(data: data, key: key, imageView: imageView)
            return
        }

        imageView.image = nil


        lock.lock()
        guard !inflight.contains(urlString) else { lock.unlock(); return }
        inflight.insert(urlString)
        lock.unlock()

        URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
            defer {
                lock.lock()
                inflight.remove(urlString)
                lock.unlock()
            }
            guard let data, !data.isEmpty else { return }

            ImageCache.shared.setImage(UIImage(), data: data, forKey: urlString)
            DispatchQueue.main.async {
                guard let imageView else { return }
                decodeAndSet(data: data, key: key, imageView: imageView)
            }
        }.resume()
    }

    private static func decodeAndSet(data: Data, key: NSString, imageView: UIImageView) {
        DispatchQueue.global(qos: .userInitiated).async {
            let animated = createAnimatedImage(from: data)
            if let animated {
                cache.setObject(animated, forKey: key)
            }
            DispatchQueue.main.async {
                imageView.image = animated
            }
        }
    }


    private static func createAnimatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {

            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {

            return UIImage(data: data)
        }

        var images: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))


            let frameDuration = gifFrameDuration(at: i, source: source)
            totalDuration += frameDuration
        }

        guard !images.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: images, duration: totalDuration)
    }

    private static func gifFrameDuration(at index: Int, source: CGImageSource) -> Double {
        var delay = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return delay
        }
        if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            delay = unclamped
        } else if let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
            delay = clamped
        }

        if delay < 0.04 { delay = 0.04 }
        return delay
    }
}


private final class GifItemCell: UICollectionViewCell {
    static let reuseId = "GifItemCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        iv.backgroundColor = UIColor.mezonLabel.withAlphaComponent(0.05)
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true

        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(imageURL: String) {
        imageView.image = nil
        AnimatedGIFLoader.load(urlString: imageURL, into: imageView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
}
