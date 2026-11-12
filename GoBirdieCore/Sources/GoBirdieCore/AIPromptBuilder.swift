//
//  AIPromptBuilder.swift
//  GoBirdieCore

import Foundation

public struct AIPromptBuilder {
    
    public enum Language: String {
        case english = "en"
        case korean = "ko"
        case spanish = "es"
        case japanese = "ja"
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
        
        // Build summary based on language
        var summary: String
        switch language {
        case .korean:
            summary = "## 라운드 요약\n"
            summary += "날짜: \(dateStr)\n"
            summary += "코스: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (레이팅 \(String(format: "%.1f", rating)), 슬로프 \(sl))"
            }
            summary += "\n핸디캡: \(handicap)\n"
            summary += "스코어: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) 파 \(totalPar) 대비\n"
            if played.count >= 16 {
                summary += "전반: \(frontScore) | 후반: \(backScore)\n"
            }
            summary += "홀: \(played.count), 소요시간: \(durationMin)분\n"
            if avgHr > 0 {
                summary += "평균 심박수: \(avgHr) bpm, 최대 심박수: \(maxHr) bpm\n"
            }
            summary += "\n## 홀별 스코어카드\n"
            summary += "홀 | 파 | 스코어 | +/- | 스코어 타입 | 퍼팅\n"
        case .spanish:
            summary = "## Resumen de la Ronda\n"
            summary += "Fecha: \(dateStr)\n"
            summary += "Campo: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (Rating \(String(format: "%.1f", rating)), Slope \(sl))"
            }
            summary += "\nTu Hándicap: \(handicap)\n"
            summary += "Puntuación: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) sobre par \(totalPar)\n"
            if played.count >= 16 {
                summary += "Ida: \(frontScore) | Vuelta: \(backScore)\n"
            }
            summary += "Hoyos: \(played.count), Duración: \(durationMin) min\n"
            if avgHr > 0 {
                summary += "FC Promedio: \(avgHr) bpm, FC Máx: \(maxHr) bpm\n"
            }
            summary += "\n## Tarjeta Hoyo por Hoyo\n"
            summary += "Hoyo | Par | Golpes | +/- | Tipo | Putts\n"
        case .english:
            summary = "## Round Summary\n"
            summary += "Date: \(dateStr)\n"
            summary += "Course: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (Rating \(String(format: "%.1f", rating)), Slope \(sl))"
            }
            summary += "\nYour Handicap: \(handicap)\n"
            summary += "Score: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) over par \(totalPar)\n"
            if played.count >= 16 {
                summary += "Front: \(frontScore) | Back: \(backScore)\n"
            }
            summary += "Holes: \(played.count), Duration: \(durationMin) min\n"
            if avgHr > 0 {
                summary += "Avg HR: \(avgHr) bpm, Max HR: \(maxHr) bpm\n"
            }
            summary += "\n## Hole-by-Hole Scorecard\n"
            summary += "Hole | Par | Score | +/- | Score Type | Putts\n"
        case .japanese:
            summary = "## ラウンドサマリー\n"
            summary += "日付: \(dateStr)\n"
            summary += "コース: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (レーティング \(String(format: "%.1f", rating)), スロープ \(sl))"
            }
            summary += "\nハンディキャップ: \(handicap)\n"
            summary += "スコア: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) パー\(totalPar)比\n"
            if played.count >= 16 {
                summary += "前半: \(frontScore) | 後半: \(backScore)\n"
            }
            summary += "ホール数: \(played.count)、所要時間: \(durationMin)分\n"
            if avgHr > 0 {
                summary += "平均心拍数: \(avgHr) bpm、最大心拍数: \(maxHr) bpm\n"
            }
            summary += "\n## ホール別スコアカード\n"
            summary += "ホール | パー | スコア | +/- | スコアタイプ | パット\n"
        }
        summary += "-----|-----|-------|-----|------------|------\n"
        
        for hole in played.sorted(by: { $0.number < $1.number }) {
            let diff = hole.strokes - hole.par
            summary += "H\(String(format: "%02d", hole.number)) | \(hole.par) | \(hole.strokes) | \(diff >= 0 ? "+" : "")\(diff) | \(scoreType(diff, language: language)) | \(hole.putts)\n"
        }
        
        let instruction: String
        switch language {
        case .korean: instruction = koreanInstruction
        case .spanish: instruction = spanishInstruction
        case .japanese: instruction = japaneseInstruction
        case .english: instruction = englishInstruction
        }
        
        return """
        \(instruction)
        
        \(summary)
        """
    }
    
    private static func scoreType(_ diff: Int, language: Language) -> String {
        switch language {
        case .korean:
            switch diff {
            case ...(-3): return "알바트로스"
            case -2: return "이글"
            case -1: return "버디"
            case 0: return "파"
            case 1: return "보기"
            case 2: return "더블보기"
            case 3: return "트리플보기"
            default: return "+4 오버파"
            }
        case .japanese:
            switch diff {
            case ...(-3): return "アルバトロス"
            case -2: return "イーグル"
            case -1: return "バーディー"
            case 0: return "パー"
            case 1: return "ボギー"
            case 2: return "ダブルボギー"
            case 3: return "トリプルボギー"
            default: return "+4 オーバーパー"
            }
        case .spanish, .english:
            // Golf terms stay in English for Spanish
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
    
    private static let spanishInstruction = """
    Eres un entrenador de golf. Analiza la ronda y proporciona feedback de 150-200 palabras.

    1. Rendimiento general vs hándicap (Considera Dificultad del Campo/Slope)
    2. Fortalezas clave y áreas a mejorar (cita hoyos/métricas específicas)
    3. Patrones de frecuencia cardíaca y correlación con el score
    4. Un enfoque de práctica accionable

    Sé directo. Cita números. Sin consejos genéricos.
    """

    private static let japaneseInstruction = """
    あなたはゴルフコーチです。ラウンドを分析し、400〜600文字程度のフィードバックを提供してください。

    1. 全体的なパフォーマンス vs ハンディキャップ(コースの難易度/スロープを必ず考慮)
    2. 良かった点と改善が必要な点(具体的なホール/数値を引用)
    3. 心拍数のパターンとスコアとの相関
    4. 実践すべき練習ポイントを1つ

    具体的に数値を引用してください。一般的なアドバイスは避けてください。
    """
}
