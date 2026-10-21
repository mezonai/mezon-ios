import Foundation

enum ScreenShareBroadcastChannel {
    static let appGroupIdentifier = "group.mezon.mobile"
    static let extensionBundleIdentifier = "mezon.mobile.MezonScreenShare"
    static let headerSize = 12
    static let maxPayloadSize = 8 * 1024 * 1024

    private static let socketFileName = "mzss"
    private static let frameMagic: UInt32 = 0x4D5A_5353

    static var socketPath: String? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let path = container.appendingPathComponent(socketFileName).path
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        return path.utf8.count < capacity ? path : nil
    }

    static func socketAddress(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                _ = strncpy(buffer, path, capacity - 1)
            }
        }
        return address
    }

    static func disableSigPipe(_ descriptor: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }

    static func encodeHeader(payloadLength: Int, orientation: UInt32) -> Data {
        var data = Data(capacity: headerSize)
        for word in [frameMagic, UInt32(payloadLength), orientation] {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decodeHeader(_ bytes: Data) -> (payloadLength: Int, orientation: UInt32)? {
        guard bytes.count >= headerSize else { return nil }
        let start = bytes.startIndex
        func word(at offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { value, index in
                value | UInt32(bytes[start + offset + index]) << (8 * UInt32(index))
            }
        }
        guard word(at: 0) == frameMagic else { return nil }
        let payloadLength = Int(word(at: 4))
        guard payloadLength > 0, payloadLength <= maxPayloadSize else { return nil }
        return (payloadLength, word(at: 8))
    }
}
