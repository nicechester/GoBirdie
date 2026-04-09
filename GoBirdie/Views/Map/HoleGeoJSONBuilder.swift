//
//  HoleGeoJSONBuilder.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import MapLibre
import GoBirdieCore

/// Builds GeoJSON shapes from hole geometry for MapLibre rendering.
enum HoleGeoJSONBuilder {

    /// Create a MapLibre shape source from hole geometry.
    /// Includes all fairway, bunker, water, and rough polygons as separate features.
    /// Silently skips any polygon with fewer than 3 points.
    static func makeSource(for geometry: HoleGeometry, sourceID: String) -> MLNShapeSource {
        var features: [MLNPolygonFeature] = []

        // Add fairway polygon
        if let fairway = geometry.fairway, fairway.count >= 3 {
            if let polygon = makePolygon(from: fairway, featureType: "fairway") {
                features.append(polygon)
            }
        }

        // Add rough polygon
        if let rough = geometry.rough, rough.count >= 3 {
            if let polygon = makePolygon(from: rough, featureType: "rough") {
                features.append(polygon)
            }
        }

        // Add water polygons
        for water in geometry.water {
            guard water.count >= 3 else { continue }
            if let polygon = makePolygon(from: water, featureType: "water") {
                features.append(polygon)
            }
        }

        // Add bunker polygons
        for bunker in geometry.bunkers {
            guard bunker.count >= 3 else { continue }
            if let polygon = makePolygon(from: bunker, featureType: "bunker") {
                features.append(polygon)
            }
        }

        // Create collection and return source
        let collection = MLNShapeCollectionFeature(shapes: features)
        return MLNShapeSource(identifier: sourceID, shape: collection, options: nil)
    }

    // MARK: - Private

    /// Convert a polygon of GpsPoints to an MLNPolygonFeature with a featureType attribute.
    private static func makePolygon(
        from polygon: [GpsPoint],
        featureType: String
    ) -> MLNPolygonFeature? {
        let coordinates = polygon.map { gpsPoint -> CLLocationCoordinate2D in
            CLLocationCoordinate2D(latitude: gpsPoint.lat, longitude: gpsPoint.lon)
        }

        let feature = MLNPolygonFeature(coordinates: coordinates, count: UInt(coordinates.count))
        feature.attributes = ["featureType": featureType]
        return feature
    }
}
