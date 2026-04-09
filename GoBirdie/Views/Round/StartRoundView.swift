//
//  StartRoundView.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI
import Combine
import GoBirdieCore

/// Sheet view for starting a new round.
/// Discovers nearby golf courses by location using Overpass API.
struct StartRoundView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    @StateObject private var viewModel = StartRoundViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("Start a Round")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Discover nearby courses")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)

                    // Content based on state
                    switch viewModel.state {
                    case .requestingLocation:
                        LocationRequestingView()

                    case .searching:
                        SearchingView()

                    case .selectCourse(let courses):
                        CourseListView(
                            courses: courses,
                            playerLocation: viewModel.currentLocation,
                            onSelect: { course in viewModel.downloadCourse(course) },
                            onRetry: { viewModel.searchNearby() }
                        )

                    case .downloading(let courseName):
                        DownloadingView(courseName: courseName)

                    case .selectStartingHole(let course):
                        StartingHoleView(course: course) { hole in
                            viewModel.startRound(course: course, startingHole: hole)
                        }

                    case .error(let message):
                        ErrorView(
                            message: message,
                            onRetry: { viewModel.retry() }
                        )
                    }

                    Spacer()

                    // Cancel button
                    Button(action: { dismiss() }) {
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

                // Show a blocking overlay while starting round
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
        .onChange(of: viewModel.startedRound) { oldVal, newVal in
            if newVal {
                dismiss()
            }
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

// MARK: - State Views

private struct LocationRequestingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.green)

            VStack(spacing: 8) {
                Text("Finding your location...")
                    .font(.headline)
                Text("Enable location in Settings if prompted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

private struct SearchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.green)
            Text("Searching for courses...")
                .font(.headline)
        }
        .padding(.vertical, 32)
    }
}

private struct CourseListView: View {
    let courses: [GolfCourseResult]
    let playerLocation: GpsPoint?
    let onSelect: (GolfCourseResult) -> Void
    let onRetry: () -> Void

