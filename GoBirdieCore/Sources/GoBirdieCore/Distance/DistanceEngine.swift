import Foundation
import CoreLocation

/// Computes front/pin/back distances in yards and meters from a player position.
public struct DistanceEngine: Sendable {

    public init() {}

    public struct Distances: Sendable {
        public var frontYards: Int?
        public var pinYards: Int?
        public var backYards: Int?
        public var frontMeters: Int?
        public var pinMeters: Int?
        public var backMeters: Int?

        public init() {}
    }

    /// Compute distances from `playerLocation` to the front, pin, and back of a hole.
    public func distances(from playerLocation: GpsPoint, hole: Hole) -> Distances {
        var result = Distances()
        let from = clLocation(playerLocation)

        if let greenFront = hole.greenFront {
            let meters = from.distance(from: clLocation(greenFront))
            result.frontMeters = Int(meters.rounded())
            result.frontYards = Int((meters * Self.metersToYards).rounded())
        }
        if let greenCenter = hole.greenCenter {
            let meters = from.distance(from: clLocation(greenCenter))
            result.pinMeters = Int(meters.rounded())
            result.pinYards = Int((meters * Self.metersToYards).rounded())
        }
        if let greenBack = hole.greenBack {
            let meters = from.distance(from: clLocation(greenBack))
            result.backMeters = Int(meters.rounded())
            result.backYards = Int((meters * Self.metersToYards).rounded())
        }
        return result
    }

    /// Straight-line distance in yards between two GPS points.
    public func distanceYards(from: GpsPoint, to: GpsPoint) -> Double {
        clLocation(from).distance(from: clLocation(to)) * Self.metersToYards
    }

    private func clLocation(_ point: GpsPoint) -> CLLocation {
        CLLocation(latitude: point.lat, longitude: point.lon)
    }

    private static let metersToYards: Double = 1.09361
}
