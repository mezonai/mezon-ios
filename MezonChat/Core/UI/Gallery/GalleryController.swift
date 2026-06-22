import Foundation
import UIKit
import AsyncDisplayKit
import Photos
import AVFoundation

final class GalleryController: UIViewController {
    private enum PhotoLibrarySaveAuthorizationResult {
        case authorized
        case denied
        case restricted
    }

    private var items: [GalleryItemInfo]
    private let initialIndex: Int
    private let channelItemsLoader: (() async -> [GalleryItemInfo])?

    private let containerNode: ASDisplayNode
    private let backgroundNode: ASDisplayNode
    private let pagingNode: GalleryPagingNode

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private let footerView = UIView()
    private let thumbnailCollectionView: UICollectionView

    private var isHeaderVisible = false
    private var panStartCenter: CGPoint = .zero

    private let placeholderImageView = UIImageView()
    private var didPerformDeferredSetup = false

    private var isSavingVideo = false
    private var didSetupVideoSaveOverlay = false
    private var videoSaveProgressObservation: NSKeyValueObservation?
    private let videoSaveBackdrop = UIView()
    private let videoSavePanel = UIView()
    private let videoSaveSpinner = UIActivityIndicatorView(style: .large)
    private let videoSaveLabel = UILabel()
    private let videoSaveProgressView = UIProgressView(progressViewStyle: .default)

