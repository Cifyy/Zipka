//
//  ZipkaApp.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import SwiftUI
import SwiftData

@main
struct ZipkaApp: App {
    @State private var locationManager = LocationManager()
    @State private var vehicleManager: VehicleManager
    @State private var tripDetail: TripDetailModel
    
    init() {
        let locManager = LocationManager()
        // Static timetable (lines, headsigns, stops, shapes). Processed on the device and cached.
        // To let a backend do the processing instead, swap in:
        //     RemoteGTFSDataSource(baseURL: URL(string: "https://your-backend.example/v1")!)
        let staticData: any TransitStaticDataSource = LocalGTFSDataSource()
        _locationManager = State(initialValue: locManager)
        _vehicleManager = State(initialValue: VehicleManager(locationManager: locManager, staticData: staticData))
        _tripDetail = State(initialValue: TripDetailModel(staticData: staticData))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(vehicleManager)
                .environment(tripDetail)
        }
    }
}
