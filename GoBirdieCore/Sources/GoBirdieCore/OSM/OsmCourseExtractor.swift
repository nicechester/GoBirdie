import Foundation

/// Builds one course from a plain osm-golf-courses region file (GeoJSON).
/// Same rules as the Overpass path and the Android extractor: holes by `ref` (closest tee to the anchor wins),
/// green snapped within 50 m, fairway and bunkers within 700 m of both tee and green.
enum OsmCourseExtractor {
    private static let golfKinds: Set<String> = ["hole", "green", "fairway", "bunker"]
    private static let pad = 0.002  // degrees of margin around the outline

    /// The course outline is the feature with `osmId`. Its holes, greens, fairways and bunkers are the golf
    /// features that start inside the outline. Returns nil when the outline or its holes aren't in this file.
    static func extract(from file: URL, osmId: String, name: String, anchor: GpsPoint) throws -> Course? {
        // Pass 1: the outline. The raw bytes are checked for the ID before any JSON parsing.
        let idNeedle = Data("\"\(osmId)\"".utf8)
        var outline: [GpsPoint] = []
        var outlineName: String?
        try forEachFeatureBytes(in: file) { bytes in
            guard bytes.range(of: idNeedle) != nil,
                  let feature = parseFeature(bytes),
                  feature["id"] as? String == osmId,
                  let ring = rings(of: feature).first, ring.count >= 3
            else { return true }
            outline = ring
            outlineName = properties(of: feature)["name"] as? String
            return false
        }
        guard outline.count >= 3 else { return nil }

        // Pass 2: golf features that start inside the outline (plus a small margin).
        let minLat = (outline.map(\.lat).min() ?? 0) - pad
        let maxLat = (outline.map(\.lat).max() ?? 0) + pad
        let minLon = (outline.map(\.lon).min() ?? 0) - pad
        let maxLon = (outline.map(\.lon).max() ?? 0) + pad

        var holeLines: [(props: [String: Any], points: [GpsPoint])] = []
        var greens: [[GpsPoint]] = []
        var fairways: [[GpsPoint]] = []
        var bunkers: [[GpsPoint]] = []
        let golfNeedle = Data("\"golf\"".utf8)

        try forEachFeatureBytes(in: file) { bytes in
            guard bytes.range(of: golfNeedle) != nil,
                  let feature = parseFeature(bytes) else { return true }
            let props = properties(of: feature)
            guard let golf = props["golf"] as? String, golfKinds.contains(golf) else { return true }
            let parts = rings(of: feature)
            guard let first = parts.first?.first,
                  (minLat...maxLat).contains(first.lat),
                  (minLon...maxLon).contains(first.lon) else { return true }

            switch golf {
            case "hole":
                if let line = parts.first, line.count >= 2 {
                    holeLines.append((props: props, points: line))
                }
            case "green":
                greens += parts.filter { $0.count >= 3 }
            case "fairway":
                fairways += parts.filter { $0.count >= 3 }
            default:
                bunkers += parts.filter { $0.count >= 3 }
            }
            return true
        }

        let holes = buildHoles(holeLines, greens: greens, fairways: fairways, bunkers: bunkers, anchor: anchor)
        guard !holes.isEmpty else { return nil }
        return Course(
            id: "osm-\(osmId)",
            name: outlineName ?? name,
            location: centroid(outline),
            holes: holes,
            downloadedAt: Date(),
            osmVersion: 1
        )
    }

    // MARK: - Hole building

