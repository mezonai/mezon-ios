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

extension FileIngest {

    private static let hlsMoovLimit: UInt64 = 64 << 20
    private static let hlsTopBoxLimit = 1024
    private static let hlsTrackLimit = 16
    private static let hlsSampleLimit: UInt32 = 4 << 20
    private static let hlsSegmentLimit: UInt32 = 16384
    private static let hlsSegmentSeconds: UInt64 = 4
    private static let hlsTopBoxTypes: Set<String> = ["ftyp", "moov", "mdat", "free", "skip", "wide", "uuid", "pnot", "junk", "meta"]
    private static let hlsFragmentBoxTypes: Set<String> = ["moof", "styp", "sidx"]
    private static let aacSampleRates: [UInt32] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

    fileprivate struct HLSBytes {
        let storage: [UInt8]
        let lower: Int
        let upper: Int

        init(_ storage: [UInt8]) {
            self.init(storage: storage, lower: 0, upper: storage.count)
        }

        private init(storage: [UInt8], lower: Int, upper: Int) {
            self.storage = storage
            self.lower = lower
            self.upper = upper
        }

        var count: Int { upper - lower }

        subscript(_ index: Int) -> UInt8 { storage[lower + index] }

        func slice(from start: Int) -> HLSBytes {
            HLSBytes(storage: storage, lower: lower + start, upper: upper)
        }

        func slice(_ start: Int, _ end: Int) -> HLSBytes {
            HLSBytes(storage: storage, lower: lower + start, upper: lower + end)
        }

        func u16(_ at: Int) -> UInt32 {
            UInt32(self[at]) << 8 | UInt32(self[at + 1])
        }

        func u32(_ at: Int) -> UInt32 {
            let high = UInt32(self[at]) << 24 | UInt32(self[at + 1]) << 16
            let low = UInt32(self[at + 2]) << 8 | UInt32(self[at + 3])
            return high | low
        }

        func u64(_ at: Int) -> UInt64 {
            UInt64(u32(at)) << 32 | UInt64(u32(at + 4))
        }

        func type(_ at: Int) -> String {
            String(decoding: storage[(lower + at)..<(lower + at + 4)], as: UTF8.self)
        }
    }

    fileprivate struct HLSBoxCursor {
        var rest: HLSBytes

        mutating func next() -> (type: String, body: HLSBytes)? {
            guard rest.count >= 8 else { return nil }
            var size = UInt64(rest.u32(0))
            var header = 8
            if size == 1 {
                guard rest.count >= 16 else { return nil }
                size = rest.u64(8)
                header = 16
            } else if size == 0 {
                size = UInt64(rest.count)
            }
            guard size >= UInt64(header), size <= UInt64(rest.count) else { return nil }
            let end = Int(size)
            let box = (type: rest.type(4), body: rest.slice(header, end))
            rest = rest.slice(from: end)
            return box
        }
    }

    fileprivate struct HLSBitReader {
        let bytes: HLSBytes
        var bit = 0

        mutating func read(_ bits: Int) -> UInt32? {
            var value: UInt32 = 0
            for _ in 0..<bits {
                guard bit < bytes.count * 8 else { return nil }
                value = value << 1 | UInt32((bytes[bit / 8] >> UInt8(7 - bit % 8)) & 1)
                bit += 1
            }
            return value
        }
    }

    fileprivate struct HLSTrak {
        var tkhd: HLSBytes?
        var mdhd: HLSBytes?
        var hdlr: HLSBytes?
        var elst: HLSBytes?
        var stsd: HLSBytes?
        var stts: HLSBytes?
        var ctts: HLSBytes?
        var stss: HLSBytes?
        var stsz: HLSBytes?
        var stz2: HLSBytes?
        var stsc: HLSBytes?
        var stco: HLSBytes?
        var co64: HLSBytes?
    }

    fileprivate struct HLSVideoSample {
        var dts: UInt64 = 0
        var cto: Int32 = 0
        var sync = false
    }

