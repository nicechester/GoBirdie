//
//  AppState.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import Combine
import GoBirdieCore

/// Manages global app state and round lifecycle.
/// Handles auto-detection of starting hole and creation of new rounds.
@MainActor
final class AppState: ObservableObject {
    @Published var activeRound: RoundSession?
    @Published var activeRoundViewModel: RoundViewModel?
    @Published var selectedTab: Int = 1
    @Published var teeColor: String = UserDefaults.standard.string(forKey: "teeColor") ?? "Blue" {
        didSet { UserDefaults.standard.set(teeColor, forKey: "teeColor") }
    }

    private let locationService = LocationService()
    private let distanceEngine = DistanceEngine()

    // MARK: - Public API

    /// Detect the nearest tee from the player's current GPS location.
    /// Returns the hole number (1-18) of the nearest tee box.
    /// - Parameters:
    ///   - playerLocation: The player's current GPS coordinates.
    ///   - course: The course being played.
    /// - Returns: The hole number (1-based) of the nearest tee, or 1 if unable to detect.
    func detectStartingHole(from playerLocation: GpsPoint, course: Course) -> Int {
        var nearest = (hole: 1, distance: Double.infinity)
        for hole in course.holes {
            guard let tee = hole.tee else { continue }
            let dist = distanceEngine.distanceYards(from: playerLocation, to: tee)
            if dist < nearest.distance {
                nearest = (hole: hole.number, distance: dist)
            }
        }
        print("[AppState] Starting hole detected: \(nearest.hole) (\(Int(nearest.distance))y from nearest tee)")
        return nearest.hole
    }

    /// Start a new round on the specified course.
    /// - Creates a Round with all 18 HoleScore structs initialized from course definition.
    /// - Auto-detects the starting hole from player's GPS location.
    /// - Activates location tracking.
    /// - Returns a configured RoundSession ready to use.
    ///
    /// - Parameters:
    ///   - course: The Course to play.
    ///   - playerLocation: The player's current GPS coordinates (for auto-detection).
    /// - Throws: Any errors from round creation or storage.
    /// - Returns: A configured RoundSession.
    func startRound(course: Course, playerLocation: GpsPoint) -> RoundSession {
        // Create HoleScore structs for all 18 holes from course definition
        let holeScores = course.holes.map { hole in
            HoleScore(
                number: hole.number,
                par: hole.par,
                strokes: 0,
                putts: 0,
                fairwayHit: nil,
                gir: false,
                shots: []
            )
        }

        // Create the Round
        let round = Round(
            id: UUID().uuidString,
            source: "apple",
            courseId: course.id,
            courseName: course.name,
            startedAt: Date(),
            endedAt: nil,
            holesPlayed: 0,
            holes: holeScores,
            totalStrokes: 0,
            totalPutts: 0
        )

        // Auto-detect starting hole
        let startingHoleNumber = 1  // default hole 1; user can change via picker
        let startingHoleIndex = startingHoleNumber - 1

        // Create the RoundSession
        let session = RoundSession(round: round, startingHoleIndex: startingHoleIndex)
        self.activeRound = session

        // Switch to Round tab
        self.selectedTab = 1

        // Create the ViewModel for UI updates
        let viewModel = RoundViewModel(session: session, course: course, locationService: locationService)
        self.activeRoundViewModel = viewModel

        // Start location tracking
        viewModel.startRound()

        // Notify Watch of round start with initial hole coordinates
        if let startingHole = course.holes.first(where: { $0.number == startingHoleNumber }) {
            ConnectivityService.shared.sendHoleData(
                hole: startingHole,
                holeNumber: startingHoleNumber,
                courseName: course.name,
                totalStrokes: 0
            )
        }

        return session
    }

    /// End the active round, save it, and clean up.
    func endActiveRound() {
        guard let session = activeRound else { return }
        session.endRound()

        let store = RoundStore()
        do {
            try store.save(session.round)
            print("[AppState] Round saved: \(session.round.id)")
        } catch {
            print("[AppState] Failed to save round: \(error)")
        }

        activeRoundViewModel?.stopRound()
        activeRound = nil
        activeRoundViewModel = nil
    }

    /// Cancel the active round without saving.
    func cancelActiveRound() {
        activeRoundViewModel?.stopRound()
        activeRound = nil
        activeRoundViewModel = nil
    }

    /// Get the current location service (for testing or advanced usage).
    func getLocationService() -> LocationService {
        locationService
    }
}
