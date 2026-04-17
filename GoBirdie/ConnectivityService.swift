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

@MainActor
final class ConnectivityService: NSObject, ObservableObject {
    static let shared = ConnectivityService()

    @Published var isWatchAvailable: Bool = false

    private let session = WCSession.default

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Send hole + round data to Watch as a single context.
    func sendRoundEnded() {
        send(["action": "roundEnded"])
    }

    func sendRoundCancelled() {
        send(["action": "roundCancelled"])
    }

    /// Send hole + round data to Watch as a single context.
    func sendHoleData(hole: Hole, holeNumber: Int, courseName: String, totalStrokes: Int, totalHoles: Int = 18) {
        var ctx: [String: Any] = [
            "holeNumber": holeNumber,
            "par": hole.par,
            "courseName": courseName,
            "totalStrokes": totalStrokes,
            "totalHoles": totalHoles,
            "clubBag": ClubBag.shared.enabledClubs.map(\.rawValue),
        ]

        if let tee = hole.tee {
            ctx["tee_lat"] = tee.lat
            ctx["tee_lon"] = tee.lon
        }
        if let gc = hole.greenCenter {
            ctx["green_lat"] = gc.lat
            ctx["green_lon"] = gc.lon
        }
        if let gf = hole.greenFront {
            ctx["front_lat"] = gf.lat
            ctx["front_lon"] = gf.lon
        }
        if let gb = hole.greenBack {
            ctx["back_lat"] = gb.lat
            ctx["back_lon"] = gb.lon
        }

        send(ctx)
    }


    private func send(_ ctx: [String: Any]) {
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        // Always persist to applicationContext so Watch gets it on launch
        do {
            try session.updateApplicationContext(ctx)
        } catch {
            print("[Connectivity] updateApplicationContext failed: \(error)")
        }
        // Also sendMessage for immediate delivery if Watch is reachable
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { error in
                print("[Connectivity] sendMessage failed: \(error)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension ConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isWatchAvailable = state == .activated
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.isWatchAvailable = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in self.isWatchAvailable = false }
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleWatchMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleWatchMessage(applicationContext)
        }
    }

    private func handleWatchMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }

        switch action {
        case "stroke":
            if let holeNumber = message["holeNumber"] as? Int,
               let strokes = message["strokes"] as? Int {
                var info: [String: Any] = ["holeNumber": holeNumber, "strokes": strokes]
                if let putts = message["putts"] as? Int {
                    info["putts"] = putts
                }
                NotificationCenter.default.post(
                    name: .watchStrokeUpdate,
                    object: nil,
                    userInfo: info
                )
            }
        case "navigate":
            if let holeNumber = message["holeNumber"] as? Int {
                NotificationCenter.default.post(
                    name: .watchNavigateHole,
                    object: nil,
                    userInfo: ["holeNumber": holeNumber]
                )
            }
        case "endRound":
            var info: [String: Any] = [:]
            if let timeline = message["heartRateTimeline"] as? [[String: Any]] {
                info["heartRateTimeline"] = timeline
            }
            NotificationCenter.default.post(name: .watchEndRound, object: nil, userInfo: info.isEmpty ? nil : info)
        case "cancelRound":
            NotificationCenter.default.post(name: .watchCancelRound, object: nil)
        case "clubSelection":
            if let holeNumber = message["holeNumber"] as? Int,
               let clubRaw = message["club"] as? String {
                NotificationCenter.default.post(
                    name: .watchClubSelection,
                    object: nil,
                    userInfo: ["holeNumber": holeNumber, "club": clubRaw]
                )
            }
        case "shot":
            if let holeNumber = message["holeNumber"] as? Int {
                var info: [String: Any] = ["holeNumber": holeNumber]
                if let strokes = message["strokes"] as? Int { info["strokes"] = strokes }
                if let putts = message["putts"] as? Int { info["putts"] = putts }
                if let lat = message["lat"] as? Double, let lon = message["lon"] as? Double {
                    info["lat"] = lat
                    info["lon"] = lon
                }
                if let alt = message["altitude"] as? Double { info["altitude"] = alt }
                if let hr = message["heartRate"] as? Int { info["heartRate"] = hr }
                NotificationCenter.default.post(
                    name: .watchShotMarked,
                    object: nil,
                    userInfo: info
                )
            }
        default:
            break
        }
    }
}

extension Notification.Name {
    static let watchStrokeUpdate = Notification.Name("watchStrokeUpdate")
    static let watchShotMarked = Notification.Name("watchShotMarked")
    static let watchNavigateHole = Notification.Name("watchNavigateHole")
    static let watchEndRound = Notification.Name("watchEndRound")
    static let watchCancelRound = Notification.Name("watchCancelRound")
    static let watchClubSelection = Notification.Name("watchClubSelection")
}
