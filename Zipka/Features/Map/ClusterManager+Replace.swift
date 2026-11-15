//
//  ClusterManager+Replace.swift
//  Zipka
//

import MapKit
import ClusterMap

extension ClusterManager {
    /// Replaces all annotations, reclusters, and returns the visible result in a single
    /// actor-isolated call, so overlapping reloads can't interleave their remove/add steps.
    func replaceAndReload(
        with annotations: [Annotation],
        mapViewSize: CGSize,
        coordinateRegion: MKCoordinateRegion
    ) async -> [AnnotationType] {
        removeAll()
        add(annotations)
        await reload(mapViewSize: mapViewSize, coordinateRegion: coordinateRegion)
        return visibleAnnotations
    }
}
