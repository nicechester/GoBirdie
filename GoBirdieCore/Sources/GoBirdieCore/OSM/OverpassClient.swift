import Foundation

/// Shared rate limiter for Overpass API — persists last request time across OverpassClient instances.
final class OverpassRateLimiter: @unchecked Sendable {
    static let shared = OverpassRateLimiter()
    private let lock = NSLock()
    private var lastRequestTime: Date = .distantPast
    private let minInterval: TimeInterval = 2.1

    private init() {}

    /// Waits if needed to enforce minimum interval, then records the current time.
    func waitIfNeeded() async throws {
        let delay: TimeInterval = lock.withLock {
            let elapsed = Date().timeIntervalSince(lastRequestTime)
            let wait = max(0, minInterval - elapsed)
            if wait > 0 {
                // Reserve the slot now so concurrent callers don't both think they can go
                lastRequestTime = Date().addingTimeInterval(wait)
            } else {
                lastRequestTime = Date()
            }
            return wait
        }
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

/// Queries the Overpass API to search for and download golf course geometry.
public actor OverpassClient {

    private let baseURL = URL(string: "https://overpass-api.de/api/interpreter")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Course Search

    /// Search for golf courses near a location within a given radius.
    /// - Parameters:
    ///   - location: Center point for search
    ///   - radius: Search radius in meters
    /// - Returns: Array of nearby courses, up to 20 results
    public func searchCourses(location: GpsPoint, radius: Int) async throws -> [CourseSearchResult] {
        let latDelta = Double(radius) / 111_000.0  // meters to degrees (roughly 111km per degree)
        let lonDelta = Double(radius) / (111_000.0 * cos(location.lat * .pi / 180))

        let bbox = (
            south: location.lat - latDelta,
            west: location.lon - lonDelta,
            north: location.lat + latDelta,
            east: location.lon + lonDelta
        )

        let query = """
[out:json][bbox:\(bbox.south),\(bbox.west),\(bbox.north),\(bbox.east)];
(
  node["leisure"="golf_course"];
  way["leisure"="golf_course"];
  relation["leisure"="golf_course"];
);
out center;
"""

        let data = try await post(query: query)
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

        return response.elements
            .compactMap { element -> CourseSearchResult? in
                guard let name = element.tags?["name"] else { return nil }
                let courseLoc = element.center ?? element.geometry?.first ?? GpsPoint(lat: element.lat ?? 0, lon: element.lon ?? 0)
                return CourseSearchResult(
                    id: "osm-\(element.id)",
                    name: name,
                    location: courseLoc,
                    osmType: element.type,
                    osmId: element.id
                )
            }
            .sorted { a, b in
                a.location.distanceMeters(to: location) < b.location.distanceMeters(to: location)
            }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Course Download

    /// Download full hole geometry for an OSM relation.
    /// - Parameters:
    ///   - osmRelationId: OSM relation ID
    ///   - name: Course name
    ///   - targetYardages: Per-hole yardages from GolfCourseAPI to guide green selection. Key = hole number.
    public func downloadCourse(osmRelationId: Int64, name: String,
                               targetYardages: [Int: Int] = [:]) async throws -> Course {
        // Query relation to get bounding box
        let relationQuery = """
[out:json];
relation(\(osmRelationId));
out geom;
"""

        let relationData = try await post(query: relationQuery)
        let relationResponse = try JSONDecoder().decode(OverpassResponse.self, from: relationData)

        guard let relation = relationResponse.elements.first(where: { $0.type == "relation" }) else {
            throw OverpassError.courseNotFound
        }

        // Use bounds directly from the relation — geometry is on members, not the relation itself
        guard let bounds = relation.bounds else { throw OverpassError.invalidGeometry }
        let (minLat, maxLat) = (bounds.minlat, bounds.maxlat)
        let (minLon, maxLon) = (bounds.minlon, bounds.maxlon)

        // Query all golf-related ways within bounding box
        let geometryQuery = """
[out:json][bbox:\(minLat - 0.01),\(minLon - 0.01),\(maxLat + 0.01),\(maxLon + 0.01)];
(
  way["golf"~"fairway|green|bunker|tee|rough"];
  node["golf"="tee"];
  node["golf"="pin"];
);
out geom;
"""

        let geometryData = try await post(query: geometryQuery)
        let geometryResponse = try JSONDecoder().decode(OverpassResponse.self, from: geometryData)

        // Parse and group by hole number
        let courseLocation = GpsPoint(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2)
        let holes = buildHoles(from: geometryResponse.elements, targetYardages: targetYardages)

        // Store all raw greens using bounds for front/center/back — matches notebook logic
        let allGreens: [GreenPolygon] = geometryResponse.elements
            .filter { $0.tags?["golf"] == "green" }
            .compactMap { e -> GreenPolygon? in
                guard let geom = e.geometry, geom.count >= 3 else { return nil }
                let centerLat = geom.map { $0.lat }.reduce(0, +) / Double(geom.count)
                let centerLon = geom.map { $0.lon }.reduce(0, +) / Double(geom.count)
                return GreenPolygon(
                    center: GpsPoint(lat: centerLat, lon: centerLon),
                    polygon: geom
                )
            }
        print("[OSM] Stored \(allGreens.count) raw greens for yardage resolution")

        let allTees: [GpsPoint] = geometryResponse.elements
            .filter { $0.tags?["golf"] == "tee" }
            .compactMap { e -> GpsPoint? in
                if let geom = e.geometry, !geom.isEmpty {
                    return centroid(of: geom)
                }
                if let c = e.center { return c }
                if let lat = e.lat, let lon = e.lon { return GpsPoint(lat: lat, lon: lon) }
                return nil
            }
        print("[OSM] Stored \(allTees.count) raw tees for nearest-tee snapping")

        let course = Course(
            id: "osm-\(osmRelationId)",
            name: name,
            location: courseLocation,
            holes: holes,
            allGreens: allGreens,
            allTees: allTees,
            downloadedAt: Date(),
            osmVersion: relation.version ?? 1
        )

        return course
    }

    // MARK: - Private

    private func post(query: String, retries: Int = 3) async throws -> Data {
        // Check disk cache first
        if let cached = await OverpassCache.shared.get(query: query) {
            return cached
        }

        try await OverpassRateLimiter.shared.waitIfNeeded()
        print("[Overpass] POST query:\n\(query)")

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw OverpassError.invalidQuery
        }
        request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OverpassError.invalidResponse
        }

        print("[Overpass] HTTP \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            await OverpassCache.shared.set(query: query, data: data)
            return data
        case 429, 504, 502, 503:
            let body = String(data: data, encoding: .utf8)?.prefix(100) ?? ""
            print("[Overpass] HTTP \(httpResponse.statusCode) — retries left: \(retries). Body: \(body)")
            guard retries > 0 else {
                throw httpResponse.statusCode == 429 ? OverpassError.rateLimited : OverpassError.serverError
            }
            // Exponential backoff: 3s, 6s, 12s
            let backoff = 3.0 * pow(2.0, Double(3 - retries))
            print("[Overpass] Backing off \(backoff)s before retry")
            try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            return try await post(query: query, retries: retries - 1)
        case 400...499:
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            print("[Overpass] HTTP \(httpResponse.statusCode) invalid query. Body: \(body)")
            throw OverpassError.invalidQuery
        default:
            print("[Overpass] HTTP \(httpResponse.statusCode) unexpected")
            throw OverpassError.httpError(httpResponse.statusCode)
        }
    }

    private func buildHoles(from elements: [OverpassElement], targetYardages: [Int: Int] = [:]) -> [Hole] {
        // Separate elements by type
        var teePolygons:    [[GpsPoint]] = []
        var greenPolygons:  [[GpsPoint]] = []
        var fairwayPolygons:[[GpsPoint]] = []
        var bunkerPolygons: [[GpsPoint]] = []
        var waterPolygons:  [[GpsPoint]] = []
        var roughPolygons:  [[GpsPoint]] = []

        for element in elements {
            guard let geom = element.geometry, !geom.isEmpty else { continue }
            switch element.tags?["golf"] {
            case "tee":     teePolygons.append(geom)
            case "green":   greenPolygons.append(geom)
            case "fairway": fairwayPolygons.append(geom)
            case "bunker":  bunkerPolygons.append(geom)
            case "rough":   roughPolygons.append(geom)
            default:
                if element.tags?["natural"] == "water" || element.tags?["water"] != nil {
                    waterPolygons.append(geom)
                }
            }
        }

        // First try ref-based grouping
        var holesByRef: [Int: [OverpassElement]] = [:]
        for element in elements {
            if let num = extractHoleNumber(from: element) {
                holesByRef[num, default: []].append(element)
            }
        }
        let hasRefTags = !holesByRef.isEmpty

        if hasRefTags {
            var holes: [Hole] = []
            for holeNum in 1...18 {
                holes.append(buildHole(number: holeNum, elements: holesByRef[holeNum] ?? []))
            }
            return holes
        }

        // No ref tags — spatially match each tee to its nearest green
        // Deduplicate tees: cluster tees within 30m of each other into one
        let teeCentroids = teePolygons.map { centroid(of: $0) }
        var usedTees = Set<Int>()
        var uniqueTees: [GpsPoint] = []
        for (i, tee) in teeCentroids.enumerated() {
            if usedTees.contains(i) { continue }
            usedTees.insert(i)
            // Merge nearby tees (same hole, multiple tee boxes)
            for (j, other) in teeCentroids.enumerated() where j > i {
                if tee.distanceMeters(to: other) < 50 { usedTees.insert(j) }
            }
            uniqueTees.append(tee)
        }

        // Match each tee to its green using yardage guidance when available,
        // otherwise fall back to nearest-green spatial matching
        let greenCentroids = greenPolygons.map { centroid(of: $0) }
        var usedGreens = Set<Int>()
        var matchedPairs: [(tee: GpsPoint, greenIdx: Int, holeNum: Int)] = []

        // Sort unique tees by lat for consistent hole numbering
        let sortedTees = uniqueTees.sorted { $0.lat < $1.lat }

        for (holeIdx, tee) in sortedTees.enumerated() {
            let holeNum = holeIdx + 1
            let targetYards = targetYardages[holeNum]

            var bestIdx = -1
            var bestScore = Double.infinity

            for (gi, green) in greenCentroids.enumerated() {
                if usedGreens.contains(gi) { continue }
                let distYards = tee.distanceMeters(to: green) * 1.09361

                // Must be a plausible golf hole distance
                guard distYards >= 45 && distYards <= 700 else { continue }

                let score: Double
                if let target = targetYards {
                    // Yardage-guided: score = difference from target yardage
                    score = abs(distYards - Double(target))
                } else {
                    // Fallback: nearest green
                    score = distYards
                }

                if score < bestScore {
                    bestScore = score
                    bestIdx = gi
                }
            }

            if bestIdx >= 0 {
                usedGreens.insert(bestIdx)
                matchedPairs.append((tee: tee, greenIdx: bestIdx, holeNum: holeNum))
                if let target = targetYards {
                    let actual = Int(greenCentroids[bestIdx].distanceMeters(to: tee) * 1.09361)
                    print("[OSM] Hole \(holeNum): target=\(target)y actual=\(actual)y diff=\(abs(actual-target))y")
                }
            }
        }

        var holes: [Hole] = []
        for pair in matchedPairs.prefix(18) {
            let greenGeom = greenPolygons[pair.greenIdx]
            let lats = greenGeom.map { $0.lat }
            let lons = greenGeom.map { $0.lon }
            let greenCenter = centroid(of: greenGeom)
            let greenFront  = GpsPoint(lat: lats.min()!, lon: lons.reduce(0,+)/Double(lons.count))
            let greenBack   = GpsPoint(lat: lats.max()!, lon: lons.reduce(0,+)/Double(lons.count))

            // Find fairways/bunkers near this hole's tee-green corridor
            let tee = pair.tee
            let holeFairways = fairwayPolygons.filter { poly in
                let c = centroid(of: poly)
                return c.distanceMeters(to: tee) < 700 && c.distanceMeters(to: greenCenter) < 700
            }
            let holeBunkers = bunkerPolygons.filter { poly in
                let c = centroid(of: poly)
                return c.distanceMeters(to: tee) < 700 && c.distanceMeters(to: greenCenter) < 700
            }

            let geometry = HoleGeometry(
                fairway: holeFairways.first,
                bunkers: holeBunkers,
                water: [],
                rough: nil
            )

            holes.append(Hole(
                id: UUID(),
                number: pair.holeNum,
                par: inferPar(from: pair.holeNum),
                handicap: nil,
                tee: tee,
                greenCenter: greenCenter,
                greenFront: greenFront,
                greenBack: greenBack,
                geometry: geometry
            ))
        }

        // Fill remaining holes up to 18 with empty placeholders
        if holes.count < 18 {
            for holeNum in (holes.count + 1)...18 {
                holes.append(Hole(
                    id: UUID(), number: holeNum, par: inferPar(from: holeNum),
                    handicap: nil, tee: nil, greenCenter: nil, greenFront: nil, greenBack: nil, geometry: nil
                ))
            }
        }

        return holes
    }

    private func buildHole(number: Int, elements: [OverpassElement]) -> Hole {
        var teePoint: GpsPoint?
        var greenPoints: [GpsPoint] = []
        var fairwayPoints: [GpsPoint] = []
        var bunkerPolygons: [[GpsPoint]] = []
        var waterPolygons: [[GpsPoint]] = []
        var roughPoints: [GpsPoint] = []

        for element in elements {
            if element.tags?["golf"] == "tee", let node = element.geometry?.first {
                teePoint = node
            } else if element.tags?["golf"] == "green", let geometry = element.geometry, !geometry.isEmpty {
                greenPoints = geometry
            } else if element.tags?["golf"] == "fairway", let geometry = element.geometry, !geometry.isEmpty {
                fairwayPoints = geometry
            } else if element.tags?["golf"] == "bunker", let geometry = element.geometry, !geometry.isEmpty {
                bunkerPolygons.append(geometry)
            } else if element.tags?["golf"] == "rough", let geometry = element.geometry, !geometry.isEmpty {
                roughPoints = geometry
            } else if element.tags?["water"] != nil || element.tags?["natural"] == "water", let geometry = element.geometry, !geometry.isEmpty {
                waterPolygons.append(geometry)
            }
        }

        // Compute green center, front, back
        let greenCenter = greenPoints.isEmpty ? nil : centroid(of: greenPoints)
        let greenFront = greenPoints.isEmpty ? nil : greenPoints.min { $0.lat < $1.lat }
        let greenBack = greenPoints.isEmpty ? nil : greenPoints.max { $0.lat < $1.lat }

        let geometry = HoleGeometry(
            fairway: fairwayPoints.isEmpty ? nil : fairwayPoints,
            bunkers: bunkerPolygons,
            water: waterPolygons,
            rough: roughPoints.isEmpty ? nil : roughPoints
        )

        return Hole(
            id: UUID(),
            number: number,
            par: inferPar(from: number),
            handicap: nil,
            tee: teePoint,
            greenCenter: greenCenter,
            greenFront: greenFront,
            greenBack: greenBack,
            geometry: geometry
        )
    }

    private func centroid(of points: [GpsPoint]) -> GpsPoint {
        let avgLat = points.map { $0.lat }.reduce(0, +) / Double(points.count)
        let avgLon = points.map { $0.lon }.reduce(0, +) / Double(points.count)
        return GpsPoint(lat: avgLat, lon: avgLon)
    }

    private func extractHoleNumber(from element: OverpassElement) -> Int? {
        if let ref = element.tags?["ref"], let num = Int(ref) { return num }
        if let name = element.tags?["name"], let range = name.range(of: "\\d+", options: .regularExpression) {
            return Int(name[range])
        }
        return nil
    }

    private func inferPar(from holeNumber: Int) -> Int {
        // Default alternating par 4/par 3 pattern
        // Holes 1,3,5,7,9,11,13,15,17 are par 4
        // Holes 2,4,6,8,10,12,14,16,18 are par 3
        return holeNumber % 2 == 1 ? 4 : 3
    }
}

// MARK: - Supporting Types

/// Lightweight result from a course location search.
public struct CourseSearchResult: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var location: GpsPoint
    public var osmType: String
    public var osmId: Int64
}

