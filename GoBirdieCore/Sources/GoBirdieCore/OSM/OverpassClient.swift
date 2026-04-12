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
    public func searchCourses(location: GpsPoint, radius: Int) async throws -> [CourseSearchResult] {
        let latDelta = Double(radius) / 111_000.0
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

        return try await runCourseSearch(query: query, sortBy: location)
    }

    /// Search for golf courses by name within a bbox around a location.
    /// Uses server-side regex filtering so the query stays fast.
    public func searchCoursesByName(_ name: String, near location: GpsPoint, radiusKm: Int = 200) async throws -> [CourseSearchResult] {
        let latDelta = Double(radiusKm) / 111.0
        let lonDelta = Double(radiusKm) / (111.0 * cos(location.lat * .pi / 180))

        let bbox = (
            south: location.lat - latDelta,
            west: location.lon - lonDelta,
            north: location.lat + latDelta,
            east: location.lon + lonDelta
        )

        let escaped = name.replacingOccurrences(of: "\"", with: "")
        let query = """
[out:json][timeout:15][bbox:\(bbox.south),\(bbox.west),\(bbox.north),\(bbox.east)];
(
  node["leisure"="golf_course"]["name"~"\(escaped)",i];
  way["leisure"="golf_course"]["name"~"\(escaped)",i];
  relation["leisure"="golf_course"]["name"~"\(escaped)",i];
);
out center;
"""

        return try await runCourseSearch(query: query, sortBy: location)
    }

    private func runCourseSearch(query: String, sortBy location: GpsPoint) async throws -> [CourseSearchResult] {
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
            .sorted { $0.location.distanceMeters(to: location) < $1.location.distanceMeters(to: location) }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Course Download

    /// Download full hole geometry for an OSM relation.
    /// - Parameters:
    ///   - osmRelationId: OSM relation ID
    ///   - name: Course name
    public func downloadCourse(osmRelationId: Int64, name: String, playerLocation: GpsPoint? = nil, holeCount: Int = 18) async throws -> [Course] {
        // Roosevelt-style courses are mapped as ways, not relations — try both
        let elementQuery = """
[out:json];
(relation(\(osmRelationId));way(\(osmRelationId)););
out geom;
"""
        let elementData = try await post(query: elementQuery)
        let elementResponse = try JSONDecoder().decode(OverpassResponse.self, from: elementData)

        let element = elementResponse.elements.first(where: { $0.type == "relation" })
                   ?? elementResponse.elements.first(where: { $0.type == "way" })
        guard let element else { throw OverpassError.courseNotFound }

        let bounds: OverpassBounds
        if let b = element.bounds {
            bounds = b
        } else if let geom = element.geometry, !geom.isEmpty {
            bounds = OverpassBounds(
                minlat: geom.map(\.lat).min()!, minlon: geom.map(\.lon).min()!,
                maxlat: geom.map(\.lat).max()!, maxlon: geom.map(\.lon).max()!
            )
        } else {
            throw OverpassError.invalidGeometry
        }
        let (minLat, maxLat) = (bounds.minlat, bounds.maxlat)
        let (minLon, maxLon) = (bounds.minlon, bounds.maxlon)

        let geometryQuery = """
[out:json][bbox:\(minLat - 0.01),\(minLon - 0.01),\(maxLat + 0.01),\(maxLon + 0.01)];
(
  way["golf"="hole"];
  way["golf"~"fairway|green|bunker|rough"];
);
out geom tags;
"""
        let geometryData = try await post(query: geometryQuery)
        let geometryResponse = try JSONDecoder().decode(OverpassResponse.self, from: geometryData)

        let courseLocation = GpsPoint(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2)
        let anchor = playerLocation ?? courseLocation
        let version = element.version ?? 1

        // Check for multi-course complex (duplicate hole refs)
        let holeLines = geometryResponse.elements.filter { $0.tags?["golf"] == "hole" }
        let refCounts = Dictionary(grouping: holeLines.compactMap { $0.tags?["ref"].flatMap(Int.init) }, by: { $0 })
        let hasDuplicates = refCounts.values.contains { $0.count > 1 }

        if hasDuplicates {
            let groups = splitCoursesByWayIdGap(holeLines)
            print("[Overpass] Multi-course complex: \(groups.count) courses detected")
            return groups.enumerated().map { idx, groupIds in
                let groupElements = geometryResponse.elements.filter { el in
                    el.tags?["golf"] == "hole" ? groupIds.contains(el.id) : true
                }
                let holes = buildHoles(from: groupElements, anchor: anchor, holeCount: holeCount)
                let suffix = groups.count > 1 ? " #\(idx + 1)" : ""
                return Course(
                    id: "osm-\(osmRelationId)-\(idx + 1)",
                    name: "\(name)\(suffix)",
                    location: courseLocation,
                    holes: holes,
                    downloadedAt: Date(),
                    osmVersion: version
                )
            }
        }

        let holes = buildHoles(from: geometryResponse.elements, anchor: anchor, holeCount: holeCount)
        return [Course(
            id: "osm-\(osmRelationId)",
            name: name,
            location: courseLocation,
            holes: holes,
            downloadedAt: Date(),
            osmVersion: version
        )]
    }

    /// Split hole ways into groups by finding the largest gap in sorted way IDs.
    /// OSM mappers typically trace one course's holes in sequence, producing contiguous ID blocks.
    private func splitCoursesByWayIdGap(_ holeLines: [OverpassElement]) -> [Set<Int64>] {
        let ids = holeLines.map(\.id).sorted()
        guard ids.count > 1 else { return [Set(ids)] }

        // Find the largest gap
        var maxGap: Int64 = 0
        var splitIdx = 0
        for i in 1..<ids.count {
            let gap = ids[i] - ids[i - 1]
            if gap > maxGap { maxGap = gap; splitIdx = i }
        }

        let group1 = Set(ids[..<splitIdx])
        let group2 = Set(ids[splitIdx...])
        return [group1, group2]
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

    private func buildHoles(from elements: [OverpassElement], anchor: GpsPoint, holeCount: Int) -> [Hole] {
        let holeLines = elements.filter { $0.tags?["golf"] == "hole" }
        let greenPolygons = elements.filter { $0.tags?["golf"] == "green" }
        let fairwayPolygons = elements.filter { $0.tags?["golf"] == "fairway" }
        let bunkerPolygons = elements.filter { $0.tags?["golf"] == "bunker" }

        // Deduplicate by ref: multi-course complexes share a bbox and have duplicate hole numbers.
        // Keep the way whose tee is closest to the player/course anchor.
        var byRef: [Int: OverpassElement] = [:]
        for line in holeLines {
            guard let ref = line.tags?["ref"], let holeNum = Int(ref),
                  let geom = line.geometry, geom.count >= 2 else { continue }
            if let existing = byRef[holeNum],
               let existingGeom = existing.geometry,
               geom[0].distanceMeters(to: anchor) >= existingGeom[0].distanceMeters(to: anchor) { continue }
            byRef[holeNum] = line
        }

        var holes: [Hole] = []
        for (holeNum, line) in byRef {
            guard let geom = line.geometry, geom.count >= 2 else { continue }

            let tee = geom.first!
            let greenCenter = geom.last!
            let par = line.tags?["par"].flatMap(Int.init) ?? 4
            let handicap = line.tags?["handicap"].flatMap(Int.init)

            // Snap to nearest green polygon for front/back
            let nearestGreen = greenPolygons
                .compactMap { $0.geometry }
                .filter { $0.count >= 3 }
                .min { centroid(of: $0).distanceMeters(to: greenCenter) < centroid(of: $1).distanceMeters(to: greenCenter) }

            let (greenFront, greenBack): (GpsPoint?, GpsPoint?)
            if let poly = nearestGreen {
                let avgLon = poly.map { $0.lon }.reduce(0, +) / Double(poly.count)
                greenFront = GpsPoint(lat: poly.map { $0.lat }.min()!, lon: avgLon)
                greenBack  = GpsPoint(lat: poly.map { $0.lat }.max()!, lon: avgLon)
            } else {
                (greenFront, greenBack) = (nil, nil)
            }

            // Fairways/bunkers whose centroid falls within 700m of both tee and green
            let holeFairway = fairwayPolygons.compactMap(\.geometry).filter {
                let c = centroid(of: $0)
                return c.distanceMeters(to: tee) < 700 && c.distanceMeters(to: greenCenter) < 700
            }.first
            let holeBunkers = bunkerPolygons.compactMap(\.geometry).filter {
                let c = centroid(of: $0)
                return c.distanceMeters(to: tee) < 700 && c.distanceMeters(to: greenCenter) < 700
            }

            holes.append(Hole(
                id: UUID(),
                number: holeNum,
                par: par,
                handicap: handicap,
                tee: tee,
                greenCenter: greenCenter,
                greenFront: greenFront,
                greenBack: greenBack,
                geometry: HoleGeometry(fairway: holeFairway, bunkers: holeBunkers, water: [], rough: nil)
            ))
        }

        holes.sort { $0.number < $1.number }

        // Fill any missing holes up to holeCount with empty placeholders
        let present = Set(holes.map(\.number))
        for holeNum in 1...holeCount where !present.contains(holeNum) {
            holes.append(Hole(id: UUID(), number: holeNum, par: 4))
        }
        holes.sort { $0.number < $1.number }

        return holes
    }

    private func centroid(of points: [GpsPoint]) -> GpsPoint {
        let avgLat = points.map { $0.lat }.reduce(0, +) / Double(points.count)
        let avgLon = points.map { $0.lon }.reduce(0, +) / Double(points.count)
        return GpsPoint(lat: avgLat, lon: avgLon)
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

    init(minlat: Double, minlon: Double, maxlat: Double, maxlon: Double) {
        self.minlat = minlat; self.minlon = minlon
        self.maxlat = maxlat; self.maxlon = maxlon
    }
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
