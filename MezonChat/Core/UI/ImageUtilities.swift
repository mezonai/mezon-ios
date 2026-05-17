import CoreImage
import UIKit

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

