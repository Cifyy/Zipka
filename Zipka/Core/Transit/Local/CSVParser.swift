//
//  CSVParser.swift
//  Zipka
//

import Foundation

/// Incremental RFC 4180 parser that works on raw bytes as they come out of the zip,
/// handing each record to a callback without building strings for fields nobody reads.
nonisolated final class CSVParser {
    private var pending: [UInt8] = []
    private var starts: [Int] = []
    private var ends: [Int] = []
    private var escaped: [Bool] = []
    private var isFirstChunk = true

    private static let quote = UInt8(ascii: "\"")
    private static let comma = UInt8(ascii: ",")
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    /// Parses the complete records in `chunk`; the unfinished tail is kept for the next call.
    func consume(_ chunk: UnsafeRawBufferPointer, _ onRecord: (CSVRecord) throws -> Void) throws {
        var bytes = UnsafeRawBufferPointer(chunk)
        if isFirstChunk {
            isFirstChunk = false
            // Skip a UTF-8 byte order mark.
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
                bytes = UnsafeRawBufferPointer(rebasing: bytes[3...])
            }
        }
        if let base = bytes.baseAddress {
            pending.append(contentsOf: UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: bytes.count))
        }
        try parsePending(isFinal: false, onRecord)
    }

    /// Parses whatever is left once the input has ended.
    func finish(_ onRecord: (CSVRecord) throws -> Void) throws {
        try parsePending(isFinal: true, onRecord)
        pending.removeAll()
    }

    private func parsePending(isFinal: Bool, _ onRecord: (CSVRecord) throws -> Void) throws {
        let consumed = try pending.withUnsafeBufferPointer { buffer in
            try parse(buffer, isFinal: isFinal, onRecord)
        }
        pending.removeSubrange(0..<consumed)
    }

    /// Returns how many bytes were consumed by complete records.
    private func parse(_ buffer: UnsafeBufferPointer<UInt8>, isFinal: Bool, _ onRecord: (CSVRecord) throws -> Void) throws -> Int {
        let count = buffer.count
        var recordStart = 0

        records: while recordStart < count {
            starts.removeAll(keepingCapacity: true)
            ends.removeAll(keepingCapacity: true)
            escaped.removeAll(keepingCapacity: true)
            var index = recordStart

            fields: while true {
                if index < count, buffer[index] == Self.quote {
                    var cursor = index + 1
                    var hasEscapes = false
                    while true {
                        guard cursor < count else {
                            if isFinal { break }
                            break records
                        }
                        if buffer[cursor] == Self.quote {
                            if cursor + 1 < count, buffer[cursor + 1] == Self.quote {
                                hasEscapes = true
                                cursor += 2
                                continue
                            }
                            // A quote at the very end might be the first half of an escaped pair.
                            if cursor + 1 >= count, !isFinal { break records }
                            break
                        }
                        cursor += 1
                    }
                    starts.append(index + 1)
                    ends.append(min(cursor, count))
                    escaped.append(hasEscapes)
                    index = cursor + 1
                    while index < count, buffer[index] != Self.comma, buffer[index] != Self.lineFeed {
                        index += 1
                    }
                } else {
                    var cursor = index
                    while cursor < count, buffer[cursor] != Self.comma, buffer[cursor] != Self.lineFeed {
                        cursor += 1
                    }
                    var end = cursor
                    if end > index, buffer[end - 1] == Self.carriageReturn { end -= 1 }
                    starts.append(index)
                    ends.append(end)
                    escaped.append(false)
                    index = cursor
                }

                if index >= count {
                    guard isFinal else { break records }
                    index = count
                    break fields
                }
                if buffer[index] == Self.comma {
                    index += 1
                    continue fields
                }
                index += 1 // line feed
                break fields
            }

            let isBlankLine = starts.count == 1 && ends[0] <= starts[0]
            if !isBlankLine {
                try onRecord(CSVRecord(buffer: buffer, starts: starts, ends: ends, escaped: escaped))
            }
            recordStart = index
        }
        return recordStart
    }
}

