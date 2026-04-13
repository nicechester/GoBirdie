import Foundation

/// A single shot dropped by the player during a hole.
/// `sequence` is 1-based (first shot of the hole is 1).
public struct Shot: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sequence: Int
    public var location: GpsPoint
    public var timestamp: Date
    public var club: ClubType
    /// Distance in yards from shot location to the pin at time of recording.
    /// nil when hole geometry is unavailable.
    public var distanceToPinYards: Int?
    public var altitudeMeters: Double?
    public var heartRateBpm: Int?
    public var temperatureCelsius: Double?

    public init(
        id: UUID = UUID(),
        sequence: Int,
        location: GpsPoint,
        timestamp: Date,
        club: ClubType = .unknown,
        distanceToPinYards: Int? = nil,
        altitudeMeters: Double? = nil,
        heartRateBpm: Int? = nil,
        temperatureCelsius: Double? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.location = location
        self.timestamp = timestamp
        self.club = club
        self.distanceToPinYards = distanceToPinYards
        self.altitudeMeters = altitudeMeters
        self.heartRateBpm = heartRateBpm
        self.temperatureCelsius = temperatureCelsius
    }

    private enum CodingKeys: String, CodingKey {
        case id, sequence, location, timestamp, club
        case distanceToPinYards = "distance_to_pin_yards"
        case altitudeMeters = "altitude_meters"
        case heartRateBpm = "heart_rate_bpm"
        case temperatureCelsius = "temperature_celsius"
    }
}
