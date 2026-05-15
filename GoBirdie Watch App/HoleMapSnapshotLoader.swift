//
//  HoleMapSnapshotLoader.swift
//  GoBirdie Watch App
//

import SwiftUI

struct HoleMapSnapshot {
    let holeNumber: Int
    let image: UIImage?
    let data: [String: Any]?
}

final class HoleMapSnapshotLoader {
    static let shared = HoleMapSnapshotLoader()

    private var cachedSnapshots: [Int: HoleMapSnapshot] = [:]

    private init() {}

    func isEnabled() -> Bool {
        #if USE_STATIC_HOLE_MAPS
        return true
        #else
        return false
        #endif
    }

    func loadSnapshot(for holeNumber: Int) -> HoleMapSnapshot? {
        #if USE_STATIC_HOLE_MAPS
        if let cached = cachedSnapshots[holeNumber] {
            return cached
        }

        let snapshot = HoleMapSnapshot(
            holeNumber: holeNumber,
            image: loadImage(for: holeNumber),
            data: loadJSON(for: holeNumber)
        )
        cachedSnapshots[holeNumber] = snapshot
        return snapshot
        #else
        return nil
        #endif
    }

    private func loadImage(for holeNumber: Int) -> UIImage? {
        #if USE_STATIC_HOLE_MAPS
        let filename = "\(holeNumber).jpg"

        // Snapshots are in the root of the bundle (not in a subdirectory)
        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil),
           let data = try? Data(contentsOf: bundleURL),
           let image = UIImage(data: data) {
            print("[HoleMapSnapshotLoader] ✓ Loaded image for hole \(holeNumber)")
            return image
        }

        print("[HoleMapSnapshotLoader] ✗ Failed to load image for hole \(holeNumber)")
        return nil
        #else
        return nil
        #endif
    }

    private func loadJSON(for holeNumber: Int) -> [String: Any]? {
        #if USE_STATIC_HOLE_MAPS
        let filename = "\(holeNumber).json"

        // Snapshots are in the root of the bundle (not in a subdirectory)
        guard let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil),
              let data = try? Data(contentsOf: bundleURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
        #else
        return nil
        #endif
    }

    func clearCache() {
        cachedSnapshots.removeAll()
    }
}
