//
//  MapView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI
import MapKit

struct MapView: View {
    @Environment(VehicleManager.self) var vehicleManager
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.9450),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var mapStyle: MapStyle = .standard
    
    @Namespace var mapScope
    var body: some View {
        Map(interactionModes: .all.subtracting([.pitch, .rotate]), scope: mapScope){
                UserAnnotation()
    
                ForEach(vehicleManager.vehicles){ vehicle in
                    Annotation("", coordinate: vehicle.position) {
                        VehicleAnnotationView(vehicle: vehicle)
                    }
                }
            }
            .mapControls {
                MapCompass().mapControlVisibility(.hidden)
            }
            .mapStyle(mapStyle)
            .overlay(alignment: .topTrailing) {
                MapControlsView(scope: mapScope, mapStyle: $mapStyle)
                    .padding(.top, 60)
                    .padding(.trailing, 16)
            }
        .mapScope(mapScope)
        .sheet(isPresented: .constant(true)) {
            SearchSheetView()
                .presentationDetents([.height(80), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
    }
}

#Preview {
    MapView()
        .environment(VehicleManager(locationManager: LocationManager()))
}
