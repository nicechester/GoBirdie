//
//  WatchMapView.swift
//  GoBirdie Watch App
//
//  Created on 2026-05-09.
//

import SwiftUI
import WatchKit
import CoreLocation
import GoBirdieCore

/// Displays a snapshot map of the current hole with GPS position overlay.
struct WatchMapView: View {
    @EnvironmentObject var session: WatchRoundSession
    @EnvironmentObject var snapshotStore: WatchSnapshotStore
    @Binding var showMapPage: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let _ = print("[Watch-MapView] render hole=\(session.holeNumber) snapshotCount=\(snapshotStore.snapshots.count) hasImage=\(snapshotStore.image(for: session.holeNumber) != nil)")
                // Map snapshot background
                if let imageData = snapshotStore.image(for: session.holeNumber),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .ignoresSafeArea()
                } else {
                    // Placeholder when snapshot not yet available
                    ZStack {
                        Color.gray.opacity(0.3)
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Map unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ignoresSafeArea()
                }

                // GPS position overlay
                if let imageData = snapshotStore.image(for: session.holeNumber),
                   let _ = UIImage(data: imageData),
                   let metadata = snapshotStore.metadata(for: session.holeNumber),
                   let currentLoc = session.currentMapLocation {
                    let projectedPoint = projectGPSToPixel(
                        gps: currentLoc,
                        metadata: metadata,
                        imageSize: CGSize(
                            width: CGFloat(metadata.imageWidthPx),
                            height: CGFloat(metadata.imageHeightPx)
                        ),
                        viewSize: geometry.size
                    )

                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                        .position(projectedPoint)
                }
            }
            .ignoresSafeArea()
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.height < -30 {
                            showMapPage = false
                        }
                    }
            )
        }
    }

    /// Project GPS coordinates to pixel position using bounds and linear interpolation.
    private func projectGPSToPixel(
        gps: CLLocation,
        metadata: HoleSnapshotMetadata,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGPoint {
        let bounds = metadata.bounds

        // Linear interpolation from lat/lon to pixel coordinates
        let latRange = bounds.neLat - bounds.swLat
        let lonRange = bounds.neLon - bounds.swLon

        let latFraction = latRange != 0 ? (gps.coordinate.latitude - bounds.swLat) / latRange : 0.5
        let lonFraction = lonRange != 0 ? (gps.coordinate.longitude - bounds.swLon) / lonRange : 0.5

        // Clamp to [0, 1]
        let latClamped = max(0, min(1, latFraction))
        let lonClamped = max(0, min(1, lonFraction))

        // Convert to pixel coordinates (with view scaling)
        let pixelX = lonClamped * viewSize.width
        let pixelY = (1.0 - latClamped) * viewSize.height // Invert Y (map coords vs screen coords)

        return CGPoint(x: pixelX, y: pixelY)
    }
}

#Preview {
    @State var showMapPage = true
    return WatchMapView(showMapPage: $showMapPage)
        .environmentObject(WatchRoundSession())
        .environmentObject(WatchSnapshotStore.shared)
}
