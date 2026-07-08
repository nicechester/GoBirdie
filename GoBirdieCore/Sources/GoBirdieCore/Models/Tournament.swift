import Foundation

public enum PlayerSource: String, Codable, Sendable {
    case `self` = "SELF"
    case received = "RECEIVED"
    case manual = "MANUAL"
}

public struct TournamentPlayer: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var holes: [HoleScore]
    public var source: PlayerSource

    public init(
        id: String = UUID().uuidString,
        name: String,
        holes: [HoleScore],
        source: PlayerSource = .manual
    ) {
        self.id = id
        self.name = name
        self.holes = holes
        self.source = source
    }

    public var totalStrokes: Int { holes.reduce(0) { $0 + $1.strokes } }
    public var totalPutts: Int   { holes.reduce(0) { $0 + $1.putts } }
    public var scoreVsPar: Int {
        let played = holes.filter { $0.strokes > 0 }
        return played.reduce(0) { $0 + $1.strokes } - played.reduce(0) { $0 + $1.par }
    }
}

public struct Tournament: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String?
    public var courseId: String
    public var courseName: String
    public var date: String          // yyyy-MM-dd
    public var players: [TournamentPlayer]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        courseId: String,
        courseName: String,
        date: String,
        players: [TournamentPlayer] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.courseId = courseId
        self.courseName = courseName
        self.date = date
        self.players = players
        self.createdAt = createdAt
    }
}
