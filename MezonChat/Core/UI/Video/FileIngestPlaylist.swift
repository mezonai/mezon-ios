import Foundation
import AVFoundation

enum FileIngestPlaylist {

    enum State {
        case unknown
        case playable(URL)
        case waitsForOriginal
    }

    struct Snapshot {
        let url: URL
        let ended: Bool
        let listedDuration: Double
        let targetDuration: Double
    }

    static let probeInterval: TimeInterval = 3
    static let pendingWindow: TimeInterval = 24 * 60 * 60

    private static let outputPrefix = "hls/"
    private static let indexName = "index.m3u8"
    private static let initSegmentName = "init.mp4"
    private static let playlistSuffix = ".m3u8"
    private static let playlistTag = "#EXTM3U"
    private static let endTag = "#EXT-X-ENDLIST"
    private static let variantTag = "#EXT-X-STREAM-INF"
    private static let mapPrefix = "#EXT-X-MAP:URI=\""
    private static let maxRemembered = 512
    private static let identityMatrixValue: Int32 = 0x10000

    private static let lock = NSLock()
    private static var markedURLs: [String] = []
    private static var markedSet: Set<String> = []
    private static var states: [String: State] = [:]
    private static var stateOrder: [String] = []
    private static var probesInFlight: Set<String> = []

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

    static func noteMarked(_ attachmentURL: String) {
        guard !attachmentURL.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard markedSet.insert(attachmentURL).inserted else { return }
        markedURLs.append(attachmentURL)
        if markedURLs.count > maxRemembered {
            markedSet.remove(markedURLs.removeFirst())
        }
    }

    static func isMarked(_ attachmentURL: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return markedSet.contains(attachmentURL)
    }

    static func state(for attachmentURL: String) -> State {
        lock.lock(); defer { lock.unlock() }
        return states[attachmentURL] ?? .unknown
    }

    static func isPlayable(_ attachmentURL: String) -> Bool {
        if case .playable = state(for: attachmentURL) { return true }
        return false
    }

    static func indexPlaylistURL(for attachmentURL: String) -> URL? {
        guard !attachmentURL.contains("#") else { return nil }
        let path = attachmentURL.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? attachmentURL
        guard let scheme = ["https://", "http://"].first(where: { path.lowercased().hasPrefix($0) }) else { return nil }
        let rest = path.dropFirst(scheme.count)
        guard let slash = rest.firstIndex(of: "/"), slash != rest.startIndex else { return nil }
        let origin = path[..<slash]
        let key = rest[rest.index(after: slash)...]
        let file = key.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        guard !file.isEmpty,
              !key.hasPrefix(outputPrefix),
              !file.lowercased().hasSuffix(playlistSuffix) else { return nil }
        return URL(string: "\(origin)/\(outputPrefix)\(key)/\(indexName)")
    }

    static func resolve(attachmentURL: String, coalescing: Bool = false, completion: @escaping (State) -> Void) {
        let cached = state(for: attachmentURL)
        if case .unknown = cached {} else {
            completion(cached)
            return
        }
        guard let playlist = indexPlaylistURL(for: attachmentURL), let probe = probeURL(for: playlist) else {
            completion(.unknown)
            return
        }
        if coalescing {
            lock.lock()
            let started = probesInFlight.insert(attachmentURL).inserted
            lock.unlock()
            guard started else {
                completion(.unknown)
                return
            }
        }
        let finish: (State) -> Void = { resolved in
            lock.lock()
            if coalescing { probesInFlight.remove(attachmentURL) }
            if case .unknown = resolved {} else { remember(resolved, for: attachmentURL) }
            lock.unlock()
            completion(resolved)
        }
        fetch(probe) { data in
            guard let data, String(decoding: data.prefix(playlistTag.utf8.count), as: UTF8.self) == playlistTag else {
                finish(.unknown)
                return
            }
            let initSegment = playlist.deletingLastPathComponent().appendingPathComponent(initSegmentName)
            fetch(initSegment) { initData in
                let turned = initData.map { hasTurnedVideoTrack([UInt8]($0)) } ?? false
                finish(turned ? .waitsForOriginal : .playable(playlist))
            }
        }
    }

