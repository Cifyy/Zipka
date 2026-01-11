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
    @State private var selectedVehicle: Vehicle?
    @State private var sheetDetent: PresentationDetent = .height(80)
    
    @Namespace var mapScope
    var body: some View {
        Map(interactionModes: .all.subtracting([.pitch, .rotate]), selection: $selectedVehicle, scope: mapScope){
                UserAnnotation()
    
                ForEach(vehicleManager.vehicles){ vehicle in
                    Annotation("", coordinate: vehicle.position) {
                        VehicleAnnotationView(vehicle: vehicle)
                    }
                    .tag(vehicle)
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
            if let vehicle = selectedVehicle {
                VehicleDetailSheetView(vehicle: vehicle) {
                    selectedVehicle = nil
                }
                .presentationDetents([.medium, .fraction(0.15)], selection: $sheetDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            } else {
                SearchSheetView()
                    .presentationDetents([.height(80), .medium, .large], selection: $sheetDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled()
            }
        }
        .onChange(of: selectedVehicle) { _, newValue in
            if newValue != nil {
                sheetDetent = .medium
            } else {
                sheetDetent = .height(80)
            }
        }
    }
}

#Preview {
    MapView()
        .environment(VehicleManager(locationManager: LocationManager()))
}
