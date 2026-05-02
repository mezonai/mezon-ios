import Foundation
import zlib

enum PeerWebRTCStringCompression {

    enum CompressError: Error {
        case invalidUTF8
        case invalidBase64
        case zlib(Int32)
        case badUTF8Output
    }

    static func gzipCompressUtf8(_ string: String) throws -> String {
        guard let raw = string.data(using: .utf8) else { throw CompressError.invalidUTF8 }
        let compressed = try gzipCompress(raw)
        return compressed.base64EncodedString()
    }

    static func gzipDecompressUtf8(_ base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64) else { throw CompressError.invalidBase64 }
        let raw = try gzipDecompress(data)
        guard let s = String(data: raw, encoding: .utf8) else { throw CompressError.badUTF8Output }
        return s
    }

    static func decompressSignalingJson(_ payload: String) throws -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        return try gzipDecompressUtf8(trimmed)
    }

    private static func gzipCompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        var inputBuffer = [UInt8](data)
        let initStatus: Int32 = inputBuffer.withUnsafeMutableBytes { raw in
            guard let ptr = raw.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = ptr
            stream.avail_in = UInt32(raw.count)
            return deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                MAX_WBITS + 16,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        }
        guard initStatus == Z_OK else {
            throw CompressError.zlib(initStatus)
        }

        var output = Data()
        let chunkCap = 32768
        let outBuf = UnsafeMutablePointer<Bytef>.allocate(capacity: chunkCap)
        defer { outBuf.deallocate() }
        while true {
            stream.next_out = outBuf
            stream.avail_out = UInt32(chunkCap)
            let deflateStatus = deflate(&stream, Z_FINISH)
            let have = chunkCap - Int(stream.avail_out)
            if have > 0 {
                output.append(UnsafeBufferPointer(start: outBuf, count: have))
            }
            if deflateStatus == Z_STREAM_END {
                break
            }
            guard deflateStatus == Z_OK else {
                deflateEnd(&stream)
                throw CompressError.zlib(deflateStatus)
            }
        }
        deflateEnd(&stream)
        return output
    }

    private static func gzipDecompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        var inputBuffer = [UInt8](data)
        let initStatus: Int32 = inputBuffer.withUnsafeMutableBytes { raw in
            guard let ptr = raw.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = ptr
            stream.avail_in = UInt32(raw.count)
            return inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initStatus == Z_OK else {
            throw CompressError.zlib(initStatus)
        }

        var output = Data()
        let chunkCap = 32768
        let outBuf = UnsafeMutablePointer<Bytef>.allocate(capacity: chunkCap)
        defer { outBuf.deallocate() }
        while true {
            stream.next_out = outBuf
            stream.avail_out = UInt32(chunkCap)
            let inflateStatus = inflate(&stream, Z_NO_FLUSH)
            let have = chunkCap - Int(stream.avail_out)
            if have > 0 {
                output.append(UnsafeBufferPointer(start: outBuf, count: have))
            }
            if inflateStatus == Z_STREAM_END {
                break
            }
            guard inflateStatus == Z_OK else {
                inflateEnd(&stream)
                throw CompressError.zlib(inflateStatus)
            }
        }
        inflateEnd(&stream)
        return output
    }
}
