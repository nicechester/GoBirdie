import Foundation

/// A polygon is an ordered list of GpsPoints forming a closed ring.
public typealias Polygon = [GpsPoint]

/// All OSM-derived spatial data for a single hole.
public struct HoleGeometry: Codable, Sendable {
    public var fairway: Polygon?
    public var bunkers: [Polygon]
    public var water: [Polygon]
    public var rough: Polygon?

    public init(
        fairway: Polygon? = nil,
        bunkers: [Polygon] = [],
        water: [Polygon] = [],
        rough: Polygon? = nil
    ) {
        self.fairway = fairway
        self.bunkers = bunkers
        self.water = water
        self.rough = rough
    }
}
