import AVFoundation
import CoreImage
import Foundation
import ImageIO
import LiveKit

final class VoiceFrontCameraPublishFlipProcessor: NSObject, VideoProcessor {
    static let shared = VoiceFrontCameraPublishFlipProcessor()

    private let ciContext = CIContext(options: [
        CIContextOption.useSoftwareRenderer: false,
        CIContextOption.cacheIntermediates: false,
    ])

    private override init() {
        super.init()
    }

    private static func cgImageOrientation(for rotation: VideoRotation) -> CGImagePropertyOrientation {
        switch rotation {
        case ._0: return .up
        case ._90: return .right
        case ._180: return .down
        case ._270: return .left
        }
    }

    func process(frame: VideoFrame) -> VideoFrame? {
        guard let src = frame.toCVPixelBuffer() else { return frame }
        let fmt = CVPixelBufferGetPixelFormatType(src)

        var image = CIImage(cvPixelBuffer: src)
        image = image.oriented(Self.cgImageOrientation(for: frame.rotation))
        let e0 = image.extent
        image = image.transformed(by: CGAffineTransform(translationX: -e0.minX, y: -e0.minY))
        let w = image.extent.width
        let h = image.extent.height
        let mirrored = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))

        let outW = max(1, Int(w.rounded(.up)))
        let outH = max(1, Int(h.rounded(.up)))

        var dst: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: fmt,
            kCVPixelBufferWidthKey: outW,
            kCVPixelBufferHeightKey: outH,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, outW, outH, fmt, attrs as CFDictionary, &dst) == kCVReturnSuccess,
              let out = dst
        else { return frame }

        guard CVPixelBufferLockBaseAddress(out, []) == kCVReturnSuccess else { return frame }
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        ciContext.render(mirrored, to: out)

        let buf = CVPixelVideoBuffer(pixelBuffer: out)
        return VideoFrame(
            dimensions: Dimensions(width: Int32(outW), height: Int32(outH)),
            rotation: ._0,
            timeStampNs: frame.timeStampNs,
            buffer: buf
        )
    }
}
