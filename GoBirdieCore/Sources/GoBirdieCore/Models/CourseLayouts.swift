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

    /// Finds the saved course for a round. A round stores no course location, but it stores each hole's green center.
    /// Order: exact id; else same club (non-combined ids), with a combined round's "A + B" layouts combined in order;
    /// else the club candidate with the same hole pars; else any saved course whose green centers match the round's
    /// (within 50 m on most holes, at least 3 compared); else the first candidate with the same hole count; else nil.
    public static func resolveSavedCourse(
        id: String,
        roundCourseName: String,
        roundHolePars: [Int],
        roundGreens: [Int: GpsPoint] = [:],
        saved: [Course]
    ) -> Course? {
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

        // No name match (e.g. GolfCourseAPI names like "Course #2 (E.O. Nay)"): compare green centers across all saved courses.
        if let match = greenMatch(roundCourseName: roundCourseName, roundGreens: roundGreens, saved: saved) {
            return match
        }
        return candidates.first { $0.holes.count == roundHolePars.count }
    }

    /// The saved non-combined course that matches the round by green centers and by name.
    /// Green match: at least 3 holes compared and at least 80% within `radiusMeters`.
    /// Name hint: the saved layout (or club) name appears in the round's name, e.g. "E.O. Nay" in "Course #2 (E.O. Nay)".
    /// Ranked by green match ratio, then name hint. Nil when nothing qualifies or the top two tie on both.
    static func greenMatch(roundCourseName: String, roundGreens: [Int: GpsPoint], saved: [Course], radiusMeters: Double = 50) -> Course? {
        guard roundGreens.count >= 3 else { return nil }
        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let roundName = normalized(roundCourseName)

        var scored: [(course: Course, ratio: Double, nameHit: Bool)] = []
        for course in saved where !course.id.contains("+") {
            var matched = 0
            var compared = 0
            for hole in course.holes {
                guard let roundGreen = roundGreens[hole.number], let green = hole.greenCenter else { continue }
                compared += 1
                if roundGreen.distanceMeters(to: green) <= radiusMeters { matched += 1 }
            }
            guard compared >= 3 else { continue }
            let ratio = Double(matched) / Double(compared)
            guard ratio >= 0.8 else { continue }

            // Layout part without the generic " Course" suffix, e.g. "E.O. Nay Course" -> "e.o. nay".
            var layout = normalized(layoutName(course.name))
            for suffix in [" golf course", " course"] where layout.hasSuffix(suffix) {
                layout = String(layout.dropLast(suffix.count))
                break
            }
            let nameHit = (!layout.isEmpty && layout != normalized(course.name) && roundName.contains(layout))
                || roundName.contains(normalized(clubName(course.name)))
            scored.append((course, ratio, nameHit))
        }

        scored.sort { lhs, rhs in
            if lhs.ratio != rhs.ratio { return lhs.ratio > rhs.ratio }
            return lhs.nameHit && !rhs.nameHit
        }
        guard let best = scored.first else { return nil }
        if scored.count > 1 {
            let runnerUp = scored[1]
            if runnerUp.ratio == best.ratio && runnerUp.nameHit == best.nameHit { return nil }
        }
        return best.course
    }
}
