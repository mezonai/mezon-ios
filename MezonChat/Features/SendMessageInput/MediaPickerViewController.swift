import UIKit
import Photos
import AVFoundation

struct MediaPickerResult {
    let image: UIImage
    let fileURL: URL?
    let isVideo: Bool
}

final class MediaPickerViewController: UIViewController {

    var onPicked: (([MediaPickerResult]) -> Void)?
    var onEditedSend: ((MediaPickerResult) -> Void)?
    var selectionLimit: Int = .max

    private static let maxUploadImageDimension: CGFloat = 2048

    private let cachingImageManager = PHCachingImageManager()
    private var fetchResult: PHFetchResult<PHAsset>?
    private var selectedAssets: [PHAsset] = []
    private var selectedOrder: [String: Int] = [:]

    private let thumbnailSize: CGSize = {
        let scale = UIScreen.main.scale
        let side: CGFloat = 110
        return CGSize(width: side * scale, height: side * scale)
    }()

    private var previousPreheatRect: CGRect = .zero

    private var albums: [(collection: PHAssetCollection?, title: String, count: Int, thumbnail: UIImage?)] = []
    private var selectedAlbumIndex: Int = 0

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.allowsSelection = false
        cv.alwaysBounceVertical = true
        cv.register(MediaPickerCell.self, forCellWithReuseIdentifier: MediaPickerCell.reuseId)
        cv.register(CameraPreviewCell.self, forCellWithReuseIdentifier: CameraPreviewCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    private lazy var headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var dragIndicator: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.mezonLabel.withAlphaComponent(0.3)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private lazy var titleButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.title = "Recent Photos"
            config.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
            config.imagePlacement = .trailing
            config.imagePadding = 4
            config.baseForegroundColor = UIColor.theme.textStrong
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
                return outgoing
            }
            btn.configuration = config
        } else {
            btn.setTitle("Recent Photos", for: .normal)
            btn.setImage(UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)), for: .normal)
            btn.semanticContentAttribute = .forceRightToLeft
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            btn.setTitleColor(UIColor.theme.textStrong, for: .normal)
            btn.tintColor = UIColor.theme.textStrong
        }
        btn.addTarget(self, action: #selector(toggleAlbumDropdownAction), for: .touchUpInside)
        return btn
    }()

    private lazy var albumDropdownView: AlbumDropdownView = {
        let v = AlbumDropdownView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onSelect = { [weak self] index in
            self?.selectAlbum(at: index)
        }
        return v
    }()

    private lazy var dropdownOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        v.isHidden = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissDropdown))
        v.addGestureRecognizer(tap)
        return v
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        btn.layer.cornerRadius = 12
        btn.addTarget(self, action: #selector(confirmSelectionAction), for: .touchUpInside)
        return btn
    }()

    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(isVietnamese ? "Chỉnh sửa" : "Edit", for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 12
        btn.addTarget(self, action: #selector(editSelectionAction), for: .touchUpInside)
        btn.isHidden = true
        return btn
    }()

    private lazy var actionBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        view.isHidden = true
        return view
    }()

    private lazy var cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Cancel", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        btn.tintColor = UIColor.theme.textStrong
        btn.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var permissionDeniedView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 44, weight: .thin)
        let iconView = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled", withConfiguration: iconConfig))
        iconView.tintColor = UIColor.white.withAlphaComponent(0.3)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "No Photo Access"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center

        let descLabel = UILabel()
        descLabel.text = "Please allow access to your photos\nto select and send media."
        descLabel.font = .systemFont(ofSize: 14, weight: .regular)
        descLabel.textColor = UIColor.theme.textDisabled
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0

        let settingsBtn = UIButton(type: .system)
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = "Go to Settings"
            config.baseBackgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
            config.baseForegroundColor = .white
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 24, bottom: 10, trailing: 24)
            settingsBtn.configuration = config
        } else {
            settingsBtn.setTitle("Go to Settings", for: .normal)
            settingsBtn.setTitleColor(.white, for: .normal)
            settingsBtn.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
            settingsBtn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
            settingsBtn.layer.cornerRadius = 20
        }
        settingsBtn.addTarget(self, action: #selector(openSettingsAction), for: .touchUpInside)

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(descLabel)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(settingsBtn)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
        ])

        return container
    }()

    private lazy var limitedBanner: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.theme.primary
        v.isHidden = true

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "You have limited Mezon from accessing your photos."
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = UIColor.theme.textDisabled
        label.numberOfLines = 2

        let manageBtn = UIButton(type: .system)
        manageBtn.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = "MANAGE"
            config.baseBackgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
            config.baseForegroundColor = .white
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = UIFont.systemFont(ofSize: 12, weight: .bold)
                return out
            }
            manageBtn.configuration = config
        } else {
            manageBtn.setTitle("MANAGE", for: .normal)
            manageBtn.setTitleColor(.white, for: .normal)
            manageBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
            manageBtn.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
            manageBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            manageBtn.layer.cornerRadius = 14
        }
        manageBtn.addTarget(self, action: #selector(manageLimitedAccessAction), for: .touchUpInside)

        manageBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        manageBtn.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        v.addSubview(label)
        v.addSubview(manageBtn)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: manageBtn.leadingAnchor, constant: -8),

            manageBtn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
            manageBtn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        return v
    }()

    private var limitedBannerHeightConstraint: NSLayoutConstraint?

    private var didSendResults = false
    private var isPresentingEditor = false
    private var sendLeadingEditConstraint: NSLayoutConstraint?
    private var sendLeadingBarConstraint: NSLayoutConstraint?

    private var isVietnamese: Bool {
        LanguageManager.shared.current == .vietnamese
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.secondary
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true

        setupUI()
        checkPermissionAndLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCachedAssets()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCameraCell()
        if !isPresentingEditor {
            sendResultsIfNeeded()
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        cachingImageManager.stopCachingImagesForAllAssets()
    }


    private func sendResultsIfNeeded() {
        guard !didSendResults, !selectedAssets.isEmpty else { return }
        didSendResults = true
        confirmSelection(shouldDismiss: false)
    }

    private func stopCameraCell() {
        guard let cell = collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? CameraPreviewCell else { return }
        cell.stopSession()
    }

    private func setupUI() {
        view.addSubview(headerView)
        headerView.addSubview(dragIndicator)
        headerView.addSubview(titleButton)
        headerView.addSubview(cancelButton)
        view.addSubview(limitedBanner)
        view.addSubview(collectionView)
        view.addSubview(actionBar)
        actionBar.addSubview(editButton)
        actionBar.addSubview(sendButton)
        view.addSubview(dropdownOverlay)
        view.addSubview(albumDropdownView)

        let headerHeight: CGFloat = 52
        let bannerHeight = limitedBanner.heightAnchor.constraint(equalToConstant: 0)
        self.limitedBannerHeightConstraint = bannerHeight

        let editWidth = editButton.widthAnchor.constraint(equalTo: sendButton.widthAnchor, multiplier: 1.0 / 3.0)
        let sendLeadingEdit = sendButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 10)
        let sendLeadingBar = sendButton.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 16)
        sendLeadingEditConstraint = sendLeadingEdit
        sendLeadingBarConstraint = sendLeadingBar

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            dragIndicator.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            dragIndicator.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            dragIndicator.widthAnchor.constraint(equalToConstant: 36),
            dragIndicator.heightAnchor.constraint(equalToConstant: 5),

            cancelButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor, constant: 4),

            titleButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor, constant: 4),

            limitedBanner.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            limitedBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            limitedBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerHeight,

            collectionView.topAnchor.constraint(equalTo: limitedBanner.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 72),

            editButton.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 16),
            editButton.topAnchor.constraint(equalTo: actionBar.topAnchor, constant: 10),
            editButton.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: -10),
            editWidth,

            sendLeadingEdit,
            sendButton.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -16),
            sendButton.topAnchor.constraint(equalTo: actionBar.topAnchor, constant: 10),
            sendButton.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: -10),

            dropdownOverlay.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            dropdownOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dropdownOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dropdownOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            albumDropdownView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            albumDropdownView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            albumDropdownView.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    private func checkPermissionAndLoad() {
        if #available(iOS 14.0, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch status {
            case .authorized:
                loadAssets()
            case .limited:
                showLimitedBanner()
                loadAssets()
                PHPhotoLibrary.shared().register(self)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                    DispatchQueue.main.async {
                        switch newStatus {
                        case .authorized:
                            self?.loadAssets()
                        case .limited:
                            self?.showLimitedBanner()
                            self?.loadAssets()
                            if let self { PHPhotoLibrary.shared().register(self) }
                        default:
                            self?.showPermissionDenied()
                        }
                    }
                }
            case .denied, .restricted:
                showPermissionDenied()
            @unknown default:
                showPermissionDenied()
            }
            return
        }
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            loadAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self?.loadAssets()
                    } else {
                        self?.showPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            showPermissionDenied()
        }
    }

    private func showLimitedBanner() {
        limitedBanner.isHidden = false
        limitedBannerHeightConstraint?.constant = 44
        view.layoutIfNeeded()
    }

    private func manageLimitedAccess() {
        guard #available(iOS 14.0, *) else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Select More Photos...", style: .default) { [weak self] _ in
            guard let self else { return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
        })

        sheet.addAction(UIAlertAction(title: "Change Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = limitedBanner
            popover.sourceRect = limitedBanner.bounds
        }

        present(sheet, animated: true)
    }

    private func showPermissionDenied() {
        titleButton.isHidden = true
        collectionView.isHidden = true

        view.addSubview(permissionDeniedView)
        NSLayoutConstraint.activate([
            permissionDeniedView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            permissionDeniedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            permissionDeniedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            permissionDeniedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        permissionDeniedView.isHidden = false
    }

    private func loadAssets() {
        loadAlbums()
        loadAssetsForCurrentAlbum()
    }

    private func loadAssetsForCurrentAlbum() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue,
                                        PHAssetMediaType.video.rawValue)

        if let collection = albums[safe: selectedAlbumIndex]?.collection {
            fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            fetchResult = PHAsset.fetchAssets(with: options)
        }

        cachingImageManager.stopCachingImagesForAllAssets()
        previousPreheatRect = .zero
        collectionView.reloadData()
        if (fetchResult?.count ?? 0) > 0 {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        }
    }

    private func loadAlbums() {
        albums.removeAll()

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                              PHAssetMediaType.image.rawValue,
                                              PHAssetMediaType.video.rawValue)
        let allCount = PHAsset.fetchAssets(with: fetchOptions).count
        albums.append((collection: nil, title: "Recent Photos", count: allCount, thumbnail: nil))

        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        let wantedSubtypes: Set<PHAssetCollectionSubtype> = [
            .smartAlbumFavorites, .smartAlbumScreenshots, .smartAlbumSelfPortraits,
            .smartAlbumPanoramas, .smartAlbumVideos, .smartAlbumLivePhotos,
        ]
        smartAlbums.enumerateObjects { collection, _, _ in
            guard wantedSubtypes.contains(collection.assetCollectionSubtype) else { return }
            let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
            guard count > 0 else { return }
            self.albums.append((collection: collection, title: collection.localizedTitle ?? "Album", count: count, thumbnail: nil))
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
            guard count > 0 else { return }
            self.albums.append((collection: collection, title: collection.localizedTitle ?? "Album", count: count, thumbnail: nil))
        }

        let thumbSize = CGSize(width: 48, height: 48)
        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = .fastFormat
        thumbOptions.resizeMode = .fast
        thumbOptions.isSynchronous = true

        for i in 0..<albums.count {
            let assetFetch: PHFetchResult<PHAsset>
            if let col = albums[i].collection {
                assetFetch = PHAsset.fetchAssets(in: col, options: fetchOptions)
            } else {
                assetFetch = PHAsset.fetchAssets(with: fetchOptions)
            }
            guard let firstAsset = assetFetch.firstObject else { continue }
            cachingImageManager.requestImage(for: firstAsset, targetSize: thumbSize, contentMode: .aspectFill, options: thumbOptions) { image, _ in
                self.albums[i].thumbnail = image
            }
        }
    }

    private func toggleAlbumDropdown() {
        if albumDropdownView.isHidden {
            showDropdown()
        } else {
            hideDropdown()
        }
    }

    private func showDropdown() {
        albumDropdownView.configure(albums: albums, selectedIndex: selectedAlbumIndex)
        dropdownOverlay.isHidden = false
        albumDropdownView.isHidden = false
        albumDropdownView.alpha = 0
        albumDropdownView.transform = CGAffineTransform(translationX: 0, y: -8)
        UIView.animate(withDuration: 0.2) {
            self.albumDropdownView.alpha = 1
            self.albumDropdownView.transform = .identity
        }
        let upImg = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        UIView.animate(withDuration: 0.2) {
            if #available(iOS 15.0, *) {
                self.titleButton.configuration?.image = upImg
            } else {
                self.titleButton.setImage(upImg, for: .normal)
            }
        }
    }

    private func hideDropdown() {
        UIView.animate(withDuration: 0.15, animations: {
            self.albumDropdownView.alpha = 0
            self.albumDropdownView.transform = CGAffineTransform(translationX: 0, y: -8)
        }, completion: { _ in
            self.albumDropdownView.isHidden = true
            self.dropdownOverlay.isHidden = true
            self.albumDropdownView.transform = .identity
        })
        let downImg = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        UIView.animate(withDuration: 0.2) {
            if #available(iOS 15.0, *) {
                self.titleButton.configuration?.image = downImg
            } else {
                self.titleButton.setImage(downImg, for: .normal)
            }
        }
    }

    @objc private func dismissDropdown() {
        hideDropdown()
    }

    @objc private func toggleAlbumDropdownAction() {
        toggleAlbumDropdown()
    }

    @objc private func confirmSelectionAction() {
        confirmSelection()
    }

    @objc private func editSelectionAction() {
        guard selectedAssets.count == 1,
              let asset = selectedAssets.first,
              asset.mediaType == .image else { return }

        editButton.isEnabled = false
        sendButton.isEnabled = false
        exportImage(asset: asset) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.editButton.isEnabled = true
                self.sendButton.isEnabled = true
                guard let result else { return }

                self.isPresentingEditor = true
                let editor = ImageEditorViewController(result: result)
                editor.onCancel = { [weak self] in
                    self?.isPresentingEditor = false
                }
                editor.onSend = { [weak self, weak editor] edited in
                    guard let self else { return }
                    self.didSendResults = true
                    self.onEditedSend?(edited)
                    editor?.dismiss(animated: true) { [weak self] in
                        self?.dismiss(animated: true)
                    }
                }
                editor.modalPresentationStyle = .fullScreen
                self.present(editor, animated: true)
            }
        }
    }

    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func openSettingsAction() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func manageLimitedAccessAction() {
        manageLimitedAccess()
    }

    private func selectAlbum(at index: Int) {
        guard index != selectedAlbumIndex else {
            hideDropdown()
            return
        }
        selectedAlbumIndex = index
        if #available(iOS 15.0, *) {
            titleButton.configuration?.title = albums[index].title
        } else {
            titleButton.setTitle(albums[index].title, for: .normal)
        }
        hideDropdown()
        loadAssetsForCurrentAlbum()
    }

    private func updateCachedAssets() {
        guard isViewLoaded, view.window != nil, let fetchResult else { return }

        let visibleRect = collectionView.bounds
        let preheatRect = visibleRect.insetBy(dx: 0, dy: -0.5 * visibleRect.height)

        let delta = abs(preheatRect.midY - previousPreheatRect.midY)
        guard delta > visibleRect.height / 3.0 else { return }

        let (addedRects, removedRects) = differencesBetween(old: previousPreheatRect, new: preheatRect)
        previousPreheatRect = preheatRect

        let addedAssets = assetsInRects(addedRects, fetchResult: fetchResult)
        let removedAssets = assetsInRects(removedRects, fetchResult: fetchResult)

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        cachingImageManager.startCachingImages(for: addedAssets,
                                                targetSize: thumbnailSize,
                                                contentMode: .aspectFill,
                                                options: options)
        cachingImageManager.stopCachingImages(for: removedAssets,
                                              targetSize: thumbnailSize,
                                              contentMode: .aspectFill,
                                              options: options)
    }

    private func differencesBetween(old: CGRect, new: CGRect) -> (added: [CGRect], removed: [CGRect]) {
        if old.intersects(new) {
            var added = [CGRect]()
            if new.maxY > old.maxY {
                added.append(CGRect(x: new.origin.x, y: old.maxY,
                                    width: new.width, height: new.maxY - old.maxY))
            }
            if old.minY > new.minY {
                added.append(CGRect(x: new.origin.x, y: new.minY,
                                    width: new.width, height: old.minY - new.minY))
            }
            var removed = [CGRect]()
            if new.maxY < old.maxY {
                removed.append(CGRect(x: new.origin.x, y: new.maxY,
                                      width: new.width, height: old.maxY - new.maxY))
            }
            if old.minY < new.minY {
                removed.append(CGRect(x: new.origin.x, y: old.minY,
                                      width: new.width, height: new.minY - old.minY))
            }
            return (added, removed)
        } else {
            return ([new], [old])
        }
    }

    private func assetsInRects(_ rects: [CGRect], fetchResult: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets = [PHAsset]()
        for rect in rects {
            guard let layoutAttributes = collectionView.collectionViewLayout
                    .layoutAttributesForElements(in: rect) else { continue }
            for attr in layoutAttributes {
                let assetIndex = attr.indexPath.item - 1
                if assetIndex >= 0, assetIndex < fetchResult.count {
                    assets.append(fetchResult.object(at: assetIndex))
                }
            }
        }
        return assets
    }

    private func toggleSelection(for asset: PHAsset, at indexPath: IndexPath) {
        let id = asset.localIdentifier
        if selectedOrder[id] != nil {
            selectedOrder.removeValue(forKey: id)
            selectedAssets.removeAll { $0.localIdentifier == id }
            for (i, a) in selectedAssets.enumerated() {
                selectedOrder[a.localIdentifier] = i + 1
            }
        } else {
            guard selectedAssets.count < selectionLimit else {
                Toast.info("You can select up to \(selectionLimit) item\(selectionLimit == 1 ? "" : "s").", title: "")
                return
            }
            selectedAssets.append(asset)
            selectedOrder[id] = selectedAssets.count
        }
        updateSendButton()
        refreshVisibleSelectionBadges()
    }

    private func refreshVisibleSelectionBadges() {
        for case let cell as MediaPickerCell in collectionView.visibleCells {
            let id = cell.assetIdentifier
            guard !id.isEmpty else { continue }
            cell.updateSelectionOrder(selectedOrder[id])
        }
    }

    private func updateSendButton() {
        let count = selectedAssets.count
        let hasSelection = count > 0
        actionBar.isHidden = !hasSelection
        sendButton.setTitle(isVietnamese ? "Gửi (\(count))" : "Send (\(count))", for: .normal)

        let canEdit = count == 1 && selectedAssets.first?.mediaType == .image
        editButton.isHidden = !canEdit
        sendLeadingEditConstraint?.isActive = canEdit
        sendLeadingBarConstraint?.isActive = !canEdit
        collectionView.contentInset.bottom = hasSelection ? 72 : 0
        collectionView.verticalScrollIndicatorInsets.bottom = hasSelection ? 72 : 0
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.mediaTypes = ["public.image"]
        camera.cameraCaptureMode = .photo
        camera.delegate = self
        present(camera, animated: true)
    }

    private func confirmSelection(shouldDismiss: Bool = true) {
        guard !selectedAssets.isEmpty else { return }
        didSendResults = true
        sendButton.isEnabled = false

        let assets = selectedAssets
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: 3)
            var results = [(Int, MediaPickerResult)]()
            let lock = NSLock()

            for (order, asset) in assets.enumerated() {
                semaphore.wait()
                group.enter()
                let isVideo = asset.mediaType == .video
                let done: (MediaPickerResult?) -> Void = { result in
                    if let r = result {
                        lock.lock()
                        results.append((order, r))
                        lock.unlock()
                    }
                    semaphore.signal()
                    group.leave()
                }
                if isVideo {
                    self.exportVideo(asset: asset, completion: done)
                } else {
                    self.exportImage(asset: asset, completion: done)
                }
            }

            group.notify(queue: .main) {
                let sorted = results.sorted { $0.0 < $1.0 }.map(\.1)
                self.onPicked?(sorted)
                if shouldDismiss {
                    self.dismiss(animated: true)
                }
            }
        }
    }

    private func exportImage(asset: PHAsset, completion: @escaping (MediaPickerResult?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let pixelW = CGFloat(asset.pixelWidth)
        let pixelH = CGFloat(asset.pixelHeight)
        let maxDim = Self.maxUploadImageDimension
        let targetSize: CGSize
        if pixelW > 0, pixelH > 0, max(pixelW, pixelH) > maxDim {
            let scale = maxDim / max(pixelW, pixelH)
            targetSize = CGSize(width: max(1, pixelW * scale), height: max(1, pixelH * scale))
        } else if pixelW > 0, pixelH > 0 {
            targetSize = CGSize(width: pixelW, height: pixelH)
        } else {
            targetSize = CGSize(width: maxDim, height: maxDim)
        }

        var didComplete = false
        cachingImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if isDegraded { return }
            guard !didComplete else { return }
            didComplete = true
            guard let image else { completion(nil); return }

            DispatchQueue.global(qos: .userInitiated).async {
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "picked-\(UUID().uuidString).jpg"
                let fileURL = tempDir.appendingPathComponent(filename)
                if let data = image.jpegData(compressionQuality: 0.9) {
                    try? data.write(to: fileURL)
                    completion(MediaPickerResult(image: image, fileURL: fileURL, isVideo: false))
                } else {
                    completion(MediaPickerResult(image: image, fileURL: nil, isVideo: false))
                }
            }
        }
    }

    private func exportVideo(asset: PHAsset, completion: @escaping (MediaPickerResult?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        cachingImageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let urlAsset = avAsset as? AVURLAsset else {
                guard let avAsset else { completion(nil); return }
                self.exportComposition(avAsset: avAsset, completion: completion)
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
            let destURL = tempDir.appendingPathComponent("picked-\(UUID().uuidString).mov")
            do {
                try FileManager.default.copyItem(at: urlAsset.url, to: destURL)
            } catch {
                completion(nil)
                return
            }

            let thumbnail = Self.generateVideoThumbnail(from: destURL)
            guard let thumb = thumbnail else { completion(nil); return }
            completion(MediaPickerResult(image: thumb, fileURL: destURL, isVideo: true))
        }
    }

    private func exportComposition(avAsset: AVAsset, completion: @escaping (MediaPickerResult?) -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent("picked-\(UUID().uuidString).mov")

        guard let session = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil)
            return
        }
        session.outputURL = destURL
        session.outputFileType = .mov
        session.exportAsynchronously {
            guard session.status == .completed else { completion(nil); return }
            let thumbnail = Self.generateVideoThumbnail(from: destURL)
            guard let thumb = thumbnail else { completion(nil); return }
            completion(MediaPickerResult(image: thumb, fileURL: destURL, isVideo: true))
        }
    }

    private static func generateVideoThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension MediaPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        (fetchResult?.count ?? 0) + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CameraPreviewCell.reuseId, for: indexPath) as! CameraPreviewCell
            cell.onTap = { [weak self] in
                self?.openCamera()
            }
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                cell.startSession()
            }
            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaPickerCell.reuseId, for: indexPath) as! MediaPickerCell
        let assetIndex = indexPath.item - 1
        guard let asset = fetchResult?.object(at: assetIndex) else { return cell }

        cell.assetIdentifier = asset.localIdentifier
        let order = selectedOrder[asset.localIdentifier]

        cell.onTap = { [weak self] in
            self?.toggleSelection(for: asset, at: indexPath)
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        cachingImageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            guard cell.assetIdentifier == asset.localIdentifier, let image else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            cell.configure(image: image, isVideo: asset.mediaType == .video,
                           duration: asset.duration, selectionOrder: order)
            if isDegraded {

            }
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns: CGFloat = 3
        let spacing: CGFloat = 2
        let totalSpacing = spacing * (columns - 1)
        let side = floor((collectionView.bounds.width - totalSpacing) / columns)
        return CGSize(width: side, height: side)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
        updateCameraVisibility()
    }

    private func updateCameraVisibility() {
        let cameraIndexPath = IndexPath(item: 0, section: 0)
        guard let cell = collectionView.cellForItem(at: cameraIndexPath) as? CameraPreviewCell else { return }
        let cellFrame = collectionView.layoutAttributesForItem(at: cameraIndexPath)?.frame ?? .zero
        let visible = collectionView.bounds.intersects(cellFrame)
        if visible {
            cell.resumeSession()
        } else {
            cell.pauseSession()
        }
    }
}


