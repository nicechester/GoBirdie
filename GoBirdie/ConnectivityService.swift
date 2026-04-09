//
//  ConnectivityService.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import Combine
import WatchConnectivity
import GoBirdieCore

/// Manages WatchConnectivity communication between iPhone and Watch.
/// Sends hole coordinates and round data to Watch for display.
@MainActor
final class ConnectivityService: NSObject, ObservableObject {
    static let shared = ConnectivityService()

    @Published var isWatchAvailable: Bool = false

    private let session = WCSession.default

    override init() {
        super.init()
        setupWatchConnectivity()
    }

    // MARK: - Public API

    /// Send the current hole's coordinates to the Watch.
    /// - Parameters:
    ///   - hole: The Hole data to send.
    ///   - holeNumber: The hole number (1-18).
    func sendHoleCoordinates(_ hole: Hole, holeNumber: Int) {
        guard session.isPaired && session.isWatchAppInstalled else { return }

        var context: [String: Any] = [
            "holeNumber": holeNumber,
            "par": hole.par,
        ]

        if let tee = hole.tee {
            context["tee_lat"] = tee.lat
            context["tee_lon"] = tee.lon
        }

        if let greenCenter = hole.greenCenter {
            context["green_lat"] = greenCenter.lat
            context["green_lon"] = greenCenter.lon
        }

        if let greenFront = hole.greenFront {
            context["front_lat"] = greenFront.lat
            context["front_lon"] = greenFront.lon
        }

        if let greenBack = hole.greenBack {
            context["back_lat"] = greenBack.lat
            context["back_lon"] = greenBack.lon
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("[ConnectivityService] Failed to send hole coordinates: \(error.localizedDescription)")
        }
    }

    /// Send round summary to the Watch.
    /// - Parameters:
    ///   - courseName: The name of the course.
    ///   - holesPlayed: Number of holes completed.
    ///   - totalStrokes: Total strokes so far.
    func sendRoundSummary(courseName: String, holesPlayed: Int, totalStrokes: Int) {
        guard session.isPaired && session.isWatchAppInstalled else { return }

        let context: [String: Any] = [
            "courseName": courseName,
            "holesPlayed": holesPlayed,
            "totalStrokes": totalStrokes,
        ]

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("[ConnectivityService] Failed to send round summary: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }

        session.delegate = self
        session.activate()
    }
}

// MARK: - WCSessionDelegate

extension ConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchAvailable = activationState == .activated && session.isPaired
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchAvailable = false
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchAvailable = false
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // Handle incoming messages from Watch if needed
    }
}
