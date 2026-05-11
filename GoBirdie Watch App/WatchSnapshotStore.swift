//
//  WatchSnapshotStore.swift
//  GoBirdie Watch App
//
//  Created on 2026-05-09.
//

import Foundation
import SwiftUI
import Combine
import GoBirdieCore
import os.log

// Helper function for debug logging that will show in Xcode console
private func debugLog(_ message: String) {
    os_log("[WATCH-SNAPSHOT] %{public}@", log: .default, type: .debug, message)
    print("[WATCH-SNAPSHOT-DEBUG] \(message)")
}

/// Manages hole snapshot storage and retrieval on the watch.
@MainActor
final class WatchSnapshotStore: ObservableObject {
    static let shared = WatchSnapshotStore()

    @Published var snapshots: [Int: Data] = [:]
    @Published var metadata: [Int: HoleSnapshotMetadata] = [:]

    private init() {}

    /// Receive a snapshot file transferred from iOS.
    /// This receives the file URL and metadata from WCSession's file transfer callback.
    func receive(fileURL: URL, metadata: [String: Any]?) {
        print("[Watch-Store] receive() fileURL=\(fileURL.path)")
        print("[Watch-Store] fileExists=\(FileManager.default.fileExists(atPath: fileURL.path))")

        guard let metadata = metadata else {
            print("[Watch-Store] ERROR: metadata is nil")
            return
        }

        print("[Watch-Store] metadata keys=\(metadata.keys.sorted().joined(separator: ", "))")
        print("[Watch-Store] metadata values=\(metadata)")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            print("[Watch-Store] JSONSerialization succeeded, jsonData size=\(jsonData.count)")
            if let jsonStr = String(data: jsonData, encoding: .utf8) {
                print("[Watch-Store] JSON=\(jsonStr)")
            }

            let snapshotMetadata = try JSONDecoder().decode(HoleSnapshotMetadata.self, from: jsonData)
            let holeNumber = snapshotMetadata.holeNumber
            print("[Watch-Store] decoded holeNumber=\(holeNumber) version=\(snapshotMetadata.version)")

            guard let imageData = try? Data(contentsOf: fileURL) else {
                print("[Watch-Store] ERROR: failed to read image data from \(fileURL.path)")
                return
            }
            print("[Watch-Store] imageData size=\(imageData.count) bytes")

            snapshots[holeNumber] = imageData
            self.metadata[holeNumber] = snapshotMetadata

            try saveSnapshot(imageData, holeNumber: holeNumber)
            print("[Watch-Store] SUCCESS: stored hole \(holeNumber), total snapshots=\(snapshots.count)")
        } catch {
            print("[Watch-Store] ERROR: \(error)")
        }
    }

    /// Get snapshot image data for a hole.
    func image(for holeNumber: Int) -> Data? {
        snapshots[holeNumber]
    }

    /// Get metadata for a hole.
    func metadata(for holeNumber: Int) -> HoleSnapshotMetadata? {
        metadata[holeNumber]
    }

    /// Load bundled test snapshots from the app bundle (simulator only).
    #if targetEnvironment(simulator)
    func loadBundledSnapshots() {
        let bundle = Bundle.main
        // Find all snapshot_hole_N.jpg files in the bundle
        let imageURLs = bundle.urls(forResourcesWithExtension: "jpg", subdirectory: nil)?
            .filter { $0.lastPathComponent.hasPrefix("snapshot_hole_") } ?? []

        print("[Watch-Store-SIM] loadBundledSnapshots found \(imageURLs.count) images")

        for imageURL in imageURLs {
            // Derive hole number from filename: snapshot_hole_1.jpg -> 1
            let stem = imageURL.deletingPathExtension().lastPathComponent
            guard let holeNumber = Int(stem.replacingOccurrences(of: "snapshot_hole_", with: "")) else {
                print("[Watch-Store-SIM] skipping unrecognised filename: \(stem)")
                continue
            }

            guard let metadataURL = bundle.url(forResource: "snapshot_hole_\(holeNumber)", withExtension: "json"),
                  let metadataData = try? Data(contentsOf: metadataURL),
                  let snapshotMetadata = try? JSONDecoder().decode(HoleSnapshotMetadata.self, from: metadataData)
            else {
                print("[Watch-Store-SIM] missing or invalid metadata for hole \(holeNumber)")
                continue
            }

            guard let imageData = try? Data(contentsOf: imageURL) else {
                print("[Watch-Store-SIM] failed to load image for hole \(holeNumber)")
                continue
            }

            snapshots[holeNumber] = imageData
            metadata[holeNumber] = snapshotMetadata
            print("[Watch-Store-SIM] loaded hole \(holeNumber) (\(imageData.count) bytes)")
        }
    }
    #endif

    /// Clear all snapshots from memory.
    func clearAll() {
        snapshots.removeAll()
        metadata.removeAll()
    }

    /// Clear snapshots if version hash doesn't match.
    func clearIfVersionMismatch(expected: String) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirURL = documentsURL.appendingPathComponent("GoBirdie/watch_snapshots", isDirectory: true)

        // If directory doesn't exist yet, nothing to clear
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            for file in files {
                if let _ = try? Data(contentsOf: file) {
                    // Check if we have metadata for this file
                    let filename = file.lastPathComponent
                    let holeNumberStr = filename.dropLast(4) // Remove .jpg
                    if let holeNumber = Int(holeNumberStr),
                       let meta = metadata[holeNumber],
                       meta.version != expected {
                        snapshots.removeValue(forKey: holeNumber)
                        self.metadata.removeValue(forKey: holeNumber)
                        try? FileManager.default.removeItem(at: file)
                        debugLog("[WatchSnapshotStore] Deleted hole \(holeNumber) (version mismatch)")
                    }
                }
            }
        } catch {
            debugLog("[WatchSnapshotStore] Error clearing version mismatches: \(error)")
        }
    }

    private func saveSnapshot(_ imageData: Data, holeNumber: Int) throws {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dirURL = documentsURL.appendingPathComponent("GoBirdie/watch_snapshots", isDirectory: true)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)

        let fileURL = dirURL.appendingPathComponent("\(holeNumber).jpg")
        try imageData.write(to: fileURL)
    }
}
