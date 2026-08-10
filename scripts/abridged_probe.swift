import Foundation
import Network

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok: \(label)")
    } else {
        failures += 1
        print("  FAIL: \(label)")
    }
}

func hex(_ data: Data, limit: Int = 32) -> String {
    data.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
}

func rawFrame(cid: UInt16, fin: Bool, payload: [UInt8]) -> [UInt8] {
    let code: UInt32 = fin ? 0xFF : 0
    var frame: [UInt8] = [0xFF, UInt8(cid >> 8), UInt8(cid & 0xFF)]
    frame.append(contentsOf: [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)])
    let len = UInt32(payload.count)
    frame.append(contentsOf: [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)])
    frame.append(contentsOf: payload)
    return frame
}

func runSelftest() {
    print("protobufMessageLength:")
    check(AbridgedFrameCodec.protobufMessageLength([0x10, 0x80, 0xA0, 0x80, 0xF0, 0xFE, 0xD1, 0xD3, 0xC5, 0x19, 0x0C, 0xC2, 0x01, 0x2A]) == 10, "delimits ack body before next frame")
    check(AbridgedFrameCodec.protobufMessageLength([0x10, 0x80, 0xA0, 0x80, 0xF0, 0xFE, 0xD1, 0xD3, 0xC5, 0x19]) == 10, "consumes whole message when no trailing frame")
    check(AbridgedFrameCodec.protobufMessageLength([0x0A, 0x03, 0x61, 0x62, 0x63, 0x17, 0x32, 0x57]) == 5, "handles length-delimited field")
    check(AbridgedFrameCodec.protobufMessageLength([0x10, 0x80, 0xA0]) == nil, "returns nil on incomplete varint")
    check(AbridgedFrameCodec.protobufMessageLength([0x0A, 0x05, 0x61, 0x62]) == nil, "returns nil on incomplete length-delimited")
    check(AbridgedFrameCodec.protobufMessageLength([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0x00, 0x00]) == 0, "caps absurd field length")
    check(AbridgedFrameCodec.protobufMessageLength([0x08, 0x58, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00]) == 4, "includes trailing empty field")

    print("handshake framing:")
    let short = AbridgedFrameCodec.frameHandshake(credential: "abc")
    check(short[0] == 0xEF && short[1] == 1 && short.count == 2 + 4, "short token uses 1-byte header")
    let long = AbridgedFrameCodec.frameHandshake(credential: String(repeating: "x", count: 600))
    let longLen4 = Int(long[2]) | Int(long[3]) << 8 | Int(long[4]) << 16
    check(long[0] == 0xEF && long[1] == 0x7F && longLen4 == 150 && long.count == 5 + 600, "long token uses extended header")

    print("envelope framing:")
    let smallEnv = AbridgedFrameCodec.frameEnvelope(payload: Data([0x08, 0x02, 0xE2]))
    check(smallEnv[0] == 1 && smallEnv.count == 5 && smallEnv[4] == 0, "small payload padded, 1-byte header")
    let bigEnv = AbridgedFrameCodec.frameEnvelope(payload: Data(repeating: 0x41, count: 600))
    let bigLen4 = Int(bigEnv[1]) | Int(bigEnv[2]) << 8 | Int(bigEnv[3]) << 16
    check(bigEnv[0] == 0x7F && bigLen4 == 150 && bigEnv.count == 4 + 600, "large payload uses extended header")
    check(AbridgedFrameCodec.framePing(cid: 1) == Data([0x00, 0x00, 0x01]), "ping frame bytes")

    print("decodeFrame:")
    if case .needMore = AbridgedFrameCodec.decodeFrame([0x00, 0x00], from: 0) {
        check(true, "ping needs 3 bytes")
    } else { check(false, "ping needs 3 bytes") }
    if case .frame(let consumed, .pong(let cid)) = AbridgedFrameCodec.decodeFrame([0x00, 0x00, 0x07], from: 0) {
        check(consumed == 3 && cid == 7, "ping parse")
    } else { check(false, "ping parse") }
    let abridged: [UInt8] = [0x02, 0x08, 0x58, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00]
    if case .frame(let consumed, .realtime(let payload)) = AbridgedFrameCodec.decodeFrame(abridged, from: 0) {
        check(consumed == 9 && payload == Data([0x08, 0x58, 0x22, 0x00]), "abridged small frame trims padding")
    } else { check(false, "abridged small frame trims padding") }
    var extended: [UInt8] = [0x7F, 0x02, 0x00, 0x00]
    extended.append(contentsOf: [0x08, 0x58, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00])
    if case .frame(let consumed, .realtime(let payload)) = AbridgedFrameCodec.decodeFrame(extended, from: 0) {
        check(consumed == 12 && payload == Data([0x08, 0x58, 0x22, 0x00]), "extended frame trims padding")
    } else { check(false, "extended frame trims padding") }
    var ws: [UInt8] = [0x82, 0x04]
    ws.append(contentsOf: [0x08, 0x58, 0x22, 0x00])
    if case .frame(let consumed, .realtime(let payload)) = AbridgedFrameCodec.decodeFrame(ws, from: 0) {
        check(consumed == 6 && payload == Data([0x08, 0x58, 0x22, 0x00]), "ws-binary frame no trim")
    } else { check(false, "ws-binary frame no trim") }
    if case .reset = AbridgedFrameCodec.decodeFrame([0x82, 0x84, 0x00], from: 0) {
        check(true, "masked ws frame resets")
    } else { check(false, "masked ws frame resets") }
    if case .reset = AbridgedFrameCodec.decodeFrame([0x90], from: 0) {
        check(true, "unknown lead byte resets")
    } else { check(false, "unknown lead byte resets") }

    print("parser:")
    var parser = AbridgedStreamParser()
    let body = [UInt8](repeating: 0x42, count: 6000)
    let chunkSize = 4096
    var r1 = parser.ingest(rawFrame(cid: 6, fin: false, payload: Array(body[0..<chunkSize])))
    if case .events(let evs) = r1 {
        check(evs.isEmpty, "non-fin chunk buffers silently")
    } else { check(false, "non-fin chunk buffers silently") }
    r1 = parser.ingest(rawFrame(cid: 6, fin: true, payload: Array(body[chunkSize...])))
    if case .events(let evs) = r1, evs.count == 1, case .apiResponse(let cid, let code, let payload) = evs[0] {
        check(cid == 6 && code == 0 && payload == Data(body), "reassembles chunked api response")
    } else { check(false, "reassembles chunked api response") }

    parser.reset()
    let frame = rawFrame(cid: 8, fin: true, payload: [0x61, 0x62, 0x63])
    var r2 = parser.ingest(Array(frame[0..<5]))
    if case .events(let evs) = r2 {
        check(evs.isEmpty, "split header buffers")
    } else { check(false, "split header buffers") }
    r2 = parser.ingest(Array(frame[5...]))
    if case .events(let evs) = r2, evs.count == 1, case .apiResponse(let cid, _, let payload) = evs[0] {
        check(cid == 8 && payload == Data([0x61, 0x62, 0x63]), "split frame delivered once complete")
    } else { check(false, "split frame delivered once complete") }

    parser.reset()
    var burst = rawFrame(cid: 20, fin: true, payload: [0x01])
    burst.append(contentsOf: rawFrame(cid: 21, fin: true, payload: []))
    burst.append(contentsOf: rawFrame(cid: 22, fin: true, payload: [0x02, 0x03]))
    burst.append(contentsOf: [0x00, 0x00, 0x05])
    let r3 = parser.ingest(burst)
    if case .events(let evs) = r3, evs.count == 4,
       case .apiResponse(20, 0, Data([0x01])) = evs[0],
       case .apiResponse(21, 0, Data()) = evs[1],
       case .apiResponse(22, 0, Data([0x02, 0x03])) = evs[2],
       case .pong(5) = evs[3] {
        check(true, "burst routes by cid + trailing pong")
    } else { check(false, "burst routes by cid + trailing pong") }

    parser.reset()
    let http = parser.ingest([UInt8]("HTTP/1.1 400 Bad Request\r\n".utf8))
    if case .failure(let reason) = http {
        check(reason.contains("HTTP"), "detects http response")
    } else { check(false, "detects http response") }

    parser.reset()
    let desync = parser.ingest([0x91, 0x00, 0x00])
    if case .failure = desync {
        check(true, "desync fails ingest")
    } else { check(false, "desync fails ingest") }

    print(failures == 0 ? "ALL SELFTESTS PASSED" : "\(failures) SELFTEST(S) FAILED")
    exit(failures == 0 ? 0 : 1)
}