extension MediaPickerViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.loadAssets()
        }
    }
}

extension MediaPickerViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }


        let tempDir = FileManager.default.temporaryDirectory
        let filename = "camera-\(UUID().uuidString).jpg"
        let fileURL = tempDir.appendingPathComponent(filename)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: fileURL)
        }

        let result = MediaPickerResult(image: image, fileURL: fileURL, isVideo: false)
        onPicked?([result])
        dismiss(animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}


private final class MediaPickerCell: UICollectionViewCell {

    static let reuseId = "MediaPickerCell"

    var assetIdentifier: String = ""
    var onTap: (() -> Void)?

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let selectionBadge: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13, weight: .bold)
        lbl.textColor = .white
        lbl.textAlignment = .center
        lbl.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        lbl.layer.cornerRadius = 12
        lbl.clipsToBounds = true
        lbl.isHidden = true
        return lbl
    }()

    private let videoOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }()

    private let durationLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        lbl.textColor = .white
        return lbl
    }()

    private let gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.5).cgColor]
        gl.locations = [0.5, 1.0]
        return gl
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tap)

        contentView.addSubview(thumbImageView)
        contentView.layer.addSublayer(gradientLayer)
        contentView.addSubview(videoOverlay)
        videoOverlay.addSubview(durationLabel)
        contentView.addSubview(selectionBadge)

        NSLayoutConstraint.activate([
            thumbImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            videoOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            videoOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            videoOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            videoOverlay.heightAnchor.constraint(equalToConstant: 24),

            durationLabel.trailingAnchor.constraint(equalTo: videoOverlay.trailingAnchor, constant: -6),
            durationLabel.bottomAnchor.constraint(equalTo: videoOverlay.bottomAnchor, constant: -4),

            selectionBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            selectionBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            selectionBadge.widthAnchor.constraint(equalToConstant: 24),
            selectionBadge.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }


    override var isHighlighted: Bool {
        didSet {}
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }

    @objc private func handleTap() {
        onTap?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbImageView.image = nil
        selectionBadge.isHidden = true
        videoOverlay.isHidden = true
        durationLabel.text = nil
        assetIdentifier = ""
        onTap = nil
    }

    func configure(image: UIImage?, isVideo: Bool, duration: TimeInterval, selectionOrder: Int?) {
        thumbImageView.image = image

        if isVideo {
            videoOverlay.isHidden = false
            gradientLayer.isHidden = false
            let mins = Int(duration) / 60
            let secs = Int(duration) % 60
            durationLabel.text = String(format: "%d:%02d", mins, secs)
        } else {
            videoOverlay.isHidden = true
            gradientLayer.isHidden = true
        }

        updateSelectionOrder(selectionOrder)
    }

    func updateSelectionOrder(_ selectionOrder: Int?) {
        if let order = selectionOrder {
            selectionBadge.isHidden = false
            selectionBadge.text = "\(order)"
            contentView.layer.borderWidth = 2
            contentView.layer.borderColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1).cgColor
        } else {
            selectionBadge.isHidden = true
            contentView.layer.borderWidth = 0
        }
    }
}


