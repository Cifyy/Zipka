//
//  RouteStopAnnotationView.swift
//  Zipka
//

import SwiftUI

/// A stop on the selected vehicle's route: a small ring in the line's colour,
/// greyed out once the vehicle has passed it.
struct RouteStopAnnotationView: View {
    let color: Color
    var isPassed: Bool = false

    var body: some View {
        ZStack {
            // The shadow is a plain shape: cheap to draw, and a blur this small comes out
            // square when flattened with `markerShadow`.
            Circle()
                .fill(MapMarkerStyle.shadow)
                .frame(width: 16, height: 16)
                .offset(y: 0.5)
            Circle()
                .fill(.white)
                .stroke(isPassed ? Color.gray.opacity(0.6) : color, lineWidth: 3)
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        RouteStopAnnotationView(color: MapMarkerStyle.bus)
        RouteStopAnnotationView(color: MapMarkerStyle.tram)
        RouteStopAnnotationView(color: MapMarkerStyle.tram, isPassed: true)
    }
    .padding()
    .background(Color(white: 0.93))
}
