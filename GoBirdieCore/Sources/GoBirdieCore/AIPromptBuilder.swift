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

    /// Builds the "Ask AI" prompt for a round.
    /// - Parameter course: The course the round was played on. Used for each hole's tee-to-green distance.
    ///   Without it, that column shows "-".
    public static func build(
        round: Round,
        handicap: String = "Bogey Golfer",
        courseRating: Double? = nil,
        slope: Int? = nil,
        course: Course? = nil,
        handedness: String = "right",
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

        // Heart rate stats (only when the round has data, e.g. an Apple Watch was worn)
        let hrSamples = round.heartRateTimeline
        let hasHeartRate = !hrSamples.isEmpty
        let avgHr = hrSamples.isEmpty ? 0 : hrSamples.reduce(0) { $0 + $1.bpm } / hrSamples.count
        let maxHr = hrSamples.map(\.bpm).max() ?? 0

        let weather = weatherLine(round, language)

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
            summary += "타격 방향: \(handedness == "left" ? "왼손잡이" : "오른손잡이")\n"
            summary += "스코어: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) 파 \(totalPar) 대비\n"
            if played.count >= 16 {
                summary += "전반: \(frontScore) | 후반: \(backScore)\n"
            }
            summary += "홀: \(played.count), 소요시간: \(durationMin)분\n"
            summary += weather
            if hasHeartRate {
                summary += "평균 심박수: \(avgHr) bpm, 최대 심박수: \(maxHr) bpm\n"
            }
            summary += "\n## 홀별 스코어카드\n"
            summary += "홀 | 파 | 스코어 | +/- | 스코어 타입 | 퍼팅 | 티→그린\n"
        case .spanish:
            summary = "## Resumen de la Ronda\n"
            summary += "Fecha: \(dateStr)\n"
            summary += "Campo: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (Rating \(String(format: "%.1f", rating)), Slope \(sl))"
            }
            summary += "\nTu Hándicap: \(handicap)\n"
            summary += "Mano dominante: \(handedness == "left" ? "Zurdo" : "Diestro")\n"
            summary += "Puntuación: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) sobre par \(totalPar)\n"
            if played.count >= 16 {
                summary += "Ida: \(frontScore) | Vuelta: \(backScore)\n"
            }
            summary += "Hoyos: \(played.count), Duración: \(durationMin) min\n"
            summary += weather
            if hasHeartRate {
                summary += "FC Promedio: \(avgHr) bpm, FC Máx: \(maxHr) bpm\n"
            }
            summary += "\n## Tarjeta Hoyo por Hoyo\n"
            summary += "Hoyo | Par | Golpes | +/- | Tipo | Putts | Tee→Green\n"
        case .english:
            summary = "## Round Summary\n"
            summary += "Date: \(dateStr)\n"
            summary += "Course: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (Rating \(String(format: "%.1f", rating)), Slope \(sl))"
            }
            summary += "\nYour Handicap: \(handicap)\n"
            summary += "Handedness: \(handedness == "left" ? "Left-handed" : "Right-handed")\n"
            summary += "Score: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) over par \(totalPar)\n"
            if played.count >= 16 {
                summary += "Front: \(frontScore) | Back: \(backScore)\n"
            }
            summary += "Holes: \(played.count), Duration: \(durationMin) min\n"
            summary += weather
            if hasHeartRate {
                summary += "Avg HR: \(avgHr) bpm, Max HR: \(maxHr) bpm\n"
            }
            summary += "\n## Hole-by-Hole Scorecard\n"
            summary += "Hole | Par | Score | +/- | Score Type | Putts | Tee→Green\n"
        case .japanese:
            summary = "## ラウンドサマリー\n"
            summary += "日付: \(dateStr)\n"
            summary += "コース: \(round.courseName)"
            if let rating = courseRating, let sl = slope {
                summary += " (レーティング \(String(format: "%.1f", rating)), スロープ \(sl))"
            }
            summary += "\nハンディキャップ: \(handicap)\n"
            summary += "利き手: \(handedness == "left" ? "左利き" : "右利き")\n"
            summary += "スコア: \(round.totalStrokes) (\(overPar >= 0 ? "+" : "")\(overPar)) パー\(totalPar)比\n"
            if played.count >= 16 {
                summary += "前半: \(frontScore) | 後半: \(backScore)\n"
            }
            summary += "ホール数: \(played.count)、所要時間: \(durationMin)分\n"
            summary += weather
            if hasHeartRate {
                summary += "平均心拍数: \(avgHr) bpm、最大心拍数: \(maxHr) bpm\n"
            }
            summary += "\n## ホール別スコアカード\n"
            summary += "ホール | パー | スコア | +/- | スコアタイプ | パット | ティー→グリーン\n"
        }
        summary += "-----|-----|-------|-----|------------|------|-------\n"

        let sortedHoles = played.sorted(by: { $0.number < $1.number })
        for hole in sortedHoles {
            let diff = hole.strokes - hole.par
            let teeToGreen = teeToGreenYards(hole, course: course)
            let teeToGreenText = teeToGreen.map { "\($0)y" } ?? "-"
            summary += "H\(String(format: "%02d", hole.number)) | \(hole.par) | \(hole.strokes) | \(diff >= 0 ? "+" : "")\(diff) | \(scoreType(diff, language: language)) | \(hole.putts) | \(teeToGreenText)\n"
        }

        // Shots: distance to the pin where it was recorded, and how far the shot moved to the next shot.
        var shotSection = ""
        for hole in sortedHoles {
            if let line = shotLine(hole, green: greenPoint(hole, course: course), language: language) {
                shotSection += "H\(String(format: "%02d", hole.number)): \(line)\n"
            }
        }
        if !shotSection.isEmpty {
            summary += "\n\(shotsHeader(language))\n"
            summary += shotSection
        }

        let instruction = coachInstruction(for: language, includeHeartRate: hasHeartRate)

        return """
        \(instruction)

        \(summary)
        """
    }

    // MARK: - Distances and labels

    private static func yards(_ meters: Double) -> Int {
        Int((meters * 1.09361).rounded())
    }

    /// Tee to green in yards for one hole: the course's tee and green, falling back to the scorecard's green.
    private static func teeToGreenYards(_ hole: HoleScore, course: Course?) -> Int? {
        let courseHole = course?.holes.first { $0.number == hole.number }
        guard let tee = courseHole?.tee, let green = courseHole?.greenCenter ?? hole.greenCenter else { return nil }
        return yards(tee.distanceMeters(to: green))
    }

    /// The green for a hole: the course's green, falling back to the scorecard's green.
    private static func greenPoint(_ hole: HoleScore, course: Course?) -> GpsPoint? {
        course?.holes.first { $0.number == hole.number }?.greenCenter ?? hole.greenCenter
    }

    /// Each shot on a hole: club, its distance to the next shot (or to the green for the last shot), and its
    /// direction relative to the green. The last shot has no direction: it ends at the green.
    private static func shotLine(_ hole: HoleScore, green: GpsPoint?, language: Language) -> String? {
        let shots = hole.shots.sorted { $0.sequence < $1.sequence }
        var items: [String] = []
        for (i, shot) in shots.enumerated() {
            let isLast = i + 1 == shots.count
            guard let target = isLast ? green : shots[i + 1].location else { continue }
            let distance = yards(shot.location.distanceMeters(to: target))
            let club = shot.club != .unknown ? "\(shot.club.displayName) " : ""
            let suffix = isLast ? " \(greenLabel(language))" : ""
            var direction = ""
            if !isLast, let green {
                direction = " " + directionName(shot.location, to: target, green: green, language: language)
            }
            // Where the shot was hit: latitude, longitude, and altitude when recorded.
            var place = String(format: "%.6f, %.6f", shot.location.lat, shot.location.lon)
            if let altitude = shot.altitudeMeters {
                // Altitude is stored in meters; the prompt shows feet.
                place += ", \(Int((altitude * 3.28084).rounded())) ft"
            }
            items.append("#\(shot.sequence) \(club)\(distance)y\(suffix)\(direction) (\(place))")
        }
        return items.isEmpty ? nil : items.joined(separator: " | ")
    }

    /// Direction of a shot relative to the green, as the desktop app computes it: the shot's bearing minus the
    /// bearing from the shot to the green, wrapped to ±180°. Within ±10° is straight; beyond ±30° is "far".
    private static func directionName(_ from: GpsPoint, to: GpsPoint, green: GpsPoint, language: Language) -> String {
        var deviation = bearing(from: from, to: to) - bearing(from: from, to: green)
        if deviation > 180 { deviation -= 360 }
        if deviation < -180 { deviation += 360 }

        let magnitude = abs(deviation)
        let right = deviation > 0
        let far = magnitude > 30
        switch language {
        case .english:
            if magnitude < 10 { return "straight" }
            return (far ? "far " : "") + (right ? "right" : "left")
        case .korean:
            if magnitude < 10 { return "직진" }
            return (far ? "많이 " : "") + (right ? "우측" : "좌측")
        case .spanish:
            if magnitude < 10 { return "recto" }
            return (far ? "mucho a la " : "a la ") + (right ? "derecha" : "izquierda")
        case .japanese:
            if magnitude < 10 { return "直進" }
            return (far ? "大きく" : "") + (right ? "右" : "左")
        }
    }

    /// Initial bearing in degrees [0, 360) from one point to another (great-circle, as the desktop app computes it).
    private static func bearing(from: GpsPoint, to: GpsPoint) -> Double {
        let lat1 = from.lat * .pi / 180
        let lat2 = to.lat * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func shotsHeader(_ language: Language) -> String {
        switch language {
        case .korean: return "## 샷별 거리"
        case .spanish: return "## Distancias por golpe"
        case .japanese: return "## ショット別の距離"
        case .english: return "## Shot Distances"
        }
    }

    private static func greenLabel(_ language: Language) -> String {
        switch language {
        case .korean: return "그린까지"
        case .spanish: return "al green"
        case .japanese: return "グリーンまで"
        case .english: return "to green"
        }
    }

    /// Weather line for the summary, or an empty string when the round has no weather data.
    private static func weatherLine(_ round: Round, _ language: Language) -> String {
        var parts: [String] = []
        if let condition = round.weatherCondition { parts.append(condition) }
        if let minF = round.temperatureMinF, let maxF = round.temperatureMaxF {
            parts.append("\(Int(minF.rounded()))–\(Int(maxF.rounded()))°F")
        } else if let temp = round.temperatureMinF ?? round.temperatureMaxF {
            parts.append("\(Int(temp.rounded()))°F")
        }
        guard !parts.isEmpty else { return "" }
        let value = parts.joined(separator: ", ")
        switch language {
        case .korean: return "날씨: \(value)\n"
        case .spanish: return "Clima: \(value)\n"
        case .japanese: return "天気: \(value)\n"
        case .english: return "Weather: \(value)\n"
        }
    }

    // MARK: - Instructions

    /// The coaching instructions. Without heart-rate data, the heart-rate item is removed and the rest renumbered,
    /// so the prompt never asks about heart rate when the round has none.
    private static func coachInstruction(for language: Language, includeHeartRate: Bool) -> String {
        let text: String
        switch language {
        case .korean: text = koreanInstruction
        case .spanish: text = spanishInstruction
        case .japanese: text = japaneseInstruction
        case .english: text = englishInstruction
        }
        guard !includeHeartRate else { return text }

        let heartRateMarkers = ["Heart rate", "심박수", "frecuencia cardíaca", "心拍数"]
        var number = 0
        return text.components(separatedBy: "\n")
            .filter { line in !heartRateMarkers.contains { line.contains($0) } }
            .map { line -> String in
                guard let first = line.first, first.isNumber, line.dropFirst().hasPrefix(".") else { return line }
                number += 1
                return "\(number)." + String(line.dropFirst(2))
            }
            .joined(separator: "\n")
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
    You are a golf coach. Analyze the round and provide 250-350 word feedback.

    1. Overall performance vs handicap (Consider Course Difficulty/Slope and weather)
    2. Key strengths and areas to improve (cite specific holes/metrics)
    3. Performance by shot type: tee, approach, chip, and putt (use the shot distances, directions, and the distance to the green)
    4. Club summary: average distance and direction tendency for each club used
    5. Terrain and lie: using each shot's latitude/longitude and altitude, infer the slope and lie (uphill, downhill, uneven) between consecutive shots, and explain how they affected ball flight and dispersion, accounting for handedness. Cite the best shots and key misses.
    6. Heart rate patterns and correlation to score
    7. One actionable practice focus

    Be direct. Cite numbers. No generic advice.
    """

    private static let koreanInstruction = """
    당신은 골프 코치입니다. 라운드를 분석해서 600~900자 내외의 피드백을 제공해주세요.

    1. 전체 성과 vs 핸디캡 (코스 난이도/슬로프와 날씨 고려 필수)
    2. 잘한 점과 개선 필요 부분 (구체적 홀/수치 인용)
    3. 샷 유형별 성과: 티샷, 어프로치, 칩, 퍼팅 (샷 거리, 방향, 그린까지 거리 활용)
    4. 클럽 요약: 사용한 클럽별 평균 거리와 방향 경향
    5. 지형과 라이: 각 샷의 위도/경도와 고도로 연속된 샷 사이의 경사와 라이(오르막, 내리막, 불안정한 라이)를 추정하고, 구질과 방향성에 미친 영향을 설명해주세요. 타격 방향을 고려하고, 가장 좋았던 샷과 주요 미스를 짚어주세요.
    6. 심박수 패턴과 스코어 연관성
    7. 한 가지 실천 포커스

    구체적으로 수치를 인용해주세요. 일반적인 조언은 피하세요.
    """

    private static let spanishInstruction = """
    Eres un entrenador de golf. Analiza la ronda y proporciona feedback de 250-350 palabras.

    1. Rendimiento general vs hándicap (Considera Dificultad del Campo/Slope y el clima)
    2. Fortalezas clave y áreas a mejorar (cita hoyos/métricas específicas)
    3. Rendimiento por tipo de golpe: salida, approach, chip y putt (usa las distancias, direcciones y la distancia al green)
    4. Resumen por palo: distancia media y tendencia de dirección de cada palo usado
    5. Terreno y lie: usando la latitud/longitud y la altitud de cada golpe, infiere la pendiente y el lie (cuesta arriba, cuesta abajo, irregular) entre golpes consecutivos y explica cómo afectaron al vuelo de la bola y a la dispersión, teniendo en cuenta la mano dominante. Cita los mejores golpes y los fallos clave.
    6. Patrones de frecuencia cardíaca y correlación con el score
    7. Un enfoque de práctica accionable

    Sé directo. Cita números. Sin consejos genéricos.
    """

    private static let japaneseInstruction = """
    あなたはゴルフコーチです。ラウンドを分析し、600〜900文字程度のフィードバックを提供してください。

    1. 全体的なパフォーマンス vs ハンディキャップ(コースの難易度/スロープと天候を必ず考慮)
    2. 良かった点と改善が必要な点(具体的なホール/数値を引用)
    3. ショットタイプ別の成績: ティーショット、アプローチ、チップ、パット(ショット距離・方向・グリーンまでの距離を活用)
    4. クラブ別の概要: 使用した各クラブの平均距離と方向の傾向
    5. 地形とライ: 各ショットの緯度経度と高度から、連続するショット間の傾斜とライ(上り、下り、不安定なライ)を推定し、弾道と方向性への影響を説明してください。利き手を考慮し、最も良かったショットと主なミスを挙げてください。
    6. 心拍数のパターンとスコアとの相関
    7. 実践すべき練習ポイントを1つ

    具体的に数値を引用してください。一般的なアドバイスは避けてください。
    """
}
