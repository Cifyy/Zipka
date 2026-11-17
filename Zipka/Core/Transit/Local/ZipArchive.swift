//
//  ZipArchive.swift
//  Zipka
//

import Foundation
import Compression

/// Minimal read-only zip reader, enough for GTFS feeds: stored and deflated entries,
/// no zip64, no encryption. Entries are decompressed as a stream, so a 140 MB
/// `stop_times.txt` never has to be in memory at once.
nonisolated struct ZipArchive {
    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error {
        case notAZip
        case unsupported(String)
        case missingEntry(String)
        case corrupt
    }

    private let data: Data
    /// Entries keyed by file name without folders, since some feeds nest their files in a directory.
    private let entries: [String: Entry]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        entries = try Self.readCentralDirectory(data)
    }

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    /// Calls `body` with consecutive chunks of the entry's decompressed bytes.
    func stream(_ name: String, chunkSize: Int = 1 << 20, _ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        guard let entry = entries[name] else { throw ZipError.missingEntry(name) }
        let start = try dataOffset(of: entry)
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.corrupt }

        switch entry.method {
        case 0:
            var offset = start
            while offset < end {
                let next = min(offset + chunkSize, end)
                try data[offset..<next].withUnsafeBytes(body)
                offset = next
            }
        case 8:
            // Apple's `.zlib` is raw DEFLATE (RFC 1951), which is what zip stores.
            // The filter only calls back from within `write` and `finalize`, so `body` never outlives this call.
            try withoutActuallyEscaping(body) { body in
                let filter = try OutputFilter(.decompress, using: .zlib, bufferCapacity: chunkSize) { output in
                    if let output { try output.withUnsafeBytes(body) }
                }
                var offset = start
                while offset < end {
                    let next = min(offset + chunkSize, end)
                    try filter.write(data[offset..<next])
                    offset = next
                }
                try filter.finalize()
            }
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    private func dataOffset(of entry: Entry) throws -> Int {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, Self.read32(data, header) == 0x0403_4b50 else { throw ZipError.corrupt }
        let nameLength = Int(Self.read16(data, header + 26))
        let extraLength = Int(Self.read16(data, header + 28))
        return header + 30 + nameLength + extraLength
    }

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        // The end-of-central-directory record sits in the last 22 bytes plus an optional comment.
        guard data.count >= 22 else { throw ZipError.notAZip }
        let searchStart = max(0, data.count - 22 - 0xFFFF)
        var eocd: Int?
        var position = data.count - 22
        while position >= searchStart {
            if read32(data, position) == 0x0605_4b50 { eocd = position; break }
            position -= 1
        }
        guard let eocd else { throw ZipError.notAZip }

        let entryCount = Int(read16(data, eocd + 10))
        let directoryOffset = Int(read32(data, eocd + 16))
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw ZipError.unsupported("zip64") }

        var entries: [String: Entry] = [:]
        var offset = directoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, read32(data, offset) == 0x0201_4b50 else { throw ZipError.corrupt }
            let flags = read16(data, offset + 8)
            let method = read16(data, offset + 10)
            let compressedSize = Int(read32(data, offset + 20))
            let uncompressedSize = Int(read32(data, offset + 24))
            let nameLength = Int(read16(data, offset + 28))
            let extraLength = Int(read16(data, offset + 30))
            let commentLength = Int(read16(data, offset + 32))
            let localHeaderOffset = Int(read32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw ZipError.corrupt }
            let path = String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)

            if flags & 1 != 0 { throw ZipError.unsupported("encryption") }
            if compressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF { throw ZipError.unsupported("zip64") }

            if !path.hasSuffix("/") {
                let name = path.split(separator: "/").last.map(String.init) ?? path
                entries[name] = Entry(
                    path: path,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
}
