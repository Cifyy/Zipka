//
//  MotionManager.swift
//  Zipka
//
//  Created by Jakub Majka on 6/12/25.
//

import CoreMotion
import SwiftUI

@Observable
class MotionManager {
    private let manager = CMMotionManager()
    var pitch: Double = 0.0
    var roll: Double = 0.0
    
    init() {
        startMotionUpdates()
    }
    
    func startMotionUpdates() {
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
                guard let data = data else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    self?.pitch = data.attitude.pitch
                    self?.roll = data.attitude.roll
                }
            }
        }
    }
    
    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
