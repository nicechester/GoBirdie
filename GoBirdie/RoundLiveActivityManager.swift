//
//  RoundLiveActivityManager.swift
//  GoBirdie
//

import ActivityKit
import Foundation

@MainActor
final class RoundLiveActivityManager {
    static let shared = RoundLiveActivityManager()
    private var activity: Activity<GoBirdieRoundAttributes>?

    func start(courseName: String, holeNumber: Int, totalHoles: Int, scoreVsPar: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = GoBirdieRoundAttributes.RoundState(
            courseName: courseName,
            holeNumber: holeNumber,
            totalHoles: totalHoles,
            scoreVsPar: scoreVsPar
        )
        let content = ActivityContent(state: state, staleDate: nil)
        activity = try? Activity.request(attributes: GoBirdieRoundAttributes(), content: content)
    }

    func update(holeNumber: Int, totalHoles: Int, scoreVsPar: Int) {
        guard let activity else { return }
        let state = GoBirdieRoundAttributes.RoundState(
            courseName: activity.content.state.courseName,
            holeNumber: holeNumber,
            totalHoles: totalHoles,
            scoreVsPar: scoreVsPar
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
}
