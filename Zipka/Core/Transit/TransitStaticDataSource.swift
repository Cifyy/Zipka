//
//  TransitStaticDataSource.swift
//  Zipka
//

import Foundation

/// Where the app gets static GTFS data (lines, headsigns, stops, shapes) from.
///
/// The app only talks to this protocol, so the source can be swapped in one place
/// (`ZipkaApp`):
/// - `LocalGTFSDataSource` downloads the agency's zip, processes it on the device and
///   caches the result in SQLite.
/// - `RemoteGTFSDataSource` asks a backend that has already done that processing and
///   returns the same models as JSON.
nonisolated protocol TransitStaticDataSource: Sendable {
    /// Makes sure the newest data for `feed` is available.
    ///
    /// Cheap to call often: implementations throttle themselves. Returns `true` when the
    /// data changed, so callers can drop anything they cached from the previous version.
    func refresh(_ feed: TransitFeed) async throws -> Bool

    /// Line number and headsign for each trip ID that the data knows. Unknown IDs are left out.
    /// Throws `TransitDataError.notReady` while there is no data yet.
    func tripSummaries(in feed: TransitFeed, for tripIDs: [String]) async throws -> [String: TripSummary]

    /// Stops, scheduled times and shape of one trip, or `nil` if the trip is unknown.
    /// Throws `TransitDataError.notReady` while there is no data yet.
    func tripDetail(in feed: TransitFeed, tripID: String) async throws -> TripDetail?
}
