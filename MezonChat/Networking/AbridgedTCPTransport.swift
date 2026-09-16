import Foundation
import Network
import Security
import dnssd

private enum AbridgedTCPLog {
    private static let idLock = NSLock()
    private static var lastConnectionId = 0

    static func nextConnectionId() -> Int {
        idLock.lock()
        defer { idLock.unlock() }
        lastConnectionId += 1
        return lastConnectionId
    }

    static func line(_ message: String) {
        NSLog("%@", message as NSString)
    }

    static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1000).rounded())
    }

    static func elapsedMilliseconds(since start: DispatchTime) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    static func elapsedSeconds(since start: DispatchTime) -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }
}

private enum AddressFamily {
    case ipv6
    case ipv4

    init(_ host: NWEndpoint.Host) {
        if case .ipv6 = host {
            self = .ipv6
        } else {
            self = .ipv4
        }
    }

    var label: String {
        switch self {
        case .ipv6: return "IPv6"
        case .ipv4: return "IPv4"
        }
    }

    var recordType: String {
        switch self {
        case .ipv6: return "AAAA"
        case .ipv4: return "A"
        }
    }

    var dnsServiceProtocol: DNSServiceProtocol {
        switch self {
        case .ipv6: return DNSServiceProtocol(kDNSServiceProtocol_IPv6)
        case .ipv4: return DNSServiceProtocol(kDNSServiceProtocol_IPv4)
        }
    }

    func endpointHost(from address: UnsafePointer<sockaddr>) -> NWEndpoint.Host? {
        switch (self, Int32(address.pointee.sa_family)) {
        case (.ipv6, AF_INET6):
            let raw = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer -> Data in
                var bytes = pointer.pointee.sin6_addr
                return Data(bytes: &bytes, count: MemoryLayout<in6_addr>.size)
            }
            return IPv6Address(raw).map { NWEndpoint.Host.ipv6($0) }
        case (.ipv4, AF_INET):
            let raw = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer -> Data in
                var bytes = pointer.pointee.sin_addr
                return Data(bytes: &bytes, count: MemoryLayout<in_addr>.size)
            }
            return IPv4Address(raw).map { NWEndpoint.Host.ipv4($0) }
        default:
            return nil
        }
    }
}

private final class DNSAddressLookup {

    private let family: AddressFamily
    private let queue: DispatchQueue
    private var serviceRef: DNSServiceRef?
    private var hosts: [NWEndpoint.Host] = []
    private var seenHosts = Set<String>()
    private var completion: ((Result<[NWEndpoint.Host], Error>) -> Void)?

    init(family: AddressFamily, queue: DispatchQueue) {
        self.family = family
        self.queue = queue
    }

    func start(hostName: String, completion: @escaping (Result<[NWEndpoint.Host], Error>) -> Void) {
        self.completion = completion
        var ref: DNSServiceRef?
        let flags = DNSServiceFlags(kDNSServiceFlagsReturnIntermediates | kDNSServiceFlagsTimeout)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = DNSServiceGetAddrInfo(&ref, flags, 0, family.dnsServiceProtocol, hostName, { _, replyFlags, _, errorCode, _, address, _, replyContext in
            guard let replyContext else { return }
            let lookup = Unmanaged<DNSAddressLookup>.fromOpaque(replyContext).takeUnretainedValue()
            lookup.handleReply(flags: replyFlags, errorCode: errorCode, address: address)
        }, context)
        guard status == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else {
            finish(.failure(lookupError(status)))
            return
        }
        let queueStatus = DNSServiceSetDispatchQueue(ref, queue)
        guard queueStatus == DNSServiceErrorType(kDNSServiceErr_NoError) else {
            DNSServiceRefDeallocate(ref)
            finish(.failure(lookupError(queueStatus)))
            return
        }
        serviceRef = ref
        _ = Unmanaged.passRetained(self)
    }

    func cancel() {
        completion = nil
        stop()
    }

