import Foundation

/// Builds the courses for one OSM outline from a plain osm-golf-courses region file (GeoJSON).
/// Same rules as the Overpass path and the Android extractor: holes by `ref` (closest tee to the anchor wins
/// within a layout), green snapped within 50 m, fairway and bunkers within 700 m of both tee and green.
enum OsmCourseExtractor {
    private static let golfKinds: Set<String> = ["hole", "green", "fairway", "bunker"]
    /// Degrees (about 660 m) a hole may start outside the outline's bounds. Larger values pull in nearby courses.
    private static let margin = 0.006

    /// The course outline is the feature with `osmId`. Its holes are the golf features within `margin` of the
    /// outline's bounds, so holes mapped just outside the club polygon are kept. A hole is kept only if it belongs
    /// to this outline: its tee is inside the outline's polygon, or nearest to its centroid among nearby outlines.
    /// This keeps neighboring courses whose bounds overlap (Torrey Pines North/South) out. Hole lines are split into
    /// layouts (a multi-course complex gives one course per layout). Returns an empty list when the outline or
    /// its holes aren't in this file.
    static func extract(from file: URL, osmId: String, name: String, anchor: GpsPoint) throws -> [Course] {
        // Pass 1: the outline, as all of its polygons. The raw bytes are checked for the ID before any JSON parsing.
        let idNeedle = Data("\"\(osmId)\"".utf8)
        var outlineRings: [[GpsPoint]] = []
        var outlineName: String?
        try forEachFeatureBytes(in: file) { bytes in
            guard bytes.range(of: idNeedle) != nil,
                  let feature = parseFeature(bytes),
                  feature["id"] as? String == osmId
            else { return true }
            outlineRings = rings(of: feature).filter { $0.count >= 3 }
            outlineName = properties(of: feature)["name"] as? String
            return false
        }
        let outlinePoints = outlineRings.flatMap { $0 }
        guard !outlinePoints.isEmpty else { return [] }

        // Pass 2: golf features that start within `margin` of the outline's bounds.
        let minLat = (outlinePoints.map(\.lat).min() ?? 0) - margin
        let maxLat = (outlinePoints.map(\.lat).max() ?? 0) + margin
        let minLon = (outlinePoints.map(\.lon).min() ?? 0) - margin
        let maxLon = (outlinePoints.map(\.lon).max() ?? 0) + margin

        var holeLines: [HoleLine] = []
        var greens: [[GpsPoint]] = []
        var fairways: [[GpsPoint]] = []
        var bunkers: [[GpsPoint]] = []
        // The requested outline plus any other course outline near it, so each hole can be matched to its own outline.
        var courseOutlines = [CourseOutline(id: osmId, rings: outlineRings)]
        let golfNeedle = Data("\"golf\"".utf8)
        let courseNeedle = Data("\"golf_course\"".utf8)
        let inBox: (GpsPoint) -> Bool = { (minLat...maxLat).contains($0.lat) && (minLon...maxLon).contains($0.lon) }

        try forEachFeatureBytes(in: file) { bytes in
            let mayBeHole = bytes.range(of: golfNeedle) != nil
            let mayBeOutline = bytes.range(of: courseNeedle) != nil
            guard mayBeHole || mayBeOutline, let feature = parseFeature(bytes) else { return true }
            let props = properties(of: feature)

            if props["leisure"] as? String == "golf_course" {
                // Only areas count as outlines, as in fetch_course.sh. A LineString trace of the club
                // boundary (same name, no polygon) would otherwise claim the holes inside it.
                let id = feature["id"] as? String ?? ""
                let geometryType = (feature["geometry"] as? [String: Any])?["type"] as? String
                let isArea = geometryType == "Polygon" || geometryType == "MultiPolygon"
                let outline = rings(of: feature).filter { $0.count >= 3 }
                if isArea, id != osmId, outline.joined().contains(where: inBox) {
                    courseOutlines.append(CourseOutline(id: id, rings: outline))
                }
                return true
            }

            guard mayBeHole, let golf = props["golf"] as? String, golfKinds.contains(golf) else { return true }
            let parts = rings(of: feature)
            // Same as the script's in_bounds: any coordinate of the feature in the box, not just its start.
            guard parts.joined().contains(where: inBox) else { return true }

            switch golf {
            case "hole":
                if let line = parts.first, line.count >= 2 {
                    holeLines.append(HoleLine(id: feature["id"] as? String ?? "", props: props, points: line))
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

        // Keep only the holes whose start point belongs to this outline (see owningOutlineId).
        holeLines = holeLines.filter { owningOutlineId(for: $0.points[0], in: courseOutlines) == osmId }

        // Layouts of a complex, in order of preference:
        // 1. The golf:course:name tag on each hole (e.g. "C.W. Koiner Course").
        // 2. The text before the number in each ref (e.g. "Creek 1", "Oaks 1"): one layout per prefix.
        // 3. One layout per duplicate hole ref, split by way-ID gap.
        let tagged = !holeLines.isEmpty && holeLines.allSatisfy { ($0.props["golf:course:name"] as? String) != nil }
        let prefixed = tagged ? [] : groupByRefPrefix(holeLines)
        let layouts: [(name: String?, lines: [HoleLine])]
        if tagged {
            var order: [String] = []
            var byName: [String: [HoleLine]] = [:]
            for line in holeLines {
                let layoutName = line.props["golf:course:name"] as? String ?? ""
                if byName[layoutName] == nil { order.append(layoutName) }
                byName[layoutName, default: []].append(line)
            }
            layouts = order.map { key -> (name: String?, lines: [HoleLine]) in (name: key, lines: byName[key] ?? []) }
        } else if prefixed.count > 1 {
            layouts = prefixed.map { group -> (name: String?, lines: [HoleLine]) in (name: group.name, lines: group.lines) }
        } else {
            let layoutCount = Dictionary(grouping: holeLines.compactMap { holeNumber($0.props["ref"]) }, by: { $0 })
                .values.map(\.count).max() ?? 1
            layouts = splitByWayGap(holeLines, layouts: layoutCount).map { group -> (name: String?, lines: [HoleLine]) in
                (name: nil, lines: group)
            }
        }

        let courseName = outlineName ?? name
        let center = centroid(outlinePoints)
        let multi = layouts.count > 1

        return layouts.enumerated().compactMap { idx, layout in
            let holes = buildHoles(layout.lines, greens: greens, fairways: fairways, bunkers: bunkers, anchor: anchor)
            guard !holes.isEmpty else { return nil }
            let layoutName = layout.name
            return Course(
                id: multi ? "osm-\(osmId)-\(idx + 1)" : "osm-\(osmId)",
                // "Club – Layout", e.g. "Brookside Golf Club – C.W. Koiner Course"
                name: !multi ? courseName
                    : (layoutName.map { "\(courseName) – \($0)" } ?? "\(courseName) #\(idx + 1)"),
                location: center,
                holes: holes,
                downloadedAt: Date(),
                osmVersion: 1
            )
        }
    }

    // MARK: - Layouts and hole building

    /// A course outline (leisure=golf_course) near the requested one, used to decide which outline a hole belongs to.
    private struct CourseOutline {
        let id: String
        let rings: [[GpsPoint]]
    }

    private struct HoleLine {
        let id: String
        let props: [String: Any]
        let points: [GpsPoint]
    }

    /// Splits hole lines into `layouts` groups at the largest gaps in OSM way IDs, as the Overpass path does.
    private static func splitByWayGap(_ lines: [HoleLine], layouts: Int) -> [[HoleLine]] {
        guard layouts > 1, lines.count > 1 else { return [lines] }
        let ordered = lines.sorted { wayNumber($0.id) < wayNumber($1.id) }
        let cuts = (1..<ordered.count)
            .map { i in (index: i, gap: wayNumber(ordered[i].id) - wayNumber(ordered[i - 1].id)) }
            .sorted { $0.gap > $1.gap }
            .prefix(layouts - 1)
            .map(\.index)
            .sorted()
        var groups: [[HoleLine]] = []
        var start = 0
        for cut in cuts {
            groups.append(Array(ordered[start..<cut]))
            start = cut
        }
        groups.append(Array(ordered[start...]))
        return groups
    }

    /// The number in an OSM id, e.g. "w1116223984" -> 1116223984.
    private static func wayNumber(_ id: String) -> Int64 {
        Int64(id.filter(\.isNumber)) ?? 0
    }

    private static func buildHoles(
        _ lines: [HoleLine],
        greens: [[GpsPoint]],
        fairways: [[GpsPoint]],
        bunkers: [[GpsPoint]],
        anchor: GpsPoint
    ) -> [Hole] {
        // One line per hole number within a layout: keep the way whose tee is closest to the anchor.
        var byRef: [Int: HoleLine] = [:]
        for line in lines {
            guard let ref = holeNumber(line.props["ref"]) else { continue }
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

    /// The hole number in a ref: "4" -> 4, "Creek 1" -> 1.
    private static func holeNumber(_ value: Any?) -> Int? {
        guard let text = value as? String else { return (value as? NSNumber)?.intValue }
        if let number = Int(text) { return number }
        guard let range = text.range(of: #"\d+$"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    /// The text before the hole number in a ref: "Creek 1" -> "Creek", "4" -> "".
    private static func refPrefix(_ value: Any?) -> String {
        guard let text = value as? String else { return "" }
        return text.replacingOccurrences(of: #"\s*\d+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Groups holes by the prefix of their ref. Holes without a prefix are left out.
    private static func groupByRefPrefix(_ lines: [HoleLine]) -> [(name: String, lines: [HoleLine])] {
        var order: [String] = []
        var byPrefix: [String: [HoleLine]] = [:]
        for line in lines {
            let prefix = refPrefix(line.props["ref"])
            guard !prefix.isEmpty else { continue }
            if byPrefix[prefix] == nil { order.append(prefix) }
            byPrefix[prefix, default: []].append(line)
        }
        return order.map { (name: $0, lines: byPrefix[$0] ?? []) }
    }

    /// The outline a hole belongs to: the outline whose polygon contains the tee, otherwise the nearest outline centroid.
    /// Matches fetch_course.sh: the nearest centroid is measured in degrees (lon, lat), not meters.
    private static func owningOutlineId(for point: GpsPoint, in outlines: [CourseOutline]) -> String? {
        if let inside = outlines.first(where: { outline in outline.rings.contains { pointInPolygon(point, $0) } }) {
            return inside.id
        }
        return outlines.min { a, b in
            degreeDistance(centroid(a.rings.flatMap { $0 }), point) < degreeDistance(centroid(b.rings.flatMap { $0 }), point)
        }?.id
    }

    /// Straight-line distance in degrees, as the script's dist() computes it.
    private static func degreeDistance(_ a: GpsPoint, _ b: GpsPoint) -> Double {
        hypot(a.lon - b.lon, a.lat - b.lat)
    }

    /// Ray casting. Points are treated as (lat, lon) pairs.
    private static func pointInPolygon(_ point: GpsPoint, _ ring: [GpsPoint]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i]
            let b = ring[j]
            if (a.lat > point.lat) != (b.lat > point.lat),
               point.lon < (b.lon - a.lon) * (point.lat - a.lat) / (b.lat - a.lat) + a.lon {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static func centroid(_ points: [GpsPoint]) -> GpsPoint {
        GpsPoint(
            lat: points.map(\.lat).reduce(0, +) / Double(points.count),
            lon: points.map(\.lon).reduce(0, +) / Double(points.count)
        )
    }
}