func runProbe(host: String, port: UInt16, credential: String, seconds: Int) {
    print("probe: connecting \(host):\(port) credential(\(credential.count) chars)")
    let queue = DispatchQueue(label: "probe")
    var parser = AbridgedStreamParser()
    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(rawValue: port)!,
        using: NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
    )

    func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                switch parser.ingest([UInt8](data)) {
                case .failure(let reason):
                    print("PARSE FAILURE: \(reason)")
                    connection.cancel()
                    exit(2)
                case .events(let events):
                    for event in events {
                        switch event {
                        case .pong(let cid):
                            print("PONG cid=\(cid)")
                        case .apiResponse(let cid, let code, let payload):
                            print("RAW cid=\(cid) code=\(code) len=\(payload.count) [\(hex(payload))]")
                        case .realtime(let payload):
                            print("REALTIME len=\(payload.count) [\(hex(payload))]")
                        }
                    }
                }
            }
            if isComplete {
                print("SERVER CLOSED")
                exit(3)
            }
            if let error {
                print("RECEIVE ERROR: \(error)")
                exit(4)
            }
            receiveLoop()
        }
    }

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("TLS READY — sending handshake")
            connection.send(content: AbridgedFrameCodec.frameHandshake(credential: credential), completion: .contentProcessed { error in
                if let error { print("HANDSHAKE SEND ERROR: \(error)"); exit(5) }
                print("HANDSHAKE SENT")
            })
            queue.asyncAfter(deadline: .now() + 0.5) {
                connection.send(content: AbridgedFrameCodec.framePing(cid: 1), completion: .contentProcessed { _ in
                    print("PING cid=1 sent")
                })
            }
            receiveLoop()
        case .failed(let error):
            print("CONNECTION FAILED: \(error)")
            exit(6)
        case .waiting(let error):
            print("WAITING: \(error)")
        default:
            break
        }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + .seconds(seconds)) {
        print("probe finished (\(seconds)s)")
        connection.cancel()
        exit(0)
    }
    dispatchMain()
}

@main
struct AbridgedProbe {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            runSelftest()
        } else if let probeIndex = args.firstIndex(of: "--probe"), args.count >= probeIndex + 4 {
            let host = args[probeIndex + 1]
            guard let port = UInt16(args[probeIndex + 2]) else {
                print("invalid port"); exit(64)
            }
            let credential = args[probeIndex + 3]
            let seconds = args.count > probeIndex + 4 ? Int(args[probeIndex + 4]) ?? 30 : 30
            runProbe(host: host, port: port, credential: credential, seconds: seconds)
        } else {
            print("""
            usage:
              abridged_probe --selftest
              abridged_probe --probe <host> <port> <credential> [seconds]

            build:
              swiftc -O -o /tmp/abridged_probe MezonChat/Networking/AbridgedFrameCodec.swift scripts/abridged_probe.swift
            """)
            exit(64)
        }
    }
}
