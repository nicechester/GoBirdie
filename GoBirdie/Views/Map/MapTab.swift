//
//  MapTab.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI
import GoBirdieCore

/// Main map tab view showing course layout with hole geometry and hole navigation.
struct MapTab: View {
    @EnvironmentObject var appState: AppState

    var session: RoundSession? {
        appState.activeRound
    }

    var body: some View {
        if let session = session {
            MapActiveView(session: session, appState: appState)
        } else {
            EmptyMapStateView()
        }
    }
}

/// View shown when an active round exists.
private struct MapActiveView: View {
    let session: RoundSession
    let appState: AppState
    @StateObject private var mapViewModel: MapViewModel

    init(session: RoundSession, appState: AppState) {
        self.session = session
        self.appState = appState

        let course = appState.activeRoundViewModel?.course ?? Self.makeTestCourse()
        let locationService = appState.getLocationService()

        _mapViewModel = StateObject(
            wrappedValue: MapViewModel(
                session: session,
                course: course,
                locationService: locationService
            )
        )
    }

    var body: some View {
        ZStack {
            MapLibreView(viewModel: mapViewModel)
                .ignoresSafeArea()

            MapOverlayView(viewModel: mapViewModel)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Clear button when tap is active
            if mapViewModel.selectedTapPoint != nil {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            mapViewModel.clearTap()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 50)
                    }
                    Spacer()
                }
            }
        }
    }

    private static func makeTestCourse() -> Course {
        let pebbleBeach = GpsPoint(lat: 36.5627, lon: -121.9496)
        let holes = (1...18).map { n in
            Hole(
                number: n,
                par: 4,
                handicap: nil,
                tee: pebbleBeach,
                greenCenter: GpsPoint(lat: pebbleBeach.lat + 0.001, lon: pebbleBeach.lon),
                greenFront: pebbleBeach,
                greenBack: GpsPoint(lat: pebbleBeach.lat + 0.002, lon: pebbleBeach.lon),
                geometry: nil
            )
        }
        return Course(id: "test", name: "Test Course", location: pebbleBeach, holes: holes)
    }
}

/// View shown when no active round exists.
private struct EmptyMapStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Start a round to view the course map")
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(20)
    }
}


#Preview("Active Round") {
    let testRound = Round(
        id: "test",
        source: "apple",
        courseId: "test",
        courseName: "Test Course",
        startedAt: Date(),
        endedAt: nil,
        holesPlayed: 0,
        holes: (1...18).map { n in
            HoleScore(number: n, par: 4, strokes: n <= 3 ? n : 0, putts: 0)
        },
        totalStrokes: 0,
        totalPutts: 0
    )
    let testSession = RoundSession(round: testRound)

    let appState = AppState()
    appState.activeRound = testSession

    return MapTab()
        .environmentObject(appState)
        .preferredColorScheme(.light)
}

#Preview("No Round") {
    let appState = AppState()
    return MapTab()
        .environmentObject(appState)
        .preferredColorScheme(.light)
}
