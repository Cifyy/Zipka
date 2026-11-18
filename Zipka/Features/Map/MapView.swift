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
    @Environment(TripDetailModel.self) var tripModel
    
    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.9450),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @State private var clusterModel = VehicleClusterModel(region: initialRegion)
    @State private var cameraPosition: MapCameraPosition = .region(initialRegion)
    
    @State private var mapStyle: MapStyle = .standard
    @State private var selectedVehicleID: String?
    @State private var sheetDetent: PresentationDetent = .height(80)

    private static let vehicleSheetDetent = PresentationDetent.height(300)
    
    private var selectedVehicle: Vehicle? {
        guard let selectedVehicleID else { return nil }
        return vehicleManager.vehicles.first { $0.id == selectedVehicleID }
    }
    
    /// Identifies the trip to track; changes when another vehicle is picked, the vehicle starts
    /// a new trip, or a newer timetable arrives.
    private struct TrackedTrip: Hashable {
        let feed: TransitFeed
        let tripID: String
        let timetableRevision: Int
    }

    private var trackedTrip: TrackedTrip? {
        guard let vehicle = selectedVehicle, let tripID = vehicle.tripID else { return nil }
        return TrackedTrip(feed: vehicle.feed, tripID: tripID, timetableRevision: vehicleManager.staticDataRevision)
    }

    /// Sequence numbers of the selected trip's stops the vehicle has already left.
    private var passedStopSequences: Set<Int> {
        guard let vehicle = selectedVehicle else { return [] }
        let timed = tripModel.timedStops(now: .now)
        guard let next = TripTimetable.upcomingStops(timed, currentStopSequence: vehicle.currentStopSequence, now: .now).first else {
            return Set(timed.map(\.stop.sequence))
        }
        return Set(timed.map(\.stop.sequence).filter { $0 < next.stop.sequence })
    }

    @Namespace var mapScope
    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all.subtracting([.pitch, .rotate]), selection: $selectedVehicleID, scope: mapScope){
                UserAnnotation()

                if let vehicle = selectedVehicle, let detail = tripModel.detail, detail.summary.tripID == vehicle.tripID {
                    routeContent(detail, color: MapMarkerStyle.color(for: vehicle.type))
                }
    
                ForEach(clusterModel.vehicles){ vehicle in
                    Annotation("", coordinate: vehicle.coordinate) {
                        VehicleAnnotationView(vehicle: vehicle, isSelected: vehicle.id == selectedVehicleID)
                    }
                    .tag(vehicle.id)
                }
            
                ForEach(clusterModel.clusters){ cluster in
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
                clusterModel.setMapSize(newSize)
            }
            // Markers refresh about once a second while panning, and right away when the gesture ends.
            .onMapCameraChange(frequency: .continuous) { context in
                clusterModel.cameraMoved(to: context.region)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                clusterModel.cameraSettled(at: context.region)
            }
        .mapScope(mapScope)
        .sheet(isPresented: .constant(true)) {
            if let vehicle = selectedVehicle {
                VehicleDetailSheetView(vehicle: vehicle) {
                    selectedVehicleID = nil
                }
                .presentationDetents([.fraction(0.15), Self.vehicleSheetDetent, .large], selection: $sheetDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.vehicleSheetDetent))
            } else {
                SearchSheetView()
                    .presentationDetents([.height(80), .medium, .large], selection: $sheetDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled()
            }
        }
        .onChange(of: vehicleManager.vehicles, initial: true) {
            reloadClusters()
        }
        .task(id: trackedTrip) {
            guard let trackedTrip else {
                tripModel.reset()
                return
            }
            await tripModel.track(feed: trackedTrip.feed, tripID: trackedTrip.tripID)
        }
        .onChange(of: selectedVehicleID) { _, newValue in
            if newValue != nil {
                sheetDetent = Self.vehicleSheetDetent
            } else {
                sheetDetent = .height(80)
            }
            reloadClusters()
        }
    }
    
    /// The selected trip's path with a white casing, and a marker for each of its stops.
    @MapContentBuilder
    private func routeContent(_ detail: TripDetail, color: Color) -> some MapContent {
        let passed = passedStopSequences
        MapPolyline(coordinates: tripModel.routeCoordinates)
            .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        MapPolyline(coordinates: tripModel.routeCoordinates)
            .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

        ForEach(detail.stops) { stop in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                RouteStopAnnotationView(color: color, isPassed: passed.contains(stop.sequence))
            }
            .annotationTitles(.hidden)
        }
    }

    /// Hands the current vehicles to the clusterer. The selected vehicle is kept out of
    /// clusters so it stays visible while its detail sheet is open.
    private func reloadClusters() {
        clusterModel.setVehicles(vehicleManager.vehicles.map { vehicle in
            var vehicle = vehicle
            vehicle.shouldCluster = vehicle.id != selectedVehicleID
            return vehicle
        })
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
    let staticData = LocalGTFSDataSource()
    MapView()
        .environment(VehicleManager(locationManager: LocationManager(), staticData: staticData))
        .environment(TripDetailModel(staticData: staticData))
}
