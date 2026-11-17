//
//  TripTimetable.swift
//  Zipka
//

import Foundation

/// A stop on a trip with real dates: scheduled from the timetable, expected after applying realtime predictions.
nonisolated struct TimedStop: Identifiable, Hashable, Sendable {
    let stop: TripStop
    let scheduled: Date
    let expected: Date
    /// Whether `expected` comes from the realtime feed rather than only the timetable.
    let isRealtime: Bool
    let isSkipped: Bool

    var id: Int { stop.sequence }
    /// Seconds behind schedule (negative when early).
    var delay: TimeInterval { expected.timeIntervalSince(scheduled) }
}

/// Combines a trip's timetable with its realtime update.
nonisolated enum TripTimetable {
    static let timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current

    /// Every stop of the trip with its scheduled and expected departure.
    static func timedStops(for detail: TripDetail, realtime: TripRealtimeUpdate?, now: Date) -> [TimedStop] {
        let stops = detail.stops
        guard !stops.isEmpty else { return [] }

        let updates = matchUpdates(realtime, to: stops)
        let dayStart = serviceDayStart(for: stops, updates: updates, now: now)

        // A delay holds for the following stops until the feed says otherwise.
        var propagatedDelay: TimeInterval? = realtime?.delay.map(TimeInterval.init)
        if propagatedDelay == nil, let firstUpdate = updates.min(by: { $0.key < $1.key })?.value {
            propagatedDelay = delay(of: firstUpdate, scheduled: dayStart.addingTimeInterval(TimeInterval(stops[firstUpdate.index].departure)))
        }

        return stops.enumerated().map { index, stop in
            let scheduled = dayStart.addingTimeInterval(TimeInterval(stop.departure))
            let update = updates[index]
            if let update, let predicted = update.time.departure ?? update.time.arrival {
                propagatedDelay = predicted.timeIntervalSince(scheduled)
                return TimedStop(stop: stop, scheduled: scheduled, expected: predicted, isRealtime: true, isSkipped: update.time.isSkipped)
            }
            if let update, let delay = update.time.delay {
                propagatedDelay = TimeInterval(delay)
            }
            let expected = scheduled.addingTimeInterval(propagatedDelay ?? 0)
            return TimedStop(
                stop: stop,
                scheduled: scheduled,
                expected: expected,
                isRealtime: propagatedDelay != nil,
                isSkipped: update?.time.isSkipped ?? false
            )
        }
    }

    /// The stops the vehicle has yet to leave, in order.
    ///
    /// Uses the vehicle's reported stop when there is one, and the expected times otherwise.
    static func upcomingStops(_ timed: [TimedStop], currentStopSequence: Int?, now: Date) -> [TimedStop] {
        let remaining: ArraySlice<TimedStop>
        if let currentStopSequence, let index = timed.firstIndex(where: { $0.stop.sequence >= currentStopSequence }) {
            remaining = timed[index...]
        } else if let index = timed.firstIndex(where: { $0.expected.timeIntervalSince(now) > -30 }) {
            remaining = timed[index...]
        } else {
            remaining = []
        }
        return remaining.filter { !$0.isSkipped }
    }

    // MARK: - Helpers

    struct MatchedUpdate {
        let index: Int
        let time: TripRealtimeUpdate.StopTime
    }

    /// Pairs realtime stop updates with timetable stops, by `stop_sequence` when given and otherwise by
    /// stop ID in travel order (so a stop that is visited twice is matched to the right visit).
    private static func matchUpdates(_ realtime: TripRealtimeUpdate?, to stops: [TripStop]) -> [Int: MatchedUpdate] {
        guard let realtime else { return [:] }
        var matched: [Int: MatchedUpdate] = [:]
        var searchFrom = 0
        for time in realtime.stopTimes {
            var index: Int?
            if let sequence = time.stopSequence {
                index = stops.firstIndex { $0.sequence == sequence }
            } else if let stopID = time.stopID, searchFrom < stops.count {
                index = stops[searchFrom...].firstIndex { $0.stopID == stopID }
            }
            if let index {
                matched[index] = MatchedUpdate(index: index, time: time)
                searchFrom = index + 1
            }
        }
        return matched
    }

    private static func delay(of update: MatchedUpdate, scheduled: Date) -> TimeInterval? {
        if let predicted = update.time.departure ?? update.time.arrival {
            return predicted.timeIntervalSince(scheduled)
        }
        return update.time.delay.map(TimeInterval.init)
    }

    /// GTFS times count from "noon minus 12 hours" of the service day, which is midnight except on
    /// daylight-saving days. Picks yesterday, today or tomorrow, whichever puts the trip closest to now
    /// (or to its realtime predictions, when there are any).
    static func serviceDayStart(for stops: [TripStop], updates: [Int: MatchedUpdate] = [:], now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let candidates = (-1...1).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return nil }
            return noon.addingTimeInterval(-12 * 60 * 60)
        }

        // A realtime prediction pins the trip down best.
        let predictedUpdate = updates.values
            .filter { ($0.time.departure ?? $0.time.arrival) != nil }
            .min { $0.index < $1.index }
        if let update = predictedUpdate, let predicted = update.time.departure ?? update.time.arrival {
            let scheduledOffset = TimeInterval(stops[update.index].departure)
            return candidates.min { abs($0.addingTimeInterval(scheduledOffset).timeIntervalSince(predicted)) < abs($1.addingTimeInterval(scheduledOffset).timeIntervalSince(predicted)) } ?? now
        }

        let first = TimeInterval(stops.first?.departure ?? 0)
        let last = TimeInterval(stops.last?.departure ?? 0)
        func distance(_ start: Date) -> TimeInterval {
            let begin = start.addingTimeInterval(first), end = start.addingTimeInterval(last)
            if now < begin { return begin.timeIntervalSince(now) }
            if now > end { return now.timeIntervalSince(end) }
            return 0
        }
        return candidates.min { distance($0) < distance($1) } ?? now
    }
}