    private func handleReply(flags: DNSServiceFlags, errorCode: DNSServiceErrorType, address: UnsafePointer<sockaddr>?) {
        guard serviceRef != nil else { return }
        let moreComing = flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) != 0
        switch Int(errorCode) {
        case kDNSServiceErr_NoError:
            if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
               let address,
               let host = family.endpointHost(from: address),
               seenHosts.insert("\(host)").inserted {
                hosts.append(host)
            }
            if !moreComing, !hosts.isEmpty {
                finish(.success(hosts))
            }
        case kDNSServiceErr_NoSuchRecord, kDNSServiceErr_NoSuchName:
            if !moreComing {
                finish(.success(hosts))
            }
        default:
            finish(hosts.isEmpty ? .failure(lookupError(errorCode)) : .success(hosts))
        }
    }

    private func finish(_ result: Result<[NWEndpoint.Host], Error>) {
        let completion = self.completion
        self.completion = nil
        stop()
        completion?(result)
    }

    private func stop() {
        guard let ref = serviceRef else { return }
        serviceRef = nil
        DNSServiceRefDeallocate(ref)
        Unmanaged.passUnretained(self).release()
    }

    private func lookupError(_ status: DNSServiceErrorType) -> Error {
        MezonError.socketError("\(family.recordType) lookup failed with DNSServiceErrorType \(status)")
    }
}

private final class HappyEyeballsConnector {

    private let hostName: String
    private let port: NWEndpoint.Port
    private let queue: DispatchQueue
    private let logTag: String
    private let startedAt = DispatchTime.now()
    private let connectionAttemptDelay: TimeInterval = 0.25
    private let resolutionDelay: TimeInterval = 0.05

    private var completion: ((Result<NWConnection, Error>) -> Void)?
    private var lookups: [DNSAddressLookup] = []
    private var ipv6Hosts: [NWEndpoint.Host]?
    private var ipv4Hosts: [NWEndpoint.Host]?
    private var attemptedHosts = Set<String>()
    private var lastAttemptFamily: AddressFamily?
    private var lastAttemptStartedAt: DispatchTime?
    private var attempts: [Int: NWConnection] = [:]
    private var stalledAttempts = Set<Int>()
    private var nextAttemptNumber = 1
    private var attemptTimer: DispatchWorkItem?
    private var resolutionDelayTimer: DispatchWorkItem?
    private var lastError: Error?
    private var isFinished = false

    init(hostName: String, port: NWEndpoint.Port, queue: DispatchQueue, logTag: String) {
        self.hostName = hostName
        self.port = port
        self.queue = queue
        self.logTag = logTag
    }

    func start(completion: @escaping (Result<NWConnection, Error>) -> Void) {
        self.completion = completion
        log("happy eyeballs \(hostName):\(port.rawValue) attemptDelay=\(AbridgedTCPLog.milliseconds(connectionAttemptDelay))ms resolutionDelay=\(AbridgedTCPLog.milliseconds(resolutionDelay))ms enableFastOpen=true")
        if let literal = IPv6Address(hostName) {
            ipv6Hosts = [NWEndpoint.Host.ipv6(literal)]
            ipv4Hosts = []
            scheduleNextAttempt()
            return
        }
        if let literal = IPv4Address(hostName) {
            ipv6Hosts = []
            ipv4Hosts = [NWEndpoint.Host.ipv4(literal)]
            scheduleNextAttempt()
            return
        }
        resolve(.ipv6)
        resolve(.ipv4)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        completion = nil
        stopPendingWork()
        attempts.values.forEach { $0.cancel() }
        attempts.removeAll()
    }

    private func resolve(_ family: AddressFamily) {
        let lookup = DNSAddressLookup(family: family, queue: queue)
        lookups.append(lookup)
        lookup.start(hostName: hostName) { [weak self] result in
            self?.handleResolution(result, family: family)
        }
    }

