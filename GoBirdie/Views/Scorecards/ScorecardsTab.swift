//
//  ScorecardsTab.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct ScorecardsTab: View {
    @EnvironmentObject var appState: AppState
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
                        .swipeActions(edge: .leading) {
                            Button { resumeRound(round) } label: {
                                Label("Resume", systemImage: "play.fill")
                            }
                            .tint(.green)
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

    private func resumeRound(_ round: Round) {
        guard appState.activeRound == nil else { return }
        let store = RoundStore()
        // Find the last hole that was played
        let lastPlayedIndex = round.holes.lastIndex(where: { $0.strokes > 0 }) ?? 0
        // Clear endedAt so it becomes in-progress again
        var resumedRound = round
        resumedRound.endedAt = nil
        let snapshot = InProgressSnapshot(
            round: resumedRound,
            courseId: round.courseId,
            currentHoleIndex: lastPlayedIndex
        )
        // Remove from completed rounds
        try? store.delete(id: round.id)
        rounds.removeAll { $0.id == round.id }
        // Resume
        appState.resumeRound(snapshot: snapshot)
    }
}

// MARK: - Round Row

private struct RoundRow: View {
    let round: Round

    private var dateString: String {
        round.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var parTotal: Int {
        round.holes.filter { $0.strokes > 0 }.reduce(0) { $0 + $1.par }
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
    @State private var currentRound: Round

    init(round: Round) {
        self.round = round
        self._currentRound = State(initialValue: round)
    }

    private var playedHoles: [HoleScore] { currentRound.holes.filter { $0.strokes > 0 } }
    private var parTotal: Int { playedHoles.reduce(0) { $0 + $1.par } }
    private var frontNine: [HoleScore] {
        let f = Array(currentRound.holes.prefix(9))
        return f.contains(where: { $0.strokes > 0 }) ? f : []
    }
    private var backNine: [HoleScore] {
        let b = Array(currentRound.holes.dropFirst(9).prefix(9))
        return b.contains(where: { $0.strokes > 0 }) ? b : []
    }
    private var courseHoles: [Hole] {
        (try? CourseStore().load(id: currentRound.courseId))?.holes ?? []
    }

    private var dateString: String {
        currentRound.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var weatherString: String? {
        guard let minF = currentRound.temperatureMinF,
              let maxF = currentRound.temperatureMaxF,
              let condition = currentRound.weatherCondition else {
            // Fallback to shot temperature if weather data not available
            let allShots = currentRound.holes.flatMap(\.shots)
            guard let c = allShots.compactMap(\.temperatureCelsius).first else { return nil }
            let f = Int((c * 9 / 5 + 32).rounded())
            return "\(f)°F"
        }
        let minFInt = Int(minF.rounded())
        let maxFInt = Int(maxF.rounded())
        return "\(minFInt)/\(maxFInt)°F \(condition)"
    }

    // Stats
    private var longestDrive: (yards: Int, hole: Int)? {
        var best: (yards: Int, hole: Int)? = nil
        for hole in playedHoles {
            let sorted = hole.shots.sorted { $0.sequence < $1.sequence }
            guard let first = sorted.first, first.club == .driver else { continue }
            let target: GpsPoint
            if sorted.count > 1 {
                target = sorted[1].location
            } else if let gc = courseHoles.first(where: { $0.number == hole.number })?.greenCenter {
                target = gc
            } else { continue }
            let yards = Int((first.location.distanceMeters(to: target) * 1.09361).rounded())
            if yards > (best?.yards ?? 0) { best = (yards, hole.number) }
        }
        return best
    }
    private var girCount: Int { playedHoles.filter(\.gir).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Date + weather line
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary)
                        Text(dateString).font(.caption).foregroundStyle(.secondary)
                        if let weather = weatherString {
                            Text("·").foregroundStyle(.secondary)
                            Text(weather).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // Scorecard table
                    if !frontNine.isEmpty {
                        NineSection(title: "Front 9", holes: frontNine, onHoleTap: showHoleMap)
                    }
                    if !backNine.isEmpty {
                        if !frontNine.isEmpty { Divider().padding(.vertical, 4) }
                        NineSection(title: "Back 9", holes: backNine, onHoleTap: showHoleMap)
                    }

                    // Totals row
                    Divider()
                    TotalsRow(round: currentRound, playedHoles: playedHoles, parTotal: parTotal)
                        .padding(.vertical, 4)

                    // Stats
                    Divider().padding(.top, 4)
                    StatsSection(
                        holesPlayed: playedHoles.count,
                        girCount: girCount,
                        girTotal: playedHoles.count,
                        longestDrive: longestDrive
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(currentRound.courseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shotMapHole) { hole in
                ShotMapSheet(allHoles: currentRound.holes, courseHoles: courseHoles, initialHole: hole) { updatedHoles in
                    currentRound.holes = updatedHoles
                    currentRound.totalStrokes = updatedHoles.reduce(0) { $0 + $1.strokes }
                    currentRound.totalPutts = updatedHoles.reduce(0) { $0 + $1.putts }
                }
            }
        }
    }

    private func showHoleMap(_ hole: HoleScore) {
        guard hole.strokes > 0 else { return }
        shotMapHole = hole
    }

    private func reloadRound() {
        let store = RoundStore()
        if let reloadedRound = (try? store.loadAll())?.first(where: { $0.id == round.id }) {
            currentRound = reloadedRound
        }
    }
}

private struct ShotMapSheet: View {
    let allHoles: [HoleScore]
    let courseHoles: [Hole]
    let initialHole: HoleScore
    let onSave: ([HoleScore]) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int = 0
    @State private var editMode = false
    @State private var editableHoles: [HoleScore]
    @State private var selectedShotId: UUID?
    @State private var showDeleteConfirm = false
    @State private var dirty = false
    @State private var showClubPicker = false
    @State private var clubPickerShotId: UUID? = nil
    @State private var clubPickerInitialClub: ClubType = .unknown

    init(allHoles: [HoleScore], courseHoles: [Hole], initialHole: HoleScore, onSave: @escaping ([HoleScore]) -> Void) {
        self.allHoles = allHoles
        self.courseHoles = courseHoles
        self.initialHole = initialHole
        self.onSave = onSave
        self._editableHoles = State(initialValue: allHoles)
    }

    private var holesWithShots: [HoleScore] {
        editableHoles.filter { $0.strokes > 0 || !$0.shots.isEmpty }
    }
    private var hole: HoleScore { holesWithShots[currentIndex] }

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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if editMode {
                    EditableShotMapView(
                        hole: hole,
                        courseHoles: courseHoles,
                        selectedShotId: $selectedShotId,
                        onMoveShotTo: { shotId, newLocation in
                            moveShotTo(shotId: shotId, location: newLocation)
                        },
                        onAddShot: { location in
                            addShot(at: location)
                        },
                        onChangeClub: { shotId, currentClub in
                            clubPickerShotId = shotId
                            clubPickerInitialClub = currentClub
                            showClubPicker = true
                        }
                    )
                    .id("\(hole.id)-\(hole.shots.map { "\($0.id)-\($0.club.rawValue)" }.joined())")
                    .ignoresSafeArea()
                } else {
                    ShotMapView(holes: [hole], courseHoles: courseHoles)
                        .id(hole.id)
                        .ignoresSafeArea()
                }

                // Bottom bar
                VStack(spacing: 0) {
                    if editMode && selectedShotId != nil {
                        HStack(spacing: 16) {
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Shot", systemImage: "trash")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                            Spacer()
                            Text("Drag pin to move")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                    }

                    if editMode {
                        HStack {
                            Text("Tap map to add shot")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("Tap pin to select")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                    }

                    HStack(spacing: 16) {
                        Text("Par \(hole.par)").font(.caption).foregroundStyle(.secondary)
                        Text("\(hole.strokes)").font(.title3).fontWeight(.bold).foregroundStyle(scoreColor)
                        Text(scoreName).font(.caption).fontWeight(.semibold).foregroundStyle(scoreColor)
                        Spacer()
                        if editMode {
                            HStack(spacing: 8) {
                                Button { adjustPutts(-1) } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3).foregroundStyle(.secondary)
                                }
                                .disabled(hole.putts <= 0)
                                Text("\(hole.putts) Putts").font(.caption).foregroundStyle(.secondary)
                                    .frame(minWidth: 50)
                                Button { adjustPutts(1) } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3).foregroundStyle(.green)
                                }
                            }
                        } else {
                            Text("\(hole.putts) Putts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if editMode {
                            selectedShotId = nil
                            if dirty { saveEdits() }
                        }
                        editMode.toggle()
                    } label: {
                        Text(editMode ? "Done" : "Edit")
                            .fontWeight(editMode ? .bold : .regular)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 16) {
                        Button { currentIndex -= 1; selectedShotId = nil } label: {
                            Image(systemName: "chevron.left")
                        }.disabled(currentIndex <= 0)
                        Text("Hole \(hole.number)").fontWeight(.semibold)
                        Button { currentIndex += 1; selectedShotId = nil } label: {
                            Image(systemName: "chevron.right")
                        }.disabled(currentIndex >= holesWithShots.count - 1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        if dirty { saveEdits() }
                        dismiss()
                    }
                }
            }
            .alert("Delete this shot?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteSelectedShot() }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showClubPicker) {
                MarkShotSheet(selectedClub: $clubPickerInitialClub) { club in
                    if let sid = clubPickerShotId {
                        changeClub(shotId: sid, club: club)
                    }
                    clubPickerShotId = nil
                }
            }
        }
        .onAppear {
            currentIndex = holesWithShots.firstIndex { $0.id == initialHole.id } ?? 0
            if initialHole.shots.isEmpty { editMode = true }
        }
    }

