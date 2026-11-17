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
        Circle()
            .fill(.white)
            .stroke(isPassed ? Color.gray.opacity(0.6) : color, lineWidth: 3)
            .frame(width: 12, height: 12)
            .shadow(color: MapMarkerStyle.shadow, radius: 1.5, y: 0.5)
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
