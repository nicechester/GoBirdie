//
//  MiniScorecardView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

/// Vertical scorecard list. Each row: H# | P# | stroke circles | score vs par
/// Matches sketch: rows scroll vertically, circles numbered 1…n, last circle red if over par.
struct MiniScorecardView: View {
    @ObservedObject var session: RoundSession
    let onHoleSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            Text("SCORECARD")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(1.5)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(session.round.holes, id: \.id) { hole in
                        ScorecardRow(
                            hole: hole,
                            isCurrent: hole.number == session.currentHoleNumber,
                            onTap: { onHoleSelect(hole.number) }
                        )
                        .id(hole.number)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct ScorecardRow: View {
    let hole: HoleScore
    let isCurrent: Bool
    let onTap: () -> Void

    private var overPar: Int { hole.strokes - hole.par }

    private var scoreLabel: String {
        guard hole.strokes > 0 else { return "—" }
        if overPar == 0 { return "E" }
        return overPar > 0 ? "+\(overPar)" : "\(overPar)"
    }

    private var scoreLabelColor: Color {
        guard hole.strokes > 0 else { return .secondary }
        if overPar < 0 { return .green }
        if overPar == 0 { return .primary }
        return .red
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // H# label
                Text("H\(hole.number)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isCurrent ? .green : .secondary)
                    .frame(width: 28, alignment: .leading)

                // P# label
                Text("P\(hole.par)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)

                // Stroke circles
                HStack(spacing: 5) {
                    if hole.strokes > 0 {
                        ForEach(1...hole.strokes, id: \.self) { n in
                            StrokeCircle(n: n, total: hole.strokes, par: hole.par)
                        }
                    } else {
                        // Not played — show 3 dim dots
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 18, height: 18)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Score vs par
                Text(scoreLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreLabelColor)
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(isCurrent ? Color.green.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)

        Divider()
            .padding(.leading, 16)
    }
}

private struct StrokeCircle: View {
    let n: Int
    let total: Int
    let par: Int

    // Last circle is red if over par, green if at/under par, otherwise green
    private var bg: Color {
        if n == total {
            return total > par ? .red : .green
        }
        return .green
    }

    var body: some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 18, height: 18)
            .background(bg)
            .foregroundStyle(.white)
            .clipShape(Circle())
    }
}

#Preview {
    let holes: [HoleScore] = [
        HoleScore(number: 1, par: 4, strokes: 5, putts: 2),
        HoleScore(number: 2, par: 3, strokes: 3, putts: 1),
        HoleScore(number: 3, par: 5, strokes: 0, putts: 0),
    ]
    let round = Round(
        id: "t", source: "apple", courseId: "t", courseName: "Test",
        startedAt: Date(), endedAt: nil, holesPlayed: 2,
        holes: holes, totalStrokes: 8, totalPutts: 3
    )
    let session = RoundSession(round: round)
    return MiniScorecardView(session: session, onHoleSelect: { _ in })
        .preferredColorScheme(.dark)
}
