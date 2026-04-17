import Foundation

/// Standard set of golf clubs. `.unknown` is the default when a player
/// skips the club picker after marking a shot.
public enum ClubType: String, Codable, Sendable, CaseIterable {
    case unknown        = "unknown"
    case driver         = "driver"
    case wood3          = "3w"
    case wood5          = "5w"
    case hybrid3        = "3h"
    case hybrid4        = "4h"
    case hybrid5        = "5h"
    case iron4          = "4i"
    case iron5          = "5i"
    case iron6          = "6i"
    case iron7          = "7i"
    case iron8          = "8i"
    case iron9          = "9i"
    case pitchingWedge  = "pw"
    case gapWedge       = "gw"
    case sandWedge      = "sw"
    case lobWedge       = "lw"
    case putter         = "putter"

    public var displayName: String {
        switch self {
        case .unknown:       return "Unknown"
        case .driver:        return "Driver"
        case .wood3:         return "3 Wood"
        case .wood5:         return "5 Wood"
        case .hybrid3:       return "3 Hybrid"
        case .hybrid4:       return "4 Hybrid"
        case .hybrid5:       return "5 Hybrid"
        case .iron4:         return "4 Iron"
        case .iron5:         return "5 Iron"
        case .iron6:         return "6 Iron"
        case .iron7:         return "7 Iron"
        case .iron8:         return "8 Iron"
        case .iron9:         return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .gapWedge:      return "Gap Wedge"
        case .sandWedge:     return "Sand Wedge"
        case .lobWedge:      return "Lob Wedge"
        case .putter:        return "Putter"
        }
    }

    public var shortName: String {
        switch self {
        case .unknown:       return "?"
        case .driver:        return "D"
        case .wood3:         return "3W"
        case .wood5:         return "5W"
        case .hybrid3:       return "3H"
        case .hybrid4:       return "4H"
        case .hybrid5:       return "5H"
        case .iron4:         return "4i"
        case .iron5:         return "5i"
        case .iron6:         return "6i"
        case .iron7:         return "7i"
        case .iron8:         return "8i"
        case .iron9:         return "9i"
        case .pitchingWedge: return "PW"
        case .gapWedge:      return "GW"
        case .sandWedge:     return "SW"
        case .lobWedge:      return "LW"
        case .putter:        return "P"
        }
    }

    /// The default set of clubs in a standard bag (no hybrids).
    public static let defaultBag: [ClubType] = [
        .driver, .wood3, .wood5,
        .iron4, .iron5, .iron6, .iron7, .iron8, .iron9,
        .pitchingWedge, .gapWedge, .sandWedge, .lobWedge,
        .putter
    ]

    /// All selectable clubs (excludes .unknown).
    public static let allSelectable: [ClubType] = allCases.filter { $0 != .unknown }
}
