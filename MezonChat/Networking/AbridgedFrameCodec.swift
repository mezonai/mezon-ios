import Foundation

enum AbridgedFrame {
    case pong(cid: UInt16)
    case raw(cid: UInt16, responseCode: UInt32, fin: Bool, payload: Data)
    case realtime(payload: Data)
}

enum AbridgedFrameStep {
    case needMore
    case reset(reason: String)
    case frame(consumed: Int, frame: AbridgedFrame)
}

enum AbridgedParsedEvent {
    case pong(cid: UInt16)
    case apiResponse(cid: UInt16, code: UInt32, payload: Data)
    case realtime(payload: Data)
}

enum AbridgedIngestResult {
    case events([AbridgedParsedEvent])
    case failure(reason: String)
}

enum AbridgedFrameCodec {

    static let maxRealtimeFrameLen = 1 << 20
    static let maxApiResponseLen = 16 << 20
    static let responseCodeTooLarge: UInt32 = 0xFFFF

    private static let prefixHandshake: UInt8 = 0xEF
    private static let prefixExtended: UInt8 = 0x7F
    private static let prefixRaw: UInt8 = 0xFF
    private static let rawHeaderLength = 11
    private static let codeFin: UInt32 = 0xFF

    static func frameHandshake(credential: String) -> Data {
        var payload = [UInt8](credential.utf8)
        let padding = (4 - (payload.count % 4)) % 4
        payload.append(contentsOf: [UInt8](repeating: 0, count: padding))
        let lenDiv4 = payload.count / 4
        var frame: [UInt8]
        if lenDiv4 < 127 {
            frame = [prefixHandshake, UInt8(lenDiv4)]
        } else {
            frame = [prefixHandshake, prefixExtended,
                     UInt8(lenDiv4 & 0xFF), UInt8((lenDiv4 >> 8) & 0xFF), UInt8((lenDiv4 >> 16) & 0xFF)]
        }
        frame.append(contentsOf: payload)
        return Data(frame)
    }

    static func framePing(cid: UInt16) -> Data {
        Data([0x00, UInt8(cid >> 8), UInt8(cid & 0xFF)])
    }

    static func frameEnvelope(payload: Data) -> Data {
        var padded = [UInt8](payload)
        let padding = (4 - (padded.count % 4)) % 4
        padded.append(contentsOf: [UInt8](repeating: 0, count: padding))
        let lenDiv4 = padded.count / 4
        var frame: [UInt8]
        if lenDiv4 < 127 {
            frame = [UInt8(lenDiv4)]
        } else {
            frame = [prefixExtended,
                     UInt8(lenDiv4 & 0xFF), UInt8((lenDiv4 >> 8) & 0xFF), UInt8((lenDiv4 >> 16) & 0xFF)]
        }
        frame.append(contentsOf: padded)
        return Data(frame)
    }

    static func looksLikeHTTP(_ chunk: [UInt8]) -> Bool {
        func startsWith(_ prefix: String) -> Bool {
            let p = [UInt8](prefix.utf8)
            guard chunk.count >= p.count else { return false }
            return Array(chunk[0..<p.count]) == p
        }
        return startsWith("HTTP/") || startsWith("GET ") || startsWith("POST ")
    }

    static func readVarint(_ bytes: [UInt8], at offset: Int) -> (value: UInt64, length: Int)? {
        var value: UInt64 = 0
        var shift: UInt32 = 0
        var i = offset
        while i < bytes.count {
            if shift >= 64 { return nil }
            let b = bytes[i]
            value |= UInt64(b & 0x7F) << UInt64(shift)
            if b & 0x80 == 0 {
                return (value, i - offset + 1)
            }
            shift += 7
            i += 1
        }
        return nil
    }

    static func protobufMessageLength(_ bytes: [UInt8]) -> Int? {
        var pos = 0
        while pos < bytes.count {
            guard let (tag, tagLen) = readVarint(bytes, at: pos) else { return nil }
            let field = tag >> 3
            let wire = tag & 7
            if field == 0 || wire == 3 || wire == 4 || wire == 6 || wire == 7 {
                return pos
            }
            let valueStart = pos + tagLen
            let valueEnd: Int
            switch wire {
            case 0:
                guard valueStart <= bytes.count,
                      let (_, n) = readVarint(bytes, at: valueStart) else { return nil }
                valueEnd = valueStart + n
            case 1:
                valueEnd = valueStart + 8
            case 5:
                valueEnd = valueStart + 4
            case 2:
                guard valueStart <= bytes.count,
                      let (len, n) = readVarint(bytes, at: valueStart) else { return nil }
                if len > UInt64(maxRealtimeFrameLen) {
                    return pos
                }
                valueEnd = valueStart + n + Int(len)
            default:
                return pos
            }
            if valueEnd > bytes.count { return nil }
            pos = valueEnd
        }
        return pos
    }

    static func trimRealtimePayload(_ framed: [UInt8]) -> Data {
        let end = protobufMessageLength(framed) ?? framed.count
        return Data(framed[0..<end])
    }

