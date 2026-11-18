//
//  Vehicle.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import Foundation
import CoreLocation
import ClusterMap

nonisolated enum VehicleType{
    case bus, tram
}

nonisolated struct Vehicle: CoordinateIdentifiable, Identifiable, Equatable, Hashable {
    let id: String
    var coordinate: CLLocationCoordinate2D
    var bearing:Int?
    /// Fleet number painted on the vehicle (e.g. "103"), not the line it runs.
    var label: String
    var shouldCluster: Bool = true
    var feed: TransitFeed = .bus
    var type: VehicleType { feed.vehicleType }

    /// Realtime trip the vehicle is running; links it to the static timetable.
    var tripID: String?
    var routeID: String?
    /// `stop_sequence` of the stop the vehicle is at or heading to.
    var currentStopSequence: Int?
    var isStoppedAtCurrentStop: Bool = false

    /// Line number from the static timetable.
    var lineNumber: String?
    /// Where the vehicle is heading, from the static timetable.
    var headsign: String?

    /// What to show on the marker: the line number once it is known.
    var displayLine: String {
        lineNumber ?? routeID ?? "–"
    }

    static func == (lhs: Vehicle, rhs: Vehicle) -> Bool {
        return lhs.id == rhs.id &&
               lhs.feed == rhs.feed &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.bearing == rhs.bearing &&
               lhs.tripID == rhs.tripID &&
               lhs.currentStopSequence == rhs.currentStopSequence &&
               lhs.isStoppedAtCurrentStop == rhs.isStoppedAtCurrentStop &&
               lhs.lineNumber == rhs.lineNumber &&
               lhs.headsign == rhs.headsign
    }
    func hash(into hasher: inout Hasher){
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(bearing)
        hasher.combine(tripID)
        hasher.combine(lineNumber)
    }
}
