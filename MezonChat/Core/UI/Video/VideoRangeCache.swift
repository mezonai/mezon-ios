import Foundation
import CryptoKit

protocol VideoRangeTaskHandler: AnyObject {
    func videoRangeTask(_ task: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    func videoRangeTask(_ task: URLSessionDataTask, didReceive data: Data)
    func videoRangeTask(_ task: URLSessionTask, didCompleteWithError error: Error?)
}

final class VideoRangeSession: NSObject, URLSessionDataDelegate {

    static let shared = VideoRangeSession()

    private struct Route {
        weak var handler: VideoRangeTaskHandler?
        let queue: DispatchQueue
    }

    private(set) var session: URLSession!
    private let lock = NSLock()
    private var routes: [Int: Route] = [:]

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    func dataTask(with request: URLRequest, handler: VideoRangeTaskHandler, queue: DispatchQueue) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        lock.lock()
        routes[task.taskIdentifier] = Route(handler: handler, queue: queue)
        lock.unlock()
        return task
    }

    private func route(for task: URLSessionTask, removing: Bool = false) -> Route? {
        lock.lock()
        defer { lock.unlock() }
        return removing ? routes.removeValue(forKey: task.taskIdentifier) : routes[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let route = route(for: dataTask) else {
            completionHandler(.allow)
            return
        }
        guard let handler = route.handler else {
            completionHandler(.cancel)
            return
        }
        route.queue.async {
            handler.videoRangeTask(dataTask, didReceive: response, completionHandler: completionHandler)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let route = route(for: dataTask), let handler = route.handler else { return }
        route.queue.async {
            handler.videoRangeTask(dataTask, didReceive: data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let route = route(for: task, removing: true), let handler = route.handler else { return }
        route.queue.async {
            handler.videoRangeTask(task, didCompleteWithError: error)
        }
    }
}

final class VideoRangeCache {

    static let shared = VideoRangeCache()
    static let chunkSize = 512 * 1024
    static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VideoRangeCache", isDirectory: true)

    private static let entryByteLimit = 128 * 1024 * 1024

    private struct Entry: Codable {
        let key: String
        let contentLength: Int64
        var chunks: [Int64: Int]

        var byteCount: Int { chunks.values.reduce(0, +) }
    }

    private let lock = NSLock()
    private let fileLock = NSLock()
    private var names: [String: String] = [:]
    private var entries: [String: Entry] = [:]
    private var retainCounts: [String: Int] = [:]

    private init() {}

    static func parseContentRange(_ header: String) -> (start: Int64, end: Int64, total: Int64)? {
        let parts = header.split(separator: " ")
        guard parts.count == 2, parts[0].lowercased() == "bytes" else { return nil }
        let lengths = parts[1].split(separator: "/")
        guard lengths.count == 2, let total = Int64(lengths[1]), total > 0 else { return nil }
        let bounds = lengths[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]),
              start >= 0, start <= end, end < total else { return nil }
        return (start, end, total)
    }

    func retain(_ key: String) {
        lock.lock()
        let name = nameLocked(for: key)
        retainCounts[name, default: 0] += 1
        let isFirstRetain = retainCounts[name] == 1
        lock.unlock()
        guard isFirstRetain else { return }
        fileLock.lock()
        let entry = Self.loadEntry(name: name, key: key)
        lock.lock()
        if retainCounts[name] != nil, entries[name] == nil {
            entries[name] = entry
        }
        lock.unlock()
        fileLock.unlock()
    }

    func release(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        let name = nameLocked(for: key)
        guard let count = retainCounts[name] else { return }
        if count > 1 {
            retainCounts[name] = count - 1
        } else {
            retainCounts[name] = nil
            entries[name] = nil
        }
    }

    func remove(_ key: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        lock.lock()
        let name = nameLocked(for: key)
        lock.unlock()
        removeEntry(name)
    }

    func attachedFileNames() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(retainCounts.keys.flatMap { [Self.dataFileName($0), Self.metaFileName($0)] })
    }

    func contentLength(for key: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return entries[nameLocked(for: key)]?.contentLength
    }

    func cachedContentLength(for key: String) -> Int64? {
        lock.lock()
        let name = nameLocked(for: key)
        let retained = entries[name]
        lock.unlock()
        if let retained { return retained.contentLength }
        return Self.readEntry(name: name, key: key)?.contentLength
    }

    func chunkLength(at offset: Int64, for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries[nameLocked(for: key)]?.chunks[offset] ?? 0
    }

    func data(at offset: Int64, for key: String) -> Data? {
        guard #available(iOS 13.4, *), chunkLength(at: offset, for: key) > 0 else { return nil }
        fileLock.lock()
        defer { fileLock.unlock() }
        lock.lock()
        let name = nameLocked(for: key)
        let length = entries[name]?.chunks[offset] ?? 0
        lock.unlock()
        guard length > 0 else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: Self.dataFileURL(name))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            if let data = try handle.read(upToCount: length), data.count == length {
                return data
            }
        } catch {}
        removeEntry(name)
        return nil
    }

