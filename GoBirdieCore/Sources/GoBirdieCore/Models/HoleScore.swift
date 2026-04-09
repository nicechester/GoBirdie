import Foundation

/// The player's score record for a single hole in a round.
public struct HoleScore: Codable, Sendable, Identifiable {
    public var id: UUID
    public var number: Int
    public var par: Int
    public var strokes: Int
    public var putts: Int
    public var fairwayHit: Bool?
    public var gir: Bool
    public var shots: [Shot]

    public init(
        id: UUID = UUID(),
        number: Int,
        par: Int,
        strokes: Int = 0,
        putts: Int = 0,
        fairwayHit: Bool? = nil,
        gir: Bool = false,
        shots: [Shot] = []
    ) {
        self.id = id
        self.number = number
        self.par = par
        self.strokes = strokes
        self.putts = putts
        self.fairwayHit = fairwayHit
        self.gir = gir
        self.shots = shots
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case par
        case strokes
        case putts
        case fairwayHit = "fairway_hit"
        case gir
        case shots
    }

    /// Net strokes vs par for this hole. Negative = under par.
    public var scoreVsPar: Int { strokes - par }
}
