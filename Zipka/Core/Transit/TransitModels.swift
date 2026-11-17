//
//  TransitModels.swift
//  Zipka
//

import Foundation

/// One of the agency's GTFS feeds. Kraków publishes buses and trams separately,
/// each with its own static timetable and its own realtime files.
nonisolated enum TransitFeed: String, CaseIterable, Codable, Sendable {
    case bus = "A"
    case tram = "T"

    static let baseURL = URL(string: "https://gtfs.ztp.krakow.pl/")!

    var staticDataURL: URL { Self.baseURL.appending(path: "GTFS_KRK_\(rawValue).zip") }
    var vehiclePositionsURL: URL { Self.baseURL.appending(path: "VehiclePositions_\(rawValue).pb") }
    var tripUpdatesURL: URL { Self.baseURL.appending(path: "TripUpdates_\(rawValue).pb") }

    var vehicleType: VehicleType {
        switch self {
        case .bus: .bus
        case .tram: .tram
        }
    }
}

/// What a vehicle on the map needs to know about its trip: the line it runs and where it is heading.
nonisolated struct TripSummary: Codable, Sendable, Hashable {
    let tripID: String
    let routeID: String
    /// `route_short_name`, the number riders know the line by.
    let lineNumber: String
    let headsign: String
    let directionID: Int?
    let shapeID: String?
}

/// A stop on a trip with its scheduled times.
nonisolated struct TripStop: Codable, Sendable, Hashable, Identifiable {
    var id: Int { sequence }

    let sequence: Int
    let stopID: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Seconds after the start of the service day ("noon minus 12 h"). Can exceed 24 h for trips past midnight.
    let arrival: Int
    let departure: Int
}

nonisolated struct ShapePoint: Codable, Sendable, Hashable {
    let latitude: Double
    let longitude: Double
}

/// Everything needed to draw a trip on the map and list its stops.
nonisolated struct TripDetail: Codable, Sendable, Hashable {
    let summary: TripSummary
    let stops: [TripStop]
    /// The path from `shapes.txt`. Empty when the feed has no shape for this trip.
    let shape: [ShapePoint]
}

nonisolated enum TransitDataError: Error {
    /// The static timetable has not been downloaded and processed yet.
    case notReady
    case badResponse(statusCode: Int)
}
