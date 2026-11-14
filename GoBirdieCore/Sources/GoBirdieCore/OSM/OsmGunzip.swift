import Compression
import Foundation

enum OsmDataError: Error {
    case badGzip
    case decompressFailed
    case downloadFailed
}

/// Streams a gzip file to `destination` in chunks, so the decompressed region never sits in memory whole.
/// Reads the gzip header itself, then hands the raw deflate data to the Compression framework.
func gunzipFile(at source: URL, to destination: URL) throws {
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let payloadStart = try gzipPayloadOffset(input)
    try input.seek(toOffset: payloadStart)

    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }

    let chunk = 256 * 1024
    let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    defer {
        srcBuffer.deallocate()
        dstBuffer.deallocate()
    }

    var stream = compression_stream(
        dst_ptr: dstBuffer, dst_size: 0,
        src_ptr: UnsafePointer(srcBuffer), src_size: 0,
        state: nil
    )
    guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
        throw OsmDataError.decompressFailed
    }
    defer { compression_stream_destroy(&stream) }

    var inputDone = false
    while true {
        if stream.src_size == 0 && !inputDone {
            let data = try input.read(upToCount: chunk) ?? Data()
            if data.isEmpty {
                inputDone = true
            } else {
                data.copyBytes(to: srcBuffer, count: data.count)
                stream.src_ptr = UnsafePointer(srcBuffer)
                stream.src_size = data.count
            }
        }

        stream.dst_ptr = dstBuffer
        stream.dst_size = chunk
        let flags: Int32 = inputDone ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
        let status = compression_stream_process(&stream, flags)

        let produced = chunk - stream.dst_size
        if produced > 0 {
            try output.write(contentsOf: Data(bytes: dstBuffer, count: produced))
        }
        if status == COMPRESSION_STATUS_END { return }
        if status == COMPRESSION_STATUS_ERROR { throw OsmDataError.decompressFailed }
    }
}

/// Byte offset where the deflate data starts, after the gzip header (RFC 1952).
private func gzipPayloadOffset(_ file: FileHandle) throws -> UInt64 {
    try file.seek(toOffset: 0)
    guard let head = try file.read(upToCount: 10), head.count == 10,
          head[0] == 0x1f, head[1] == 0x8b, head[2] == 8 else {
        throw OsmDataError.badGzip
    }
    let flags = head[3]
    var offset: UInt64 = 10
    if flags & 0x04 != 0 {  // FEXTRA: 2-byte length, then the field
        try file.seek(toOffset: offset)
        guard let lenBytes = try file.read(upToCount: 2), lenBytes.count == 2 else {
            throw OsmDataError.badGzip
        }
        offset += 2 + UInt64(lenBytes[0]) + (UInt64(lenBytes[1]) << 8)
    }
    if flags & 0x08 != 0 {  // FNAME: zero-terminated
        offset = try skipZeroTerminated(file, from: offset)
    }
    if flags & 0x10 != 0 {  // FCOMMENT: zero-terminated
        offset = try skipZeroTerminated(file, from: offset)
    }
    if flags & 0x02 != 0 {  // FHCRC
        offset += 2
    }
    return offset
}

private func skipZeroTerminated(_ file: FileHandle, from start: UInt64) throws -> UInt64 {
    try file.seek(toOffset: start)
    var offset = start
    while let bytes = try file.read(upToCount: 1), let byte = bytes.first {
        offset += 1
        if byte == 0 { break }
    }
    return offset
}
