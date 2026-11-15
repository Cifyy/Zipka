//
//  ClusterAnnotationView.swift
//  Zipka
//

import SwiftUI

struct ClusterAnnotationView: View {
    let count: Int
    /// How many of the clustered vehicles are trams; the rest are buses.
    var tramCount: Int = 0

    private var diameter: CGFloat {
        switch count {
        case ..<10: 34
        case ..<50: 40
        default: 46
        }
    }

    private let ringWidth: CGFloat = 3
    /// White margin between the ring and the edge of the bubble.
    private let ringInset: CGFloat = 2.5

    private var tramFraction: CGFloat {
        count > 0 ? CGFloat(tramCount) / CGFloat(count) : 0
    }

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(MapMarkerStyle.labelFont(size: count < 100 ? 14 : 12))
            .monospacedDigit()
            .foregroundStyle(MapMarkerStyle.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, ringInset + ringWidth + 2)
            .frame(width: diameter, height: diameter)
            .background(ring.padding(ringInset + ringWidth / 2))
            .background(
                Circle()
                    .fill(.white)
                    .shadow(color: MapMarkerStyle.shadow, radius: 3, y: 1)
            )
            .contentShape(Circle())
            .accessibilityElement()
            .accessibilityLabel("\(count) vehicles")
            .accessibilityAddTraits(.isButton)
    }
    
    /// A ring split by vehicle type: the tram share starts at the top and runs clockwise.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(MapMarkerStyle.bus, lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: tramFraction)
                .stroke(MapMarkerStyle.tram, lineWidth: ringWidth)
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        ClusterAnnotationView(count: 4, tramCount: 1)
        ClusterAnnotationView(count: 23, tramCount: 23)
        ClusterAnnotationView(count: 148, tramCount: 50)
        ClusterAnnotationView(count: 7)
    }
    .padding(40)
    .background(Color(white: 0.93))
}
