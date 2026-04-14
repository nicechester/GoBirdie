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

private struct SearchBar: View {
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

private struct CourseListView: View {
    let courses: [GolfCourseResult]
    let playerLocation: GpsPoint?
    let isSearchingOnline: Bool
    let isSaved: (GolfCourseResult) -> Bool
    let onSelect: (GolfCourseResult) -> Void
    let onRetry: () -> Void

    var body: some View {
        if courses.isEmpty && !isSearchingOnline {
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
                            isSaved: isSaved(course),
                            distanceString: playerLocation.map { course.location.distanceMilesString(to: $0) },
                            onTap: { onSelect(course) }
                        )
                    }
                    if isSearchingOnline {
                        HStack(spacing: 8) {
                            ProgressView().tint(.green)
                            Text("Searching for more courses...")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}

private struct CourseCell: View {
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
    @Published var isSearchingOnline = false
    @Published var searchText = ""

    var appState: AppState?

    private var locationService: LocationService = LocationService()
    private let overpassClient = OverpassClient()
    private let golfCourseAPI = GolfCourseAPIClient(apiKey: Config.golfCourseAPIKey)
    var currentLocation: GpsPoint?
    private var lastFailedCourse: GolfCourseResult?
    private var displayedCourses: [GolfCourseResult] = []
    private var savedCourseIds: Set<Int> = []
    private var cacheIdMap: [Int: String] = [:]  // GolfCourseResult.id -> CourseStore ID

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
        locationService.start()

        Task {
            let startTime = Date()
            while self.currentLocation == nil && Date().timeIntervalSince(startTime) < 20 {
                if let location = locationService.currentLocation {
                    self.currentLocation = location
                    await MainActor.run { self.showCoursesForLocation(location) }
                    return
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            if self.currentLocation == nil {
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
                let intId = stableId(from: c.id)
                cacheIdMap[intId] = c.id
                return GolfCourseResult(id: intId, name: c.name, location: c.location, city: "")
            }

        savedCourseIds = Set(savedResults.map { $0.id })
        displayedCourses = savedResults
        state = .selectCourse(displayedCourses)

        // 2. Search online in background
        isSearchingOnline = true
        Task {
            defer { Task { @MainActor in self.isSearchingOnline = false } }
            do {
                var osmResults = try await overpassClient.searchCourses(location: location, radius: 15_000)
                if osmResults.isEmpty {
                    osmResults = try await overpassClient.searchCourses(location: location, radius: 30_000)
                }
                print("[Overpass] Found \(osmResults.count) nearby courses")

                let newResults = osmResults
                    .map { r -> GolfCourseResult in
                        let intId = -Int(r.osmId)
                        self.cacheIdMap[intId] = "osm-\(r.osmId)"
                        return GolfCourseResult(id: intId, name: r.name, location: r.location, city: "")
                    }
                    .filter { !self.savedCourseIds.contains($0.id) }

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
                let apiResults = try await golfCourseAPI.searchCourses(query: query, playerLocation: searchCenter)
                let filtered = apiResults.map { r -> GolfCourseResult in
                    GolfCourseResult(id: r.id, name: r.name, location: r.location, city: r.city)
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

    private func mergeCourse(name: String, id: String, location: GpsPoint,
                             apiHoles: [GolfCourseHole], osmCourse: Course?) -> Course {
        let osmHoles = osmCourse?.holes ?? []
        let osmHoleMap = Dictionary(uniqueKeysWithValues: osmHoles.map { ($0.number, $0) })
        // OSM is ground truth for hole count (9-hole courses have 18 API holes)
        let effectiveApiHoles = !apiHoles.isEmpty && !osmHoles.isEmpty
            ? Array(apiHoles.prefix(osmHoles.count))
            : apiHoles
        let baseHoles: [Hole] = effectiveApiHoles.isEmpty
            ? osmHoles
            : effectiveApiHoles.map { api in
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
                      holes: baseHoles, downloadedAt: Date(), osmVersion: 1)
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
        let cacheId = cacheIdMap[course.id] ?? (course.id > 0 ? "gcapi-\(course.id)" : "osm-\(abs(course.id))")
        if let cached = try? store.load(id: cacheId) {
            print("[CourseStore] Loaded \(course.name) from cache")
            state = .selectStartingHole(cached)
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

                // 3. Download OSM geometry
                var osmCourse: Course?
                var osmCourses: [Course] = []
                if let osm = osmMatch {
                    print("[Overpass] Downloading geometry for \(osm.name) osmId=\(osm.osmId)")
                    osmCourses = (try? await overpassClient.downloadCourse(
                        osmRelationId: osm.osmId, name: course.name,
                        playerLocation: currentLocation
                    )) ?? []
                }

                // Multi-course complex: match to GolfCourseAPI by yardage, save all, let user pick
                if osmCourses.count > 1 {
                    // Fetch all GolfCourseAPI courses for this club
                    let apiResults = (try? await golfCourseAPI.searchCourses(
                        query: course.name, playerLocation: course.location
                    ))?.filter { $0.location.distanceMeters(to: course.location) < 5_000 } ?? []

                    // Fetch hole data for each API course
                    var apiCourseHoles: [(name: String, id: Int, holes: [GolfCourseHole])] = []
                    for api in apiResults {
                        if let holes = try? await golfCourseAPI.fetchHoles(courseId: api.id, teeColor: teeColor), !holes.isEmpty {
                            apiCourseHoles.append((name: api.name, id: api.id, holes: holes))
                        }
                    }
                    print("[MultiCourse] \(osmCourses.count) OSM clusters, \(apiResults.count) API results, \(apiCourseHoles.count) with holes")

                    // Match each OSM cluster to best API course by yardage
                    var usedApiIdx = Set<Int>()
                    var subCourses: [GolfCourseResult] = []
                    for osc in osmCourses {
                        let osmTotal = osc.holes.compactMap { h -> Double? in
                            guard let t = h.tee, let g = h.greenCenter else { return nil }
                            return t.distanceMeters(to: g) * 1.09361
                        }.reduce(0, +)
                        let bestMatch = matchByYardage(osmCourse: osc, apiCourses: apiCourseHoles, excluding: usedApiIdx)
                        let matchedHoles = bestMatch.map { apiCourseHoles[$0].holes } ?? []
                        let matchedName = bestMatch.map { apiCourseHoles[$0].name } ?? osc.name
                        if let idx = bestMatch { usedApiIdx.insert(idx) }
                        print("[MultiCourse] OSM '\(osc.name)' (\(Int(osmTotal)) yds) -> matched '\(matchedName)' (idx=\(bestMatch.map(String.init) ?? "nil"), used=\(usedApiIdx))")

                        let merged = mergeCourse(name: matchedName, id: osc.id,
                                                 location: osc.location,
                                                 apiHoles: matchedHoles, osmCourse: osc)
                        try? store.save(merged)
                    }
                    // Reload from store so user sees properly named courses
                    let saved = (try? store.loadAll()) ?? []
                    subCourses = saved
                        .filter { $0.id.hasPrefix("osm-\(osmMatch!.osmId)-") }
                        .map { c -> GolfCourseResult in
                            let intId = stableId(from: c.id)
                            self.cacheIdMap[intId] = c.id
                            return GolfCourseResult(id: intId, name: c.name, location: c.location, city: "")
                        }
                    print("[CourseStore] Saved \(osmCourses.count) sub-courses")
                    await MainActor.run {
                        self.lastFailedCourse = nil
                        self.displayedCourses = subCourses
                        self.state = .selectCourse(subCourses)
                    }
                    return
                }

                // Single course
                osmCourse = osmCourses.first
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

    /// Stable negative Int ID from a course store string ID.
    private func stableId(from courseId: String) -> Int {
        // "osm-16307627" -> -16307627, "osm-16307627-1" -> hash-based
        let stripped = courseId
            .replacingOccurrences(of: "osm-", with: "")
            .replacingOccurrences(of: "gcapi-", with: "")
        if let num = Int(stripped) { return -num }
        return -abs(courseId.hashValue)
    }

    /// Match an OSM course to the best GolfCourseAPI course by comparing
    /// tee-to-green distances against actual yardages.
    private func matchByYardage(osmCourse: Course, apiCourses: [(name: String, id: Int, holes: [GolfCourseHole])], excluding: Set<Int>) -> Int? {
        guard !apiCourses.isEmpty else { return nil }
        let osmYards: [Int: Double] = Dictionary(uniqueKeysWithValues:
            osmCourse.holes.compactMap { hole -> (Int, Double)? in
                guard let tee = hole.tee, let green = hole.greenCenter else { return nil }
                return (hole.number, tee.distanceMeters(to: green) * 1.09361)
            }
        )
        guard !osmYards.isEmpty else { return nil }

        var bestIdx: Int?
        var bestError = Double.infinity
        for (idx, api) in apiCourses.enumerated() where !excluding.contains(idx) {
            var totalError = 0.0
            for (i, h) in api.holes.enumerated() {
                let holeNum = i + 1
                if let osmYd = osmYards[holeNum] {
                    let diff = osmYd - Double(h.yardage)
                    totalError += diff * diff
                }
            }
            if totalError < bestError { bestError = totalError; bestIdx = idx }
        }
        return bestIdx
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
