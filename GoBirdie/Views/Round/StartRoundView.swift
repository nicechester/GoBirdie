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
                        Text("round.startRound".localized)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("map.discoverNearby".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)

                    // Content based on state
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
                            searchFailed: viewModel.searchFailed,
                            isSaved: { viewModel.isSaved($0) },
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
                        Text("common.cancel".localized)
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
        .onChange(of: viewModel.startedRound) { newVal in
            if newVal {
                dismiss()
            }
        }
        .safeAreaInset(edge: .top) {
            if !appState.getLocationService().isFullyAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(.orange)
                    Text("map.locationPermission".localized)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("common.fix".localized) {
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

struct LocationRequestingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.green)

            VStack(spacing: 8) {
                Text("map.findingLocation".localized)
                    .font(.headline)
                Text("map.enableLocation".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by name", text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit { onCommit() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct CourseListView: View {
    let courses: [GolfCourseResult]
    let playerLocation: GpsPoint?
    let isSearchingOnline: Bool
    let searchFailed: Bool
    let isSaved: (GolfCourseResult) -> Bool
    let onSelect: (GolfCourseResult) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Search indicator at top
            if isSearchingOnline {
                HStack(spacing: 8) {
                    ProgressView().tint(.green)
                    Text("courses.searchingMore".localized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Saved courses are listed, but the nearby search failed
            if searchFailed && !isSearchingOnline && !courses.isEmpty {
                HStack {
                    Text("courses.searchFailed".localized)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("common.retry".localized, action: onRetry)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
            }

            // Course list
            if courses.isEmpty && !isSearchingOnline {
                VStack(spacing: 16) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("courses.noCoursesFound".localized)
                        .font(.headline)
                    Button(action: onRetry) {
                        Text("common.retry".localized)
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
                                isSaved: isSaved(course),
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
}

struct CourseCell: View {
    let course: GolfCourseResult
    let isSaved: Bool
    let distanceString: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                        if let dist = distanceString {
                            Text(dist)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !course.city.isEmpty {
                            Text(course.city)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

struct DownloadingView: View {
    let courseName: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.green)

            VStack(spacing: 8) {
                Text("courses.downloading".localized(with: courseName))
                    .font(.headline)
                Text("courses.gettingGeometry".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("common.error".localized)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Text("common.retry".localized)
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
            Text("round.whichHole".localized)
                .font(.headline)
                .multilineTextAlignment(.center)

            Picker("Starting Hole", selection: $selectedHole) {
                ForEach(course.holes, id: \.number) { hole in
                    if let yardage = hole.yardage {
                        Text("round.holeParYards".localized(with: hole.number, hole.par, yardage)).tag(hole.number)
                    } else {
                        Text("round.holePar".localized(with: hole.number, hole.par)).tag(hole.number)
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)

            Button {
                onStart(selectedHole)
            } label: {
                Text("round.startOnHole".localized(with: selectedHole))
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
    @Published var isSearchingOnline = false
    /// The nearby (Overpass) search failed. Saved courses stay listed; the list offers a retry.
    @Published var searchFailed = false
    @Published var searchText = ""

    var appState: AppState?

    private var locationService: LocationService = LocationService()
    private let courseDownloadService = CourseDownloadService()
    private let overpassClient = OverpassClient()
    private let golfCourseAPI = GolfCourseAPIClient(apiKey: Config.golfCourseAPIKey)
    var currentLocation: GpsPoint?
    private var lastFailedCourse: GolfCourseResult?
    private var displayedCourses: [GolfCourseResult] = []
    private var savedCourseIds: Set<String> = []

    enum ViewState {
        case requestingLocation
        case selectCourse([GolfCourseResult])
        case downloading(String)
        case selectStartingHole(Course)
        case error(String)
    }

    init() {}

    func setup(locationService: LocationService) {
        self.locationService = locationService
    }

    func requestLocation() {
        // 1. Load and show saved courses immediately (without waiting for location)
        let store = CourseStore()
        let saved = (try? store.loadAll()) ?? []

        if !saved.isEmpty {
            let savedResults = saved
                .prefix(20)
                .map { c -> GolfCourseResult in
                    GolfCourseResult(id: c.id, name: c.name, location: c.location, city: "")
                }

            savedCourseIds = Set(savedResults.map { $0.id })
            displayedCourses = savedResults
            state = .selectCourse(displayedCourses)
        }

        // 2. Request location and search online in background
        locationService.start()

        Task {
            let startTime = Date()
            while self.currentLocation == nil && Date().timeIntervalSince(startTime) < 20 {
                if let location = locationService.currentLocation {
                    self.currentLocation = location
                    // Always call showCoursesForLocation to properly sort by distance
                    await MainActor.run { self.showCoursesForLocation(location) }
                    return
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            // Only show error if we have no saved courses to fall back on
            if self.currentLocation == nil && self.displayedCourses.isEmpty {
                await MainActor.run {
                    self.state = .error("Could not get location. Check Settings.")
                }
            }
        }
    }

    private func showCoursesForLocation(_ location: GpsPoint) {
        // 1. Show saved courses immediately, sorted by distance
        let store = CourseStore()
        let saved = (try? store.loadAll()) ?? []
        let savedResults = saved
            .sorted { $0.location.distanceMeters(to: location) < $1.location.distanceMeters(to: location) }
            .prefix(20)
            .map { c -> GolfCourseResult in
                GolfCourseResult(id: c.id, name: c.name, location: c.location, city: "")
            }

        savedCourseIds = Set(savedResults.map { $0.id })
        displayedCourses = savedResults
        state = .selectCourse(displayedCourses)

        // 2. Search online in background
        searchOnlineForLocation(location)
    }

    private func searchOnlineForLocation(_ location: GpsPoint) {
        isSearchingOnline = true
        searchFailed = false
        Task {
            defer { Task { @MainActor in self.isSearchingOnline = false } }
            do {
                // Static OSM index first (no live query); Overpass only when the index has nothing nearby.
                let staticHits = (try? await OsmCourseSource.shared.nearby(location, radiusMeters: 15_000)) ?? []
                let newResults: [GolfCourseResult]
                if !staticHits.isEmpty {
                    newResults = staticHits
                        .map { e in
                            GolfCourseResult(id: "osm-\(e.osmId)", name: e.name, location: e.point, city: e.city)
                        }
                        .filter { !self.savedCourseIds.contains($0.id) }
                } else {
                    var osmResults = try await overpassClient.searchCourses(location: location, radius: 15_000)
                    if osmResults.isEmpty {
                        osmResults = try await overpassClient.searchCourses(location: location, radius: 30_000)
                    }
                    print("[Overpass] Found \(osmResults.count) nearby courses")

                    newResults = osmResults
                        .map { r -> GolfCourseResult in
                            GolfCourseResult(id: "osm-\(r.osmId)", name: r.name, location: r.location, city: "")
                        }
                        .filter { !self.savedCourseIds.contains($0.id) }
                }

                await MainActor.run {
                    self.displayedCourses.append(contentsOf: newResults)
                    self.displayedCourses.sort { $0.location.distanceMeters(to: location) < $1.location.distanceMeters(to: location) }
                    if case .selectCourse = self.state {
                        self.state = .selectCourse(self.displayedCourses)
                    }
                }
            } catch {
                print("[Search] Online search failed: \(error)")
                // Saved courses are already showing, so don't overwrite with error
                await MainActor.run {
                    self.searchFailed = true
                    if self.displayedCourses.isEmpty {
                        self.state = .error("No courses found. \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func searchNearby() {
        guard let location = currentLocation else {
            state = .error("Location not available")
            return
        }
        showCoursesForLocation(location)
    }

    func isSaved(_ course: GolfCourseResult) -> Bool {
        savedCourseIds.contains(course.id)
    }

    func searchByName() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            // Clear search — restore location-based results
            if let loc = currentLocation { showCoursesForLocation(loc) }
            return
        }

        isSearchingOnline = true
        state = .selectCourse([])

        Task {
            defer { Task { @MainActor in self.isSearchingOnline = false } }
            do {
                let searchCenter = currentLocation ?? GpsPoint(lat: 34.0, lon: -118.0)

                // Static index first: it covers every course in the data. GolfCourseAPI only when it has no match.
                let staticHits: [OsmIndexEntry]
                do {
                    staticHits = try await OsmCourseSource.shared.search(name: query, near: searchCenter)
                } catch {
                    print("[OSM] name search '\(query)' failed: \(error)")
                    staticHits = []
                }
                print("[OSM] name search '\(query)': \(staticHits.count) index hits")
                if !staticHits.isEmpty {
                    let results = staticHits.map { e in
                        GolfCourseResult(id: "osm-\(e.osmId)", name: e.name, location: e.point, city: e.city)
                    }
                    await MainActor.run {
                        self.displayedCourses = results
                        self.state = .selectCourse(results)
                    }
                    return
                }

                let apiResults = try await golfCourseAPI.searchCourses(query: query, playerLocation: searchCenter)
                let loc = self.currentLocation
                let filtered = apiResults
                    .map { GolfCourseResult(id: $0.id, apiId: $0.apiId, name: $0.name, location: $0.location, city: $0.city) }
                    .sorted { a, b in
                        guard let loc else { return false }
                        return a.location.distanceMeters(to: loc) < b.location.distanceMeters(to: loc)
                    }

                await MainActor.run {
                    self.displayedCourses = filtered
                    self.state = .selectCourse(filtered)
                }
            } catch {
                print("[Search] Name search failed: \(error)")
                await MainActor.run {
                    self.state = .error("Search failed: \(error.localizedDescription)")
                }
            }
        }
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
        } else {
            searchNearby()
        }
    }

    func downloadCourse(_ course: GolfCourseResult) {
        let store = CourseStore()
        let cacheId = course.id

        // Check cache first. Layouts of a complex are saved as "<id>-1", "<id>-2", so match the prefix too.
        let cachedCourse = (try? store.load(id: cacheId))
            ?? (try? store.loadAll())?.first { $0.id.hasPrefix(cacheId + "-") }
        if let cached = cachedCourse {
            print("[CourseStore] Loaded \(course.name) from cache")
            state = .selectStartingHole(cached)
            return
        }

        lastFailedCourse = course
        state = .downloading(course.name)
        print("[Download] Starting \(course.name) id=\(course.id)")

        Task {
            do {
                let teeColor = appState?.teeColor ?? "Blue"

                let result = try await courseDownloadService.downloadCourse(
                    id: course.id,
                    name: course.name,
                    location: course.location,
                    teeColor: teeColor
                )

                print("[CourseStore] Saving course (isSingleCourse: \(result.isSingleCourse))")
                try? store.save(result.course)
                // Other layouts of a multi-course complex are saved too, so each shows in the saved list.
                for layout in result.additionalCourses { try? store.save(layout) }

                await MainActor.run {
                    self.lastFailedCourse = nil
                    self.state = .selectStartingHole(result.course)
                }
            } catch {
                print("[Download] Error: \(error)")
                await MainActor.run {
                    self.state = .error("Failed: \(error.localizedDescription)")
                }
            }
        }
    }

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
