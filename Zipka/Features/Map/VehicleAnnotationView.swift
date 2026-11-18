//
//  VehicleAnnotationView.swift
//  Zipka
//
//  Created by Jakub Majka on 5/12/25.
//

import SwiftUI
import CoreLocation

/// Shared look of the map markers, so vehicles and clusters read as one family.
enum MapMarkerStyle {
    /// Petrol blue.
    static let bus = Color(red: 0.07, green: 0.42, blue: 0.58)
    /// Burnt orange.
    static let tram = Color(red: 0.84, green: 0.44, blue: 0.13)
    /// Text colour on the white cluster bubbles.
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.19)
    static let shadow = Color.black.opacity(0.22)

    static func color(for type: VehicleType) -> Color {
        switch type {
        case .bus: bus
        case .tram: tram
        }
    }

    static func labelFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension View {
    /// The markers' drop shadow, baked into their bitmap.
    ///
    /// A plain `.shadow` ends up as a Core Animation shadow without a shadow path, which is
    /// rendered offscreen again on every frame while the map pans or zooms, once per marker.
    /// Flattening the marker with `drawingGroup()` draws the shadow only when the marker changes.
    ///
    /// - Parameter overflow: How far the content may reach past the view's frame (for example
    ///   when it is scaled up), so the flattened bitmap does not cut it off.
    func markerShadow(radius: CGFloat, y: CGFloat = 1, overflow: CGFloat = 0) -> some View {
        let margin = overflow + radius * 2 + abs(y)
        return compositingGroup()
            .shadow(color: MapMarkerStyle.shadow, radius: radius, y: y)
            .padding(margin)
            .drawingGroup()
            .padding(-margin)
    }
}

struct VehicleAnnotationView: View {
    let vehicle: Vehicle
    var isSelected: Bool = false

    private let tileSize = CGSize(width: 34, height: 26)
    private let cornerRadius: CGFloat = 9
    /// White border of the tile; kept equal to `pointerOutline` so both outlines match.
    private let borderWidth: CGFloat = 1.5
    /// Width and length of the arrow tip before its corners are rounded off.
    private let pointerSize = CGSize(width: 9.5, height: 7.5)
    /// Stroke in the fill colour that rounds every corner of the pointer; the corner radius is half of it.
    private let pointerRounding: CGFloat = 4
    /// Width of the white outline around the pointer.
    private let pointerOutline: CGFloat = 1.5
    /// Width of the see-through band around the tile that keeps the pointer at a distance.
    private let bandWidth: CGFloat = 1.5
    private let selectedScale: CGFloat = 1.3

    private var color: Color { MapMarkerStyle.color(for: vehicle.type) }

    /// How far the pointer's path stays from the tile's edge. The rounding stroke and the
    /// white outline are drawn on top of that, which leaves exactly `bandWidth` see-through.
    private var pointerClearance: CGFloat {
        borderWidth + bandWidth + pointerOutline + pointerRounding / 2
    }

    /// Big enough to hold the pointer at any bearing, so the marker never changes size.
    private var frameSize: CGSize {
        let margin = pointerClearance + pointerSize.height + pointerRounding / 2 + pointerOutline
        return CGSize(width: tileSize.width + margin * 2, height: tileSize.height + margin * 2)
    }

    var body: some View {
        ZStack {
            if let bearing = vehicle.bearing {
                pointer(bearing: Double(bearing))
            }

            RoundedRectangle(cornerRadius: cornerRadius + borderWidth, style: .continuous)
                .fill(.white)
                .frame(width: tileSize.width + borderWidth * 2, height: tileSize.height + borderWidth * 2)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
                .frame(width: tileSize.width, height: tileSize.height)

            Text(vehicle.displayLine)
                .font(MapMarkerStyle.labelFont(size: 13))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: tileSize.width - borderWidth * 2)
        }
        .frame(width: frameSize.width, height: frameSize.height)
        // Scaled inside the flattened bitmap, so the selected marker stays sharp.
        .scaleEffect(isSelected ? selectedScale : 1)
        .markerShadow(
            radius: isSelected ? 6 : 3,
            overflow: max(frameSize.width, frameSize.height) * (selectedScale - 1) / 2
        )
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isSelected)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let kind = vehicle.type == .tram ? "Tram" : "Bus"
        guard let headsign = vehicle.headsign else { return "\(kind) \(vehicle.displayLine)" }
        return "\(kind) \(vehicle.displayLine) to \(headsign)"
    }

    private func pointer(bearing: Double) -> some View {
        let shape = PointerShape(
            bearing: bearing,
            tileSize: tileSize,
            cornerRadius: cornerRadius,
            tipSize: pointerSize,
            clearance: pointerClearance
        )
        return shape
            .fill(color)
            .stroke(color, style: StrokeStyle(lineWidth: pointerRounding, lineJoin: .round))
            .background(
                shape.stroke(.white, style: StrokeStyle(lineWidth: pointerRounding + pointerOutline * 2, lineJoin: .round))
            )
            .frame(width: frameSize.width, height: frameSize.height)
    }
}

