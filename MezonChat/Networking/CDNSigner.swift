import Foundation
import UIKit

struct CDNRequestURL {
    let url: URL
    let channelID: Int64
    let signature: String

    var isSigned: Bool { !signature.isEmpty }

    static func unsigned(_ url: URL) -> CDNRequestURL {
        CDNRequestURL(url: url, channelID: 0, signature: "")
    }
}

final class CDNTaskHandle {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }

    fileprivate func attach(_ task: URLSessionTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.task = task
        return true
    }
}

final class CDNSigner {

    static let shared = CDNSigner()

    typealias SignatureProvider = (Int64) async throws -> String

    private enum Entry {
        case signed(String, Date)
        case refused(Date)
    }

    private enum CacheState {
        case missing
        case refused
        case signed(String)
    }

    private struct SigningTarget {
        let channelID: Int64
        let build: (String) -> URL?
    }

    private static let refreshAfter: TimeInterval = 3 * 60 * 60
    private static let refusedRetryAfter: TimeInterval = 60
    private static let forbiddenRefetchAfter: TimeInterval = 30
    private static let fetchTimeoutNanoseconds: UInt64 = 5_000_000_000
    private static let channelSegmentLength = 16
    private static let imgproxySourceMarker = "/plain/"
    private static let knownMediaOrigins = [
        "https://cdn.mezon.ai",
        "https://cdn.mezon.vn",
        "https://cdn.komu.vn",
        "https://cdn.komu.ai",
    ]
    private static let renditionSourceAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "@")
        return allowed
    }()

    private let lock = NSLock()
    private var provider: SignatureProvider?
    private var entries: [Int64: Entry] = [:]
    private var flights: [Int64: Task<String?, Never>] = [:]
    private var generation = 0

    private init() {}

    func install(_ provider: @escaping SignatureProvider) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    func reset() {
        lock.lock()
        provider = nil
        entries.removeAll()
        flights.removeAll()
        generation += 1
        lock.unlock()
    }

    func prefetch(channelID: Int64) {
        guard channelID != 0 else { return }
        lock.lock()
        let state = cacheStateLocked(channelID)
        let inFlight = flights[channelID] != nil
        let hasProvider = provider != nil
        lock.unlock()
        guard case .missing = state, !inFlight, hasProvider else {
            return
        }
        Task {
            _ = await self.signature(for: channelID)
        }
    }

    func wants(_ url: URL) -> Bool {
        signingTarget(for: url) != nil
    }

    func readyRequestURL(for url: URL) -> CDNRequestURL? {
        guard let target = signingTarget(for: url) else { return CDNRequestURL.unsigned(url) }
        lock.lock()
        let state = cacheStateLocked(target.channelID)
        lock.unlock()
        switch state {
        case .missing:
            return nil
        case .refused:
            return CDNRequestURL.unsigned(url)
        case .signed(let signature):
            return request(for: url, target: target, signature: signature)
        }
    }

    func requestURL(for url: URL) async -> CDNRequestURL {
        guard let target = signingTarget(for: url) else { return .unsigned(url) }
        guard let fetched = await self.signature(for: target.channelID) else {
            return .unsigned(url)
        }
        return request(for: url, target: target, signature: fetched)
    }

    func requestURL(for url: URL, completion: @escaping (CDNRequestURL) -> Void) {
        Task {
            completion(await self.requestURL(for: url))
        }
    }

    func invalidate(_ request: CDNRequestURL) -> Bool {
        guard request.isSigned else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard case .signed(let cached, let fetchedAt)? = entries[request.channelID],
              cached == request.signature else {
            return true
        }
        let age = Self.age(of: fetchedAt)
        guard age >= Self.forbiddenRefetchAfter else {
            return false
        }
        entries[request.channelID] = nil
        return true
    }

    func shouldRetry(_ request: CDNRequestURL, response: URLResponse?) -> Bool {
        guard request.isSigned, (response as? HTTPURLResponse)?.statusCode == 403 else { return false }
        return invalidate(request)
    }

    func freshRequestURL(
        after request: CDNRequestURL,
        for url: URL,
        completion: @escaping (CDNRequestURL?) -> Void
    ) {
        requestURL(for: url) { next in
            let fresh = next.isSigned && next.signature != request.signature ? next : nil
            completion(fresh)
        }
    }

    @discardableResult
    func dataTask(
        with url: URL,
        in session: URLSession,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> CDNTaskHandle {
        let handle = CDNTaskHandle()
        func start(_ request: CDNRequestURL, isRetry: Bool) {
            let task = session.dataTask(with: request.url) { data, response, error in
                guard !isRetry, self.shouldRetry(request, response: response) else {
                    completion(data, response, error)
                    return
                }
                self.freshRequestURL(after: request, for: url) { next in
                    guard let next else {
                        completion(data, response, error)
                        return
                    }
                    start(next, isRetry: true)
                }
            }
            guard handle.attach(task) else {
                completion(nil, nil, URLError(.cancelled))
                return
            }
            task.resume()
        }
        if let ready = readyRequestURL(for: url) {
            start(ready, isRetry: false)
        } else {
            requestURL(for: url) { start($0, isRetry: false) }
        }
        return handle
    }

    @discardableResult
    func downloadTask(
        with url: URL,
        in session: URLSession,
        onStart: ((URLSessionDownloadTask) -> Void)? = nil,
        completion: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> CDNTaskHandle {
        let handle = CDNTaskHandle()
        func start(_ request: CDNRequestURL, isRetry: Bool) {
            let task = session.downloadTask(with: request.url) { location, response, error in
                guard !isRetry, self.shouldRetry(request, response: response) else {
                    completion(location, response, error)
                    return
                }
                self.freshRequestURL(after: request, for: url) { next in
                    guard let next else {
                        completion(nil, response, error)
                        return
                    }
                    start(next, isRetry: true)
                }
            }
            guard handle.attach(task) else {
                completion(nil, nil, URLError(.cancelled))
                return
            }
            onStart?(task)
            task.resume()
        }
        if let ready = readyRequestURL(for: url) {
            start(ready, isRetry: false)
        } else {
            requestURL(for: url) { start($0, isRetry: false) }
        }
        return handle
    }

    func openExternally(_ url: URL) {
        if let ready = readyRequestURL(for: url) {
            UIApplication.shared.open(ready.url)
            return
        }
        requestURL(for: url) { request in
            DispatchQueue.main.async {
                UIApplication.shared.open(request.url)
            }
        }
    }

    private func request(for url: URL, target: SigningTarget, signature: String) -> CDNRequestURL {
        guard let signed = target.build(signature) else { return .unsigned(url) }
        return CDNRequestURL(url: signed, channelID: target.channelID, signature: signature)
    }

    private func cacheStateLocked(_ channelID: Int64) -> CacheState {
        switch entries[channelID] {
        case .signed(let signature, let fetchedAt)? where Self.age(of: fetchedAt) < Self.refreshAfter:
            return .signed(signature)
        case .refused(let refusedAt)? where Self.age(of: refusedAt) < Self.refusedRetryAfter:
            return .refused
        default:
            return .missing
        }
    }

    private func signature(for channelID: Int64) async -> String? {
        lock.lock()
        let state = cacheStateLocked(channelID)
        var flight: Task<String?, Never>?
        if case .missing = state, provider != nil {
            if let existing = flights[channelID] {
                flight = existing
            } else {
                let started = generation
                let created = Task { await self.fetchSignature(for: channelID, generation: started) }
                flights[channelID] = created
                flight = created
            }
        }
        lock.unlock()
        switch state {
        case .signed(let signature):
            return signature
        case .refused:
            return nil
        case .missing:
            guard let flight else {
                return nil
            }
            return await flight.value
        }
    }

    private func fetchSignature(for channelID: Int64, generation started: Int) async -> String? {
        let fetched = await fetchWithTimeout(channelID)
        lock.lock()
        defer { lock.unlock() }
        guard generation == started else {
            return nil
        }
        flights[channelID] = nil
        entries[channelID] = fetched.map { Entry.signed($0, Date()) } ?? Entry.refused(Date())
        return fetched
    }

    private func fetchWithTimeout(_ channelID: Int64) async -> String? {
        lock.lock()
        let provider = self.provider
        lock.unlock()
        guard let provider else {
            return nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let resumed = Atomic<Bool>(value: false)
            let timer = Task {
                try? await Task.sleep(nanoseconds: Self.fetchTimeoutNanoseconds)
                guard !resumed.swap(true) else { return }
                continuation.resume(returning: nil)
            }
            Task {
                let fetched: String?
                do {
                    fetched = try await provider(channelID)
                } catch {
                    fetched = nil
                }
                guard !resumed.swap(true) else {
                    return
                }
                timer.cancel()
                continuation.resume(returning: fetched.flatMap { $0.isEmpty ? nil : $0 })
            }
        }
    }

    private func signingTarget(for url: URL) -> SigningTarget? {
        let string = url.absoluteString
        if let directChannel = self.channelID(of: string) {
            return SigningTarget(channelID: directChannel) { URL(string: "\(string)?\($0)") }
        }
        guard let parts = renditionParts(of: string),
              let sourceChannel = self.channelID(of: String(parts.source)) else { return nil }
        return SigningTarget(channelID: sourceChannel) { signature in
            guard let escaped = "\(parts.source)?\(signature)"
                .addingPercentEncoding(withAllowedCharacters: Self.renditionSourceAllowed) else { return nil }
            return URL(string: "\(parts.head)\(Self.imgproxySourceMarker)\(escaped)\(parts.suffix)")
        }
    }

    private func channelID(of urlString: String) -> Int64? {
        for origin in Self.mediaOrigins() where urlString.hasPrefix(origin) {
            let rest = urlString.dropFirst(origin.count)
            guard rest.first == "/", !rest.contains("?"), !rest.contains("#") else { return nil }
            let segments = rest.dropFirst().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard segments.count == 2, !segments[1].isEmpty else { return nil }
            return Self.channelID(fromSegment: segments[0])
        }
        return nil
    }

    private func renditionParts(of urlString: String) -> (head: Substring, source: Substring, suffix: Substring)? {
        guard let proxy = Self.urlBase(MezonEnvironment.current.imgproxyBaseURL),
              urlString.hasPrefix(proxy),
              urlString.dropFirst(proxy.count).first == "/",
              let marker = urlString.range(of: Self.imgproxySourceMarker) else { return nil }
        let head = urlString[..<marker.lowerBound]
        let rest = urlString[marker.upperBound...]
        guard let at = rest.lastIndex(of: "@") else { return (head, rest, rest[rest.endIndex...]) }
        return (head, rest[..<at], rest[at...])
    }

    private static func mediaOrigins() -> [String] {
        ([MezonConfig.baseImgURL] + knownMediaOrigins).compactMap(urlBase)
    }

    private static func urlBase(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func channelID(fromSegment segment: Substring) -> Int64? {
        guard segment.utf8.count == channelSegmentLength,
              segment.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let value = UInt64(segment, radix: 16),
              value != 0 else { return nil }
        return Int64(bitPattern: value)
    }

    private static func age(of date: Date) -> TimeInterval {
        let elapsed = Date().timeIntervalSince(date)
        return elapsed < 0 ? .infinity : elapsed
    }
}
