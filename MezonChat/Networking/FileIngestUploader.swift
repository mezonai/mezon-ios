import Foundation

enum FileIngest {
    static let chunkSize: Int64 = 8 * 1024 * 1024
    static let maxSize: Int64 = 1024 * 1024 * 1024

    private static let videoExtensions: Set<String> = [
        "3g2", "3gp", "avi", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "mts", "ogv", "qt", "webm", "wmv",
    ]
    private static let schemes = ["https://", "http://"]

    static func baseURLs(_ raw: String = MezonEnvironment.current.fileIngestBases) -> [String: String] {
        var bases: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            guard let equals = pair.firstIndex(of: "="), equals != pair.startIndex else { continue }
            let host = pair[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var base = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            while base.hasSuffix("/") { base.removeLast() }
            guard !host.isEmpty, isOrigin(base) else { continue }
            bases[host] = base
        }
        return bases
    }

    static func isCandidate(filetype: String, filename: String, size: Int) -> Bool {
        let name = filename as NSString
        let isVideo = filetype.lowercased().hasPrefix("video")
            || (!name.deletingPathExtension.isEmpty && videoExtensions.contains(name.pathExtension.lowercased()))
        return isVideo && size >= 1 && Int64(size) <= maxSize && !baseURLs().isEmpty
    }

    static func ingestURL(forPresignedURL presigned: String) -> String? {
        guard let scheme = schemes.first(where: { presigned.lowercased().hasPrefix($0) }) else { return nil }
        let rest = presigned.dropFirst(scheme.count)
        guard let pathStart = rest.firstIndex(where: { "/?#".contains($0) }), rest[pathStart] == "/" else { return nil }
        let host = rest[..<pathStart].lowercased()
        guard !host.isEmpty else { return nil }
        let bases = baseURLs()
        let hostWithoutPort = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        guard let base = bases[host] ?? bases[hostWithoutPort] else { return nil }
        return base + rest[pathStart...]
    }

    static func moovAfterMdat(fileURL: URL, size: Int64) -> Int64 {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return -1 }
        defer { try? handle.close() }
        var offset: Int64 = 0
        var sawMdat = false
        while offset + 8 <= size {
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return -1 }
            let header = [UInt8](handle.readData(ofLength: 16))
            guard header.count >= 8 else { return -1 }
            var boxSize = Int64(bigEndian(header, from: 0, count: 4))
            let type = String(decoding: header[4..<8], as: UTF8.self)
            if boxSize == 1 {
                guard header.count >= 16 else { return -1 }
                boxSize = Int64(bitPattern: bigEndian(header, from: 8, count: 8))
            } else if boxSize == 0 {
                boxSize = size - offset
            }
            if type == "moov" { return sawMdat ? offset : -1 }
            if type == "mdat" { sawMdat = true }
            if boxSize < 8 || boxSize > size - offset { return -1 }
            offset += boxSize
        }
        return -1
    }

    static func nextChunk(size: Int64, received: [[Int64]], moov: Int64) -> ClosedRange<Int64>? {
        let fileStart: Int64 = 0
        let order: [(first: Int64, last: Int64)] = moov > 0
            ? [(moov, size - 1), (fileStart, moov - 1)]
            : [(fileStart, size - 1)]
        let ranges = received
            .compactMap { pair -> (from: Int64, to: Int64)? in pair.count == 2 ? (pair[0], pair[1]) : nil }
            .sorted { $0.from < $1.from }
        for (first, last) in order {
            var start = first
            for range in ranges {
                if range.from > start { break }
                start = max(start, range.to + 1)
            }
            if start > last { continue }
            let followingStart = ranges.first(where: { $0.from > start })?.from
            let end = min(start + chunkSize - 1, last, followingStart.map { $0 - 1 } ?? last)
            return start...end
        }
        return nil
    }

    static func isPresignedURLExpired(_ url: String, now: Date = Date()) -> Bool {
        guard let query = url.split(separator: "?", maxSplits: 1).dropFirst().first else { return false }
        var issuedAt: String?
        var expiresIn: Double?
        for item in query.split(separator: "&") {
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0] == "X-Amz-Date" { issuedAt = String(parts[1]) }
            if parts[0] == "X-Amz-Expires" { expiresIn = Double(parts[1]) }
        }
        guard let issuedAt, let expiresIn, expiresIn > 0 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        guard let issued = formatter.date(from: issuedAt) else { return false }
        return now >= issued.addingTimeInterval(expiresIn)
    }

    private static func isOrigin(_ value: String) -> Bool {
        guard let scheme = schemes.first(where: { value.lowercased().hasPrefix($0) }) else { return false }
        let host = value.dropFirst(scheme.count)
        return !host.isEmpty && !host.contains(where: { "/?#".contains($0) })
    }

    private static func bigEndian(_ bytes: [UInt8], from start: Int, count: Int) -> UInt64 {
        bytes[start..<start + count].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
}

