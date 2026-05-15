import UIKit

struct DmMessageActivityItem: Equatable {
    let userId: Int64
    let displayName: String
    let username: String
    let avatarURL: String
    let activitySubtitle: String

    var resolvedDisplayName: String {
        let d = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { return d }
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? "User" : u
    }
}

final class DmMessageActivityStripView: UIView {

    var onSelect: ((DmMessageActivityItem) -> Void)?

    private var items: [DmMessageActivityItem] = []
    private weak var stripWindow: UIWindow?

    private lazy var flow: UICollectionViewFlowLayout = {
        let f = UICollectionViewFlowLayout()
        f.scrollDirection = .horizontal
        f.minimumLineSpacing = 10.sw
        f.minimumInteritemSpacing = 0
        f.sectionInset = UIEdgeInsets(top: 0, left: 18.sw, bottom: 0, right: 18.sw)
        f.itemSize = CGSize(width: 220.sw, height: 50.sh)
        return f
    }()

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: flow)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        cv.delaysContentTouches = false
        cv.register(DmMessageActivityCell.self, forCellWithReuseIdentifier: DmMessageActivityCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stripWindow = nil
            return
        }
        if stripWindow == nil {
            resetScrollToStart(animated: false)
        }
        stripWindow = window
    }

    func resetScrollToStart(animated: Bool) {
        guard !items.isEmpty, collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) > 0 else { return }
        collectionView.layoutIfNeeded()
        let top = -collectionView.adjustedContentInset.top
        let left = -collectionView.adjustedContentInset.left
        collectionView.setContentOffset(CGPoint(x: left, y: top), animated: animated)
    }

    func setItems(_ rows: [DmMessageActivityItem]) {
        if rows == items { return }
        items = rows
        collectionView.reloadData()
        isHidden = items.isEmpty
    }

    func applyTheme() {
        collectionView.visibleCells.forEach { ($0 as? DmMessageActivityCell)?.applyTheme() }
        collectionView.reloadData()
    }
}

extension DmMessageActivityStripView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DmMessageActivityCell.reuseId, for: indexPath) as! DmMessageActivityCell
        cell.configure(item: items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(items[indexPath.item])
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}

private final class DmMessageActivityCell: UICollectionViewCell {

    static let reuseId = "DmMessageActivityCell"

    private let card = UIView()
    private let textAvatar = TextAvatarView(username: "", size: 36.swh, fontSize: 14.sf)
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var imageTask: URLSessionDataTask?
    private var avatarLoadGeneration: UInt = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 12.swh
        card.clipsToBounds = true

        textAvatar.translatesAutoresizingMaskIntoConstraints = false

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 10.swh

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        nameLabel.numberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10.sf)
        subtitleLabel.numberOfLines = 1

        contentView.addSubview(card)
        card.addSubview(textAvatar)
        textAvatar.addSubview(avatarImageView)
        card.addSubview(nameLabel)
        card.addSubview(subtitleLabel)

        let avSize: CGFloat = 36.swh
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textAvatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8.sw),
            textAvatar.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textAvatar.widthAnchor.constraint(equalToConstant: avSize),
            textAvatar.heightAnchor.constraint(equalToConstant: avSize),

            avatarImageView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: textAvatar.trailingAnchor, constant: 8.sw),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10.sw),
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 8.sh),

            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6.sh),
        ])

        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadGeneration += 1
        imageTask?.cancel()
        imageTask = nil
        avatarImageView.image = nil
    }

    func applyTheme() {
        let t = UIColor.theme
        card.backgroundColor = t.tertiary
        nameLabel.textColor = t.textStrong
        subtitleLabel.textColor = t.textDisabled
    }

    func configure(item: DmMessageActivityItem) {
        applyTheme()
        nameLabel.text = item.resolvedDisplayName
        subtitleLabel.text = item.activitySubtitle

        let raw = item.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL: URL? = {
            guard !raw.isEmpty else { return nil }
            if let u = URL(string: raw) { return u }
            if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let u = URL(string: encoded) { return u }
            return nil
        }()
        textAvatar.configure(username: item.username, fontSize: 14.sf)
        if let url = resolvedURL {
            loadAvatar(url: url, fallbackUsername: item.username)
        } else {
            avatarLoadGeneration += 1
            imageTask?.cancel()
            imageTask = nil
            avatarImageView.image = nil
        }
    }

    private func loadAvatar(url: URL, fallbackUsername: String) {
        imageTask?.cancel()
        imageTask = nil
        avatarLoadGeneration += 1
        let gen = avatarLoadGeneration
        let proxied = ImgproxyURL.avatarProxyURL(from: url.absoluteString, width: 100, height: 100)
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            guard gen == avatarLoadGeneration else { return }
            avatarImageView.image = cached
            textAvatar.showImageMode()
            return
        }
        imageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self, gen == self.avatarLoadGeneration else { return }
            if let image {
                self.avatarImageView.image = image
                self.textAvatar.showImageMode()
            } else {
                self.avatarImageView.image = nil
                self.textAvatar.configure(username: fallbackUsername, fontSize: 14.sf)
            }
        }
    }
}
