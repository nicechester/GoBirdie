import Foundation

/// The strokes-gained baseline a player compares themselves against.
/// Expected strokes gained per category for each tier are based on
/// standard SG research benchmarks.
public enum SGBaseline: String, CaseIterable, Sendable, Codable {
    case scratch  = "Scratch"
    case single   = "Single Digit"
    case bogey    = "Bogey Golfer"
    case highCap  = "High Handicap"

    /// Expected total strokes gained vs scratch baseline per round.
    /// scratch = 0 by definition; others are negative (they lose strokes vs scratch).
    public var expectedTotalVsScratch: Double {
        switch self {
        case .scratch:  return  0.0
        case .single:   return -4.0
        case .bogey:    return -9.0
        case .highCap:  return -16.0
        }
    }

    /// Expected SG per category vs scratch.
    public var expectedSG: (offTee: Double, approach: Double, shortGame: Double, putting: Double) {
        switch self {
        case .scratch:  return (0.0,   0.0,   0.0,   0.0)
        case .single:   return (-0.8, -1.5,  -0.9,  -0.8)
        case .bogey:    return (-1.8, -3.5,  -2.0,  -1.7)
        case .highCap:  return (-3.2, -6.0,  -3.5,  -3.3)
        }
    }

    public var displayName: String { rawValue }
}