enum FileIngestAvailability {
    private static let availableFor: TimeInterval = 30 * 60
    private static let unavailableFor: TimeInterval = 5 * 60
    private static let schemes = ["https://", "http://"]

    private static let lock = NSLock()
    private static var verdicts: [String: (available: Bool, expiresAt: Date)] = [:]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    static func isAvailable(ingestURL: String) async -> Bool {
        let unsigned = ingestURL.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ingestURL
        guard let origin = origin(of: unsigned), let url = URL(string: unsigned) else { return false }
        lock.lock()
        let cached = verdicts[origin]
        lock.unlock()
        if let cached, cached.expiresAt > Date() { return cached.available }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        let answer: Bool? = await withCheckedContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                guard error == nil, let status = (response as? HTTPURLResponse)?.statusCode else {
                    continuation.resume(returning: nil)
                    return
                }
                let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                continuation.resume(returning: status != 404 && body is [String: Any])
            }.resume()
        }
        guard let answer else { return false }
        lock.lock()
        verdicts[origin] = (available: answer, expiresAt: Date().addingTimeInterval(answer ? availableFor : unavailableFor))
        lock.unlock()
        return answer
    }

    private static func origin(of url: String) -> String? {
        guard let scheme = schemes.first(where: { url.lowercased().hasPrefix($0) }) else { return nil }
        let host = url.dropFirst(scheme.count).prefix(while: { !"/?#".contains($0) })
        guard !host.isEmpty else { return nil }
        return scheme + host.lowercased()
    }
}

enum FileIngestError: Error {
    case busy
    case unreachable
    case uploadLost
    case unreadableFile
    case directUploadFailed
    case rejected(statusCode: Int)
}

private struct FileIngestStatus: Decodable {
    let received: [[Int64]]?
    let stored: Bool?
}

final class FileIngestUploader {

    static let shared = FileIngestUploader()

    private static let statusPollNanoseconds: UInt64 = 2_000_000_000
    private static let retryDelaySeconds: [UInt64] = [1, 2, 4, 8, 16, 30, 30, 30, 30, 30]
    private static let retryStatusCodes: Set<Int> = [408, 500, 503]

    private let session: URLSession
    private let lock = NSLock()
    private var activeUploads: Set<String> = []

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    func upload(
        fileURL: URL,
        size: Int64,
        presignedURL: String,
        ingestURL: String,
        contentType: String,
        onProgress: @escaping (Double) -> Void,
        onSent: @escaping () -> Void
    ) async throws {
        guard begin(ingestURL) else { throw FileIngestError.busy }
        defer { end(ingestURL) }
        guard let target = URL(string: ingestURL) else { throw FileIngestError.rejected(statusCode: 0) }

        let moov = FileIngest.moovAfterMdat(fileURL: fileURL, size: size)
        var status: FileIngestStatus?
        var retries = 0
        var announcedSent = false

        func accept(_ data: Data) throws {
            guard let decoded = try? JSONDecoder().decode(FileIngestStatus.self, from: data) else {
                throw FileIngestError.rejected(statusCode: 200)
            }
            status = decoded
            onProgress(Self.heldFraction(of: decoded, size: size))
        }

        func restart() throws {
            if FileIngest.isPresignedURLExpired(presignedURL) { throw FileIngestError.uploadLost }
            status = nil
            announcedSent = false
            onProgress(0)
        }

        if let existing = await getStatus(target), existing.code == 200 {
            try? accept(existing.data)
        }

        while true {
            let chunk = FileIngest.nextChunk(size: size, received: status?.received ?? [], moov: moov)
            if chunk == nil, !announcedSent {
                announcedSent = true
                onSent()
            }
            if chunk == nil, status?.stored == true {
                return
            }

            let answer: (code: Int, data: Data)?
            if let chunk {
                let body = try Self.read(fileURL, range: chunk)
                answer = await put(body, range: chunk, size: size, to: target)
            } else {
                try? await Task.sleep(nanoseconds: Self.statusPollNanoseconds)
                answer = await getStatus(target)
            }

            if let answer, answer.code == 200 {
                try accept(answer.data)
                retries = 0
                continue
            }
            if chunk != nil, let code = answer?.code,
               code == 403 || (status == nil && (code == 503 || code == 413)) {
                try await putDirectly(fileURL: fileURL, presignedURL: presignedURL, contentType: contentType, onProgress: onProgress)
                return
            }
            if chunk == nil, answer?.code == 404 {
                try restart()
                continue
            }
            if let code = answer?.code, !Self.retryStatusCodes.contains(code) {
                throw FileIngestError.rejected(statusCode: code)
            }

            var recovered = false
            while !recovered {
                guard retries < Self.retryDelaySeconds.count else {
                    throw FileIngestError.unreachable
                }
                try? await Task.sleep(nanoseconds: Self.retryDelaySeconds[retries] * 1_000_000_000)
                retries += 1
                let retryAnswer = await getStatus(target)
                if let retryAnswer, retryAnswer.code == 200 {
                    try accept(retryAnswer.data)
                    recovered = true
                } else if retryAnswer?.code == 404 {
                    try restart()
                    recovered = true
                } else if let code = retryAnswer?.code, !Self.retryStatusCodes.contains(code) {
                    throw FileIngestError.rejected(statusCode: code)
                }
            }
        }
    }

