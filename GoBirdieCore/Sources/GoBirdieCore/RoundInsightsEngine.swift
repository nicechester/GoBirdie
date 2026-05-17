//
//  RoundInsightsEngine.swift
//  GoBirdieCore

import Foundation

public struct RoundInsight: Sendable {
    public enum Severity: Int, Sendable { case critical = 0, warning, positive, info }
    public let severity: Severity
    public let message: String
}

public struct RoundInsightsEngine {

    public static func generate(round: Round, courseHoles: [Hole] = []) -> [RoundInsight] {
        let played = round.holes.filter { $0.strokes > 0 }
        guard played.count >= 4 else { return [] }

        let holesPlayed = played.count
        let totalPutts = played.reduce(0) { $0 + $1.putts }

        // Three-putts
        let threePutts = played.filter { $0.putts >= 3 }.count
        // One-putts
        let onePutts = played.filter { $0.putts == 1 }.count

        // FIR (par 4+ only)
        let firHoles = played.filter { $0.par >= 4 }
        let firCount = firHoles.filter { $0.fairwayHit == true }.count
        let firPct = firHoles.isEmpty ? 0 : firCount * 100 / firHoles.count

        // GIR
        let girCount = played.filter(\.gir).count
        let girPct = girCount * 100 / holesPlayed

        // Scrambling: par-or-better on missed-GIR holes
        let missedGir = played.filter { !$0.gir }
        let scrambled = missedGir.filter { $0.strokes <= $0.par }.count
        let scramblingPct = missedGir.isEmpty ? 100 : scrambled * 100 / missedGir.count

        // Front/back split
        let front = played.filter { $0.number <= 9 }
        let back = played.filter { $0.number > 9 }
        let frontScore = front.count >= 8 ? front.reduce(0) { $0 + $1.strokes } : nil
        let backScore = back.count >= 8 ? back.reduce(0) { $0 + $1.strokes } : nil

        // Par 3 / Par 5 averages
        let par3s = played.filter { $0.par == 3 }
        let par5s = played.filter { $0.par == 5 }
        let par3Avg = par3s.isEmpty ? 0.0 : Double(par3s.reduce(0) { $0 + $1.scoreVsPar }) / Double(par3s.count)
        let par5Avg = par5s.isEmpty ? 0.0 : Double(par5s.reduce(0) { $0 + $1.scoreVsPar }) / Double(par5s.count)

        // Consecutive bogeys
        var maxConsecBogeys = 0
        var streak = 0
        for h in played.sorted(by: { $0.number < $1.number }) {
            if h.scoreVsPar > 0 { streak += 1; maxConsecBogeys = max(maxConsecBogeys, streak) }
            else { streak = 0 }
        }

        // Longest drive
        var longestDriveYards: Int?
        for hole in played {
            let sorted = hole.shots.sorted { $0.sequence < $1.sequence }
            guard let first = sorted.first, first.club == .driver, sorted.count > 1 else { continue }
            let target = sorted[1].location
            let yards = Int((first.location.distanceMeters(to: target) * 1.09361).rounded())
            if yards > (longestDriveYards ?? 0) { longestDriveYards = yards }
        }

        // --- Evaluate insights ---
        var insights: [RoundInsight] = []

        // Three-putts
        if threePutts >= 3 {
            insights.append(.init(severity: .critical, message: "\(threePutts) three-putts — that's \(threePutts) strokes given away. Lag putting needs work."))
        } else if threePutts == 2 {
            insights.append(.init(severity: .warning, message: "\(threePutts) three-putts today. Getting the first putt within 3 feet would save strokes."))
        }

        // FIR high but GIR low
        if firPct >= 55 && girPct < 35 {
            insights.append(.init(severity: .critical, message: "Hit \(firPct)% fairways but only \(girPct)% greens — irons aren't converting good drives."))
        }

        // Poor scrambling
        if scramblingPct < 25 && girPct < 45 {
            insights.append(.init(severity: .critical, message: "Only \(scramblingPct)% scrambling on missed greens. Short game practice would have a big impact."))
        } else if scramblingPct >= 50 && girPct < 45 {
            insights.append(.init(severity: .positive, message: "Only \(girPct)% GIR but scrambled \(scramblingPct)% — short game saved the round."))
        }

        // Front/back split
        if let f = frontScore, let b = backScore {
            if b > f + 4 {
                insights.append(.init(severity: .warning, message: "Front \(f), back \(b) — a \(b - f) shot drop-off. Fatigue may be a factor."))
            } else if f > b + 3 {
                insights.append(.init(severity: .positive, message: "Strong finish — improved \(f - b) shots from front (\(f)) to back (\(b))."))
            }
        }

        // Par 3 struggles
        if par3s.count >= 2 && par3Avg > 0.8 {
            insights.append(.init(severity: .warning, message: "Par 3s averaged +\(String(format: "%.1f", par3Avg)) — iron accuracy from the tee needs attention."))
        }

        // Par 5 scoring
        if par5s.count >= 2 && par5Avg > 0.5 {
            insights.append(.init(severity: .warning, message: "Par 5s averaged +\(String(format: "%.1f", par5Avg)) — not capitalizing on scoring holes."))
        } else if par5s.count >= 2 && par5Avg < -0.3 {
            insights.append(.init(severity: .positive, message: "Par 5s averaged \(String(format: "%.1f", par5Avg)) — great scoring on the long holes."))
        }

        // Consecutive bogeys
        if maxConsecBogeys >= 3 {
            insights.append(.init(severity: .warning, message: "\(maxConsecBogeys) bogeys in a row — breaking bad streaks early is key."))
        }

        // One-putts
        if onePutts >= 4 {
            insights.append(.init(severity: .positive, message: "\(onePutts) one-putts today — excellent close-range putting."))
        }

        // Zero three-putts + good putting average
        if threePutts == 0 && totalPutts <= Int(Double(holesPlayed) * 1.8) {
            insights.append(.init(severity: .positive, message: "Zero three-putts — lag putting distance control was excellent."))
        }

        // Longest drive callout
        if let ld = longestDriveYards, ld >= 270 {
            insights.append(.init(severity: .positive, message: "Longest drive: \(ld) yards — great power off the tee."))
        }

        // Rank: critical first, then warning, then positive/info. Return top 3.
        insights.sort { $0.severity.rawValue < $1.severity.rawValue }

        // Cap: max 1 positive if there are criticals/warnings
        let negatives = insights.filter { $0.severity == .critical || $0.severity == .warning }
        let positives = insights.filter { $0.severity == .positive || $0.severity == .info }
        if negatives.isEmpty {
            return Array(positives.prefix(3))
        }
        return Array((negatives.prefix(2) + positives.prefix(1)).prefix(3))
    }
}
