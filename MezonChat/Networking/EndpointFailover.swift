import Foundation
import Sentry

struct HealthyEndpointStatusError: Error {
    let statusCode: Int
}

private struct EndpointRefreshRequest {
    let endpoint: RealtimeEndpoint
    let reason: HealthyEndpointReason
}

private enum AskOutcome {
    case done
    case retry
}

@MainActor
final class EndpointFailover {

    static let shared = EndpointFailover()

    var sessionProvider: (() -> MezonSession?)?
    var refreshTokenProvider: (() async throws -> String)?
    var applyEndpoints: ((_ apiURL: String?, _ wsURL: String?, _ tcpURL: String) -> Bool)?

    private static let retryBase: TimeInterval = 5
    private static let retryCap: TimeInterval = 60
    private static let askTimeout: TimeInterval = 5
    private static let askPacingSettle: TimeInterval = 60

    private let enabled = EndpointFailoverFlags.enabled
    private let slowSwitchEnabled = EndpointFailoverFlags.slowSwitchEnabled
    private let health = EndpointHealth()

    private var pending: EndpointRefreshRequest?
    private var worker: Task<Void, Never>?
    private var retrySeconds = EndpointFailover.retryBase
    private var lastAskAt: Date?
    private var routeMissing = false
    private var automaticChoiceTask: Task<Void, Never>?

    private init() {}

    func onConnected(_ endpoint: RealtimeEndpoint?) {
        guard enabled else { return }
        health.setEndpoint(endpoint)
        guard endpoint != nil else { return }
        health.recordConnected(at: Date())
        if lastAskAt.map({ Date().timeIntervalSince($0) >= Self.askPacingSettle }) ?? true {
            retrySeconds = Self.retryBase
            lastAskAt = nil
        }
    }

    func onDisconnected() {
        guard enabled else { return }
        health.recordDisconnected()
    }

    func onProbeRtt(_ rttMs: Double) {
        guard enabled, slowSwitchEnabled, let endpoint = health.connectedEndpoint() else { return }
        guard health.recordActiveProbe(rttMs: rttMs, at: Date()) else { return }
        reportWeak(endpoint, signal: "slow_ping")
    }

    func onApiTimeout() {
        guard enabled, slowSwitchEnabled, let endpoint = health.connectedEndpoint() else { return }
        guard health.recordApiTimeout(at: Date()) else { return }
        reportWeak(endpoint, signal: "api_timeout")
    }

    func onHeartbeat(sinceLastPong gap: TimeInterval) {
        guard enabled, slowSwitchEnabled, let endpoint = health.connectedEndpoint() else { return }
        guard health.recordHeartbeat(sinceLastPong: gap, at: Date()) else { return }
        reportWeak(endpoint, signal: "pong_overdue")
    }

    private func reportWeak(_ endpoint: RealtimeEndpoint, signal: String) {
        SentryLogger.addBreadcrumb(
            category: "endpoint.failover",
            message: "slow_node_report",
            data: ["node": endpoint.label, "signal": signal]
        )
        enqueue(EndpointRefreshRequest(endpoint: endpoint, reason: .highLatency))
    }

    func onUnreachable(_ endpoint: RealtimeEndpoint?) {
        guard enabled else { return }
        guard let target = endpoint ?? health.connectedEndpoint() else { return }
        health.recordDisconnected()
        SentryLogger.addBreadcrumb(
            category: "endpoint.failover",
            message: "unreachable_report",
            level: .warning,
            data: ["node": target.label]
        )
        enqueue(EndpointRefreshRequest(endpoint: target, reason: .unreachable))
    }

    func reset() {
        guard enabled else { return }
        pending = nil
        worker?.cancel()
        worker = nil
        health.setEndpoint(nil)
        retrySeconds = Self.retryBase
        lastAskAt = nil
    }

    func select(_ choice: RealtimeServerChoice) {
        if choice == .auto, automaticChoiceTask != nil { return }
        RealtimeServerChoice.current = choice
        SentryLogger.addBreadcrumb(
            category: "endpoint.failover",
            message: "server_choice_selected",
            data: ["choice": choice.rawValue]
        )
        pending = nil
        automaticChoiceTask?.cancel()
        automaticChoiceTask = nil
        guard choice == .auto else {
            MezonSocket.shared.reconnectIfTargetChanged()
            return
        }
        automaticChoiceTask = Task { @MainActor [weak self] in
            await self?.chooseAutomatically()
            guard !Task.isCancelled else { return }
            self?.automaticChoiceTask = nil
        }
    }