    private func begin(_ ingestURL: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return activeUploads.insert(ingestURL).inserted
    }

    private func end(_ ingestURL: String) {
        lock.lock(); activeUploads.remove(ingestURL); lock.unlock()
    }

    private func put(_ body: Data, range: ClosedRange<Int64>, size: Int64, to target: URL) async -> (code: Int, data: Data)? {
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("bytes \(range.lowerBound)-\(range.upperBound)/\(size)", forHTTPHeaderField: "Content-Range")
        return await withCheckedContinuation { continuation in
            session.uploadTask(with: request, from: body) { data, response, error in
                guard error == nil, let http = response as? HTTPURLResponse else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (http.statusCode, data ?? Data()))
            }.resume()
        }
    }

    private func getStatus(_ target: URL) async -> (code: Int, data: Data)? {
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        return await withCheckedContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                guard error == nil, let http = response as? HTTPURLResponse else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (http.statusCode, data ?? Data()))
            }.resume()
        }
    }

    private func putDirectly(
        fileURL: URL,
        presignedURL: String,
        contentType: String,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        do {
            _ = try await MinIOStreamingUploader.shared.put(
                url: presignedURL, fileURL: fileURL, contentType: contentType, onProgress: onProgress)
        } catch {
            throw FileIngestError.directUploadFailed
        }
    }

    private static func read(_ fileURL: URL, range: ClosedRange<Int64>) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { throw FileIngestError.unreadableFile }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(range.lowerBound))) != nil else { throw FileIngestError.unreadableFile }
        let length = Int(range.upperBound - range.lowerBound + 1)
        let data = handle.readData(ofLength: length)
        guard data.count == length else { throw FileIngestError.unreadableFile }
        return data
    }

    private static func heldFraction(of status: FileIngestStatus, size: Int64) -> Double {
        guard size > 0 else { return 0 }
        let held = (status.received ?? []).reduce(Int64(0)) { total, pair in
            pair.count == 2 ? total + pair[1] - pair[0] + 1 : total
        }
        return min(max(Double(held) / Double(size), 0), 1)
    }
}

struct FileIngestJob: Codable {
    let id: String
    let key: String
    let userId: String
    let fileName: String
    let size: Int64
    let presignedURL: String
    let ingestURL: String
    let contentType: String
    let clanId: Int64
    let channelId: Int64
    let mode: Int32
    let isPublic: Bool
    let topicId: Int64
    let messageId: Int64
    let createTimeSeconds: UInt32
    let outgoingBase: Data
    let mentions: Data
    let ingestKeys: [String]
    let createdAt: Date
}

final class FileIngestJobStore {

    static let shared = FileIngestJobStore()

    private static let maxAge: TimeInterval = 24 * 60 * 60
    private static let metadataExtension = "json"

    private let lock = NSLock()
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("FileIngestJobs", isDirectory: true)
    }

    @discardableResult
    func save(_ job: FileIngestJob, sourceFile: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let fileManager = FileManager.default
        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var excluded = directory
                try? excluded.setResourceValues(values)
            }
            let stored = directory.appendingPathComponent(job.fileName)
            if !fileManager.fileExists(atPath: stored.path) {
                do {
                    try fileManager.linkItem(at: sourceFile, to: stored)
                } catch {
                    try fileManager.copyItem(at: sourceFile, to: stored)
                }
            }
            try JSONEncoder().encode(job).write(to: metadataURL(for: job), options: .atomic)
            return true
        } catch {
            try? fileManager.removeItem(at: directory.appendingPathComponent(job.fileName))
            return false
        }
    }

    func fileURL(for job: FileIngestJob) -> URL {
        directory.appendingPathComponent(job.fileName)
    }

    func all() -> [FileIngestJob] {
        lock.lock(); defer { lock.unlock() }
        var jobs: [FileIngestJob] = []
        for job in loadAll() {
            if Date().timeIntervalSince(job.createdAt) > Self.maxAge {
                delete(job)
            } else {
                jobs.append(job)
            }
        }
        return jobs
    }

    func remove(keys: [String]) {
        guard !keys.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for job in loadAll() where keys.contains(where: { PresignFinishContent.presignKeysMatch($0, job.key) }) {
            delete(job)
        }
    }

    func remove(_ job: FileIngestJob) {
        lock.lock(); defer { lock.unlock() }
        delete(job)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
    }

    private func loadAll() -> [FileIngestJob] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { ($0 as NSString).pathExtension == Self.metadataExtension }
            .compactMap { name in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
                return try? JSONDecoder().decode(FileIngestJob.self, from: data)
            }
    }

    private func delete(_ job: FileIngestJob) {
        try? FileManager.default.removeItem(at: metadataURL(for: job))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(job.fileName))
    }

    private func metadataURL(for job: FileIngestJob) -> URL {
        directory.appendingPathComponent(job.id).appendingPathExtension(Self.metadataExtension)
    }
}

