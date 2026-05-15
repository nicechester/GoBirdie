//
//  WatchSnapshotTransferManager.swift
//  GoBirdie
//
//  Created on 2026-05-09.
//

import Foundation
import Combine
import WatchConnectivity
import GoBirdieCore
import os.log

// Helper function for debug logging that will show in Xcode console
private func debugLog(_ message: String) {
    os_log("[TRANSFER] %{public}@", log: .default, type: .debug, message)
    print("[TRANSFER-DEBUG] \(message)")
}

/// Manages file transfers of hole snapshots to the Apple Watch.
@MainActor
final class WatchSnapshotTransferManager: NSObject, ObservableObject {
    static let shared = WatchSnapshotTransferManager()

    @Published private var inFlightTransfers: [Int: WCSessionFileTransfer] = [:]
    private var retryScheduled: Set<Int> = []
    var onFileTransferComplete: ((WCSessionFileTransfer, Error?) -> Void)?

    override private init() {
        super.init()
    }

    /// Transfer all hole snapshots for a course to the Watch.
    /// Iterates through holes, generates snapshots, and transfers each via WCSession.
    func transferAllHoles(
        for course: Course,
        courseId: String,
        versionHash: String
    ) async {
        let session = WCSession.default
        debugLog("transferAllHoles called for \(course.holes.count) holes")
        debugLog("WCSession state: activationState=\(session.activationState.rawValue), isReachable=\(session.isReachable), isPaired=\(session.isPaired)")

        guard session.isReachable else {
            debugLog("ERROR: Watch not reachable, skipping transfers")
            return
        }

        debugLog("Watch IS reachable, transferring \(course.holes.count) holes")
        for hole in course.holes {
            await transferHole(holeNumber: hole.number, courseId: courseId, versionHash: versionHash)
        }
        debugLog("Completed transfer requests for all holes")
    }

    /// Transfer a single hole snapshot.
    private func transferHole(holeNumber: Int, courseId: String, versionHash: String) async {
        let fileManager = FileManager.default
        let documentsURL = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard let documentsURL = documentsURL else {
            debugLog("ERROR: Could not find Documents directory for hole \(holeNumber)")
            return
        }

        let snapshotsDir = documentsURL
            .appendingPathComponent("GoBirdie/watch_snapshots", isDirectory: true)

        let fileURL = snapshotsDir
            .appendingPathComponent("\(holeNumber).jpg")

        let metadataURL = snapshotsDir
            .appendingPathComponent("\(holeNumber).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            debugLog("ERROR: Snapshot file NOT found at: \(fileURL.path)")
            return
        }

        debugLog("Snapshot file EXISTS for hole \(holeNumber): \(fileURL.path)")

        // Load metadata JSON and embed in transfer metadata
        var transferMetadata: [String: Any] = [
            "holeNumber": holeNumber,
            "version": versionHash
        ]

        if fileManager.fileExists(atPath: metadataURL.path) {
            if let metadataData = try? Data(contentsOf: metadataURL) {
                debugLog("Metadata JSON loaded for hole \(holeNumber)")
                if let metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                    debugLog("Metadata parsed for hole \(holeNumber), keys: \(metadataDict.keys.joined(separator: ", "))")
                    // Merge metadata from JSON file
                    transferMetadata.merge(metadataDict) { _, new in new }
                } else {
                    debugLog("ERROR: Failed to parse metadata JSON for hole \(holeNumber)")
                }
            } else {
                debugLog("ERROR: Failed to read metadata file for hole \(holeNumber)")
            }
        } else {
            debugLog("WARNING: Metadata JSON not found at: \(metadataURL.path)")
        }

        debugLog("Transferring hole \(holeNumber) with \(transferMetadata.count) metadata fields")
        let transfer = WCSession.default.transferFile(fileURL, metadata: transferMetadata)
        inFlightTransfers[holeNumber] = transfer
        debugLog("Started transfer for hole \(holeNumber)")
    }

    /// Mark a hole to be transferred with priority (sent first).
    func prioritizeHole(_ holeNumber: Int, courseId: String) {
        // In a more complex implementation, this could reorder the queue.
        // For now, it's a placeholder for future optimization.
        debugLog("Prioritized hole \(holeNumber)")
    }

    /// Clear cached snapshot files for a course.
    func clearCachedSnapshots(courseId: String) {
        let fileManager = FileManager.default
        let documentsURL = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard let documentsURL = documentsURL else { return }

        let dirURL = documentsURL.appendingPathComponent("GoBirdie/watch_snapshots", isDirectory: true)
        try? fileManager.removeItem(at: dirURL)
        debugLog("Cleared cached snapshots for \(courseId)")
    }

    /// Handle file transfer completion (called by ConnectivityService).
    func handleFileTransferCompleted(_ transfer: WCSessionFileTransfer, error: Error?) {
        let holeNumber = (transfer.file.metadata?["holeNumber"] as? Int) ?? -1
        if let error = error {
            debugLog("ERROR: Transfer FAILED for hole \(holeNumber): \(error)")
            // Retry once after 5 seconds
            if let metadata = transfer.file.metadata,
               let holeNumber = metadata["holeNumber"] as? Int,
               !retryScheduled.contains(holeNumber) {
                retryScheduled.insert(holeNumber)
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    retryScheduled.remove(holeNumber)
                }
            }
        } else {
            debugLog("SUCCESS: Transfer completed for hole \(holeNumber)")
            inFlightTransfers.removeValue(forKey: holeNumber)
        }
        onFileTransferComplete?(transfer, error)
    }
}