    private func chooseAutomatically() async {
        if let response = await askForDefaultNode() {
            guard !Task.isCancelled else { return }
            applyDefaultNode(response)
        }
        guard !Task.isCancelled else { return }
        MezonSocket.shared.reconnectIfTargetChanged()
    }

    private func askForDefaultNode() async -> HealthyEndpoint? {
        guard enabled, !routeMissing, let session = sessionProvider?() else { return nil }
        var token = session.token
        if session.isExpired || token.isEmpty {
            let renewal = await renewToken()
            guard case .success(let renewed) = renewal else { return nil }
            token = renewed
        }
        do {
            return try await fetchDefaultNode(token: token)
        } catch let error as HealthyEndpointStatusError where error.statusCode == 401 || error.statusCode == 403 {
            let renewal = await renewToken()
            guard case .success(let renewed) = renewal else { return nil }
            return try? await fetchDefaultNode(token: renewed)
        } catch {
            SentryLogger.addBreadcrumb(
                category: "endpoint.failover",
                message: "default_node_ask_failed",
                level: .warning,
                data: ["error": String(describing: error)]
            )
            return nil
        }
    }

    private func fetchDefaultNode(token: String) async throws -> HealthyEndpoint {
        try await withTimeout(Self.askTimeout) {
            try await MezonHTTPClient.shared.getHealthyEndpoint(
                token: token,
                currentEndpointId: 0,
                reasonCode: HealthyEndpointReason.highLatency.rawValue
            )
        }
    }

    private func applyDefaultNode(_ response: HealthyEndpoint) {
        let current = sessionProvider?()
        guard RealtimeServerChoice.current == .auto,
              let next = EndpointAddress.node(answeredBy: response, fallbackTcpURL: current?.tcpURL)
        else { return }
        let tcpURL = response.tcpURL.isEmpty ? "\(next.host):\(next.port)" : response.tcpURL
        let applied = applyEndpoints?(
            response.apiURL.isEmpty ? nil : response.apiURL,
            response.wsURL.isEmpty ? nil : response.wsURL,
            tcpURL
        ) ?? false
        SentryLogger.addBreadcrumb(
            category: "endpoint.failover",
            message: "gateway_default_node",
            data: ["node": next.label, "applied": applied]
        )
    }

