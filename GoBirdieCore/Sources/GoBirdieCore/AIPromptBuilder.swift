//
//  AIPromptBuilder.swift
//  GoBirdieCore

import Foundation

public struct AIPromptBuilder {
    
    public enum Language: String {
        case english = "en"
        case korean = "ko"
    }
    
    public static func build(
        round: Round,
        handicap: String = "Bogey Golfer",
        courseRating: Double? = nil,
        slope: Int? = nil,
        language: Language = .english
    ) -> String {
        let played = round.holes.filter { $0.strokes > 0 }
        guard !played.isEmpty else { return "No scorecard data available." }
        
        let totalPar = played.reduce(0) { $0 + $1.par }
        let totalPutts = played.reduce(0) { $0 + $1.putts }
        let overPar = round.totalStrokes - totalPar
        
        let front = played.filter { $0.number <= 9 }
        let back = played.filter { $0.number > 9 }
        let frontScore = front.reduce(0) { $0 + $1.strokes }
        let backScore = back.reduce(0) { $0 + $1.strokes }
        
        let dateStr = ISO8601DateFormatter().string(from: round.startedAt).prefix(10)
        let durationMin = round.endedAt.map { Int($0.timeIntervalSince(round.startedAt) / 60) } ?? 0
        
        // Heart rate stats
        let hrSamples = round.heartRateTimeline
        let avgHr = hrSamples.isEmpty ? 0 : hrSamples.reduce(0) { $0 + $1.bpm } / hrSamples.count
        let maxHr = hrSamples.map(\.bpm).max() ?? 0
        
        // Build summary
        var summary = "## Round Summary\n"
        summary += "Date: \(dateStr)\n"
        summary += "Course: \(round.courseName)"
        if let rating = courseRating, let sl = slope {
            summary += " (Rating \(String(format: "%.1f", rating)), Slope \(sl))"
        }
        summary += "\n"
        summary += "Your Handicap: \(handicap)\n"
        summary += "Score: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) over par \(totalPar)\n"
        
        if played.count >= 16 {
            summary += "Front: \(frontScore) | Back: \(backScore)\n"
        }
        
        summary += "Holes: \(played.count), Duration: \(durationMin) min\n"
        if avgHr > 0 {
            summary += "Avg HR: \(avgHr) bpm, Max HR: \(maxHr) bpm\n"
        }
        
        // Scorecard table
        summary += "\n## Hole-by-Hole Scorecard\n"
        summary += "Hole | Par | Score | +/- | Score Type | Putts\n"
        summary += "-----|-----|-------|-----|------------|------\n"
        
        for hole in played.sorted(by: { $0.number < $1.number }) {
            let diff = hole.strokes - hole.par
            summary += "H\(String(format: "%02d", hole.number)) | \(hole.par) | \(hole.strokes) | \(diff >= 0 ? "+" : "")\(diff) | \(scoreType(diff)) | \(hole.putts)\n"
        }
        
        let instruction = language == .korean ? koreanInstruction : englishInstruction
        
        return """
        \(instruction)
        
        \(summary)
        """
    }
    
    private static func scoreType(_ diff: Int) -> String {
        switch diff {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double Bogey"
        case 3: return "Triple Bogey"
        default: return "+4 Over Par"
        }
    }
    
    private static let englishInstruction = """
    You are a golf coach. Analyze the round and provide 150-200 word feedback.

    1. Overall performance vs handicap (Consider Course Difficulty/Slope)
    2. Key strengths and areas to improve (cite specific holes/metrics)
    3. Heart rate patterns and correlation to score
    4. One actionable practice focus

    Be direct. Cite numbers. No generic advice.
    """
    
    private static let koreanInstruction = """
    당신은 골프 코치입니다. 라운드를 분석해서 400~600자 내외의 피드백을 제공해주세요.

    1. 전체 성과 vs 핸디캡 (코스 난이도/슬로프 고려 필수)
    2. 잘한 점과 개선 필요 부분 (구체적 홀/수치 인용)
    3. 심박수 패턴과 스코어 연관성
    4. 한 가지 실천 포커스

    구체적으로 수치를 인용해주세요. 일반적인 조언은 피하세요.
    """
}
