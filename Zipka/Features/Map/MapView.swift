//
//  MapView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI
import MapKit

struct MapView: View {
    @State private var vehicleManager = VehicleManager()
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.9450),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var body: some View {
        Map(){
            ForEach(vehicleManager.vehicles){ vehicle in
                Annotation("", coordinate: vehicle.position) {
                    VehicleAnnotationView(vehicle: vehicle)
                }
            }
        }
    }
    
}

#Preview {
    MapView()
}
