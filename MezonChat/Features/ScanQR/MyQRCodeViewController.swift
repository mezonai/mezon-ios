import AsyncDisplayKit
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private let maxQRCenterImageDimension: CGFloat = 512

private func normalizedQRCenterImage(_ image: UIImage) -> UIImage {
    let pixelSize = CGSize(
        width: image.size.width * image.scale,
        height: image.size.height * image.scale)
    let longestSide = max(pixelSize.width, pixelSize.height)
    guard longestSide > maxQRCenterImageDimension, longestSide > 0 else { return image }

    let scale = maxQRCenterImageDimension / longestSide
    let targetSize = CGSize(
        width: max(1, pixelSize.width * scale),
        height: max(1, pixelSize.height * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
}

private func qrCenterImageThumbnail(from data: Data) -> UIImage? {
    UIImage.avatarPreviewImage(
        from: data,
        maxPixelSize: Int(maxQRCenterImageDimension))
}

final class MyQRCodeViewController: ViewController {

    private enum PhotoLibrarySaveAuthorizationResult {
        case authorized
        case denied
        case restricted
    }

    private let context: AccountContext
    private var centerImageRequestGeneration = 0
    private var myQRCodeNode: MyQRCodeContainerNode {
        return self.displayNode as! MyQRCodeContainerNode
    }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
        self.title = L(L10n.QRScanner.myQRCode)
        self.displayNavigationBar = false
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        self.displayNode = MyQRCodeContainerNode(context: self.context)

        myQRCodeNode.onTabChanged = { [weak self] index in
            self?.myQRCodeNode.updateTab(index)
        }
        
        myQRCodeNode.onBackTapped = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }

        myQRCodeNode.onEditCenterImageTapped = { [weak self] in
            self?.presentCenterImageOptions()
        }
        
        myQRCodeNode.onDownloadTapped = { [weak self] image in
            self?.saveImageToPhotoLibrary(image)
        }
        
        myQRCodeNode.onShareTapped = { [weak self] image in
            guard let self = self else { return }
            let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                let anchorView = self.myQRCodeNode.shareAnchorView
                popover.sourceView = anchorView
                popover.sourceRect = anchorView.bounds
            }
            self.present(activityVC, animated: true)
        }
    }

    private func presentCenterImageOptions() {
        let sheet = UIAlertController(
            title: L(L10n.QRScanner.centerImage), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: L(L10n.QRScanner.chooseCenterImage), style: .default
        ) { [weak self] _ in
            self?.chooseCenterImageFromDevice()
        })
        sheet.addAction(UIAlertAction(
            title: L(L10n.QRScanner.useProfileAvatar), style: .default
        ) { [weak self] _ in
            self?.selectProfileAvatar()
        })
        sheet.addAction(UIAlertAction(
            title: L(L10n.QRScanner.useMezonLogo), style: .default
        ) { [weak self] _ in
            self?.selectMezonLogo()
        })
        sheet.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))

        if let popover = sheet.popoverPresentationController {
            let anchorView = myQRCodeNode.editAnchorView
            popover.sourceView = anchorView
            popover.sourceRect = anchorView.bounds
        }
        present(sheet, animated: true)
    }

    private func chooseCenterImageFromDevice() {
        invalidatePendingCenterImageRequest()
        presentCenterImagePicker()
    }

    private func selectProfileAvatar() {
        invalidatePendingCenterImageRequest()
        myQRCodeNode.useProfileAvatar()
    }

    private func selectMezonLogo() {
        invalidatePendingCenterImageRequest()
        myQRCodeNode.useMezonLogo()
    }

    private func presentCenterImagePicker() {
        if #available(iOS 14.0, *) {
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        } else {
            requestLegacyPhotoLibraryAccess()
        }
    }

    private func requestLegacyPhotoLibraryAccess() {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            presentLegacyImagePicker()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if status == .authorized {
                        self.presentLegacyImagePicker()
                    } else {
                        self.presentPhotoPermissionSettingsAlert()
                    }
                }
            }
        case .denied, .restricted:
            presentPhotoPermissionSettingsAlert()
        @unknown default:
            presentPhotoPermissionSettingsAlert()
        }
    }

    private func presentLegacyImagePicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        if UIDevice.current.userInterfaceIdiom == .pad {
            picker.modalPresentationStyle = .popover
            if let popover = picker.popoverPresentationController {
                let anchorView = myQRCodeNode.editAnchorView
                popover.sourceView = anchorView
                popover.sourceRect = anchorView.bounds
            }
        }
        present(picker, animated: true)
    }

    private func presentPhotoPermissionSettingsAlert() {
        let presentAlert = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: L(L10n.Gallery.photoPermissionTitle),
                message: L(L10n.Gallery.photoPermissionMessage),
                preferredStyle: .alert)
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
                            Toast.error(
                                error?.localizedDescription ?? L(L10n.Gallery.imageSaveFailed))
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

    private func requestPhotoLibrarySaveAuthorization(
        completion: @escaping (PhotoLibrarySaveAuthorizationResult) -> Void
    ) {
        if #available(iOS 14.0, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                completion(.authorized)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    switch status {
                    case .authorized, .limited:
                        completion(.authorized)
                    case .restricted:
                        completion(.restricted)
                    case .denied, .notDetermined:
                        completion(.denied)
                    @unknown default:
                        completion(.denied)
                    }
                }
            case .restricted:
                completion(.restricted)
            case .denied:
                completion(.denied)
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

    private func prepareCenterImage(
        from data: Data,
        requestGeneration: Int
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let centerImage = qrCenterImageThumbnail(from: data)
            DispatchQueue.main.async {
                self?.finishCenterImageRequest(centerImage, generation: requestGeneration)
            }
        }
    }

    private func prepareCenterImage(
        _ image: UIImage,
        requestGeneration: Int
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let centerImage = normalizedQRCenterImage(image)
            DispatchQueue.main.async {
                self?.finishCenterImageRequest(centerImage, generation: requestGeneration)
            }
        }
    }

    private func prepareCenterImage(
        at imageURL: URL,
        requestGeneration: Int
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let centerImage = (try? Data(contentsOf: imageURL))
                .flatMap(qrCenterImageThumbnail)
            DispatchQueue.main.async {
                self?.finishCenterImageRequest(centerImage, generation: requestGeneration)
            }
        }
    }

    private func finishCenterImageRequest(_ image: UIImage?, generation: Int) {
        guard centerImageRequestGeneration == generation else { return }
        guard let image else {
            Toast.error(L(L10n.Error.somethingWentWrong))
            return
        }
        myQRCodeNode.useCustomCenterImage(image)
    }

    private func invalidatePendingCenterImageRequest() {
        centerImageRequestGeneration &+= 1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.tintColor = UIColor.mezonTextStrong
    }

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition
    ) {
        super.containerLayoutUpdated(layout, transition: transition)
        myQRCodeNode.updateLayout(layout: layout, transition: transition)
    }
}

@available(iOS 14.0, *)
extension MyQRCodeViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider else {
            return
        }

        let typeIdentifier = UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return }

        let requestGeneration = centerImageRequestGeneration
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data else {
                    self.finishCenterImageRequest(nil, generation: requestGeneration)
                    return
                }
                self.prepareCenterImage(from: data, requestGeneration: requestGeneration)
            }
        }
    }
}

extension MyQRCodeViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        let requestGeneration = centerImageRequestGeneration
        if let imageURL = info[.imageURL] as? URL {
            prepareCenterImage(
                at: imageURL,
                requestGeneration: requestGeneration)
        } else if let image = info[.originalImage] as? UIImage {
            prepareCenterImage(image, requestGeneration: requestGeneration)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
