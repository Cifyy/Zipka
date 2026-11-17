//
//  ApiService.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import Foundation
import SwiftProtobuf
import ZIpkaProtobuf

enum fetchError: Error {
    case runtimeError(String)
}

/// Live predictions for one trip from the GTFS-realtime TripUpdates feed.
nonisolated struct TripRealtimeUpdate: Sendable, Equatable {
    nonisolated struct StopTime: Sendable, Equatable {
        let stopSequence: Int?
        let stopID: String?
        let arrival: Date?
        let departure: Date?
        /// Seconds behind schedule, when the feed gives it.
        let delay: Int?
        let isSkipped: Bool
    }

    let tripID: String
    let stopTimes: [StopTime]
    /// Trip-level delay in seconds, for feeds that do not give per-stop times.
    let delay: Int?
}

/// Fetching and decoding of GTFS-realtime feeds. Decoding runs off the main actor.
nonisolated final class ApiService: Sendable {

    @concurrent
    func fetchRealtimeDataAsync(request: URL) async throws -> TransitRealtime_FeedMessage {
        let (data, _) = try await URLSession.shared.data(from: request)
        do {
            return try TransitRealtime_FeedMessage(serializedBytes: data)
        } catch {
            throw fetchError.runtimeError("An error occurred while fetching data: \(error)")
        }
    }

    /// The current predictions for `tripID`, or `nil` when the feed has none for it.
    @concurrent
    func fetchTripUpdate(feed: TransitFeed, tripID: String) async throws -> TripRealtimeUpdate? {
        let message = try await fetchRealtimeDataAsync(request: feed.tripUpdatesURL)
        guard let update = message.entity.first(where: { $0.hasTripUpdate && $0.tripUpdate.trip.tripID == tripID })?.tripUpdate else {
            return nil
        }

        func date(_ event: TransitRealtime_TripUpdate.StopTimeEvent) -> Date? {
            // Some feeds send an empty event (time 0) for stops they have no prediction for.
            event.hasTime && event.time > 0 ? Date(timeIntervalSince1970: TimeInterval(event.time)) : nil
        }

        func delay(_ event: TransitRealtime_TripUpdate.StopTimeEvent) -> Int? {
            event.hasDelay ? Int(event.delay) : nil
        }

        let stopTimes = update.stopTimeUpdate.map { stopTime in
            let arrival = stopTime.hasArrival ? date(stopTime.arrival) : nil
            let departure = stopTime.hasDeparture ? date(stopTime.departure) : nil
            // Take the delay from the event that carries a real prediction.
            let stopDelay = departure != nil ? delay(stopTime.departure)
                : arrival != nil ? delay(stopTime.arrival)
                : stopTime.hasDeparture ? delay(stopTime.departure)
                : stopTime.hasArrival ? delay(stopTime.arrival) : nil
            return TripRealtimeUpdate.StopTime(
                stopSequence: stopTime.hasStopSequence ? Int(stopTime.stopSequence) : nil,
                stopID: stopTime.hasStopID ? stopTime.stopID : nil,
                arrival: arrival,
                departure: departure,
                delay: stopDelay,
                isSkipped: stopTime.scheduleRelationship == .skipped
            )
        }
        return TripRealtimeUpdate(
            tripID: tripID,
            stopTimes: stopTimes,
            delay: update.hasDelay ? Int(update.delay) : nil
        )
    }
}
