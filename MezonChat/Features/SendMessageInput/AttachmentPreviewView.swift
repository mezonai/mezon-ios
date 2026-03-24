import UIKit

final class AttachmentPreviewView: UIView {

    var onRemove: ((Int) -> Void)?

    private(set) var images: [UIImage] = []
    private(set) var videoIndices: Set<Int> = []

    static let previewHeight: CGFloat = 110

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 14.sw
        layout.minimumLineSpacing = 14.sw
        layout.sectionInset = UIEdgeInsets(top: 10.sh, left: 8.sw, bottom: 10.sh, right: 20.sw)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(collectionView)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AttachmentThumbCell.self, forCellWithReuseIdentifier: AttachmentThumbCell.reuseId)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        collectionView.reloadData()
    }

    func forceReload() {
        collectionView.reloadData()
    }

    func addImage(_ image: UIImage) {
        images.append(image)
        collectionView.reloadData()
    }

    func addVideo(thumbnail: UIImage) {
        let index = images.count
        images.append(thumbnail)
        videoIndices.insert(index)
        collectionView.reloadData()
    }

    func markAsVideo(at index: Int) {
        videoIndices.insert(index)
        collectionView.reloadData()
    }

    func removeImage(at index: Int) {
        guard index >= 0, index < images.count else { return }
        images.remove(at: index)
        // Re-index video indices
        var newIndices: Set<Int> = []
        for vi in videoIndices where vi != index {
            newIndices.insert(vi > index ? vi - 1 : vi)
        }
        videoIndices = newIndices
        collectionView.reloadData()
    }

    func removeAll() {
        images.removeAll()
        videoIndices.removeAll()
        collectionView.reloadData()
    }

    func setImages(_ newImages: [UIImage]) {
        images = newImages
        videoIndices.removeAll()
        collectionView.reloadData()
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension AttachmentPreviewView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        images.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentThumbCell.reuseId, for: indexPath) as! AttachmentThumbCell
        let isVideo = videoIndices.contains(indexPath.item)
        cell.configure(image: images[indexPath.item], isVideo: isVideo)
        cell.onClose = { [weak self] in
            self?.onRemove?(indexPath.item)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let thumbH: CGFloat = 80.sh
        let thumbW: CGFloat = 70.sw
        return CGSize(width: thumbW, height: thumbH)
    }
}

// MARK: - AttachmentThumbCell

private final class AttachmentThumbCell: UICollectionViewCell {

    static let reuseId = "AttachmentThumbCell"

    var onClose: (() -> Void)?

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 6
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let playOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        v.isHidden = true

        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let playIcon = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: config))
        playIcon.tintColor = .white
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: v.centerXAnchor, constant: 1),
            playIcon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    private lazy var closeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.gray
        btn.layer.cornerRadius = 12
        btn.layer.borderWidth = 2
        btn.layer.borderColor = UIColor.theme.secondary.cgColor
        btn.clipsToBounds = true
        btn.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = false
        clipsToBounds = false

        contentView.addSubview(thumbImageView)
        contentView.addSubview(playOverlay)
        contentView.addSubview(closeButton)

        let closeSize: CGFloat = 24
        let playSize: CGFloat = 32

        NSLayoutConstraint.activate([
            thumbImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            thumbImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: closeSize / 2),

            playOverlay.centerXAnchor.constraint(equalTo: thumbImageView.centerXAnchor),
            playOverlay.centerYAnchor.constraint(equalTo: thumbImageView.centerYAnchor),
            playOverlay.widthAnchor.constraint(equalToConstant: playSize),
            playOverlay.heightAnchor.constraint(equalToConstant: playSize),

            closeButton.widthAnchor.constraint(equalToConstant: closeSize),
            closeButton.heightAnchor.constraint(equalToConstant: closeSize),
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: closeSize / 2 - 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(image: UIImage, isVideo: Bool = false) {
        thumbImageView.image = image
        playOverlay.isHidden = !isVideo
    }
}
