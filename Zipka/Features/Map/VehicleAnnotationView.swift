//
//  VehicleAnnotationView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI

struct VehicleAnnotationView: View {
    let vehicle: Vehicle
    
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 4, height: 4)
    }
}

//#Preview {
//    VehicleAnnotationView()
//}