    fileprivate struct HLSTrackTiming {
        let timescale: UInt32
        let editStart: UInt64
        let samples: [HLSVideoSample]
    }

    fileprivate enum HLSTrackCheck {
        case accepted(HLSTrackTiming)
        case rejected(String)
    }

    static func supportsHLS(fileURL: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            FileIngest.hlsProblem(fileURL: fileURL) == nil
        }.value
    }

    fileprivate static func hlsProblem(fileURL: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return "unreadable" }
        defer { try? handle.close() }
        let fileSize = size.uint64Value
        var offset: UInt64 = 0
        var moovOffset: UInt64 = 0
        var moovLength: UInt64 = 0
        var boxCount = 0
        while moovLength == 0 {
            if offset >= fileSize { return "no moov box" }
            let left = fileSize - offset
            if boxCount == hlsTopBoxLimit || left < 8 { return "bad top-level boxes" }
            guard let head = hlsRead(handle, at: offset, count: 8) else { return "unreadable" }
            var boxSize = UInt64(head.u32(0))
            var headerSize: UInt64 = 8
            if boxSize == 1 {
                if left < 16 { return "bad top-level boxes" }
                guard let large = hlsRead(handle, at: offset + 8, count: 8) else { return "unreadable" }
                boxSize = large.u64(0)
                headerSize = 16
            } else if boxSize == 0 {
                boxSize = left
            }
            let type = head.type(4)
            if hlsFragmentBoxTypes.contains(type) { return "fragmented MP4" }
            if boxCount == 0, !hlsTopBoxTypes.contains(type) { return "not an MP4 or MOV file" }
            if boxSize < headerSize || boxSize > left { return "box past the end of the file" }
            if type == "moov" {
                moovOffset = offset + headerSize
                moovLength = boxSize - headerSize
                if moovLength == 0 { return "empty moov" }
            }
            offset += boxSize
            boxCount += 1
        }
        if moovLength > hlsMoovLimit { return "moov over 64 MiB" }
        guard let moov = hlsRead(handle, at: moovOffset, count: Int(moovLength)) else { return "unreadable" }
        return hlsMoovProblem(moov, fileSize: fileSize)
    }

    private static func hlsRead(_ handle: FileHandle, at offset: UInt64, count: Int) -> HLSBytes? {
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        let data = handle.readData(ofLength: count)
        return data.count == count ? HLSBytes([UInt8](data)) : nil
    }

    private static func hlsChild(_ parent: HLSBytes, _ type: String) -> HLSBytes? {
        var cursor = HLSBoxCursor(rest: parent)
        while let box = cursor.next() {
            if box.type == type { return box.body }
        }
        return nil
    }

    private static func hlsTrak(_ trak: HLSBytes) -> HLSTrak {
        var boxes = HLSTrak()
        boxes.tkhd = hlsChild(trak, "tkhd")
        boxes.elst = hlsChild(trak, "edts").flatMap { hlsChild($0, "elst") }
        guard let mdia = hlsChild(trak, "mdia") else { return boxes }
        boxes.mdhd = hlsChild(mdia, "mdhd")
        boxes.hdlr = hlsChild(mdia, "hdlr")
        if let stbl = hlsChild(mdia, "minf").flatMap({ hlsChild($0, "stbl") }) {
            boxes.stsd = hlsChild(stbl, "stsd")
            boxes.stts = hlsChild(stbl, "stts")
            boxes.ctts = hlsChild(stbl, "ctts")
            boxes.stss = hlsChild(stbl, "stss")
            boxes.stsz = hlsChild(stbl, "stsz")
            boxes.stz2 = hlsChild(stbl, "stz2")
            boxes.stsc = hlsChild(stbl, "stsc")
            boxes.stco = hlsChild(stbl, "stco")
            boxes.co64 = hlsChild(stbl, "co64")
        }
        return boxes
    }

    private static func hlsTimescale(_ box: HLSBytes) -> UInt32 {
        guard box.count >= 24 else { return 0 }
        if box[0] == 1 {
            return box.count >= 32 ? box.u32(20) : 0
        }
        return box.u32(12)
    }

    private static func hlsTable(_ box: HLSBytes?, _ entrySize: Int) -> UInt32? {
        guard let box, box.count >= 8 else { return nil }
        let count = box.u32(4)
        return UInt64(count) <= UInt64((box.count - 8) / entrySize) ? count : nil
    }

    private static func hlsParseAudioSpecificConfig(_ config: HLSBytes) -> Bool {
        var reader = HLSBitReader(bytes: config)
        guard let objectType = reader.read(5) else { return false }
        if objectType == 31, reader.read(6) == nil { return false }
        guard let index = reader.read(4) else { return false }
        let rate: UInt32
        if index == 15 {
            guard let explicitRate = reader.read(24) else { return false }
            rate = explicitRate
        } else if Int(index) < aacSampleRates.count {
            rate = aacSampleRates[Int(index)]
        } else {
            return false
        }
        return reader.read(4) != nil && rate > 0
    }

    private static func hlsDescriptor(_ stream: inout HLSBytes) -> (tag: UInt8, body: HLSBytes)? {
        guard stream.count >= 2 else { return nil }
        let tag = stream[0]
        var index = 1
        var length = 0
        var lengthBytes = 0
        while true {
            guard index < stream.count, lengthBytes < 4 else { return nil }
            let byte = stream[index]
            index += 1
            lengthBytes += 1
            length = length << 7 | Int(byte & 0x7f)
            if byte & 0x80 == 0 { break }
        }
        guard length <= stream.count - index else { return nil }
        let body = stream.slice(index, index + length)
        stream = stream.slice(from: index + length)
        return (tag, body)
    }

    private static func hlsAudioSpecificConfig(_ esds: HLSBytes) -> HLSBytes? {
        guard esds.count >= 4 else { return nil }
        var stream = esds.slice(from: 4)
        guard let elementary = hlsDescriptor(&stream), elementary.tag == 0x03, elementary.body.count >= 3 else { return nil }
        let flags = elementary.body[2]
        var skip = 3 + (flags & 0x80 != 0 ? 2 : 0)
        if flags & 0x40 != 0 {
            guard elementary.body.count > skip else { return nil }
            skip += 1 + Int(elementary.body[skip])
        }
        skip += flags & 0x20 != 0 ? 2 : 0
        guard skip <= elementary.body.count else { return nil }
        var rest = elementary.body.slice(from: skip)
        while let descriptor = hlsDescriptor(&rest) {
            if descriptor.tag != 0x04 { continue }
            guard descriptor.body.count >= 13, descriptor.body[0] == 0x40 else { return nil }
            var nested = descriptor.body.slice(from: 13)
            while let info = hlsDescriptor(&nested) {
                if info.tag == 0x05 { return info.body }
            }
            return nil
        }
        return nil
    }

    private static func hlsVideoEntryProblem(_ type: String, _ entry: HLSBytes, width: UInt32, height: UInt32) -> String? {
        let isAVC = type == "avc1" || type == "avc3"
        let isHEVC = type == "hvc1" || type == "hev1"
        guard isAVC || isHEVC else { return "video is not H.264 or HEVC" }
        guard entry.count >= 86 else { return "short video sample entry" }
        guard let config = hlsChild(entry.slice(from: 86), isAVC ? "avcC" : "hvcC"),
              config.count >= (isAVC ? 4 : 23), config[0] == 1 else {
            return isAVC ? "no avcC" : "no hvcC"
        }
        var pictureWidth = width
        var pictureHeight = height
        if pictureWidth == 0 || pictureHeight == 0 {
            pictureWidth = entry.u16(32)
            pictureHeight = entry.u16(34)
        }
        return pictureWidth > 0 && pictureHeight > 0 ? nil : "no picture size"
    }

    private static func hlsAudioEntryProblem(_ type: String, _ entry: HLSBytes) -> String? {
        guard entry.count >= 36 else { return "short audio sample entry" }
        if type == "Opus" {
            guard let dOps = hlsChild(entry.slice(from: 36), "dOps"), dOps.count >= 11 else { return "no dOps" }
            return nil
        }
        guard type == "mp4a" else { return "audio is not AAC or Opus" }
        let version = entry.u16(16)
        let boxesStart: Int
        switch version {
        case 1: boxesStart = 52
        case 2: boxesStart = 72
        default: boxesStart = 36
        }
        guard version <= 2, entry.count >= boxesStart else { return "unknown sound sample description" }
        let rest = entry.slice(from: boxesStart)
        guard let esds = hlsChild(rest, "esds") ?? hlsChild(rest, "wave").flatMap({ hlsChild($0, "esds") }) else {
            return "no esds"
        }
        guard let config = hlsAudioSpecificConfig(esds), config.count > 0, config.count <= 64,
              hlsParseAudioSpecificConfig(config) else {
            return "audio is not AAC"
        }
        return nil
    }

    private static func hlsSampleSize(_ table: HLSBytes, fixed: UInt32, field: UInt32, index: Int) -> UInt32 {
        if fixed != 0 { return fixed }
        switch field {
        case 32: return table.u32(4 * index)
        case 16: return table.u16(2 * index)
        case 8: return UInt32(table[index])
        default: return UInt32((table[index / 2] >> (index % 2 == 0 ? 4 : 0)) & 15)
        }
    }

    private static func hlsCheckTrack(_ boxes: HLSTrak, video: Bool, movieTimescale: UInt32, fileSize: UInt64) -> HLSTrackCheck {
        let timescale = boxes.mdhd.map(hlsTimescale) ?? 0
        guard let tkhd = boxes.tkhd, let stsd = boxes.stsd, timescale != 0,
              tkhd.count >= 84, !(tkhd[0] == 1 && tkhd.count < 96), stsd.count >= 16 else {
            return .rejected("track without timescale, tkhd or stsd")
        }
        let matrixOffset = tkhd[0] == 1 ? 52 : 40
        let width = tkhd.u32(matrixOffset + 36) >> 16
        let height = tkhd.u32(matrixOffset + 40) >> 16

        let entryLength = Int(stsd.u32(8))
        guard stsd.u32(4) != 0, entryLength >= 8, entryLength <= stsd.count - 8 else { return .rejected("bad stsd") }
        let entry = stsd.slice(8, 8 + entryLength)
        let type = entry.type(4)
        let entryProblem = video
            ? hlsVideoEntryProblem(type, entry, width: width, height: height)
            : hlsAudioEntryProblem(type, entry)
        if let entryProblem { return .rejected(entryProblem) }

        let sizes: HLSBytes
        let fixed: UInt32
        let field: UInt32
        let count: UInt32
        if let stsz = boxes.stsz {
            guard stsz.count >= 12 else { return .rejected("short stsz") }
            sizes = stsz
            fixed = stsz.u32(4)
            field = 32
            count = stsz.u32(8)
        } else if let stz2 = boxes.stz2, stz2.count >= 12 {
            let fieldSize = UInt32(stz2[7])
            guard fieldSize == 4 || fieldSize == 8 || fieldSize == 16 else { return .rejected("bad stz2 field size") }
            sizes = stz2
            fixed = 0
            field = fieldSize
            count = stz2.u32(8)
        } else {
            return .rejected("no stsz")
        }
        if count == 0 {
            return video
                ? .rejected("video track without samples")
                : .accepted(HLSTrackTiming(timescale: timescale, editStart: 0, samples: []))
        }
        guard count <= hlsSampleLimit else { return .rejected("over 4 million samples in a track") }
        if fixed == 0, UInt64(count) * UInt64(field) > UInt64(sizes.count - 12) * 8 {
            return .rejected("stsz shorter than its count")
        }
        let sizeTable = sizes.slice(from: 12)
        let sampleCount = Int(count)
        for index in 0..<sampleCount where hlsSampleSize(sizeTable, fixed: fixed, field: field, index: index) >= 1 << 31 {
            return .rejected("sample over 2 GiB")
        }

        var samples = video ? [HLSVideoSample](repeating: HLSVideoSample(), count: sampleCount) : []

        guard let stts = boxes.stts, let sttsCount = hlsTable(stts, 8) else { return .rejected("bad stts") }
        var timed = 0
        var dts: UInt64 = 0
        for entryIndex in 0..<Int(sttsCount) {
            if timed >= sampleCount { break }
            let repeats = stts.u32(8 + 8 * entryIndex)
            let delta = UInt64(stts.u32(12 + 8 * entryIndex))
            var repeated: UInt32 = 0
            while repeated < repeats, timed < sampleCount {
                if video { samples[timed].dts = dts }
                dts = dts &+ delta
                timed += 1
                repeated += 1
            }
        }
        guard timed == sampleCount else { return .rejected("stts covers fewer samples than stsz") }
        let endDTS = dts

        if let ctts = boxes.ctts {
            guard let cttsCount = hlsTable(ctts, 8) else { return .rejected("bad ctts") }
            if video {
                var shifted = 0
                for entryIndex in 0..<Int(cttsCount) {
                    if shifted >= sampleCount { break }
                    let repeats = ctts.u32(8 + 8 * entryIndex)
                    let offset = Int32(bitPattern: ctts.u32(12 + 8 * entryIndex))
                    var repeated: UInt32 = 0
                    while repeated < repeats, shifted < sampleCount {
                        samples[shifted].cto = offset
                        shifted += 1
                        repeated += 1
                    }
                }
            }
        }

        if let stss = boxes.stss {
            guard let stssCount = hlsTable(stss, 4) else { return .rejected("bad stss") }
            for entryIndex in 0..<Int(stssCount) {
                let number = stss.u32(8 + 4 * entryIndex)
                guard number != 0, number <= count else { return .rejected("stss names a sample that does not exist") }
                if video { samples[Int(number) - 1].sync = true }
            }
        } else if video {
            for index in samples.indices { samples[index].sync = true }
        }

        let isWide = boxes.stco == nil
        guard let chunkOffsets = isWide ? boxes.co64 : boxes.stco,
              let chunkCount = hlsTable(chunkOffsets, isWide ? 8 : 4),
              let stsc = boxes.stsc, let stscCount = hlsTable(stsc, 12), stscCount != 0 else {
            return .rejected("bad stsc, stco or co64")
        }
        var placed = 0
        for entryIndex in 0..<Int(stscCount) {
            if placed >= sampleCount { break }
            let base = 8 + 12 * entryIndex
            let first = UInt64(stsc.u32(base))
            let perChunk = stsc.u32(base + 4)
            let next = entryIndex + 1 < Int(stscCount) ? UInt64(stsc.u32(base + 12)) : UInt64(chunkCount) + 1
            if first == 0 || (entryIndex == 0 && first != 1) || next <= first || next > UInt64(chunkCount) + 1 || perChunk == 0 {
                return .rejected("bad stsc")
            }
            if stsc.u32(base + 8) != 1 { return .rejected("more than one sample description") }
            var chunk = first
            while chunk < next, placed < sampleCount {
                let chunkIndex = Int(chunk - 1)
                var offset = isWide ? chunkOffsets.u64(8 + 8 * chunkIndex) : UInt64(chunkOffsets.u32(8 + 4 * chunkIndex))
                var inChunk: UInt32 = 0
                while inChunk < perChunk, placed < sampleCount {
                    let size = UInt64(hlsSampleSize(sizeTable, fixed: fixed, field: field, index: placed))
                    if offset > fileSize || size > fileSize - offset { return .rejected("sample past the end of the file") }
                    offset += size
                    placed += 1
                    inChunk += 1
                }
                chunk += 1
            }
        }
        guard placed == sampleCount else { return .rejected("chunks hold fewer samples than stsz") }

        var editStart: UInt64 = 0
        if let elst = boxes.elst {
            let isVersion1 = elst.count > 0 && elst[0] == 1
            let entrySize = isVersion1 ? 20 : 12
            guard let elstCount = hlsTable(elst, entrySize) else { return .rejected("bad elst") }
            var delay: Double = 0
            for entryIndex in 0..<Int(elstCount) {
                let base = 8 + entryIndex * entrySize
                let duration = isVersion1 ? elst.u64(base) : UInt64(elst.u32(base))
                let media = isVersion1
                    ? Int64(bitPattern: elst.u64(base + 8))
                    : Int64(Int32(bitPattern: elst.u32(base + 4)))
                if media == -1 {
                    delay += Double(duration)
                    continue
                }
                if media < 0 || UInt64(media) > endDTS { return .rejected("edit outside the track") }
                editStart = UInt64(media)
                break
            }
            if movieTimescale > 0, delay > 0, delay * Double(timescale) / Double(movieTimescale) > Double(UInt32.max) {
                return .rejected("edit delay too long")
            }
        }

        if video {
            var lowest: Int64 = 0
            var highest: Int64 = 0
            for sample in samples {
                lowest = min(lowest, Int64(sample.cto))
                highest = max(highest, Int64(sample.cto))
            }
            if highest - lowest > Int64(Int32.max) { return .rejected("composition offsets out of range") }
        }
        return .accepted(HLSTrackTiming(timescale: timescale, editStart: editStart, samples: samples))
    }

    private static func hlsMoovProblem(_ moov: HLSBytes, fileSize: UInt64) -> String? {
        var video: (boxes: HLSTrak, enabled: Bool)?
        var audio: (boxes: HLSTrak, enabled: Bool)?
        var movieTimescale: UInt32 = 0
        var trakCount = 0
        var cursor = HLSBoxCursor(rest: moov)
        while let box = cursor.next() {
            if box.type == "mvex" { return "fragmented MP4" }
            if box.type == "mvhd" { movieTimescale = hlsTimescale(box.body) }
            guard box.type == "trak" else { continue }
            trakCount += 1
            if trakCount > hlsTrackLimit { return "more than 16 tracks" }
            let boxes = hlsTrak(box.body)
            guard let hdlr = boxes.hdlr, let tkhd = boxes.tkhd, hdlr.count >= 12, tkhd.count >= 4 else { continue }
            let enabled = tkhd[3] & 1 != 0
            switch hdlr.type(8) {
            case "vide":
                if video == nil || (enabled && video?.enabled == false) { video = (boxes, enabled) }
            case "soun":
                if audio == nil || (enabled && audio?.enabled == false) { audio = (boxes, enabled) }
            default:
                break
            }
        }
        guard let videoBoxes = video?.boxes else { return "no video track" }
        let timing: HLSTrackTiming
        switch hlsCheckTrack(videoBoxes, video: true, movieTimescale: movieTimescale, fileSize: fileSize) {
        case .accepted(let checked): timing = checked
        case .rejected(let reason): return reason
        }
        if let audioBoxes = audio?.boxes,
           case .rejected(let reason) = hlsCheckTrack(audioBoxes, video: false, movieTimescale: movieTimescale, fileSize: fileSize) {
            return reason
        }
        let samples = timing.samples
        guard var first = samples.firstIndex(where: { $0.sync }) else { return "no video keyframe" }
        let editStart = Int64(bitPattern: timing.editStart)
        let presentationTime: (HLSVideoSample) -> Int64 = { Int64(bitPattern: $0.dts) &+ Int64($0.cto) }
        if presentationTime(samples[first]) < editStart {
            while first < samples.count, !(samples[first].sync && presentationTime(samples[first]) >= editStart) {
                first += 1
            }
        }
        guard first < samples.count else { return "no keyframe from the video edit's start on" }
        let step = hlsSegmentSeconds * UInt64(timing.timescale)
        var segments: UInt32 = 1
        var segmentStart = first
        for index in (first + 1)..<samples.count
        where samples[index].sync && samples[index].dts &- samples[segmentStart].dts >= step {
            segments += 1
            segmentStart = index
        }
        return segments > hlsSegmentLimit ? "over 16384 segments" : nil
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
