//
//  AppState.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import Combine
import UIKit
import OSLog
import GoBirdieCore

private let appStateLogger = Logger(subsystem: "com.gobirdie", category: "AppState")

/// Manages global app state and round lifecycle.
/// Handles auto-detection of starting hole and creation of new rounds.
@MainActor
final class AppState: ObservableObject {
    @Published var activeRound: RoundSession?
    @Published var activeRoundViewModel: RoundViewModel?
    @Published var selectedTab: Int = 1
    @Published var pendingResume: InProgressSnapshot?
    @Published var teeColor: String = UserDefaults.standard.string(forKey: "teeColor") ?? "Blue" {
        didSet { UserDefaults.standard.set(teeColor, forKey: "teeColor") }
    }
    @Published var syncServerEnabled: Bool = false {
        didSet {
            if syncServerEnabled {
                syncServer.start()
                syncServerRunning = true
            } else {
                syncServer.stop()
                syncServerRunning = false
            }
            UserDefaults.standard.set(syncServerEnabled, forKey: "syncServerEnabled")
        }
    }
    @Published var syncServerRunning: Bool = false

    private let locationService = LocationService()
    private let distanceEngine = DistanceEngine()
    private let inProgressStore = InProgressStore()
    private let roundStore = RoundStore()
    private let syncServer: SyncServer
    private var autoSaveTimer: Timer?
    private var idleTimer: Timer?
    @Published var showIdlePrompt = false

    init() {
        syncServer = SyncServer(roundStore: roundStore)
        syncServer.onStateChange = { [weak self] running in
            appStateLogger.info("onStateChange callback: running=\(running)")
            if !running {
                Task { @MainActor [weak self] in
                    self?.syncServerRunning = false
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .watchEndRound, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                if let timeline = notification.userInfo?["heartRateTimeline"] as? [[String: Any]],
                   let session = self?.activeRound {
                    session.round.heartRateTimeline = timeline.compactMap { dict in
                        guard let ts = dict["timestamp"] as? Double,
                              let bpm = dict["bpm"] as? Int else { return nil }
                        return HeartRateSample(
                            timestamp: Date(timeIntervalSince1970: ts),
                            bpm: bpm,
                            altitudeMeters: dict["altitude"] as? Double
                        )
                    }
                }
                self?.endActiveRound(fromWatch: true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .watchCancelRound, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelActiveRound(fromWatch: true)
            }
        }
    }

    // MARK: - Sync Server

    func startSyncServer() {
        appStateLogger.info("startSyncServer() called")
        syncServer.start()
        syncServerRunning = true
    }

    func stopSyncServer() {
        appStateLogger.info("stopSyncServer() called")
        syncServer.stop()
        syncServerRunning = false
    }

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

    // MARK: - Resume

    /// Check for an in-progress round on launch.
    func checkForInProgressRound() {
        if let snapshot = inProgressStore.load() {
            print("[AppState] Found in-progress round: \(snapshot.round.courseName)")
            pendingResume = snapshot
        }
    }

    /// Resume a previously saved in-progress round.
    func resumeRound(snapshot: InProgressSnapshot) {
        let courseStore = CourseStore()
        guard let course = try? courseStore.load(id: snapshot.courseId) else {
            print("[AppState] Cannot resume — course \(snapshot.courseId) not found")
            inProgressStore.clear()
            pendingResume = nil
            return
        }

        let session = RoundSession(round: snapshot.round, startingHoleIndex: snapshot.currentHoleIndex)
        self.activeRound = session
        self.selectedTab = 1

        let viewModel = RoundViewModel(session: session, course: course, locationService: locationService)
        self.activeRoundViewModel = viewModel
        viewModel.startRound()

        // Notify Watch of resumed hole
        let holeNumber = snapshot.currentHoleIndex + 1
        if let hole = course.holes.first(where: { $0.number == holeNumber }) {
            ConnectivityService.shared.sendHoleData(
                hole: hole,
                holeNumber: holeNumber,
                courseName: course.name,
                totalStrokes: session.round.totalStrokes,
                totalHoles: course.holes.count
            )
        }

        startAutoSave()
        resetIdleTimer()
        pendingResume = nil
        print("[AppState] Resumed round on hole \(holeNumber)")
    }

    /// Discard the saved in-progress round.
    func discardInProgressRound() {
        inProgressStore.clear()
        pendingResume = nil
    }

    // MARK: - Auto-save

    /// Save current round state to disk.
    func saveInProgress() {
        guard let session = activeRound,
              let vm = activeRoundViewModel else { return }
        let snapshot = InProgressSnapshot(
            round: session.round,
            courseId: vm.course.id,
            currentHoleIndex: session.currentHoleIndex
        )
        try? inProgressStore.save(snapshot)
    }

    private func startAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveInProgress()
            }
        }
    }

    private func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    // MARK: - Start Round

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
                shots: [],
                greenCenter: hole.greenCenter
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

        startAutoSave()
        resetIdleTimer()

        // Notify Watch of round start with initial hole coordinates
        if let startingHole = course.holes.first(where: { $0.number == startingHoleNumber }) {
            ConnectivityService.shared.sendHoleData(
                hole: startingHole,
                holeNumber: startingHoleNumber,
                courseName: course.name,
                totalStrokes: 0,
                totalHoles: course.holes.count
            )
        }

        return session
    }

    /// End the active round, save it, and clean up.
    func endActiveRound(fromWatch: Bool = false) {
        guard let session = activeRound else { return }
        session.endRound()

        do {
            try roundStore.save(session.round)
            print("[AppState] Round saved: \(session.round.id)")
        } catch {
            print("[AppState] Failed to save round: \(error)")
        }

        if !fromWatch {
            ConnectivityService.shared.sendRoundEnded()
        }
        cleanupRound()
    }

    /// Cancel the active round without saving.
    func cancelActiveRound(fromWatch: Bool = false) {
        if !fromWatch {
            ConnectivityService.shared.sendRoundCancelled()
        }
        cleanupRound()
    }

    /// Reset the idle timer — call on any user interaction during a round.
    func resetIdleTimer() {
        idleTimer?.invalidate()
        showIdlePrompt = false
        guard activeRound != nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showIdlePrompt = true
            }
        }
    }

    private func cleanupRound() {
        stopAutoSave()
        idleTimer?.invalidate()
        idleTimer = nil
        showIdlePrompt = false
        inProgressStore.clear()
        activeRoundViewModel?.stopRound()
        activeRound = nil
        activeRoundViewModel = nil
    }

    /// Get the current location service (for testing or advanced usage).
    func getLocationService() -> LocationService {
        locationService
    }
}
