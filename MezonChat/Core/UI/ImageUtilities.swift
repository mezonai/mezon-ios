import UIKit

extension UIImage {

    convenience init?(bundleImageName name: String) {
        guard let img = UIImage(named: name, in: Bundle.main, compatibleWith: nil),
              let cgImage = img.cgImage else { return nil }
        self.init(cgImage: cgImage, scale: img.scale, orientation: img.imageOrientation)
    }

    func dominantColor(sampleSize: Int = 64) -> UIColor? {
        let dim = sampleSize
        guard dim > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim))
        let scaled = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: CGSize(width: dim, height: dim)))
        }
        guard let cgImage = scaled.cgImage else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bytesPerRow: dim * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dim, height: dim))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: dim * dim * 4)

        var buckets: [Int: Int] = [:]
        let step = max(1, (dim * dim) / 256)
        for i in stride(from: 0, to: dim * dim, by: step) {
            let offset = i * 4
            let r = Int(ptr[offset]) / 32
            let g = Int(ptr[offset + 1]) / 32
            let b = Int(ptr[offset + 2]) / 32
            let a = ptr[offset + 3]
            if a < 128 { continue }
            let key = (r << 10) | (g << 5) | b
            buckets[key, default: 0] += 1
        }

        guard let (key, _) = buckets.max(by: { $0.value < $1.value }) else { return nil }
        let r = ((key >> 10) & 31) * 32
        let g = ((key >> 5) & 31) * 32
        let b = (key & 31) * 32
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