    private func changeClub(shotId: UUID, club: ClubType) {
        guard let hi = holeIndex(),
              let si = editableHoles[hi].shots.firstIndex(where: { $0.id == shotId }) else { return }
        editableHoles[hi].shots[si].club = club
        dirty = true
    }

    private func holeIndex() -> Int? {
        editableHoles.firstIndex(where: { $0.id == hole.id })
    }

    private func moveShotTo(shotId: UUID, location: GpsPoint) {
        guard let hi = holeIndex(),
              let si = editableHoles[hi].shots.firstIndex(where: { $0.id == shotId }) else { return }
        editableHoles[hi].shots[si].location = location
        dirty = true
    }

    private func addShot(at location: GpsPoint) {
        guard let hi = holeIndex() else { return }
        let seq = (editableHoles[hi].shots.map(\.sequence).max() ?? 0) + 1
        let shot = Shot(sequence: seq, location: location, timestamp: Date(), club: .unknown)
        editableHoles[hi].shots.append(shot)
        recalcStrokes(hi)
        selectedShotId = shot.id
        clubPickerShotId = shot.id
        clubPickerInitialClub = .unknown
        showClubPicker = true
        dirty = true
    }

    private func deleteSelectedShot() {
        guard let shotId = selectedShotId, let hi = holeIndex() else { return }
        editableHoles[hi].shots.removeAll { $0.id == shotId }
        for i in editableHoles[hi].shots.indices {
            editableHoles[hi].shots[i].sequence = i + 1
        }
        recalcStrokes(hi)
        selectedShotId = nil
        dirty = true
    }