extension MediaPickerViewController {

    static func present(
        from viewController: UIViewController,
        selectionLimit: Int = .max,
        onEditedSend: ((MediaPickerResult) -> Void)? = nil,
        onPicked: @escaping ([MediaPickerResult]) -> Void
    ) {
        let picker = MediaPickerViewController()
        picker.onPicked = onPicked
        picker.onEditedSend = onEditedSend
        picker.selectionLimit = selectionLimit
        picker.modalPresentationStyle = .pageSheet

        if #available(iOS 15.0, *) {
            if let sheet = picker.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.preferredCornerRadius = 16
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            }
        }


        var presenter: UIViewController = viewController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let parent = viewController.parent {
            presenter = parent
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
        }

        presenter.present(picker, animated: true)
    }
}


private final class CameraPreviewCell: UICollectionViewCell {

    static let reuseId = "CameraPreviewCell"

    var onTap: (() -> Void)?

    private var captureSession: AVCaptureSession?
    private let previewLayer = AVCaptureVideoPreviewLayer()

    private let cameraIconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "camera.fill", withConfiguration: config))
        iv.tintColor = .white
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.clipsToBounds = true

        previewLayer.videoGravity = .resizeAspectFill
        contentView.layer.addSublayer(previewLayer)

        contentView.addSubview(cameraIconView)
        NSLayoutConstraint.activate([
            cameraIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cameraIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = contentView.bounds
    }

    @objc private func handleTap() {
        onTap?()
    }

    func startSession() {
        guard captureSession == nil,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        setupSession()
    }

    private func setupSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)
        previewLayer.session = session
        captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func pauseSession() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    func resumeSession() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func stopSession() {
        let session = captureSession
        captureSession = nil
        previewLayer.session = nil
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
    }
}


