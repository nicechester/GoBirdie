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
    @State private var shotMapHole: HoleScore?

    private var parTotal: Int { round.holes.reduce(0) { $0 + $1.par } }
    private var frontNine: [HoleScore] { Array(round.holes.prefix(9)) }
    private var backNine: [HoleScore] { Array(round.holes.dropFirst(9).prefix(9)) }
    private var courseHoles: [Hole] {
        (try? CourseStore().load(id: round.courseId))?.holes ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryCard(round: round, parTotal: parTotal)
                        .padding(.horizontal, 16)

                    if !frontNine.isEmpty {
                        NineSection(title: "Front 9", holes: frontNine, onHoleTap: showHoleMap)
                    }
                    if !backNine.isEmpty {
                        NineSection(title: "Back 9", holes: backNine, onHoleTap: showHoleMap)
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
            .sheet(item: $shotMapHole) { hole in
                ShotMapSheet(allHoles: round.holes, courseHoles: courseHoles, initialHole: hole)
            }
        }
    }

    private func showHoleMap(_ hole: HoleScore) {
        guard !hole.shots.isEmpty else { return }
        shotMapHole = hole
    }
}

private struct ShotMapSheet: View {
    let allHoles: [HoleScore]
    let courseHoles: [Hole]
    let initialHole: HoleScore
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int = 0

    private var holesWithShots: [HoleScore] {
        allHoles.filter { !$0.shots.isEmpty }
    }
    private var hole: HoleScore { holesWithShots[currentIndex] }

    private var sortedShots: [Shot] {
        hole.shots.sorted { $0.sequence < $1.sequence }
    }

    private var scoreName: String {
        let diff = hole.strokes - hole.par
        switch diff {
        case ...(-2): return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Dbl Bogey"
        default: return "+\(diff)"
        }
    }

    private var scoreColor: Color {
        let diff = hole.strokes - hole.par
        if diff <= -2 { return .yellow }
        if diff == -1 { return .green }
        if diff == 0 { return .primary }
        if diff == 1 { return .orange }
        return .red
    }

    private func shotDistance(_ shot: Shot) -> Int? {
        let sorted = sortedShots
        guard let idx = sorted.firstIndex(where: { $0.id == shot.id }) else { return nil }
        let nextPoint: GpsPoint?
        if idx + 1 < sorted.count {
            nextPoint = sorted[idx + 1].location
        } else {
            nextPoint = courseHoles.first { $0.number == hole.number }?.greenCenter
        }
        guard let to = nextPoint else { return nil }
        let meters = shot.location.distanceMeters(to: to)
        return Int((meters * 1.09361).rounded())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ShotMapView(holes: [hole], courseHoles: courseHoles)
                    .id(hole.id)
                    .ignoresSafeArea()

                // Score bar overlay at bottom
                HStack(spacing: 16) {
                    Text("Par \(hole.par)").font(.caption).foregroundStyle(.secondary)
                    Text("\(hole.strokes)").font(.title3).fontWeight(.bold).foregroundStyle(scoreColor)
                    Text(scoreName).font(.caption).fontWeight(.semibold).foregroundStyle(scoreColor)
                    Spacer()
                    Text("\(hole.putts) Putts").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 16) {
                        Button { currentIndex -= 1 } label: {
                            Image(systemName: "chevron.left")
                        }.disabled(currentIndex <= 0)
                        Text("Hole \(hole.number)").fontWeight(.semibold)
                        Button { currentIndex += 1 } label: {
                            Image(systemName: "chevron.right")
                        }.disabled(currentIndex >= holesWithShots.count - 1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            currentIndex = holesWithShots.firstIndex { $0.id == initialHole.id } ?? 0
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
    let onHoleTap: (HoleScore) -> Void

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
                HoleRow(hole: hole, hasShotMap: !hole.shots.isEmpty)
                    .onTapGesture { onHoleTap(hole) }
                if hole.number != holes.last?.number {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}

private struct HoleRow: View {
    let hole: HoleScore
    var hasShotMap: Bool = false

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

                if hasShotMap {
                    Image(systemName: "map")
                        .font(.caption).foregroundStyle(.green)
                }

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
