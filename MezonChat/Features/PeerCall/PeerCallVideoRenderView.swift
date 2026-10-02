import AVFoundation
import WebRTC
import MetalKit
import UIKit

final class PeerCallVideoRenderView: UIView {

    enum RenderContentMode {
        case fit
        case fill
    }

    private let mtlVideoView: RTCMTLVideoView
    private let renderSurface: PeerCallSampleBufferRenderSurface?
    private var attachedTrack: RTCVideoTrack?
    private var lastReplaySize: CGSize = .zero

    private var renderers: [RTCVideoRenderer] {
        guard let renderSurface else { return [mtlVideoView] }
        return [renderSurface, mtlVideoView]
    }

    var isMirrored: Bool = false {
        didSet {
            mtlVideoView.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
            renderSurface?.setMirrored(isMirrored)
        }
    }

    var renderContentMode: RenderContentMode = .fit {
        didSet {
            let fill = renderContentMode == .fill
            mtlVideoView.videoContentMode = fill ? .scaleAspectFill : .scaleAspectFit
            mtlVideoView.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
            renderSurface?.setVideoGravity(fill ? .resizeAspectFill : .resizeAspect)
            configureEmbeddedMTKViewIfPresent()
        }
    }

    override convenience init(frame: CGRect) {
        self.init(frame: frame, sampleBufferSurface: true)
    }

    convenience init(sampleBufferSurface: Bool) {
        self.init(frame: .zero, sampleBufferSurface: sampleBufferSurface)
    }

