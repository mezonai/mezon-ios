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
    private static let minFrameInterval: TimeInterval = 1.0 / 15
    private static let maxLongSide: CGFloat = 1280
    private static let jpegQuality: CGFloat = 0.75

    private let queue = DispatchQueue(label: "mezon.screenshare.sender")
    private let lock = NSLock()
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var descriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var connectAttempts = 0
    private var stopped = false
    private var connected = false
    private var writing = false
    private var lastFrameUptime: TimeInterval = 0

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
        let ready = connected && !writing && now - lastFrameUptime >= Self.minFrameInterval
        if ready {
            writing = true
            lastFrameUptime = now
        }
        lock.unlock()
        guard ready else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let payload = autoreleasepool(invoking: { jpegData(from: pixelBuffer) }) else {
            finishWriting()
            return
        }
        let header = ScreenShareBroadcastChannel.encodeHeader(
            payloadLength: payload.count,
            orientation: Self.orientation(of: sampleBuffer)
        )
        queue.async {
            if self.descriptor >= 0, !(self.write(header) && self.write(payload)) {
                self.handleRemoteClosed()
            }
            self.finishWriting()
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
        descriptor = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            if count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN) {
                self?.handleRemoteClosed()
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
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
        readSource?.cancel()
        readSource = nil
        descriptor = -1
    }

    private func end(_ reason: EndReason) {
        guard !stopped else { return }
        stopped = true
        onEnded?(reason)
    }

    private func write(_ data: Data) -> Bool {
        let fd = descriptor
        return data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return false }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, Self.maxLongSide / max(width, height))
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return imageContext.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: Self.jpegQuality]
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
