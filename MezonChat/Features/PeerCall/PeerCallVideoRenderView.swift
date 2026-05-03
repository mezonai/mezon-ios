import AVFoundation
import LiveKit
import LiveKitWebRTC
import MetalKit
import UIKit

final class PeerCallVideoRenderView: UIView {

    private let mtlVideoView: LKRTCMTLVideoView
    private let renderSurface: PeerCallSampleBufferRenderSurface
    private var attachedTrack: LKRTCVideoTrack?

    var isMirrored: Bool = false {
        didSet {
            mtlVideoView.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
            renderSurface.setMirrored(isMirrored)
        }
    }

    override init(frame: CGRect) {
        mtlVideoView = LKRTCMTLVideoView(frame: .zero)
        renderSurface = PeerCallSampleBufferRenderSurface(frame: .zero)
        super.init(frame: frame)
        mtlVideoView.translatesAutoresizingMaskIntoConstraints = false
        mtlVideoView.isEnabled = true
        mtlVideoView.videoContentMode = .scaleAspectFit
        mtlVideoView.contentMode = .scaleAspectFit
        renderSurface.translatesAutoresizingMaskIntoConstraints = false
        renderSurface.isUserInteractionEnabled = false
        addSubview(renderSurface)
        addSubview(mtlVideoView)
        NSLayoutConstraint.activate([
            renderSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderSurface.topAnchor.constraint(equalTo: topAnchor),
            renderSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            mtlVideoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtlVideoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mtlVideoView.topAnchor.constraint(equalTo: topAnchor),
            mtlVideoView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        backgroundColor = .black
        clipsToBounds = true
        isHidden = false
        configureEmbeddedMTKViewIfPresent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureEmbeddedMTKViewIfPresent()
    }

    private func configureEmbeddedMTKViewIfPresent() {
        guard let mtk = mtlVideoView.subviews.compactMap({ $0 as? MTKView }).first else { return }
        mtk.preferredFramesPerSecond = 60
        mtk.isPaused = false
        mtk.contentMode = .scaleAspectFit
        mtk.contentScaleFactor = contentScaleFactor
    }

    func attach(track: LKRTCVideoTrack?) {
        guard let track else {
            attachedTrack?.remove(renderSurface)
            attachedTrack?.remove(mtlVideoView)
            attachedTrack = nil
            renderSurface.flushContent()
            return
        }
        if attachedTrack === track {
            return
        }
        if let cur = attachedTrack, cur.trackId == track.trackId, cur !== track {
            cur.remove(renderSurface)
            cur.remove(mtlVideoView)
            attachedTrack = track
            renderSurface.flushContent()
            track.add(renderSurface)
            track.add(mtlVideoView)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configureEmbeddedMTKViewIfPresent()
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.mtlVideoView.setNeedsLayout()
                self.mtlVideoView.layoutIfNeeded()
                self.renderSurface.setNeedsLayout()
                self.renderSurface.layoutIfNeeded()
            }
            return
        }
        attachedTrack?.remove(renderSurface)
        attachedTrack?.remove(mtlVideoView)
        attachedTrack = track
        renderSurface.flushContent()
        track.add(renderSurface)
        track.add(mtlVideoView)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configureEmbeddedMTKViewIfPresent()
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.mtlVideoView.setNeedsLayout()
            self.mtlVideoView.layoutIfNeeded()
            self.renderSurface.setNeedsLayout()
            self.renderSurface.layoutIfNeeded()
        }
    }

    func refreshAttachedRenderers() {
        guard let track = attachedTrack else { return }
        track.remove(renderSurface)
        track.remove(mtlVideoView)
        renderSurface.flushContent()
        track.add(renderSurface)
        track.add(mtlVideoView)
        configureEmbeddedMTKViewIfPresent()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.mtlVideoView.setNeedsLayout()
            self.mtlVideoView.layoutIfNeeded()
            self.renderSurface.setNeedsLayout()
            self.renderSurface.layoutIfNeeded()
        }
    }

    deinit {
        attachedTrack?.remove(renderSurface)
        attachedTrack?.remove(mtlVideoView)
    }
}

private final class PeerCallSampleBufferRenderSurface: UIView, LKRTCVideoRenderer {

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var mirrored = false
    private var videoRotation: LKRTCVideoRotation = ._0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        displayLayer.videoGravity = .resizeAspect
        displayLayer.isOpaque = false
        displayLayer.backgroundColor = UIColor.clear.cgColor
        displayLayer.zPosition = 1
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setMirrored(_ value: Bool) {
        mirrored = value
        setNeedsLayout()
    }

    func flushContent() {
        displayLayer.flushAndRemoveImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var t = transform(for: videoRotation)
        if mirrored {
            t = CATransform3DConcat(t, CATransform3DMakeScale(-1, 1, 1))
        }
        displayLayer.transform = t
        displayLayer.frame = bounds
        displayLayer.removeAllAnimations()
    }

