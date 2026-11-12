//
//  RoundInsightsEngine.swift
//  GoBirdieCore

import Foundation

public struct RoundInsight: Sendable {
    public enum Severity: Int, Sendable { case critical = 0, warning, positive, info }
    public let code: String
    public let severity: Severity
    public let tier: Int
    public let params: [String: String]
    
    /// Localization key for this insight (e.g., "insight.SG_PUTTING_CRITICAL")
    public var localizationKey: String { "insight.\(code)" }
}

// MARK: - Analytics Context

struct InsightContext {
    // Basic stats
    let holesPlayed: Int
    let girPct: Int
    let fir: Int
    let threePutts: Int
    let onePutts: Int
    let scramblingPct: Int
    let frontScore: Int?
    let backScore: Int?
    let par3AvgOverPar: Double
    let par5AvgOverPar: Double
    let maxConsecBogeys: Int
    let totalPutts: Int

    // SG categories (relative to baseline)
    let sgOffTee: Double
    let sgApproach: Double
    let sgShortGame: Double
    let sgPutting: Double
    var sgTotal: Double { sgOffTee + sgApproach + sgShortGame + sgPutting }

    // Club analysis
    let bestClub: ClubStat?
    let worstClub: ClubStat?
    let driverDistStd: Double?
    let driverAvgDev: Double?  // lateral deviation angle avg (not available without GPS, nil if unknown)

    // Health
    let earlyRoundHr: Double?
    let lateRoundHr: Double?
    let bbEnd: Int?
    let bbDrain: Int?

    // Historical
    let histDriverAvgDiff: Double?   // curr - hist (negative = shorter today)
    let histApproachAvgDiff: Double? // curr - hist (positive = farther from pin today)
    let longestDriveYards: Int?

    // Duration
    let durationMin: Double?
}

struct ClubStat {
    let name: String
    let avgSg: Double
    let shots: Int
    let distStd: Double?
}

// MARK: - Engine

public struct RoundInsightsEngine {

    // MARK: - Public API

    public static func generate(
        round: Round,
        courseHoles: [Hole] = [],
        historicalRounds: [Round] = [],
        baseline: SGBaseline = .bogey
    ) -> [RoundInsight] {
        let played = round.holes.filter { $0.strokes > 0 }
        guard played.count >= 4 else { return [] }

        let ctx = buildContext(round: round, played: played, historicalRounds: historicalRounds, baseline: baseline)
        return evaluate(ctx: ctx)
    }

    // MARK: - Context Builder