    private func handleResolution(_ result: Result<[NWEndpoint.Host], Error>, family: AddressFamily) {
        guard !isFinished else { return }
        let hosts: [NWEndpoint.Host]
        switch result {
        case .success(let resolved):
            hosts = resolved
            let list = resolved.map { "\($0)" }.joined(separator: ", ")
            log("dns \(family.recordType) -> \(resolved.count) addresses [\(list)] at +\(elapsedMilliseconds)ms")
        case .failure(let error):
            hosts = []
            lastError = error
            log("dns \(family.recordType) failed at +\(elapsedMilliseconds)ms: \(error)")
        }
        switch family {
        case .ipv6: ipv6Hosts = hosts
        case .ipv4: ipv4Hosts = hosts
        }

        if lastAttemptStartedAt == nil, ipv6Hosts == nil {
            if !hosts.isEmpty, resolutionDelayTimer == nil {
                armResolutionDelay()
            }
        } else {
            resolutionDelayTimer?.cancel()
            resolutionDelayTimer = nil
            scheduleNextAttempt()
        }
        failIfExhausted()
    }

    private func armResolutionDelay() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isFinished else { return }
            self.resolutionDelayTimer = nil
            self.log("AAAA still pending after \(AbridgedTCPLog.milliseconds(self.resolutionDelay))ms resolution delay, starting with IPv4")
            self.scheduleNextAttempt()
        }
        resolutionDelayTimer = work
        queue.asyncAfter(deadline: .now() + resolutionDelay, execute: work)
    }

    private func scheduleNextAttempt() {
        guard !isFinished, attemptTimer == nil, !remainingHosts().isEmpty else { return }
        guard let lastStart = lastAttemptStartedAt, !attempts.isEmpty else {
            startNextAttempt()
            return
        }
        let wait = connectionAttemptDelay - AbridgedTCPLog.elapsedSeconds(since: lastStart)
        guard wait > 0 else {
            startNextAttempt()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isFinished else { return }
            self.attemptTimer = nil
            self.startNextAttempt()
        }
        attemptTimer = work
        queue.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func startNextAttempt() {
        attemptTimer?.cancel()
        attemptTimer = nil
        guard !isFinished, let host = remainingHosts().first else { return }
        let family = AddressFamily(host)
        let number = nextAttemptNumber
        nextAttemptNumber += 1
        attemptedHosts.insert("\(host)")
        lastAttemptFamily = family
        lastAttemptStartedAt = DispatchTime.now()

        let connection = NWConnection(host: host, port: port, using: makeParameters())
        attempts[number] = connection
        log("attempt #\(number) \(family.label) \(host) started at +\(elapsedMilliseconds)ms")
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleAttemptState(state, number: number, host: host, connection: connection)
        }
        connection.start(queue: queue)
        scheduleNextAttempt()
    }

    private func handleAttemptState(_ state: NWConnection.State, number: Int, host: NWEndpoint.Host, connection: NWConnection) {
        guard !isFinished, attempts[number] === connection else { return }
        switch state {
        case .ready:
            succeed(with: connection, number: number, host: host)
        case .waiting(let error):
            lastError = error
            guard stalledAttempts.insert(number).inserted else { return }
            log("attempt #\(number) \(AddressFamily(host).label) \(host) waiting at +\(elapsedMilliseconds)ms: \(error), kept alive while other addresses are tried")
            startNextAttempt()
        case .failed(let error):
            connection.cancel()
            attempts[number] = nil
            stalledAttempts.remove(number)
            lastError = error
            log("attempt #\(number) \(AddressFamily(host).label) \(host) failed at +\(elapsedMilliseconds)ms: \(error)")
            startNextAttempt()
            failIfExhausted()
        default:
            break
        }
    }

    private func succeed(with connection: NWConnection, number: Int, host: NWEndpoint.Host) {
        attempts[number] = nil
        let losers = Array(attempts.values)
        log("attempt #\(number) \(AddressFamily(host).label) \(host) won at +\(elapsedMilliseconds)ms, cancelling \(losers.count) other attempts")
        let completion = self.completion
        isFinished = true
        self.completion = nil
        stopPendingWork()
        losers.forEach { $0.cancel() }
        attempts.removeAll()
        completion?(.success(connection))
    }

    private func failIfExhausted() {
        guard !isFinished, attempts.isEmpty, ipv6Hosts != nil, ipv4Hosts != nil, remainingHosts().isEmpty else { return }
        let error = lastError ?? MezonError.socketError("No addresses found for \(hostName)")
        log("all attempts exhausted at +\(elapsedMilliseconds)ms: \(error)")
        let completion = self.completion
        isFinished = true
        self.completion = nil
        stopPendingWork()
        completion?(.failure(error))
    }

    private func remainingHosts() -> [NWEndpoint.Host] {
        let ipv6 = (ipv6Hosts ?? []).filter { !attemptedHosts.contains("\($0)") }
        let ipv4 = (ipv4Hosts ?? []).filter { !attemptedHosts.contains("\($0)") }
        let (first, second) = lastAttemptFamily == .ipv6 ? (ipv4, ipv6) : (ipv6, ipv4)
        var ordered: [NWEndpoint.Host] = []
        for index in 0..<max(first.count, second.count) {
            if index < first.count { ordered.append(first[index]) }
            if index < second.count { ordered.append(second[index]) }
        }
        return ordered
    }

    private func makeParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, hostName)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableFastOpen = true
        return NWParameters(tls: tlsOptions, tcp: tcpOptions)
    }

    private func stopPendingWork() {
        attemptTimer?.cancel()
        attemptTimer = nil
        resolutionDelayTimer?.cancel()
        resolutionDelayTimer = nil
        lookups.forEach { $0.cancel() }
        lookups.removeAll()
    }

    private var elapsedMilliseconds: UInt64 {
        AbridgedTCPLog.elapsedMilliseconds(since: startedAt)
    }

    private func log(_ message: String) {
        AbridgedTCPLog.line("\(logTag) \(message)")
    }
}