    func setSize(_: CGSize) {}

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        guard let frame else { return }
        guard let pixelBuffer = Self.extractPixelBuffer(frame: frame) else { return }
        guard let sampleBuffer = CMSampleBuffer.from(pixelBuffer) else { return }
        let rotation = frame.rotation
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.videoRotation != rotation {
                self.videoRotation = rotation
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
            if self.displayLayer.status == .failed {
                self.displayLayer.flushAndRemoveImage()
            }
            self.displayLayer.enqueue(sampleBuffer)
        }
    }

    private func transform(for rotation: LKRTCVideoRotation) -> CATransform3D {
        switch rotation {
        case ._0:
            CATransform3DIdentity
        case ._90:
            CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
        case ._180:
            CATransform3DMakeRotation(.pi, 0, 0, 1)
        case ._270:
            CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        @unknown default:
            CATransform3DIdentity
        }
    }

    private static func extractPixelBuffer(frame: LKRTCVideoFrame) -> CVPixelBuffer? {
        if let cv = frame.buffer as? LKRTCCVPixelBuffer {
            return pixelBuffer(fromCVBuffer: cv, frame: frame)
        }
        if let i420 = frame.buffer as? LKRTCI420Buffer {
            return pixelBuffer(fromI420: i420)
        }
        let converted = frame.buffer.toI420()
        if let i420 = converted as? LKRTCI420Buffer {
            return pixelBuffer(fromI420: i420)
        }
        let i420Frame = frame.newI420()
        return extractPixelBuffer(frame: i420Frame)
    }

    private static func pixelBuffer(fromCVBuffer cv: LKRTCCVPixelBuffer, frame: LKRTCVideoFrame) -> CVPixelBuffer? {
        let pb = cv.pixelBuffer
        if !cv.requiresCropping(), !cv.requiresScaling(toWidth: frame.width, height: frame.height) {
            return pb
        }
        let w = frame.width
        let h = frame.height
        let tmpCount = Int(cv.bufferSizeForCroppingAndScaling(toWidth: w, height: h))
        var output: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(w), Int(h), CVPixelBufferGetPixelFormatType(pb), attrs as CFDictionary, &output) == kCVReturnSuccess,
              let output
        else { return nil }
        if tmpCount <= 0 {
            guard cv.cropAndScale(to: output, withTempBuffer: nil) else { return nil }
            return output
        }
        var tmp = [UInt8](repeating: 0, count: tmpCount)
        return tmp.withUnsafeMutableBytes { raw -> CVPixelBuffer? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            guard cv.cropAndScale(to: output, withTempBuffer: base) else { return nil }
            return output
        }
    }

    private static func pixelBuffer(fromI420 i420: LKRTCI420Buffer) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(i420.width),
            Int(i420.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else { return nil }
        CVPixelBufferLockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
        let pixelFormat = CVPixelBufferGetPixelFormatType(output)
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        {
            let dstY = CVPixelBufferGetBaseAddressOfPlane(output, 0)
            let dstYStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
            let dstUV = CVPixelBufferGetBaseAddressOfPlane(output, 1)
            let dstUVStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
            LKRTCYUVHelper.i420(
                toNV12: i420.dataY,
                srcStrideY: i420.strideY,
                srcU: i420.dataU,
                srcStrideU: i420.strideU,
                srcV: i420.dataV,
                srcStrideV: i420.strideV,
                dstY: dstY,
                dstStrideY: Int32(dstYStride),
                dstUV: dstUV,
                dstStrideUV: Int32(dstUVStride),
                width: i420.width,
                height: i420.height
            )
        } else {
            let dst = CVPixelBufferGetBaseAddress(output)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
            if pixelFormat == kCVPixelFormatType_32BGRA {
                LKRTCYUVHelper.i420(
                    toARGB: i420.dataY,
                    srcStrideY: i420.strideY,
                    srcU: i420.dataU,
                    srcStrideU: i420.strideU,
                    srcV: i420.dataV,
                    srcStrideV: i420.strideV,
                    dstARGB: dst,
                    dstStrideARGB: Int32(bytesPerRow),
                    width: i420.width,
                    height: i420.height
                )
            } else if pixelFormat == kCVPixelFormatType_32ARGB {
                LKRTCYUVHelper.i420(
                    toBGRA: i420.dataY,
                    srcStrideY: i420.strideY,
                    srcU: i420.dataU,
                    srcStrideU: i420.strideU,
                    srcV: i420.dataV,
                    srcStrideV: i420.strideV,
                    dstBGRA: dst,
                    dstStrideBGRA: Int32(bytesPerRow),
                    width: i420.width,
                    height: i420.height
                )
            }
        }
        CVPixelBufferUnlockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
        return output
    }
}