    private static func buildContext(
        round: Round,
        played: [HoleScore],
        historicalRounds: [Round],
        baseline: SGBaseline
    ) -> InsightContext {
        let holesPlayed = played.count
        let totalPutts = played.reduce(0) { $0 + $1.putts }
        let threePutts = played.filter { $0.putts >= 3 }.count
        let onePutts   = played.filter { $0.putts == 1 }.count

        let firHoles = played.filter { $0.par >= 4 }
        let firPct   = firHoles.isEmpty ? 0 : firHoles.filter { $0.fairwayHit == true }.count * 100 / firHoles.count
        let girCount = played.filter { $0.gir }.count
        let girPct   = girCount * 100 / holesPlayed

        let missedGir    = played.filter { !$0.gir }
        let scrambled    = missedGir.filter { $0.strokes <= $0.par }.count
        let scramblingPct = missedGir.isEmpty ? 100 : scrambled * 100 / missedGir.count

        let front = played.filter { $0.number <= 9 }
        let back  = played.filter { $0.number > 9 }
        let frontScore: Int? = front.count >= 8 ? front.reduce(0) { $0 + $1.strokes } : nil
        let backScore:  Int? = back.count  >= 8 ? back.reduce(0)  { $0 + $1.strokes } : nil

        let par3s = played.filter { $0.par == 3 }
        let par5s = played.filter { $0.par == 5 }
        let par3Avg = par3s.isEmpty ? 0.0 : Double(par3s.reduce(0) { $0 + $1.scoreVsPar }) / Double(par3s.count)
        let par5Avg = par5s.isEmpty ? 0.0 : Double(par5s.reduce(0) { $0 + $1.scoreVsPar }) / Double(par5s.count)

        var maxConsec = 0; var streak = 0
        for h in played.sorted(by: { $0.number < $1.number }) {
            if h.scoreVsPar > 0 { streak += 1; maxConsec = max(maxConsec, streak) } else { streak = 0 }
        }

        // SG estimation from shot data
        let exp = baseline.expectedSG
        let sgOffTee   = estimateSGOffTee(played: played)   - exp.offTee
        let sgApproach = estimateSGApproach(played: played) - exp.approach
        let sgShortGame = estimateSGShortGame(played: played) - exp.shortGame
        let sgPutting  = estimateSGPutting(played: played, holesPlayed: holesPlayed) - exp.putting

        // Club stats
        let clubStats = buildClubStats(played: played)
        let best  = clubStats.max(by: { $0.avgSg < $1.avgSg }).flatMap { $0.shots >= 2 && $0.avgSg > 0.2  ? $0 : nil }
        // Issue #38 Finding 4: lowered from -0.2 to -0.05 so WORST_CLUB_SG can fire
        let worst = clubStats.min(by: { $0.avgSg < $1.avgSg }).flatMap { $0.shots >= 2 && $0.avgSg < -0.05 ? $0 : nil }
        let driverStats = clubStats.first(where: { $0.name == "Driver" })

        // Health
        let sorted = round.heartRateTimeline.sorted { $0.timestamp < $1.timestamp }
        let earlyHr = sorted.prefix(max(1, sorted.count / 3)).map { Double($0.bpm) }.avg
        let lateHr  = sorted.suffix(max(1, sorted.count / 3)).map { Double($0.bpm) }.avg

        // Historical
        let history = Array(historicalRounds.filter { $0.id != round.id }.prefix(10))
        let histDriverAvg = trimmedMean(driverDistances(from: history))
        let currDriverAvg = trimmedMean(driverDistances(from: [round]))
        let histApproachAvg = trimmedMean(approachProximities(from: history))
        let currApproachAvg = trimmedMean(approachProximities(from: [round]))

        let histDriverDiff: Double? = (currDriverAvg != nil && histDriverAvg != nil && history.count >= 3)
            ? currDriverAvg! - histDriverAvg! : nil
        let histApproachDiff: Double? = (currApproachAvg != nil && histApproachAvg != nil && history.count >= 3)
            ? currApproachAvg! - histApproachAvg! : nil

        var longestDrive: Int?
        for hole in played {
            let shots = hole.shots.sorted { $0.sequence < $1.sequence }
            guard let first = shots.first, first.club == .driver, shots.count > 1 else { continue }
            let yards = Int((first.location.distanceMeters(to: shots[1].location) * 1.09361).rounded())
            if yards > 50 { longestDrive = max(longestDrive ?? 0, yards) }
        }

        let duration: Double? = round.endedAt.map { $0.timeIntervalSince(round.startedAt) / 60 }

        return InsightContext(
            holesPlayed: holesPlayed,
            girPct: girPct,
            fir: firPct,
            threePutts: threePutts,
            onePutts: onePutts,
            scramblingPct: scramblingPct,
            frontScore: frontScore,
            backScore: backScore,
            par3AvgOverPar: par3Avg,
            par5AvgOverPar: par5Avg,
            maxConsecBogeys: maxConsec,
            totalPutts: totalPutts,
            sgOffTee: sgOffTee,
            sgApproach: sgApproach,
            sgShortGame: sgShortGame,
            sgPutting: sgPutting,
            bestClub: best,
            worstClub: worst,
            driverDistStd: driverStats?.distStd,
            driverAvgDev: nil,
            earlyRoundHr: earlyHr,
            lateRoundHr: lateHr,
            bbEnd: nil,
            bbDrain: nil,
            histDriverAvgDiff: histDriverDiff,
            histApproachAvgDiff: histApproachDiff,
            longestDriveYards: longestDrive,
            durationMin: duration
        )
    }

    // MARK: - SG Estimators

