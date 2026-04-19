import Foundation

/// The player's score record for a single hole in a round.
public struct HoleScore: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var number: Int
    public var par: Int
    public var strokes: Int
    public var putts: Int
    public var fairwayHit: Bool?
    public var penalties: Int
    public var shots: [Shot]
    public var greenCenter: GpsPoint?

    public init(
        id: UUID = UUID(),
        number: Int,
        par: Int,
        strokes: Int = 0,
        putts: Int = 0,
        fairwayHit: Bool? = nil,
        penalties: Int = 0,
        shots: [Shot] = [],
        greenCenter: GpsPoint? = nil
    ) {
        self.id = id
        self.number = number
        self.par = par
        self.strokes = strokes
        self.putts = putts
        self.fairwayHit = fairwayHit
        self.penalties = penalties
        self.shots = shots
        self.greenCenter = greenCenter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        par = try c.decode(Int.self, forKey: .par)
        strokes = try c.decode(Int.self, forKey: .strokes)
        putts = try c.decode(Int.self, forKey: .putts)
        fairwayHit = try c.decodeIfPresent(Bool.self, forKey: .fairwayHit)
        penalties = (try? c.decode(Int.self, forKey: .penalties)) ?? 0
        shots = try c.decode([Shot].self, forKey: .shots)
        greenCenter = try c.decodeIfPresent(GpsPoint.self, forKey: .greenCenter)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case par
        case strokes
        case putts
        case fairwayHit = "fairway_hit"
        case penalties
        case shots
        case greenCenter = "green_center"
    }

    /// Net strokes vs par for this hole. Negative = under par.
    public var scoreVsPar: Int { strokes - par }

    /// Greens In Regulation: reached green in regulation strokes (2 putts remaining on par or better).
    /// Calculated from: (strokes - putts) <= (par - 2)
    public var gir: Bool { (strokes - putts) <= (par - 2) }
}
