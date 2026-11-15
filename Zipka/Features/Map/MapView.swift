//
//  MapView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI
import MapKit
import ClusterMap

struct MapView: View {
    @Environment(VehicleManager.self) var vehicleManager
    
    @State private var clusterManager = ClusterManager<Vehicle>(configuration: .init(maxZoomLevel: 12, shouldDistributeAnnotationsOnSameCoordinate: false))
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.9450),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.9450),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    ))
    @State private var mapSize: CGSize = .zero
    @State private var visibleVehicles: [Vehicle] = []
    @State private var clusters: [ClusterManager<Vehicle>.ClusterAnnotation] = []
    @State private var reloadGeneration = 0
    
    @State private var mapStyle: MapStyle = .standard
    @State private var selectedVehicleID: String?
    @State private var sheetDetent: PresentationDetent = .height(80)
    
    private var selectedVehicle: Vehicle? {
        guard let selectedVehicleID else { return nil }
        return vehicleManager.vehicles.first { $0.id == selectedVehicleID }
    }
    
    @Namespace var mapScope
    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all.subtracting([.pitch, .rotate]), selection: $selectedVehicleID, scope: mapScope){
                UserAnnotation()
    
                ForEach(visibleVehicles){ vehicle in
                    Annotation("", coordinate: vehicle.coordinate) {
                        VehicleAnnotationView(vehicle: vehicle, isSelected: vehicle.id == selectedVehicleID)
                    }
                    .tag(vehicle.id)
                }
            
                ForEach(clusters){ cluster in
                    Annotation("", coordinate: cluster.coordinate) {
                        ClusterAnnotationView(
                            count: cluster.memberAnnotations.count,
                            tramCount: cluster.memberAnnotations.filter { $0.type == .tram }.count
                        )
                            .onTapGesture {
                                zoom(into: cluster)
                            }
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
            .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                mapSize = newSize
                reloadClusters()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                reloadClusters()
            }
        .mapScope(mapScope)
        .sheet(isPresented: .constant(true)) {
            if let vehicle = selectedVehicle {
                VehicleDetailSheetView(vehicle: vehicle) {
                    selectedVehicleID = nil
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
        .onChange(of: vehicleManager.vehicles) {
            reloadClusters()
        }
        .onChange(of: selectedVehicleID) { _, newValue in
            if newValue != nil {
                sheetDetent = .medium
            } else {
                sheetDetent = .height(80)
            }
            reloadClusters()
        }
    }
    
    /// Reclusters the current vehicles for the visible region. The selected vehicle is kept
    /// out of clusters so it stays visible while its detail sheet is open. Results from a
    /// reload that was superseded by a newer one are discarded.
    private func reloadClusters() {
        guard mapSize.width > 0, mapSize.height > 0 else { return }
        
        reloadGeneration += 1
        let generation = reloadGeneration
        let vehicles = vehicleManager.vehicles.map { vehicle in
            var vehicle = vehicle
            vehicle.shouldCluster = vehicle.id != selectedVehicleID
            return vehicle
        }
        let size = mapSize
        let region = region
        
        Task {
            let annotations = await clusterManager.replaceAndReload(with: vehicles, mapViewSize: size, coordinateRegion: region)
            guard generation == reloadGeneration else { return }
            
            var newVehicles: [Vehicle] = []
            var newClusters: [ClusterManager<Vehicle>.ClusterAnnotation] = []
            for annotation in annotations {
                switch annotation {
                case .annotation(let vehicle):
                    newVehicles.append(vehicle)
                case .cluster(let cluster):
                    newClusters.append(cluster)
                }
            }
            withAnimation(.easeInOut) {
                visibleVehicles = newVehicles
                clusters = newClusters
            }
        }
    }
    
    private func zoom(into cluster: ClusterManager<Vehicle>.ClusterAnnotation) {
        let latitudes = cluster.memberAnnotations.map(\.coordinate.latitude)
        let longitudes = cluster.memberAnnotations.map(\.coordinate.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
        
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.003),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.003)
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

#Preview {
    MapView()
        .environment(VehicleManager(locationManager: LocationManager()))
}