    init(frame: CGRect, sampleBufferSurface: Bool) {
        mtlVideoView = RTCMTLVideoView(frame: .zero)
        renderSurface = sampleBufferSurface ? PeerCallSampleBufferRenderSurface(frame: .zero) : nil
        super.init(frame: frame)
        mtlVideoView.translatesAutoresizingMaskIntoConstraints = false
        mtlVideoView.isEnabled = true
        mtlVideoView.videoContentMode = .scaleAspectFit
        mtlVideoView.contentMode = .scaleAspectFit
        if let renderSurface {
            renderSurface.translatesAutoresizingMaskIntoConstraints = false
            renderSurface.isUserInteractionEnabled = false
            addSubview(renderSurface)
            NSLayoutConstraint.activate([
                renderSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
                renderSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
                renderSurface.topAnchor.constraint(equalTo: topAnchor),
                renderSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        addSubview(mtlVideoView)
        NSLayoutConstraint.activate([
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
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastReplaySize else { return }
        lastReplaySize = bounds.size
        replayAttachedFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        setNeedsLayout()
        layoutIfNeeded()
        replayAttachedFrame()
    }

    private func replayAttachedFrame() {
        guard let track = attachedTrack, bounds.width > 0, bounds.height > 0 else { return }
        VideoTrackLastFrameStore.replayLastFrame(of: track, to: renderers)
    }

    private func configureEmbeddedMTKViewIfPresent() {
        guard let mtk = mtlVideoView.subviews.compactMap({ $0 as? MTKView }).first else { return }
        mtk.preferredFramesPerSecond = 60
        mtk.isPaused = attachedTrack == nil
        mtk.contentMode = renderContentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        mtk.contentScaleFactor = contentScaleFactor
    }

    private func subscribe(_ track: RTCVideoTrack) {
        for renderer in renderers {
            track.add(renderer)
        }
    }

    private func unsubscribe(_ track: RTCVideoTrack?) {
        guard let track else { return }
        for renderer in renderers {
            track.remove(renderer)
        }
    }

    func attach(track: RTCVideoTrack?) {
        guard let track else {
            unsubscribe(attachedTrack)
            attachedTrack = nil
            lastReplaySize = .zero
            mtlVideoView.isEnabled = false
            configureEmbeddedMTKViewIfPresent()
            renderSurface?.flushContent()
            return
        }
        if attachedTrack === track {
            return
        }
        if let cur = attachedTrack, cur.trackId == track.trackId, cur !== track {
            unsubscribe(cur)
            attachedTrack = track
            mtlVideoView.isEnabled = true
            renderSurface?.flushContent()
            configureEmbeddedMTKViewIfPresent()
            layoutIfNeeded()
            subscribe(track)
            VideoTrackLastFrameStore.replayLastFrame(of: track, to: renderers)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configureEmbeddedMTKViewIfPresent()
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.mtlVideoView.setNeedsLayout()
                self.mtlVideoView.layoutIfNeeded()
                self.renderSurface?.setNeedsLayout()
                self.renderSurface?.layoutIfNeeded()
                self.replayAttachedFrame()
            }
            return
        }
        unsubscribe(attachedTrack)
        attachedTrack = track
        mtlVideoView.isEnabled = true
        renderSurface?.flushContent()
        configureEmbeddedMTKViewIfPresent()
        layoutIfNeeded()
        subscribe(track)
        VideoTrackLastFrameStore.replayLastFrame(of: track, to: renderers)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configureEmbeddedMTKViewIfPresent()
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.mtlVideoView.setNeedsLayout()
            self.mtlVideoView.layoutIfNeeded()
            self.renderSurface?.setNeedsLayout()
            self.renderSurface?.layoutIfNeeded()
            self.replayAttachedFrame()
        }
    }

    func refreshAttachedRenderers() {
        guard let track = attachedTrack else { return }
        unsubscribe(track)
        renderSurface?.flushContent()
        configureEmbeddedMTKViewIfPresent()
        layoutIfNeeded()
        subscribe(track)
        VideoTrackLastFrameStore.replayLastFrame(of: track, to: renderers)
        configureEmbeddedMTKViewIfPresent()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.mtlVideoView.setNeedsLayout()
            self.mtlVideoView.layoutIfNeeded()
            self.renderSurface?.setNeedsLayout()
            self.renderSurface?.layoutIfNeeded()
            self.replayAttachedFrame()
        }
    }

    deinit {
        if let renderSurface {
            attachedTrack?.remove(renderSurface)
        }
        attachedTrack?.remove(mtlVideoView)
    }
}

final class VideoTrackFrameKeeper: NSObject, RTCVideoRenderer {

    private let lock = NSLock()
    private var frame: RTCVideoFrame?
    private var frameUptime: TimeInterval = 0
    weak var track: RTCVideoTrack?

    var lastFrame: RTCVideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        return frame
    }

    var lastFrameUptime: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return frame == nil ? nil : frameUptime
    }

    func clear() {
        lock.lock()
        frame = nil
        frameUptime = 0
        lock.unlock()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        lock.lock()
        self.frame = frame
        frameUptime = uptime
        lock.unlock()
    }
}

@MainActor
enum VideoTrackLastFrameStore {

    // receiver.track creates new ObjC wrappers. WebRTC's isEqual compares the
    // native track; trackId alone also cannot distinguish a replacement source.
    private static var keepers: [VideoTrackFrameKeeper] = []
    private static var replayCount: Int64 = 0

    static func cachedFrame(of track: RTCVideoTrack) -> RTCVideoFrame? {
        guard let keeper = keeper(for: track) else { return nil }
        return keeper.lastFrame
    }

    static func cachedFrameUptime(of track: RTCVideoTrack) -> TimeInterval? {
        guard let keeper = keeper(for: track) else { return nil }
        return keeper.lastFrameUptime
    }

    static func observe(_ track: RTCVideoTrack) -> VideoTrackFrameKeeper {
        keepers.removeAll { $0.track == nil }
        if let keeper = keeper(for: track) { return keeper }
        let keeper = VideoTrackFrameKeeper()
        keeper.track = track
        track.add(keeper)
        keepers.append(keeper)
        return keeper
    }

