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
    
    init() {
        let locManager = LocationManager()
        _locationManager = State(initialValue: locManager)
        _vehicleManager = State(initialValue: VehicleManager(locationManager: locManager))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(vehicleManager)
        }
    }
}