    static func fetchSnapshot(playlist: URL, completion: @escaping (Snapshot?) -> Void) {
        guard let probe = probeURL(for: playlist) else {
            completion(nil)
            return
        }
        fetch(probe) { data in
            guard let data, let text = String(data: data, encoding: .utf8), text.hasPrefix(playlistTag) else {
                completion(nil)
                return
            }
            var listedDuration = 0.0
            var targetDuration = 0.0
            for line in text.split(whereSeparator: \.isNewline) {
                if line.hasPrefix("#EXTINF:") {
                    let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first ?? ""
                    listedDuration += Double(value) ?? 0
                } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                    targetDuration = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 0
                }
            }
            completion(Snapshot(
                url: probe,
                ended: text.contains(endTag),
                listedDuration: listedDuration,
                targetDuration: targetDuration))
        }
    }

    enum FinishedParts {
        case parts([URL])
        case missing
        case unfinished
        case unreachable
    }

    static func finishedParts(attachmentURL: String, completion: @escaping (FinishedParts) -> Void) {
        guard let playlist = indexPlaylistURL(for: attachmentURL), let probe = probeURL(for: playlist) else {
            completion(.missing)
            return
        }
        var request = URLRequest(url: probe, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let status = (response as? HTTPURLResponse)?.statusCode else {
                completion(.unreachable)
                return
            }
            guard (200..<300).contains(status) else {
                completion(status == 403 || status == 404 ? .missing : .unreachable)
                return
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if text.hasPrefix(playlistTag), !text.contains(endTag), !text.contains(variantTag) {
                completion(.unfinished)
                return
            }
            completion(downloadParts(playlist: playlist, text: text).map(FinishedParts.parts) ?? .missing)
        }.resume()
    }

    static func downloadParts(playlist: URL, text: String) -> [URL]? {
        guard text.hasPrefix(playlistTag), text.contains(endTag), !text.contains(variantTag) else { return nil }
        let directory = playlist.deletingLastPathComponent()
        var initSegment: URL?
        var segments: [URL] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix(mapPrefix) {
                let rest = line.dropFirst(mapPrefix.count)
                guard initSegment == nil,
                      let quote = rest.firstIndex(of: "\""), quote > rest.startIndex,
                      let url = partURL(String(rest[..<quote]), in: directory) else { return nil }
                initSegment = url
            } else if !line.hasPrefix("#") {
                guard let url = partURL(line, in: directory) else { return nil }
                segments.append(url)
            }
        }
        guard let initSegment, !segments.isEmpty else { return nil }
        return [initSegment] + segments
    }

    private static func partURL(_ uri: String, in directory: URL) -> URL? {
        uri.contains("://") ? URL(string: uri) : URL(string: uri, relativeTo: directory)?.absoluteURL
    }

    private static func probeURL(for playlist: URL) -> URL? {
        let window = Int64(Date().timeIntervalSince1970 * 1000) / Int64(probeInterval * 1000)
        return URL(string: "\(playlist.absoluteString)?probe=\(window)")
    }

    private static func remember(_ state: State, for attachmentURL: String) {
        if states.updateValue(state, forKey: attachmentURL) == nil {
            stateOrder.append(attachmentURL)
        }
        if stateOrder.count > maxRemembered {
            states.removeValue(forKey: stateOrder.removeFirst())
        }
    }

    private static func fetch(_ url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let status = (response as? HTTPURLResponse)?.statusCode,
                  (200..<300).contains(status) else {
                completion(nil)
                return
            }
            completion(data ?? Data())
        }.resume()
    }

    private static func hasTurnedVideoTrack(_ bytes: [UInt8], start: Int = 0, end: Int? = nil) -> Bool {
        let end = end ?? bytes.count
        var at = start
        while at + 8 <= end {
            let declared = Int(uint32(bytes, at))
            let size = declared == 0 ? end - at : declared
            if size < 8 || at + size > end { return false }
            let type = String(decoding: bytes[(at + 4)..<(at + 8)], as: UTF8.self)
            if type == "moov" || type == "trak", hasTurnedVideoTrack(bytes, start: at + 8, end: at + size) {
                return true
            }
            if type == "tkhd", isTurnedVideoHeader(bytes, at: at, size: size) {
                return true
            }
            at += size
        }
        return false
    }

    private static func isTurnedVideoHeader(_ bytes: [UInt8], at: Int, size: Int) -> Bool {
        guard size >= 92 else { return false }
        let matrix = at + 8 + (bytes[at + 8] == 1 ? 52 : 40)
        guard matrix + 44 <= at + size,
              uint32(bytes, matrix + 36) != 0,
              uint32(bytes, matrix + 40) != 0 else { return false }
        return int32(bytes, matrix) != identityMatrixValue
            || int32(bytes, matrix + 4) != 0
            || int32(bytes, matrix + 12) != 0
            || int32(bytes, matrix + 16) != identityMatrixValue
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func int32(_ bytes: [UInt8], _ offset: Int) -> Int32 {
        Int32(bitPattern: uint32(bytes, offset))
    }
}

