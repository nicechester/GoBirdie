import Foundation

/// A golf course fetched from OSM and cached locally.
public struct Course: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var location: GpsPoint
    public var holes: [Hole]
    public var allGreens: [GreenPolygon]  // all OSM greens, for yardage-based resolution
    public var allTees: [GpsPoint]         // all OSM tee centers, for nearest-tee snapping
    public var downloadedAt: Date
    public var osmVersion: Int

    public init(
        id: String,
        name: String,
        location: GpsPoint,
        holes: [Hole] = [],
        allGreens: [GreenPolygon] = [],
        allTees: [GpsPoint] = [],
        downloadedAt: Date = Date(),
        osmVersion: Int = 0
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.holes = holes
        self.allGreens = allGreens
        self.allTees = allTees
        self.downloadedAt = downloadedAt
        self.osmVersion = osmVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, location, holes
        case allGreens    = "all_greens"
        case allTees      = "all_tees"
        case downloadedAt = "downloaded_at"
        case osmVersion   = "osm_version"
    }
}

/// A raw OSM green polygon with geometry for tee-line front/back computation.
public struct GreenPolygon: Codable, Sendable {
    public var center: GpsPoint
    public var polygon: [GpsPoint]  // full OSM polygon ring

    public init(center: GpsPoint, polygon: [GpsPoint]) {
        self.center = center
        self.polygon = polygon
    }

    /// Compute front and back by intersecting the tee→center line with the polygon.
    /// Front = nearest intersection to tee, Back = farthest.
    /// Falls back to center if no intersections found.
    public func frontAndBack(from tee: GpsPoint) -> (front: GpsPoint, back: GpsPoint) {
        let intersections = polygonIntersections(rayFrom: tee, through: center)
        guard intersections.count >= 2 else {
            // Fallback: nearest/farthest polygon vertex
            let sorted = polygon.sorted { tee.distanceMeters(to: $0) < tee.distanceMeters(to: $1) }
            return (front: sorted.first ?? center, back: sorted.last ?? center)
        }
        let sorted = intersections.sorted { tee.distanceMeters(to: $0) < tee.distanceMeters(to: $1) }
        return (front: sorted.first!, back: sorted.last!)
    }

    /// Find all intersection points of a ray (from→through, extended) with the polygon edges.
    private func polygonIntersections(rayFrom: GpsPoint, through: GpsPoint) -> [GpsPoint] {
        guard polygon.count >= 3 else { return [] }
        var hits: [GpsPoint] = []
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            if let pt = lineSegmentIntersection(
                p1: rayFrom, p2: through, p3: a, p4: b
            ) {
                hits.append(pt)
            }
        }
        return hits
    }

    /// Intersect the infinite line through p1→p2 with segment p3→p4.
    /// Returns the intersection point if it lies on the segment.
    private func lineSegmentIntersection(
        p1: GpsPoint, p2: GpsPoint, p3: GpsPoint, p4: GpsPoint
    ) -> GpsPoint? {
        let dx1 = p2.lon - p1.lon, dy1 = p2.lat - p1.lat
        let dx2 = p4.lon - p3.lon, dy2 = p4.lat - p3.lat
        let denom = dx1 * dy2 - dy1 * dx2
        guard abs(denom) > 1e-12 else { return nil } // parallel
        let t = ((p3.lon - p1.lon) * dy2 - (p3.lat - p1.lat) * dx2) / denom
        let u = ((p3.lon - p1.lon) * dy1 - (p3.lat - p1.lat) * dx1) / denom
        guard u >= 0 && u <= 1 else { return nil } // must be on segment
        // t can be any value (infinite line), but should be positive (forward from tee)
        guard t > 0 else { return nil }
        return GpsPoint(
            lat: p1.lat + t * dy1,
            lon: p1.lon + t * dx1
        )
    }

    /// Find the green whose center is closest to targetYards from tee position.
    public static func best(from greens: [GreenPolygon], tee: GpsPoint, targetYards: Int) -> GreenPolygon? {
        let tolerance = 5.0
        let fallbackTolerance = 20.0

        func dist(_ g: GreenPolygon) -> Double {
            tee.distanceMeters(to: g.center) * 1.09361
        }

        if let match = greens.first(where: { abs(dist($0) - Double(targetYards)) <= tolerance }) {
            return match
        }
        return greens
            .filter { abs(dist($0) - Double(targetYards)) <= fallbackTolerance }
            .min { abs(dist($0) - Double(targetYards)) < abs(dist($1) - Double(targetYards)) }
    }
}
