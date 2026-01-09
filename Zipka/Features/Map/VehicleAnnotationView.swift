//
//  VehicleAnnotationView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI
import CoreLocation

struct VehicleAnnotationView: View {
    let vehicle: Vehicle
    let cornerRadius: CGFloat = 4

    var body: some View {
        ZStack {
            
            if let bearing = vehicle.bearing {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 24))
                    .offset(y: -7)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(Double(bearing)))
                    .offset(bearingToOffSet(degrees: Double(bearing), width: 21, height: 10))
                    
            }
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(red: 0.0, green: 0.4, blue: 0.8))
                .frame(width: 36, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white, lineWidth: 2.5)
                )
            
            Text(vehicle.label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
        }

    }
    private func exponentialPercent(value: CGFloat, maxVal: CGFloat) -> CGFloat {
        let normalized = value /  maxVal
        
        let numerator = pow(10, normalized) - 1
        let denominator: CGFloat = 9
        return CGFloat(numerator / denominator)
    }
    
    private func bearingToOffSet(degrees: CGFloat, width: CGFloat, height: CGFloat) -> CGSize {
        let inputRadians = (degrees-90) * .pi / 180.0
        let squareX = cos(inputRadians)
        let squareY = sin(inputRadians)
        
        let rectX = squareX * width
        let rectY = squareY * height
        
        let radians = atan2(rectY, rectX)
        
        let dx = cos(radians)
        let dy = sin(radians)
        
        let xBound = width / 2.0
        let yBound = height / 2.0
        
        let tx = abs(dx) > 0.0001 ? xBound / abs(dx) : CGFloat.greatestFiniteMagnitude
        let ty = abs(dy) > 0.0001 ? yBound / abs(dy) : CGFloat.greatestFiniteMagnitude
        
        let t = min(tx, ty)
        
        let degreesToCorner = 45 - abs(45 - degrees.truncatingRemainder(dividingBy: 90))
        let inOffsetPercent = 1 - (exponentialPercent(value: degreesToCorner, maxVal: 45) * 0.2)
        let inXOffsetPercent = inOffsetPercent * height / width
        
        return CGSize(width: t * dx * inOffsetPercent, height: t * dy * inXOffsetPercent)
    }
//
//    private func bearingToOffset(_ degrees: Double) -> CGSize{
//        let radians = degrees * Double.pi / 180.0
//        
//        let a = tan(radians) * 27
//        return CGSize(width: a, height: -19)
////        return CGSize(width: 27, height: -19)
//    }
//    var body: some View {
//        ZStack {
//            if let bearing = vehicle.bearing {
//                VStack {
//                    Image(systemName: "arrowtriangle.up.fill")
//                        .resizable()
//                        .frame(width: 10, height: 10)
//                        .foregroundColor(.blue)
//                    Spacer()
//                }
//                .frame(height: 30)
//                .rotationEffect(.degrees(Double(bearing)))
//            }
//            
//            Circle()
//                .fill(Color.blue)
//                .frame(width: 20, height: 20)
//                .overlay(
//                    Circle()
//                        .stroke(Color.white, lineWidth: 2)
//                )
//                .shadow(radius: 2)
//            
//            Text(vehicle.label)
//                .font(.system(size: 12, weight: .bold))
//                .foregroundColor(.white)
//                .lineLimit(1)
//        }
//    }
}

#Preview {
    VehicleAnnotationView(vehicle: Vehicle(id: "10", position: CLLocationCoordinate2D(latitude: 0, longitude: 0), bearing: 0 , label: "194"))
}
