//
//  VehicleClusterModel.swift
//  Zipka
//

import Foundation
import MapKit
import SwiftUI
import Observation
import ClusterMap

/// Decides which vehicles the map shows individually and which it groups into clusters.
///
/// While the camera is moving the map reclusters only once per `movingInterval`, since every
/// recluster rebuilds the markers on screen. When the gesture ends, or the vehicles change,
/// it reclusters straight away. Only one recluster runs at a time; requests that arrive
/// meanwhile are merged into the next one.
@Observable
final class VehicleClusterModel {
    private(set) var vehicles: [Vehicle] = []
    private(set) var clusters: [ClusterManager<Vehicle>.ClusterAnnotation] = []

    @ObservationIgnored private let manager = ClusterManager<Vehicle>(
        configuration: .init(maxZoomLevel: 12, shouldDistributeAnnotationsOnSameCoordinate: false)
    )
    @ObservationIgnored private var allVehicles: [Vehicle] = []
    @ObservationIgnored private var region: MKCoordinateRegion
    @ObservationIgnored private var mapSize: CGSize = .zero

    /// The vehicles changed since the last recluster, so the cluster tree has to be rebuilt.
    /// Camera moves alone only re-run clustering on the existing tree.
    @ObservationIgnored private var needsTreeRebuild = false
    /// When the next recluster is due, or `nil` when none is planned.
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let clock = ContinuousClock()

    /// How often to recluster while the map is being panned or zoomed.
    private let movingInterval: Duration = .seconds(1)

    init(region: MKCoordinateRegion) {
        self.region = region
    }

    func setVehicles(_ vehicles: [Vehicle]) {
        allVehicles = vehicles
        needsTreeRebuild = true
        requestReload(in: .zero)
    }

    /// Call on every camera change during a gesture.
    func cameraMoved(to region: MKCoordinateRegion) {
        self.region = region
        requestReload(in: movingInterval)
    }

    /// Call once the gesture has ended.
    func cameraSettled(at region: MKCoordinateRegion) {
        self.region = region
        requestReload(in: .zero)
    }

    func setMapSize(_ size: CGSize) {
        mapSize = size
        requestReload(in: .zero)
    }

    private func requestReload(in delay: Duration) {
        let due = clock.now + delay
        // A recluster that is planned sooner will pick up this change too.
        if let deadline, deadline <= due { return }
        deadline = due
        // A running recluster checks the deadline again when it finishes.
        guard !isReloading else { return }
        // Restart the wait, since the new deadline is earlier.
        loop?.cancel()
        loop = Task { await runPendingReloads() }
    }

    private func runPendingReloads() async {
        while let deadline {
            let wait = deadline - clock.now
            if wait > .zero {
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    return // Replaced by a loop with an earlier deadline.
                }
            }
            self.deadline = nil
            isReloading = true
            await reload()
            isReloading = false
        }
    }

    private func reload() async {
        guard mapSize.width > 0, mapSize.height > 0 else { return }

        let annotations: [ClusterManager<Vehicle>.AnnotationType]
        if needsTreeRebuild {
            needsTreeRebuild = false
            annotations = await manager.replaceAndReload(with: allVehicles, mapViewSize: mapSize, coordinateRegion: region)
        } else {
            annotations = await manager.reloadVisible(mapViewSize: mapSize, coordinateRegion: region)
        }

        var newVehicles: [Vehicle] = []
        var newClusters: [ClusterManager<Vehicle>.ClusterAnnotation] = []
        for annotation in annotations {
            switch annotation {
            case .annotation(let vehicle): newVehicles.append(vehicle)
            case .cluster(let cluster): newClusters.append(cluster)
            }
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            vehicles = newVehicles
            clusters = newClusters
        }
    }
}
