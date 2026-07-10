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
    @State private var renamingTournament: Tournament?
    @State private var renameText = ""

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
                            .contextMenu {
                                Button { renamingTournament = tournament; renameText = tournament.title ?? tournament.courseName } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) { delete(tournament) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .alert("Rename Tournament", isPresented: Binding(
                        get: { renamingTournament != nil },
                        set: { if !$0 { renamingTournament = nil } }
                    )) {
                        TextField("Name", text: $renameText)
                        Button("Save") {
                            guard let t = renamingTournament, !renameText.isEmpty else { return }
                            var updated = t
                            updated.title = renameText
                            try? TournamentStore().save(updated)
                            load()
                            renamingTournament = nil
                        }
                        Button("Cancel", role: .cancel) { renamingTournament = nil }
                    }
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

    @EnvironmentObject private var appState: AppState
    @State private var showAddManual = false
    @State private var longPressPlayer: TournamentPlayer?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var editingCell: (playerId: String, hole: Int)?
    @State private var editingStrokeText = ""

    init(tournament: Tournament, onDismiss: @escaping () -> Void) {
        self._tournament = State(initialValue: tournament)
        self.onDismiss = onDismiss
    }

    private var isLiveRoundActive: Bool {
        guard let session = appState.activeRound else { return false }
        return session.round.courseId == tournament.courseId
    }


    var body: some View {
        detailView
    }

    private var detailView: some View {
        NavigationStack {
            detailContent
                .navigationTitle(tournament.title ?? tournament.courseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { detailToolbar }
                .sheet(isPresented: $showAddManual) {
                    AddPlayerSheet(
                        onAdd: { name in
                            let blank = TournamentPlayer(name: name, holes: [], source: .manual)
                            tournament.players.append(blank)
                            persist()
                        },
                        onScanned: { payload, name in
                            let player = payload.toTournamentPlayer(name: name)
                            tournament.players.append(player)
                            persist()
                        }
                    )
                }
                .modifier(LiveScoreUpdater(tournament: $tournament, isLive: isLiveRoundActive, activeHoles: appState.activeRound?.round.holes, persist: persist))
                .modifier(PlayerEditDialogs(
                    longPressPlayer: $longPressPlayer,
                    showRenameAlert: $showRenameAlert,
                    renameText: $renameText,
                    onRename: { p, name in
                        tournament.players = tournament.players.map {
                            $0.id == p.id ? TournamentPlayer(id: $0.id, name: name, holes: $0.holes, source: $0.source) : $0
                        }
                        persist()
                    }
                ))
                .sheet(isPresented: Binding(
                    get: { editingCell != nil },
                    set: { if !$0 { editingCell = nil } }
                )) {
                    if let cell = editingCell {
                        StrokePickerSheet(current: editingStrokeText) { val in
                            guard let pIdx = tournament.players.firstIndex(where: { $0.id == cell.playerId })
                            else { editingCell = nil; return }
                            if let hIdx = tournament.players[pIdx].holes.firstIndex(where: { $0.number == cell.hole }) {
                                tournament.players[pIdx].holes[hIdx].strokes = val
                            } else {
                                let par = tournament.players.first(where: { $0.source == .self })?.holes.first(where: { $0.number == cell.hole })?.par ?? 4
                                tournament.players[pIdx].holes.append(HoleScore(number: cell.hole, par: par, strokes: val))
                            }
                            persist()
                            editingCell = nil
                        }
                    }
                }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            if tournament.players.isEmpty {
                Spacer()
                Text("No players yet. Tap + or scan a QR code.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Spacer()
            } else {
                ScoreGrid(
                    players: tournament.players,
                    onLongPress: { player in
                        longPressPlayer = player
                        renameText = player.name
                        showRenameAlert = true
                    },
                    onTapCell: { playerId, hole in
                        editingStrokeText = ""
                        if let p = tournament.players.first(where: { $0.id == playerId }),
                           let h = p.holes.first(where: { $0.number == hole }) {
                            editingStrokeText = h.strokes > 0 ? "\(h.strokes)" : ""
                        }
                        editingCell = (playerId, hole)
                    }
                )
                Spacer()
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack {
                Button { showAddManual = true } label: { Image(systemName: "plus") }
                if isLiveRoundActive {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { onDismiss() }
        }
    }

private func save(_ updated: TournamentPlayer) {
        tournament.players = tournament.players.map { $0.id == updated.id ? updated : $0 }
        persist()
    }

    private func persist() {
        try? TournamentStore().save(tournament)
    }
}

// MARK: - Stroke Picker Sheet

private struct StrokePickerSheet: View {
    let current: String
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let cur = Int(current)
        VStack(spacing: 16) {
            Text("Strokes")
                .font(.headline)
                .padding(.top, 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(1...10, id: \.self) { n in
                    Button {
                        onSelect(n)
                        dismiss()
                    } label: {
                        Text("\(n)")
                            .font(.title3).fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(cur == n ? Color.accentColor : Color(.systemGray5))
                            .foregroundStyle(cur == n ? Color.white : Color.primary)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 24)
            Button("Clear") {
                onSelect(0)
                dismiss()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(280)])
    }
}

// MARK: - ViewModifiers extracted to help Swift type-checker

private struct LiveScoreUpdater: ViewModifier {
    @Binding var tournament: Tournament
    let isLive: Bool
    let activeHoles: [HoleScore]?
    let persist: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .watchStrokeUpdate)) { notification in
                guard isLive,
                      let holeNumber = notification.userInfo?["holeNumber"] as? Int,
                      let strokes = notification.userInfo?["strokes"] as? Int,
                      let idx = tournament.players.firstIndex(where: { $0.source == .self }),
                      let holeIdx = tournament.players[idx].holes.firstIndex(where: { $0.number == holeNumber })
                else { return }
                tournament.players[idx].holes[holeIdx].strokes = strokes
                if let putts = notification.userInfo?["putts"] as? Int {
                    tournament.players[idx].holes[holeIdx].putts = putts
                }
                persist()
            }
            .onChange(of: activeHoles) { holes in
                guard isLive, let holes else { return }
                guard let idx = tournament.players.firstIndex(where: { $0.source == .self }) else { return }
                tournament.players[idx].holes = holes.filter { $0.strokes > 0 }
                persist()
            }
    }
}

private struct PlayerEditDialogs: ViewModifier {
    @Binding var longPressPlayer: TournamentPlayer?
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    let onRename: (TournamentPlayer, String) -> Void

    func body(content: Content) -> some View {
        content
            .alert("Rename Player", isPresented: $showRenameAlert) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    guard let p = longPressPlayer, !renameText.isEmpty else { return }
                    onRename(p, renameText)
                    longPressPlayer = nil
                }
                Button("Cancel", role: .cancel) { longPressPlayer = nil }
            }
    }
}

// MARK: - Score Grid (transposed: rows = holes, columns = players)

private struct ScoreGrid: View {
    let players: [TournamentPlayer]
    let onLongPress: (TournamentPlayer) -> Void
    let onTapCell: (String, Int) -> Void  // (playerId, holeNumber)
    private let labelW: CGFloat = 44
    private let cellW: CGFloat = 60

    private var playedHoles: [Int] {
        let scored = Set(players.flatMap { $0.holes }.filter { $0.strokes > 0 }.map { $0.number })
        return scored.sorted()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // Header row: blank label + player names (long-press to edit)
                HStack(spacing: 0) {
                    Text("").frame(width: labelW)
                    ForEach(players) { player in
                        Text(player.name)
                            .font(.subheadline).fontWeight(player.source == .self ? .bold : .regular)
                            .lineLimit(1)
                            .frame(width: cellW)
                            .foregroundStyle(player.source == .self ? Color.green : Color.primary)
                            .onLongPressGesture { onLongPress(player) }
                    }
                }
                .padding(.vertical, 8)
                Divider()

                // One row per played hole
                ForEach(playedHoles, id: \.self) { n in
                    HStack(spacing: 0) {
                        Text("H\(n)")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                            .frame(width: labelW)
                        ForEach(players) { player in
                            let hole = player.holes.first { $0.number == n }
                            ScoreCell(strokes: hole?.strokes ?? 0, par: hole?.par ?? 4)
                                .frame(width: cellW)
                                .onTapGesture { onTapCell(player.id, n) }
                        }
                    }
                    Divider()
                }

                // Total row
                HStack(spacing: 0) {
                    Text("Tot")
                        .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                        .frame(width: labelW)
                    ForEach(players) { player in
                        let total = player.totalStrokes
                        Text(total > 0 ? "\(total)" : "—")
                            .font(.subheadline).fontWeight(.bold)
                            .frame(width: cellW)
                    }
                }
                .padding(.vertical, 6)
                Divider()

                // +/− row
                HStack(spacing: 0) {
                    Text("+/−")
                        .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                        .frame(width: labelW)
                    ForEach(players) { player in
                        let total = player.totalStrokes
                        let diff = player.scoreVsPar
                        let label = total == 0 ? "—" : diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)"
                        let color: Color = total == 0 ? .secondary : diff < 0 ? .green : diff == 0 ? .primary : .red
                        Text(label)
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(color)
                            .frame(width: cellW)
                    }
                }
                .padding(.vertical, 6)
            }
        }
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
            .font(.subheadline).fontWeight(.bold)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(bg)
    }
}

