//
//  MapTab.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI
import GoBirdieCore

/// State for the explore mode
enum ExploreState {
    case inactive
    case picking
    case exploring(course: Course)
}

/// Main map tab view showing course layout with hole geometry and hole navigation.
struct MapTab: View {
    @EnvironmentObject var appState: AppState
    @State private var exploreState: ExploreState = .inactive

    var session: RoundSession? {
        appState.activeRound
    }

    var body: some View {
        if let session = session {
            MapActiveView(session: session, appState: appState)
        } else {
            switch exploreState {
            case .inactive:
                ExploreEntryView { exploreState = .picking }
            case .picking:
                ExploreCoursePicker(
                    exploreState: $exploreState,
                    appState: appState
                )
            case .exploring(let course):
                ExploreMapView(course: course, appState: appState) {
                    exploreState = .picking
                }
            }
        }
    }
}

/// Entry view for explore mode
private struct ExploreEntryView: View {
    let onExplore: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Explore Courses")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("View course layouts without tracking a round")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onExplore) {
                Text("Start Exploring")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(20)
    }
}

/// Course picker for explore mode
private struct ExploreCoursePicker: View {
    @Binding var exploreState: ExploreState
    let appState: AppState
    @StateObject private var viewModel = StartRoundViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Image(systemName: "map.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("Explore Courses")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Pick a course to explore")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)

                    switch viewModel.state {
                    case .requestingLocation:
                        LocationRequestingView()

                    case .selectCourse(let courses):
                        SearchBar(text: $viewModel.searchText, onCommit: { viewModel.searchByName() })
                            .padding(.bottom, 8)

                        CourseListView(
                            courses: courses,
                            playerLocation: viewModel.currentLocation,
                            isSearchingOnline: viewModel.isSearchingOnline,
                            isSaved: { viewModel.isSaved($0) },
                            onSelect: { course in viewModel.downloadCourse(course) },
                            onRetry: { viewModel.searchNearby() }
                        )

                    case .downloading(let courseName):
                        DownloadingView(courseName: courseName)

                    case .selectStartingHole(let course):
                        // Auto-transition to map view (skip intermediate screen)
                        Color.clear
                            .task {
                                DispatchQueue.main.async {
                                    exploreState = .exploring(course: course)
                                }
                            }

                    case .error(let message):
                        ErrorView(
                            message: message,
                            onRetry: { viewModel.retry() }
                        )
                    }

                    Spacer()

                    Button(action: { exploreState = .inactive }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .navigationBarTitleDisplayMode(.inline)

                if viewModel.isStartingRound {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .onAppear {
            viewModel.appState = appState
            viewModel.setup(locationService: appState.getLocationService())
            viewModel.requestLocation()
        }
        .safeAreaInset(edge: .top) {
            if !appState.getLocationService().isFullyAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(.orange)
                    Text("Set Location to \"While Using\" for best accuracy")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Fix") {
                        appState.getLocationService().openSettings()
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
            }
        }
    }
}

/// Map view for explore mode
private struct ExploreMapView: View {
    let course: Course
    let appState: AppState
    let onBack: () -> Void
    @StateObject private var mapViewModel: MapViewModel

    init(course: Course, appState: AppState, onBack: @escaping () -> Void) {
        self.course = course
        self.appState = appState
        self.onBack = onBack
        let locationService = appState.getLocationService()
        _mapViewModel = StateObject(
            wrappedValue: MapViewModel(
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

                ExploreMapBannerCTA(onBack: onBack)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }
}

/// Bottom action button for explore mode
private struct ExploreMapBannerCTA: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.headline)
                Text("Pick Another Course")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
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
        .onAppear {
            mapViewModel.syncToSession()
        }
    }

    fileprivate static func makeTestCourse() -> Course {
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

    return (
        MapTab()
            .environmentObject(appState)
            .preferredColorScheme(.light)
    )
}

#Preview("No Round") {
    let appState = AppState()
    return (
        MapTab()
            .environmentObject(appState)
            .preferredColorScheme(.light)
    )
}
