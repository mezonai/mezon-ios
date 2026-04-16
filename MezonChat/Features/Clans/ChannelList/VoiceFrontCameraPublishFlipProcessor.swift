import AVFoundation
import CoreImage
import Foundation
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

    func process(frame: VideoFrame) -> VideoFrame? {
        guard let src = frame.toCVPixelBuffer() else { return frame }
        let fmt = CVPixelBufferGetPixelFormatType(src)
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)

        var dst: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: fmt,
            kCVPixelBufferWidthKey: w,
            kCVPixelBufferHeightKey: h,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt, attrs as CFDictionary, &dst) == kCVReturnSuccess,
              let out = dst
        else { return frame }

        let image = CIImage(cvPixelBuffer: src)
        let flipped = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.width, ty: 0))

        guard CVPixelBufferLockBaseAddress(out, []) == kCVReturnSuccess else { return frame }
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        ciContext.render(flipped, to: out)

        let buf = CVPixelVideoBuffer(pixelBuffer: out)
        return VideoFrame(
            dimensions: frame.dimensions,
            rotation: frame.rotation,
            timeStampNs: frame.timeStampNs,
            buffer: buf
        )
    }
}
