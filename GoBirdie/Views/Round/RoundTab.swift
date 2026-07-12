//
//  RoundTab.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore
import CryptoKit

struct RoundTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showStartRoundSheet = false
    @State private var showMenu = false

    var body: some View {
        if let session = appState.activeRound,
           let viewModel = appState.activeRoundViewModel {
            ActiveRoundView(
                session: session,
                viewModel: viewModel,
                appState: appState,
                showMenu: $showMenu
            )
        } else if let snapshot = appState.pendingResume {
            ResumeRoundView(snapshot: snapshot, appState: appState)
        } else {
            EmptyRoundStateView(onStartRound: { showStartRoundSheet = true })
                .sheet(isPresented: $showStartRoundSheet) { StartRoundView() }
        }
    }
}

// Separate view so @ObservedObject works correctly
private struct ActiveRoundView: View {
    @ObservedObject var session: RoundSession
    @ObservedObject var viewModel: RoundViewModel
    @ObservedObject var appState: AppState
    @Binding var showMenu: Bool
    @State private var showEndConfirm = false
    @State private var showMoveShotsSheet = false
    @State private var showTournamentSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row with menu button
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hole \(session.currentHoleNumber)")
                    .font(.title3).fontWeight(.bold)
                    .accessibilityIdentifier("holeLabel")

