import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ReplayKit

final class ScreenShareFrameSender {
    enum EndReason {
        case appUnavailable
        case stoppedByApp
    }

    var onEnded: ((EndReason) -> Void)?

    private static let connectRetryDelay: TimeInterval = 0.25
    private static let maxConnectAttempts = 40
    private struct Quality {
        let minFrameInterval: TimeInterval
        let maxLongSide: CGFloat
        let jpegQuality: CGFloat
    }

    private static let qualities = [
        Quality(minFrameInterval: 1.0 / 15, maxLongSide: 960, jpegQuality: 0.75),
        Quality(minFrameInterval: 1.0 / 10, maxLongSide: 800, jpegQuality: 0.70),
        Quality(minFrameInterval: 1.0 / 7.5, maxLongSide: 640, jpegQuality: 0.65),
    ]
    private static let slowFramesToReduceQuality = 3
    private static let fastFramesToIncreaseQuality = 60

    private let queue = DispatchQueue(label: "mezon.screenshare.sender")
    private let encodingQueue = DispatchQueue(label: "mezon.screenshare.encoder", qos: .utility)
    private let lock = NSLock()
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var descriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var sourceGroup: DispatchGroup?
    private var pendingWrite: (header: Data, payload: Data, offset: Int, startedAt: TimeInterval)?
    private var connectAttempts = 0
    private var stopped = false
    private var connected = false
    private var writing = false
    private var lastFrameUptime: TimeInterval = 0
    private var qualityIndex = 0
    private var slowFrameCount = 0
    private var fastFrameCount = 0

    func start() {
        queue.async { self.attemptConnection() }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.closeConnection()
        }
    }

    func send(_ sampleBuffer: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let quality = Self.qualities[qualityIndex]
        let ready = connected && !writing && now - lastFrameUptime >= quality.minFrameInterval
        if ready {
            writing = true
            lastFrameUptime = now
        }
        lock.unlock()
        guard ready else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            finishWriting()
            return
        }
        let orientation = Self.orientation(of: sampleBuffer)
        encodingQueue.async {
            guard let payload = autoreleasepool(invoking: { self.jpegData(from: pixelBuffer, quality: quality) }) else {
                self.finishWriting()
                return
            }
            let header = ScreenShareBroadcastChannel.encodeHeader(
                payloadLength: payload.count,
                orientation: orientation
            )
            self.queue.async {
                guard self.descriptor >= 0 else {
                    self.finishWriting()
                    return
                }
                self.pendingWrite = (header, payload, 0, now)
                self.flushPendingWrite()
            }
        }
    }

    private func finishWriting() {
        lock.lock()
        writing = false
        lock.unlock()
    }

    private func setConnected(_ value: Bool) {
        lock.lock()
        connected = value
        lock.unlock()
    }

    private func attemptConnection() {
        guard !stopped, descriptor < 0 else { return }
        guard let path = ScreenShareBroadcastChannel.socketPath else {
            end(.appUnavailable)
            return
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd >= 0 {
            ScreenShareBroadcastChannel.disableSigPipe(fd)
            var address = ScreenShareBroadcastChannel.socketAddress(path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result == 0 {
                didConnect(fd)
                return
            }
            Darwin.close(fd)
        }
        connectAttempts += 1
        guard connectAttempts < Self.maxConnectAttempts else {
            end(.appUnavailable)
            return
        }
        queue.asyncAfter(deadline: .now() + Self.connectRetryDelay) { self.attemptConnection() }
    }

    private func didConnect(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            Darwin.close(fd)
            end(.appUnavailable)
            return
        }
        descriptor = fd
        let group = DispatchGroup()
        sourceGroup = group
        group.enter()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            if count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
                self?.handleRemoteClosed()
            }
        }
        source.setCancelHandler {
            group.leave()
        }
        readSource = source
        source.resume()
        setConnected(true)
    }

    private func handleRemoteClosed() {
        guard descriptor >= 0 else { return }
        closeConnection()
        if !stopped { end(.stoppedByApp) }
    }

    private func closeConnection() {
        setConnected(false)
        let fd = descriptor
        let group = sourceGroup
        writeSource?.cancel()
        writeSource = nil
        pendingWrite = nil
        readSource?.cancel()
        readSource = nil
        sourceGroup = nil
        descriptor = -1
        if fd >= 0, let group {
            // Both dispatch sources must stop monitoring the descriptor before it is closed.
            group.notify(queue: queue) { Darwin.close(fd) }
        }
    }

    private func end(_ reason: EndReason) {
        guard !stopped else { return }
        stopped = true
        onEnded?(reason)
    }

    private func flushPendingWrite() {
        guard descriptor >= 0, var frame = pendingWrite else { return }
        let totalLength = frame.header.count + frame.payload.count
        while frame.offset < totalLength {
            let inHeader = frame.offset < frame.header.count
            let data = inHeader ? frame.header : frame.payload
            let offset = inHeader ? frame.offset : frame.offset - frame.header.count
            let written = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
            }
            if written > 0 {
                frame.offset += written
                continue
            }
            if written < 0 && errno == EINTR { continue }
            if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                pendingWrite = frame
                if writeSource == nil {
                    guard let group = sourceGroup else {
                        handleRemoteClosed()
                        finishWriting()
                        return
                    }
                    group.enter()
                    let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
                    source.setEventHandler { [weak self] in self?.flushPendingWrite() }
                    source.setCancelHandler { group.leave() }
                    writeSource = source
                    source.resume()
                }
                return
            }
            handleRemoteClosed()
            finishWriting()
            return
        }
        writeSource?.cancel()
        writeSource = nil
        pendingWrite = nil
        updateQuality(processingTime: ProcessInfo.processInfo.systemUptime - frame.startedAt)
        finishWriting()
    }

    private func updateQuality(processingTime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let frameInterval = Self.qualities[qualityIndex].minFrameInterval
        if processingTime > frameInterval * 1.5 {
            slowFrameCount += 1
            fastFrameCount = 0
            if slowFrameCount >= Self.slowFramesToReduceQuality {
                qualityIndex = min(qualityIndex + 1, Self.qualities.count - 1)
                slowFrameCount = 0
            }
        } else if processingTime < frameInterval * 0.7 {
            fastFrameCount += 1
            slowFrameCount = 0
            if fastFrameCount >= Self.fastFramesToIncreaseQuality {
                qualityIndex = max(qualityIndex - 1, 0)
                fastFrameCount = 0
            }
        } else {
            slowFrameCount = 0
            fastFrameCount = 0
        }
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer, quality: Quality) -> Data? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, quality.maxLongSide / max(width, height))
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return imageContext.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality.jpegQuality]
        )
    }

    private static func orientation(of sampleBuffer: CMSampleBuffer) -> UInt32 {
        let value = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber
        return value?.uint32Value ?? CGImagePropertyOrientation.up.rawValue
    }
}
