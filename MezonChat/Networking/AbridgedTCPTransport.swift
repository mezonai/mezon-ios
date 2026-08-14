import Foundation
import Network

final class AbridgedTCPTransport {

    var onOpen: (() -> Void)?
    var onClose: ((_ wasClean: Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onEvents: (([AbridgedParsedEvent]) -> Void)?

    private let queue = DispatchQueue(label: "mezon.abridged.transport")
    private var connection: NWConnection?
    private var parser = AbridgedStreamParser()
    private var isClosed = false
    private let writeStallTimeoutSeconds: TimeInterval = 20

    func connect(host: String, port: UInt16, credential: String) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, self.connection == nil else { return }
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                self.failConnection(MezonError.socketError("Invalid abridged port \(port)"))
                return
            }
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcpOptions)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] state in
                self?.queue.async {
                    guard let self, self.connection === connection, !self.isClosed else { return }
                    switch state {
                    case .ready:
                        self.sendRaw(AbridgedFrameCodec.frameHandshake(credential: credential)) { [weak self] error in
                            guard let self, self.connection === connection, !self.isClosed else { return }
                            if let error {
                                self.failConnection(error)
                            } else {
                                self.onOpen?()
                            }
                        }
                        self.receiveLoop(connection)
                    case .failed(let error):
                        self.failConnection(error)
                    default:
                        break
                    }
                }
            }
            connection.start(queue: self.queue)
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
            self.isClosed = true
            self.connection?.cancel()
            self.connection = nil
            self.onOpen = nil
            self.onClose = nil
            self.onError = nil
            self.onEvents = nil
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
        connection?.cancel()
        connection = nil
        if let error {
            onError?(error)
        }
        onClose?(wasClean)
        onOpen = nil
        onClose = nil
        onError = nil
        onEvents = nil
    }
}
