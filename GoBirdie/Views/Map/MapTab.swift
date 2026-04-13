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

            VStack {
                HoleInfoBar(viewModel: mapViewModel)
                    .padding(.top, 50)
                    .padding(.horizontal, 16)

                Spacer()

                // Clear button when tap is active
                if mapViewModel.selectedTapPoint != nil {
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
                        .padding(.bottom, 16)
                    }
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

/// Hole info bar with prev/next arrows and hole details.
private struct HoleInfoBar: View {
    @ObservedObject var viewModel: MapViewModel

    private var hole: Hole? { viewModel.currentHole }
    private var isFirst: Bool { viewModel.currentHoleIndex == 0 }
    private var isLast: Bool { viewModel.currentHoleIndex >= viewModel.course.holes.count - 1 }

    var body: some View {
        HStack {
            Button { viewModel.navigatePrevious() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isFirst ? .gray : .white)
            }
            .disabled(isFirst)

            Spacer()

            if let hole {
                VStack(spacing: 2) {
                    Text("Hole \(hole.number)")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text("Par \(hole.par)")
                        if let yds = hole.yardage {
                            Text("\(yds) yd")
                        }
                        if let hcp = hole.handicap {
                            Text("HCP \(hcp)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer()

            Button { viewModel.navigateNext() } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isLast ? .gray : .white)
            }
            .disabled(isLast)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(.black.opacity(0.6))
        .cornerRadius(12)
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
