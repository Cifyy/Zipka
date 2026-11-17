//
//  GTFSImporter.swift
//  Zipka
//

import Foundation

/// Turns a GTFS zip into the compact SQLite database that `GTFSDatabase` reads.
///
/// Only the parts the app uses are kept: lines, trip headsigns, stops, the stop
/// sequence of every trip and its shape. Calendars are skipped because the realtime
/// feed already says which trip each vehicle is running.
///
/// Runs synchronously and takes a few seconds for a large feed, so call it off the main actor.
nonisolated struct GTFSImporter {
    /// Bump when the schema or the way data is processed changes, so cached databases get rebuilt.
    static let schemaVersion = 1

    let archiveURL: URL
    let databaseURL: URL

    func run() throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: databaseURL)

        let archive = try ZipArchive(url: archiveURL)
        let database = try SQLiteDatabase(url: databaseURL, readOnly: false)
        try database.execute("""
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            PRAGMA cache_size = -65536;
            PRAGMA temp_store = MEMORY;
            """)
        try database.execute(Self.schema)
        try database.execute("BEGIN")

        let feedVersion = try importFeedInfo(archive)
        try importRoutes(archive, into: database)
        let stopKeys = try importStops(archive, into: database)
        let tripKeys = try importTrips(archive, into: database)
        try importStopTimes(archive, into: database, tripKeys: tripKeys, stopKeys: stopKeys)
        if archive.contains("shapes.txt") {
            try importShapes(archive, into: database)
        }

        // Trips without a headsign show where they end instead.
        try database.execute("""
            UPDATE trips SET headsign = COALESCE((
                SELECT s.name FROM stop_times st JOIN stops s ON s.stop_key = st.stop_key
                WHERE st.trip_key = trips.trip_key ORDER BY st.seq DESC LIMIT 1
            ), '') WHERE headsign = '';
            """)

        let meta = try database.prepare("INSERT INTO meta (key, value) VALUES (?, ?)")
        for (key, value) in [
            ("schema_version", String(Self.schemaVersion)),
            ("feed_version", feedVersion ?? ""),
            ("imported_at", ISO8601DateFormatter().string(from: .now)),
        ] {
            meta.bind(key, at: 1)
            meta.bind(value, at: 2)
            try meta.run()
        }

        try database.execute("COMMIT")
    }

    static let schema = """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE routes (route_id TEXT PRIMARY KEY, short_name TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE stops (
            stop_key INTEGER PRIMARY KEY,
            stop_id TEXT NOT NULL,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL
        );
        CREATE TABLE trips (
            trip_key INTEGER PRIMARY KEY,
            trip_id TEXT NOT NULL UNIQUE,
            route_id TEXT NOT NULL,
            headsign TEXT NOT NULL,
            direction_id INTEGER,
            shape_id TEXT
        );
        CREATE TABLE stop_times (
            trip_key INTEGER NOT NULL,
            seq INTEGER NOT NULL,
            stop_key INTEGER NOT NULL,
            arrival INTEGER,
            departure INTEGER,
            PRIMARY KEY (trip_key, seq)
        ) WITHOUT ROWID;
        CREATE TABLE shapes (shape_id TEXT PRIMARY KEY, points BLOB NOT NULL) WITHOUT ROWID;
        """

    private func importFeedInfo(_ archive: ZipArchive) throws -> String? {
        guard archive.contains("feed_info.txt") else { return nil }
        var version: String?
        try archive.readCSV("feed_info.txt") { header in
            let column = header.optional("feed_version")
            return { record in
                if version == nil { version = record.nonEmptyString(column) }
            }
        }
        return version
    }

    private func importRoutes(_ archive: ZipArchive, into database: SQLiteDatabase) throws {
        let insert = try database.prepare("INSERT OR REPLACE INTO routes (route_id, short_name) VALUES (?, ?)")
        try archive.readCSV("routes.txt") { header in
            let id = try header.required("route_id", in: "routes.txt")
            let shortName = header.optional("route_short_name")
            let longName = header.optional("route_long_name")
            return { record in
                let routeID = record.string(id)
                insert.bind(routeID, at: 1)
                insert.bind(record.nonEmptyString(shortName) ?? record.nonEmptyString(longName) ?? routeID, at: 2)
                try insert.run()
            }
        }
    }

    private func importStops(_ archive: ZipArchive, into database: SQLiteDatabase) throws -> [String: Int] {
        let insert = try database.prepare("INSERT INTO stops (stop_key, stop_id, name, lat, lon) VALUES (?, ?, ?, ?, ?)")
        var keys: [String: Int] = [:]
        try archive.readCSV("stops.txt") { header in
            let id = try header.required("stop_id", in: "stops.txt")
            let name = header.optional("stop_name")
            let latitude = header.optional("stop_lat")
            let longitude = header.optional("stop_lon")
            return { record in
                let stopID = record.string(id)
                guard keys[stopID] == nil else { return }
                let key = keys.count + 1
                keys[stopID] = key
                insert.bind(key, at: 1)
                insert.bind(stopID, at: 2)
                insert.bind(record.string(name), at: 3)
                insert.bind(Double(record.microdegrees(latitude) ?? 0) / 1_000_000, at: 4)
                insert.bind(Double(record.microdegrees(longitude) ?? 0) / 1_000_000, at: 5)
                try insert.run()
            }
        }
        return keys
    }

    private func importTrips(_ archive: ZipArchive, into database: SQLiteDatabase) throws -> [String: Int] {
        let insert = try database.prepare("""
            INSERT INTO trips (trip_key, trip_id, route_id, headsign, direction_id, shape_id) VALUES (?, ?, ?, ?, ?, ?)
            """)
        var keys: [String: Int] = [:]
        try archive.readCSV("trips.txt") { header in
            let id = try header.required("trip_id", in: "trips.txt")
            let route = try header.required("route_id", in: "trips.txt")
            let headsign = header.optional("trip_headsign")
            let direction = header.optional("direction_id")
            let shape = header.optional("shape_id")
            return { record in
                let tripID = record.string(id)
                guard keys[tripID] == nil else { return }
                let key = keys.count + 1
                keys[tripID] = key
                insert.bind(key, at: 1)
                insert.bind(tripID, at: 2)
                insert.bind(record.string(route), at: 3)
                insert.bind(record.string(headsign), at: 4)
                insert.bind(record.int(direction), at: 5)
                insert.bind(record.nonEmptyString(shape), at: 6)
                try insert.run()
            }
        }
        return keys
    }

    private func importStopTimes(
        _ archive: ZipArchive,
        into database: SQLiteDatabase,
        tripKeys: [String: Int],
        stopKeys: [String: Int]
    ) throws {
        let insert = try database.prepare("""
            INSERT OR REPLACE INTO stop_times (trip_key, seq, stop_key, arrival, departure) VALUES (?, ?, ?, ?, ?)
            """)
        try archive.readCSV("stop_times.txt") { header in
            let trip = try header.required("trip_id", in: "stop_times.txt")
            let stop = try header.required("stop_id", in: "stop_times.txt")
            let sequence = try header.required("stop_sequence", in: "stop_times.txt")
            let arrival = header.optional("arrival_time")
            let departure = header.optional("departure_time")
            // Rows of one trip are usually together, so remember the last lookup.
            var lastTripID = ""
            var lastTripKey: Int?
            return { record in
                let tripID = record.string(trip)
                if tripID != lastTripID {
                    lastTripID = tripID
                    lastTripKey = tripKeys[tripID]
                }
                guard let tripKey = lastTripKey,
                      let stopKey = stopKeys[record.string(stop)],
                      let seq = record.int(sequence) else { return }
                insert.bind(tripKey, at: 1)
                insert.bind(seq, at: 2)
                insert.bind(stopKey, at: 3)
                insert.bind(record.gtfsTime(arrival), at: 4)
                insert.bind(record.gtfsTime(departure), at: 5)
                try insert.run()
            }
        }
    }

    /// Stores every shape as one blob of little-endian `Int32` pairs (latitude, longitude in
    /// millionths of a degree), already in `shape_pt_sequence` order.
    private func importShapes(_ archive: ZipArchive, into database: SQLiteDatabase) throws {
        // Flat [sequence, latitude, longitude, ...] per shape.
        var shapes: [String: [Int32]] = [:]
        // Points of one shape are usually together; collect them before touching the dictionary.
        var currentID = ""
        var current: [Int32] = []
        func flush() {
            guard !current.isEmpty else { return }
            shapes[currentID, default: []].append(contentsOf: current)
            current.removeAll(keepingCapacity: true)
        }
        try archive.readCSV("shapes.txt") { header in
            let id = try header.required("shape_id", in: "shapes.txt")
            let latitude = try header.required("shape_pt_lat", in: "shapes.txt")
            let longitude = try header.required("shape_pt_lon", in: "shapes.txt")
            let sequence = try header.required("shape_pt_sequence", in: "shapes.txt")
            return { record in
                guard let lat = record.microdegrees(latitude),
                      let lon = record.microdegrees(longitude),
                      let seq = record.int(sequence) else { return }
                let shapeID = record.string(id)
                if shapeID != currentID {
                    flush()
                    currentID = shapeID
                }
                current.append(Int32(clamping: seq))
                current.append(lat)
                current.append(lon)
            }
        }
        flush()

        let insert = try database.prepare("INSERT INTO shapes (shape_id, points) VALUES (?, ?)")
        for (shapeID, flat) in shapes {
            let count = flat.count / 3
            var order = Array(0..<count)
            // Files are normally sorted already; only pay for sorting when they are not.
            if !(1..<max(count, 1)).allSatisfy({ flat[($0 - 1) * 3] <= flat[$0 * 3] }) {
                order.sort { flat[$0 * 3] < flat[$1 * 3] }
            }
            var points: [Int32] = []
            points.reserveCapacity(count * 2)
            for index in order {
                points.append(flat[index * 3 + 1].littleEndian)
                points.append(flat[index * 3 + 2].littleEndian)
            }
            insert.bind(shapeID, at: 1)
            insert.bind(points.withUnsafeBytes { Data($0) }, at: 2)
            try insert.run()
        }
    }
}
