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
        collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .left, animated: animated)
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
    private let avatarView = UIImageView()
    private let initialsLabel = UILabel()
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

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 10.swh

        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        initialsLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        initialsLabel.textAlignment = .center
        initialsLabel.isHidden = true

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        nameLabel.numberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10.sf)
        subtitleLabel.numberOfLines = 1

        contentView.addSubview(card)
        card.addSubview(avatarView)
        avatarView.addSubview(initialsLabel)
        card.addSubview(nameLabel)
        card.addSubview(subtitleLabel)

        let avSize: CGFloat = 36.swh
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            avatarView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8.sw),
            avatarView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: avSize),
            avatarView.heightAnchor.constraint(equalToConstant: avSize),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8.sw),
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
        avatarView.image = nil
        initialsLabel.isHidden = true
    }

    func applyTheme() {
        let t = UIColor.theme
        card.backgroundColor = t.tertiary
        nameLabel.textColor = t.textStrong
        subtitleLabel.textColor = t.textDisabled
        initialsLabel.textColor = t.textStrong
        avatarView.backgroundColor = t.colorActiveClan.withAlphaComponent(0.3)
    }

    func configure(item: DmMessageActivityItem) {
        applyTheme()
        nameLabel.text = item.resolvedDisplayName
        subtitleLabel.text = item.activitySubtitle

        let raw = item.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, let url = URL(string: raw) {
            initialsLabel.isHidden = true
            avatarView.backgroundColor = .clear
            loadAvatar(url: url)
        } else {
            avatarLoadGeneration += 1
            imageTask?.cancel()
            imageTask = nil
            avatarView.image = nil
            avatarView.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
            initialsLabel.isHidden = false
            initialsLabel.text = String(item.resolvedDisplayName.prefix(1)).uppercased()
        }
    }

    private func loadAvatar(url: URL) {
        imageTask?.cancel()
        imageTask = nil
        avatarLoadGeneration += 1
        let gen = avatarLoadGeneration
        let proxied = ImgproxyURL.avatarProxyURL(from: url.absoluteString, width: 100, height: 100)
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            guard gen == avatarLoadGeneration else { return }
            avatarView.image = cached
            return
        }
        imageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self, gen == self.avatarLoadGeneration else { return }
            if let image {
                self.initialsLabel.isHidden = true
                self.avatarView.image = image
            } else {
                self.avatarView.image = nil
                self.avatarView.backgroundColor = UIColor.theme.colorActiveClan.withAlphaComponent(0.3)
                self.initialsLabel.isHidden = false
                self.initialsLabel.text = String((self.nameLabel.text ?? "U").prefix(1)).uppercased()
            }
        }
    }
}