    init(items: [GalleryItemInfo], initialIndex: Int, channelItemsLoader: (() async -> [GalleryItemInfo])? = nil) {
        self.items = items
        self.initialIndex = max(0, min(initialIndex, items.count - 1))
        self.channelItemsLoader = channelItemsLoader

        self.containerNode = ASDisplayNode()
        self.backgroundNode = ASDisplayNode()
        self.pagingNode = GalleryPagingNode()
        let thumbnailLayout = UICollectionViewFlowLayout()
        thumbnailLayout.scrollDirection = .horizontal
        thumbnailLayout.minimumInteritemSpacing = 4
        thumbnailLayout.minimumLineSpacing = 4
        thumbnailLayout.itemSize = CGSize(width: 44, height: 64)
        self.thumbnailCollectionView = UICollectionView(frame: .zero, collectionViewLayout: thumbnailLayout)

        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        placeholderImageView.contentMode = .scaleAspectFit
        placeholderImageView.backgroundColor = .black
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        if items.indices.contains(initialIndex) {
            applyInitialPlaceholder(for: items[initialIndex])
        }
        view.addSubview(placeholderImageView)
        NSLayoutConstraint.activate([
            placeholderImageView.topAnchor.constraint(equalTo: view.topAnchor),
            placeholderImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholderImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        DispatchQueue.main.async { [weak self] in
            self?.performDeferredSetupIfNeeded()
        }
    }

    private func applyInitialPlaceholder(for item: GalleryItemInfo) {
        if let preview = item.image {
            placeholderImageView.image = preview
            return
        }
        for key in placeholderCacheKeys(for: item) {
            if let cached = ImageCache.shared.memoryImage(forKey: key) {
                placeholderImageView.image = cached
                return
            }
        }
        loadPlaceholderFromDiskIfNeeded(for: item)
    }

    private func placeholderCacheKeys(for item: GalleryItemInfo) -> [String] {
        var keys: [String] = []
        if let placeholderURL = item.placeholderURL, !placeholderURL.isEmpty {
            keys.append(placeholderURL)
        }
        if !item.url.isEmpty {
            keys.append(item.url)
        }
        if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
            keys.append(contentsOf: GalleryItemInfo.previewCacheKeys(sourceURL: sourceURL, placeholderProxySize: 150))
            keys.append(contentsOf: GalleryItemInfo.previewCacheKeys(sourceURL: sourceURL, placeholderProxySize: 400))
        }
        var unique: [String] = []
        for key in keys where !unique.contains(key) {
            unique.append(key)
        }
        return unique
    }

    private func loadPlaceholderFromDiskIfNeeded(for item: GalleryItemInfo) {
        guard placeholderImageView.image == nil else { return }
        for key in placeholderCacheKeys(for: item) {
            guard ImageCache.shared.memoryImage(forKey: key) == nil else { continue }
            guard ImageCache.shared.hasDiskCache(forKey: key) else { continue }
            ImageCache.shared.imageFromDisk(forKey: key) { [weak self] image in
                guard let self, let image, self.placeholderImageView.image == nil else { return }
                self.placeholderImageView.image = image
            }
            return
        }
        guard let placeholderURL = item.placeholderURL, !placeholderURL.isEmpty else { return }
        ImageCache.shared.loadImage(urlString: placeholderURL) { [weak self] image in
            guard let self, let image, self.placeholderImageView.image == nil else { return }
            self.placeholderImageView.image = image
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performDeferredSetupIfNeeded()
    }

    private func performDeferredSetupIfNeeded() {
        guard !didPerformDeferredSetup else { return }
        didPerformDeferredSetup = true

        backgroundNode.backgroundColor = .black
        backgroundNode.frame = view.bounds
        backgroundNode.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(backgroundNode.view, belowSubview: placeholderImageView)

        containerNode.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(containerNode.view, belowSubview: placeholderImageView)
        NSLayoutConstraint.activate([
            containerNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            containerNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupHeader()
        setupFooter()
        headerView.alpha = isHeaderVisible ? 1 : 0
        footerView.alpha = isHeaderVisible && items.count > 1 ? 1 : 0

        pagingNode.configure(items: items, initialIndex: initialIndex) { [weak self] info, index -> GalleryItemNode in
            return self?.makeItemNode(info: info, index: index) ?? GalleryItemNode()
        }
        pagingNode.centralItemIndexUpdated = { [weak self] index in
            self?.updateSelection(for: index, revealControls: true)
        }
        pagingNode.toggleControlsVisibility = { [weak self] in
            self?.toggleHeader()
        }
        pagingNode.dismiss = { [weak self] in
            self?.closeTapped()
        }
        containerNode.addSubnode(pagingNode)

        counterLabel.font = .systemFont(ofSize: 13, weight: .medium)
        counterLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        counterLabel.textAlignment = .center
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(counterLabel)
        NSLayoutConstraint.activate([
            counterLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counterLabel.bottomAnchor.constraint(equalTo: footerView.topAnchor, constant: -8),
        ])

        counterLabel.alpha = isHeaderVisible ? 1 : 0

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanDismiss(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        view.setNeedsLayout()
        view.layoutIfNeeded()
        pagingNode.frame = containerNode.bounds
        pagingNode.updateLayout(size: containerNode.bounds.size, navigationBarHeight: 0)
        loadChannelItemsIfNeeded()

        dismissPlaceholderWhenGalleryReady()
        setupVideoSaveOverlayIfNeeded()
    }

    private func dismissPlaceholderWhenGalleryReady(attempt: Int = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasGalleryImage = (self.pagingNode.currentItemNode() as? ChatImageGalleryItemNode)?.currentImage != nil
            if hasGalleryImage {
                UIView.animate(withDuration: 0.12, animations: {
                    self.placeholderImageView.alpha = 0
                }, completion: { _ in
                    self.placeholderImageView.removeFromSuperview()
                })
                return
            }
            if self.placeholderImageView.image != nil {
                return
            }
            if attempt >= 200 {
                return
            }
            self.dismissPlaceholderWhenGalleryReady(attempt: attempt + 1)
        }
    }

    private func setupVideoSaveOverlayIfNeeded() {
        guard !didSetupVideoSaveOverlay else { return }
        didSetupVideoSaveOverlay = true

        videoSaveBackdrop.translatesAutoresizingMaskIntoConstraints = false
        videoSaveBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        videoSaveBackdrop.isHidden = true
        videoSaveBackdrop.isUserInteractionEnabled = true
        view.addSubview(videoSaveBackdrop)

        videoSavePanel.translatesAutoresizingMaskIntoConstraints = false
        videoSavePanel.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 0.96)
        videoSavePanel.layer.cornerRadius = 14
        videoSavePanel.isHidden = true
        videoSaveBackdrop.addSubview(videoSavePanel)

        videoSaveSpinner.translatesAutoresizingMaskIntoConstraints = false
        videoSaveSpinner.color = .white
        videoSaveSpinner.hidesWhenStopped = true
        videoSavePanel.addSubview(videoSaveSpinner)

        videoSaveLabel.translatesAutoresizingMaskIntoConstraints = false
        videoSaveLabel.font = .systemFont(ofSize: 14, weight: .medium)
        videoSaveLabel.textColor = .white
        videoSaveLabel.textAlignment = .center
        videoSaveLabel.numberOfLines = 2
        videoSavePanel.addSubview(videoSaveLabel)

        videoSaveProgressView.translatesAutoresizingMaskIntoConstraints = false
        videoSaveProgressView.progressTintColor = .systemBlue
        videoSaveProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.25)
        videoSaveProgressView.progress = 0
        videoSavePanel.addSubview(videoSaveProgressView)

        NSLayoutConstraint.activate([
            videoSaveBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            videoSaveBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoSaveBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoSaveBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            videoSavePanel.centerXAnchor.constraint(equalTo: videoSaveBackdrop.centerXAnchor),
            videoSavePanel.centerYAnchor.constraint(equalTo: videoSaveBackdrop.centerYAnchor),
            videoSavePanel.widthAnchor.constraint(equalToConstant: 240),

            videoSaveSpinner.topAnchor.constraint(equalTo: videoSavePanel.topAnchor, constant: 22),
            videoSaveSpinner.centerXAnchor.constraint(equalTo: videoSavePanel.centerXAnchor),

            videoSaveLabel.topAnchor.constraint(equalTo: videoSaveSpinner.bottomAnchor, constant: 12),
            videoSaveLabel.leadingAnchor.constraint(equalTo: videoSavePanel.leadingAnchor, constant: 16),
            videoSaveLabel.trailingAnchor.constraint(equalTo: videoSavePanel.trailingAnchor, constant: -16),

            videoSaveProgressView.topAnchor.constraint(equalTo: videoSaveLabel.bottomAnchor, constant: 14),
            videoSaveProgressView.leadingAnchor.constraint(equalTo: videoSavePanel.leadingAnchor, constant: 20),
            videoSaveProgressView.trailingAnchor.constraint(equalTo: videoSavePanel.trailingAnchor, constant: -20),
            videoSaveProgressView.bottomAnchor.constraint(equalTo: videoSavePanel.bottomAnchor, constant: -22),
        ])
    }

    private func showVideoSaveOverlay(progress: Float) {
        setupVideoSaveOverlayIfNeeded()
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        videoSaveLabel.text = "\(L(L10n.Gallery.videoDownloading)) \(percent)%"
        videoSaveProgressView.isHidden = false
        videoSaveProgressView.setProgress(min(max(progress, 0), 1), animated: progress > 0)
        videoSaveSpinner.startAnimating()
        videoSaveBackdrop.isHidden = false
        videoSavePanel.isHidden = false
        view.bringSubviewToFront(videoSaveBackdrop)
    }

    private func updateVideoSaveOverlaySavingPhase() {
        videoSaveLabel.text = L(L10n.Gallery.videoSaving)
        videoSaveProgressView.setProgress(1, animated: true)
    }

    private func hideVideoSaveOverlay() {
        videoSaveProgressObservation?.invalidate()
        videoSaveProgressObservation = nil
        videoSaveSpinner.stopAnimating()
        videoSaveProgressView.progress = 0
        videoSaveBackdrop.isHidden = true
        videoSavePanel.isHidden = true
        isSavingVideo = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard didPerformDeferredSetup else { return }
        pagingNode.frame = containerNode.bounds
        pagingNode.updateLayout(size: containerNode.bounds.size, navigationBarHeight: 0)
    }

    override var prefersStatusBarHidden: Bool { true }

    private func setupHeader() {
        headerView.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let backConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(backButton)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 20
        avatarImageView.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(avatarImageView)

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(nameLabel)

        dateLabel.font = .systemFont(ofSize: 13, weight: .regular)
        dateLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(dateLabel)

        let moreConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: moreConfig), for: .normal)
        moreButton.tintColor = .white
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        headerView.addSubview(moreButton)

        let safeGuide = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: safeGuide.topAnchor, constant: 56),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: safeGuide.topAnchor, constant: 28),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),

            avatarImageView.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            avatarImageView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 2),

            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            moreButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 40),
            moreButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func setupFooter() {
        footerView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.isHidden = !isHeaderVisible || items.count <= 1
        view.addSubview(footerView)

        thumbnailCollectionView.backgroundColor = .clear
        thumbnailCollectionView.showsHorizontalScrollIndicator = false
        thumbnailCollectionView.contentInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        thumbnailCollectionView.dataSource = self
        thumbnailCollectionView.delegate = self
        thumbnailCollectionView.register(GalleryThumbnailCell.self, forCellWithReuseIdentifier: GalleryThumbnailCell.reuseIdentifier)
        thumbnailCollectionView.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(thumbnailCollectionView)

        NSLayoutConstraint.activate([
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 96),

            thumbnailCollectionView.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            thumbnailCollectionView.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            thumbnailCollectionView.topAnchor.constraint(equalTo: footerView.topAnchor, constant: 12),
            thumbnailCollectionView.bottomAnchor.constraint(equalTo: footerView.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
    }

    private func updateSelection(for index: Int, revealControls: Bool) {
        if revealControls {
            if isHeaderVisible {
                updateHeader(for: index)
                updateFooterSelection(for: index, animated: true)
            } else {
                setControlsVisible(true, animated: true)
            }
        } else if isHeaderVisible {
            updateHeader(for: index)
            updateFooterSelection(for: index, animated: true)
        }
    }

    private func updateHeader(for index: Int) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]

        nameLabel.text = item.senderName.isEmpty ? nil : item.senderName
        avatarImageView.isHidden = item.senderName.isEmpty
        nameLabel.isHidden = item.senderName.isEmpty
        dateLabel.isHidden = item.senderName.isEmpty

        if let ts = item.timestamp {
            dateLabel.text = formatDate(ts)
        } else {
            dateLabel.text = nil
        }

        if let avatarURLStr = item.senderAvatarURL, !avatarURLStr.isEmpty {
            let proxyURL = ImgproxyURL.attachmentURL(
                from: avatarURLStr,
                width: 100,
                height: 100,
                resizeType: "fill"
            )
            if let cached = ImageCache.shared.memoryImage(forKey: proxyURL) {
                avatarImageView.image = cached
            } else {
                avatarImageView.image = nil
                ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
                    guard let self, let image else { return }
                    self.avatarImageView.image = image
                }
            }
        } else {
            avatarImageView.image = nil
        }

        if items.count > 1 {
            counterLabel.text = "\(index + 1)/\(items.count)"
            counterLabel.isHidden = false
        } else {
            counterLabel.isHidden = true
        }
    }

    private func updateFooterSelection(for index: Int, animated: Bool) {
        guard items.count > 1, index >= 0, index < items.count else {
            footerView.isHidden = true
            return
        }
        footerView.isHidden = false
        thumbnailCollectionView.reloadData()
        thumbnailCollectionView.layoutIfNeeded()
        thumbnailCollectionView.selectItem(
            at: IndexPath(item: index, section: 0),
            animated: false,
            scrollPosition: []
        )
        thumbnailCollectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredHorizontally,
            animated: animated
        )
    }

    private func loadChannelItemsIfNeeded() {
        guard let channelItemsLoader else { return }
        Task { [weak self] in
            let loadedItems = await channelItemsLoader()
            await MainActor.run {
                self?.applyLoadedChannelItems(loadedItems)
            }
        }
    }

    private func applyLoadedChannelItems(_ loadedItems: [GalleryItemInfo]) {
        guard !loadedItems.isEmpty else { return }
        let currentIdentity = items.indices.contains(pagingNode.centralItemIndex)
            ? items[pagingNode.centralItemIndex].stableIdentity
            : nil
        let mergedItems = mergedItems(primary: loadedItems, fallback: items)
        guard !mergedItems.isEmpty else { return }
        let focusIndex: Int
        if let currentIdentity,
           let found = mergedItems.firstIndex(where: { $0.stableIdentity == currentIdentity }) {
            focusIndex = found
        } else {
            focusIndex = min(pagingNode.centralItemIndex, mergedItems.count - 1)
        }
        items = mergedItems
        pagingNode.replaceItemsPreservingCurrent(mergedItems, focusIndex: focusIndex)
        if isHeaderVisible {
            setControlsVisible(true, animated: false)
        }
    }

    private func mergedItems(primary: [GalleryItemInfo], fallback: [GalleryItemInfo]) -> [GalleryItemInfo] {
        var seen = Set<String>()
        var result: [GalleryItemInfo] = []
        for item in primary + fallback {
            let key = item.stableIdentity.isEmpty ? "local:\(result.count)" : item.stableIdentity
            guard seen.insert(key).inserted else { continue }
            result.append(item)
        }
        return result
    }

    private func toggleHeader() {
        setControlsVisible(!isHeaderVisible, animated: true)
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        isHeaderVisible = visible
        if visible {
            updateHeader(for: pagingNode.centralItemIndex)
            updateFooterSelection(for: pagingNode.centralItemIndex, animated: false)
        }
        let updates = {
            self.headerView.alpha = visible ? 1 : 0
            self.counterLabel.alpha = visible ? 1 : 0
            self.footerView.alpha = visible && self.items.count > 1 ? 1 : 0
        }
        guard animated else {
            updates()
            if !visible {
                self.footerView.isHidden = true
            }
            return
        }
        if visible {
            footerView.isHidden = items.count <= 1
        }
        UIView.animate(withDuration: 0.25, animations: {
            updates()
        }, completion: { _ in
            if !visible {
                self.footerView.isHidden = true
            }
        })
    }

    private func makeItemNode(info: GalleryItemInfo, index: Int) -> GalleryItemNode {
        if info.isVideo {
            let node = ChatVideoGalleryItemNode()
            node.index = index
            node.configure(info: info)
            return node
        } else {
            let node = ChatImageGalleryItemNode()
            node.index = index
            node.configure(info: info)
            return node
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func moreTapped() {
        guard items.indices.contains(pagingNode.centralItemIndex) else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let currentItem = items[pagingNode.centralItemIndex]
        if currentItem.isVideo {
            sheet.addAction(UIAlertAction(title: L(L10n.MessageAction.saveVideo), style: .default) { [weak self] _ in
                guard let self else { return }
                let item = self.items[self.pagingNode.centralItemIndex]
                let videoURLString = item.sourceURL ?? item.url
                self.saveVideoToPhotoLibrary(urlString: videoURLString)
            })
        } else {
            sheet.addAction(UIAlertAction(title: L(L10n.MessageAction.saveImage), style: .default) { [weak self] _ in
                guard let self else { return }
                guard let node = self.pagingNode.currentItemNode() as? ChatImageGalleryItemNode,
                      let image = node.currentImage else {
                    Toast.error(L(L10n.Gallery.imageSaveFailed))
                    return
                }
                self.saveImageToPhotoLibrary(image)
            })
            sheet.addAction(UIAlertAction(title: L(L10n.MessageAction.copyImage), style: .default) { [weak self] _ in
                guard let node = self?.pagingNode.currentItemNode() as? ChatImageGalleryItemNode,
                      let image = node.currentImage else { return }
                UIPasteboard.general.image = image
                Toast.success(L(L10n.MessageAction.copied))
            })
        }

        sheet.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            guard let self else { return }
            let item = self.items[self.pagingNode.centralItemIndex]
            var shareItems: [Any] = []
            if let node = self.pagingNode.currentItemNode() as? ChatImageGalleryItemNode,
               let image = node.currentImage {
                shareItems.append(image)
            } else if let url = URL(string: item.url) {
                shareItems.append(url)
            }
            guard !shareItems.isEmpty else { return }
            let activity = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = self.moreButton
                popover.sourceRect = self.moreButton.bounds
            }
            self.present(activity, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = moreButton
            popover.sourceRect = moreButton.bounds
        }
        present(sheet, animated: true)
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) {
        requestPhotoLibrarySaveAuthorization { [weak self] result in
            switch result {
            case .authorized:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            Toast.success(L(L10n.Gallery.imageSaved))
                        } else {
                            Toast.error(error?.localizedDescription ?? L(L10n.Gallery.imageSaveFailed))
                        }
                    }
                })
            case .denied:
                DispatchQueue.main.async {
                    self?.presentPhotoPermissionSettingsAlert()
                }
            case .restricted:
                DispatchQueue.main.async {
                    Toast.error(L(L10n.Gallery.photoPermissionDenied))
                }
            }
        }
    }

    private func saveVideoToPhotoLibrary(urlString: String) {
        guard !isSavingVideo else { return }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let remoteURL = URL(string: trimmed) else {
            Toast.error(L(L10n.Gallery.videoSaveFailed))
            return
        }

        isSavingVideo = true
        requestPhotoLibrarySaveAuthorization { [weak self] result in
            guard let self else { return }
            switch result {
            case .authorized:
                DispatchQueue.main.async {
                    self.showVideoSaveOverlay(progress: 0)
                }
                let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, _, error in
                    guard let self else { return }
                    guard let tempURL, error == nil else {
                        DispatchQueue.main.async {
                            self.hideVideoSaveOverlay()
                            Toast.error(error?.localizedDescription ?? L(L10n.Gallery.videoSaveFailed))
                        }
                        return
                    }

                    let ext = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("gallery-video-\(UUID().uuidString).\(ext)")

                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: destURL)
                    } catch {
                        DispatchQueue.main.async {
                            self.hideVideoSaveOverlay()
                            Toast.error(L(L10n.Gallery.videoSaveFailed))
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.updateVideoSaveOverlaySavingPhase()
                    }

                    let savedAt = Date()
                    PHPhotoLibrary.shared().performChanges({
                        let request = PHAssetCreationRequest.forAsset()
                        request.creationDate = savedAt
                        request.addResource(with: .video, fileURL: destURL, options: nil)
                    }, completionHandler: { success, saveError in
                        try? FileManager.default.removeItem(at: destURL)
                        DispatchQueue.main.async {
                            self.hideVideoSaveOverlay()
                            if success {
                                Toast.success(L(L10n.Gallery.videoSaved))
                            } else {
                                Toast.error(saveError?.localizedDescription ?? L(L10n.Gallery.videoSaveFailed))
                            }
                        }
                    })
                }
                self.videoSaveProgressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    DispatchQueue.main.async {
                        self?.showVideoSaveOverlay(progress: Float(progress.fractionCompleted))
                    }
                }
                task.resume()
            case .denied:
                DispatchQueue.main.async {
                    self.hideVideoSaveOverlay()
                    self.presentPhotoPermissionSettingsAlert()
                }
            case .restricted:
                DispatchQueue.main.async {
                    self.hideVideoSaveOverlay()
                    Toast.error(L(L10n.Gallery.photoPermissionDenied))
                }
            }
        }
    }

    private func requestPhotoLibrarySaveAuthorization(completion: @escaping (PhotoLibrarySaveAuthorizationResult) -> Void) {
        if #available(iOS 14.0, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    switch status {
                    case .authorized, .limited:
                        completion(.authorized)
                    case .denied:
                        completion(.denied)
                    case .restricted:
                        completion(.restricted)
                    case .notDetermined:
                        completion(.denied)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .denied:
                completion(.denied)
            case .restricted:
                completion(.restricted)
            @unknown default:
                completion(.denied)
            }
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized, .limited:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    switch status {
                    case .authorized, .limited:
                        completion(.authorized)
                    case .denied:
                        completion(.denied)
                    case .restricted:
                        completion(.restricted)
                    case .notDetermined:
                        completion(.denied)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .denied:
                completion(.denied)
            case .restricted:
                completion(.restricted)
            @unknown default:
                completion(.denied)
            }
        }
    }

    private func presentPhotoPermissionSettingsAlert() {
        let presentAlert = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: L(L10n.Gallery.photoPermissionTitle),
                message: L(L10n.Gallery.photoPermissionMessage),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
            alert.addAction(UIAlertAction(title: L(L10n.Common.settings), style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
            self.present(alert, animated: true)
        }

        if let presentedViewController {
            presentedViewController.dismiss(animated: true, completion: presentAlert)
        } else {
            presentAlert()
        }
    }

    @objc private func handlePanDismiss(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            panStartCenter = containerNode.view.center
        case .changed:
            let progress = abs(translation.y) / (view.bounds.height / 2)
            backgroundNode.alpha = max(0.3, 1 - progress)
            if isHeaderVisible {
                headerView.alpha = max(0, 1 - progress * 2)
                counterLabel.alpha = max(0, 1 - progress * 2)
                footerView.alpha = items.count > 1 ? max(0, 1 - progress * 2) : 0
            }
            containerNode.view.center = CGPoint(x: panStartCenter.x, y: panStartCenter.y + translation.y)
        case .ended, .cancelled:
            let shouldDismiss = abs(translation.y) > 100 || abs(velocity.y) > 800
            if shouldDismiss {
                if let videoNode = pagingNode.currentItemNode() as? ChatVideoGalleryItemNode {
                    videoNode.visibilityUpdated(isVisible: false)
                }
                UIView.animate(withDuration: 0.25, animations: {
                    self.backgroundNode.alpha = 0
                    self.containerNode.alpha = 0
                    self.headerView.alpha = 0
                    self.counterLabel.alpha = 0
                    self.footerView.alpha = 0
                    let targetY = translation.y > 0 ? self.view.bounds.height : -self.view.bounds.height
                    self.containerNode.view.center = CGPoint(x: self.panStartCenter.x, y: targetY)
                }) { _ in
                    self.dismiss(animated: false)
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.backgroundNode.alpha = 1
                    self.headerView.alpha = self.isHeaderVisible ? 1 : 0
                    self.counterLabel.alpha = self.isHeaderVisible ? 1 : 0
                    self.footerView.alpha = self.isHeaderVisible && self.items.count > 1 ? 1 : 0
                    self.containerNode.view.center = self.panStartCenter
                }
            }
        default: break
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let time = fmt.string(from: date)
        if cal.isDateInToday(date) { return "Today at \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday at \(time)" }
        fmt.dateFormat = "dd/MM/yyyy HH:mm"
        return fmt.string(from: date)
    }
}

