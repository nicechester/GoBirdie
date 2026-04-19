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

        NotificationCenter.default.addObserver(
            forName: .watchStrokeUpdate, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let holeNumber = notification.userInfo?["holeNumber"] as? Int,
                  let strokes = notification.userInfo?["strokes"] as? Int,
                  let idx = self.round.holes.firstIndex(where: { $0.number == holeNumber })
            else { return }
            self.round.holes[idx].strokes = strokes
            if let putts = notification.userInfo?["putts"] as? Int {
                self.round.holes[idx].putts = putts
            }
            self.recomputeTotals()
        }

        NotificationCenter.default.addObserver(
            forName: .watchShotMarked, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let holeNumber = info["holeNumber"] as? Int,
                  let idx = self.round.holes.firstIndex(where: { $0.number == holeNumber })
            else { return }
            let lat = info["lat"] as? Double ?? 0
            let lon = info["lon"] as? Double ?? 0
            let shot = Shot(
                sequence: self.round.holes[idx].shots.count + 1,
                location: GpsPoint(lat: lat, lon: lon),
                timestamp: Date(),
                altitudeMeters: info["altitude"] as? Double,
                heartRateBpm: info["heartRate"] as? Int
            )
            self.round.holes[idx].shots.append(shot)
            if let strokes = info["strokes"] as? Int {
                self.round.holes[idx].strokes = strokes
            }
            if let putts = info["putts"] as? Int {
                self.round.holes[idx].putts = putts
            }
            self.recomputeTotals()
        }

        NotificationCenter.default.addObserver(
            forName: .watchClubSelection, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let holeNumber = info["holeNumber"] as? Int,
                  let clubRaw = info["club"] as? String,
                  let club = ClubType(rawValue: clubRaw),
                  let idx = self.round.holes.firstIndex(where: { $0.number == holeNumber }),
                  !self.round.holes[idx].shots.isEmpty
            else { return }
            let lastIdx = self.round.holes[idx].shots.count - 1
            self.round.holes[idx].shots[lastIdx].club = club
        }
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
        sendStrokeUpdate()
    }

    /// Add a penalty stroke to the current hole.
    func addPenalty() {
        guard currentHole != nil, !isComplete else { return }
        round.holes[currentHoleIndex].strokes += 1
        round.holes[currentHoleIndex].penalties += 1
        recomputeTotals()
        sendStrokeUpdate()
    }

    /// Undo the last action on the current hole.
    /// If there are shots, removes the last shot and decrements strokes.
    /// Otherwise decrements strokes (minimum 0).
    func undoLastAction() {
        guard let hole = currentHole, !isComplete, hole.strokes > 0 else { return }
        if !round.holes[currentHoleIndex].shots.isEmpty {
            round.holes[currentHoleIndex].shots.removeLast()
        } else if round.holes[currentHoleIndex].penalties > 0 {
            round.holes[currentHoleIndex].penalties -= 1
        }
        round.holes[currentHoleIndex].strokes -= 1
        recomputeTotals()
        sendStrokeUpdate()
    }

    /// Remove one stroke from the current hole (minimum 0).
    func removeStroke() {
        guard let hole = currentHole, !isComplete, hole.strokes > 0 else { return }
        round.holes[currentHoleIndex].strokes -= 1
        recomputeTotals()
        sendStrokeUpdate()
    }

    private func sendStrokeUpdate() {
        ConnectivityService.shared.sendStrokeUpdate(
            holeNumber: currentHoleNumber,
            strokes: round.holes[currentHoleIndex].strokes,
            putts: round.holes[currentHoleIndex].putts
        )
    }

    /// Mark a shot at the player's current GPS location.
    /// - Parameters:
    ///   - location: The GPS coordinates of the shot.
    ///   - club: The club used (defaults to unknown).
    ///   - distanceToPinYards: Optional distance to pin at time of recording.
    func markShot(at location: GpsPoint, club: ClubType = .unknown, distanceToPinYards: Int? = nil,
                   altitudeMeters: Double? = nil, heartRateBpm: Int? = nil, temperatureCelsius: Double? = nil) {
        guard currentHole != nil else { return }
        let shot = Shot(
            sequence: round.holes[currentHoleIndex].shots.count + 1,
            location: location,
            timestamp: Date(),
            club: club,
            distanceToPinYards: distanceToPinYards,
            altitudeMeters: altitudeMeters,
            heartRateBpm: heartRateBpm,
            temperatureCelsius: temperatureCelsius
        )
        round.holes[currentHoleIndex].shots.append(shot)
        round.holes[currentHoleIndex].strokes += 1
        recomputeTotals()
        sendStrokeUpdate()
    }

    /// Set the number of putts for the current hole.
    /// Automatically recalculates GIR after update.
    /// - Parameter count: Number of putts (must be >= 0).
    func setPutts(_ count: Int) {
        guard currentHole != nil, count >= 0 else { return }
        let oldPutts = round.holes[currentHoleIndex].putts
        let delta = count - oldPutts
        round.holes[currentHoleIndex].putts = count
        round.holes[currentHoleIndex].strokes += delta
        if round.holes[currentHoleIndex].strokes < 0 {
            round.holes[currentHoleIndex].strokes = 0
        }
        updateGIR()
        recomputeTotals()

        ConnectivityService.shared.sendStrokeUpdate(
            holeNumber: currentHoleNumber,
            strokes: round.holes[currentHoleIndex].strokes,
            putts: round.holes[currentHoleIndex].putts
        )
    }

    /// Move to the next hole, or complete the round if on the last hole.
    func endHole() {
        guard currentHoleIndex < round.holes.count - 1 else {
            round.endedAt = Date()
            isComplete = true
            return
        }
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
            ConnectivityService.shared.sendHoleData(
                hole: hole,
                holeNumber: holeNumber,
                courseName: course.name,
                totalStrokes: round.totalStrokes,
                totalHoles: course.holes.count
            )
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
    /// GIR = (strokes - putts) <= (par - 2)
    /// Means: reached green in regulation strokes (2 putts remaining on par or better)
    private func updateGIR() {
        guard currentHoleIndex < round.holes.count else { return }
        let hole = round.holes[currentHoleIndex]
        let gir = (hole.strokes - hole.putts) <= (hole.par - 2)
        round.holes[currentHoleIndex].gir = gir
    }
}
