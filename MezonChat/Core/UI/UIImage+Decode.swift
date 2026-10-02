import UIKit
import ImageIO

extension UIImage {

    static func decodeImage(from data: Data) -> UIImage? {
        if let img = UIImage(data: data) { return img }
        return decodeWithImageIO(data)
    }

    static func decompressedImage(from data: Data) -> UIImage? {
        if let animated = animatedImage(from: data) {
            return animated
        }
        guard let image = decodeImage(from: data) else { return nil }
        if let frames = image.images, frames.count > 1 {
            return image
        }
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

    static func avatarPreviewImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = avatarThumbnail(
                from: source,
                at: 0,
                maxPixelSize: maxPixelSize
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func optimizedAvatarImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        if count == 1 {
            guard let cgImage = avatarThumbnail(
                from: source,
                at: 0,
                maxPixelSize: maxPixelSize
            ) else { return nil }
            return UIImage(cgImage: cgImage)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var duration: Double = 0

        for index in 0..<count {
            guard let cgImage = avatarThumbnail(
                from: source,
                at: index,
                maxPixelSize: maxPixelSize
            ) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += optimizedAvatarFrameDuration(source: source, index: index)
        }

        guard frames.count > 1 else { return frames.first }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    static func optimizedAvatarCacheData(from image: UIImage) -> Data? {
        guard let frames = image.images, frames.count > 1 else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "com.compuserve.gif" as CFString,
            frames.count,
            nil
        ) else { return nil }

        let gifProperties: NSDictionary = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ]
        CGImageDestinationSetProperties(destination, gifProperties)

        let frameDelay = max(image.duration / Double(frames.count), 0.02)
        let frameProperties: NSDictionary = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ],
        ]
        for frame in frames {
            guard let cgImage = frame.cgImage else { continue }
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
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

    private static func avatarThumbnail(
        from source: CGImageSource,
        at index: Int,
        maxPixelSize: Int
    ) -> CGImage? {
        let options: NSDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true as NSNumber,
            kCGImageSourceCreateThumbnailWithTransform: true as NSNumber,
            kCGImageSourceShouldCacheImmediately: true as NSNumber,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1) as NSNumber,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private static func optimizedAvatarFrameDuration(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
            return 0.1
        }
        let delay: Double
        if let webp = props["{WebP}"] as? [String: Any],
           let value = webp["DelayTime"] as? Double {
            delay = value
        } else if let gif = props["{GIF}"] as? [String: Any],
                  let value = gif["DelayTime"] as? Double {
            delay = value
        } else {
            delay = 0.1
        }
        return max(delay, 0.02)
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
