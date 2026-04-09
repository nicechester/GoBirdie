import Foundation

/// Static definition of a hole on a course, derived from OSM data.
public struct Hole: Codable, Sendable, Identifiable {
    public var id: UUID
    public var number: Int
    public var par: Int
    public var handicap: Int?
    public var yardage: String?   // from GolfCourseAPI e.g. "385"
    public var tee: GpsPoint?
    public var greenCenter: GpsPoint?
    public var greenFront: GpsPoint?
    public var greenBack: GpsPoint?
    public var geometry: HoleGeometry?

    public init(
        id: UUID = UUID(),
        number: Int,
        par: Int,
        handicap: Int? = nil,
        yardage: String? = nil,
        tee: GpsPoint? = nil,
        greenCenter: GpsPoint? = nil,
        greenFront: GpsPoint? = nil,
        greenBack: GpsPoint? = nil,
        geometry: HoleGeometry? = nil
    ) {
        self.id = id
        self.number = number
        self.par = par
        self.handicap = handicap
        self.yardage = yardage
        self.tee = tee
        self.greenCenter = greenCenter
        self.greenFront = greenFront
        self.greenBack = greenBack
        self.geometry = geometry
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, par, handicap, yardage, tee, geometry
        case greenCenter = "green_center"
        case greenFront  = "green_front"
        case greenBack   = "green_back"
    }
}
