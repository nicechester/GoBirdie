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
import CoreLocation
import CryptoKit
import GoBirdieCore
private let appStateLogger = Logger(subsystem: "com.gobirdie", category: "AppState")

// Helper function for debug logging that will show in Xcode console
private func debugLog(_ message: String) {
    os_log("[SNAPSHOT] %{public}@", log: .default, type: .debug, message)
    print("[SNAPSHOT-DEBUG] \(message)")
}

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
    @Published var sgBaseline: SGBaseline = SGBaseline(rawValue: UserDefaults.standard.string(forKey: "sgBaseline") ?? "") ?? .bogey {
        didSet { UserDefaults.standard.set(sgBaseline.rawValue, forKey: "sgBaseline") }
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
    private let weatherProvider = WeatherProvider.shared
    private var autoSaveTimer: Timer?
    private var idleTimer: Timer?
    @Published var showIdlePrompt = false
    @Published var isSavingRound = false
    @Published var teeDetectionHole: Int? = nil  // non-nil when phone should show prompt

    private var teeHitCounts: [Int: Int] = [:]   // hole number → consecutive hit count
    private var dismissedTees: Set<Int> = []

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
        NotificationCenter.default.addObserver(
            forName: .watchTeeDetectDismissed, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                if let hole = notification.userInfo?["holeNumber"] as? Int {
                    self?.dismissedTees.insert(hole)
                }
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
        guard activeRound == nil else { return }
        if let snapshot = inProgressStore.load() {
            print("[AppState] Found in-progress round: \(snapshot.round.courseName)")
            pendingResume = snapshot
        }
    }

    /// Resume a previously saved in-progress round.
    func resumeRound(snapshot: InProgressSnapshot) {
        os_log("[ENTRY-POINT] resumeRound CALLED", log: .default, type: .debug)
        debugLog("=== resumeRound() ENTERED ===")

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

        let viewModel = RoundViewModel(session: session, course: course, locationService: locationService, appState: self)
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

        // Compute course hash and trigger snapshot generation
        let courseHash = computeCourseHash(course: course)
        debugLog("resumeRound: computed courseHash: \(courseHash)")
        ConnectivityService.shared.sendRoundStartContext(versionHash: courseHash, courseId: course.id)

        // Fire async task to generate and transfer snapshots
        debugLog("resumeRound: creating background task for snapshot generation")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            debugLog("Background task (resume) EXECUTING")
            guard let self = self else {
                debugLog("ERROR: self was deallocated (resume)")
                return
            }
            Task {
                debugLog("Creating Task on background queue (resume)")
                await self.generateAndTransferSnapshots(course: course, courseHash: courseHash)
                debugLog("generateAndTransferSnapshots completed (resume)")
            }
        }

        startAutoSave()
        resetIdleTimer()
        pendingResume = nil
        NSLog("[AppState] Resumed round on hole %d", holeNumber)
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
        os_log("[ENTRY-POINT] startRound CALLED for course: %{public}@", log: .default, type: .debug, course.name)
        debugLog("=== startRound() ENTERED ===")

        // Create HoleScore structs for all 18 holes from course definition
        let holeScores = course.holes.map { hole in
            HoleScore(
                number: hole.number,
                par: hole.par,
                strokes: 0,
                putts: 0,
                fairwayHit: nil,
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
        let viewModel = RoundViewModel(session: session, course: course, locationService: locationService, appState: self)
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

        // Compute course hash and trigger snapshot generation
        let courseHash = computeCourseHash(course: course)
        debugLog("startRound: computed courseHash: \(courseHash)")
        ConnectivityService.shared.sendRoundStartContext(versionHash: courseHash, courseId: course.id)

        // Fire async task to generate and transfer snapshots
        debugLog("startRound: creating background task for snapshot generation")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            debugLog("Background task EXECUTING")
            guard let self = self else {
                debugLog("ERROR: self was deallocated")
                return
            }
            Task {
                debugLog("Creating Task on background queue")
                await self.generateAndTransferSnapshots(course: course, courseHash: courseHash)
                debugLog("generateAndTransferSnapshots completed")
            }
        }

        return session
    }

    /// End the active round, save it, and clean up.
    func endActiveRound(fromWatch: Bool = false) {
        guard let session = activeRound else { return }
        session.endRound()
        isSavingRound = true

        // Save round immediately — no waiting for weather
        do {
            try roundStore.save(session.round)
            print("[AppState] Round saved: \(session.round.id)")
        } catch {
            print("[AppState] Failed to save round: \(error)")
        }

        ConnectivityService.shared.sendRoundEnded()
        cleanupRound()

        // Fetch weather async and update saved round in background
        if let currentLocation = locationService.currentLocation {
            let roundId = session.round.id
            let coordinate = CLLocationCoordinate2D(
                latitude: currentLocation.lat,
                longitude: currentLocation.lon
            )
            Task { [weak self] in
                guard let self else { return }
                guard let weatherData = await self.weatherProvider.fetchCurrentWeather(location: coordinate) else { return }
                guard var saved = try? self.roundStore.load(id: roundId) else { return }
                saved.temperatureMinF = weatherData.minF
                saved.temperatureMaxF = weatherData.maxF
                saved.weatherCondition = weatherData.condition
                try? self.roundStore.save(saved)
                print("[AppState] Weather updated async: \(weatherData.minF)°F/\(weatherData.maxF)°F \(weatherData.condition)")
            }
        }
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

    func checkTeeProximity(location: GpsPoint, course: Course, currentHoleNumber: Int) {
        for hole in course.holes {
            guard let tee = hole.tee,
                  hole.number != currentHoleNumber,
                  hole.number > currentHoleNumber,
                  !dismissedTees.contains(hole.number) else { continue }
            let dist = distanceEngine.distanceYards(from: location, to: tee)
            if dist <= 3.28 {
                teeHitCounts[hole.number, default: 0] += 1
                if teeHitCounts[hole.number]! >= 3 {
                    teeHitCounts.removeAll()
                    if ConnectivityService.shared.isWatchReachable {
                        ConnectivityService.shared.sendTeeDetected(holeNumber: hole.number)
                    } else {
                        teeDetectionHole = hole.number
                    }
                }
                return
            } else {
                teeHitCounts[hole.number] = 0
            }
        }
    }

    func confirmTeeDetection(holeNumber: Int) {
        teeDetectionHole = nil
        guard let session = activeRound, let vm = activeRoundViewModel else { return }
        session.navigateTo(holeNumber: holeNumber, course: vm.course)
    }

    func dismissTeeDetection(holeNumber: Int) {
        teeDetectionHole = nil
        dismissedTees.insert(holeNumber)
    }

    private func cleanupRound() {
        stopAutoSave()
        idleTimer?.invalidate()
        idleTimer = nil
        showIdlePrompt = false
        isSavingRound = false
        teeDetectionHole = nil
        teeHitCounts.removeAll()
        dismissedTees.removeAll()
        inProgressStore.clear()

        if let courseId = activeRoundViewModel?.course.id {
            WatchSnapshotTransferManager.shared.clearCachedSnapshots(courseId: courseId)
        }

        activeRoundViewModel?.stopRound()
        activeRound = nil
        activeRoundViewModel = nil
    }

    /// Get the current location service (for testing or advanced usage).
    func getLocationService() -> LocationService {
        locationService
    }

    // MARK: - Snapshot Generation

    /// Compute hash for a course based on all hole coordinates.
    private func computeCourseHash(course: Course) -> String {
        let coordStrings = course.holes.compactMap { hole in
            guard let tee = hole.tee, let green = hole.greenCenter else { return nil }
            return "\(tee.lat),\(tee.lon),\(green.lat),\(green.lon)"
        }.joined(separator: "|")

        let data = Data(coordStrings.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate snapshots for all holes and transfer them to the watch.
    private func generateAndTransferSnapshots(course: Course, courseHash: String) async {
        debugLog("generateAndTransferSnapshots STARTED for course: \(course.name) hash: \(courseHash)")
        let engine = HoleSnapshotEngine()

        // Get style URL from resources
        guard let styleURL = Bundle.main.url(forResource: "watch_snapshot_style", withExtension: "json") else {
            debugLog("ERROR: Could not find watch_snapshot_style.json")
            return
        }

        let imageSize = CGSize(width: 272, height: 340) // Typical watch screen size
        debugLog("Starting snapshot generation for \(course.holes.count) holes")

        var generatedCount = 0
        for hole in course.holes {
            do {
                debugLog("Generating snapshot for hole \(hole.number)...")
                let (image, metadata) = try await engine.generate(
                    for: hole,
                    styleURL: styleURL,
                    imageSize: imageSize
                )
                debugLog("Generated snapshot for hole \(hole.number), saving metadata...")

                // Save metadata JSON alongside image
                try saveSnapshotMetadata(metadata, holeNumber: hole.number)
                generatedCount += 1
                debugLog("Completed hole \(hole.number) (\(generatedCount)/\(course.holes.count))")
            } catch {
                debugLog("ERROR: Failed to generate snapshot for hole \(hole.number): \(error)")
            }
        }

        debugLog("Completed snapshot generation: \(generatedCount) of \(course.holes.count) holes")

        // After all snapshots generated, transfer them
        let startingHoleNumber = self.activeRound?.currentHoleNumber ?? 1
        debugLog("Starting file transfers for \(course.holes.count) holes, starting with hole \(startingHoleNumber)")
        await WatchSnapshotTransferManager.shared.transferAllHoles(
            for: course,
            courseId: course.id,
            versionHash: courseHash
        )
        WatchSnapshotTransferManager.shared.prioritizeHole(
            startingHoleNumber,
            courseId: course.id
        )
        debugLog("File transfer requests submitted to WatchConnectivity")
    }

    /// Save snapshot metadata JSON file.
    private func saveSnapshotMetadata(_ metadata: HoleSnapshotMetadata, holeNumber: Int) throws {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dirURL = documentsURL.appendingPathComponent("GoBirdie/watch_snapshots", isDirectory: true)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)

        let filename = "\(holeNumber).json"
        let fileURL = dirURL.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(metadata)
        try jsonData.write(to: fileURL)

        debugLog("Saved metadata for hole \(holeNumber) at \(fileURL.path)")
    }
}
