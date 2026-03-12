import UIKit

extension UIImage {

    convenience init?(bundleImageName name: String) {
        guard let img = UIImage(named: name, in: Bundle.main, compatibleWith: nil),
              let cgImage = img.cgImage else { return nil }
        self.init(cgImage: cgImage, scale: img.scale, orientation: img.imageOrientation)
    }
}