// MARK: - Overpass API Types

struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassBounds: Decodable {
    let minlat: Double
    let minlon: Double
    let maxlat: Double
    let maxlon: Double
}

struct OverpassElement: Decodable {
    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let tags: [String: String]?
    let center: GpsPoint?
    let geometry: [GpsPoint]?
    let bounds: OverpassBounds?
    let version: Int?

    enum CodingKeys: String, CodingKey {
        case type, id, lat, lon, tags, center, geometry, bounds, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(Int64.self, forKey: .id)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        tags = try container.decodeIfPresent([String: String].self, forKey: .tags)
        center = try container.decodeIfPresent(GpsPoint.self, forKey: .center)
        geometry = try container.decodeIfPresent([GpsPoint].self, forKey: .geometry)
        bounds = try container.decodeIfPresent(OverpassBounds.self, forKey: .bounds)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
    }
}

enum OverpassError: LocalizedError {
    case invalidQuery
    case rateLimited
    case serverError
    case httpError(Int)
    case invalidResponse
    case courseNotFound
    case invalidGeometry
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid Overpass query"
        case .rateLimited:
            return "Overpass API rate limited. Try again in a few moments."
        case .serverError:
            return "Overpass server error. Try again later."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .invalidResponse:
            return "Invalid response from Overpass API"
        case .courseNotFound:
            return "Course not found in Overpass database"
        case .invalidGeometry:
            return "Invalid course geometry"
        case .decodingError(let msg):
            return "Failed to decode course data: \(msg)"
        }
    }
}
