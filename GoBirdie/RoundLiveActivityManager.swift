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
        let info = ActivityAuthorizationInfo()
        print("[LiveActivity] areActivitiesEnabled=\(info.areActivitiesEnabled)")
        guard info.areActivitiesEnabled else {
            print("[LiveActivity] ERROR: Live Activities not enabled — check Settings → GoBirdie → Live Activities")
            return
        }
        let state = GoBirdieRoundAttributes.RoundState(
            courseName: courseName,
            holeNumber: holeNumber,
            totalHoles: totalHoles,
            scoreVsPar: scoreVsPar
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            activity = try Activity.request(attributes: GoBirdieRoundAttributes(), content: content)
            print("[LiveActivity] Started: id=\(activity?.id ?? "nil")")
        } catch {
            print("[LiveActivity] ERROR starting: \(error)")
        }
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
        Task {
            // End the tracked activity
            if let activity {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            // Also end any orphaned activities (e.g. after app restart)
            for orphan in Activity<GoBirdieRoundAttributes>.activities {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
            self.activity = nil
        }
    }
}
