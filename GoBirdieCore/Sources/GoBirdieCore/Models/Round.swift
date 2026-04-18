import Foundation

/// A timestamped health reading from Apple Watch during a round.
public struct HeartRateSample: Codable, Sendable {
    public var timestamp: Date
    public var bpm: Int
    public var altitudeMeters: Double?

    public init(timestamp: Date, bpm: Int, altitudeMeters: Double? = nil) {
        self.timestamp = timestamp
        self.bpm = bpm
        self.altitudeMeters = altitudeMeters
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, bpm
        case altitudeMeters = "altitude_meters"
    }
}

/// A complete or in-progress golf round.
public struct Round: Codable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var courseId: String
    public var courseName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var holesPlayed: Int
    public var holes: [HoleScore]
    public var totalStrokes: Int
    public var totalPutts: Int
    public var heartRateTimeline: [HeartRateSample]
    public var temperatureMinF: Double?
    public var temperatureMaxF: Double?
    public var weatherCondition: String?

    public init(
        id: String,
        source: String = "apple",
        courseId: String,
        courseName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        holesPlayed: Int = 0,
        holes: [HoleScore] = [],
        totalStrokes: Int = 0,
        totalPutts: Int = 0,
        heartRateTimeline: [HeartRateSample] = [],
        temperatureMinF: Double? = nil,
        temperatureMaxF: Double? = nil,
        weatherCondition: String? = nil
    ) {
        self.id = id
        self.source = source
        self.courseId = courseId
        self.courseName = courseName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.holesPlayed = holesPlayed
        self.holes = holes
        self.totalStrokes = totalStrokes
        self.totalPutts = totalPutts
        self.heartRateTimeline = heartRateTimeline
        self.temperatureMinF = temperatureMinF
        self.temperatureMaxF = temperatureMaxF
        self.weatherCondition = weatherCondition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        courseId = try c.decode(String.self, forKey: .courseId)
        courseName = try c.decode(String.self, forKey: .courseName)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        holesPlayed = try c.decode(Int.self, forKey: .holesPlayed)
        holes = try c.decode([HoleScore].self, forKey: .holes)
        totalStrokes = try c.decode(Int.self, forKey: .totalStrokes)
        totalPutts = try c.decode(Int.self, forKey: .totalPutts)
        heartRateTimeline = (try? c.decode([HeartRateSample].self, forKey: .heartRateTimeline)) ?? []
        temperatureMinF = try c.decodeIfPresent(Double.self, forKey: .temperatureMinF)
        temperatureMaxF = try c.decodeIfPresent(Double.self, forKey: .temperatureMaxF)
        weatherCondition = try c.decodeIfPresent(String.self, forKey: .weatherCondition)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case courseId    = "course_id"
        case courseName  = "course_name"
        case startedAt   = "started_at"
        case endedAt     = "ended_at"
        case holesPlayed = "holes_played"
        case holes
        case totalStrokes = "total_strokes"
        case totalPutts   = "total_putts"
        case heartRateTimeline = "heart_rate_timeline"
        case temperatureMinF = "temperature_min_f"
        case temperatureMaxF = "temperature_max_f"
        case weatherCondition = "weather_condition"
    }
}
