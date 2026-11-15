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
        Task {
            async let buses = fetchFeed("VehiclePositions_A.pb", type: .bus)
            async let trams = fetchFeed("VehiclePositions_T.pb", type: .tram)
            let (newBuses, newTrams) = await (buses, trams)
            
            await MainActor.run {
                if let newBuses { self.busList = newBuses }
                if let newTrams { self.tramList = newTrams }
                withAnimation(.easeInOut){
                    self.updateVehicles(self.busList + self.tramList)
                }
            }
        }
    }

    private func fetchFeed(_ resource: String, type: VehicleType) async -> [Vehicle]? {
        let baseURL = URL(string: "https://gtfs.ztp.krakow.pl")!
        let requestURL = URL(string: resource, relativeTo: baseURL)!
        
        do {
            let feedMessage = try await apiService.fetchRealtimeDataAsync(request: requestURL)
            
            return feedMessage.entity.compactMap { entity -> Vehicle? in
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
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    bearing: bearing,
                    label: label,
                    type: type
                )
            }
        } catch {
            print("Error fetching \(resource): \(error)")
            return nil
        }
    }
    
    private func updateVehicles(_ newVehicles: [Vehicle]) {
        self.vehicles = newVehicles
    }
}
