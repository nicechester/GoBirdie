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

    private let courseDownloadService = CourseDownloadService()
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
        downloadingId = result.id

        Task {
            do {
                let teeColor = appState.teeColor
                let downloadResult = try await courseDownloadService.downloadCourse(
                    id: result.id,
                    name: result.name,
                    location: result.location,
                    teeColor: teeColor
                )

                try? CourseStore().save(downloadResult.course)

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
