import UIKit
import Photos

final class MediaActionHandler {
    private enum PhotoLibrarySaveAuthorizationResult {
        case authorized
        case denied
        case restricted
    }

    private weak var presenter: UIViewController?
    private var isSavingVideo = false
    private var videoSaveProgressObservation: NSKeyValueObservation?
    private lazy var videoSaveBackdrop = UIView()
    private lazy var videoSavePanel = UIView()
    private lazy var videoSaveSpinner = UIActivityIndicatorView(style: .large)
    private lazy var videoSaveLabel = UILabel()
    private lazy var videoSaveProgressView = UIProgressView(progressViewStyle: .default)

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    static func shareImage(_ image: UIImage, from presenter: UIViewController, sourceView: UIView) {
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView
            if sourceView === presenter.view {
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            } else {
                popover.sourceRect = sourceView.bounds
            }
        }
        presenter.present(activity, animated: true)
    }

    private func finishVideoSave() {
        videoSaveProgressObservation?.invalidate()
        videoSaveProgressObservation = nil
        isSavingVideo = false
        hideVideoSaveOverlay()
    }

    func saveImageToPhotoLibrary(_ image: UIImage) {
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
                self?.presentPhotoPermissionSettingsAlert()
            case .restricted:
                Toast.error(L(L10n.Gallery.photoPermissionDenied))
            }
        }
    }

    func saveVideoToPhotoLibrary(urlString: String) {
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
                self.showVideoSaveOverlay(progress: 0)
                CDNSigner.shared.downloadTask(with: remoteURL, in: .shared, onStart: { [weak self] started in
                    DispatchQueue.main.async {
                        guard let self, self.isSavingVideo else { return }
                        self.videoSaveProgressObservation = started.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                            let fractionCompleted = Float(progress.fractionCompleted)
                            DispatchQueue.main.async {
                                guard let self, self.isSavingVideo else { return }
                                self.showVideoSaveOverlay(progress: fractionCompleted)
                            }
                        }
                    }
                }) { [weak self] tempURL, _, error in
                    guard let self else { return }
                    guard let tempURL, error == nil else {
                        DispatchQueue.main.async {
                            self.finishVideoSave()
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
                            self.finishVideoSave()
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
                            self.finishVideoSave()
                            if success {
                                Toast.success(L(L10n.Gallery.videoSaved))
                            } else {
                                Toast.error(saveError?.localizedDescription ?? L(L10n.Gallery.videoSaveFailed))
                            }
                        }
                    })
                }
            case .denied:
                self.finishVideoSave()
                self.presentPhotoPermissionSettingsAlert()
            case .restricted:
                self.finishVideoSave()
                Toast.error(L(L10n.Gallery.photoPermissionDenied))
            }
        }
    }

    private func requestPhotoLibrarySaveAuthorization(completion: @escaping (PhotoLibrarySaveAuthorizationResult) -> Void) {
        let handleStatus: (PHAuthorizationStatus) -> Void = { status in
            let result: PhotoLibrarySaveAuthorizationResult
            switch status {
            case .authorized, .limited:
                result = .authorized
            case .restricted:
                result = .restricted
            case .denied, .notDetermined:
                result = .denied
            @unknown default:
                result = .denied
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }

        if #available(iOS 14.0, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if status == .notDetermined {
                PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: handleStatus)
            } else {
                handleStatus(status)
            }
        } else {
            let status = PHPhotoLibrary.authorizationStatus()
            if status == .notDetermined {
                PHPhotoLibrary.requestAuthorization(handleStatus)
            } else {
                handleStatus(status)
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
            self.presenter?.present(alert, animated: true)
        }

        if let presentedViewController = presenter?.presentedViewController {
            presentedViewController.dismiss(animated: true, completion: presentAlert)
        } else {
            presentAlert()
        }
    }

    private func setupVideoSaveOverlayIfNeeded() {
        guard let view = presenter?.view, videoSaveBackdrop.superview == nil else { return }

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
        presenter?.view.bringSubviewToFront(videoSaveBackdrop)
    }

    private func updateVideoSaveOverlaySavingPhase() {
        videoSaveLabel.text = L(L10n.Gallery.videoSaving)
        videoSaveProgressView.setProgress(1, animated: true)
    }

    private func hideVideoSaveOverlay() {
        guard videoSaveBackdrop.superview != nil else { return }
        videoSaveSpinner.stopAnimating()
        videoSaveProgressView.progress = 0
        videoSaveBackdrop.isHidden = true
        videoSavePanel.isHidden = true
    }

}