final class AbridgedTCPTransport {

    var onOpen: (() -> Void)?
    var onClose: ((_ wasClean: Bool, _ error: Error?) -> Void)?
    var onError: ((Error) -> Void)?
    var onEvents: (([AbridgedParsedEvent]) -> Void)?

    private let queue = DispatchQueue(label: "mezon.abridged.transport")
    private var connector: HappyEyeballsConnector?
    private var connection: NWConnection?
    private var parser = AbridgedStreamParser()
    private var isClosed = false
    private let writeStallTimeoutSeconds: TimeInterval = 20
    private let logTag = "[abridged-tcp] [c\(AbridgedTCPLog.nextConnectionId())]"

    func connect(host: String, port: UInt16, credential: String) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.connection == nil, self.connector == nil else { return }
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                self.failConnection(MezonError.socketError("Invalid abridged port \(port)"))
                return
            }
            let startedAt = DispatchTime.now()
            let connector = HappyEyeballsConnector(hostName: host, port: nwPort, queue: self.queue, logTag: self.logTag)
            self.connector = connector
            connector.start { [weak self] result in
                guard let self, self.connector === connector, !self.isClosed else {
                    if case .success(let orphan) = result {
                        orphan.cancel()
                    }
                    return
                }
                self.connector = nil
                switch result {
                case .success(let connection):
                    self.adopt(connection, credential: credential, startedAt: startedAt)
                case .failure(let error):
                    self.failConnection(error)
                }
            }
        }
    }

    func send(envelopePayload: Data, completion: @escaping (Error?) -> Void) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.connection != nil else {
                completion(MezonError.socketError("Abridged transport is not connected"))
                return
            }
            self.sendRaw(AbridgedFrameCodec.frameEnvelope(payload: envelopePayload), completion: completion)
        }
    }

    func sendPing(cid: UInt16) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.connection != nil else { return }
            self.sendRaw(AbridgedFrameCodec.framePing(cid: cid), completion: nil)
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            AbridgedTCPLog.line("\(self.logTag) close requested")
            self.isClosed = true
            self.connector?.cancel()
            self.connector = nil
            self.connection?.cancel()
            self.connection = nil
            self.onOpen = nil
            self.onClose = nil
            self.onError = nil
            self.onEvents = nil
        }
    }

    private func adopt(_ connection: NWConnection, credential: String, startedAt: DispatchTime) {
        self.connection = connection
        let tag = logTag
        AbridgedTCPLog.line("\(tag) ready at +\(AbridgedTCPLog.elapsedMilliseconds(since: startedAt))ms")
        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                guard let self, self.connection === connection, !self.isClosed else { return }
                AbridgedTCPLog.line("\(tag) state \(state) at +\(AbridgedTCPLog.elapsedMilliseconds(since: startedAt))ms")
                if case .failed(let error) = state {
                    self.failConnection(error)
                }
            }
        }
        logEstablishment(of: connection)
        sendRaw(AbridgedFrameCodec.frameHandshake(credential: credential)) { [weak self] error in
            guard let self, self.connection === connection, !self.isClosed else { return }
            if let error {
                self.failConnection(error)
            } else {
                self.onOpen?()
            }
        }
        receiveLoop(connection)
    }

    private func logEstablishment(of connection: NWConnection) {
        let tag = logTag
        let remote = connection.currentPath?.remoteEndpoint.map { "\($0)" } ?? "unknown"
        connection.requestEstablishmentReport(queue: queue) { report in
            guard let report else {
                AbridgedTCPLog.line("\(tag) establishment report unavailable, remote \(remote)")
                return
            }
            let handshakes = report.handshakes.map { handshake in
                "\(handshake.definition.name) \(AbridgedTCPLog.milliseconds(handshake.handshakeDuration))ms rtt \(AbridgedTCPLog.milliseconds(handshake.handshakeRTT))ms"
            }
            let handshakeSummary = handshakes.isEmpty ? "none" : handshakes.joined(separator: ", ")
            AbridgedTCPLog.line("\(tag) established via \(remote) in \(AbridgedTCPLog.milliseconds(report.duration))ms, usedProxy=\(report.usedProxy), handshakes: \(handshakeSummary)")
        }
    }

    private func sendRaw(_ data: Data, completion: ((Error?) -> Void)?) {
        guard let connection else {
            completion?(MezonError.socketError("Abridged transport is not connected"))
            return
        }
        let stallGuard = DispatchWorkItem { [weak self] in
            self?.failConnection(MezonError.socketError("Abridged socket write timed out"))
        }
        queue.asyncAfter(deadline: .now() + writeStallTimeoutSeconds, execute: stallGuard)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.queue.async {
                stallGuard.cancel()
                guard let self, !self.isClosed else { return }
                completion?(error)
                if let error {
                    self.failConnection(error)
                }
            }
        })
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            self?.queue.async {
                guard let self, self.connection === connection, !self.isClosed else { return }

                if let data, !data.isEmpty {
                    switch self.parser.ingest([UInt8](data)) {
                    case .failure(let reason):
                        self.failConnection(MezonError.socketError(reason))
                        return
                    case .events(let events):
                        if !events.isEmpty {
                            self.onEvents?(events)
                        }
                    }
                }

                if isComplete {
                    self.closeInternally(wasClean: true, error: nil)
                    return
                }
                if let error {
                    self.failConnection(error)
                    return
                }
                self.receiveLoop(connection)
            }
        }
    }

    private func failConnection(_ error: Error) {
        closeInternally(wasClean: false, error: error)
    }

    private func closeInternally(wasClean: Bool, error: Error?) {
        guard !isClosed else { return }
        isClosed = true
        let reason = error.map { "\($0)" } ?? "none"
        AbridgedTCPLog.line("\(logTag) closed wasClean=\(wasClean) error=\(reason)")
        connector?.cancel()
        connector = nil
        connection?.cancel()
        connection = nil
        if let error {
            onError?(error)
        }
        onClose?(wasClean, error)
        onOpen = nil
        onClose = nil
        onError = nil
        onEvents = nil
    }
}