    /// Off-tee SG: derived from fairway hit rate vs par-4/5 baseline.
    private static func estimateSGOffTee(played: [HoleScore]) -> Double {
        let teeHoles = played.filter { $0.par >= 4 }
        guard !teeHoles.isEmpty else { return 0 }
        let firPct = Double(teeHoles.filter { $0.fairwayHit == true }.count) / Double(teeHoles.count)
        // Tour average FIR ~60%; each 10% miss ≈ 0.3 SG penalty
        return (firPct - 0.60) * 3.0
    }

    /// Approach SG: derived from GIR rate and proximity.
    private static func estimateSGApproach(played: [HoleScore]) -> Double {
        let girPct = Double(played.filter { $0.gir }.count) / Double(played.count)
        // Tour average GIR ~65%; each 10% below ≈ 0.5 SG lost
        return (girPct - 0.65) * 5.0
    }

    /// Short game SG: scrambling-based estimate.
    private static func estimateSGShortGame(played: [HoleScore]) -> Double {
        let missedGir = played.filter { !$0.gir }
        guard !missedGir.isEmpty else { return 0.5 }
        let scramblePct = Double(missedGir.filter { $0.strokes <= $0.par }.count) / Double(missedGir.count)
        // Tour average scrambling ~58%; each 10% delta ≈ 0.4 SG
        return (scramblePct - 0.58) * 4.0
    }

    /// Putting SG: putts per GIR hole vs baseline of 1.8.
    private static func estimateSGPutting(played: [HoleScore], holesPlayed: Int) -> Double {
        guard holesPlayed > 0 else { return 0 }
        let avgPutts = Double(played.reduce(0) { $0 + $1.putts }) / Double(holesPlayed)
        // Tour average ~1.73 putts/hole; each 0.1 delta ≈ 0.3 SG
        return (1.73 - avgPutts) * 3.0
    }

    // MARK: - Club Analysis

    private static func buildClubStats(played: [HoleScore]) -> [ClubStat] {
        var clubShots: [ClubType: [(sg: Double, dist: Double)]] = [:]

        for hole in played {
            let shots = hole.shots.sorted { $0.sequence < $1.sequence }
            for i in 0..<shots.count {
                let shot = shots[i]
                guard shot.club != .unknown && shot.club != .putter else { continue }
                let dist: Double
                if i + 1 < shots.count {
                    dist = shot.location.distanceMeters(to: shots[i + 1].location) * 1.09361
                } else {
                    dist = 0
                }
                // Simple SG proxy: did this shot lead to GIR or close proximity?
                let sgProxy: Double
                if let pin = shots[i].distanceToPinYards {
                    sgProxy = pin < 20 ? 0.4 : pin < 40 ? 0.1 : -0.1
                } else {
                    sgProxy = hole.gir ? 0.1 : -0.1
                }
                clubShots[shot.club, default: []].append((sg: sgProxy, dist: dist))
            }
        }

        return clubShots.compactMap { (club, data) -> ClubStat? in
            guard data.count >= 2 else { return nil }
            let avgSg = data.map { $0.sg }.reduce(0, +) / Double(data.count)
            let dists = data.map { $0.dist }.filter { $0 > 0 }
            let distStd: Double? = dists.count >= 3 ? standardDeviation(dists) : nil
            return ClubStat(name: club.displayName, avgSg: avgSg, shots: data.count, distStd: distStd)
        }
    }

    // MARK: - Template Evaluation

