//
//  VehicleDetailSheetView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI
internal import _LocationEssentials

struct VehicleDetailSheetView: View {
    let vehicle: Vehicle
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Line \(vehicle.label)")
                    .font(.largeTitle)
                    .bold()
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray.opacity(0.8))
                }
            }
            
            Divider()
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    VehicleDetailSheetView(vehicle: Vehicle(id: "123", position: .init(latitude: 50.0, longitude: 19.0), bearing: 90, label: "52"), onClose: {})
}
