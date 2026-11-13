import Foundation

/// A golf course fetched from OSM and cached locally.
public struct Course: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var location: GpsPoint
    public var holes: [Hole]
    public var downloadedAt: Date
    public var osmVersion: Int
    /// GolfCourseAPI course ID. Older saves stored this as a number; it's read as a string either way.
    public var golfCourseApiId: String?

    public init(
        id: String,
        name: String,
        location: GpsPoint,
        holes: [Hole] = [],
        downloadedAt: Date = Date(),
        osmVersion: Int = 0,
        golfCourseApiId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.holes = holes
        self.downloadedAt = downloadedAt
        self.osmVersion = osmVersion
        self.golfCourseApiId = golfCourseApiId
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, location, holes
        case downloadedAt = "downloaded_at"
        case osmVersion   = "osm_version"
        case golfCourseApiId = "golf_course_api_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        location = try c.decode(GpsPoint.self, forKey: .location)
        holes = try c.decode([Hole].self, forKey: .holes)
        downloadedAt = try c.decode(Date.self, forKey: .downloadedAt)
        osmVersion = try c.decode(Int.self, forKey: .osmVersion)
        // Accept both the old numeric form and the current string form.
        if let text = try? c.decodeIfPresent(String.self, forKey: .golfCourseApiId) {
            golfCourseApiId = text
        } else if let number = try? c.decodeIfPresent(Int.self, forKey: .golfCourseApiId) {
            golfCourseApiId = String(number)
        } else {
            golfCourseApiId = nil
        }
    }
}