    static func decodeFrame(_ buffer: [UInt8], from start: Int) -> AbridgedFrameStep {
        let available = buffer.count - start
        guard available >= 1 else { return .needMore }
        let first = buffer[start]

        switch first {
        case 0x00:
            guard available >= 3 else { return .needMore }
            let cid = UInt16(buffer[start + 1]) << 8 | UInt16(buffer[start + 2])
            return .frame(consumed: 3, frame: .pong(cid: cid))

        case prefixRaw:
            guard available >= rawHeaderLength else { return .needMore }
            let cid = UInt16(buffer[start + 1]) << 8 | UInt16(buffer[start + 2])
            let code = UInt32(buffer[start + 3]) << 24 | UInt32(buffer[start + 4]) << 16
                     | UInt32(buffer[start + 5]) << 8 | UInt32(buffer[start + 6])
            let len = Int(UInt32(buffer[start + 7]) << 24 | UInt32(buffer[start + 8]) << 16
                        | UInt32(buffer[start + 9]) << 8 | UInt32(buffer[start + 10]))
            if len > maxApiResponseLen {
                return .reset(reason: "raw frame length too large")
            }
            let total = rawHeaderLength + len
            guard available >= total else { return .needMore }
            let responseCode = (code >> 16) & 0xFFFF
            let fin = (code & 0xFFFF) == codeFin
            let payload = Data(buffer[(start + rawHeaderLength)..<(start + total)])
            return .frame(consumed: total, frame: .raw(cid: cid, responseCode: responseCode, fin: fin, payload: payload))

        case 0x82:
            guard available >= 2 else { return .needMore }
            let b1 = buffer[start + 1]
            if b1 & 0x80 != 0 {
                return .reset(reason: "masked websocket frame")
            }
            let len7 = Int(b1)
            let header: Int
            let payloadLen: Int
            if len7 < 126 {
                header = 2
                payloadLen = len7
            } else if len7 == 126 {
                guard available >= 4 else { return .needMore }
                header = 4
                payloadLen = Int(UInt16(buffer[start + 2]) << 8 | UInt16(buffer[start + 3]))
            } else {
                guard available >= 10 else { return .needMore }
                var len64: UInt64 = 0
                for i in 0..<8 {
                    len64 = len64 << 8 | UInt64(buffer[start + 2 + i])
                }
                if len64 > UInt64(maxRealtimeFrameLen) {
                    return .reset(reason: "websocket frame length too large")
                }
                header = 10
                payloadLen = Int(len64)
            }
            if payloadLen > maxRealtimeFrameLen {
                return .reset(reason: "websocket frame length too large")
            }
            let total = header + payloadLen
            guard available >= total else { return .needMore }
            let payload = Data(buffer[(start + header)..<(start + total)])
            return .frame(consumed: total, frame: .realtime(payload: payload))

        case prefixExtended:
            guard available >= 4 else { return .needMore }
            let lenDiv4 = Int(UInt32(buffer[start + 1]) | UInt32(buffer[start + 2]) << 8 | UInt32(buffer[start + 3]) << 16)
            let payloadLen = lenDiv4 * 4
            if payloadLen > maxRealtimeFrameLen {
                return .reset(reason: "extended frame length too large")
            }
            let total = 4 + payloadLen
            guard available >= total else { return .needMore }
            let framed = Array(buffer[(start + 4)..<(start + total)])
            return .frame(consumed: total, frame: .realtime(payload: trimRealtimePayload(framed)))

        case let f where f >= 0x01 && f < prefixExtended:
            let total = 1 + Int(f) * 4
            guard available >= total else { return .needMore }
            let framed = Array(buffer[(start + 1)..<(start + total)])
            return .frame(consumed: total, frame: .realtime(payload: trimRealtimePayload(framed)))

        default:
            return .reset(reason: "unexpected lead byte 0x\(String(first, radix: 16))")
        }
    }
}

struct AbridgedStreamParser {

    private var buffer: [UInt8] = []
    private var streams: [UInt16: Data] = [:]
    private var sawValidFrame = false

    mutating func reset() {
        buffer.removeAll()
        streams.removeAll()
        sawValidFrame = false
    }

    mutating func ingest(_ chunk: [UInt8]) -> AbridgedIngestResult {
        if chunk.isEmpty { return .events([]) }
        if !sawValidFrame, buffer.isEmpty, AbridgedFrameCodec.looksLikeHTTP(chunk) {
            return .failure(reason: "server spoke HTTP instead of abridged TCP")
        }
        buffer.append(contentsOf: chunk)

        var events: [AbridgedParsedEvent] = []
        var start = 0

        while true {
            if start >= buffer.count {
                buffer.removeAll(keepingCapacity: true)
                return .events(events)
            }
            switch AbridgedFrameCodec.decodeFrame(buffer, from: start) {
            case .needMore:
                buffer.removeFirst(start)
                return .events(events)
            case .reset(let reason):
                buffer.removeAll()
                streams.removeAll()
                return .failure(reason: reason)
            case .frame(let consumed, let frame):
                start += consumed
                sawValidFrame = true
                switch frame {
                case .pong(let cid):
                    events.append(.pong(cid: cid))
                case .raw(let cid, let responseCode, let fin, let payload):
                    if fin {
                        var body = streams.removeValue(forKey: cid) ?? Data()
                        body.append(payload)
                        events.append(.apiResponse(cid: cid, code: responseCode, payload: body))
                    } else {
                        var pending = streams[cid] ?? Data()
                        pending.append(payload)
                        if pending.count > AbridgedFrameCodec.maxApiResponseLen {
                            streams.removeValue(forKey: cid)
                            events.append(.apiResponse(cid: cid, code: AbridgedFrameCodec.responseCodeTooLarge, payload: Data()))
                        } else {
                            streams[cid] = pending
                        }
                    }
                case .realtime(let payload):
                    events.append(.realtime(payload: payload))
                }
            }
        }
    }
}
