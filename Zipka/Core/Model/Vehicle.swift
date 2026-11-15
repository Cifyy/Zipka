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
    var label: String
    var shouldCluster: Bool = true
    var type: VehicleType = .bus
//    var type: VehicleType
//    var routeId
//    var lastUpdate: Date
    
    static func == (lhs: Vehicle, rhs: Vehicle) -> Bool {
        return lhs.id == rhs.id &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.bearing == rhs.bearing
    }
    func hash(into hasher: inout Hasher){
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(bearing)
    }
}
 
