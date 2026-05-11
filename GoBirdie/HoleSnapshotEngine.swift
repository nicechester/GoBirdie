//
//  HoleSnapshotEngine.swift
//  GoBirdie
//
//  Created on 2026-05-09.
//

import Foundation
import MapLibre
import CryptoKit
import UIKit
import GoBirdieCore

/// Actor that generates snapshot images of golf holes for watch display.
actor HoleSnapshotEngine {
    private static let imageQuality: CGFloat = 0.6

    /// Generate a snapshot image and metadata for a hole.
    /// - Parameters:
    ///   - hole: The hole to snapshot.
    ///   - styleURL: URL to the MapLibre style JSON.
    ///   - imageSize: Size of the output image in pixels.
    /// - Returns: Tuple of (image: UIImage, metadata: HoleSnapshotMetadata)
    func generate(
        for hole: Hole,
        styleURL: URL,
        imageSize: CGSize
    ) async throws -> (image: UIImage, metadata: HoleSnapshotMetadata) {
        guard let tee = hole.tee, let green = hole.greenCenter else {
            throw SnapshotError.missingCoordinates
        }

        // Compute bearing and zoom using same formula as map views
        let bearing = computeBearing(from: tee, to: green)
        let distance = tee.distanceMeters(to: green)
        let altitude = max(distance * 3.5, 200)

        // Convert altitude to proper MapLibre zoom level (0-20 range)
        // Formula: zoom = 18.2 - log2(altitude / 200)
        // Zoomed out (0.8 levels) to ensure full hole is visible with proper spacing
        let zoomLevel = 18.2 - log2(altitude / 200.0)

        print("=== SNAPSHOT GENERATION DEBUG ===")
        print("Hole #\(hole.number)")
        print("  Tee: lat=\(String(format: "%.6f", tee.lat)), lon=\(String(format: "%.6f", tee.lon))")
        print("  Green: lat=\(String(format: "%.6f", green.lat)), lon=\(String(format: "%.6f", green.lon))")
        print("  Distance: \(String(format: "%.1f", distance))m")
        print("  Altitude (calculated): \(String(format: "%.1f", altitude))m (formula: max(distance*3.5, 200))")
        print("  Bearing: \(String(format: "%.1f", bearing))°")
        print("  Zoom Level: \(String(format: "%.2f", zoomLevel)) (formula: 19 - log2(altitude/200))")
        print("  Image Size: \(imageSize.width)x\(imageSize.height)px")
        print("  Style URL: \(styleURL.absoluteString)")

        // Center on midpoint between tee and green
        let center = CLLocationCoordinate2D(
            latitude: (tee.lat + green.lat) / 2,
            longitude: (tee.lon + green.lon) / 2
        )
        let camera = MLNMapCamera(
            lookingAtCenter: center,
            altitude: 0,  // Altitude is overridden by zoomLevel below
            pitch: 0,
            heading: bearing
        )

        // Create snapshot options with proper zoom level
        let options = MLNMapSnapshotOptions(
            styleURL: styleURL,
            camera: camera,
            size: imageSize
        )
        options.zoomLevel = zoomLevel  // Use proper 0-20 zoom level, not altitude in meters

        print("  Camera created:")
        print("    Center: lat=\(String(format: "%.6f", camera.centerCoordinate.latitude)), lon=\(String(format: "%.6f", camera.centerCoordinate.longitude))")
        print("    Altitude (ignored due to zoomLevel): \(camera.altitude)m")
        print("    Pitch: \(camera.pitch)°")
        print("    Heading: \(camera.heading)°")
        print("  Options set:")
        print("    Zoom Level: \(options.zoomLevel) (overrides altitude)")
        print("    Size: \(options.size.width)x\(options.size.height)px")

        // Generate snapshot on main thread (MapLibre requirement)
        let snapshot: MLNMapSnapshot = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                print("  Starting snapshot generation on main thread...")
                let snapshotter = MLNMapSnapshotter(options: options)
                snapshotter.start { snapshot, error in
                    if let error = error {
                        print("  ❌ Snapshot generation failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else if let snapshot = snapshot {
                        print("  ✅ Snapshot generated successfully")
                        print("    Image size: \(snapshot.image.size.width)x\(snapshot.image.size.height)pt")
                        continuation.resume(returning: snapshot)
                    } else {
                        print("  ❌ Snapshot generation failed: no error but snapshot is nil")
                        continuation.resume(throwing: SnapshotError.snapshotFailed)
                    }
                }
            }
        }

        let image = snapshot.image
        print("=== END SNAPSHOT DEBUG ===\n")

        // Extract bounds by projecting corner pixels
        let bounds = extractBounds(from: snapshot, imageSize: imageSize)

        // Compute version hash
        let versionHash = computeVersionHash(tee: tee, green: green)

        // Save JPEG to Documents
        _ = try saveImage(image, holeNumber: hole.number, courseId: "default")

        // Create metadata
        let metadata = HoleSnapshotMetadata(
            holeNumber: hole.number,
            version: versionHash,
            bounds: bounds,
            imageWidthPx: Int(imageSize.width),
            imageHeightPx: Int(imageSize.height),
            bearingDegrees: bearing
        )

        return (image: image, metadata: metadata)
    }

    /// Compute bearing (heading) from tee to green using atan2.
    private func computeBearing(from tee: GpsPoint, to green: GpsPoint) -> Double {
        let dLat = green.lat - tee.lat
        let dLon = green.lon - tee.lon
        let bearing = atan2(dLon, dLat) * 180 / .pi
        // Normalize to 0-360
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    /// Extract SW and NE corner bounds from snapshot by projecting corner pixels.
    private func extractBounds(from snapshot: MLNMapSnapshot, imageSize: CGSize) -> HoleSnapshotMetadata.SnapshotBounds {
        // SW corner (bottom-left)
        let swPoint = CGPoint(x: 0, y: imageSize.height)
        let swCoord = snapshot.coordinate(for: swPoint)

        // NE corner (top-right)
        let nePoint = CGPoint(x: imageSize.width, y: 0)
        let neCoord = snapshot.coordinate(for: nePoint)

        return HoleSnapshotMetadata.SnapshotBounds(
            swLat: swCoord.latitude,
            swLon: swCoord.longitude,
            neLat: neCoord.latitude,
            neLon: neCoord.longitude
        )
    }

    /// Compute SHA-256 hash of tee + green coordinates.
    private func computeVersionHash(tee: GpsPoint, green: GpsPoint) -> String {
        let hashInput = "\(tee.lat),\(tee.lon),\(green.lat),\(green.lon)"
        let data = Data(hashInput.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Save JPEG to Documents/GoBirdie/watch_snapshots/{holeNumber}.jpg
    private func saveImage(_ image: UIImage, holeNumber: Int, courseId: String) throws -> String {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dirURL = documentsURL.appendingPathComponent("GoBirdie/watch_snapshots", isDirectory: true)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)

        let filename = "\(holeNumber).jpg"
        let fileURL = dirURL.appendingPathComponent(filename)

        guard let jpegData = image.jpegData(compressionQuality: Self.imageQuality) else {
            throw SnapshotError.jpegEncodingFailed
        }

        try jpegData.write(to: fileURL)
        return fileURL.path
    }

    enum SnapshotError: LocalizedError {
        case missingCoordinates
        case snapshotFailed
        case jpegEncodingFailed

        var errorDescription: String? {
            switch self {
            case .missingCoordinates:
                return "Hole missing tee or green coordinates"
            case .snapshotFailed:
                return "Failed to generate snapshot image"
            case .jpegEncodingFailed:
                return "Failed to encode JPEG"
            }
        }
    }
}