enum FileIngestHLSCopy {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30 * 60
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    enum Outcome {
        case file(URL)
        case unavailable
        case stillUploading
        case unreachable
        case outOfSpace
        case failed
    }

    static func makeFile(
        attachmentURL: String,
        shouldContinue: @escaping () -> Bool = { true },
        progress: @escaping (Double) -> Void,
        completion: @escaping (Outcome) -> Void
    ) {
        FileIngestPlaylist.finishedParts(attachmentURL: attachmentURL) { finished in
            guard shouldContinue() else { completion(.failed); return }
            let parts: [URL]
            switch finished {
            case .parts(let found):
                parts = found
            case .missing:
                completion(.unavailable)
                return
            case .unfinished:
                completion(.stillUploading)
                return
            case .unreachable:
                completion(.unreachable)
                return
            }
            let joined = temporaryFileURL()
            guard FileManager.default.createFile(atPath: joined.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: joined) else {
                completion(.failed)
                return
            }
            append(parts, from: 0, to: handle, shouldContinue: shouldContinue, progress: progress) { failure in
                try? handle.close()
                if let failure {
                    try? FileManager.default.removeItem(at: joined)
                    completion(failure)
                    return
                }
                remux(joined) { output in
                    if output != nil {
                        try? FileManager.default.removeItem(at: joined)
                    }
                    completion(.file(output ?? joined))
                }
            }
        }
    }

    static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return true }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }

    private static func append(
        _ parts: [URL],
        from index: Int,
        to handle: FileHandle,
        shouldContinue: @escaping () -> Bool,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Outcome?) -> Void
    ) {
        guard shouldContinue() else { completion(.failed); return }
        guard index < parts.count else {
            completion(nil)
            return
        }
        session.downloadTask(with: parts[index]) { location, response, error in
            guard shouldContinue() else { completion(.failed); return }
            if let error {
                completion(isOutOfSpace(error) ? .outOfSpace : .unreachable)
                return
            }
            guard let status = (response as? HTTPURLResponse)?.statusCode else {
                completion(.unreachable)
                return
            }
            guard (200...299).contains(status), let location else {
                completion(status == 403 || status == 404 ? .unavailable : .unreachable)
                return
            }
            do {
                let data = try Data(contentsOf: location, options: .mappedIfSafe)
                try write(data, to: handle)
            } catch {
                completion(isOutOfSpace(error) ? .outOfSpace : .failed)
                return
            }
            progress(Double(index + 1) / Double(parts.count))
            append(parts, from: index + 1, to: handle, shouldContinue: shouldContinue, progress: progress, completion: completion)
        }.resume()
    }

    private static func write(_ data: Data, to handle: FileHandle) throws {
        if #available(iOS 13.4, *) {
            try handle.write(contentsOf: data)
        } else {
            handle.write(data)
        }
    }

    private static func remux(_ source: URL, completion: @escaping (URL?) -> Void) {
        let output = temporaryFileURL()
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough) else {
            completion(nil)
            return
        }
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            guard export.status == .completed else {
                try? FileManager.default.removeItem(at: output)
                completion(nil)
                return
            }
            completion(output)
        }
    }

    private static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hls-copy-\(UUID().uuidString).mp4")
    }
}
