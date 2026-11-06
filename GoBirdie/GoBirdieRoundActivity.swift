//
//  GoBirdieRoundActivity.swift
//  GoBirdie
//

import ActivityKit
import Foundation

struct GoBirdieRoundAttributes: ActivityAttributes {
    public typealias ContentState = RoundState

    struct RoundState: Codable, Hashable {
        var courseName: String
        var holeNumber: Int
        var totalHoles: Int
        var scoreVsPar: Int  // cumulative score vs par across played holes
    }
}

extension GoBirdieRoundAttributes.RoundState {
    var scoreLabel: String {
        if scoreVsPar == 0 { return "E" }
        return scoreVsPar > 0 ? "+\(scoreVsPar)" : "\(scoreVsPar)"
    }
}
