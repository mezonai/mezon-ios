import CoreImage
import CoreVideo
import Foundation
import ImageIO
import WebRTC

final class ScreenShareFrameReceiver {
    var onConnectionChanged: ((Bool) -> Void)?

    private static let readChunkSize = 64 * 1024
    private static let maxReadsPerEvent = 16
    private static let maxPixelBuffers = 6
    private static let repeatInterval: TimeInterval = 0.5

    private let queue = DispatchQueue(label: "mezon.screenshare.receiver")
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let readChunk = UnsafeMutableRawPointer.allocate(
        byteCount: ScreenShareFrameReceiver.readChunkSize,
        alignment: 1
    )
    private var listenSource: DispatchSourceRead?
    private var clientSource: DispatchSourceRead?
    private var repeatTimer: DispatchSourceTimer?
    private var pending = Data()
    private var pendingHeader: (payloadLength: Int, orientation: UInt32)?
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0
    private var lastFrame: (buffer: CVPixelBuffer, rotation: RTCVideoRotation)?
    private var lastFrameUptime: TimeInterval = 0
    private var frameHandler: ((RTCVideoFrame) -> Void)?

    deinit {
        listenSource?.cancel()
        clientSource?.cancel()
        repeatTimer?.cancel()
        readChunk.deallocate()
    }

    func start() {
        queue.async { self.openListener() }
    }

    func stop() {
        queue.async {
            self.dropClient()
            self.listenSource?.cancel()
            self.listenSource = nil
        }
    }

    func disconnectClient() {
        queue.async { self.dropClient() }
    }

    func setFrameHandler(_ handler: ((RTCVideoFrame) -> Void)?) {
        queue.async { self.frameHandler = handler }
    }

    private func openListener() {
        guard listenSource == nil, let path = ScreenShareBroadcastChannel.socketPath else { return }
        unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = ScreenShareBroadcastChannel.socketAddress(path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else {
            Darwin.close(fd)
            return
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient(listener: fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        listenSource = source
        source.resume()
    }

    private func acceptClient(listener: Int32) {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return }
        guard clientSource == nil else {
            Darwin.close(fd)
            return
        }
        ScreenShareBroadcastChannel.disableSigPipe(fd)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        pending.removeAll()
        pendingHeader = nil
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readClient(fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        clientSource = source
        source.resume()
        startRepeatTimer()
        notifyConnection(true)
    }

    private func readClient(_ fd: Int32) {
        for _ in 0..<Self.maxReadsPerEvent {
            let count = Darwin.read(fd, readChunk, Self.readChunkSize)
            if count > 0 {
                pending.append(readChunk.assumingMemoryBound(to: UInt8.self), count: count)
                drainFrames()
                guard clientSource != nil else { return }
                continue
            }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { break }
            dropClient()
            return
        }
    }

    private func drainFrames() {
        var latest: (payload: Data, orientation: UInt32)?
        while true {
            if pendingHeader == nil {
                guard pending.count >= ScreenShareBroadcastChannel.headerSize else { break }
                guard let header = ScreenShareBroadcastChannel.decodeHeader(
                    pending.prefix(ScreenShareBroadcastChannel.headerSize)
                ) else {
                    dropClient()
                    return
                }
                pending.removeFirst(ScreenShareBroadcastChannel.headerSize)
                pendingHeader = header
            }
            guard let header = pendingHeader, pending.count >= header.payloadLength else { break }
            latest = (Data(pending.prefix(header.payloadLength)), header.orientation)
            pending.removeFirst(header.payloadLength)
            pendingHeader = nil
        }
        if let latest {
            autoreleasepool { decode(latest.payload, orientation: latest.orientation) }
        }
    }

    private func decode(_ payload: Data, orientation: UInt32) {
        guard let image = CIImage(data: payload) else { return }
        let width = Int(image.extent.width) & ~1
        let height = Int(image.extent.height) & ~1
        guard width > 0, height > 0, let buffer = makePixelBuffer(width: width, height: height) else { return }
        imageContext.render(image, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)
        let rotation = Self.rotation(for: orientation)
        lastFrame = (buffer, rotation)
        deliver(buffer, rotation: rotation)
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pixelBufferPool == nil || poolWidth != width || poolHeight != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            pixelBufferPool = pool
            poolWidth = width
            poolHeight = height
        }
        guard let pool = pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        let auxiliaryAttributes = [
            kCVPixelBufferPoolAllocationThresholdKey as String: Self.maxPixelBuffers,
        ] as CFDictionary
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxiliaryAttributes, &buffer)
        return buffer
    }

    private func deliver(_ buffer: CVPixelBuffer, rotation: RTCVideoRotation) {
        let uptime = ProcessInfo.processInfo.systemUptime
        lastFrameUptime = uptime
        let frame = RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: buffer),
            rotation: rotation,
            timeStampNs: Int64(uptime * 1_000_000_000)
        )
        frameHandler?(frame)
    }

    private func startRepeatTimer() {
        repeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.repeatInterval, repeating: Self.repeatInterval)
        timer.setEventHandler { [weak self] in
            guard let self, let frame = self.lastFrame,
                  ProcessInfo.processInfo.systemUptime - self.lastFrameUptime >= Self.repeatInterval else { return }
            self.deliver(frame.buffer, rotation: frame.rotation)
        }
        repeatTimer = timer
        timer.resume()
    }

    private func dropClient() {
        guard let source = clientSource else { return }
        source.cancel()
        clientSource = nil
        repeatTimer?.cancel()
        repeatTimer = nil
        pending.removeAll()
        pendingHeader = nil
        lastFrame = nil
        pixelBufferPool = nil
        notifyConnection(false)
    }

    private func notifyConnection(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChanged?(connected)
        }
    }

    private static func rotation(for orientation: UInt32) -> RTCVideoRotation {
        switch CGImagePropertyOrientation(rawValue: orientation) {
        case .left?: return ._90
        case .down?: return ._180
        case .right?: return ._270
        default: return ._0
        }
    }
}