final class FileIngestResumer {

    static let shared = FileIngestResumer()

    private var isRunning = false

    private init() {}

    @MainActor
    func resume(context: AccountContext) {
        guard !isRunning, let userId = context.currentUser?.id, !userId.isEmpty else { return }
        isRunning = true
        Task { @MainActor in
            defer { self.isRunning = false }
            let jobs = await Task.detached(priority: .utility) { FileIngestJobStore.shared.all() }.value
            for job in jobs where job.userId == userId {
                await self.run(job, context: context)
            }
        }
    }

    @MainActor
    private func run(_ job: FileIngestJob, context: AccountContext) async {
        let fileURL = FileIngestJobStore.shared.fileURL(for: job)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            FileIngestJobStore.shared.remove(job)
            return
        }
        do {
            try await FileIngestUploader.shared.upload(
                fileURL: fileURL,
                size: job.size,
                presignedURL: job.presignedURL,
                ingestURL: job.ingestURL,
                contentType: job.contentType,
                onProgress: { _ in },
                onSent: {})
        } catch FileIngestError.busy {
            return
        } catch FileIngestError.unreachable {
            return
        } catch FileIngestError.directUploadFailed {
            return
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "FileIngestResumer.run",
                "messageId": job.messageId,
            ])
            FileIngestJobStore.shared.remove(job)
            return
        }
        if await patchMessage(job, context: context) {
            FileIngestJobStore.shared.remove(job)
        }
    }

    @MainActor
    private func patchMessage(_ job: FileIngestJob, context: AccountContext) async -> Bool {
        let record = context.account.postbox.read { tx in tx.getMessageById("\(job.messageId)") }
        let current = record?.content ?? Data()
        var finishedKeys = PresignFinishContent.parseKeys(from: current) ?? []
        if !finishedKeys.contains(where: { PresignFinishContent.presignKeysMatch($0, job.key) }) {
            finishedKeys.append(job.key)
        }
        var ingestKeys = PresignFinishContent.parseIngestKeys(from: current)
        for key in job.ingestKeys where !ingestKeys.contains(key) {
            ingestKeys.append(key)
        }
        let base = current.isEmpty ? job.outgoingBase : PresignFinishContent.presignSyncOriginContent(current)
        let localContent = PresignFinishContent.contentStringForSend(
            base: base, presignKeys: finishedKeys, ingestKeys: ingestKeys)
        let storedCreateTime = record.map { UInt32(max(0, $0.createdAt.timeIntervalSince1970)) } ?? 0
        let createTimeSeconds = storedCreateTime > 0 ? storedCreateTime : job.createTimeSeconds
        let content = PresignFinishContent.withCreateTimeSeconds(localContent, createTimeSeconds: createTimeSeconds)
        let mentionsData = (record?.mentionsJSON).flatMap { $0.isEmpty ? nil : $0 } ?? job.mentions
        let mentions = (try? Mezon_Api_MessageMentionList(serializedBytes: mentionsData))?.mentions ?? []
        guard let token = await context.getToken() else { return false }
        do {
            _ = try await context.account.network.updateChannelMessage(
                clanId: job.clanId,
                channelId: job.channelId,
                mode: job.mode,
                isPublic: job.isPublic,
                messageId: job.messageId,
                content: content,
                mentions: mentions,
                hideEditted: true,
                topicId: job.topicId != 0 ? job.topicId : nil,
                isUpdateMsgTopic: job.topicId != 0,
                createTimeSeconds: createTimeSeconds != 0 ? createTimeSeconds : nil,
                token: token
            )
            return true
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "FileIngestResumer.patchMessage",
                "messageId": job.messageId,
            ])
            return false
        }
    }
}
