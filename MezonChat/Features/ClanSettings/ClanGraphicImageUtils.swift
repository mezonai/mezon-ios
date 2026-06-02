import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ClanGraphicImageUtils {
    private static let ciContext = CIContext(options: nil)

    static let emojiMaxDimension: CGFloat = 128

    static func isGIF(data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let bytes = [UInt8](data.prefix(6))
        return bytes.starts(with: [0x47, 0x49, 0x46, 0x38])
    }

    static func isAllowedEmojiUpload(contentType: String, data: Data) -> Bool {
        switch contentType.lowercased() {
        case "image/jpeg", "image/png", "image/gif":
            return true
        default:
            return isGIF(data: data)
        }
    }

    static func uploadDimensions(for image: UIImage, maxDimension: CGFloat = emojiMaxDimension) -> (width: Int, height: Int) {
        guard let rendered = renderForEmojiUpload(from: image, maxDimension: maxDimension) else {
            return (1, 1)
        }
        return (max(1, Int(rendered.size.width)), max(1, Int(rendered.size.height)))
    }

    static func resizedWebPData(from image: UIImage, maxDimension: CGFloat = emojiMaxDimension) -> Data? {
        guard #available(iOS 14.0, *) else { return nil }
        guard let rendered = renderForEmojiUpload(from: image, maxDimension: maxDimension),
              let cgImage = rendered.cgImage else {
            return nil
        }
        return encodeWebP(cgImage: cgImage)
    }

    static func resizedJPEGData(from image: UIImage, maxDimension: CGFloat = emojiMaxDimension, quality: CGFloat = 0.92) -> Data? {
        renderForEmojiUpload(from: image, maxDimension: maxDimension)?.jpegData(compressionQuality: quality)
    }

    static func renderForEmojiUpload(from image: UIImage, maxDimension: CGFloat = emojiMaxDimension) -> UIImage? {
        let normalized = normalizedOrientation(image)
        let pixelWidth = normalized.size.width * normalized.scale
        let pixelHeight = normalized.size.height * normalized.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let scale = min(maxDimension / pixelWidth, maxDimension / pixelHeight, 1)
        let targetSize = CGSize(
            width: max(1, floor(pixelWidth * scale)),
            height: max(1, floor(pixelHeight * scale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func encodeWebP(cgImage: CGImage) -> Data? {
        let utis: [CFString] = {
            if #available(iOS 14.0, *) {
                return [UTType.webP.identifier as CFString, "org.webmproject.webp" as CFString, "public.webp" as CFString]
            }
            return ["org.webmproject.webp" as CFString, "public.webp" as CFString]
        }()

        for uti in utis {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, uti, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, cgImage, nil)
            if CGImageDestinationFinalize(destination), data.length > 0 {
                return data as Data
            }

            let dataWithQuality = NSMutableData()
            guard let destinationWithQuality = CGImageDestinationCreateWithData(dataWithQuality, uti, 1, nil) else { continue }
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
            CGImageDestinationAddImage(destinationWithQuality, cgImage, options as CFDictionary)
            if CGImageDestinationFinalize(destinationWithQuality), dataWithQuality.length > 0 {
                return dataWithQuality as Data
            }
        }
        return nil
    }

    static func pngData(from image: UIImage) -> Data? {
        normalizedOrientation(image).pngData()
    }

    static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func blurredWatermarkedImage(
        from image: UIImage,
        watermarkText: String = "SOLD",
        blurRadius: CGFloat = 2
    ) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            if let blurred = image.applyingGaussianBlur(radius: blurRadius, context: ciContext) {
                blurred.draw(in: rect)
            } else {
                image.draw(in: rect)
            }

            let fontSize = max(size.width / 2, 12)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor(white: 0.5, alpha: 0.75)
            ]
            let text = watermarkText as NSString
            let textSize = text.size(withAttributes: attributes)
            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            cgContext.rotate(by: .pi / 4)
            text.draw(
                at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                withAttributes: attributes
            )
            cgContext.restoreGState()
        }
    }
}

private extension UIImage {
    func applyingGaussianBlur(radius: CGFloat, context: CIContext) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage else { return nil }

        let extent = ciImage.extent
        guard let cgImage = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}
