//
//  MapControlsView.swift
//  Zipka
//
//  Created by Jakub Majka on 6/12/25.
//

import SwiftUI
import MapKit

struct MapControlsView: View {
    var scope: Namespace.ID
    @Binding var mapStyle: MapStyle
    
    // capsule rerenders on menu close, maybe it will get fixed somedaymake a 
    var body: some View {
        VStack(spacing: 0) {
            Menu {
                Button("Standard", systemImage: "map") {
                    mapStyle = .standard
                }
                Button("Hybrid", systemImage: "globe.americas.fill") {
                    mapStyle = .hybrid
                }
                Button("Satellite", systemImage: "globe.americas") {
                    mapStyle = .imagery
                }
            } label: {
                Image(systemName: "map")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            Divider()
                .background(Color.primary.opacity(0.2))
                .frame(width: 30)
            
            MapUserLocationButton(scope: scope)
                .tint(Color.primary)
                .foregroundColor(Color.primary)
                .frame(width: 44, height: 44)
                .clipShape(
                    RoundedCorner(
                        radius: 22,
                        corners: [.bottomLeft, .bottomRight]
                    )
                )
            
        }
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

struct RoundedCorner: InsettableShape {
    var radius: CGFloat
    var corners: UIRectCorner
    var insetAmount: CGFloat = 0
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect.insetBy(dx: insetAmount, dy: insetAmount),
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
    
    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
//#Preview {
//    @Previewable @Namespace var scope
//    @Previewable @State var style: MapStyle = .standard
//    MapControlsView(scope: scope, mapStyle: $style)
//}