    func store(_ data: Data, at offset: Int64, contentLength: Int64, for key: String) {
        guard #available(iOS 13.4, *) else { return }
        fileLock.lock()
        defer { fileLock.unlock() }
        lock.lock()
        let name = nameLocked(for: key)
        let isRetained = retainCounts[name] != nil
        var entry = entries[name]
        lock.unlock()
        guard isRetained else { return }
        let fileManager = FileManager.default
        let fileURL = Self.dataFileURL(name)
        if let existing = entry,
           existing.contentLength != contentLength || !fileManager.fileExists(atPath: fileURL.path) {
            removeEntry(name)
            entry = nil
        }
        var updated = entry ?? Entry(key: key, contentLength: contentLength, chunks: [:])
        let saved = updated.chunks[offset] ?? 0
        let added = data.count - saved
        guard added > 0, updated.byteCount + added <= Self.entryByteLimit else { return }
        do {
            try fileManager.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: fileURL.path) {
                guard fileManager.createFile(atPath: fileURL.path, contents: nil) else { return }
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset) + UInt64(saved))
            try handle.write(contentsOf: data.dropFirst(saved))
            updated.chunks[offset] = data.count
            try JSONEncoder().encode(updated).write(to: Self.metaFileURL(name), options: .atomic)
        } catch {
            removeEntry(name)
            return
        }
        lock.lock()
        if retainCounts[name] != nil {
            entries[name] = updated
        }
        lock.unlock()
        StorageMaintenance.shared.noteDiskCacheWrite(byteCount: added)
    }

    private func nameLocked(for key: String) -> String {
        if let name = names[key] { return name }
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        names[key] = name
        return name
    }

    private func removeEntry(_ name: String) {
        lock.lock()
        entries[name] = nil
        lock.unlock()
        Self.removeFiles(name)
    }

    private static func loadEntry(name: String, key: String) -> Entry? {
        guard let entry = readEntry(name: name, key: key) else {
            removeFiles(name)
            return nil
        }
        let now = Date()
        for url in [dataFileURL(name), metaFileURL(name)] {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
        return entry
    }

    private static func readEntry(name: String, key: String) -> Entry? {
        guard let meta = try? Data(contentsOf: metaFileURL(name)),
              let entry = try? JSONDecoder().decode(Entry.self, from: meta),
              entry.key == key, entry.contentLength > 0,
              let size = (try? FileManager.default.attributesOfItem(atPath: dataFileURL(name).path))?[.size] as? NSNumber,
              entry.chunks.allSatisfy({ $0.key >= 0 && $0.key + Int64($0.value) <= size.int64Value }) else { return nil }
        return entry
    }

    private static func removeFiles(_ name: String) {
        try? FileManager.default.removeItem(at: dataFileURL(name))
        try? FileManager.default.removeItem(at: metaFileURL(name))
    }

    private static func dataFileName(_ name: String) -> String { name + ".data" }
    private static func metaFileName(_ name: String) -> String { name + ".json" }
    private static func dataFileURL(_ name: String) -> URL { directory.appendingPathComponent(dataFileName(name)) }
    private static func metaFileURL(_ name: String) -> URL { directory.appendingPathComponent(metaFileName(name)) }
}

final class VideoRangePrefetcher: VideoRangeTaskHandler {

    static let shared = VideoRangePrefetcher()

    private static let headByteCount = 2 * VideoRangeCache.chunkSize
    private static let tailByteLimit = 2 * VideoRangeCache.chunkSize
    private static let maxActiveJobs = 2

    private struct Job {
        let url: URL
        let key: String
        let allowsExpensiveNetwork: Bool
    }

    private enum State {
        case waiting
        case active
        case finished
    }

    private final class Transfer {
        let job: Job
        let url: URL
        let start: Int64
        let end: Int64
        var contentLength: Int64?
        var data = Data()

        init(job: Job, url: URL, start: Int64, end: Int64) {
            self.job = job
            self.url = url
            self.start = start
            self.end = end
        }
    }

    private let queue = DispatchQueue(label: "mezon.video.range-prefetch", qos: .utility)
    private var states: [String: State] = [:]
    private var waitingJobs: [Job] = []
    private var activeJobCount = 0
    private var tasks: [String: URLSessionDataTask] = [:]
    private var transfers: [Int: Transfer] = [:]

    private init() {}

    func prefetch(_ url: URL, allowsExpensiveNetwork: Bool) {
        guard VideoRangeLoadingPolicy.shouldProbe(url) else { return }
        let key = url.absoluteString
        queue.async {
            guard self.states[key] == nil, !FileIngestPlaylist.isMarked(key) else { return }
            self.states[key] = .waiting
            self.waitingJobs.append(Job(url: url, key: key, allowsExpensiveNetwork: allowsExpensiveNetwork))
            self.startWaitingJobs()
        }
    }

    func cancel(_ url: URL) {
        let key = url.absoluteString
        queue.async {
            self.states[key] = .finished
            self.waitingJobs.removeAll { $0.key == key }
            self.tasks[key]?.cancel()
        }
    }

