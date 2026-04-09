import Foundation

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
        totalPutts: Int = 0
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
    }
}
