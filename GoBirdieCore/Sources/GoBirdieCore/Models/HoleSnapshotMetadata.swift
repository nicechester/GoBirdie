import Foundation

/// Metadata for a hole snapshot image generated for watch display.
/// Contains bounds (SW/NE corners), image dimensions, and bearing for orientation.
public struct HoleSnapshotMetadata: Codable, Sendable {
    public let holeNumber: Int
    public let version: String      // SHA-256 hex of tee + green coordinates
    public let bounds: SnapshotBounds
    public let imageWidthPx: Int
    public let imageHeightPx: Int
    public let bearingDegrees: Double

    /// SW/NE coordinate bounds for map projection
    public struct SnapshotBounds: Codable, Sendable {
        public let swLat: Double
        public let swLon: Double
        public let neLat: Double
        public let neLon: Double

        public init(swLat: Double, swLon: Double, neLat: Double, neLon: Double) {
            self.swLat = swLat
            self.swLon = swLon
            self.neLat = neLat
            self.neLon = neLon
        }

        private enum CodingKeys: String, CodingKey {
            case swLat = "sw_lat"
            case swLon = "sw_lon"
            case neLat = "ne_lat"
            case neLon = "ne_lon"
        }
    }

    public init(
        holeNumber: Int,
        version: String,
        bounds: SnapshotBounds,
        imageWidthPx: Int,
        imageHeightPx: Int,
        bearingDegrees: Double
    ) {
        self.holeNumber = holeNumber
        self.version = version
        self.bounds = bounds
        self.imageWidthPx = imageWidthPx
        self.imageHeightPx = imageHeightPx
        self.bearingDegrees = bearingDegrees
    }

    /// Initialize from a flat dictionary (as received from WCSession transfer metadata).
    public init(from dict: [String: Any]) throws {
        guard let holeNumber = dict["holeNumber"] as? Int,
              let version = dict["version"] as? String,
              let imageWidthPx = dict["imageWidthPx"] as? Int,
              let imageHeightPx = dict["imageHeightPx"] as? Int,
              let bearingDegrees = dict["bearing"] as? Double else {
            throw CocodingError.invalidInput
        }

        let bounds: SnapshotBounds
        if let boundsDict = dict["bounds"] as? [String: Double] {
            guard let swLat = boundsDict["swLat"],
                  let swLon = boundsDict["swLon"],
                  let neLat = boundsDict["neLat"],
                  let neLon = boundsDict["neLon"] else {
                throw CocodingError.invalidInput
            }
            bounds = SnapshotBounds(swLat: swLat, swLon: swLon, neLat: neLat, neLon: neLon)
        } else {
            throw CocodingError.invalidInput
        }

        self.init(
            holeNumber: holeNumber,
            version: version,
            bounds: bounds,
            imageWidthPx: imageWidthPx,
            imageHeightPx: imageHeightPx,
            bearingDegrees: bearingDegrees
        )
    }

    private enum CodingKeys: String, CodingKey {
        case holeNumber = "hole_number"
        case version
        case bounds
        case imageWidthPx = "image_width_px"
        case imageHeightPx = "image_height_px"
        case bearingDegrees = "bearing"
    }

    enum CocodingError: Error {
        case invalidInput
    }
}
