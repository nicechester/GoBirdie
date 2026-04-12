import Foundation

/// Snapshot of an in-progress round, enough to fully restore state.
public struct InProgressSnapshot: Codable, Sendable {
    public var round: Round
    public var courseId: String
    public var currentHoleIndex: Int

    public init(round: Round, courseId: String, currentHoleIndex: Int) {
        self.round = round
        self.courseId = courseId
        self.currentHoleIndex = currentHoleIndex
    }
}

/// Persists a single in-progress round to disk.
/// File: <Documents>/GoBirdie/in_progress.json
public final class InProgressStore: Sendable {

    private let fileURL: URL

    public init(documentsURL: URL = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        let dir = documentsURL.appendingPathComponent("GoBirdie")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("in_progress.json")
    }

    public func save(_ snapshot: InProgressSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> InProgressSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InProgressSnapshot.self, from: data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
