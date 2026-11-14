import Foundation

/// Static OSM course data (osm-golf-courses): the index for nearby courses, and region files for geometry.
/// The index and region live in Caches, so the system may clear them; both are re-downloaded when needed.
public actor OsmCourseSource {
    public static let shared = OsmCourseSource(
        baseDir: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("osm", isDirectory: true)
    )

    private let index: OsmStaticIndex
    private let regions: OsmRegionCache

    public init(baseDir: URL) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        index = OsmStaticIndex(cacheFile: baseDir.appendingPathComponent("index.json"), session: session)
        regions = OsmRegionCache(dir: baseDir.appendingPathComponent("regions", isDirectory: true), session: session)
    }

    /// Courses within `radiusMeters` of `location`, nearest first. Empty when the index has nothing nearby.
    public func nearby(_ location: GpsPoint, radiusMeters: Double) async throws -> [OsmIndexEntry] {
        try await index.nearby(location, radiusMeters: radiusMeters, limit: 20)
    }

    /// Name search over the whole index, not just nearby courses. A course matches when its name has every
    /// distinctive word of `name` ("Angeles National" matches "Angeles National Golf Club"). Nearest first.
    public func search(name: String, near location: GpsPoint, limit: Int = 30) async throws -> [OsmIndexEntry] {
        let query = Self.distinctiveWords(name)
        guard !query.isEmpty else { return [] }
        return try await index.uniqueEntries()
            .filter { Self.distinctiveWords($0.name).isSuperset(of: query) }
            .sorted { $0.point.distanceMeters(to: location) < $1.point.distanceMeters(to: location) }
            .prefix(limit)
            .map { $0 }
    }

    /// Geometry for one course, one `Course` per layout (a multi-course complex gives several). The region comes
    /// from the user's location (the index entry nearest the user), with the course's own region as a fallback.
    /// Returns an empty list when neither region has the course.
    public func loadCourse(osmId: String, name: String, userLocation: GpsPoint) async throws -> [Course] {
        let nearbyFile = try await index.regionNear(userLocation)
        let ownFile = try await index.find(osmId: osmId)?.file

        var candidates: [String] = []
        if let nearbyFile { candidates.append(nearbyFile) }
        if let ownFile, ownFile != nearbyFile { candidates.append(ownFile) }

        for file in candidates {
            let plain = try await regions.ensure(file)
            let courses = try OsmCourseExtractor.extract(from: plain, osmId: osmId, name: name, anchor: userLocation)
            if !courses.isEmpty { return courses }
        }
        return []
    }

    /// The course named `name` near `location`. Used for GolfCourseAPI courses, whose names may differ slightly
    /// from OSM. A name matches when it has the same distinctive words, or when the OSM name contains all of them,
    /// so "Harding" never picks up a different course by distance alone.
    public func loadNamedNear(name: String, location: GpsPoint, radiusMeters: Double = 5_000) async throws -> Course? {
        let hits = try await index.nearby(location, radiusMeters: radiusMeters, limit: 50)
        guard let match = Self.namedMatch(name, in: hits) else { return nil }
        return try await loadCourse(osmId: match.osmId, name: name, userLocation: location).first
    }

    /// Bytes used by the cached region (0 when nothing is cached).
    public func cachedRegionBytes() async -> Int {
        await regions.size()
    }

    /// Settings → Clear temporary files. Removes the cached region only. Returns the bytes freed.
    public func clearRegionCache() async -> Int {
        await regions.clear()
    }

    static func namedMatch(_ name: String, in hits: [OsmIndexEntry]) -> OsmIndexEntry? {
        let query = distinctiveWords(name)
        if query.isEmpty {
            return hits.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        return hits.first { distinctiveWords($0.name) == query }
            ?? hits.first { distinctiveWords($0.name).isSuperset(of: query) }
    }

    static func distinctiveWords(_ name: String) -> Set<String> {
        Set(
            name.lowercased()
                .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
                .map(String.init)
                .filter { !genericWords.contains($0) }
        )
    }

    private static let genericWords: Set<String> = [
        "golf", "course", "club", "country", "municipal", "links", "the", "academy", "par",
    ]
}
