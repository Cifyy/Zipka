//
//  Vehicle.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import Foundation
import CoreLocation

struct Vehicle: Identifiable, Equatable, Hashable {
    let id: String
    var position: CLLocationCoordinate2D
    var bearing: Int?
    
    static func == (lhs: Vehicle, rhs: Vehicle) -> Bool {
        return lhs.id == rhs.id &&
               lhs.position.latitude == rhs.position.latitude &&
               lhs.position.longitude == rhs.position.longitude &&
               lhs.bearing == rhs.bearing
    }
    func hash(into hasher: inout Hasher){
        hasher.combine(id)
        hasher.combine(position.latitude)
        hasher.combine(position.longitude)
        hasher.combine(bearing)
    }
}
