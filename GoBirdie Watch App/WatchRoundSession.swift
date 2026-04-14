//
//  WatchRoundSession.swift
//  GoBirdie Watch App

import Foundation
import CoreLocation
import WatchConnectivity
import HealthKit
import Combine

@MainActor
final class WatchRoundSession: NSObject, ObservableObject {
    @Published var holeNumber: Int = 1
    @Published var par: Int = 4
    @Published var strokes: Int = 0
    @Published var putts: Int = 0
    @Published var frontYards: Int?
    @Published var pinYards: Int?
    @Published var backYards: Int?
    @Published var isActive: Bool = false
    @Published var hasHoleData: Bool = false
    @Published var courseName: String = ""
    @Published var latestHeartRate: Int?

    private var greenFront: CLLocation?
    private var greenCenter: CLLocation?
    private var greenBack: CLLocation?
    private var currentLocation: CLLocation?

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    override init() {
        super.init()
        setupConnectivity()
        setupLocationManager()
    }

    // MARK: - Public API

    func markShot() {
        strokes += 1
        sendShotToPhone()
    }

    func addStroke() {
        strokes += 1
        sendStrokesToPhone()
    }

    func addPutt() {
        putts += 1
        strokes += 1
        sendStrokesToPhone()
    }

    func removePutt() {
        guard putts > 0 else { return }
        putts -= 1
        strokes -= 1
        sendStrokesToPhone()
    }

    func previousHole() {
        guard holeNumber > 1 else { return }
        holeNumber -= 1
        strokes = 0
        requestHoleFromPhone()
    }

    func nextHole() {
        guard holeNumber < 18 else { return }
        holeNumber += 1
        strokes = 0
        requestHoleFromPhone()
    }

    func startWorkout() {
        guard !isActive else { return }
        isActive = true
        locationManager.startUpdatingLocation()

        // HKWorkoutSession is optional — keeps GPS alive in background
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.requestAuthorization(toShare: [HKQuantityType.workoutType()], read: []) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                self.startHKSession()
            }
        }
    }

    private func startHKSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            builder.delegate = self
            self.workoutSession = session
            self.workoutBuilder = builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
        } catch {
            print("[Watch] HKWorkoutSession failed: \(error) — GPS still active")
        }
    }

    func endWorkout() {
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { _, _ in }
        workoutBuilder?.finishWorkout { _, _ in }
        locationManager.stopUpdatingLocation()
        isActive = false
    }

    // MARK: - Distance Computation

    private func recomputeDistances() {
        guard let loc = currentLocation else { return }

        if let front = greenFront {
            frontYards = Int((loc.distance(from: front) * 1.09361).rounded())
        }
        if let center = greenCenter {
            pinYards = Int((loc.distance(from: center) * 1.09361).rounded())
        }
        if let back = greenBack {
            backYards = Int((loc.distance(from: back) * 1.09361).rounded())
        }
    }

    // MARK: - Location

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Watch Connectivity

    private func setupConnectivity() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func sendShotToPhone() {
        guard WCSession.default.isReachable else { return }
        var msg: [String: Any] = [
            "action": "shot",
            "holeNumber": holeNumber,
            "strokes": strokes,
            "putts": putts
        ]
        if let loc = currentLocation {
            msg["lat"] = loc.coordinate.latitude
            msg["lon"] = loc.coordinate.longitude
            if loc.verticalAccuracy >= 0 {
                msg["altitude"] = loc.altitude
            }
        }
        if let hr = latestHeartRate {
            msg["heartRate"] = hr
        }
        WCSession.default.sendMessage(msg, replyHandler: nil)
    }

    private func sendStrokesToPhone() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "stroke", "holeNumber": holeNumber, "strokes": strokes, "putts": putts],
            replyHandler: nil
        )
    }

    private func requestHoleFromPhone() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["action": "requestHole", "holeNumber": holeNumber],
            replyHandler: nil
        )
    }

    private func handleContext(_ context: [String: Any]) {
        if let hole = context["holeNumber"] as? Int {
            holeNumber = hole
        }
        if let p = context["par"] as? Int {
            par = p
        }
        if let name = context["courseName"] as? String {
            courseName = name
        }

        if let lat = context["front_lat"] as? Double, let lon = context["front_lon"] as? Double {
            greenFront = CLLocation(latitude: lat, longitude: lon)
        }
        if let lat = context["green_lat"] as? Double, let lon = context["green_lon"] as? Double {
            greenCenter = CLLocation(latitude: lat, longitude: lon)
        }
        if let lat = context["back_lat"] as? Double, let lon = context["back_lon"] as? Double {
            greenBack = CLLocation(latitude: lat, longitude: lon)
        }

        strokes = 0
        putts = 0
        hasHoleData = true
        recomputeDistances()

        // Auto-start workout when we receive hole data from iPhone
        if !isActive {
            startWorkout()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchRoundSession: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = loc
            self.recomputeDistances()
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchRoundSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleContext(message)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchRoundSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let value = stats.mostRecentQuantity() else { return }
        let bpm = Int(value.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in
            self.latestHeartRate = bpm
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
