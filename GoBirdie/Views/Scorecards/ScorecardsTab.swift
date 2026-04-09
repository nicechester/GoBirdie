//
//  ScorecardsTab.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct ScorecardsTab: View {
    @State private var rounds: [Round] = []
    @State private var selectedRound: Round?

    var body: some View {
        NavigationStack {
            Group {
                if rounds.isEmpty {
                    EmptyScorecardsView()
                } else {
                    List(rounds) { round in
                        Button { selectedRound = round } label: {
                            RoundRow(round: round)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteRound(round) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scorecards")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedRound) { round in
                ScorecardDetailView(round: round)
            }
        }
        .onAppear { loadRounds() }
    }

    private func loadRounds() {
        let store = RoundStore()
        rounds = (try? store.loadAll()) ?? []
    }

    private func deleteRound(_ round: Round) {
        let store = RoundStore()
        try? store.delete(id: round.id)
        rounds.removeAll { $0.id == round.id }
    }
}

// MARK: - Round Row

private struct RoundRow: View {
    let round: Round

    private var dateString: String {
        round.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var parTotal: Int {
        round.holes.reduce(0) { $0 + $1.par }
    }

    private var scoreVsPar: String {
        let diff = round.totalStrokes - parTotal
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(round.courseName)
                    .font(.subheadline).fontWeight(.semibold)
                Text(dateString)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(round.totalStrokes)")
                    .font(.title3).fontWeight(.bold)
                Text(scoreVsPar)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(scoreColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var scoreColor: Color {
        let diff = round.totalStrokes - parTotal
        if diff < 0 { return .green }
        if diff == 0 { return .primary }
        return .red
    }
}

// MARK: - Detail View

private struct ScorecardDetailView: View {
    let round: Round
    @Environment(\.dismiss) var dismiss

    private var parTotal: Int { round.holes.reduce(0) { $0 + $1.par } }
    private var frontNine: [HoleScore] { Array(round.holes.prefix(9)) }
    private var backNine: [HoleScore] { Array(round.holes.dropFirst(9).prefix(9)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryCard(round: round, parTotal: parTotal)
                        .padding(.horizontal, 16)

                    if !frontNine.isEmpty {
                        NineSection(title: "Front 9", holes: frontNine)
                    }
                    if !backNine.isEmpty {
                        NineSection(title: "Back 9", holes: backNine)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle(round.courseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SummaryCard: View {
    let round: Round
    let parTotal: Int

    private var diff: Int { round.totalStrokes - parTotal }
    private var scoreVsPar: String {
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    var body: some View {
        HStack(spacing: 24) {
            StatColumn(label: "Score", value: "\(round.totalStrokes)")
            StatColumn(label: "vs Par", value: scoreVsPar)
            StatColumn(label: "Putts", value: "\(round.totalPutts)")
            StatColumn(label: "Par", value: "\(parTotal)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2).fontWeight(.bold).monospacedDigit()
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Nine Section

private struct NineSection: View {
    let title: String
    let holes: [HoleScore]

    private var totalStrokes: Int { holes.reduce(0) { $0 + $1.strokes } }
    private var totalPar: Int { holes.reduce(0) { $0 + $1.par } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Text("\(totalStrokes) (\(totalPar))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ForEach(holes, id: \.id) { hole in
                HoleRow(hole: hole)
                if hole.number != holes.last?.number {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}

private struct HoleRow: View {
    let hole: HoleScore

    private var diff: Int { hole.strokes - hole.par }
    private var scoreColor: Color {
        guard hole.strokes > 0 else { return .secondary }
        if diff <= -2 { return .yellow }
        if diff == -1 { return .green }
        if diff == 0 { return .primary }
        if diff == 1 { return .orange }
        return .red
    }
    private var scoreName: String {
        guard hole.strokes > 0 else { return "" }
        switch diff {
        case ...(-2): return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Dbl Bogey"
        default: return "+\(diff)"
        }
    }

    var body: some View {
        HStack {
            Text("\(hole.number)")
                .font(.caption).fontWeight(.semibold)
                .frame(width: 24, alignment: .center)
                .foregroundStyle(.secondary)

            Text("P\(hole.par)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 28)

            if hole.strokes > 0 {
                Text("\(hole.strokes)")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(scoreColor)
                    .frame(width: 28)

                Text(scoreName)
                    .font(.caption).foregroundStyle(scoreColor)

                Spacer()

                if hole.putts > 0 {
                    Text("\(hole.putts)P")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 28)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Empty State

private struct EmptyScorecardsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Scorecards")
                .font(.title3).fontWeight(.bold)
            Text("Completed rounds will appear here")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
