//
//  LocalGTFSDataSource.swift
//  Zipka
//

import Foundation

/// Downloads the agency's static GTFS zips, processes them on the device and serves
/// queries from the resulting SQLite databases in the Caches directory.
///
/// A feed is downloaded again only when the server reports a new version
/// (`ETag` / `Last-Modified`), and the server is asked at most once per `checkInterval`.
/// While a new version is being processed, queries keep using the previous database.
actor LocalGTFSDataSource: TransitStaticDataSource {
    private let directory: URL
    private let checkInterval: TimeInterval
    private let session: URLSession

    private var databases: [TransitFeed: GTFSDatabase] = [:]
    private var refreshes: [TransitFeed: Task<Bool, Error>] = [:]

    /// What we know about the cached copy of a feed.
    private struct CacheState: Codable {
        var schemaVersion: Int
        var etag: String?
        var lastModified: String?
        var lastChecked: Date
    }

    init(
        directory: URL = URL.cachesDirectory.appending(path: "GTFS", directoryHint: .isDirectory),
        checkInterval: TimeInterval = 60 * 60,
        session: URLSession = .shared
    ) {
        self.directory = directory
        self.checkInterval = checkInterval
        self.session = session
    }

    // MARK: - TransitStaticDataSource

    func refresh(_ feed: TransitFeed) async throws -> Bool {
        if let running = refreshes[feed] {
            return try await running.value
        }
        let task = Task { try await performRefresh(feed) }
        refreshes[feed] = task
        defer { refreshes[feed] = nil }
        return try await task.value
    }

    func tripSummaries(in feed: TransitFeed, for tripIDs: [String]) throws -> [String: TripSummary] {
        try database(for: feed).summaries(for: tripIDs)
    }

    func tripDetail(in feed: TransitFeed, tripID: String) throws -> TripDetail? {
        try database(for: feed).detail(for: tripID)
    }

    // MARK: - Refreshing

    private func performRefresh(_ feed: TransitFeed) async throws -> Bool {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = databaseURL(for: feed)
        var state = loadState(for: feed)
        let hasUsableDatabase = state?.schemaVersion == GTFSImporter.schemaVersion
            && FileManager.default.fileExists(atPath: databaseURL.path)

        if hasUsableDatabase, let state, Date.now.timeIntervalSince(state.lastChecked) < checkInterval {
            return false
        }

        var request = URLRequest(url: feed.staticDataURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if hasUsableDatabase {
            if let etag = state?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lastModified = state?.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        }

        let (downloadURL, response) = try await session.download(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 304, var unchanged = state {
            try? FileManager.default.removeItem(at: downloadURL)
            unchanged.lastChecked = .now
            saveState(unchanged, for: feed)
            return false
        }
        guard (200..<300).contains(statusCode) else {
            try? FileManager.default.removeItem(at: downloadURL)
            throw TransitDataError.badResponse(statusCode: statusCode)
        }

        // The download lands in a temporary file the system may delete; keep our own copy while processing.
        let archiveURL = directory.appending(path: "\(feed.rawValue).zip")
        let buildURL = directory.appending(path: "\(feed.rawValue).building.sqlite")
        try? FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.moveItem(at: downloadURL, to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let importer = GTFSImporter(archiveURL: archiveURL, databaseURL: buildURL)
        do {
            try await Task.detached(priority: .utility) { try importer.run() }.value
        } catch {
            try? FileManager.default.removeItem(at: buildURL)
            throw error
        }

        // Swap the new database in. The open connection to the old one is closed first.
        databases[feed] = nil
        try? FileManager.default.removeItem(at: databaseURL)
        try FileManager.default.moveItem(at: buildURL, to: databaseURL)

        let headers = response as? HTTPURLResponse
        state = CacheState(
            schemaVersion: GTFSImporter.schemaVersion,
            etag: headers?.value(forHTTPHeaderField: "ETag"),
            lastModified: headers?.value(forHTTPHeaderField: "Last-Modified"),
            lastChecked: .now
        )
        saveState(state!, for: feed)
        return true
    }

    // MARK: - Storage

    private func database(for feed: TransitFeed) throws -> GTFSDatabase {
        if let database = databases[feed] { return database }
        let url = databaseURL(for: feed)
        guard FileManager.default.fileExists(atPath: url.path) else { throw TransitDataError.notReady }
        let database = try GTFSDatabase(url: url)
        databases[feed] = database
        return database
    }

    private func databaseURL(for feed: TransitFeed) -> URL {
        directory.appending(path: "\(feed.rawValue).sqlite")
    }

    private func stateURL(for feed: TransitFeed) -> URL {
        directory.appending(path: "\(feed.rawValue).json")
    }

    private func loadState(for feed: TransitFeed) -> CacheState? {
        guard let data = try? Data(contentsOf: stateURL(for: feed)) else { return nil }
        return try? JSONDecoder().decode(CacheState.self, from: data)
    }

    private func saveState(_ state: CacheState, for feed: TransitFeed) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL(for: feed), options: .atomic)
    }
}
