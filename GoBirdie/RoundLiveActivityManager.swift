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
        guard info.areActivitiesEnabled else {
            print("[LiveActivity] ERROR: Live Activities not enabled")
            return
        }
        // End any existing activities before starting a new one
        Task {
            for orphan in Activity<GoBirdieRoundAttributes>.activities {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
            let state = GoBirdieRoundAttributes.RoundState(
                courseName: courseName,
                holeNumber: holeNumber,
                totalHoles: totalHoles,
                scoreVsPar: scoreVsPar
            )
            do {
                self.activity = try Activity.request(
                    attributes: GoBirdieRoundAttributes(),
                    content: ActivityContent(state: state, staleDate: nil)
                )
                print("[LiveActivity] Started: id=\(self.activity?.id ?? "nil")")
            } catch {
                print("[LiveActivity] ERROR starting: \(error)")
            }
        }
    }

    /// Call on app launch to clean up any activities left over from a previous session.
    func endOrphans() {
        Task {
            for orphan in Activity<GoBirdieRoundAttributes>.activities {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
            self.activity = nil
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
