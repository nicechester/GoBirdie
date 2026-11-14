import Foundation

/// The region file for the user's location, on disk. Only one region is kept: a new region replaces the old one.
/// The release file is gzipped; it is gunzipped once, as a stream, and the plain GeoJSON is what gets read.
actor OsmRegionCache {
    private static let releaseBase = URL(string: "https://github.com/nicechester/osm-golf-courses/releases/latest/download/")!

    private let dir: URL
    private let session: URLSession

    init(dir: URL, session: URLSession) {
        self.dir = dir
        self.session = session
    }

    /// Plain GeoJSON for `fileName` (a `.geojson.gz` name from the index). Downloads and gunzips it first if not cached.
    func ensure(_ fileName: String) async throws -> URL {
        let plainName = String(fileName.dropLast(3))  // "x.geojson.gz" -> "x.geojson"
        let target = dir.appendingPathComponent(plainName)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: target.path))?[.size] as? Int, size > 0 {
            print("[OSM] region cache hit: \(plainName)")
            return target
        }
        print("[OSM] downloading region: \(fileName)")

        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Replace whatever region was cached before.
        for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: old)
        }

        let (downloaded, response) = try await session.download(
            from: Self.releaseBase.appendingPathComponent(fileName)
        )
        defer { try? fm.removeItem(at: downloaded) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OsmDataError.downloadFailed
        }

        let part = dir.appendingPathComponent(plainName + ".part")
        try? fm.removeItem(at: part)
        try gunzipFile(at: downloaded, to: part)
        try fm.moveItem(at: part, to: target)
        return target
    }

    /// Bytes used by the cached region.
    func size() -> Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, file in
            total + ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// Deletes the cached region and returns the bytes freed. Downloaded courses are not affected.
    func clear() -> Int {
        let freed = size()
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: file)
        }
        return freed
    }
}
