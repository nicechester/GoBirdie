import Foundation

/// A golf course fetched from OSM and cached locally.
public struct Course: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var location: GpsPoint
    public var holes: [Hole]
    public var downloadedAt: Date
    public var osmVersion: Int

    public init(
        id: String,
        name: String,
        location: GpsPoint,
        holes: [Hole] = [],
        downloadedAt: Date = Date(),
        osmVersion: Int = 0
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.holes = holes
        self.downloadedAt = downloadedAt
        self.osmVersion = osmVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, location, holes
        case downloadedAt = "downloaded_at"
        case osmVersion   = "osm_version"
    }
}

