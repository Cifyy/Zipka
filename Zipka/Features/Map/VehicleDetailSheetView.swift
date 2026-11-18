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
                    .padding(.top, 22)
                    .padding(.bottom, 10)

                content(upcoming: upcoming, now: context.date)
            }
        }
    }

    // MARK: - Header

    private func header(nextStop: TimedStop?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            LinePill(line: vehicle.displayLine, color: color)

            VStack(alignment: .leading, spacing: 1) {
                Text(vehicle.headsign ?? trip.detail?.summary.headsign ?? "Unknown destination")
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("\(vehicle.type == .tram ? "Tram" : "Bus") \(vehicle.label)")
                    if let nextStop {
                        Text("·")
                        StatusText(stop: nextStop)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Stops

    @ViewBuilder
    private func content(upcoming: [TimedStop], now: Date) -> some View {
        switch trip.state {
        case .loaded:
            if upcoming.isEmpty {
                message("Trip finished", systemImage: "flag.checkered")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, stop in
                            StopRow(
                                stop: stop,
                                now: now,
                                color: color,
                                isNext: index == 0,
                                isLast: index == upcoming.count - 1
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
        case .preparingTimetable:
            message("Preparing timetable…", systemImage: nil)
        case .unavailable:
            message("No timetable for this trip", systemImage: "calendar.badge.exclamationmark")
        case .idle, .loading:
            if vehicle.tripID == nil {
                message("Not in service", systemImage: "moon.zzz")
            } else {
                message(nil, systemImage: nil)
            }
        }
    }

    /// A quiet one-line state in place of the list. With no symbol it shows a spinner.
    private func message(_ title: String?, systemImage: String?) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            } else {
                ProgressView().controlSize(.small)
            }
            if let title {
                Text(title)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

// MARK: - Pieces

/// The line number on a small pill in the line's colour.
private struct LinePill: View {
    let line: String
    let color: Color

    var body: some View {
        Text(line)
            .font(MapMarkerStyle.labelFont(size: 17))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .frame(minWidth: 46, minHeight: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel("Line \(line)")
    }
}

/// "On time", "3 min late" or "1 min early" for the next stop. Only a delay gets a colour.
private struct StatusText: View {
    let stop: TimedStop

    var body: some View {
        if !stop.isRealtime {
            Text("Scheduled")
        } else {
            let minutes = Int((stop.delay / 60).rounded())
            if minutes >= 1 {
                Text("\(minutes) min late").foregroundStyle(.orange)
            } else if minutes <= -1 {
                Text("\(-minutes) min early")
            } else {
                Text("On time")
            }
        }
    }
}

/// One stop: a point on a thin track, the stop name, and when the vehicle leaves it.
private struct StopRow: View {
    let stop: TimedStop
    let now: Date
    let color: Color
    let isNext: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 14) {
            Track(color: color, isFirst: isNext, isLast: isLast, isNext: isNext)

            Text(stop.stop.name)
                .font(isNext ? .body.weight(.semibold) : .body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(departureText)
                .font(.callout.weight(isNext ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isNext ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stop.stop.name), \(departureText), at \(clock)")
    }

    private var clock: String { stop.expected.formatted(date: .omitted, time: .shortened) }

    /// "Now", "4 min", or the clock time once it is an hour or more away.
    private var departureText: String {
        let seconds = stop.expected.timeIntervalSince(now)
        if seconds < 60 { return "Now" }
        if seconds < 60 * 60 { return "\(Int(seconds / 60)) min" }
        return clock
    }
}

/// The vertical line that ties the stops together. The next stop gets a solid dot,
/// the rest a small ring.
private struct Track: View {
    let color: Color
    let isFirst: Bool
    let isLast: Bool
    let isNext: Bool

    var body: some View {
        VStack(spacing: 0) {
            segment(hidden: isFirst)
            Group {
                if isNext {
                    Circle().fill(color).frame(width: 12, height: 12)
                } else {
                    Circle().strokeBorder(color, lineWidth: 2).frame(width: 9, height: 9)
                }
            }
            .padding(.vertical, 2)
            segment(hidden: isLast)
        }
        .frame(width: 12)
    }

    private func segment(hidden: Bool) -> some View {
        Rectangle()
            .fill(hidden ? Color.clear : color.opacity(0.35))
            .frame(width: 2)
    }
}

#Preview {
    VehicleDetailSheetView(vehicle: Vehicle(id: "123", coordinate: .init(latitude: 50.0, longitude: 19.0), bearing: 90, label: "103", lineNumber: "52", headsign: "Czerwone Maki P+R"), onClose: {})
        .environment(TripDetailModel(staticData: LocalGTFSDataSource()))
}