    private static func buildHoles(
        _ lines: [(props: [String: Any], points: [GpsPoint])],
        greens: [[GpsPoint]],
        fairways: [[GpsPoint]],
        bunkers: [[GpsPoint]],
        anchor: GpsPoint
    ) -> [Hole] {
        // One line per hole number: keep the way whose tee is closest to the anchor.
        var byRef: [Int: (props: [String: Any], points: [GpsPoint])] = [:]
        for line in lines {
            guard let ref = intValue(line.props["ref"]) else { continue }
            if let existing = byRef[ref],
               line.points[0].distanceMeters(to: anchor) >= existing.points[0].distanceMeters(to: anchor) {
                continue
            }
            byRef[ref] = line
        }

        var holes: [Hole] = []
        for (number, line) in byRef {
            let tee = line.points[0]
            let greenCenter = line.points[line.points.count - 1]
            let par = intValue(line.props["par"]) ?? 4
            let handicap = intValue(line.props["handicap"])

            let green = greens
                .filter { centroid($0).distanceMeters(to: greenCenter) < 50 }
                .min { centroid($0).distanceMeters(to: greenCenter) < centroid($1).distanceMeters(to: greenCenter) }
            var front: GpsPoint?
            var back: GpsPoint?
            if let green {
                let avgLon = green.map(\.lon).reduce(0, +) / Double(green.count)
                front = GpsPoint(lat: green.map(\.lat).min() ?? greenCenter.lat, lon: avgLon)
                back = GpsPoint(lat: green.map(\.lat).max() ?? greenCenter.lat, lon: avgLon)
            }

            let nearHole: ([GpsPoint]) -> Bool = { polygon in
                let c = centroid(polygon)
                return c.distanceMeters(to: tee) < 700 && c.distanceMeters(to: greenCenter) < 700
            }
            holes.append(Hole(
                number: number,
                par: par,
                handicap: handicap,
                tee: tee,
                greenCenter: greenCenter,
                greenFront: front,
                greenBack: back,
                geometry: HoleGeometry(
                    fairway: fairways.first(where: nearHole),
                    bunkers: bunkers.filter(nearHole)
                )
            ))
        }
        return holes.sorted { $0.number < $1.number }
    }

    // MARK: - Streaming read

    /// Visits each feature of the FeatureCollection, reading the file in chunks. `visit` returns false to stop.
    /// A feature object opens at depth 3: the FeatureCollection `{`, its `features` `[`, then the feature `{`.
    private static func forEachFeatureBytes(in file: URL, _ visit: (Data) throws -> Bool) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var depth = 0
        var inString = false
        var escaped = false
        var collecting = false
        var feature = Data()

        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            for byte in chunk {
                if inString {
                    if collecting { feature.append(byte) }
                    if escaped {
                        escaped = false
                    } else if byte == 0x5C {       // backslash
                        escaped = true
                    } else if byte == 0x22 {       // quote ends the string
                        inString = false
                    }
                    continue
                }
                switch byte {
                case 0x22:                         // quote starts a string
                    inString = true
                    if collecting { feature.append(byte) }
                case 0x7B, 0x5B:                   // { [
                    depth += 1
                    if byte == 0x7B && depth == 3 {
                        collecting = true
                        feature.removeAll(keepingCapacity: true)
                    }
                    if collecting { feature.append(byte) }
                case 0x7D, 0x5D:                   // } ]
                    if collecting { feature.append(byte) }
                    depth -= 1
                    if byte == 0x7D && depth == 2 && collecting {
                        collecting = false
                        guard try visit(feature) else { return }
                    }
                default:
                    if collecting { feature.append(byte) }
                }
            }
        }
    }

    // MARK: - JSON helpers

    private static func parseFeature(_ bytes: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }

    private static func properties(of feature: [String: Any]) -> [String: Any] {
        feature["properties"] as? [String: Any] ?? [:]
    }

    /// The feature's geometry as rings: a LineString is one ring; a polygon contributes its outer ring.
    private static func rings(of feature: [String: Any]) -> [[GpsPoint]] {
        guard let geometry = feature["geometry"] as? [String: Any],
              let type = geometry["type"] as? String,
              let coords = geometry["coordinates"] as? [Any] else { return [] }
        switch type {
        case "LineString":
            return [points(coords)]
        case "Polygon":
            guard let outer = coords.first as? [Any] else { return [] }
            return [points(outer)]
        case "MultiPolygon":
            return coords.compactMap { poly -> [GpsPoint]? in
                guard let polyRings = poly as? [Any], let outer = polyRings.first as? [Any] else { return nil }
                return points(outer)
            }
        default:
            return []
        }
    }

    private static func points(_ ring: [Any]) -> [GpsPoint] {
        ring.compactMap { position -> GpsPoint? in
            guard let c = position as? [Any], c.count >= 2,
                  let lon = number(c[0]), let lat = number(c[1]) else { return nil }
            return GpsPoint(lat: lat, lon: lon)
        }
    }

    private static func number(_ value: Any) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// Hole numbers and par can be JSON strings ("1") or numbers.
    private static func intValue(_ value: Any?) -> Int? {
        if let text = value as? String { return Int(text) }
        return (value as? NSNumber)?.intValue
    }

    private static func centroid(_ points: [GpsPoint]) -> GpsPoint {
        GpsPoint(
            lat: points.map(\.lat).reduce(0, +) / Double(points.count),
            lon: points.map(\.lon).reduce(0, +) / Double(points.count)
        )
    }
}
