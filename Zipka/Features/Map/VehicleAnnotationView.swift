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
            
            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .fill(Color.black)
                .frame(width: 40, height: 24)
            
            if let bearing = vehicle.bearing {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .background(
                        Image(systemName: "arrowtriangle.up") // Use the outline version
                            .font(.system(size: 27))
                            .foregroundColor(.black)
                    )
                    .rotationEffect(.degrees(Double(bearing)))
                    .offset(bearingToOffSet(degrees: Double(bearing)))
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
    
    private func bearingToOffSet(degrees: Double) -> CGSize{
        let xFlatOff:CGFloat = 20
        let yFlatfOff:CGFloat = -12
        let xAngleOff:CGFloat = 16.5
        let yAngleOff:CGFloat = -9
        
        switch degrees{
        case 0...22.5:
            return CGSize(width: 0, height: yFlatfOff)
        case 22.5...67.5:
            return CGSize(width: xAngleOff, height: yAngleOff)
        case 67.5...112.5:
            return CGSize(width: xFlatOff, height: 0)
        case 112.5...157.5:
            return CGSize(width: xAngleOff, height: -yAngleOff)
        case 157.5...202.5:
            return CGSize(width: 0, height: -yFlatfOff)
        case 202.5...247.5:
            return CGSize(width: -xAngleOff, height: -yAngleOff)
        case 247.5...292.5:
            return CGSize(width: -xFlatOff, height: 0)
        case 292.5...337.5:
            return CGSize(width: -xAngleOff, height: yAngleOff)
        case 337.5...360:
            return CGSize(width: 0, height: yFlatfOff)
        default:
            return CGSize(width: 0, height: 0)
        }
    }
//    private func exponentialPercent(value: CGFloat, maxVal: CGFloat) -> CGFloat {
//        let normalized = value /  maxVal
//        
//        let numerator = pow(10, normalized) - 1
//        let denominator: CGFloat = 9
//        return CGFloat(numerator / denominator)
//    }
//    
//    private func bearingToOffSet(degrees: CGFloat, width: CGFloat, height: CGFloat) -> CGSize {
//        let inputRadians = (degrees-90) * .pi / 180.0
//        let squareX = cos(inputRadians)
//        let squareY = sin(inputRadians)
//        
//        let rectX = squareX * width
//        let rectY = squareY * height
//        
//        let radians = atan2(rectY, rectX)
//        
//        let dx = cos(radians)
//        let dy = sin(radians)
//        
//        let xBound = width / 2.0
//        let yBound = height / 2.0
//        
//        let tx = abs(dx) > 0.0001 ? xBound / abs(dx) : CGFloat.greatestFiniteMagnitude
//        let ty = abs(dy) > 0.0001 ? yBound / abs(dy) : CGFloat.greatestFiniteMagnitude
//        
//        let t = min(tx, ty)
//        
//        let degreesToCorner = 45 - abs(45 - degrees.truncatingRemainder(dividingBy: 90))
//        let inOffsetPercent = 1 - (exponentialPercent(value: degreesToCorner, maxVal: 45) * 0.2)
//        let inXOffsetPercent = inOffsetPercent * height / width
//        
//        return CGSize(width: t * dx * inOffsetPercent, height: t * dy * inXOffsetPercent)
//    }
}

#Preview {
    VehicleAnnotationView(vehicle: Vehicle(id: "10", position: CLLocationCoordinate2D(latitude: 0, longitude: 0), bearing: 45, label: "194"))
}
