//
//  VehicleManager.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import Foundation
import CoreLocation
import SwiftUI
import Observation 
import ZIpkaProtobuf

@Observable
class VehicleManager {
    private let apiService = ApiService()
    
    var vehicles: [Vehicle] = []
    var busList: [Vehicle] = []
    var tramList: [Vehicle] = []
    
    private var timer: Timer?
    private let locationManager: LocationManager
    
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        startUpdating()
    }
    
    deinit {
        stopUpdating()
    }
    
    func startUpdating() {
        fetchVehicles()
        
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.fetchVehicles()
        }
    }
    
    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }
    
    private func fetchVehicles() {
        let baseURL = URL(string: "https://gtfs.ztp.krakow.pl")!
        let requestURL = URL(string: "VehiclePositions.pb", relativeTo: baseURL)!
        
        Task {
            do {
                let feedMessage = try await apiService.fetchRealtimeDataAsync(request: requestURL)
                
                let newVehicles = feedMessage.entity.compactMap { entity -> Vehicle? in
                    guard entity.hasVehicle else { return nil }
                    let vehicleData = entity.vehicle
                    
                    guard vehicleData.hasPosition else { return nil }
                    
                    let pos = vehicleData.position
                    let lat = Double(pos.latitude)
                    let lon = Double(pos.longitude)
                    
                    let id = vehicleData.hasVehicle ? vehicleData.vehicle.id : entity.id
                
                    let label = vehicleData.hasVehicle ? vehicleData.vehicle.label : "?"
                    
                    let bearing: Int? = pos.hasBearing ? Int(pos.bearing) : nil
                    
                    return Vehicle(
                        id: id,
                        position: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        bearing: bearing,
                        label: label
                    )
                }
                
                await MainActor.run {
                    withAnimation(.easeInOut){
                        self.updateVehicles(newVehicles)
                    }
                }
            } catch {
                print("Error fetching vehicles: \(error)")
            }
        }
    }
    
    private func updateVehicles(_ newVehicles: [Vehicle]) {
        self.vehicles = newVehicles
    }
}
