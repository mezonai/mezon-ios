import UIKit
import ImageIO

extension UIImage {

    static func decodeImage(from data: Data) -> UIImage? {
        if let img = UIImage(data: data) { return img }
        return decodeWithImageIO(data)
    }

    static func decompressedImage(from data: Data) -> UIImage? {
        guard let image = decodeImage(from: data) else { return nil }
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let decoded = ctx.makeImage() else { return image }
        return UIImage(cgImage: decoded, scale: image.scale, orientation: image.imageOrientation)
    }

    private static let heicTypeHint = "public.heic" as CFString

    private static func decodeWithImageIO(_ data: Data) -> UIImage? {
        var source: CGImageSource? = CGImageSourceCreateWithData(data as CFData, nil)
        if source == nil {
            let heicHint = [kCGImageSourceTypeIdentifierHint: heicTypeHint] as CFDictionary
            source = CGImageSourceCreateWithData(data as CFData, heicHint)
        }
        guard let src = source, CGImageSourceGetCount(src) > 0 else { return nil }
        let createImageOptions: NSDictionary = [kCGImageSourceShouldCache: false as NSNumber]
        if let cgImage = CGImageSourceCreateImageAtIndex(src, 0, createImageOptions as CFDictionary) {
            let orientation = imageOrientation(from: src)
            return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        }
        let thumbnailOptions: NSDictionary = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true as NSNumber,
            kCGImageSourceCreateThumbnailWithTransform: true as NSNumber,
            kCGImageSourceThumbnailMaxPixelSize: 4096 as NSNumber
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbnailOptions as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }

    static func animatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        var images: [UIImage] = []
        var duration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))

            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any] {
                let delay: Double
                if let webp = props["{WebP}"] as? [String: Any],
                   let d = webp["DelayTime"] as? Double {
                    delay = d
                } else if let gif = props["{GIF}"] as? [String: Any],
                          let d = gif["DelayTime"] as? Double {
                    delay = d
                } else {
                    delay = 0.1
                }
                duration += max(delay, 0.02)
            } else {
                duration += 0.1
            }
        }

        guard images.count > 1 else { return nil }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    private static func imageOrientation(from source: CGImageSource) -> UIImage.Orientation {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let value = props[kCGImagePropertyOrientation] as? NSNumber else { return .up }
        switch value.intValue {
        case 1: return .up
        case 3: return .down
        case 8: return .left
        case 6: return .right
        case 2: return .upMirrored
        case 4: return .downMirrored
        case 5: return .leftMirrored
        case 7: return .rightMirrored
        default: return .up
        }
    }
}
