import Foundation

/// One course in the osm-golf-courses index. Border courses can appear under more than one `file`.
public struct OsmIndexEntry: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var city: String
    public var osmId: String
    public var file: String
    public var lat: Double?
    public var lon: Double?

    public var id: String { osmId }

    /// Location of the course. Only meaningful for entries returned by `OsmStaticIndex.nearby`, which
    /// are always located.
    public var point: GpsPoint { GpsPoint(lat: lat ?? 0, lon: lon ?? 0) }

    public init(name: String, city: String = "", osmId: String, file: String, lat: Double? = nil, lon: Double? = nil) {
        self.name = name
        self.city = city
        self.osmId = osmId
        self.file = file
        self.lat = lat
        self.lon = lon
    }

    private enum CodingKeys: String, CodingKey {
        case name, city, osmId, file, lat, lon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        osmId = try c.decode(String.self, forKey: .osmId)
        file = try c.decode(String.self, forKey: .file)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon = try c.decodeIfPresent(Double.self, forKey: .lon)
    }
}

/// The course index published on GitHub Pages. Cached on disk and refreshed weekly.
/// Entries without coordinates are dropped; border duplicates are merged by OSM ID.
actor OsmStaticIndex {
    static let indexURL = URL(string: "https://nicechester.github.io/osm-golf-courses/indexes/index.json")!
    private static let weekSeconds: TimeInterval = 7 * 24 * 3600

    private struct Located {
        let entry: OsmIndexEntry
        let point: GpsPoint
    }

    private let cacheFile: URL
    private let session: URLSession
    private var all: [Located]?           // every located entry, border duplicates included
    private var unique: [Located] = []    // one per OSM ID
    private var byOsmId: [String: OsmIndexEntry] = [:]

    init(cacheFile: URL, session: URLSession) {
        self.cacheFile = cacheFile
        self.session = session
    }

    /// Unique courses within `radiusMeters` of `location`, nearest first.
    func nearby(_ location: GpsPoint, radiusMeters: Double, limit: Int = 20) async throws -> [OsmIndexEntry] {
        try await load()
        return unique
            .map { ($0.entry, $0.point.distanceMeters(to: location)) }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// The region file of the entry nearest `location`. Used to pick the region to cache.
    func regionNear(_ location: GpsPoint) async throws -> String? {
        try await load()
        return all?
            .min { $0.point.distanceMeters(to: location) < $1.point.distanceMeters(to: location) }?
            .entry.file
    }

    func find(osmId: String) async throws -> OsmIndexEntry? {
        try await load()
        return byOsmId[osmId]
    }

    /// Every unique course in the index, for name search.
    func uniqueEntries() async throws -> [OsmIndexEntry] {
        try await load()
        return unique.map(\.entry)
    }

    private func load() async throws {
        if all != nil { return }
        let data = try await readOrFetch()
        let raw: [OsmIndexEntry]
        do {
            raw = try JSONDecoder().decode([OsmIndexEntry].self, from: data)
        } catch {
            print("[OSM] index decode failed (\(data.count) bytes): \(error)")
            throw error
        }

        let located: [Located] = raw.compactMap { entry in
            guard let lat = entry.lat, let lon = entry.lon else { return nil }
            return Located(entry: entry, point: GpsPoint(lat: lat, lon: lon))
        }
        var seen = Set<String>()
        var uniqueList: [Located] = []
        var byId: [String: OsmIndexEntry] = [:]
        for item in located {
            if seen.insert(item.entry.osmId).inserted {
                uniqueList.append(item)
                byId[item.entry.osmId] = item.entry
            }
        }
        print("[OSM] index loaded: \(raw.count) entries, \(located.count) located, \(uniqueList.count) unique")
        all = located
        unique = uniqueList
        byOsmId = byId
    }

    private func readOrFetch() async throws -> Data {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: cacheFile.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.weekSeconds,
           let cached = try? Data(contentsOf: cacheFile) {
            return cached
        }
        do {
            let (data, response) = try await session.data(from: Self.indexURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try fm.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheFile, options: .atomic)
            return data
        } catch {
            // Offline or Pages down: use the last good copy if there is one.
            if let stale = try? Data(contentsOf: cacheFile) { return stale }
            throw error
        }
    }
}
