//
//  TournamentsTab.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore
import AVFoundation

// MARK: - QR Payload (matches Android)

private struct QrRoundPayload: Codable {
    let c: String           // course name
    let d: String           // date yyyy-MM-dd
    let h: [[Int]]          // [[strokes, putts], ...]
}

private extension Round {
    func toQrPayload() -> QrRoundPayload {
        let date = startedAt.formatted(.iso8601.year().month().day())
        return QrRoundPayload(
            c: courseName,
            d: date,
            h: holes.map { [$0.strokes, $0.putts] }
        )
    }
}

// MARK: - Tournaments List

struct TournamentsTab: View {
    @State private var tournaments: [Tournament] = []
    @State private var showCreate = false
    @State private var selectedTournament: Tournament?

    var body: some View {
        Group {
            if let t = selectedTournament {
                TournamentDetailView(
                    tournament: t,
                    onDismiss: {
                        selectedTournament = nil
                        load()
                    }
                )
            } else if showCreate {
                CreateTournamentView(
                    onCreated: { tournament in
                        try? TournamentStore().save(tournament)
                        showCreate = false
                        load()
                        selectedTournament = tournament
                    },
                    onDismiss: { showCreate = false }
                )
            } else {
                listView
            }
        }
        .onAppear { load() }
    }