    private static func evaluate(ctx: InsightContext) -> [RoundInsight] {
        var fired: [RoundInsight] = []

        func add(_ code: String, _ severity: RoundInsight.Severity, _ tier: Int, _ params: [String: String] = [:]) {
            fired.append(RoundInsight(code: code, severity: severity, tier: tier, params: params))
        }

        let sg = (offTee: ctx.sgOffTee, approach: ctx.sgApproach, shortGame: ctx.sgShortGame, putting: ctx.sgPutting, total: ctx.sgTotal)

        // ── TIER 1: Critical SG ──────────────────────────────────────────────

        if sg.putting < -1.5 {
            add("SG_PUTTING_CRITICAL", .critical, 1, ["sg": sgFmt(sg.putting)])
        }
        if sg.approach < -1.5 {
            add("SG_APPROACH_CRITICAL", .critical, 1, ["sg": sgFmt(sg.approach)])
        }
        if sg.offTee < -1.5 {
            add("SG_OFF_TEE_CRITICAL", .critical, 1, ["sg": sgFmt(sg.offTee)])
        }
        if sg.shortGame < -1.0 {
            add("SG_SHORT_GAME_CRITICAL", .critical, 1, ["sg": sgFmt(sg.shortGame)])
        }

        // ── TIER 1: Strong positives ──────────────────────────────────────────

        if sg.putting > 1.0 {
            add("SG_PUTTING_STRONG", .positive, 1, ["sg": sgFmt(sg.putting)])
        }
        if sg.approach > 1.0 {
            add("SG_APPROACH_STRONG", .positive, 1, ["sg": sgFmt(sg.approach)])
        }
        if sg.shortGame > 0.8 {
            add("SG_SHORT_GAME_STRONG", .positive, 1, ["sg": sgFmt(sg.shortGame)])
        }
        if sg.offTee > 1.0 {
            add("SG_OFF_TEE_STRONG", .positive, 1, ["sg": sgFmt(sg.offTee)])
        }
        if sg.total > 2.0 {
            add("SG_TOTAL_POSITIVE", .positive, 1, ["sg": sgFmt(sg.total)])
        }

        // ── TIER 2: Correlations & patterns ──────────────────────────────────

        if ctx.fir >= 55 && ctx.girPct < 35 {
            add("HIGH_FIR_LOW_GIR", .critical, 2, ["fir": "\(ctx.fir)", "gir": "\(ctx.girPct)"])
        }
        if ctx.fir < 35 && ctx.girPct >= 50 {
            add("LOW_FIR_HIGH_GIR", .info, 2, ["fir": "\(ctx.fir)", "gir": "\(ctx.girPct)"])
        }
        if ctx.threePutts >= 3 {
            add("THREE_PUTTS_CRITICAL", .critical, 2, ["count": "\(ctx.threePutts)"])
        } else if ctx.threePutts == 2 {
            add("THREE_PUTTS_WARNING", .warning, 2, ["count": "\(ctx.threePutts)"])
        }
        if ctx.scramblingPct >= 50 && ctx.girPct < 45 {
            add("GOOD_SCRAMBLING", .positive, 2, ["gir": "\(ctx.girPct)", "scramble": "\(ctx.scramblingPct)"])
        }
        if ctx.scramblingPct < 25 && ctx.girPct < 45 && sg.shortGame < 0 {
            add("POOR_SCRAMBLING", .critical, 2, ["missedGir": "\(100 - ctx.girPct)", "scramble": "\(ctx.scramblingPct)"])
        }
        if let f = ctx.frontScore, let b = ctx.backScore {
            if b > f + 4 {
                add("FRONT_BACK_WORSE", .warning, 2, ["front": "\(f)", "back": "\(b)", "diff": "\(b - f)"])
            } else if f > b + 3 {
                add("FRONT_BACK_BETTER", .positive, 2, ["front": "\(f)", "back": "\(b)", "diff": "\(f - b)"])
            }
        }
        if ctx.par3AvgOverPar > 0.8 {
            add("PAR3_STRUGGLES", .warning, 2, ["avg": String(format: "%.1f", ctx.par3AvgOverPar)])
        }
        if ctx.par5AvgOverPar > 0.5 {
            add("PAR5_SCORING", .warning, 2, ["avg": String(format: "%.1f", ctx.par5AvgOverPar)])
        } else if ctx.par5AvgOverPar < -0.3 {
            add("PAR5_BIRDIE_MACHINE", .positive, 2, ["avg": String(format: "%.1f", ctx.par5AvgOverPar)])
        }
        if ctx.maxConsecBogeys >= 3 {
            add("CONSECUTIVE_BOGEYS", .warning, 2, ["count": "\(ctx.maxConsecBogeys)"])
        }
        if let early = ctx.earlyRoundHr, let late = ctx.lateRoundHr, late > early + 8 {
            add("HIGH_HR_LATE_ROUND", .info, 2, ["diff": "\(Int(late - early))"])
        }

        // ── TIER 3: Club-specific ─────────────────────────────────────────────

        if let worst = ctx.worstClub {
            add("WORST_CLUB_SG", .warning, 3, ["club": worst.name, "sg": sgFmt(worst.avgSg), "shots": "\(worst.shots)"])
        }
        if let best = ctx.bestClub {
            add("BEST_CLUB_SG", .positive, 3, ["club": best.name, "sg": sgFmt(best.avgSg), "shots": "\(best.shots)"])
        }
        if let std = ctx.driverDistStd, std > 30 {
            add("DRIVER_INCONSISTENT", .warning, 3, ["std": "\(Int(std))"])
        }

        // ── TIER 4: Minor observations & positives ────────────────────────────

        if ctx.onePutts >= 4 {
            add("ONE_PUTTS_HIGH", .positive, 4, ["count": "\(ctx.onePutts)"])
        }
        if ctx.threePutts == 0 && ctx.totalPutts <= Int(Double(ctx.holesPlayed) * 1.8) {
            add("ZERO_THREE_PUTTS", .positive, 4, [:])
        }
        if let ld = ctx.longestDriveYards, ld >= 270 {
            add("LONGEST_DRIVE", .positive, 4, ["yards": "\(ld)"])
        }
        if let diff = ctx.histDriverAvgDiff {
            if diff <= -15 {
                add("DRIVER_DOWN_VS_HISTORY", .warning, 4, ["diff": "\(Int(-diff))"])
            } else if diff >= 10 {
                add("DRIVER_UP_VS_HISTORY", .positive, 4, ["diff": "\(Int(diff))"])
            }
        }
        if let diff = ctx.histApproachAvgDiff {
            if diff >= 8 {
                add("APPROACH_WORSE_VS_HISTORY", .warning, 4, ["diff": "\(Int(diff))"])
            } else if diff <= -6 {
                add("APPROACH_BETTER_VS_HISTORY", .positive, 4, ["diff": "\(Int(-diff))"])
            }
        }
        if let mins = ctx.durationMin, mins > 270 {
            add("ROUND_DURATION_LONG", .info, 4, ["mins": "\(Int(mins))"])
        }

        // ── Rank: tier → severity, cap positives ────────────────────────────

        fired.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            return $0.severity.rawValue < $1.severity.rawValue
        }

