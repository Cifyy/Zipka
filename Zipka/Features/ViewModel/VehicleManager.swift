//
//  VehicleManager.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import Foundation
import CoreLocation
import SwiftUI
import Observation
import ZIpkaProtobuf

@Observable
class VehicleManager {
    private let apiService = ApiService()
    let staticData: any TransitStaticDataSource

    var vehicles: [Vehicle] = []
    var busList: [Vehicle] = []
    var tramList: [Vehicle] = []

    /// Increases whenever a newer static timetable becomes available, so views can reload what they derived from it.
    private(set) var staticDataRevision = 0

    private var tripSummaries: [TransitFeed: [String: TripSummary]] = [:]
    /// Trips the timetable does not know, so they are not looked up again on every refresh.
    private var unknownTrips: [TransitFeed: Set<String>] = [:]
    private var isRefreshingStaticData = false
    private var lastStaticDataRefresh: Date?
    /// How often to ask the data source whether the timetable changed. The source throttles itself too.
    private let staticDataRefreshInterval: TimeInterval = 60 * 60

    private var timer: Timer?
    private let locationManager: LocationManager

    init(locationManager: LocationManager, staticData: any TransitStaticDataSource) {
        self.locationManager = locationManager
        self.staticData = staticData
        startUpdating()
    }

    deinit {
        stopUpdating()
    }

    func startUpdating() {
        fetchVehicles()
        refreshStaticDataIfNeeded()

        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fetchVehicles()
                self?.refreshStaticDataIfNeeded()
            }
        }
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Static timetable

    /// Lets the data source download and process a new timetable if one was published.
    func refreshStaticDataIfNeeded() {
        guard !isRefreshingStaticData else { return }
        if let lastStaticDataRefresh, Date.now.timeIntervalSince(lastStaticDataRefresh) < staticDataRefreshInterval { return }
        isRefreshingStaticData = true

        Task {
            var succeeded = true
            // Trams first: their feed is small, so their line numbers show up sooner on a first launch.
            for feed in [TransitFeed.tram, .bus] {
                do {
                    if try await staticData.refresh(feed) {
                        tripSummaries[feed] = nil
                        unknownTrips[feed] = nil
                        staticDataRevision += 1
                        await resolveTrips(in: feed)
                        applyTripSummaries()
                    }
                } catch {
                    succeeded = false
                    print("Static data refresh for \(feed) failed: \(error)")
                }
            }
            // Retry failures on the next tick instead of waiting the full interval.
            if succeeded { lastStaticDataRefresh = .now }
            isRefreshingStaticData = false
        }
    }

    /// Looks up line numbers and headsigns for trips of `feed` that have not been looked up yet.
    private func resolveTrips(in feed: TransitFeed) async {
        let known = tripSummaries[feed] ?? [:]
        let unknown = unknownTrips[feed] ?? []
        let list = feed == .bus ? busList : tramList
        let missing = Set(list.compactMap(\.tripID)).filter { known[$0] == nil && !unknown.contains($0) }
        guard !missing.isEmpty else { return }

        do {
            let found = try await staticData.tripSummaries(in: feed, for: Array(missing))
            tripSummaries[feed, default: [:]].merge(found) { _, new in new }
            unknownTrips[feed, default: []].formUnion(missing.subtracting(found.keys))
        } catch TransitDataError.notReady {
            // Not processed yet; try again on the next refresh.
        } catch {
            print("Trip lookup for \(feed) failed: \(error)")
        }
    }

    private func withTripSummary(_ vehicle: Vehicle) -> Vehicle {
        guard let tripID = vehicle.tripID, let summary = tripSummaries[vehicle.type.feed]?[tripID] else { return vehicle }
        var vehicle = vehicle
        vehicle.lineNumber = summary.lineNumber
        vehicle.headsign = summary.headsign
        return vehicle
    }

    private func applyTripSummaries() {
        busList = busList.map(withTripSummary)
        tramList = tramList.map(withTripSummary)
        withAnimation(.easeInOut) {
            updateVehicles(busList + tramList)
        }
    }

    // MARK: - Realtime positions

    private func fetchVehicles() {
        Task {
            async let buses = fetchFeed(.bus)
            async let trams = fetchFeed(.tram)
            let (newBuses, newTrams) = await (buses, trams)

            if let newBuses { busList = newBuses }
            if let newTrams { tramList = newTrams }
            await resolveTrips(in: .bus)
            await resolveTrips(in: .tram)
            applyTripSummaries()
        }
    }

    private func fetchFeed(_ feed: TransitFeed) async -> [Vehicle]? {
        do {
            let feedMessage = try await apiService.fetchRealtimeDataAsync(request: feed.vehiclePositionsURL)

            return feedMessage.entity.compactMap { entity -> Vehicle? in
                guard entity.hasVehicle else { return nil }
                let vehicleData = entity.vehicle

                guard vehicleData.hasPosition else { return nil }

                let pos = vehicleData.position
                let lat = Double(pos.latitude)
                let lon = Double(pos.longitude)

                let id = vehicleData.hasVehicle ? vehicleData.vehicle.id : entity.id

                let label = vehicleData.hasVehicle ? vehicleData.vehicle.label : "?"

                let bearing: Int? = pos.hasBearing ? Int(pos.bearing) : nil

                let trip = vehicleData.hasTrip ? vehicleData.trip : nil

                return Vehicle(
                    id: id,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    bearing: bearing,
                    label: label,
                    type: feed.vehicleType,
                    tripID: trip.flatMap { $0.hasTripID && !$0.tripID.isEmpty ? $0.tripID : nil },
                    routeID: trip.flatMap { $0.hasRouteID && !$0.routeID.isEmpty ? $0.routeID : nil },
                    currentStopSequence: vehicleData.hasCurrentStopSequence ? Int(vehicleData.currentStopSequence) : nil,
                    isStoppedAtCurrentStop: vehicleData.hasCurrentStatus && vehicleData.currentStatus == .stoppedAt
                )
            }
        } catch {
            print("Error fetching \(feed.vehiclePositionsURL.lastPathComponent): \(error)")
            return nil
        }
    }

    private func updateVehicles(_ newVehicles: [Vehicle]) {
        self.vehicles = newVehicles
    }
}