    private func enqueue(_ request: EndpointRefreshRequest) {
        guard RealtimeServerChoice.current == .auto else { return }
        pending = request
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    private func drain() async {
        while let request = pending {
            pending = nil
            let carried = await step(request)
            if Task.isCancelled { return }
            if let carried, pending == nil {
                pending = carried
            }
        }
    }

    private func stillAimed(at endpoint: RealtimeEndpoint) -> Bool {
        MezonSocket.shared.targetEndpoint?.isSameNode(endpoint) == true
    }

    private func recoveredOnItsOwn(_ request: EndpointRefreshRequest) -> Bool {
        request.reason == .unreachable && MezonSocket.shared.isConnected
    }

    private func sleep(_ seconds: TimeInterval) async -> Bool {
        guard seconds > 0 else { return !Task.isCancelled }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }

    private func step(_ request: EndpointRefreshRequest) async -> EndpointRefreshRequest? {
        guard !routeMissing, stillAimed(at: request.endpoint) else { return nil }

        while !NetworkMonitor.shared.isConnected {
            guard await sleep(1) else { return nil }
        }

        let wait: TimeInterval
        if let lastAskAt {
            wait = retrySeconds - Date().timeIntervalSince(lastAskAt)
        } else {
            wait = request.reason == .highLatency ? 0 : Self.retryBase
        }
        guard await sleep(wait) else { return nil }

        guard stillAimed(at: request.endpoint) else { return nil }
        if recoveredOnItsOwn(request) {
            SentryLogger.addBreadcrumb(
                category: "endpoint.failover",
                message: "report_dropped_node_recovered",
                data: ["node": request.endpoint.label]
            )
            return nil
        }

        lastAskAt = Date()
        let outcome = await ask(request)
        retrySeconds = doubledBackoff(retrySeconds, cap: Self.retryCap)
        return outcome == .retry ? request : nil
    }

    private func ask(_ request: EndpointRefreshRequest) async -> AskOutcome {
        guard RealtimeServerChoice.current == .auto, let session = sessionProvider?() else { return .done }

        var token = session.token
        if session.isExpired || token.isEmpty {
            switch await renewToken() {
            case .success(let renewed): token = renewed
            case .failure(let failure): return failure.outcome
            }
        }

        do {
            let response = try await fetch(request, token: token)
            return adopt(request, response: response)
        } catch let error as HealthyEndpointStatusError {
            switch error.statusCode {
            case 404:
                routeMissing = true
                SentryLogger.addBreadcrumb(
                    category: "endpoint.failover",
                    message: "route_missing_failover_off"
                )
                return .done
            case 401, 403:
                return await askWithFreshToken(request)
            default:
                SentryLogger.addBreadcrumb(
                    category: "endpoint.failover",
                    message: "ask_failed",
                    level: .warning,
                    data: ["status": error.statusCode]
                )
                return .retry
            }
        } catch {
            SentryLogger.addBreadcrumb(
                category: "endpoint.failover",
                message: "ask_failed",
                level: .warning,
                data: ["error": String(describing: error)]
            )
            return .retry
        }
    }

    private func askWithFreshToken(_ request: EndpointRefreshRequest) async -> AskOutcome {
        let token: String
        switch await renewToken() {
        case .success(let renewed): token = renewed
        case .failure(let failure): return failure.outcome
        }
        do {
            let response = try await fetch(request, token: token)
            return adopt(request, response: response)
        } catch {
            SentryLogger.addBreadcrumb(
                category: "endpoint.failover",
                message: "ask_failed_with_renewed_token",
                level: .warning,
                data: ["error": String(describing: error)]
            )
            return .retry
        }
    }

    private func renewToken() async -> Result<String, AskOutcomeFailure> {
        guard SessionRefreshManager.shared.mayRefresh else { return .failure(.retry) }
        guard let provider = refreshTokenProvider else { return .failure(.retry) }
        do {
            return .success(try await provider())
        } catch is SessionError {
            return .failure(.done)
        } catch {
            return .failure(.retry)
        }
    }

    private enum AskOutcomeFailure: Error {
        case done
        case retry

        var outcome: AskOutcome {
            switch self {
            case .done: return .done
            case .retry: return .retry
            }
        }
    }

    private func fetch(_ request: EndpointRefreshRequest, token: String) async throws -> HealthyEndpoint {
        let currentEndpointId = request.endpoint.id
        let reasonCode = request.reason.rawValue
        return try await withTimeout(Self.askTimeout) {
            try await MezonHTTPClient.shared.getHealthyEndpoint(
                token: token,
                currentEndpointId: currentEndpointId,
                reasonCode: reasonCode
            )
        }
    }

    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else { throw URLError(.unknown) }
            group.cancelAll()
            return first
        }
    }

    private func adopt(_ request: EndpointRefreshRequest, response: HealthyEndpoint) -> AskOutcome {
        let current = sessionProvider?()
        guard let next = EndpointAddress.node(answeredBy: response, fallbackTcpURL: current?.tcpURL) else {
            return .retry
        }
        guard RealtimeServerChoice.current == .auto, stillAimed(at: request.endpoint) else { return .done }

        if next.isSameNode(request.endpoint) {
            health.setEndpoint(next)
            if request.reason == .highLatency {
                health.disableSlowReports()
            }
            SentryLogger.addBreadcrumb(
                category: "endpoint.failover",
                message: "gateway_kept_node",
                data: ["node": request.endpoint.label, "reason": request.reason.rawValue]
            )
            return .done
        }

        let tcpURL = response.tcpURL.isEmpty ? "\(next.host):\(next.port)" : response.tcpURL
        let applied = applyEndpoints?(
            response.apiURL.isEmpty ? nil : response.apiURL,
            response.wsURL.isEmpty ? nil : response.wsURL,
            tcpURL
        ) ?? false
        guard applied else { return .done }

        SentryLogger.addBreadcrumb(
            category: "endpoint.failover",
            message: "gateway_moved_node",
            level: .warning,
            data: ["from": request.endpoint.label, "to": next.label, "reason": request.reason.rawValue]
        )
        health.setEndpoint(next)
        MezonSocket.shared.reconnectForEndpointChange()
        return .done
    }
}
