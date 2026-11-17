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

    @Environment(TripDetailModel.self) private var trip

    private var color: Color { MapMarkerStyle.color(for: vehicle.type) }

    var body: some View {
        // Refresh often enough that "Now" and minute counts stay honest between position updates.
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let timed = trip.timedStops(now: context.date)
            let upcoming = TripTimetable.upcomingStops(timed, currentStopSequence: vehicle.currentStopSequence, now: context.date)

            VStack(alignment: .leading, spacing: 0) {
                header(nextStop: upcoming.first)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                Divider()

                content(upcoming: upcoming, now: context.date)
            }
        }
    }

    // MARK: - Header

    private func header(nextStop: TimedStop?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(line: vehicle.displayLine, color: color)

            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.headsign ?? trip.detail?.summary.headsign ?? "Unknown destination")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text("\(vehicle.type == .tram ? "Tram" : "Bus") #\(vehicle.label)")
                        .foregroundStyle(.secondary)
                    if let nextStop {
                        Text("·").foregroundStyle(.tertiary)
                        DelayLabel(stop: nextStop)
                    }
                }
                .font(.subheadline)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.gray.opacity(0.8))
            }
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Stops

    @ViewBuilder
    private func content(upcoming: [TimedStop], now: Date) -> some View {
        switch trip.state {
        case .loaded:
            if upcoming.isEmpty {
                message("Trip finished", systemImage: "flag.checkered", detail: "This vehicle has no more stops on this trip.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, stop in
                            NextStopRow(
                                stop: stop,
                                now: now,
                                color: color,
                                isNext: index == 0,
                                isLast: index == upcoming.count - 1
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        case .preparingTimetable:
            message("Preparing timetable", systemImage: "arrow.down.circle", detail: "Downloading the latest schedule. This only takes a moment the first time.", showsProgress: true)
        case .unavailable:
            message("No timetable", systemImage: "calendar.badge.exclamationmark", detail: "This trip isn't in the current schedule.")
        case .idle, .loading:
            if vehicle.tripID == nil {
                message("No trip", systemImage: "questionmark.circle", detail: "This vehicle isn't reporting a trip right now.")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            }
        }
    }

    private func message(_ title: String, systemImage: String, detail: String, showsProgress: Bool = false) -> some View {
        VStack(spacing: 8) {
            if showsProgress {
                ProgressView().padding(.bottom, 4)
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 28)
    }
}

// MARK: - Pieces

/// The line number on a tile in the line's colour, matching the map marker.
struct LineBadge: View {
    let line: String
    let color: Color

    var body: some View {
        Text(line)
            .font(MapMarkerStyle.labelFont(size: 20))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: 52, minHeight: 40)
            .padding(.horizontal, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityLabel("Line \(line)")
    }
}

/// "On time", "3 min late" or "1 min early", from the expected and scheduled time of the next stop.
private struct DelayLabel: View {
    let stop: TimedStop

    var body: some View {
        if !stop.isRealtime {
            Text("Scheduled").foregroundStyle(.secondary)
        } else {
            let minutes = Int((stop.delay / 60).rounded())
            if minutes >= 1 {
                Text("\(minutes) min late").foregroundStyle(.orange)
            } else if minutes <= -1 {
                Text("\(-minutes) min early").foregroundStyle(.blue)
            } else {
                Text("On time").foregroundStyle(.green)
            }
        }
    }
}

/// One stop in the list: a dot on the route line, the stop name, and when the vehicle leaves it.
private struct NextStopRow: View {
    let stop: TimedStop
    let now: Date
    let color: Color
    let isNext: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 14) {
            RouteTrack(color: color, isFirst: isNext, isLast: isLast, isEmphasized: isNext)

            Text(stop.stop.name)
                .font(isNext ? .body.weight(.semibold) : .body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            DepartureTime(expected: stop.expected, now: now, isEmphasized: isNext)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// The vertical line that ties the stops together, with a dot for this stop.
private struct RouteTrack: View {
    let color: Color
    let isFirst: Bool
    let isLast: Bool
    let isEmphasized: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? .clear : color)
                .frame(width: 4)
            Circle()
                .fill(isEmphasized ? color : .white)
                .stroke(color, lineWidth: 3)
                .frame(width: isEmphasized ? 16 : 12, height: isEmphasized ? 16 : 12)
            Rectangle()
                .fill(isLast ? .clear : color)
                .frame(width: 4)
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity)
    }
}

/// Time until departure ("Now", "4 min"), with the clock time underneath.
/// An hour or more away, only the clock time is shown.
private struct DepartureTime: View {
    let expected: Date
    let now: Date
    let isEmphasized: Bool

    private var seconds: TimeInterval { expected.timeIntervalSince(now) }
    private var clock: String { expected.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if seconds >= 60 * 60 {
                Text(clock)
                    .font(.body.weight(isEmphasized ? .semibold : .regular))
            } else {
                Text(seconds < 60 ? "Now" : "\(Int(seconds / 60)) min")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEmphasized ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(clock)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

#Preview {
    VehicleDetailSheetView(vehicle: Vehicle(id: "123", coordinate: .init(latitude: 50.0, longitude: 19.0), bearing: 90, label: "103", lineNumber: "52", headsign: "Czerwone Maki P+R"), onClose: {})
        .environment(TripDetailModel(staticData: LocalGTFSDataSource()))
}