    private var listView: some View {
        NavigationStack {
            Group {
                if tournaments.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "trophy").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No Tournaments").font(.title3).fontWeight(.bold)
                        Text("Tap + to create one").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(tournaments) { tournament in
                            Button { selectedTournament = tournament } label: {
                                TournamentRow(tournament: tournament)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(tournament) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tournaments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private func load() {
        tournaments = (try? TournamentStore().loadAll()) ?? []
    }

    private func delete(_ tournament: Tournament) {
        try? TournamentStore().delete(id: tournament.id)
        tournaments.removeAll { $0.id == tournament.id }
    }
}

private struct TournamentRow: View {
    let tournament: Tournament
    var body: some View {
        HStack {
            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(tournament.title ?? tournament.courseName)
                    .font(.subheadline).fontWeight(.semibold)
                Text("\(tournament.date)  ·  \(tournament.players.count) player\(tournament.players.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Tournament

private struct CreateTournamentView: View {
    let onCreated: (Tournament) -> Void
    let onDismiss: () -> Void

    @State private var selectedCourse: Course?
    @State private var date = Date().formatted(.iso8601.year().month().day())
    @State private var title = ""
    @State private var showCoursePicker = false

    private var courses: [Course] { (try? CourseStore().loadAll()) ?? [] }
    private var latestRound: Round? { (try? RoundStore().loadAll())?.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    Button { showCoursePicker = true } label: {
                        HStack {
                            Text(selectedCourse?.name ?? "Select a course…")
                                .foregroundStyle(selectedCourse != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    TextField("Date (yyyy-MM-dd)", text: $date)
                    TextField("Title (optional)", text: $title)
                }

                if let r = latestRound {
                    Section {
                        Text("Your latest round (\(r.courseName)) will be added automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(selectedCourse == nil || date.isEmpty)
                        .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showCoursePicker) {
                CoursePickerSheet(courses: courses) { selectedCourse = $0 }
            }
        }
    }

    private func create() {
        guard let course = selectedCourse else { return }
        var players: [TournamentPlayer] = []
        if let round = latestRound {
            players.append(TournamentPlayer(name: "Me", holes: round.holes, source: .self))
        }
        let tournament = Tournament(
            title: title.isEmpty ? nil : title,
            courseId: course.id,
            courseName: course.name,
            date: date,
            players: players
        )
        onCreated(tournament)
    }
}

private struct CoursePickerSheet: View {
    let courses: [Course]
    let onSelect: (Course) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if courses.isEmpty {
                    Text("No saved courses. Download a course first.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    List(courses) { course in
                        Button {
                            onSelect(course)
                            dismiss()
                        } label: {
                            Text(course.name).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Select Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tournament Detail (grid)

struct TournamentDetailView: View {
    @State private var tournament: Tournament
    let onDismiss: () -> Void

    @State private var editingPlayer: TournamentPlayer?
    @State private var showAddManual = false
    @State private var showQrScan = false
    @State private var longPressPlayer: TournamentPlayer?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showRemoveConfirm = false

    init(tournament: Tournament, onDismiss: @escaping () -> Void) {
        self._tournament = State(initialValue: tournament)
        self.onDismiss = onDismiss
    }

    private var sorted: [TournamentPlayer] {
        tournament.players.sorted {
            if $0.totalStrokes == 0 { return false }
            if $1.totalStrokes == 0 { return true }
            return $0.scoreVsPar < $1.scoreVsPar
        }
    }

    var body: some View {
        Group {
            if let player = editingPlayer {
                EditPlayerScoreView(
                    player: player,
                    parReference: tournament.players.first(where: { $0.source == .self })?.holes ?? [],
                    onSave: { updated in
                        save(updated)
                        editingPlayer = nil
                    },
                    onDismiss: { editingPlayer = nil }
                )
            } else if showQrScan {
                QrScanView(
                    onScanned: { payload, name in
                        let player = payload.toTournamentPlayer(name: name)
                        tournament.players.append(player)
                        persist()
                    },
                    onDismiss: { showQrScan = false }
                )
            } else {
                detailView
            }
        }
    }

    private var detailView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if tournament.players.isEmpty {
                    Spacer()
                    Text("No players yet. Tap + or scan a QR code.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    Spacer()
                } else {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            ScoreGridHeader(maxHole: maxHole)
                            Divider()
                            // Player rows
                            ForEach(sorted) { player in
                                ScoreGridRow(player: player, maxHole: maxHole)
                                    .background(player.source == .self ? Color.green.opacity(0.08) : Color.clear)
                                    .onLongPressGesture {
                                        longPressPlayer = player
                                        renameText = player.name
                                    }
                                Divider()
                            }
                        }
                    }
                    Spacer()
                }
            }
            .navigationTitle(tournament.title ?? tournament.courseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button { showQrScan = true } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                        Button { showAddManual = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .sheet(isPresented: $showAddManual) {
                AddPlayerSheet { name in
                    let blank = TournamentPlayer(name: name, holes: [], source: .manual)
                    tournament.players.append(blank)
                    persist()
                    editingPlayer = blank
                }
            }
            .confirmationDialog(longPressPlayer?.name ?? "", isPresented: Binding(
                get: { longPressPlayer != nil && !showRenameAlert && !showRemoveConfirm },
                set: { if !$0 && !showRenameAlert && !showRemoveConfirm { longPressPlayer = nil } }
            ), titleVisibility: .visible) {
                Button("Edit Scores") {
                    editingPlayer = longPressPlayer
                    longPressPlayer = nil
                }
                Button("Rename") { showRenameAlert = true }
                Button("Remove", role: .destructive) { showRemoveConfirm = true }
                Button("Cancel", role: .cancel) { longPressPlayer = nil }
            }
            .alert("Rename Player", isPresented: $showRenameAlert) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    guard let p = longPressPlayer, !renameText.isEmpty else { return }
                    tournament.players = tournament.players.map {
                        $0.id == p.id ? TournamentPlayer(id: $0.id, name: renameText, holes: $0.holes, source: $0.source) : $0
                    }
                    persist()
                    longPressPlayer = nil
                }
                Button("Cancel", role: .cancel) { longPressPlayer = nil }
            }
            .alert("Remove \(longPressPlayer?.name ?? "player")?", isPresented: $showRemoveConfirm) {
                Button("Remove", role: .destructive) {
                    guard let p = longPressPlayer else { return }
                    tournament.players.removeAll { $0.id == p.id }
                    persist()
                    longPressPlayer = nil
                }
                Button("Cancel", role: .cancel) { longPressPlayer = nil }
            }
        }
    }

    private var maxHole: Int {
        tournament.players.flatMap { $0.holes }.map { $0.number }.max() ?? 18
    }

    private func save(_ updated: TournamentPlayer) {
        tournament.players = tournament.players.map { $0.id == updated.id ? updated : $0 }
        persist()
    }

    private func persist() {
        try? TournamentStore().save(tournament)
    }
}

// MARK: - Score Grid

private struct ScoreGridHeader: View {
    let maxHole: Int
    private let nameW: CGFloat = 100
    private let cellW: CGFloat = 32
    private let totalW: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            Text("Player").font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                .frame(width: nameW, alignment: .leading).padding(.horizontal, 4)
            ForEach(1...maxHole, id: \.self) { n in
                Text("\(n)").font(.system(size: 10)).fontWeight(.bold).foregroundStyle(.secondary)
                    .frame(width: cellW)
            }
            Text("Tot").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).frame(width: totalW)
            Text("+/−").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).frame(width: totalW)
        }
        .padding(.vertical, 8)
    }
}

private struct ScoreGridRow: View {
    let player: TournamentPlayer
    let maxHole: Int
    private let nameW: CGFloat = 100
    private let cellW: CGFloat = 32
    private let totalW: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            Text(player.name)
                .font(.caption)
                .fontWeight(player.source == .self ? .bold : .regular)
                .lineLimit(1)
                .frame(width: nameW, alignment: .leading)
                .padding(.horizontal, 4)

            ForEach(1...maxHole, id: \.self) { n in
                let hole = player.holes.first { $0.number == n }
                ScoreCell(strokes: hole?.strokes ?? 0, par: hole?.par ?? 4)
                    .frame(width: cellW)
            }

            let total = player.totalStrokes
            Text(total > 0 ? "\(total)" : "—")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(diffColor(player.scoreVsPar, hasScore: total > 0))
                .frame(width: totalW)

            let diff = player.scoreVsPar
            Text(total == 0 ? "—" : diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(diffColor(diff, hasScore: total > 0))
                .frame(width: totalW)
        }
        .padding(.vertical, 6)
    }

    private func diffColor(_ diff: Int, hasScore: Bool) -> Color {
        guard hasScore else { return .secondary }
        if diff < 0 { return .green }
        if diff == 0 { return .primary }
        return .red
    }
}

private struct ScoreCell: View {
    let strokes: Int
    let par: Int

    private var diff: Int { strokes - par }
    private var bg: Color {
        guard strokes > 0 else { return .clear }
        if diff <= -2 { return .yellow.opacity(0.8) }
        if diff == -1 { return .green.opacity(0.7) }
        if diff == 1  { return .orange.opacity(0.6) }
        if diff >= 2  { return .red.opacity(0.7) }
        return .clear
    }
    private var fg: Color {
        guard strokes > 0 else { return .secondary }
        if diff <= -1 || diff >= 1 { return .white }
        return .primary
    }

    var body: some View {
        Text(strokes > 0 ? "\(strokes)" : "—")
            .font(.system(size: 11))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(bg)
    }
}

// MARK: - Edit Player Score

private struct EditPlayerScoreView: View {
    let player: TournamentPlayer
    let parReference: [HoleScore]
    let onSave: (TournamentPlayer) -> Void
    let onDismiss: () -> Void

    @State private var holes: [HoleScore]

    init(player: TournamentPlayer, parReference: [HoleScore], onSave: @escaping (TournamentPlayer) -> Void, onDismiss: @escaping () -> Void) {
        self.player = player
        self.parReference = parReference
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._holes = State(initialValue: (1...18).map { n in
            player.holes.first { $0.number == n }
                ?? parReference.first { $0.number == n }.map { HoleScore(number: n, par: $0.par, strokes: 0) }
                ?? HoleScore(number: n, par: 4, strokes: 0)
        })
    }

    private var total: Int { holes.reduce(0) { $0 + $1.strokes } }
    private var par: Int { holes.reduce(0) { $0 + $1.par } }
    private var diff: Int { total - par }

    var body: some View {
        NavigationStack {
            List {
                ForEach(holes.indices, id: \.self) { i in
                    HoleStepperRow(hole: $holes[i])
                }
                Section {
                    HStack {
                        Text("Total").fontWeight(.bold)
                        Spacer()
                        Text("\(total)").fontWeight(.bold)
                            .foregroundStyle(diff < 0 ? .green : diff == 0 ? .primary : .red)
                        Text(diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(diff < 0 ? .green : diff == 0 ? .primary : .red)
                    }
                }
            }
            .navigationTitle(player.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(TournamentPlayer(
                            id: player.id,
                            name: player.name,
                            holes: holes.filter { $0.strokes > 0 },
                            source: player.source
                        ))
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct HoleStepperRow: View {
    @Binding var hole: HoleScore

    private var diff: Int { hole.strokes > 0 ? hole.strokes - hole.par : Int.min }
    private var scoreColor: Color {
        guard hole.strokes > 0 else { return .secondary }
        if diff <= -2 { return .yellow }
        if diff == -1 { return .green }
        if diff == 0  { return .primary }
        if diff == 1  { return .orange }
        return .red
    }

    var body: some View {
        HStack {
            Text("H\(hole.number)").font(.subheadline).fontWeight(.semibold).frame(width: 36, alignment: .leading)
            Text("P\(hole.par)").font(.caption).foregroundStyle(.secondary).frame(width: 28)
            Spacer()
            Button { if hole.strokes > 0 { hole.strokes -= 1 } } label: {
                Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text(hole.strokes > 0 ? "\(hole.strokes)" : "—")
                .font(.subheadline).fontWeight(.bold)
                .foregroundStyle(scoreColor)
                .frame(width: 32, alignment: .center)
            Button { hole.strokes += 1 } label: {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Add Player Sheet

private struct AddPlayerSheet: View {
    let onAdd: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Player name", text: $name)
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(name.trimmingCharacters(in: .whitespaces)); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.bold)
                }
            }
        }
    }
}

// MARK: - QR Share (sender)

struct QrShareView: View {
    let round: Round
    @Environment(\.dismiss) var dismiss

    private var payload: String {
        let p = round.toQrPayload()
        return (try? String(data: JSONEncoder().encode(p), encoding: .utf8)) ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if let img = generateQR(payload) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                VStack(spacing: 4) {
                    Text(round.courseName).font(.subheadline).foregroundStyle(.secondary)
                    Text(round.startedAt.formatted(.iso8601.year().month().day()))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(round.totalStrokes) strokes")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                }
                Text("Have the tournament host scan this code")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 32)
            .navigationTitle("Share Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func generateQR(_ string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - QR Scan (receiver)

private struct QrScanView: View {
    let onScanned: (QrRoundPayload, String) -> Void
    let onDismiss: () -> Void

    @State private var scannedPayload: QrRoundPayload?
    @State private var playerName = ""
    @State private var showNameAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview { string in
                    guard scannedPayload == nil,
                          let data = string.data(using: .utf8),
                          let payload = try? JSONDecoder().decode(QrRoundPayload.self, from: data)
                    else { return }
                    scannedPayload = payload
                    showNameAlert = true
                }
                .ignoresSafeArea()
                VStack {
                    Spacer()
                    Text("Point camera at a GoBirdie QR code")
                        .font(.caption).foregroundStyle(.white)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Scan Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .alert("Player Name", isPresented: $showNameAlert, presenting: scannedPayload) { payload in
                TextField("Player name", text: $playerName)
                Button("Add Player") {
                    guard !playerName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onScanned(payload, playerName.trimmingCharacters(in: .whitespaces))
                    onDismiss()
                }
                Button("Re-scan", role: .cancel) { scannedPayload = nil; playerName = "" }
            } message: { payload in
                Text("\(payload.c)  ·  \(payload.d)\n\(payload.h.reduce(0) { $0 + ($1.first ?? 0) }) strokes")
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let onDecode: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return view }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = UIScreen.main.bounds
        view.layer.addSublayer(preview)
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        context.coordinator.session = session
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDecode: onDecode) }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onDecode: (String) -> Void
        var session: AVCaptureSession?
        var decoded = false

        init(onDecode: @escaping (String) -> Void) { self.onDecode = onDecode }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !decoded,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let string = obj.stringValue else { return }
            decoded = true
            onDecode(string)
        }
    }
}

// MARK: - QR payload → TournamentPlayer

private extension QrRoundPayload {
    func toTournamentPlayer(name: String) -> TournamentPlayer {
        let holes = h.enumerated().map { idx, scores in
            HoleScore(number: idx + 1, par: 4, strokes: scores.first ?? 0, putts: scores.dropFirst().first ?? 0)
        }
        return TournamentPlayer(id: UUID().uuidString, name: name, holes: holes, source: .received)
    }
}
