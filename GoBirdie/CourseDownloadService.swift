//
//  CourseDownloadService.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/18/26.
//

import Foundation
import GoBirdieCore

/// Service for downloading and merging golf course data from OSM and GolfCourseAPI.
class CourseDownloadService {
    private let overpassClient = OverpassClient()
    private let golfCourseAPI = GolfCourseAPIClient(apiKey: Config.golfCourseAPIKey)

    /// Result of downloading a course
    struct DownloadResult {
        let course: Course
        let isSingleCourse: Bool  // true if only one course was saved, false if part of multi-complex
    }

    /// Download and merge course data for a single selected course.
    /// - Parameters:
    ///   - courseId: Unique identifier for the course (e.g., "api-20781" or "osm-16307627")
    ///   - courseName: User-facing name of the course
    ///   - location: GPS location of the course
    ///   - teeColor: Tee color preference for GolfCourseAPI
    /// - Returns: The merged course ready to save
    func downloadCourse(
        id courseId: String,
        name courseName: String,
        location: GpsPoint,
        teeColor: String
    ) async throws -> DownloadResult {
        // 1. Static OSM data first: a course picked from the static index needs no live query.
        if let key = Self.staticOsmKey(courseId) {
            do {
                if let course = try await OsmCourseSource.shared.loadCourse(osmId: key, name: courseName, userLocation: location) {
                    print("[OSM] downloaded '\(courseName)' from static data: \(course.holes.count) holes")
                    return DownloadResult(course: course, isSingleCourse: true)
                }
                print("[OSM] '\(courseName)' (\(key)) not in static region data")
            } catch {
                print("[OSM] '\(courseName)' (\(key)) static load failed: \(error)")
            }
        }

        // 2. OSM geometry: Overpass for numeric IDs; static data by name for GolfCourseAPI courses.
        var osmCourses: [Course] = []
        if Self.staticOsmKey(courseId) != nil {
            // Not in the static data: exact name match on Overpass within 5 km, never just the nearest course.
            osmCourses = try await overpassCourses(matchingName: courseName, near: location)
        } else if let id = Self.numericOsmId(courseId) {
            osmCourses = (try? await overpassClient.downloadCourse(
                osmRelationId: id,
                name: courseName
            )) ?? []
        } else if let course = try? await OsmCourseSource.shared.loadNamedNear(name: courseName, location: location) {
            osmCourses = [course]
        } else if let id = try await overpassClient.searchCourses(location: location, radius: 2_000).first?.osmId {
            osmCourses = (try? await overpassClient.downloadCourse(
                osmRelationId: id,
                name: courseName
            )) ?? []
        }

        // 3. Fetch GolfCourseAPI courses and holes at this location
        let apiResults = (try? await golfCourseAPI.searchCourses(
            query: courseName,
            playerLocation: location
        ))?.filter { $0.location.distanceMeters(to: location) < 5_000 } ?? []

        var apiCourseHoles: [(name: String, id: String, holes: [GolfCourseHole])] = []
        for api in apiResults {
            guard let apiId = api.apiId else { continue }
            if let holes = try? await golfCourseAPI.fetchHoles(courseId: apiId, teeColor: teeColor),
               !holes.isEmpty {
                apiCourseHoles.append((name: api.name, id: apiId, holes: holes))
            }
        }

        // 4. Match and merge
        if osmCourses.count > 1 && !apiCourseHoles.isEmpty {
            // Multi-course complex: match selected course to best OSM layout by yardage
            let bestOsmCourse = matchApiToOsmByYardage(
                apiHoles: apiCourseHoles.first?.holes ?? [],
                osmCourses: osmCourses
            ) ?? osmCourses.first!

            let mergedCourse = mergeCourse(
                id: courseId,
                name: courseName,
                location: location,
                apiHoles: apiCourseHoles.first?.holes ?? [],
                osmCourse: bestOsmCourse,
                golfCourseApiId: apiCourseHoles.first?.id
            )

            return DownloadResult(course: mergedCourse, isSingleCourse: false)
        } else if let osmCourse = osmCourses.first {
            // Single OSM course or no multi-course: match to best API course
            let bestMatch = matchOsmToApiByYardage(
                osmCourse: osmCourse,
                apiCourses: apiCourseHoles
            )
            let matchedHoles = bestMatch?.holes ?? []
            let finalName = bestMatch?.name ?? courseName

            let mergedCourse = mergeCourse(
                id: courseId,
                name: finalName,
                location: location,
                apiHoles: matchedHoles,
                osmCourse: osmCourse,
                golfCourseApiId: bestMatch?.id
            )

            return DownloadResult(course: mergedCourse, isSingleCourse: true)
        } else {
            // No OSM data found
            throw CourseDownloadError.noOsmDataFound
        }
    }

