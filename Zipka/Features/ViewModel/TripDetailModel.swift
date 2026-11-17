//
//  TripDetailModel.swift
//  Zipka
//

import Foundation
import CoreLocation
import Observation

/// The trip of the selected vehicle: its route and stops from the static timetable,
/// kept up to date with realtime predictions while it is being tracked.
@Observable
final class TripDetailModel {
    enum State {
        case idle
        case loading
        /// The timetable is still being downloaded or processed.
        case preparingTimetable
        /// The timetable has no such trip, or loading failed.
        case unavailable
        case loaded(TripDetail)
    }

    private(set) var state: State = .idle
    private(set) var realtime: TripRealtimeUpdate?
    /// Path to draw on the map: the trip's shape, or straight lines between its stops when there is none.
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []

    private(set) var tripID: String?

    private let staticData: any TransitStaticDataSource
    private let apiService = ApiService()
    private let realtimeInterval: Duration = .seconds(15)

    init(staticData: any TransitStaticDataSource) {
        self.staticData = staticData
    }

    var detail: TripDetail? {
        if case .loaded(let detail) = state { detail } else { nil }
    }

    /// Loads the trip, then keeps its realtime predictions fresh until the calling task is cancelled.
    func track(feed: TransitFeed, tripID: String) async {
        if self.tripID != tripID {
            self.tripID = tripID
            state = .loading
            realtime = nil
            routeCoordinates = []
        }

        do {
            if let detail = try await staticData.tripDetail(in: feed, tripID: tripID) {
                guard self.tripID == tripID else { return }
                state = .loaded(detail)
                routeCoordinates = Self.coordinates(for: detail)
            } else {
                state = .unavailable
            }
        } catch TransitDataError.notReady {
            state = .preparingTimetable
        } catch {
            if Task.isCancelled { return }
            print("Loading trip \(tripID) failed: \(error)")
            state = .unavailable
        }

        while !Task.isCancelled {
            do {
                let update = try await apiService.fetchTripUpdate(feed: feed, tripID: tripID)
                guard self.tripID == tripID, !Task.isCancelled else { return }
                realtime = update
            } catch {
                // Keep the last prediction; the next attempt may succeed.
            }
            do {
                try await Task.sleep(for: realtimeInterval)
            } catch {
                return
            }
        }
    }

    func reset() {
        tripID = nil
        state = .idle
        realtime = nil
        routeCoordinates = []
    }

    /// Stops with scheduled and expected times, with the vehicle's live position taken into account.
    func timedStops(now: Date) -> [TimedStop] {
        guard let detail else { return [] }
        return TripTimetable.timedStops(for: detail, realtime: realtime, now: now)
    }

    private static func coordinates(for detail: TripDetail) -> [CLLocationCoordinate2D] {
        if detail.shape.count >= 2 {
            return detail.shape.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        return detail.stops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
