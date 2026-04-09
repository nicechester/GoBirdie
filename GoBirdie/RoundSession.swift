//
//  RoundSession.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import Combine
import GoBirdieCore

/// Manages the state machine for an in-progress golf round.
/// Handles stroke counting, shot marking, hole navigation, and score totals.
@MainActor
final class RoundSession: ObservableObject {
    @Published var round: Round
    @Published var currentHoleIndex: Int = 0
    @Published var isComplete: Bool = false

    init(round: Round, startingHoleIndex: Int = 0) {
        self.round = round
        self.currentHoleIndex = startingHoleIndex
        self.isComplete = false
    }

    // MARK: - Computed Properties

    var currentHole: HoleScore? {
        guard round.holes.indices.contains(currentHoleIndex) else { return nil }
        return round.holes[currentHoleIndex]
    }

    var currentHoleNumber: Int {
        currentHoleIndex + 1
    }

    // MARK: - Public API

    /// Add one stroke to the current hole.
    func addStroke() {
        guard currentHole != nil, !isComplete else { return }
        round.holes[currentHoleIndex].strokes += 1
        recomputeTotals()
    }

    /// Remove one stroke from the current hole (minimum 0).
    func removeStroke() {
        guard let hole = currentHole, !isComplete, hole.strokes > 0 else { return }
        round.holes[currentHoleIndex].strokes -= 1
        recomputeTotals()
    }

    /// Mark a shot at the player's current GPS location.
    /// - Parameters:
    ///   - location: The GPS coordinates of the shot.
    ///   - club: The club used (defaults to unknown).
    ///   - distanceToPinYards: Optional distance to pin at time of recording.
    func markShot(at location: GpsPoint, club: ClubType = .unknown, distanceToPinYards: Int? = nil) {
        guard currentHole != nil else { return }
        let shot = Shot(
            sequence: round.holes[currentHoleIndex].shots.count + 1,
            location: location,
            timestamp: Date(),
            club: club,
            distanceToPinYards: distanceToPinYards
        )
        round.holes[currentHoleIndex].shots.append(shot)
    }

    /// Set the number of putts for the current hole.
    /// Automatically recalculates GIR after update.
    /// - Parameter count: Number of putts (must be >= 0).
    func setPutts(_ count: Int) {
        guard currentHole != nil, count >= 0 else { return }
        round.holes[currentHoleIndex].putts = count
        updateGIR()
        recomputeTotals()
    }

    /// Move to the next hole, or complete the round if on hole 18.
    func endHole() {
        guard currentHoleIndex < 17 else {
            // Last hole completed, mark round complete
            round.endedAt = Date()
            isComplete = true
            return
        }
        // Move to next hole
        currentHoleIndex += 1
    }

    /// Navigate directly to a specific hole by number.
    /// Notifies Watch of the hole change if available.
    /// - Parameter holeNumber: The hole number (1-18).
    /// - Parameter course: The current course (for hole coordinates).
    func navigateTo(holeNumber: Int, course: Course? = nil) {
        let idx = holeNumber - 1
        guard round.holes.indices.contains(idx) else { return }
        currentHoleIndex = idx

        // Notify Watch of hole change if course data is available
        if let course = course, let hole = course.holes.first(where: { $0.number == holeNumber }) {
            ConnectivityService.shared.sendHoleCoordinates(hole, holeNumber: holeNumber)
        }
    }

    /// End the round immediately and mark it complete.
    /// Sets endedAt timestamp and recalculates totals.
    func endRound() {
        guard !isComplete else { return }
        round.endedAt = Date()
        isComplete = true
        recomputeTotals()
    }

    // MARK: - Private

    /// Recompute total strokes and putts from all holes.
    private func recomputeTotals() {
        round.totalStrokes = round.holes.reduce(0) { $0 + $1.strokes }
        round.totalPutts = round.holes.reduce(0) { $0 + $1.putts }
    }

    /// Update GIR (Greens In Regulation) for the current hole.
    /// GIR = strokes <= par + 2
    private func updateGIR() {
        guard currentHoleIndex < round.holes.count else { return }
        let hole = round.holes[currentHoleIndex]
        let gir = hole.strokes <= hole.par + 2
        round.holes[currentHoleIndex].gir = gir
    }
}
