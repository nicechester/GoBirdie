//
//  CourseManagerView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct CourseManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var savedCourses: [Course] = []
    @State private var searchText = ""
    @State private var searchResults: [CourseSearchResult] = []
    @State private var isSearching = false
    @State private var downloadingId: String?
    @State private var errorMessage: String?

    private let overpassClient = OverpassClient()
    private let golfCourseAPI = GolfCourseAPIClient(apiKey: Config.golfCourseAPIKey)

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search courses to download", text: $searchText)
                        .autocorrectionDisabled()
                        .onSubmit { search() }
                    if !searchText.isEmpty {
                        Button { searchText = ""; searchResults = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isSearching {
                Section {
                    HStack {
                        Spacer()
                        ProgressView().tint(.green)
                        Text("Searching...").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults, id: \.id) { result in
                        let alreadySaved = savedCourses.contains { $0.id == "osm-\(result.osmId)" }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).font(.subheadline)
                            }
                            Spacer()
                            if alreadySaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if downloadingId == "osm-\(result.osmId)" {
                                ProgressView().tint(.green)
                            } else {
                                Button {
                                    downloadCourse(result)
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Saved Courses (\(savedCourses.count))") {
                if savedCourses.isEmpty {
                    Text("No courses downloaded yet")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(savedCourses) { course in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.subheadline)
                            Text("\(course.holes.count) holes · Downloaded \(course.downloadedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteCourses)
                }
            }
        }
        .navigationTitle("Courses")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSaved() }
    }

    private func loadSaved() {
        savedCourses = (try? CourseStore().loadAll()) ?? []
    }

    private func deleteCourses(at offsets: IndexSet) {
        let store = CourseStore()
        for idx in offsets {
            try? store.delete(id: savedCourses[idx].id)
        }
        savedCourses.remove(atOffsets: offsets)
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        searchResults = []

        Task {
            do {
                let location = appState.getLocationService().currentLocation ?? GpsPoint(lat: 34.0, lon: -118.0)
                let results = try await overpassClient.searchCoursesByName(query, near: location)
                let filtered = results

                await MainActor.run {
                    searchResults = filtered
                    isSearching = false
                    if filtered.isEmpty { errorMessage = "No courses found for \"\(query)\"" }
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = "Search failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func matchByYardage(osmCourse: Course, apiCourses: [(name: String, holes: [GolfCourseHole])], excluding usedIdx: inout Set<Int>) -> (name: String, holes: [GolfCourseHole])? {
        let osmYards: [Int: Double] = Dictionary(uniqueKeysWithValues:
            osmCourse.holes.compactMap { hole -> (Int, Double)? in
                guard let tee = hole.tee, let green = hole.greenCenter else { return nil }
                return (hole.number, tee.distanceMeters(to: green) * 1.09361)
            }
        )
        guard !osmYards.isEmpty, !apiCourses.isEmpty else { return nil }

        var bestIdx: Int?
        var bestError = Double.infinity
        for (idx, api) in apiCourses.enumerated() where !usedIdx.contains(idx) {
            var totalError = 0.0
            for (i, h) in api.holes.enumerated() {
                if let osmYd = osmYards[i + 1] {
                    let diff = osmYd - Double(h.yardage)
                    totalError += diff * diff
                }
            }
            if totalError < bestError { bestError = totalError; bestIdx = idx }
        }
        guard let idx = bestIdx else { return nil }
        usedIdx.insert(idx)
        return apiCourses[idx]
    }

    private func downloadCourse(_ result: CourseSearchResult) {
        let cacheId = "osm-\(result.osmId)"
        downloadingId = cacheId

        Task {
            do {
                let teeColor = appState.teeColor
                let location = result.location

                // OSM geometry
                let osmCourses = (try? await overpassClient.downloadCourse(
                    osmRelationId: result.osmId, name: result.name
                )) ?? []

                // GolfCourseAPI: fetch all matching courses at this location
                let apiResults = (try? await golfCourseAPI.searchCourses(
                    query: result.name, playerLocation: location
                ))?.filter { $0.location.distanceMeters(to: location) < 5_000 } ?? []

                var apiCourseHoles: [(name: String, holes: [GolfCourseHole])] = []
                for api in apiResults {
                    if let holes = try? await golfCourseAPI.fetchHoles(courseId: api.id, teeColor: teeColor), !holes.isEmpty {
                        apiCourseHoles.append((name: api.name, holes: holes))
                    }
                }

                // Match & save each OSM course
                var usedApiIdx = Set<Int>()
                for osmCourse in osmCourses {
                    let bestMatch = matchByYardage(osmCourse: osmCourse, apiCourses: apiCourseHoles, excluding: &usedApiIdx)
                    let matchedHoles = bestMatch?.holes ?? []
                    let courseName = bestMatch?.name ?? osmCourse.name

                    let osmHoleMap = Dictionary(uniqueKeysWithValues: osmCourse.holes.map { ($0.number, $0) })
                    let holes: [Hole] = matchedHoles.isEmpty
                        ? osmCourse.holes
                        : matchedHoles.map { api in
                            let osm = osmHoleMap[api.number]
                            return Hole(
                                id: osm?.id ?? UUID(), number: api.number,
                                par: api.par, handicap: api.handicap, yardage: "\(api.yardage)",
                                tee: osm?.tee, greenCenter: osm?.greenCenter,
                                greenFront: osm?.greenFront, greenBack: osm?.greenBack,
                                geometry: osm?.geometry
                            )
                        }
                    let course = Course(id: osmCourse.id, name: courseName, location: location,
                                        holes: holes, downloadedAt: Date(), osmVersion: 1)
                    try? CourseStore().save(course)
                }

                await MainActor.run {
                    downloadingId = nil
                    loadSaved()
                }
            } catch {
                await MainActor.run {
                    downloadingId = nil
                    errorMessage = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
