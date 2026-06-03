import Foundation

struct UploadedAttachmentFile {
    let serverFilename: String
    let cdnURL: String
}

final class AttachmentUploadProgressStore {

    static let shared = AttachmentUploadProgressStore()
    private init() {}

    private let lock = NSLock()
    private var progressByKey: [String: Double] = [:]

    func setProgress(_ value: Double, forKey key: String) {
        guard !key.isEmpty else { return }
        let clamped = min(max(value, 0), 1)
        lock.lock(); progressByKey[key] = clamped; lock.unlock()
    }

    func progress(forKey key: String) -> Double {
        guard !key.isEmpty else { return 0 }
        lock.lock(); defer { lock.unlock() }
        return progressByKey[key] ?? 0
    }

    func clear(forKey key: String) {
        guard !key.isEmpty else { return }
        lock.lock(); progressByKey.removeValue(forKey: key); lock.unlock()
    }
}

final class AttachmentUploader {

    static let shared = AttachmentUploader()
    private init() {}

    private static let partSize = 10 * 1024 * 1024
    private static let minMultipartFileSize = 10 * 1024 * 1024
    private static let maxParallelParts = 3

    private struct MultipartNotApplicable: Error {}

    private let stateLock = NSLock()
    private var skipMultipartForSession = false

    private var shouldSkipMultipart: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return skipMultipartForSession
    }

    private func markMultipartUnavailable() {
        stateLock.lock(); skipMultipartForSession = true; stateLock.unlock()
    }

    func uploadFile(
        fileURL: URL,
        filename: String,
        filetype: String,
        fileSize: Int,
        width: Int = 0,
        height: Int = 0,
        token: String,
        progressKey: String = "",
        network: MezonHTTPClient
    ) async throws -> UploadedAttachmentFile {
        reportProgress(0, forKey: progressKey)

        if fileSize >= Self.minMultipartFileSize, !shouldSkipMultipart {
            do {
                return try await uploadMultipart(
                    fileURL: fileURL, filename: filename, filetype: filetype,
                    fileSize: fileSize, width: width, height: height,
                    token: token, progressKey: progressKey, network: network)
            } catch is MultipartNotApplicable {
                markMultipartUnavailable()
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "AttachmentUploader.uploadMultipart",
                    "filename": filename,
                    "fileSize": fileSize,
                ])
            }
        }

        return try await uploadSinglePut(
            fileURL: fileURL, filename: filename, filetype: filetype,
            fileSize: fileSize, width: width, height: height,
            token: token, progressKey: progressKey, network: network)
    }

    private func uploadSinglePut(
        fileURL: URL,
        filename: String,
        filetype: String,
        fileSize: Int,
        width: Int,
        height: Int,
        token: String,
        progressKey: String,
        network: MezonHTTPClient
    ) async throws -> UploadedAttachmentFile {
        let info = try await network.uploadAttachmentFile(
            filename: filename, filetype: filetype, size: fileSize,
            width: width, height: height, token: token)
        _ = try await MinIOStreamingUploader.shared.put(
            url: info.url, fileURL: fileURL, contentType: filetype
        ) { [weak self] fraction in
            self?.reportProgress(fraction, forKey: progressKey)
        }
        reportProgress(1, forKey: progressKey)
        return UploadedAttachmentFile(
            serverFilename: info.filename,
            cdnURL: "\(MezonConfig.baseImgURL)/\(info.filename)")
    }

    private func uploadMultipart(
        fileURL: URL,
        filename: String,
        filetype: String,
        fileSize: Int,
        width: Int,
        height: Int,
        token: String,
        progressKey: String,
        network: MezonHTTPClient
    ) async throws -> UploadedAttachmentFile {
        let requestedPartCount = max(1, Int((Double(fileSize) / Double(Self.partSize)).rounded(.up)))
        let start = try await network.multipartUploadAttachmentFileStart(
            filename: filename, filetype: filetype, size: fileSize,
            width: width, height: height, partCount: requestedPartCount, token: token)
        let urls = start.urls
        let uploadId = start.uploadID

        if urls.count == 1, uploadId.isEmpty {
            _ = try await MinIOStreamingUploader.shared.put(
                url: urls[0], fileURL: fileURL, contentType: filetype
            ) { [weak self] fraction in
                self?.reportProgress(fraction, forKey: progressKey)
            }
            reportProgress(1, forKey: progressKey)
            let serverFilename = start.filename.isEmpty ? filename : start.filename
            return UploadedAttachmentFile(
                serverFilename: serverFilename,
                cdnURL: "\(MezonConfig.baseImgURL)/\(serverFilename)")
        }

        if urls.isEmpty || uploadId.isEmpty {
            throw MultipartNotApplicable()
        }

        let partCount = urls.count
        let total = max(fileSize, 1)

        var collected: [(partNumber: Int, eTag: String)] = []
        collected.reserveCapacity(partCount)
        var uploadedBytes = 0

        try await withThrowingTaskGroup(of: (Int, String, Int).self) { group in
            var nextIndex = 0

            func submit() {
                guard nextIndex < partCount else { return }
                let index = nextIndex
                nextIndex += 1
                let offset = index * Self.partSize
                let end = (index == partCount - 1) ? fileSize : offset + Self.partSize
                let length = max(0, end - offset)
                let url = urls[index]
                let ft = filetype
                let furl = fileURL
                group.addTask {
                    let chunk = try Self.readChunk(fileURL: furl, offset: offset, length: length)
                    let etag = try await network.uploadPartToMinIO(url: url, data: chunk, contentType: ft)
                    return (index + 1, etag, length)
                }
            }

            for _ in 0..<min(Self.maxParallelParts, partCount) { submit() }

            while let (partNumber, etag, length) = try await group.next() {
                collected.append((partNumber, etag))
                uploadedBytes += length
                reportProgress(Double(uploadedBytes) / Double(total), forKey: progressKey)
                submit()
            }
        }

        collected.sort { $0.partNumber < $1.partNumber }

        let finish = try await network.multipartUploadAttachmentFileFinish(
            uploadId: uploadId, parts: collected, filename: start.filename, token: token)
        reportProgress(1, forKey: progressKey)

        let serverFilename: String = {
            if !finish.filename.isEmpty { return finish.filename }
            if !start.filename.isEmpty { return start.filename }
            return filename
        }()
        return UploadedAttachmentFile(
            serverFilename: serverFilename,
            cdnURL: "\(MezonConfig.baseImgURL)/\(serverFilename)")
    }

    private static func readChunk(fileURL: URL, offset: Int, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        if offset > 0 {
            try handle.seek(toOffset: UInt64(offset))
        }
        return handle.readData(ofLength: length)
    }

    private func reportProgress(_ value: Double, forKey key: String) {
        guard !key.isEmpty else { return }
        let previous = AttachmentUploadProgressStore.shared.progress(forKey: key)
        let clamped = min(max(value, 0), 1)
        AttachmentUploadProgressStore.shared.setProgress(clamped, forKey: key)

        let previousBucket = Int(previous * 100)
        let newBucket = Int(clamped * 100)
        guard newBucket != previousBucket || clamped >= 1 else { return }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .mezonAttachmentUploadProgress,
                object: nil,
                userInfo: ["key": key, "progress": clamped])
        }
    }
}

