import Foundation
import CryptoKit

/// Caches raw Overpass API responses to disk keyed by SHA256 of the query.
/// TTL: 7 days — OSM data doesn't change often.
actor OverpassCache {
    static let shared = OverpassCache()

    private let cacheDir: URL
    private let ttl: TimeInterval = 7 * 24 * 3600  // 7 days

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDir = docs.appendingPathComponent("GoBirdie/overpass_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func get(query: String) -> Data? {
        let url = fileURL(for: query)
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < ttl
        else { return nil }
        let data = try? Data(contentsOf: url)
        if data != nil { print("[OverpassCache] HIT \(url.lastPathComponent)") }
        return data
    }

    func set(query: String, data: Data) {
        let url = fileURL(for: query)
        try? data.write(to: url, options: .atomic)
        print("[OverpassCache] STORED \(url.lastPathComponent) (\(data.count) bytes)")
    }

    func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDir,
            includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" } ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        print("[OverpassCache] Cleared \(files.count) entries")
    }

    private func fileURL(for query: String) -> URL {
        let hash = SHA256.hash(data: Data(query.utf8))
            .compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        return cacheDir.appendingPathComponent("\(hash).json")
    }
}
