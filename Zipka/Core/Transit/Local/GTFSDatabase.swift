//
//  GTFSDatabase.swift
//  Zipka
//

import Foundation

/// Read side of the database written by `GTFSImporter`.
nonisolated final class GTFSDatabase {
    private let database: SQLiteDatabase
    private let summaryQuery: SQLiteStatement
    private let tripKeyQuery: SQLiteStatement
    private let stopsQuery: SQLiteStatement
    private let shapeQuery: SQLiteStatement

    /// Opens the database, throwing `TransitDataError.notReady` if it was written by another schema version.
    init(url: URL) throws {
        database = try SQLiteDatabase(url: url, readOnly: true)

        let version = try database.prepare("SELECT value FROM meta WHERE key = 'schema_version'")
        guard try version.step(), Int(version.string(0)) == GTFSImporter.schemaVersion else {
            throw TransitDataError.notReady
        }

        summaryQuery = try database.prepare("""
            SELECT t.trip_id, t.route_id, COALESCE(r.short_name, t.route_id), t.headsign, t.direction_id, t.shape_id
            FROM trips t LEFT JOIN routes r ON r.route_id = t.route_id
            WHERE t.trip_id = ?
            """)
        tripKeyQuery = try database.prepare("SELECT trip_key FROM trips WHERE trip_id = ?")
        stopsQuery = try database.prepare("""
            SELECT st.seq, s.stop_id, s.name, s.lat, s.lon, st.arrival, st.departure
            FROM stop_times st JOIN stops s ON s.stop_key = st.stop_key
            WHERE st.trip_key = ?
            ORDER BY st.seq
            """)
        shapeQuery = try database.prepare("SELECT points FROM shapes WHERE shape_id = ?")
    }

    func summaries(for tripIDs: [String]) throws -> [String: TripSummary] {
        var result: [String: TripSummary] = [:]
        for tripID in Set(tripIDs) {
            if let summary = try summary(for: tripID) {
                result[tripID] = summary
            }
        }
        return result
    }

    func summary(for tripID: String) throws -> TripSummary? {
        defer { summaryQuery.reset() }
        summaryQuery.bind(tripID, at: 1)
        guard try summaryQuery.step() else { return nil }
        return TripSummary(
            tripID: summaryQuery.string(0),
            routeID: summaryQuery.string(1),
            lineNumber: summaryQuery.string(2),
            headsign: summaryQuery.string(3),
            directionID: summaryQuery.optionalInt(4),
            shapeID: summaryQuery.optionalString(5)
        )
    }

    func detail(for tripID: String) throws -> TripDetail? {
        guard let summary = try summary(for: tripID) else { return nil }

        tripKeyQuery.bind(tripID, at: 1)
        let tripKey = try tripKeyQuery.step() ? tripKeyQuery.int(0) : nil
        tripKeyQuery.reset()
        guard let tripKey else { return nil }

        var rows: [(sequence: Int, stopID: String, name: String, latitude: Double, longitude: Double, arrival: Int?, departure: Int?)] = []
        stopsQuery.bind(tripKey, at: 1)
        while try stopsQuery.step() {
            rows.append((
                stopsQuery.int(0),
                stopsQuery.string(1),
                stopsQuery.string(2),
                stopsQuery.double(3),
                stopsQuery.double(4),
                stopsQuery.optionalInt(5),
                stopsQuery.optionalInt(6)
            ))
        }
        stopsQuery.reset()

        let times = Self.fillMissingTimes(rows.map { $0.departure ?? $0.arrival })
        let stops = rows.enumerated().map { index, row in
            TripStop(
                sequence: row.sequence,
                stopID: row.stopID,
                name: row.name,
                latitude: row.latitude,
                longitude: row.longitude,
                arrival: row.arrival ?? times[index],
                departure: row.departure ?? times[index]
            )
        }

        var shape: [ShapePoint] = []
        if let shapeID = summary.shapeID {
            shapeQuery.bind(shapeID, at: 1)
            if try shapeQuery.step() {
                shape = Self.decodeShape(shapeQuery.data(0))
            }
            shapeQuery.reset()
        }

        return TripDetail(summary: summary, stops: stops, shape: shape)
    }

    /// GTFS lets stops between timepoints leave their times empty; spread them evenly between the known ones.
    static func fillMissingTimes(_ times: [Int?]) -> [Int] {
        var result = times.map { $0 ?? 0 }
        let known = times.indices.filter { times[$0] != nil }
        guard let first = known.first, let last = known.last else { return result }
        for index in 0..<first { result[index] = result[first] }
        for index in (last + 1)..<max(times.count, last + 1) { result[index] = result[last] }
        for (start, end) in zip(known, known.dropFirst()) where end - start > 1 {
            let span = result[end] - result[start]
            for index in (start + 1)..<end {
                result[index] = result[start] + span * (index - start) / (end - start)
            }
        }
        return result
    }

    static func decodeShape(_ data: Data) -> [ShapePoint] {
        data.withUnsafeBytes { bytes in
            let count = bytes.count / 8
            return (0..<count).map { index in
                let latitude = Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 8, as: Int32.self))
                let longitude = Int32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 8 + 4, as: Int32.self))
                return ShapePoint(latitude: Double(latitude) / 1_000_000, longitude: Double(longitude) / 1_000_000)
            }
        }
    }
}
