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
    @State private var cachedRegionBytes = 0
    @State private var clearedMessage: String?

    private let courseDownloadService = CourseDownloadService()
    private let golfCourseAPI = GolfCourseAPIClient(apiKey: Config.golfCourseAPIKey)
    private let overpassClient = OverpassClient()

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
                        Text("courses.searching".localized).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults, id: \.id) { result in
                        let alreadySaved = savedCourses.contains { $0.id == result.id }
                            || (result.apiId.map { apiId in savedCourses.contains { $0.golfCourseApiId == apiId } } ?? false)
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
                    Text("courses.noCourses".localized)
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(savedCourses) { course in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.subheadline)
                            Text("courses.holesDownloaded".localized(with: course.holes.count, course.downloadedAt.formatted(.relative(presentation: .named))))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteCourses)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        // Region cache only: downloaded courses are kept.
                        let freed = await OsmCourseSource.shared.clearRegionCache()
                        cachedRegionBytes = await OsmCourseSource.shared.cachedRegionBytes()
                        clearedMessage = ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file)
                    }
                } label: {
                    Label("settings.clearTempFiles".localized, systemImage: "trash")
                        .foregroundStyle(cachedRegionBytes == 0 ? Color.gray.opacity(0.4) : Color.red)
                }
                .disabled(cachedRegionBytes == 0)
            } footer: {
                Text("settings.clearTempFilesFooter".localized)
            }
        }
        .navigationTitle("settings.manageCourses".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSaved()
            Task { cachedRegionBytes = await OsmCourseSource.shared.cachedRegionBytes() }
        }
        .alert(
            "settings.clearTempFiles".localized,
            isPresented: Binding(
                get: { clearedMessage != nil },
                set: { if !$0 { clearedMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(format: "settings.clearedMessage".localized, clearedMessage ?? ""))
        }
    }

    private func loadSaved() {
        savedCourses = (try? CourseStore().loadAll()) ?? []
        // Downloads create the region cache, so refresh its size whenever the list reloads.
        Task { cachedRegionBytes = await OsmCourseSource.shared.cachedRegionBytes() }
    }

    private func deleteCourses(at offsets: IndexSet) {
        let store = CourseStore()
        for idx in offsets {
            try? store.delete(id: savedCourses[idx].id)
        }
        savedCourses.remove(atOffsets: offsets)
        Task { await overpassClient.clearCache() }
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

                // Static index first: covers every course in the data. GolfCourseAPI only when it has no match.
                let staticHits: [OsmIndexEntry]
                do {
                    staticHits = try await OsmCourseSource.shared.search(name: query, near: location)
                } catch {
                    print("[OSM] manage courses name search '\(query)' failed: \(error)")
                    staticHits = []
                }
                print("[OSM] manage courses name search '\(query)': \(staticHits.count) index hits")

                let results: [CourseSearchResult]
                if !staticHits.isEmpty {
                    results = staticHits.map { e in
                        CourseSearchResult(id: "osm-\(e.osmId)", name: e.name, location: e.point, osmType: "static", osmId: 0, city: e.city)
                    }
                } else {
                    let apiResults = try await golfCourseAPI.searchCourses(query: query, playerLocation: location)
                    results = apiResults.map { r in
                        CourseSearchResult(id: r.id, name: r.name, location: r.location, osmType: "api", osmId: 0, city: r.city, apiId: r.apiId)
                    }
                }

                await MainActor.run {
                    searchResults = results
                    isSearching = false
                    if results.isEmpty { errorMessage = "courses.noCoursesFound".localized }
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
