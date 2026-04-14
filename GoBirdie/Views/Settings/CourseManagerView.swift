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
                        let apiId = Int(result.osmId)
                        let alreadySaved = savedCourses.contains { $0.golfCourseApiId == apiId }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).font(.subheadline)
                                if let subtitle = resultSubtitle(result) {
                                    Text(subtitle)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if alreadySaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if downloadingId == result.id {
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
                let apiResults = try await golfCourseAPI.searchCourses(query: query, playerLocation: location)
                let results = apiResults.map { r in
                    CourseSearchResult(id: "api-\(r.id)", name: r.name, location: r.location, osmType: "api", osmId: Int64(r.id), city: r.city)
                }

                await MainActor.run {
                    searchResults = results
                    isSearching = false
                    if results.isEmpty { errorMessage = "No courses found for \"\(query)\"" }
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = "Search failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func matchByYardage(osmCourse: Course, apiCourses: [(name: String, id: Int, holes: [GolfCourseHole])], excluding usedIdx: inout Set<Int>) -> (name: String, id: Int, holes: [GolfCourseHole])? {
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

    private func resultSubtitle(_ result: CourseSearchResult) -> String? {
        let location = appState.getLocationService().currentLocation
        var parts: [String] = []
        if !result.city.isEmpty { parts.append(result.city) }
        if let loc = location {
            let mi = result.location.distanceMeters(to: loc) / 1609.34
            parts.append(mi < 1 ? "< 1 mi away" : String(format: "%.0f mi away", mi))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func downloadCourse(_ result: CourseSearchResult) {
        let cacheId = result.id
        downloadingId = cacheId

        Task {
            do {
                let teeColor = appState.teeColor
                let location = result.location

                // Find OSM relation near this course's location
                let nearbyOsm = try await overpassClient.searchCourses(location: location, radius: 2_000)
                let osmMatch = nearbyOsm.first

                // OSM geometry (if found)
                var osmCourses: [Course] = []
                if let osm = osmMatch {
                    osmCourses = (try? await overpassClient.downloadCourse(
                        osmRelationId: osm.osmId, name: result.name
                    )) ?? []
                }

                // GolfCourseAPI: fetch all matching courses at this location
                let apiResults = (try? await golfCourseAPI.searchCourses(
                    query: result.name, playerLocation: location
                ))?.filter { $0.location.distanceMeters(to: location) < 5_000 } ?? []

                var apiCourseHoles: [(name: String, id: Int, holes: [GolfCourseHole])] = []
                for api in apiResults {
                    if let holes = try? await golfCourseAPI.fetchHoles(courseId: api.id, teeColor: teeColor), !holes.isEmpty {
                        apiCourseHoles.append((name: api.name, id: api.id, holes: holes))
                    }
                }

                // Match & save each OSM course
                var usedApiIdx = Set<Int>()
                for osmCourse in osmCourses {
                    let bestMatch = matchByYardage(osmCourse: osmCourse, apiCourses: apiCourseHoles, excluding: &usedApiIdx)
                    let matchedHoles = bestMatch?.holes ?? []
                    let courseName = bestMatch?.name ?? osmCourse.name

                    let osmHoleMap = Dictionary(uniqueKeysWithValues: osmCourse.holes.map { ($0.number, $0) })
                    let cappedHoles = !matchedHoles.isEmpty ? Array(matchedHoles.prefix(osmCourse.holes.count)) : matchedHoles
                    let holes: [Hole] = cappedHoles.isEmpty
                        ? osmCourse.holes
                        : cappedHoles.map { api in
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
                                        holes: holes, downloadedAt: Date(), osmVersion: 1,
                                        golfCourseApiId: bestMatch?.id)
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