    var body: some View {
        if courses.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No courses found")
                    .font(.headline)
                Button(action: onRetry) {
                    Text("Retry")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 32)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(courses) { course in
                        CourseCell(
                            course: course,
                            distanceString: playerLocation.map { course.location.distanceMilesString(to: $0) },
                            onTap: { onSelect(course) }
                        )
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}

private struct CourseCell: View {
    let course: GolfCourseResult
    let distanceString: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Text(course.city)
                        .font(.caption).foregroundStyle(.secondary)
                    if let dist = distanceString {
                        Text("· \(dist)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

private struct DownloadingView: View {
    let courseName: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.green)

            VStack(spacing: 8) {
                Text("Downloading \(courseName)...")
                    .font(.headline)
                Text("Getting course geometry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Error")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Text("Retry")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 32)
    }
}

private struct StartingHoleView: View {
    let course: Course
    let onStart: (Int) -> Void
    @State private var selectedHole: Int = 1

    var body: some View {
        VStack(spacing: 20) {
            Text("Which hole are you starting on?")
                .font(.headline)
                .multilineTextAlignment(.center)

            Picker("Starting Hole", selection: $selectedHole) {
                ForEach(course.holes, id: \.number) { hole in
                    Text("Hole \(hole.number)  Par \(hole.par)\(hole.yardage.map { "  \($0) yds" } ?? "")").tag(hole.number)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)

            Button {
                onStart(selectedHole)
            } label: {
                Text("Start on Hole \(selectedHole)")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - View Model

@MainActor
class StartRoundViewModel: ObservableObject {
    @Published var state: ViewState = .requestingLocation
    @Published var isStartingRound = false
    @Published var startedRound = false

    var appState: AppState?

    private var locationService: LocationService = LocationService()
    private let overpassClient = OverpassClient()
    private let golfCourseAPI = GolfCourseAPIClient(apiKey: Config.golfCourseAPIKey)
    var currentLocation: GpsPoint?
    private var searchAttempts = 0
    private var lastSearchResults: [GolfCourseResult] = []
    private var lastFailedCourse: GolfCourseResult?

    enum ViewState {
        case requestingLocation
        case searching
        case selectCourse([GolfCourseResult])
        case downloading(String)
        case selectStartingHole(Course)   // ask user which hole to start on
        case error(String)
    }

    init() {}

    func setup(locationService: LocationService) {
        self.locationService = locationService
    }

    func requestLocation() {
        locationService.start()

        // Wait for location update with timeout
        Task {
            let startTime = Date()

            while self.currentLocation == nil && Date().timeIntervalSince(startTime) < 20 {
                // Poll current location every 0.5 seconds
                if let location = locationService.currentLocation {
                    self.currentLocation = location
                    await MainActor.run {
                        self.searchNearby()
                    }
                    return
                }
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            }

            // Timeout
            if self.currentLocation == nil {
                await MainActor.run {
                    self.state = .error("Could not get location. Check Settings.")
                }
            }
        }
    }

    func searchNearby() {
        guard let location = currentLocation else {
            state = .error("Location not available")
            return
        }

        if !lastSearchResults.isEmpty {
            print("[Search] Using cached results (\(lastSearchResults.count) courses)")
            state = .selectCourse(lastSearchResults)
            return
        }

        state = .searching
        print("[Search] Searching near \(location.lat), \(location.lon)")

        Task {
            do {
                var osmResults = try await overpassClient.searchCourses(location: location, radius: 15_000)
                if osmResults.isEmpty {
                    osmResults = try await overpassClient.searchCourses(location: location, radius: 30_000)
                }
                print("[Overpass] Found \(osmResults.count) nearby courses")

                let results = osmResults.map {
                    GolfCourseResult(id: -Int($0.osmId), name: $0.name, location: $0.location, city: "")
                }

                await MainActor.run {
                    if results.isEmpty {
                        self.state = .error("No golf courses found nearby.")
                    } else {
                        self.lastSearchResults = results
                        self.state = .selectCourse(results)
                    }
                }
            } catch {
                print("[Search] Error: \(error)")
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
        }
    }

    private func mergeCourse(name: String, id: String, location: GpsPoint,
                             apiHoles: [GolfCourseHole], osmCourse: Course?) -> Course {
        let osmHoleMap = Dictionary(uniqueKeysWithValues:
            (osmCourse?.holes ?? []).map { ($0.number, $0) }
        )
        let baseHoles: [Hole] = apiHoles.isEmpty
            ? (osmCourse?.holes ?? [])
            : apiHoles.map { api in
                let osm = osmHoleMap[api.number]
                return Hole(
                    id: osm?.id ?? UUID(), number: api.number,
                    par: api.par, handicap: api.handicap,
                    yardage: "\(api.yardage)",
                    tee: osm?.tee, greenCenter: osm?.greenCenter,
                    greenFront: osm?.greenFront, greenBack: osm?.greenBack,
                    geometry: osm?.geometry
                )
            }
        return Course(id: id, name: name, location: location,
                      holes: baseHoles, allGreens: osmCourse?.allGreens ?? [],
                      allTees: osmCourse?.allTees ?? [],
                      downloadedAt: Date(), osmVersion: 1)
    }

    func startRound(course: Course, startingHole: Int) {
        isStartingRound = true
        if let appState {
            let loc = currentLocation ?? course.location
            let session = appState.startRound(course: course, playerLocation: loc)
            if startingHole != 1 {
                session.navigateTo(holeNumber: startingHole)
            }
        }
        startedRound = true
    }

    func retry() {
        if let course = lastFailedCourse {
            downloadCourse(course)
        } else if !lastSearchResults.isEmpty {
            state = .selectCourse(lastSearchResults)
        } else {
            searchNearby()
        }
    }

    func downloadCourse(_ course: GolfCourseResult) {
        let store = CourseStore()
        let cacheId = course.id > 0 ? "gcapi-\(course.id)" : "osm-\(abs(course.id))"
        if let cached = try? store.load(id: cacheId) {
            print("[CourseStore] Loaded \(course.name) from cache")
            isStartingRound = true
            if let appState { _ = appState.startRound(course: cached, playerLocation: currentLocation ?? course.location) }
            startedRound = true
            return
        }

        lastFailedCourse = course
        state = .downloading(course.name)
        print("[Download] Starting \(course.name) id=\(course.id)")

        Task {
            do {
                // 1. Get OSM geometry
                let osmResults = try await overpassClient.searchCourses(location: course.location, radius: 2_000)
                let osmMatch = osmResults.first(where: {
                    levenshtein($0.name, course.name) < 10
                }) ?? osmResults.first

                // 2. Get par/yardage from GolfCourseAPI — search by name if no direct ID
                var apiHoles: [GolfCourseHole] = []
                let teeColor = appState?.teeColor ?? "Blue"
                var gcapiId = course.id > 0 ? course.id : nil

                if gcapiId == nil {
                    // Search by course name to get the GolfCourseAPI ID
                    let apiResults = try? await golfCourseAPI.searchCourses(query: course.name, playerLocation: course.location)
                    gcapiId = apiResults?.first(where: { levenshtein($0.name, course.name) < 15 })?.id
                    print("[GolfCourseAPI] Resolved id=\(gcapiId.map(String.init) ?? "nil") for '\(course.name)'")
                }

                if let id = gcapiId {
                    apiHoles = (try? await golfCourseAPI.fetchHoles(courseId: id, teeColor: teeColor)) ?? []
                    print("[GolfCourseAPI] Got \(apiHoles.count) holes for tee: \(teeColor)")
                }

                // Build yardage map for OSM green matching
                let targetYardages = Dictionary(uniqueKeysWithValues: apiHoles.map { ($0.number, $0.yardage) })

                // 3. Download OSM geometry with yardage-guided green matching
                var osmCourse: Course?
                if let osm = osmMatch {
                    print("[Overpass] Downloading geometry for \(osm.name) osmId=\(osm.osmId)")
                    osmCourse = try? await overpassClient.downloadCourse(
                        osmRelationId: osm.osmId, name: course.name,
                        targetYardages: targetYardages
                    )
                }

                // 3. Merge
                let mergedCourse = mergeCourse(
                    name: course.name, id: cacheId,
                    location: course.location,
                    apiHoles: apiHoles, osmCourse: osmCourse
                )

                try? store.save(mergedCourse)
                print("[CourseStore] Saved \(course.name)")

                await MainActor.run {
                    self.lastFailedCourse = nil
                    self.state = .selectStartingHole(mergedCourse)
                }
            } catch {
                print("[Download] Error: \(error)")
                await MainActor.run { self.state = .error("Failed: \(error.localizedDescription)") }
            }
        }
    }

    // Simple Levenshtein for fuzzy name matching
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = a.lowercased(), b = b.lowercased()
        var dp = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var prev = i
            dp[0] = i + 1
            for (j, cb) in b.enumerated() {
                let temp = dp[j + 1]
                dp[j + 1] = ca == cb ? prev : 1 + min(prev, min(dp[j], dp[j + 1]))
                prev = temp
            }
        }
        return dp[b.count]
    }
}

#Preview {
    let appState = AppState()
    return StartRoundView()
        .environmentObject(appState)
}
