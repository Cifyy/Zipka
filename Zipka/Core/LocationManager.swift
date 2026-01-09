//
//  LocationManager.swift
//  Zipka
//
//  Created by Jakub Majka on 6/12/25.
//

import CoreLocation
import Observation

enum locationError: Error{
    case locationServicesNotEnabled, noLocationPermission, unknownLocationError
}

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    var location: CLLocationCoordinate2D?
    var locationPermission = true
    
    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }
    
    func checkAuthorization() async throws -> CLLocationCoordinate2D{
        
        if !CLLocationManager.locationServicesEnabled(){
            throw locationError.locationServicesNotEnabled
        }
        
        switch self.manager.authorizationStatus{
            
            case .denied, .notDetermined, .restricted:
                throw locationError.noLocationPermission
            
            case .authorizedAlways, .authorizedWhenInUse:
                guard let location = manager.location?.coordinate else {
                    throw locationError.unknownLocationError
                }
                return location

            @unknown default:
                break
                
        }
        throw locationError.unknownLocationError
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager){
        if manager.authorizationStatus == .authorizedWhenInUse{ locationPermission = true }
        else{ locationPermission = false }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first?.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print(String(describing: error))
    }
}
