import Foundation

/// Client for the GolfCourse API (golfcourseapi.com).
/// Provides course search by name and hole-level par/yardage/handicap data.
public actor GolfCourseAPIClient {

    private let baseURL = "https://api.golfcourseapi.com/v1"
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - Search

    /// Search courses by name, sorted by distance from playerLocation.
    public func searchCourses(query: String, playerLocation: GpsPoint) async throws -> [GolfCourseResult] {
        guard var components = URLComponents(string: "\(baseURL)/search") else {
            throw GolfCourseAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        guard let url = components.url else { throw GolfCourseAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GolfCourseAPIError.invalidResponse }
        print("[GolfCourseAPI] Search '\(query)' -> HTTP \(http.statusCode)")

        switch http.statusCode {
        case 200: break
        case 401: throw GolfCourseAPIError.unauthorized
        case 429: throw GolfCourseAPIError.rateLimited
        default:  throw GolfCourseAPIError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.courses
            .map { GolfCourseResult(from: $0) }
            .sorted { $0.location.distanceMeters(to: playerLocation) < $1.location.distanceMeters(to: playerLocation) }
    }

    /// Fetch hole data (par, yardage, handicap) for a course by ID.
    /// - Parameter teeColor: Preferred tee name e.g. "Blue", "White". Falls back to first available.
    public func fetchHoles(courseId: Int, teeColor: String = "Blue") async throws -> [GolfCourseHole] {
        guard let url = URL(string: "\(baseURL)/courses/\(courseId)") else {
            throw GolfCourseAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GolfCourseAPIError.invalidResponse }
        print("[GolfCourseAPI] Fetch course \(courseId) -> HTTP \(http.statusCode)")

        switch http.statusCode {
        case 200: break
        case 401: throw GolfCourseAPIError.unauthorized
        case 429: throw GolfCourseAPIError.rateLimited
        case 404: throw GolfCourseAPIError.notFound
        default:  throw GolfCourseAPIError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(CourseDetailResponse.self, from: data)
        let teeList = decoded.course.tees.male ?? decoded.course.tees.female ?? []

        // Find requested tee color, fall back to first available
        let tee = teeList.first(where: { $0.tee_name.lowercased() == teeColor.lowercased() })
               ?? teeList.first
        guard let tee else { throw GolfCourseAPIError.noHoleData }

        print("[GolfCourseAPI] Using tee: \(tee.tee_name)")
        return tee.holes.enumerated().map { idx, h in
            GolfCourseHole(number: idx + 1, par: h.par, yardage: h.yardage, handicap: h.handicap)
        }
    }
}

// MARK: - Public result types

public struct GolfCourseResult: Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let location: GpsPoint
    public let city: String

    public init(id: Int, name: String, location: GpsPoint, city: String) {
        self.id = id; self.name = name; self.location = location; self.city = city
    }

    fileprivate init(from api: APICourse) {
        self.id       = api.id
        self.name     = api.course_name
        self.location = GpsPoint(lat: api.location.latitude, lon: api.location.longitude)
        self.city     = [api.location.city, api.location.state].compactMap { $0 }.joined(separator: ", ")
    }
}

public struct GolfCourseHole: Sendable {
    public let number: Int
    public let par: Int
    public let yardage: Int
    public let handicap: Int?
}

// MARK: - Private decodable types

private struct SearchResponse: Decodable { let courses: [APICourse] }
private struct CourseDetailResponse: Decodable { let course: APICourse }

private struct APICourse: Decodable {
    let id: Int
    let course_name: String
    let location: APILocation
    let tees: APITees
}

private struct APILocation: Decodable {
    let city: String?
    let state: String?
    let latitude: Double
    let longitude: Double
}

private struct APITees: Decodable {
    let male: [APITee]?
    let female: [APITee]?
}

private struct APITee: Decodable {
    let tee_name: String
    let holes: [APIHole]
}

private struct APIHole: Decodable {
    let par: Int
    let yardage: Int
    let handicap: Int?
}

// MARK: - Errors

public enum GolfCourseAPIError: LocalizedError {
    case invalidURL, invalidResponse, unauthorized, rateLimited, notFound, noHoleData
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid URL"
        case .invalidResponse:  return "Invalid response"
        case .unauthorized:     return "Invalid API key"
        case .rateLimited:      return "Rate limited — try again shortly"
        case .notFound:         return "Course not found"
        case .noHoleData:       return "No hole data available"
        case .httpError(let c): return "HTTP error \(c)"
        }
    }
}
