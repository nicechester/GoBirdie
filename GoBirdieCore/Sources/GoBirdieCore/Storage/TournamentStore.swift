import Foundation

/// Persists Tournament values as individual JSON files.
/// Storage path: <Documents>/GoBirdie/tournaments/<id>.json
public final class TournamentStore: Sendable {

    private let baseURL: URL

    public init(documentsURL: URL = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        baseURL = documentsURL
            .appendingPathComponent("GoBirdie")
            .appendingPathComponent("tournaments")
    }

    public func save(_ tournament: Tournament) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try makeEncoder().encode(tournament)
        try data.write(to: fileURL(for: tournament.id), options: .atomic)
    }

    public func loadAll() throws -> [Tournament] {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        let decoder = makeDecoder()
        return urls
            .compactMap { try? decoder.decode(Tournament.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    public func load(id: String) throws -> Tournament? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try makeDecoder().decode(Tournament.self, from: Data(contentsOf: url))
    }

    public func delete(id: String) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: ":", with: "_")
        return baseURL.appendingPathComponent("\(safe).json")
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
