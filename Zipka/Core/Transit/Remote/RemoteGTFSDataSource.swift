//
//  RemoteGTFSDataSource.swift
//  Zipka
//

import Foundation

/// Gets static GTFS data from a backend that does the processing, instead of the device.
///
/// The backend runs the same pipeline as `LocalGTFSDataSource` (it can reuse
/// `GTFSImporter` and `GTFSDatabase`) and returns the app's models as JSON:
///
/// - `GET  {baseURL}/feeds/{feed}` → `{ "version": "…" }`, where `feed` is `A` (bus) or `T` (tram)
/// - `POST {baseURL}/feeds/{feed}/trips/lookup` with `{ "tripIDs": ["…"] }` → `[TripSummary]`
/// - `GET  {baseURL}/feeds/{feed}/trips/{tripID}` → `TripDetail`, or 404 when the trip is unknown
///
/// A 503 from any trip endpoint means the backend has no data yet.
actor RemoteGTFSDataSource: TransitStaticDataSource {
    private let baseURL: URL
    private let session: URLSession
    private var versions: [TransitFeed: String] = [:]

    private struct FeedInfo: Decodable {
        let version: String
    }

    private struct LookupRequest: Encodable {
        let tripIDs: [String]
    }

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The backend keeps itself up to date; this only reports when its version changed.
    func refresh(_ feed: TransitFeed) async throws -> Bool {
        let (data, response) = try await session.data(from: feedURL(feed))
        try Self.check(response)
        let version = try JSONDecoder().decode(FeedInfo.self, from: data).version
        defer { versions[feed] = version }
        return versions[feed] != version
    }

    func tripSummaries(in feed: TransitFeed, for tripIDs: [String]) async throws -> [String: TripSummary] {
        guard !tripIDs.isEmpty else { return [:] }
        var request = URLRequest(url: feedURL(feed).appending(path: "trips/lookup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LookupRequest(tripIDs: tripIDs))

        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        let summaries = try JSONDecoder().decode([TripSummary].self, from: data)
        return Dictionary(summaries.map { ($0.tripID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func tripDetail(in feed: TransitFeed, tripID: String) async throws -> TripDetail? {
        let url = feedURL(feed).appending(path: "trips").appending(path: tripID)
        let (data, response) = try await session.data(from: url)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try Self.check(response)
        return try JSONDecoder().decode(TripDetail.self, from: data)
    }

    private func feedURL(_ feed: TransitFeed) -> URL {
        baseURL.appending(path: "feeds").appending(path: feed.rawValue)
    }

    private static func check(_ response: URLResponse) throws {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 503 { throw TransitDataError.notReady }
        guard (200..<300).contains(statusCode) else { throw TransitDataError.badResponse(statusCode: statusCode) }
    }
}