                if let hole = session.currentHole,
                   let courseHole = viewModel.course.holes.first(where: { $0.number == session.currentHoleNumber }) {
                    let ydsText = courseHole.yardage.map { "\($0) yds" } ?? ""
                    Text("Par \(hole.par)" + (ydsText.isEmpty ? "" : "  ·  \(ydsText)"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()

                Menu {
                    if (session.currentHole?.shots.count ?? 0) > 0 {
                        Button {
                            showMoveShotsSheet = true
                        } label: {
                            Label("Move Shots to Hole...", systemImage: "arrow.triangle.swap")
                        }
                        Divider()
                    }
                    Button {
                        syncWatch()
                    } label: {
                        Label("Sync Watch", systemImage: "applewatch")
                    }
                    Button {
                        showTournamentSheet = true
                    } label: {
                        Label("Create Tournament", systemImage: "trophy")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showEndConfirm = true
                    } label: {
                        Label("End Round", systemImage: "flag.checkered")
                    }
                    .accessibilityIdentifier("endRoundMenu")
                    Button(role: .destructive) {
                        appState.cancelActiveRound()
                    } label: {
                        Label("Cancel Round", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("roundMenu")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            DistanceDisplayView(
                distances: viewModel.distances,
                hasGpsLock: appState.getLocationService().hasReceivedLocation
            )
            .padding(.horizontal, 16)

            HoleControlsView(
                session: session,
                course: viewModel.course,
                locationService: appState.getLocationService(),
                viewModel: viewModel
            )
            .padding(.top, 4)

            MiniScorecardView(session: session)
                .padding(.top, 4)
        }
        .alert("End Round?", isPresented: $showEndConfirm) {
            Button("End", role: .destructive) {
                session.endRound()
                appState.endActiveRound()
            }
            .accessibilityIdentifier("confirmEndRound")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save and finish this round?")
        }
        .alert("Are you still playing?", isPresented: $appState.showIdlePrompt) {
            Button("Yes, still playing") {
                appState.resetIdleTimer()
            }
            Button("End Round", role: .destructive) {
                session.endRound()
                appState.endActiveRound()
            }
        } message: {
            Text("No activity for 30 minutes.")
        }
        .alert("Move to Hole \(appState.teeDetectionHole ?? 0)?", isPresented: Binding(
            get: { appState.teeDetectionHole != nil },
            set: { if !$0 { appState.teeDetectionHole = nil } }
        )) {
            if let hole = appState.teeDetectionHole {
                Button("Move to Hole \(hole)") { appState.confirmTeeDetection(holeNumber: hole) }
                Button("Stay", role: .cancel) { appState.dismissTeeDetection(holeNumber: hole) }
            }
        } message: {
            if let hole = appState.teeDetectionHole {
                Text("You're near the Hole \(hole) tee box.")
            }
        }
        .sheet(isPresented: $showMoveShotsSheet) {
            MoveShotsSheet(session: session, course: viewModel.course)
        }
        .sheet(isPresented: $showTournamentSheet) {
            CreateTournamentFromRoundSheet(
                round: session.round,
                course: viewModel.course,
                appState: appState,
                onDismiss: { showTournamentSheet = false }
            )
        }
        .overlay {
            if appState.isSavingRound {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Saving round...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                }
            }
        }
    }

    private func syncWatch() {
        let course = viewModel.course
        let holeNumber = session.currentHoleNumber
        guard let hole = course.holes.first(where: { $0.number == holeNumber }) else { return }
        let courseHash = computeCourseHash(course: course)
        ConnectivityService.shared.sendRoundStartContext(versionHash: courseHash, courseId: course.id)
        ConnectivityService.shared.sendHoleData(
            hole: hole,
            holeNumber: holeNumber,
            courseName: course.name,
            totalStrokes: session.round.totalStrokes,
            totalHoles: course.holes.count,
            strokes: session.currentHole?.strokes ?? 0,
            putts: session.currentHole?.putts ?? 0
        )
        Task.detached(priority: .userInitiated) {
            await WatchSnapshotTransferManager.shared.transferAllHoles(
                for: course,
                courseId: course.id,
                versionHash: courseHash
            )
        }
    }

    private func computeCourseHash(course: Course) -> String {
        let coordStrings = course.holes.compactMap { hole in
            guard let tee = hole.tee, let green = hole.greenCenter else { return nil }
            return "\(tee.lat),\(tee.lon),\(green.lat),\(green.lon)"
        }.joined(separator: "|")

        let data = Data(coordStrings.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct EmptyRoundStateView: View {
    var onStartRound: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "flag.fill")
                .font(.system(size: 56)).foregroundStyle(.green)
            Text("No Active Round").font(.title2).fontWeight(.bold)
            Text("Start a round to track distances\nand mark your shots")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onStartRound) {
                Label("Start Round", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .accessibilityIdentifier("startRoundButton")
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Move Shots Sheet

private struct MoveShotsSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var session: RoundSession
    let course: Course

    var body: some View {
        NavigationStack {
            let currentNum = session.currentHoleNumber
            let shotCount = session.currentHole?.shots.count ?? 0
            List {
                Section {
                    ForEach(session.round.holes, id: \.id) { hole in
                        if hole.number != currentNum {
                            Button {
                                session.moveShotsToHole(hole.number)
                                dismiss()
                            } label: {
                                HStack {
                                    Text("Hole \(hole.number)")
                                    Text("Par \(hole.par)").foregroundStyle(.secondary)
                                    Spacer()
                                    if hole.strokes > 0 {
                                        Text("\(hole.strokes) strokes").foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Move \(shotCount) shot\(shotCount == 1 ? "" : "s") from Hole \(currentNum) to:")
                }
            }
            .navigationTitle("Move Shots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct ResumeRoundView: View {
    let snapshot: InProgressSnapshot
    let appState: AppState

    private var elapsed: String {
        let mins = Int(Date().timeIntervalSince(snapshot.round.startedAt) / 60)
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h \(mins % 60)m ago"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.orange)

            Text("Round In Progress").font(.title2).fontWeight(.bold)

            VStack(spacing: 6) {
                Text(snapshot.round.courseName)
                    .font(.headline)
                Text("Hole \(snapshot.currentHoleIndex + 1)  ·  Started \(elapsed)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if snapshot.round.totalStrokes > 0 {
                    Text("\(snapshot.round.totalStrokes) strokes")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                appState.resumeRound(snapshot: snapshot)
            } label: {
                Label("Resume Round", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)

            Button {
                appState.discardInProgressRound()
            } label: {
                Text("Discard")
                    .foregroundStyle(.red)
            }
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Create Tournament from Round Sheet

private struct CreateTournamentFromRoundSheet: View {
    let round: Round
    let course: Course
    @ObservedObject var appState: AppState
    let onDismiss: () -> Void

    @State private var title = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tournament") {
                    TextField("Title (optional)", text: $title)
                }

                Section("Round") {
                    Text(round.courseName).foregroundStyle(.secondary)
                    Text(round.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(round.totalStrokes) strokes")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTournament() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func createTournament() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: round.startedAt)

        let tournament = Tournament(
            title: title.isEmpty ? nil : title,
            courseId: round.courseId,
            courseName: round.courseName,
            date: date,
            players: [TournamentPlayer(name: "Me", holes: round.holes, source: .self)]
        )

        try? TournamentStore().save(tournament)
        onDismiss()
    }
}