    private static func keeper(for track: RTCVideoTrack) -> VideoTrackFrameKeeper? {
        keepers.first { $0.track?.isEqual(track) == true }
    }

    /// Keep the wrapper that owns the frame observer alive in the session/UI.
    /// This also keeps recovery identity stable across receiver snapshots.
    static func canonicalTrack(_ track: RTCVideoTrack) -> RTCVideoTrack {
        observe(track).track ?? track
    }

    static func clearFrame(of track: RTCVideoTrack) {
        keeper(for: track)?.clear()
    }

    static func replayLastFrame(of track: RTCVideoTrack, to renderers: [RTCVideoRenderer]) {
        guard let frame = observe(track).lastFrame else { return }
        replayCount += 1
        let replay = RTCVideoFrame(buffer: frame.buffer, rotation: frame.rotation, timeStampNs: frame.timeStampNs + replayCount)
        let rotated = frame.rotation == ._90 || frame.rotation == ._270
        let size = rotated
            ? CGSize(width: CGFloat(frame.height), height: CGFloat(frame.width))
            : CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
        for renderer in renderers {
            renderer.setSize(size)
            renderer.renderFrame(replay)
        }
    }
}

private extension CMSampleBuffer {
    static func from(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return nil }
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachmentsArray) > 0 {
            let attachments = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                attachments,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sampleBuffer
    }
}

private final class PeerCallSampleBufferRenderSurface: UIView, RTCVideoRenderer {

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var mirrored = false
    private var videoRotation: RTCVideoRotation = ._0

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

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        displayLayer.videoGravity = gravity
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

    func renderFrame(_ frame: RTCVideoFrame?) {
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

    private func transform(for rotation: RTCVideoRotation) -> CATransform3D {
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

    private static func extractPixelBuffer(frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let cv = frame.buffer as? RTCCVPixelBuffer {
            return pixelBuffer(fromCVBuffer: cv, frame: frame)
        }
        if let i420 = frame.buffer as? RTCI420Buffer {
            return pixelBuffer(fromI420: i420)
        }
        let converted = frame.buffer.toI420()
        if let i420 = converted as? RTCI420Buffer {
            return pixelBuffer(fromI420: i420)
        }
        let i420Frame = frame.newI420()
        return extractPixelBuffer(frame: i420Frame)
    }

    private static func pixelBuffer(fromCVBuffer cv: RTCCVPixelBuffer, frame: RTCVideoFrame) -> CVPixelBuffer? {
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

    private static func pixelBuffer(fromI420 i420: RTCI420Buffer) -> CVPixelBuffer? {
        let width = Int(i420.width)
        let height = Int(i420.height)
        guard width > 0, height > 0 else { return nil }
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            options as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else { return nil }
        CVPixelBufferLockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0)) }
        guard let dstYBase = CVPixelBufferGetBaseAddressOfPlane(output, 0),
              let dstUVBase = CVPixelBufferGetBaseAddressOfPlane(output, 1)
        else { return nil }
        let dstYStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        let dstUVStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
        let dstY = dstYBase.assumingMemoryBound(to: UInt8.self)
        let dstUV = dstUVBase.assumingMemoryBound(to: UInt8.self)
        let srcY = i420.dataY
        let srcU = i420.dataU
        let srcV = i420.dataV
        let srcYStride = Int(i420.strideY)
        let srcUStride = Int(i420.strideU)
        let srcVStride = Int(i420.strideV)
        for row in 0..<height {
            memcpy(dstY + row * dstYStride, srcY + row * srcYStride, width)
        }
        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        for row in 0..<chromaHeight {
            let uRow = srcU + row * srcUStride
            let vRow = srcV + row * srcVStride
            let uvRow = dstUV + row * dstUVStride
            for col in 0..<chromaWidth {
                uvRow[col * 2] = uRow[col]
                uvRow[col * 2 + 1] = vRow[col]
            }
        }
        return output
    }
}