    func withdraw(_ url: URL) {
        let key = url.absoluteString
        queue.async {
            guard case .waiting? = self.states[key] else { return }
            self.states[key] = nil
            self.waitingJobs.removeAll { $0.key == key }
        }
    }

    private func startWaitingJobs() {
        while activeJobCount < Self.maxActiveJobs, let job = waitingJobs.popLast() {
            activeJobCount += 1
            states[job.key] = .active
            begin(job)
        }
    }

    private func begin(_ job: Job) {
        guard VideoRangeCache.shared.cachedContentLength(for: job.key) == nil else {
            finish(job, retryable: false)
            return
        }
        CDNSigner.shared.requestURL(for: job.url) { request in
            self.queue.async {
                self.fetch(job, from: request.url, start: 0, end: Int64(Self.headByteCount) - 1)
            }
        }
    }

    private func fetch(_ job: Job, from url: URL, start: Int64, end: Int64) {
        guard case .active? = states[job.key] else {
            finish(job, retryable: false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.allowsConstrainedNetworkAccess = false
        request.allowsExpensiveNetworkAccess = job.allowsExpensiveNetwork
        let task = VideoRangeSession.shared.dataTask(with: request, handler: self, queue: queue)
        task.priority = URLSessionTask.lowPriority
        tasks[job.key] = task
        transfers[task.taskIdentifier] = Transfer(job: job, url: url, start: start, end: end)
        task.resume()
    }

    private func finish(_ job: Job, retryable: Bool) {
        tasks[job.key] = nil
        activeJobCount -= 1
        if retryable, case .active? = states[job.key] {
            states[job.key] = nil
        } else {
            states[job.key] = .finished
        }
        startWaitingJobs()
    }

    private func store(_ data: Data, at start: Int64, contentLength: Int64, key: String) {
        let cache = VideoRangeCache.shared
        cache.retain(key)
        var offset = 0
        while offset < data.count {
            let end = min(offset + VideoRangeCache.chunkSize, data.count)
            cache.store(data.subdata(in: offset..<end), at: start + Int64(offset), contentLength: contentLength, for: key)
            offset = end
        }
        cache.release(key)
    }

    func videoRangeTask(_ task: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let transfer = transfers[task.taskIdentifier],
              let http = response as? HTTPURLResponse, http.statusCode == 206,
              let header = http.value(forHTTPHeaderField: "Content-Range"),
              let range = VideoRangeCache.parseContentRange(header),
              range.start == transfer.start, range.end <= transfer.end else {
            completionHandler(.cancel)
            return
        }
        transfer.contentLength = range.total
        completionHandler(.allow)
    }

    func videoRangeTask(_ task: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfers[task.taskIdentifier], transfer.contentLength != nil else { return }
        guard Int64(transfer.data.count + data.count) <= transfer.end - transfer.start + 1 else {
            task.cancel()
            return
        }
        transfer.data.append(data)
    }

    func videoRangeTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = transfers.removeValue(forKey: task.taskIdentifier) else { return }
        let job = transfer.job
        guard error == nil, let contentLength = transfer.contentLength, !transfer.data.isEmpty else {
            let isCancelled = (error as? URLError)?.code == .cancelled
            finish(job, retryable: error != nil && !isCancelled)
            return
        }
        store(transfer.data, at: transfer.start, contentLength: contentLength, key: job.key)
        if transfer.start == 0,
           let tailStart = Self.trailingMetadataChunkOffset(in: transfer.data, contentLength: contentLength) {
            fetch(job, from: transfer.url, start: tailStart, end: contentLength - 1)
            return
        }
        finish(job, retryable: false)
    }

    private static func trailingMetadataChunkOffset(in head: Data, contentLength: Int64) -> Int64? {
        var offset = 0
        while offset + 8 <= head.count {
            let size32 = readBigEndian(head, at: offset, count: 4)
            let type = String(decoding: head[(offset + 4)..<(offset + 8)], as: UTF8.self)
            var size = Int64(size32)
            if size32 == 1 {
                guard offset + 16 <= head.count else { return nil }
                size = Int64(clamping: readBigEndian(head, at: offset + 8, count: 8))
            } else if size32 == 0 {
                return nil
            }
            guard size >= 8 else { return nil }
            if type == "moov" { return nil }
            let next = Int64(offset) + size
            if type == "mdat", next >= Int64(head.count) {
                guard next < contentLength else { return nil }
                let chunk = Int64(VideoRangeCache.chunkSize)
                let tailStart = next / chunk * chunk
                guard tailStart >= Int64(head.count), contentLength - tailStart <= Int64(tailByteLimit) else { return nil }
                return tailStart
            }
            guard next < Int64(head.count) else { return nil }
            offset = Int(next)
        }
        return nil
    }

    private static func readBigEndian(_ data: Data, at offset: Int, count: Int) -> UInt64 {
        data[offset..<(offset + count)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
}