extension GalleryController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GalleryThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as? GalleryThumbnailCell else {
            return UICollectionViewCell()
        }
        let index = indexPath.item
        if index < items.count {
            cell.configure(item: items[index], isSelected: index == pagingNode.centralItemIndex)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        pagingNode.setCentralItemIndex(indexPath.item, animated: true)
        updateSelection(for: indexPath.item, revealControls: false)
    }
}

private final class GalleryThumbnailCell: UICollectionViewCell {
    static let reuseIdentifier = "GalleryThumbnailCell"

    private let imageView = UIImageView()
    private let playOverlayView = UIView()
    private let playIconView = UIImageView()
    private var representedIdentity: String?
    private var imageTask: URLSessionDataTask?
    private var thumbnailGenerator: AVAssetImageGenerator?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 4
        contentView.backgroundColor = UIColor.white.withAlphaComponent(0.12)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        playOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        playOverlayView.translatesAutoresizingMaskIntoConstraints = false
        playOverlayView.isHidden = true
        contentView.addSubview(playOverlayView)

        let playConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        playIconView.image = UIImage(systemName: "play.fill", withConfiguration: playConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        playIconView.contentMode = .scaleAspectFit
        playIconView.translatesAutoresizingMaskIntoConstraints = false
        playOverlayView.addSubview(playIconView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            playOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            playOverlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            playOverlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            playIconView.centerXAnchor.constraint(equalTo: playOverlayView.centerXAnchor),
            playIconView.centerYAnchor.constraint(equalTo: playOverlayView.centerYAnchor),
            playIconView.widthAnchor.constraint(equalToConstant: 18),
            playIconView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedIdentity = nil
        imageTask?.cancel()
        imageTask = nil
        thumbnailGenerator?.cancelAllCGImageGeneration()
        thumbnailGenerator = nil
        imageView.image = nil
        playOverlayView.isHidden = true
    }

    func configure(item: GalleryItemInfo, isSelected: Bool) {
        representedIdentity = item.stableIdentity
        contentView.layer.borderWidth = isSelected ? 2 : 0
        contentView.layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
        playOverlayView.isHidden = !item.isVideo

        if item.isVideo {
            loadVideoThumbnail(urlString: item.sourceURL ?? item.url, identity: item.stableIdentity)
        } else if let image = item.image {
            imageView.image = image
        } else {
            let thumbnailURL = item.placeholderURL ?? item.url
            loadImage(urlString: thumbnailURL, identity: item.stableIdentity)
        }
    }

    private func loadImage(urlString: String, identity: String) {
        guard !urlString.isEmpty else { return }
        imageTask = ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            guard let self, self.representedIdentity == identity else { return }
            self.imageView.image = image
        }
    }

    private func loadVideoThumbnail(urlString: String, identity: String) {
        guard let videoURL = URL(string: urlString), !urlString.isEmpty else { return }
        let cacheKey = "video_thumb_\(urlString)"
        if let cached = ImageCache.shared.image(forKey: cacheKey) {
            imageView.image = cached
            return
        }

        let asset = AVURLAsset(url: videoURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        thumbnailGenerator = generator

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, cgImage, _, _, _ in
            guard let cgImage else { return }
            let image = UIImage(cgImage: cgImage)
            ImageCache.shared.setImage(image, data: image.jpegData(compressionQuality: 0.7), forKey: cacheKey)
            DispatchQueue.main.async {
                guard let self, self.representedIdentity == identity else { return }
                self.imageView.image = image
            }
        }
    }
}

extension GalleryController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: view)
        guard abs(v.y) > abs(v.x) else { return false }
        if let zoomable = pagingNode.currentItemNode() as? ZoomableContentGalleryItemNode {
            let sv = zoomable.scrollNode.view
            if sv.zoomScale > sv.minimumZoomScale + 0.01 {
                return false
            }
        }
        return true
    }
}