/// The arrow next to a vehicle tile, in the coordinate space of the whole marker
/// (the tile is centred in the rect).
///
/// It is an arrow tip with a straight body behind it that reaches back under the tile;
/// the tile, grown by `clearance`, is then cut out of it. What remains is an arrow of
/// constant width whose base follows the tile's shape: flat on the sides, curved at the corners.
private struct PointerShape: Shape {
    /// Direction of travel in degrees, clockwise from north.
    var bearing: Double
    let tileSize: CGSize
    let cornerRadius: CGFloat
    /// Width and length of the triangular tip.
    let tipSize: CGSize
    /// Distance kept between the tile's edge and this path.
    let clearance: CGFloat

    var animatableData: Double {
        get { bearing }
        set { bearing = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radians = bearing * .pi / 180
        let direction = CGVector(dx: sin(radians), dy: -cos(radians))
        let anchor = outlineAnchor(facing: direction)

        // Drawn pointing up with the tip at the origin, then rotated and moved into place.
        let bodyLength = clearance + cornerRadius
        let halfWidth = tipSize.width / 2
        var arrow = Path()
        arrow.move(to: .zero)
        arrow.addLine(to: CGPoint(x: halfWidth, y: tipSize.height))
        arrow.addLine(to: CGPoint(x: halfWidth, y: tipSize.height + bodyLength))
        arrow.addLine(to: CGPoint(x: -halfWidth, y: tipSize.height + bodyLength))
        arrow.addLine(to: CGPoint(x: -halfWidth, y: tipSize.height))
        arrow.closeSubpath()

        let tipDistance = clearance + tipSize.height
        let transform = CGAffineTransform(
            translationX: rect.midX + anchor.x + direction.dx * tipDistance,
            y: rect.midY + anchor.y + direction.dy * tipDistance
        ).rotated(by: radians)

        let cutout = Path(
            roundedRect: CGRect(
                x: rect.midX - tileSize.width / 2 - clearance,
                y: rect.midY - tileSize.height / 2 - clearance,
                width: tileSize.width + clearance * 2,
                height: tileSize.height + clearance * 2
            ),
            cornerRadius: cornerRadius + clearance,
            style: .continuous
        )
        return arrow.applying(transform).subtracting(cutout)
    }

    /// The point on the tile's outline where the pointer attaches for a given unit direction,
    /// relative to the tile's centre.
    ///
    /// Rather than shooting a ray from the centre (which meets the outline at a slant, so the
    /// pointer sits crooked near the corners), this picks the spot where the outline itself
    /// faces `direction`. An ellipse inside the tile, grown by the corner radius, gives that
    /// spot a smooth path: centred on an edge for the four cardinal directions and sliding
    /// round the corners between.
    private func outlineAnchor(facing direction: CGVector) -> CGPoint {
        let innerWidth = tileSize.width / 2 - cornerRadius
        let innerHeight = tileSize.height / 2 - cornerRadius

        // Point on the inner ellipse whose normal is `direction`.
        let scaledX = innerWidth * innerWidth * direction.dx
        let scaledY = innerHeight * innerHeight * direction.dy
        let norm = max(sqrt(innerWidth * innerWidth * direction.dx * direction.dx + innerHeight * innerHeight * direction.dy * direction.dy), 0.0001)
        var point = CGPoint(
            x: scaledX / norm + cornerRadius * direction.dx,
            y: scaledY / norm + cornerRadius * direction.dy
        )

        let overX = max(abs(point.x) - innerWidth, 0)
        let overY = max(abs(point.y) - innerHeight, 0)
        let inside = min(max(abs(point.x) - innerWidth, abs(point.y) - innerHeight), 0)
        let signedDistance = sqrt(overX * overX + overY * overY) + inside - cornerRadius
        if signedDistance < 0 {
            point.x -= direction.dx * signedDistance
            point.y -= direction.dy * signedDistance
        }
        return point
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            VehicleAnnotationView(vehicle: Vehicle(id: "1", coordinate: CLLocationCoordinate2D(), bearing: 0, label: "414", feed: .tram, lineNumber: "52"))
            VehicleAnnotationView(vehicle: Vehicle(id: "2", coordinate: CLLocationCoordinate2D(), bearing: 45, label: "194", lineNumber: "476"))
            VehicleAnnotationView(vehicle: Vehicle(id: "3", coordinate: CLLocationCoordinate2D(), bearing: 200, label: "613", feed: .tram, lineNumber: "4"))
            VehicleAnnotationView(vehicle: Vehicle(id: "4", coordinate: CLLocationCoordinate2D(), bearing: nil, label: "52", lineNumber: "139"))
        }
        VehicleAnnotationView(vehicle: Vehicle(id: "5", coordinate: CLLocationCoordinate2D(), bearing: 290, label: "139", lineNumber: "52"), isSelected: true)
    }
    .padding(40)
    .background(Color(white: 0.93))
}