private final class AlbumDropdownView: UIView {

    var onSelect: ((Int) -> Void)?

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 0)
        tv.rowHeight = 54
        tv.register(AlbumCell.self, forCellReuseIdentifier: AlbumCell.reuseId)
        tv.bounces = false
        return tv
    }()

    private var albums: [(collection: PHAssetCollection?, title: String, count: Int, thumbnail: UIImage?)] = []
    private var selectedIndex: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.theme.secondary
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        clipsToBounds = false

        tableView.clipsToBounds = true
        tableView.layer.cornerRadius = 12
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self

        addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(albums: [(collection: PHAssetCollection?, title: String, count: Int, thumbnail: UIImage?)], selectedIndex: Int) {
        self.albums = albums
        self.selectedIndex = selectedIndex
        tableView.reloadData()


        let contentHeight = min(CGFloat(albums.count) * 54, 300)
        for c in constraints where c.firstAttribute == .height {
            c.constant = contentHeight
        }
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let h = min(CGFloat(albums.count) * 54, 300)
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }
}

extension AlbumDropdownView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        albums.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AlbumCell.reuseId, for: indexPath) as! AlbumCell
        let album = albums[indexPath.row]
        let isSelected = indexPath.row == selectedIndex
        cell.configure(title: album.title, count: album.count, thumbnail: album.thumbnail, isSelected: isSelected)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onSelect?(indexPath.row)
    }
}


private final class AlbumCell: UITableViewCell {

    static let reuseId = "AlbumCell"

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = UIColor.systemGray5
        return iv
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 15, weight: .medium)
        return lbl
    }()

    private let countLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = UIColor.mezonSecondaryLabel
        return lbl
    }()

    private let checkmarkView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let iv = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: config))
        iv.tintColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(thumbImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)
        contentView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            thumbImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbImageView.widthAnchor.constraint(equalToConstant: 36),
            thumbImageView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -8),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int, thumbnail: UIImage?, isSelected: Bool) {
        titleLabel.text = title
        countLabel.text = "\(count)"
        thumbImageView.image = thumbnail
        checkmarkView.isHidden = !isSelected
        titleLabel.textColor = UIColor.theme.textStrong
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