        let negatives = fired.filter { $0.severity == .critical || $0.severity == .warning }
        let positives = fired.filter { $0.severity == .positive || $0.severity == .info }
        let maxPositives = negatives.isEmpty ? 6 : 2
        return Array((negatives.prefix(4) + positives.prefix(maxPositives)).prefix(6))
    }

    // MARK: - Helpers

    private static func sgFmt(_ v: Double) -> String {
        (v >= 0 ? "+" : "") + String(format: "%.2f", v)
    }

    private static func trimmedMean(_ values: [Double], trimFraction: Double = 0.2) -> Double? {
        guard values.count >= 3 else { return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let sorted = values.sorted()
        let drop = max(1, Int((Double(sorted.count) * trimFraction).rounded()))
        let trimmed = Array(sorted.dropFirst(drop).dropLast(drop))
        guard !trimmed.isEmpty else { return nil }
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }

    private static func driverDistances(from rounds: [Round]) -> [Double] {
        rounds.flatMap { round in
            round.holes.compactMap { hole -> Double? in
                let sorted = hole.shots.sorted { $0.sequence < $1.sequence }
                guard sorted.count >= 2, sorted[0].club == .driver else { return nil }
                let yards = sorted[0].location.distanceMeters(to: sorted[1].location) * 1.09361
                return yards > 50 ? yards : nil
            }
        }
    }

    private static func approachProximities(from rounds: [Round]) -> [Double] {
        rounds.flatMap { round in
            round.holes.compactMap { hole -> Double? in
                let sorted = hole.shots.sorted { $0.sequence < $1.sequence }
                guard sorted.count >= 2 else { return nil }
                let nonPutts = sorted.filter { $0.club != .putter && $0.club != .unknown }
                guard let approach = nonPutts.last,
                      let next = sorted.first(where: { $0.sequence == approach.sequence + 1 }),
                      let prox = next.distanceToPinYards,
                      prox < 100 else { return nil }
                return Double(prox)
            }
        }
    }
}

// MARK: - Array avg helper

private extension Array where Element == Double {
    var avg: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
