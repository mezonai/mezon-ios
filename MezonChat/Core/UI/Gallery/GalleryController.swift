import Foundation
import UIKit
import AsyncDisplayKit
import Photos

final class GalleryController: UIViewController {
    private enum PhotoLibrarySaveAuthorizationResult {
        case authorized
        case denied
        case restricted
    }

    private let items: [GalleryItemInfo]
    private let initialIndex: Int

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

    private var isHeaderVisible = false
    private var panStartCenter: CGPoint = .zero

    private let placeholderImageView = UIImageView()
    private var didPerformDeferredSetup = false

    init(items: [GalleryItemInfo], initialIndex: Int) {
        self.items = items
        self.initialIndex = max(0, min(initialIndex, items.count - 1))

        self.containerNode = ASDisplayNode()
        self.backgroundNode = ASDisplayNode()
        self.pagingNode = GalleryPagingNode()

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
        let initialItem = items[initialIndex]
        if let placeholderURL = initialItem.placeholderURL,
           !placeholderURL.isEmpty,
           let cached = ImageCache.shared.memoryImage(forKey: placeholderURL) {
            placeholderImageView.image = cached
        } else {
            placeholderImageView.image = initialItem.image
        }
        view.addSubview(placeholderImageView)
        NSLayoutConstraint.activate([
            placeholderImageView.topAnchor.constraint(equalTo: view.topAnchor),
            placeholderImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholderImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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
        headerView.alpha = 0

        pagingNode.configure(items: items, initialIndex: initialIndex) { [weak self] info, index -> GalleryItemNode in
            return self?.makeItemNode(info: info, index: index) ?? GalleryItemNode()
        }
        pagingNode.centralItemIndexUpdated = { [weak self] index in
            self?.updateHeader(for: index)
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
            counterLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        counterLabel.alpha = 0

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanDismiss(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        updateHeader(for: initialIndex)

        view.setNeedsLayout()
        view.layoutIfNeeded()
        pagingNode.frame = containerNode.bounds
        pagingNode.updateLayout(size: containerNode.bounds.size, navigationBarHeight: 0)

        DispatchQueue.main.async { [weak self] in
            self?.placeholderImageView.removeFromSuperview()
        }
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

    private func updateHeader(for index: Int) {
        guard index < items.count else { return }
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

    private func toggleHeader() {
        isHeaderVisible.toggle()
        UIView.animate(withDuration: 0.25) {
            self.headerView.alpha = self.isHeaderVisible ? 1 : 0
            self.counterLabel.alpha = self.isHeaderVisible ? 1 : 0
        }
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
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let currentItem = items[pagingNode.centralItemIndex]
        if !currentItem.isVideo {
            sheet.addAction(UIAlertAction(title: "Save Image", style: .default) { [weak self] _ in
                guard let self else { return }
                guard let node = self.pagingNode.currentItemNode() as? ChatImageGalleryItemNode,
                      let image = node.currentImage else {
                    Toast.error(L(L10n.Gallery.imageSaveFailed))
                    return
                }
                self.saveImageToPhotoLibrary(image)
            })
            sheet.addAction(UIAlertAction(title: "Copy Image", style: .default) { [weak self] _ in
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
            self.present(activity, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
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
                    let targetY = translation.y > 0 ? self.view.bounds.height : -self.view.bounds.height
                    self.containerNode.view.center = CGPoint(x: self.panStartCenter.x, y: targetY)
                }) { _ in
                    self.dismiss(animated: false)
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.backgroundNode.alpha = 1
                    self.headerView.alpha = self.isHeaderVisible ? 1 : 0
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
