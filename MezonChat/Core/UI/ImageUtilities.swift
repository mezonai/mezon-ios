import UIKit

// MARK: - UIImage bundleImageName (Telegram-style)

extension UIImage {

    convenience init?(bundleImageName name: String) {
        guard let img = UIImage(named: name, in: Bundle.main, compatibleWith: nil),
              let cgImage = img.cgImage else { return nil }
        self.init(cgImage: cgImage, scale: img.scale, orientation: img.imageOrientation)
    }
}

// MARK: - generateTintedImage (Telegram-style)

/// Renders image with given tint color. Uses image alpha as mask.
func generateTintedImage(image: UIImage?, color: UIColor, backgroundColor: UIColor? = nil) -> UIImage? {
    guard let image = image else { return nil }

    let imageSize = image.size

    UIGraphicsBeginImageContextWithOptions(imageSize, backgroundColor != nil, image.scale)
    guard let context = UIGraphicsGetCurrentContext() else {
        UIGraphicsEndImageContext()
        return nil
    }

    if let backgroundColor = backgroundColor {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))
    }

    let imageRect = CGRect(origin: .zero, size: imageSize)
    context.saveGState()
    context.translateBy(x: imageRect.midX, y: imageRect.midY)
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: -imageRect.midX, y: -imageRect.midY)

    if let cgImage = image.cgImage {
        context.clip(to: imageRect, mask: cgImage)
        context.setFillColor(color.cgColor)
        context.fill(imageRect)
    }
    context.restoreGState()

    let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return tintedImage
}