    // MARK: - Private Helpers

    /// OSM key of a course from the static index (e.g. "osm-a2372626008"). Nil for numeric Overpass IDs and API IDs.
    static func staticOsmKey(_ courseId: String) -> String? {
        guard courseId.hasPrefix("osm-") else { return nil }
        let key = String(courseId.dropFirst(4))
        guard let first = key.first, first.isLetter, key.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return key
    }

    /// Numeric Overpass relation/way ID (e.g. "osm-16307627"). Nil otherwise.
    static func numericOsmId(_ courseId: String) -> Int64? {
        guard courseId.hasPrefix("osm-") else { return nil }
        return courseId.dropFirst(4).split(separator: "-").first.flatMap { Int64($0) }
    }

    /// Overpass course with exactly this name within 5 km. Returns no courses when none matches.
    private func overpassCourses(matchingName name: String, near location: GpsPoint) async throws -> [Course] {
        let nearby = try await overpassClient.searchCourses(location: location, radius: 5_000)
        guard let match = nearby.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return []
        }
        return (try? await overpassClient.downloadCourse(osmRelationId: match.osmId, name: name)) ?? []
    }

    /// Merge OSM and GolfCourseAPI data into a single Course.
    private func mergeCourse(
        id: String,
        name: String,
        location: GpsPoint,
        apiHoles: [GolfCourseHole],
        osmCourse: Course,
        golfCourseApiId: String?
    ) -> Course {
        let osmHoleMap = Dictionary(uniqueKeysWithValues: osmCourse.holes.map { ($0.number, $0) })

        let cappedApiHoles = !apiHoles.isEmpty
            ? Array(apiHoles.prefix(osmCourse.holes.count))
            : apiHoles

        let holes: [Hole] = cappedApiHoles.isEmpty
            ? osmCourse.holes
            : cappedApiHoles.map { api in
                let osm = osmHoleMap[api.number]
                return Hole(
                    id: osm?.id ?? UUID(),
                    number: api.number,
                    par: api.par,
                    handicap: api.handicap,
                    yardage: "\(api.yardage)",
                    tee: osm?.tee,
                    greenCenter: osm?.greenCenter,
                    greenFront: osm?.greenFront,
                    greenBack: osm?.greenBack,
                    geometry: osm?.geometry
                )
            }

        return Course(
            id: id,
            name: name,
            location: location,
            holes: holes,
            downloadedAt: Date(),
            osmVersion: 1,
            golfCourseApiId: golfCourseApiId
        )
    }

    /// Match GolfCourseAPI holes to the best OSM course layout by comparing yardages.
    private func matchApiToOsmByYardage(
        apiHoles: [GolfCourseHole],
        osmCourses: [Course]
    ) -> Course? {
        guard !apiHoles.isEmpty && !osmCourses.isEmpty else { return nil }

        var bestCourse: Course?
        var bestError = Double.infinity

        for osmCourse in osmCourses {
            let osmYards: [Int: Double] = Dictionary(uniqueKeysWithValues:
                osmCourse.holes.compactMap { hole -> (Int, Double)? in
                    guard let tee = hole.tee, let green = hole.greenCenter else { return nil }
                    return (hole.number, tee.distanceMeters(to: green) * 1.09361)
                }
            )
            guard !osmYards.isEmpty else { continue }

            var totalError = 0.0
            for (i, h) in apiHoles.enumerated() {
                if let osmYd = osmYards[i + 1] {
                    let diff = osmYd - Double(h.yardage)
                    totalError += diff * diff
                }
            }

            if totalError < bestError {
                bestError = totalError
                bestCourse = osmCourse
            }
        }

        return bestCourse
    }

    /// Match an OSM course to the best GolfCourseAPI course by comparing yardages.
    private func matchOsmToApiByYardage(
        osmCourse: Course,
        apiCourses: [(name: String, id: String, holes: [GolfCourseHole])]
    ) -> (name: String, id: String, holes: [GolfCourseHole])? {
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

        for (idx, api) in apiCourses.enumerated() {
            var totalError = 0.0
            for (i, h) in api.holes.enumerated() {
                if let osmYd = osmYards[i + 1] {
                    let diff = osmYd - Double(h.yardage)
                    totalError += diff * diff
                }
            }
            if totalError < bestError {
                bestError = totalError
                bestIdx = idx
            }
        }

        return bestIdx.map { apiCourses[$0] }
    }
}

enum CourseDownloadError: LocalizedError {
    case noOsmDataFound

    var errorDescription: String? {
        switch self {
        case .noOsmDataFound:
            return "Could not find course geometry data"
        }
    }
}
