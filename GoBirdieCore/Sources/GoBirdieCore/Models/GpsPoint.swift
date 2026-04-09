import Foundation

/// A WGS-84 coordinate. Used everywhere a latitude/longitude is stored.
public struct GpsPoint: Codable, Sendable, Hashable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    public func distanceMeters(to other: GpsPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (other.lat - lat) * .pi / 180
        let dLon = (other.lon - lon) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2)
            + cos(lat * .pi / 180) * cos(other.lat * .pi / 180)
            * sin(dLon/2) * sin(dLon/2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    public func distanceMilesString(to other: GpsPoint) -> String {
        let miles = distanceMeters(to: other) / 1609.34
        if miles < 0.1 { return "< 0.1 mi" }
        return String(format: "%.1f mi", miles)
    }
}