    private func adjustPutts(_ delta: Int) {
        guard let hi = holeIndex() else { return }
        editableHoles[hi].putts = max(0, editableHoles[hi].putts + delta)
        recalcStrokes(hi)
        dirty = true
    }

    private func recalcStrokes(_ hi: Int) {
        editableHoles[hi].strokes = editableHoles[hi].shots.count + editableHoles[hi].putts
    }

    private func saveEdits() {
        // Rebuild the round with edited holes and save
        guard let roundId = findRoundId() else { return }
        let store = RoundStore()
        guard var round = (try? store.loadAll())?.first(where: { $0.id == roundId }) else { return }
        round.holes = editableHoles
        round.totalStrokes = editableHoles.reduce(0) { $0 + $1.strokes }
        round.totalPutts = editableHoles.reduce(0) { $0 + $1.putts }
        try? store.save(round)
        onSave(editableHoles)
    }

    private func findRoundId() -> String? {
        let store = RoundStore()
        return (try? store.loadAll())?.first(where: { r in
            r.holes.count == allHoles.count &&
            r.holes.first?.id == allHoles.first?.id
        })?.id
    }
}

private struct TotalsRow: View {
    let round: Round
    let playedHoles: [HoleScore]
    let parTotal: Int

    private var diff: Int { round.totalStrokes - parTotal }
    private var diffStr: String {
        diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)"
    }
    private var diffColor: Color {
        diff < 0 ? .green : diff == 0 ? .primary : .red
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("Total")
                .font(.caption).fontWeight(.bold)
                .frame(width: 52, alignment: .leading)

            Text("\(round.totalStrokes)")
                .font(.subheadline).fontWeight(.bold)
                .foregroundStyle(diffColor)
                .frame(width: 28)

            Spacer()

            Text("\(round.totalPutts)")
                .font(.caption).fontWeight(.semibold)
                .frame(width: 32, alignment: .center)

            Text("\(playedHoles.reduce(0) { $0 + $1.penalties })")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.orange)
                .frame(width: 28, alignment: .center)

            Text(diffStr)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(diffColor)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }
}

private struct StatsSection: View {
    let holesPlayed: Int
    let girCount: Int
    let girTotal: Int
    let longestDrive: (yards: Int, hole: Int)?

    var body: some View {
        VStack(spacing: 6) {
            statRow("Holes Played", value: "\(holesPlayed)")
            statRow("GIR", value: "\(girCount)/\(girTotal)")
            if let ld = longestDrive {
                statRow("Longest Drive", value: "\(ld.yards) yds (H\(ld.hole))")
            }
        }
        .padding(.horizontal, 16)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold)
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
    private var totalPutts: Int { holes.reduce(0) { $0 + $1.putts } }
    private var totalPenalties: Int { holes.reduce(0) { $0 + $1.penalties } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text(title)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Text("Putts").font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .center)
                Text("Pen").font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
                Text("\(totalStrokes)")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ForEach(holes, id: \.id) { hole in
                HoleRow(hole: hole, hasShotMap: hole.strokes > 0)
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

    var body: some View {
        HStack(spacing: 0) {
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

                Spacer()

                if hasShotMap {
                    Image(systemName: "map")
                        .font(.caption).foregroundStyle(.green)
                        .padding(.trailing, 6)
                }

                Text(hole.putts > 0 ? "\(hole.putts)" : "—")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .center)

                Text(hole.penalties > 0 ? "\(hole.penalties)" : "—")
                    .font(.caption).foregroundStyle(hole.penalties > 0 ? .orange : .secondary)
                    .frame(width: 28, alignment: .center)

                Text(diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(scoreColor)
                    .frame(width: 28, alignment: .trailing)
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
