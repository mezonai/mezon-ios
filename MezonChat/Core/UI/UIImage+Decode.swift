import UIKit
import ImageIO

extension UIImage {

    static func decodeImage(from data: Data) -> UIImage? {
        if let img = UIImage(data: data) { return img }
        return decodeWithImageIO(data)
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