/// One CSV record. Only valid inside the callback that receives it.
nonisolated struct CSVRecord {
    fileprivate let buffer: UnsafeBufferPointer<UInt8>
    fileprivate let starts: [Int]
    fileprivate let ends: [Int]
    fileprivate let escaped: [Bool]

    var count: Int { starts.count }

    private func bytes(_ column: Int?) -> UnsafeBufferPointer<UInt8>? {
        guard let column, column < starts.count else { return nil }
        return UnsafeBufferPointer(rebasing: buffer[starts[column]..<ends[column]])
    }

    /// The field as text; empty when the column is missing.
    func string(_ column: Int?) -> String {
        guard let bytes = bytes(column), let column else { return "" }
        let value = String(decoding: bytes, as: UTF8.self)
        return escaped[column] ? value.replacingOccurrences(of: "\"\"", with: "\"") : value
    }

    /// The field as text, or `nil` when it is empty or the column is missing.
    func nonEmptyString(_ column: Int?) -> String? {
        let value = string(column)
        return value.isEmpty ? nil : value
    }

    func int(_ column: Int?) -> Int? {
        guard let bytes = trimmed(column), !bytes.isEmpty else { return nil }
        var value = 0
        var sign = 1
        var index = 0
        if bytes[0] == UInt8(ascii: "-") { sign = -1; index = 1 }
        guard index < bytes.count else { return nil }
        while index < bytes.count {
            let digit = Int(bytes[index]) - 48
            guard digit >= 0, digit <= 9 else { return nil }
            value = value * 10 + digit
            index += 1
        }
        return value * sign
    }

    /// A decimal degree value such as `50.088290` as millionths of a degree, rounded.
    func microdegrees(_ column: Int?) -> Int32? {
        guard let bytes = trimmed(column), !bytes.isEmpty else { return nil }
        var index = 0
        var negative = false
        if bytes[0] == UInt8(ascii: "-") || bytes[0] == UInt8(ascii: "+") {
            negative = bytes[0] == UInt8(ascii: "-")
            index = 1
        }
        var whole = 0
        var sawDigit = false
        while index < bytes.count, bytes[index] != UInt8(ascii: ".") {
            let digit = Int(bytes[index]) - 48
            guard digit >= 0, digit <= 9 else { return fallbackMicrodegrees(column) }
            whole = whole * 10 + digit
            sawDigit = true
            index += 1
        }
        var fraction = 0
        var digits = 0
        var roundUp = false
        if index < bytes.count {
            index += 1 // decimal point
            while index < bytes.count {
                let digit = Int(bytes[index]) - 48
                guard digit >= 0, digit <= 9 else { return fallbackMicrodegrees(column) }
                if digits < 6 {
                    fraction = fraction * 10 + digit
                    digits += 1
                } else if digits == 6 {
                    roundUp = digit >= 5
                    digits += 1
                }
                sawDigit = true
                index += 1
            }
        }
        guard sawDigit else { return nil }
        while digits < 6 { fraction *= 10; digits += 1 }
        var value = whole * 1_000_000 + fraction + (roundUp ? 1 : 0)
        if negative { value = -value }
        return Int32(clamping: value)
    }

    /// A GTFS time (`H:MM:SS`, hours may exceed 23) as seconds after the start of the service day.
    func gtfsTime(_ column: Int?) -> Int? {
        guard let bytes = trimmed(column), !bytes.isEmpty else { return nil }
        var parts = [0, 0, 0]
        var part = 0
        for byte in bytes {
            if byte == UInt8(ascii: ":") {
                part += 1
                guard part < 3 else { return nil }
                continue
            }
            let digit = Int(byte) - 48
            guard digit >= 0, digit <= 9 else { return nil }
            parts[part] = parts[part] * 10 + digit
        }
        guard part == 2 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private func trimmed(_ column: Int?) -> UnsafeBufferPointer<UInt8>? {
        guard var bytes = bytes(column) else { return nil }
        while let first = bytes.first, first == UInt8(ascii: " ") { bytes = UnsafeBufferPointer(rebasing: bytes.dropFirst()) }
        while let last = bytes.last, last == UInt8(ascii: " ") { bytes = UnsafeBufferPointer(rebasing: bytes.dropLast()) }
        return bytes
    }

    private func fallbackMicrodegrees(_ column: Int?) -> Int32? {
        guard let value = Double(string(column).trimmingCharacters(in: .whitespaces)) else { return nil }
        return Int32(clamping: Int((value * 1_000_000).rounded()))
    }
}

/// Column positions read from a CSV header row.
nonisolated struct CSVHeader {
    private let indices: [String: Int]

    init(_ record: CSVRecord) {
        var indices: [String: Int] = [:]
        for column in 0..<record.count {
            let name = record.string(column).trimmingCharacters(in: .whitespaces)
            if indices[name] == nil { indices[name] = column }
        }
        self.indices = indices
    }

    func optional(_ name: String) -> Int? {
        indices[name]
    }

    func required(_ name: String, in file: String) throws -> Int {
        guard let index = indices[name] else { throw GTFSImportError.missingColumn(name, file: file) }
        return index
    }
}

nonisolated enum GTFSImportError: Error {
    case missingColumn(String, file: String)
    case missingFile(String)
}

nonisolated extension ZipArchive {
    /// Streams a CSV file from the archive. `makeHandler` receives the header and returns
    /// the closure that is then called for every data row.
    func readCSV(_ name: String, _ makeHandler: (CSVHeader) throws -> (CSVRecord) throws -> Void) throws {
        guard contains(name) else { throw GTFSImportError.missingFile(name) }
        let parser = CSVParser()
        var handler: ((CSVRecord) throws -> Void)?
        func onRecord(_ record: CSVRecord) throws {
            if let handler {
                try handler(record)
            } else {
                handler = try makeHandler(CSVHeader(record))
            }
        }
        try stream(name) { chunk in
            try parser.consume(chunk, onRecord)
        }
        try parser.finish(onRecord)
    }
}
