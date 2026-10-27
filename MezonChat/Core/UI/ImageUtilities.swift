import CoreImage
import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

enum ImagePickerFilename {
    static func originalFilename(from info: [UIImagePickerController.InfoKey: Any]) -> String? {
        guard let asset = info[.phAsset] as? PHAsset,
              let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
            return nil
        }
        let name = resource.originalFilename
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }

    static func requiresOriginalData(from info: [UIImagePickerController.InfoKey: Any]) -> Bool {
        guard let asset = info[.phAsset] as? PHAsset,
              let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else {
            return false
        }
        return publicImageRequiresOriginalData(resource.uniformTypeIdentifier)
    }
}

@available(iOS 14.0, *)
func publicImageTypeIdentifier(_ registeredTypes: [String]) -> String {
    registeredTypes.first {
        $0 != UTType.image.identifier
            && !$0.hasPrefix("com.apple.private.photos.thumbnail.")
            && UTType($0)?.conforms(to: .image) == true
    } ?? UTType.image.identifier
}

func publicImageRequiresOriginalData(_ identifier: String) -> Bool {
    if #available(iOS 14.0, *) {
        let mimeType = UTType(identifier)?.preferredMIMEType
        return mimeType == "image/gif" || mimeType == "image/webp"
    }
    return identifier == "com.compuserve.gif" || identifier == "org.webmproject.webp"
}

func publicImagePassthroughMimeType(for data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let type = CGImageSourceGetType(source) as String? else { return nil }
    switch type {
    case "com.compuserve.gif": return "image/gif"
    case "org.webmproject.webp": return "image/webp"
    default: return nil
    }
}

struct PublicImageSelection {
    let image: UIImage
    let preservedData: Data?
    let originalFilename: String?
    let sourceByteCount: Int?
    var mimeType: String { preservedData.flatMap(publicImagePassthroughMimeType) ?? "image/jpeg" }
}

final class PublicImagePicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    UIAdaptivePresentationControllerDelegate {
    private var picker: UIImagePickerController?
    private let allowsEditing: Bool
    private let maxBytes: Int?
    private let tooLargeMessage: String
    private let previewPixelSize: Int
    private var completion: ((PublicImageSelection?) -> Void)?

    init(allowsEditing: Bool, maxBytes: Int? = nil,
         tooLargeMessage: String = L(L10n.ProfileSetting.updateError), previewPixelSize: Int = 512,
         completion: @escaping (PublicImageSelection?) -> Void) {
        self.allowsEditing = allowsEditing
        self.maxBytes = maxBytes
        self.tooLargeMessage = tooLargeMessage
        self.previewPixelSize = previewPixelSize
        self.completion = completion
    }

    func present(from presenter: UIViewController) {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            finish(nil)
            return
        }
        let controller = UIImagePickerController()
        controller.sourceType = .photoLibrary
        controller.mediaTypes = ["public.image"]
        controller.allowsEditing = allowsEditing
        controller.delegate = self
        picker = controller
        presenter.present(controller, animated: true)
        controller.presentationController?.delegate = self
    }

    private func prepare(data: Data?, fallbackImage: UIImage?, filename: String?) {
        let maxBytes = maxBytes
        let previewPixelSize = previewPixelSize
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mimeType = data.flatMap(publicImagePassthroughMimeType)
            if mimeType != nil, let data, let maxBytes, data.count > maxBytes {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.completion != nil else { return }
                    self.dismissPicker {
                        Toast.error(self.tooLargeMessage)
                        self.finish(nil)
                    }
                }
                return
            }
            let image: UIImage?
            if mimeType != nil, let data {
                image = UIImage.publicImageUploadPreview(from: data, maxPixelSize: previewPixelSize)
            } else {
                image = fallbackImage ?? data.flatMap { UIImage.decodeImage(from: $0) }
            }
            let selection = image.map {
                PublicImageSelection(image: $0, preservedData: mimeType == nil ? nil : data,
                                     originalFilename: filename, sourceByteCount: data?.count)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.completion != nil else { return }
                self.dismissPicker { self.deliver(selection) }
            }
        }
    }

    private func dismissPicker(completion: @escaping () -> Void) {
        guard let picker else { completion(); return }
        self.picker = nil
        picker.dismiss(animated: true, completion: completion)
    }

    private func deliver(_ selection: PublicImageSelection?) {
        guard completion != nil else { return }
        guard let selection else {
            Toast.error(L(L10n.ProfileSetting.updateError))
            finish(nil)
            return
        }
        finish(selection)
    }

    private func finish(_ selection: PublicImageSelection?) {
        let callback = completion
        completion = nil
        callback?(selection)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        let filename = ImagePickerFilename.originalFilename(from: info)
        let url = info[.imageURL] as? URL
        let requiresOriginalData = ImagePickerFilename.requiresOriginalData(from: info)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
            if requiresOriginalData, data.flatMap(publicImagePassthroughMimeType) == nil {
                self?.prepare(data: nil, fallbackImage: nil, filename: filename)
            } else {
                self?.prepare(data: data, fallbackImage: image, filename: filename)
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismissPicker { self.finish(nil) }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        picker = nil
        finish(nil)
    }
}

extension ImageCache {
    func cachePublicImage(_ image: UIImage, data: Data, mimeType: String, forKey key: String) {
        if mimeType == "image/gif" || mimeType == "image/webp" {
            persistData(data, forKey: key)
        } else {
            setImage(image, data: data, forKey: key)
        }
    }
}

extension UIImage {

    convenience init?(bundleImageName name: String) {
        guard let img = UIImage(named: name, in: Bundle.main, compatibleWith: nil),
              let cgImage = img.cgImage else { return nil }
        self.init(cgImage: cgImage, scale: img.scale, orientation: img.imageOrientation)
    }

    private static let areaAverageCIContext = CIContext(options: [.cacheIntermediates: false])

    func dominantColor(sampleSize: Int = 64) -> UIColor? {
        let dim = max(1, min(sampleSize, 128))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: dim, height: dim), format: format)
        let scaled = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: CGSize(width: dim, height: dim)))
        }
        guard let cgImage = scaled.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        Self.areaAverageCIContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: cs
        )
        let a = CGFloat(bitmap[3]) / 255
        if a < 0.02 { return nil }
        var r = CGFloat(bitmap[0]) / 255
        var g = CGFloat(bitmap[1]) / 255
        var b = CGFloat(bitmap[2]) / 255
        if a > 0.001, a < 0.999 {
            r = min(1, r / a)
            g = min(1, g / a)
            b = min(1, b / a)
        }
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

