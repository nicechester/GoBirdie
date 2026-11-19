import Foundation

/// Helpers for the layouts of a multi-course complex (one `Course` per layout, named "Club – Layout").
public enum CourseLayouts {
    /// Joins layouts into one course for a round, e.g. two 9-hole layouts make 18 holes.
    /// Holes are renumbered 1…N in the order given. Par, yardage, and geometry stay with each hole.
    /// Name: "Club – Creek + Oaks". Returns nil for an empty list.
    public static func combine(_ layouts: [Course]) -> Course? {
        guard let first = layouts.first else { return nil }

        var holes: [Hole] = []
        for layout in layouts {
            for var hole in layout.holes {
                hole.number = holes.count + 1
                holes.append(hole)
            }
        }

        let club = clubName(first.name)
        let layoutNames = layouts.map { layoutName($0.name) }
        return Course(
            id: layouts.map(\.id).joined(separator: "+"),
            name: "\(club) – \(layoutNames.joined(separator: " + "))",
            location: first.location,
            holes: holes,
            downloadedAt: Date(),
            osmVersion: first.osmVersion
        )
    }

    /// Key shared by all layouts of one complex: "osm-a1-2" -> "osm-a1". A combined id uses its first layout.
    public static func complexKey(forId id: String) -> String {
        let working = id.components(separatedBy: "+").first ?? id
        let parts = working.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == "osm", !parts[1].isEmpty, !parts[2].isEmpty,
           parts[2].allSatisfy({ ("0"..."9").contains($0) }) {
            return "osm-" + String(parts[1])
        }
        return working
    }

    /// "Temecula Creek Inn Golf Course – Creek" -> "Temecula Creek Inn Golf Course"
    public static func clubName(_ name: String) -> String {
        name.components(separatedBy: " – ").first ?? name
    }

    /// "Temecula Creek Inn Golf Course – Creek" -> "Creek". A name with no layout part is returned unchanged.
    public static func layoutName(_ name: String) -> String {
        let parts = name.components(separatedBy: " – ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " – ") : name
    }

    /// Finds the saved course for a round, which stores no location, so it matches by id, then name, then pars.
    /// Order: exact id; else same club (non-combined ids), with a combined round's "A + B" layouts combined in order;
    /// else the club candidate with the same hole pars; else the first candidate with the same hole count; else nil.
    public static func resolveSavedCourse(id: String, roundCourseName: String, roundHolePars: [Int], saved: [Course]) -> Course? {
        if let exact = saved.first(where: { $0.id == id }) { return exact }

        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let wantedClub = normalized(clubName(roundCourseName))
        let candidates = saved.filter { !$0.id.contains("+") && normalized(clubName($0.name)) == wantedClub }

        if roundCourseName.contains(" + ") {
            let parts = layoutName(roundCourseName).components(separatedBy: " + ")
            let layouts = parts.compactMap { part in
                candidates.first { normalized(layoutName($0.name)) == normalized(part) }
            }
            if layouts.count == parts.count, let combined = combine(layouts) { return combined }
        }

        if let match = candidates.first(where: { $0.holes.count == roundHolePars.count && $0.holes.map(\.par) == roundHolePars }) {
            return match
        }
        return candidates.first { $0.holes.count == roundHolePars.count }
    }
}