// MARK: - Edit Tournament Sheet

private struct EditTournamentSheet: View {
    let tournament: Tournament
    let onSave: (Tournament) -> Void
    @State private var title: String
    @State private var date: String
    @Environment(\.dismiss) var dismiss

    init(tournament: Tournament, onSave: @escaping (Tournament) -> Void) {
        self.tournament = tournament
        self.onSave = onSave
        self._title = State(initialValue: tournament.title ?? "")
        self._date = State(initialValue: tournament.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    Text(tournament.courseName).foregroundStyle(.secondary)
                }
                Section {
                    TextField("Date (yyyy-MM-dd)", text: $date)
                    TextField("Title (optional)", text: $title)
                }
            }
            .navigationTitle("Edit Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = tournament
                        updated.title = title.isEmpty ? nil : title
                        updated.date = date
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(date.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Player Sheet

private struct AddPlayerSheet: View {
    let onAdd: (String) -> Void
    let onScanned: (QrRoundPayload, String) -> Void
    @State private var name = ""
    @State private var showQrScan = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        if showQrScan {
            QrScanView(
                playerName: name.trimmingCharacters(in: .whitespaces),
                onScanned: { payload, playerName in
                    onScanned(payload, playerName)
                    dismiss()
                },
                onDismiss: { showQrScan = false }
            )
        } else {
            NavigationStack {
                Form {
                    TextField("Player name", text: $name)
                    Button { showQrScan = true } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
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
    var playerName: String = ""
    let onScanned: (QrRoundPayload, String) -> Void
    let onDismiss: () -> Void

    @State private var scannedPayload: QrRoundPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview { string in
                    guard scannedPayload == nil,
                          let data = string.data(using: .utf8),
                          let payload = try? JSONDecoder().decode(QrRoundPayload.self, from: data)
                    else { return }
                    scannedPayload = payload
                    onScanned(payload, playerName.isEmpty ? payload.c : playerName)
                    onDismiss()
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