extension Notification.Name {
    static let mezonAttachmentUploadProgress = Notification.Name("mezon.attachment.uploadProgress")
}

final class MinIOStreamingUploader: NSObject, URLSessionTaskDelegate {

    static let shared = MinIOStreamingUploader()

    private var session: URLSession!
    private let lock = NSLock()
    private var progressHandlers: [Int: (Double) -> Void] = [:]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    @discardableResult
    func put(
        url: String,
        fileURL: URL,
        contentType: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> (etag: String?, statusCode: Int) {
        guard let uploadURL = URL(string: url) else {
            throw MezonError.httpError(statusCode: 0, message: "Invalid MinIO URL")
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: fileURL) { _, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: MezonError.invalidResponse)
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    continuation.resume(throwing: MezonError.httpError(
                        statusCode: http.statusCode, message: "MinIO upload failed"))
                    return
                }
                let raw = http.value(forHTTPHeaderField: "Etag") ?? http.value(forHTTPHeaderField: "ETag")
                let etag = raw?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                continuation.resume(returning: (etag?.isEmpty == false ? etag : nil, http.statusCode))
            }
            lock.lock()
            progressHandlers[task.taskIdentifier] = onProgress
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        lock.lock()
        let handler = progressHandlers[task.taskIdentifier]
        lock.unlock()
        handler?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        progressHandlers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
    }
}
